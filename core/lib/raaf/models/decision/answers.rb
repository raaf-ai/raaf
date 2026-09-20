# frozen_string_literal: true

require_relative "../../errors"

module RAAF

  module Models

    module Decision

      ##
      # Raised when a provider's answer cannot be read as the expected type
      #
      class MalformedAnswerError < RAAF::Error; end

      ##
      # Typed answers returned by a decision model
      #
      # Every answer keeps the provider's raw body in {Base#raw} so callers can
      # reach vendor-specific extras without the interface having to model them.
      #
      module Answers

        ##
        # Base class for decision answers
        #
        # @abstract
        #
        class Base

          # @return [Decision::Question] The question this answers
          attr_reader :question

          # @return [Hash] The provider's raw answer body
          attr_reader :raw

          ##
          # @param question [Decision::Question] The question being answered
          # @param raw [Hash] The provider's answer body for that question
          #
          def initialize(question:, raw:)
            @question = question
            @raw = raw.is_a?(Hash) ? raw : {}
            parse!
          end

          ##
          # How sure the model is, from 0.0 to 1.0
          #
          # @return [Float]
          #
          attr_reader :confidence

          ##
          # @return [Hash] The answer as a plain Hash
          #
          def to_h
            { type: question.type, confidence: confidence }
          end

          private

          ##
          # Reads the answer out of {#raw}
          #
          # @return [void]
          # @raise [NotImplementedError] Unless overridden
          #
          def parse!
            raise NotImplementedError, "#{self.class} must implement #parse!"
          end

          ##
          # Reads the first key present, trying both String and Symbol forms
          #
          # @param keys [Array<String, Symbol>] Keys to try, in order
          # @return [Object, nil] The value, or nil if no key is present
          #
          def value_for(*keys)
            keys.each do |key|
              return raw[key.to_s] if raw.key?(key.to_s)
              return raw[key.to_sym] if raw.key?(key.to_sym)
            end
            nil
          end

          ##
          # Coerces a value to a probability
          #
          # @param value [Object] The raw value
          # @param field [String] Field name, for the error message
          # @return [Float] A value between 0.0 and 1.0
          # @raise [MalformedAnswerError] If the value is missing or out of range
          #
          def probability!(value, field)
            raise MalformedAnswerError, "#{question.type} answer is missing #{field}" if value.nil?

            float = Float(value)
            unless float.between?(0.0, 1.0)
              raise MalformedAnswerError,
                    "#{question.type} answer #{field} must be between 0 and 1, got #{float}"
            end

            float
          rescue ::ArgumentError, ::TypeError
            raise MalformedAnswerError, "#{question.type} answer #{field} is not a number: #{value.inspect}"
          end

          ##
          # Coerces a Hash of name => probability
          #
          # @param value [Object] The raw distribution
          # @return [Hash{String => Float}] Empty when the provider sends none
          #
          def distribution_for(value)
            return {} unless value.is_a?(Hash)

            value.each_with_object({}) do |(key, probability), result|
              result[key.to_s] = Float(probability)
            rescue ::ArgumentError, ::TypeError
              next
            end
          end

        end

        ##
        # The answer to a {Decision::Noul}: a calibrated probability
        #
        class Noul < Base

          # @return [Float] Probability that the statement holds, 0.0 to 1.0
          attr_reader :probability

          ##
          # Whether the statement holds at the given threshold
          #
          # @param threshold [Float] Decision threshold (default: 0.5)
          # @return [Boolean]
          #
          def true?(threshold: 0.5)
            probability >= threshold
          end

          def to_h
            super.merge(probability: probability)
          end

          private

          def parse!
            @probability = probability!(value_for(:noul, :probability, :value), "noul")

            # Vendors that report a separate confidence win; otherwise distance
            # from the coin flip is the only confidence signal a noul carries.
            supplied = value_for(:confidence)
            @confidence = supplied.nil? ? ((@probability - 0.5).abs * 2) : probability!(supplied, "confidence")
          end

        end

        ##
        # The answer to a {Decision::Choice}: one option plus its distribution
        #
        class Choice < Base

          # @return [String] The selected option
          attr_reader :option

          # @return [Hash{String => Float}] Probability per option
          attr_reader :probabilities

          def to_h
            super.merge(option: option, probabilities: probabilities)
          end

          private

          def parse!
            @probabilities = distribution_for(value_for(:probabilities, :distribution, :options))
            @option = resolve_option

            unless question.options.include?(@option)
              raise MalformedAnswerError,
                    "choice answer #{@option.inspect} is not one of #{question.options.inspect}"
            end

            supplied = value_for(:confidence)
            @confidence = supplied.nil? ? (@probabilities[@option] || 0.0) : probability!(supplied, "confidence")
          end

          ##
          # The selected option, falling back to the most probable one
          #
          # @return [String]
          # @raise [MalformedAnswerError] If neither a choice nor probabilities are present
          #
          def resolve_option
            selected = value_for(:choice, :option, :value, :selected)
            return selected.to_s unless selected.nil?

            best = @probabilities.max_by { |_option, probability| probability }
            raise MalformedAnswerError, "choice answer is missing choice" if best.nil?

            best.first
          end

        end

        ##
        # The answer to a {Decision::Score}: a place on the rubric
        #
        class Score < Base

          # @return [Float] The continuous score across the rubric
          attr_reader :score

          # @return [String] The level the score lands on
          attr_reader :level

          # @return [Hash{String => Float}] Probability per level
          attr_reader :distribution

          def to_h
            super.merge(score: score, level: level, distribution: distribution)
          end

          private

          def parse!
            raw_score = value_for(:score, :value)
            raise MalformedAnswerError, "score answer is missing score" if raw_score.nil?

            begin
              @score = Float(raw_score)
            rescue ::ArgumentError, ::TypeError
              raise MalformedAnswerError, "score answer score is not a number: #{raw_score.inspect}"
            end

            @distribution = distribution_for(value_for(:distribution, :probabilities, :levels))
            @level = resolve_level

            supplied = value_for(:confidence)
            @confidence = supplied.nil? ? (@distribution[@level] || 0.0) : probability!(supplied, "confidence")
          end

          ##
          # The level for this score
          #
          # Uses the provider's own label when it sends one, then the most
          # probable level, and finally the score rounded onto the rubric.
          #
          # @return [String]
          #
          def resolve_level
            supplied = value_for(:level, :label)
            return supplied.to_s unless supplied.nil?

            best = @distribution.max_by { |_level, probability| probability }
            return best.first unless best.nil?

            index = @score.round.clamp(0, question.levels.size - 1)
            question.levels[index]
          end

        end

      end

      ##
      # Every answer from one call to a decision model
      #
      # Answers are looked up by the name the question was given, with either a
      # String or a Symbol.
      #
      # @example
      #   result = provider.decide(state: ticket, questions: { urgent: ..., team: ... })
      #   result[:urgent].probability  # => 0.999
      #   result["team"].option        # => "billing"
      #
      class Result

        include Enumerable

        # @return [Hash{String => Answers::Base}] Answers by question name
        attr_reader :answers

        # @return [String, nil] The model that answered
        attr_reader :model

        # @return [String, nil] The provider that answered
        attr_reader :provider

        # @return [Hash] The provider's raw response body
        attr_reader :raw

        # @return [Hash, nil] Token usage, when the provider reports it
        attr_reader :usage

        ##
        # @param answers [Hash] Answers keyed by question name
        # @param model [String, nil] The model that answered
        # @param provider [String, nil] The provider that answered
        # @param raw [Hash] The provider's raw response body
        # @param usage [Hash, nil] Token usage, when reported
        #
        def initialize(answers:, model: nil, provider: nil, raw: {}, usage: nil)
          @answers = answers.each_with_object({}) { |(name, answer), result| result[name.to_s] = answer }
          @model = model
          @provider = provider
          @raw = raw
          @usage = usage
        end

        ##
        # Looks up one answer
        #
        # @param name [String, Symbol] The question name
        # @return [Answers::Base, nil]
        #
        def [](name)
          answers[name.to_s]
        end

        ##
        # Looks up one answer, raising when it is absent
        #
        # @param name [String, Symbol] The question name
        # @return [Answers::Base]
        # @raise [KeyError] If no question by that name was answered
        #
        def fetch(name)
          answers.fetch(name.to_s)
        end

        ##
        # @yield [name, answer] Each answer with its question name
        #
        def each(&)
          answers.each(&)
        end

        ##
        # @return [Array<String>] The answered question names
        #
        def names
          answers.keys
        end

        ##
        # @return [Hash] The answers as plain Hashes, keyed by question name
        #
        def to_h
          answers.transform_values(&:to_h)
        end

      end

    end

  end

end

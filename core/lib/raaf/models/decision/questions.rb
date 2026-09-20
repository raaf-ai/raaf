# frozen_string_literal: true

module RAAF

  module Models

    ##
    # Decision models ("System One" models)
    #
    # A decision model answers typed questions about a piece of state and
    # returns probabilities instead of text. It is a different shape of model
    # from the chat LLMs behind {RAAF::Models::ModelInterface}: there are no
    # messages, no tool calls, no streaming and no generated prose.
    #
    # The three question primitives below are the ones the current vendors
    # (TypeSafe Jev, Laya) agree on, so they are what RAAF abstracts over.
    #
    module Decision

      ##
      # Base class for the question types a decision model can answer
      #
      # A question carries the instructions describing what to decide. The
      # state it is asked about is supplied separately, once per request, so
      # several questions can share one state.
      #
      # @abstract Use {Noul}, {Choice} or {Score}
      #
      class Question

        # @return [String] What the model should decide
        attr_reader :instructions

        ##
        # @param instructions [String] What the model should decide
        # @raise [ArgumentError] If instructions are missing or blank
        #
        def initialize(instructions:)
          raise ArgumentError, "instructions must be a non-empty String" if instructions.nil? || instructions.to_s.strip.empty?

          @instructions = instructions.to_s
        end

        ##
        # The wire type name for this question
        #
        # @return [String]
        # @raise [NotImplementedError] Unless overridden
        #
        def type
          raise NotImplementedError, "#{self.class} must implement #type"
        end

        ##
        # The question as a request fragment
        #
        # @return [Hash] Question body to send to the provider
        #
        def to_request
          { type: type, instructions: instructions }
        end

        ##
        # Builds an answer object from a provider's raw answer for this question
        #
        # @param raw [Hash] The provider's answer body for this question
        # @return [Decision::Answers::Base]
        # @raise [NotImplementedError] Unless overridden
        #
        def parse(raw)
          raise NotImplementedError, "#{self.class} must implement #parse"
        end

        ##
        # Builds a question from a Hash, passing Question instances through
        #
        # This accepts the same shape as the wire format, so callers can write
        # questions inline without naming the classes.
        #
        # @param value [Question, Hash] The question, or its Hash form
        # @return [Question]
        # @raise [ArgumentError] If the type is unknown or the value is not a Hash
        #
        # @example
        #   Question.build(type: :noul, instructions: "Is this urgent?")
        #
        def self.build(value)
          return value if value.is_a?(Question)
          raise ArgumentError, "question must be a Question or Hash, got #{value.class}" unless value.is_a?(Hash)

          attrs = value.transform_keys { |key| key.to_s.downcase }
          type = attrs.delete("type").to_s.downcase
          kwargs = attrs.transform_keys(&:to_sym)

          case type
          when "noul" then Noul.new(**kwargs)
          when "choice" then Choice.new(**kwargs)
          when "score" then Score.new(**kwargs)
          else
            raise ArgumentError, "unknown question type: #{type.inspect} (expected noul, choice or score)"
          end
        end

      end

      ##
      # A calibrated yes or no
      #
      # The answer is the probability that the statement in the instructions
      # holds for the state.
      #
      # @example
      #   Noul.new(instructions: "The message conveys urgency")
      #
      class Noul < Question

        def type
          "noul"
        end

        def parse(raw)
          Answers::Noul.new(question: self, raw: raw)
        end

      end

      ##
      # One option out of a set
      #
      # The answer carries the selected option, a probability per option and an
      # overall confidence.
      #
      # @example
      #   Choice.new(
      #     instructions: "Which team should handle this ticket?",
      #     options: %w[billing engineering success]
      #   )
      #
      class Choice < Question

        # @return [Array<String>] The options the model picks from
        attr_reader :options

        ##
        # @param instructions [String] What the model should decide
        # @param options [Array<String>] Two or more distinct options
        # @raise [ArgumentError] If fewer than two distinct options are given
        #
        def initialize(instructions:, options:)
          super(instructions: instructions)

          @options = Array(options).map(&:to_s)
          raise ArgumentError, "choice needs at least 2 options" if @options.size < 2
          raise ArgumentError, "choice options must be distinct" if @options.uniq.size != @options.size
        end

        def type
          "choice"
        end

        def to_request
          super.merge(options: options)
        end

        def parse(raw)
          Answers::Choice.new(question: self, raw: raw)
        end

      end

      ##
      # A place on an ordered rubric
      #
      # The answer carries a continuous score, the level it lands on, the
      # distribution across levels and a confidence.
      #
      # @example
      #   Score.new(
      #     instructions: "How severe is this incident?",
      #     levels: %w[low medium high critical]
      #   )
      #
      class Score < Question

        # @return [Array<String>] The rubric levels, lowest first
        attr_reader :levels

        ##
        # @param instructions [String] What the model should decide
        # @param levels [Array<String>] Two or more ordered levels, lowest first
        # @raise [ArgumentError] If fewer than two distinct levels are given
        #
        def initialize(instructions:, levels:)
          super(instructions: instructions)

          @levels = Array(levels).map(&:to_s)
          raise ArgumentError, "score needs at least 2 levels" if @levels.size < 2
          raise ArgumentError, "score levels must be distinct" if @levels.uniq.size != @levels.size
        end

        def type
          "score"
        end

        def to_request
          super.merge(levels: levels)
        end

        def parse(raw)
          Answers::Score.new(question: self, raw: raw)
        end

      end

    end

  end

end

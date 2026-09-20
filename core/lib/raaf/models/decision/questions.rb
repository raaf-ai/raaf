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
    # Their wire shapes follow TypeSafe's SDKs.
    #
    module Decision

      ##
      # Base class for the question types a decision model can answer
      #
      # A question carries +instructions+ (what to decide, in a sentence) and
      # +criteria+ (the structure the answer must take). Both are optional for
      # a {Noul}; {Choice} and {Score} need criteria, since that is where their
      # options and levels live. The state a question is asked about is
      # supplied separately, once per request, so several questions can share
      # one state.
      #
      # @abstract Use {Noul}, {Choice} or {Score}
      #
      class Question

        # @return [String, nil] What the model should decide
        attr_reader :instructions

        # @return [Hash, Array, nil] The structure the answer must take
        attr_reader :criteria

        # @return [Hash] Extra request fields passed through untouched
        attr_reader :extra

        ##
        # @param instructions [String, nil] What the model should decide
        # @param criteria [Hash, Array, nil] The structure the answer must take
        # @param extra [Hash] Extra fields to send with the question, for API
        #   fields RAAF does not model yet
        #
        def initialize(instructions: nil, criteria: nil, extra: {})
          @instructions = instructions&.to_s
          @criteria = criteria
          @extra = stringify(extra || {})
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
          request = { "type" => type }
          request["instructions"] = instructions unless instructions.nil?
          request["criteria"] = criteria_request unless criteria.nil?
          request.merge(extra)
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
        # questions inline. Keys RAAF does not know are kept and sent as they
        # are, so a field the API ships before RAAF models it still reaches it.
        #
        # @param value [Question, Hash] The question, or its Hash form
        # @return [Question]
        # @raise [ArgumentError] If the type is unknown or the value is not a Hash
        #
        # @example
        #   Question.build(type: :noul, instructions: "Is this urgent?")
        #
        # @example Sending a field RAAF does not model
        #   Question.build(type: :noul, instructions: "Is this urgent?", weight: 2)
        #
        def self.build(value)
          return value if value.is_a?(Question)
          raise ArgumentError, "question must be a Question or Hash, got #{value.class}" unless value.is_a?(Hash)

          attrs = value.to_h { |key, item| [key.to_s.downcase, item] }
          type = attrs.delete("type").to_s.downcase
          instructions = attrs.delete("instructions")
          criteria = attrs.delete("criteria")

          klass = TYPES[type]
          raise ArgumentError, "unknown question type: #{type.inspect} (expected noul, choice or score)" unless klass

          klass.new(instructions: instructions, criteria: criteria, extra: attrs)
        end

        private

        ##
        # The criteria as a request fragment
        #
        # @return [Hash, Array]
        #
        def criteria_request
          criteria
        end

        ##
        # @param hash [Hash] A Hash with Symbol or String keys
        # @return [Hash] The same Hash with String keys
        #
        def stringify(hash)
          hash.to_h { |key, value| [key.to_s, value] }
        end

      end

      ##
      # A calibrated yes or no
      #
      # The answer is the probability that the statement holds for the state.
      # Criteria, when given, describe what a true and a false answer mean.
      #
      # @example
      #   Noul.new(instructions: "The message conveys urgency")
      #
      # @example With criteria
      #   Noul.new(
      #     instructions: "Is this message spam?",
      #     criteria: { "true" => "Unsolicited advertising", "false" => "A real conversation" }
      #   )
      #
      class Noul < Question

        ##
        # @param instructions [String, nil] The statement to assess
        # @param criteria [Hash, nil] Descriptions of a true and a false answer
        # @param extra [Hash] Extra request fields
        # @raise [ArgumentError] If neither instructions nor criteria are given,
        #   or if criteria are not a Hash
        #
        def initialize(instructions: nil, criteria: nil, extra: {})
          super

          raise ArgumentError, "noul needs instructions or criteria" if instructions.nil? && criteria.nil?
          raise ArgumentError, "noul criteria must be a Hash of true and false descriptions" unless criteria.nil? || criteria.is_a?(Hash)
        end

        def type
          "noul"
        end

        def parse(raw)
          Answers::Noul.new(question: self, raw: raw)
        end

        private

        def criteria_request
          stringify(criteria)
        end

      end

      ##
      # One option out of a set
      #
      # Criteria name the options and describe them. A description may be nil
      # when the option name speaks for itself, and an Array of names is
      # accepted as shorthand for exactly that.
      #
      # @example
      #   Choice.new(
      #     instructions: "Which team should handle this ticket?",
      #     criteria: {
      #       billing: "Payment or subscription issues",
      #       engineering: "Bugs or integration problems",
      #       success: "Pricing or account questions"
      #     }
      #   )
      #
      # @example Names that speak for themselves
      #   Choice.new(instructions: "What is the tone?", criteria: %w[calm frustrated angry])
      #
      class Choice < Question

        ##
        # @param criteria [Hash, Array] Options, with descriptions or without
        # @param instructions [String, nil] What the model should decide
        # @param extra [Hash] Extra request fields
        # @raise [ArgumentError] If criteria are missing, malformed, or name
        #   fewer than two distinct options
        #
        def initialize(criteria:, instructions: nil, extra: {})
          criteria = criteria.to_h { |option| [option, nil] } if criteria.is_a?(Array)

          super(instructions: instructions, criteria: criteria, extra: extra)

          raise ArgumentError, "choice criteria must be a Hash of options to descriptions" unless criteria.is_a?(Hash)
          raise ArgumentError, "choice needs at least 2 options" if options.size < 2
          raise ArgumentError, "choice options must be distinct" if options.uniq.size != options.size
        end

        ##
        # @return [Array<String>] The options the model picks from
        #
        def options
          criteria.keys.map(&:to_s)
        end

        def type
          "choice"
        end

        def parse(raw)
          Answers::Choice.new(question: self, raw: raw)
        end

        private

        def criteria_request
          stringify(criteria)
        end

      end

      ##
      # A place on an ordered rubric
      #
      # Criteria are the levels, lowest first, each described in its own
      # string. A level's position is its score, starting at zero, and the
      # answer's score is probability-weighted, so it can land between levels.
      #
      # @example
      #   Score.new(
      #     instructions: "How frustrated does the customer appear?",
      #     criteria: ["Calm, just stating facts", "Frustrated but civil", "Very angry"]
      #   )
      #
      class Score < Question

        ##
        # @param criteria [Array<String>] Level descriptions, lowest first
        # @param instructions [String, nil] What the model should decide
        # @param extra [Hash] Extra request fields
        # @raise [ArgumentError] If criteria are not an Array of at least two levels
        #
        def initialize(criteria:, instructions: nil, extra: {})
          super(instructions: instructions, criteria: criteria, extra: extra)

          raise ArgumentError, "score criteria must be an Array of level descriptions" unless criteria.is_a?(Array)
          raise ArgumentError, "score needs at least 2 levels" if criteria.size < 2
        end

        ##
        # @return [Array<String>] The rubric levels, lowest first
        #
        def levels
          criteria.map(&:to_s)
        end

        def type
          "score"
        end

        def parse(raw)
          Answers::Score.new(question: self, raw: raw)
        end

      end

      # Wire type names to their question classes
      Question::TYPES = {
        "noul" => Noul,
        "choice" => Choice,
        "score" => Score
      }.freeze

    end

  end

end

# frozen_string_literal: true

require_relative "../logging"
require_relative "../errors"
require_relative "../retry_handler"
require_relative "decision/questions"
require_relative "decision/answers"

module RAAF

  module Models

    ##
    # Abstract base class for decision model ("System One") providers
    #
    # A decision model evaluates a piece of state and returns typed answers
    # with probabilities. It does not generate text, call tools or stream, so
    # it deliberately does not share {ModelInterface}: a decision provider has
    # no sensible +chat_completion+ and a chat provider has no sensible
    # +decide+. Routing a decision model through {RAAF::ProviderRegistry} would
    # hand chat callers something that cannot answer them, which is why
    # {RAAF::DecisionRegistry} is separate.
    #
    # Implementations supply {#perform_decision}; retry handling is applied
    # around it by {#decide}.
    #
    # @abstract Subclass and implement {#perform_decision} and {#provider_name}
    #
    # @example Implementing a provider
    #   class MyDecisionProvider < DecisionInterface
    #     def perform_decision(state:, questions:, model:, **kwargs)
    #       # POST somewhere, then build a Decision::Result
    #     end
    #
    #     def provider_name
    #       "MyDecisionProvider"
    #     end
    #   end
    #
    # @example Asking several questions about one state
    #   result = provider.decide(
    #     state: ticket_body,
    #     questions: {
    #       urgent: Decision::Noul.new(instructions: "The message conveys urgency"),
    #       team: Decision::Choice.new(
    #         instructions: "Which team should handle this?",
    #         options: %w[billing engineering success]
    #       )
    #     }
    #   )
    #   result[:urgent].probability  # => 0.999
    #   result[:team].option         # => "billing"
    #
    class DecisionInterface

      include Logger
      include RetryHandler

      # @return [String, nil] The model this provider asks by default
      attr_reader :model

      ##
      # Initialize a new decision provider
      #
      # @param api_key [String, nil] API key for authentication
      # @param api_base [String, nil] Custom API base URL
      # @param model [String, nil] Default model id for {#decide}
      # @param options [Hash] Additional provider-specific options
      #
      def initialize(api_key: nil, api_base: nil, model: nil, **options)
        @api_key = api_key
        @api_base = api_base
        @options = options
        @model = model || default_model
        initialize_retry_config
      end

      ##
      # Answer questions about a piece of state
      #
      # Providers evaluate every question in one pass, so asking several
      # questions about the same state costs little more than asking one.
      #
      # @param state [String, Hash, Array] What to decide about
      # @param questions [Hash{Symbol, String => Decision::Question, Hash}] Questions by name
      # @param model [String, nil] Model id, overriding the provider default
      # @param kwargs [Hash] Additional provider-specific parameters
      #
      # @return [Decision::Result] The answers, keyed by question name
      #
      # @raise [ArgumentError] If the state or questions are missing or malformed
      # @raise [AuthenticationError] If the API key is invalid
      # @raise [RateLimitError] If the rate limit is exceeded
      # @raise [APIError] For other API errors
      #
      def decide(state:, questions:, model: nil, **kwargs)
        validate_state!(state)
        built = build_questions(questions)

        with_retry(:decide) do
          perform_decision(state: state, questions: built, model: model || @model, **kwargs)
        end
      end

      ##
      # Ask a single yes/no question about a piece of state
      #
      # @param state [String, Hash, Array] What to decide about
      # @param instructions [String] The statement to assess
      # @param model [String, nil] Model id, overriding the provider default
      # @param kwargs [Hash] Additional provider-specific parameters
      #
      # @return [Decision::Answers::Noul] The calibrated probability
      #
      # @example
      #   provider.noul(state: ticket, instructions: "The message conveys urgency").probability
      #
      def noul(state:, instructions:, model: nil, **)
        decide(
          state: state,
          questions: { answer: Decision::Noul.new(instructions: instructions) },
          model: model,
          **
        ).fetch("answer")
      end

      ##
      # Perform the decision request
      #
      # @param state [String, Hash, Array] What to decide about
      # @param questions [Hash{String => Decision::Question}] Built questions by name
      # @param model [String, nil] Model id to use
      # @param kwargs [Hash] Additional provider-specific parameters
      # @return [Decision::Result]
      # @raise [NotImplementedError] Unless overridden
      #
      def perform_decision(state:, questions:, model:, **kwargs)
        raise NotImplementedError, "#{self.class} must implement #perform_decision"
      end

      ##
      # The provider's display name
      #
      # @return [String]
      # @raise [NotImplementedError] Unless overridden
      #
      def provider_name
        raise NotImplementedError, "#{self.class} must implement #provider_name"
      end

      ##
      # The model used when the caller names none
      #
      # @return [String, nil]
      #
      def default_model
        nil
      end

      ##
      # Model ids this provider accepts, empty when it does not restrict them
      #
      # @return [Array<String>]
      #
      def supported_models
        []
      end

      private

      ##
      # @param state [Object] The state to check
      # @raise [ArgumentError] If the state is missing or empty
      #
      def validate_state!(state)
        raise ArgumentError, "state is required" if state.nil?
        raise ArgumentError, "state cannot be empty" if state.respond_to?(:empty?) && state.empty?
      end

      ##
      # Builds every question, keyed by name as a String
      #
      # @param questions [Hash] Questions by name
      # @return [Hash{String => Decision::Question}]
      # @raise [ArgumentError] If no questions are given or one is malformed
      #
      def build_questions(questions)
        raise ArgumentError, "questions must be a Hash of name => question" unless questions.is_a?(Hash)
        raise ArgumentError, "at least one question is required" if questions.empty?

        questions.each_with_object({}) do |(name, question), built|
          built[name.to_s] = Decision::Question.build(question)
        rescue ArgumentError => e
          raise ArgumentError, "question #{name.inspect}: #{e.message}"
        end
      end

      ##
      # Checks a model id against {#supported_models}
      #
      # @param model [String, nil] The model id
      # @raise [ArgumentError] If the provider restricts models and this one is not listed
      #
      def validate_model!(model)
        return if supported_models.empty?
        return if supported_models.include?(model)

        raise ArgumentError,
              "Model #{model.inspect} is not supported by #{provider_name}. " \
              "Supported: #{supported_models.join(", ")}"
      end

    end

  end

end

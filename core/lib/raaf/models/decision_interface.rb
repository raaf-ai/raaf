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
      include RAAF::Tracing::Traceable

      trace_as :decision

      # @return [String, nil] The model this provider asks by default
      attr_reader :model

      ##
      # Initialize a new decision provider
      #
      # @param api_key [String, nil] API key for authentication
      # @param api_base [String, nil] Custom API base URL
      # @param model [String, nil] Default model id for {#decide}
      # @param tracer [Object, nil] Tracer to send decision spans to, instead
      #   of whichever tracer is configured globally
      # @param trace_state [Boolean, nil] Whether to record the state decided
      #   about on the span. nil defers to +RAAF_TRACE_DECISION_STATE+.
      # @param options [Hash] Additional provider-specific options
      #
      def initialize(api_key: nil, api_base: nil, model: nil, tracer: nil, trace_state: nil, **options)
        @api_key = api_key
        @api_base = api_base
        @options = options
        @model = model || default_model
        @tracer = tracer
        @trace_state = trace_state
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
        asked = model || @model

        # One span per call, wrapped outside the retries: a caller reading the
        # trace wants to know that a decision was made and what it cost, and
        # three spans for one answer would be counted three times on the bill.
        with_traced_decision(state: state, questions: built) do
          with_tracing(:decide, span_display_name: asked) do
            with_retry(:decide) do
              perform_decision(state: state, questions: built, model: asked, **kwargs)
            end
          end
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

      ##
      # Whether the state decided about is recorded on the span
      #
      # The state is whatever the caller is deciding about, which in an
      # application is customer data. Copying it into a span payload is a
      # decision somebody has to make deliberately, so it is off unless the
      # provider was built asking for it or +RAAF_TRACE_DECISION_STATE+ is
      # "true". An explicit +trace_state:+ wins over the environment.
      #
      # @return [Boolean]
      #
      def trace_state?
        return @trace_state ? true : false unless @trace_state.nil?

        ENV["RAAF_TRACE_DECISION_STATE"].to_s == "true"
      end

      ##
      # The call this provider has in flight on this thread
      #
      # The questions are arguments to one call rather than state of the
      # provider, so {RAAF::Tracing::SpanCollectors::DecisionCollector} has
      # nowhere else to read them from. Kept per thread and keyed by the
      # provider itself, because a provider is registered once and shared: two
      # threads deciding at the same time would otherwise record each other's
      # questions.
      #
      # @return [Hash{Symbol => Object}, nil] +{ state:, questions: }+, or nil
      #   outside a call
      #
      def traced_decision
        Thread.current[:raaf_decision_calls]&.[](self)
      end

      # The state shapes a decision model accepts
      STATE_TYPES = [String, Symbol, Hash, Array].freeze

      private

      ##
      # Publish the call in flight for {#traced_decision}, and take it down again
      #
      # @param call [Hash] The state and built questions of this call
      # @return [Object] Whatever the block returns
      #
      def with_traced_decision(**call)
        calls = (Thread.current[:raaf_decision_calls] ||= {}.compare_by_identity)
        calls[self] = call
        yield
      ensure
        calls.delete(self)
        Thread.current[:raaf_decision_calls] = nil if calls.empty?
      end

      ##
      # @param state [Object] The state to check
      # @raise [ArgumentError] If the state is missing, empty, or a shape that
      #   cannot be sent as JSON
      #
      def validate_state!(state)
        raise ArgumentError, "state is required" if state.nil?
        raise ArgumentError, "state cannot be empty" if state.respond_to?(:empty?) && state.empty?
        return if STATE_TYPES.any? { |type| state.is_a?(type) }

        raise ArgumentError, "state must be a String, Hash or Array, got #{state.class}"
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

# frozen_string_literal: true

require_relative "model_config"
require_relative "tracing_config"
require_relative "execution_config"

module RAAF

  ##
  # Configuration for a single run of an agent
  #
  # This class composes focused configuration objects to provide
  # a clean separation of concerns while maintaining backwards compatibility.
  # Uses composition pattern with specialized config objects for better
  # maintainability and testing.
  #
  # @example Basic usage
  #   config = RunConfig.new(max_turns: 10, temperature: 0.7)
  #   runner.run(messages, config: config)
  #
  # @example Using focused configs
  #   model_config = Config::ModelConfig.new(temperature: 0.7, max_tokens: 1000)
  #   tracing_config = Config::TracingConfig.new(trace_id: "custom-123")
  #   config = RunConfig.new(model: model_config, tracing: tracing_config)
  #
  # @example Disable tracing for sensitive data
  #   config = RunConfig.new(
  #     tracing_disabled: true,
  #     trace_include_sensitive_data: false
  #   )
  #
  # @example Custom trace context
  #   config = RunConfig.new(
  #     trace_id: "custom-trace-123",
  #     group_id: "conversation-456",
  #     metadata: { user_id: "user789" }
  #   )
  #
  class RunConfig

    attr_reader :model, :tracing, :execution

    ##
    # Initialize with either individual parameters or config objects
    #
    # @param model [Config::ModelConfig, nil] Model configuration
    # @param tracing [Config::TracingConfig, nil] Tracing configuration
    # @param execution [Config::ExecutionConfig, nil] Execution configuration
    # @param kwargs [Hash] Individual parameters (for backwards compatibility)
    #
    def initialize(
      model: nil,
      tracing: nil,
      execution: nil,
      **kwargs
    )
      # If config objects provided, use them
      @model = model || Config::ModelConfig.new(**extract_model_params(kwargs))
      @tracing = tracing || Config::TracingConfig.new(**extract_tracing_params(kwargs))
      @execution = execution || Config::ExecutionConfig.new(**extract_execution_params(kwargs))
    end

    ##
    # Backwards compatibility: delegate to model config
    delegate :temperature, to: :model

    delegate :temperature=, to: :model

    delegate :max_tokens, to: :model

    delegate :max_tokens=, to: :model

    delegate :stream, to: :model

    delegate :stream=, to: :model

    delegate :previous_response_id, to: :model

    delegate :previous_response_id=, to: :model

    ##
    # Backwards compatibility: delegate to tracing config
    delegate :trace_id, to: :tracing

    delegate :trace_id=, to: :tracing

    delegate :tracing_disabled, to: :tracing

    delegate :tracing_disabled=, to: :tracing

    delegate :trace_include_sensitive_data, to: :tracing

    delegate :trace_include_sensitive_data=, to: :tracing

    delegate :metadata, to: :tracing

    delegate :metadata=, to: :tracing

    delegate :workflow_name, to: :tracing

    delegate :workflow_name=, to: :tracing

    delegate :group_id, to: :tracing

    delegate :group_id=, to: :tracing

    ##
    # Backwards compatibility: delegate to execution config
    delegate :max_turns, to: :execution

    delegate :max_turns=, to: :execution

    delegate :hooks, to: :execution

    delegate :hooks=, to: :execution

    delegate :input_guardrails, to: :execution

    delegate :input_guardrails=, to: :execution

    delegate :output_guardrails, to: :execution

    delegate :output_guardrails=, to: :execution

    delegate :context, to: :execution

    delegate :context=, to: :execution

    delegate :session, to: :execution

    delegate :session=, to: :execution

    ##
    # Convert to model parameters (delegates to model config)
    #
    # @return [Hash] Parameters for model API calls
    #
    delegate :to_model_params, to: :model

    ##
    # Merge with another RunConfig
    #
    # @param other [RunConfig] Config to merge
    # @return [RunConfig] New merged config
    #
    def merge(other)
      return self unless other

      self.class.new(
        model: model.merge(other.model),
        tracing: tracing.merge(other.tracing),
        execution: execution.merge(other.execution)
      )
    end

    ##
    # Convert to hash representation
    #
    # @return [Hash] Complete configuration as hash
    #
    def to_h
      model.to_h.merge(tracing.to_h).merge(execution.to_h)
    end

    ##
    # Create a copy with focused config replaced
    #
    # @param model [Config::ModelConfig, nil] New model config
    # @param tracing [Config::TracingConfig, nil] New tracing config
    # @param execution [Config::ExecutionConfig, nil] New execution config
    # @return [RunConfig] New config with replaced components
    #
    def with_configs(model: nil, tracing: nil, execution: nil)
      self.class.new(
        model: model || self.model,
        tracing: tracing || self.tracing,
        execution: execution || self.execution
      )
    end

    private

    def extract_model_params(kwargs)
      model_keys = %i[temperature max_tokens model top_p stop frequency_penalty
                      presence_penalty user stream previous_response_id parallel_tool_calls
                      response_format]

      model_params = kwargs.slice(*model_keys)

      # Handle model_kwargs specially
      model_params.merge!(kwargs[:model_kwargs]) if kwargs[:model_kwargs]

      model_params
    end

    def extract_tracing_params(kwargs)
      tracing_keys = %i[trace_id group_id metadata tracing_disabled
                        trace_include_sensitive_data workflow_name]

      kwargs.slice(*tracing_keys)
    end

    def extract_execution_params(kwargs)
      execution_keys = %i[max_turns hooks input_guardrails output_guardrails context session]

      kwargs.slice(*execution_keys)
    end

  end

end

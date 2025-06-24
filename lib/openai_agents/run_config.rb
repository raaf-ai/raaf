# frozen_string_literal: true

module OpenAIAgents
  # Configuration for a single run of an agent
  #
  # This class provides fine-grained control over agent execution,
  # including tracing, model parameters, and execution limits.
  #
  # @example Basic usage
  #   config = RunConfig.new(max_turns: 10, temperature: 0.7)
  #   runner.run(messages, config: config)
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
  class RunConfig
    # @return [Integer] Maximum number of agent turns (default: from agent)
    attr_accessor :max_turns

    # @return [String, nil] Custom trace ID for this run
    attr_accessor :trace_id

    # @return [String, nil] Group ID to link related traces
    attr_accessor :group_id

    # @return [Hash, nil] Custom metadata for tracing
    attr_accessor :metadata

    # @return [Boolean] Whether to disable tracing for this run
    attr_accessor :tracing_disabled

    # @return [Boolean] Whether to include sensitive data in traces
    attr_accessor :trace_include_sensitive_data

    # @return [Float, nil] Temperature for model sampling (0.0-2.0)
    attr_accessor :temperature

    # @return [Integer, nil] Maximum tokens to generate
    attr_accessor :max_tokens

    # @return [Boolean] Whether to stream responses
    attr_accessor :stream

    # @return [String, nil] Override model for this run
    attr_accessor :model

    # @return [String] Workflow name for tracing
    attr_accessor :workflow_name

    # @return [Float, nil] Top-p sampling parameter
    attr_accessor :top_p

    # @return [Array<String>, nil] Stop sequences
    attr_accessor :stop

    # @return [Float, nil] Frequency penalty (-2.0 to 2.0)
    attr_accessor :frequency_penalty

    # @return [Float, nil] Presence penalty (-2.0 to 2.0)
    attr_accessor :presence_penalty

    # @return [String, nil] User identifier for rate limiting
    attr_accessor :user

    # @return [Hash] Additional model-specific parameters
    attr_accessor :model_kwargs

    def initialize(
      max_turns: nil,
      trace_id: nil,
      group_id: nil,
      metadata: nil,
      tracing_disabled: false,
      trace_include_sensitive_data: true,
      temperature: nil,
      max_tokens: nil,
      stream: false,
      model: nil,
      workflow_name: "Agent workflow",
      top_p: nil,
      stop: nil,
      frequency_penalty: nil,
      presence_penalty: nil,
      user: nil,
      **model_kwargs
    )
      @max_turns = max_turns
      @trace_id = trace_id
      @group_id = group_id
      @metadata = metadata
      @tracing_disabled = tracing_disabled
      @trace_include_sensitive_data = trace_include_sensitive_data
      @temperature = temperature
      @max_tokens = max_tokens
      @stream = stream
      @model = model
      @workflow_name = workflow_name
      @top_p = top_p
      @stop = stop
      @frequency_penalty = frequency_penalty
      @presence_penalty = presence_penalty
      @user = user
      @model_kwargs = model_kwargs
    end

    # Merge with another RunConfig, with other taking precedence
    def merge(other)
      return self unless other

      result = self.class.new

      # Copy all instance variables
      instance_variables.each do |var|
        value = instance_variable_get(var)
        other_value = other.instance_variable_get(var) if other.instance_variable_defined?(var)

        # Use other's value if defined and not nil
        final_value = if other.instance_variable_defined?(var) && !other_value.nil?
                        other_value
                      else
                        value
                      end

        result.instance_variable_set(var, final_value)
      end

      result
    end

    # Convert to hash for API calls
    def to_model_params
      params = {}

      params[:temperature] = temperature if temperature
      params[:max_tokens] = max_tokens if max_tokens
      params[:top_p] = top_p if top_p
      params[:stop] = stop if stop
      params[:frequency_penalty] = frequency_penalty if frequency_penalty
      params[:presence_penalty] = presence_penalty if presence_penalty
      params[:user] = user if user
      params[:stream] = stream if stream

      # Merge any additional model kwargs
      params.merge!(model_kwargs) if model_kwargs

      params
    end

    # Convert to hash
    def to_h
      {
        max_turns: max_turns,
        trace_id: trace_id,
        group_id: group_id,
        metadata: metadata,
        tracing_disabled: tracing_disabled,
        trace_include_sensitive_data: trace_include_sensitive_data,
        temperature: temperature,
        max_tokens: max_tokens,
        stream: stream,
        model: model,
        workflow_name: workflow_name,
        top_p: top_p,
        stop: stop,
        frequency_penalty: frequency_penalty,
        presence_penalty: presence_penalty,
        user: user,
        model_kwargs: model_kwargs
      }
    end
  end
end

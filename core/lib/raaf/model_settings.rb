# frozen_string_literal: true

module RAAF

  ##
  # ModelSettings - Comprehensive configuration for LLM model parameters
  #
  # This class provides a centralized way to configure all model-specific parameters
  # that can be passed to LLM providers. It matches the Python implementation's
  # ModelSettings dataclass and provides validation and merging capabilities.
  #
  # == Basic Usage
  #
  #   settings = RAAF::ModelSettings.new(
  #     temperature: 0.7,
  #     max_tokens: 2000,
  #     top_p: 0.9
  #   )
  #
  # == Advanced Usage
  #
  #   settings = RAAF::ModelSettings.new(
  #     temperature: 0.3,
  #     tool_choice: "auto",
  #     parallel_tool_calls: true,
  #     reasoning: { reasoning_effort: "medium" },
  #     metadata: { user_id: "123", session_id: "abc" }
  #   )
  class ModelSettings

    # Core model parameters
    attr_accessor :temperature, :top_p, :frequency_penalty, :presence_penalty
    attr_accessor :max_tokens, :stop, :stream

    # Tool-related parameters
    attr_accessor :tool_choice, :parallel_tool_calls

    # Advanced parameters
    attr_accessor :truncation, :reasoning, :metadata, :store, :include_usage

    # Request customization
    attr_accessor :extra_query, :extra_body, :extra_headers, :extra_args

    # Response format
    attr_accessor :response_format

    # Model-specific parameters
    attr_accessor :top_k, :repetition_penalty, :min_p, :typical_p

    ##
    # Create new ModelSettings instance
    #
    # @param temperature [Float, nil] controls randomness (0.0-2.0)
    # @param top_p [Float, nil] nucleus sampling parameter (0.0-1.0)
    # @param frequency_penalty [Float, nil] frequency penalty (-2.0-2.0)
    # @param presence_penalty [Float, nil] presence penalty (-2.0-2.0)
    # @param max_tokens [Integer, nil] maximum tokens to generate
    # @param stop [String, Array<String>, nil] stop sequences
    # @param stream [Boolean, nil] enable streaming responses
    # @param tool_choice [String, Hash, nil] tool selection strategy
    # @param parallel_tool_calls [Boolean, nil] allow parallel tool execution
    # @param truncation [String, nil] truncation strategy ('auto', 'disabled')
    # @param reasoning [Hash, nil] reasoning configuration
    # @param metadata [Hash, nil] request metadata
    # @param store [Boolean, nil] store conversation
    # @param include_usage [Boolean, nil] include usage statistics
    # @param extra_query [Hash, nil] additional query parameters
    # @param extra_body [Hash, nil] additional body parameters
    # @param extra_headers [Hash, nil] additional headers
    # @param extra_args [Hash, nil] additional arguments
    # @param response_format [Hash, nil] response format specification
    # @param top_k [Integer, nil] top-k sampling
    # @param repetition_penalty [Float, nil] repetition penalty
    # @param min_p [Float, nil] minimum probability threshold
    # @param typical_p [Float, nil] typical probability sampling
    def initialize(
      temperature: nil,
      top_p: nil,
      frequency_penalty: nil,
      presence_penalty: nil,
      max_tokens: nil,
      stop: nil,
      stream: nil,
      tool_choice: nil,
      parallel_tool_calls: nil,
      truncation: nil,
      reasoning: nil,
      metadata: nil,
      store: nil,
      include_usage: nil,
      extra_query: nil,
      extra_body: nil,
      extra_headers: nil,
      extra_args: nil,
      response_format: nil,
      top_k: nil,
      repetition_penalty: nil,
      min_p: nil,
      typical_p: nil,
      **kwargs
    )
      @temperature = temperature
      @top_p = top_p
      @frequency_penalty = frequency_penalty
      @presence_penalty = presence_penalty
      @max_tokens = max_tokens
      @stop = stop
      @stream = stream
      @tool_choice = tool_choice
      @parallel_tool_calls = parallel_tool_calls
      @truncation = truncation
      @reasoning = reasoning
      @metadata = metadata
      @store = store
      @include_usage = include_usage
      @extra_query = extra_query
      @extra_body = extra_body
      @extra_headers = extra_headers
      @extra_args = extra_args
      @response_format = response_format
      @top_k = top_k
      @repetition_penalty = repetition_penalty
      @min_p = min_p
      @typical_p = typical_p

      # Handle any additional kwargs
      kwargs.each do |key, value|
        instance_variable_set("@#{key}", value)
        self.class.attr_accessor(key) unless respond_to?(key)
      end

      validate_parameters
    end

    ##
    # Merge with another ModelSettings instance or hash
    #
    # @param other [ModelSettings, Hash] settings to merge
    # @return [ModelSettings] new instance with merged settings
    def merge(other)
      case other
      when ModelSettings
        new_params = to_h.merge(other.to_h)
      when Hash
        new_params = to_h.merge(other)
      else
        raise ArgumentError, "Can only merge with ModelSettings or Hash"
      end

      self.class.new(**new_params)
    end

    ##
    # Convert to hash for API calls
    #
    # @param provider_format [Symbol] format for specific provider (:openai, :anthropic, :cohere)
    # @return [Hash] parameters formatted for the provider
    def to_h(provider_format: :openai)
      base_params = {
        temperature: @temperature,
        top_p: @top_p,
        frequency_penalty: @frequency_penalty,
        presence_penalty: @presence_penalty,
        max_tokens: @max_tokens,
        stop: @stop,
        stream: @stream,
        tool_choice: @tool_choice,
        parallel_tool_calls: @parallel_tool_calls,
        truncation: @truncation,
        reasoning: @reasoning,
        metadata: @metadata,
        store: @store,
        include_usage: @include_usage,
        response_format: @response_format,
        top_k: @top_k,
        repetition_penalty: @repetition_penalty,
        min_p: @min_p,
        typical_p: @typical_p
      }.compact

      # Add extra parameters
      base_params.merge!(@extra_query || {})
      base_params.merge!(@extra_body || {})
      base_params.merge!(@extra_args || {}) if @extra_args

      # Format for specific provider
      case provider_format
      when :anthropic
        format_for_anthropic(base_params)
      when :cohere
        format_for_cohere(base_params)
      when :gemini
        format_for_gemini(base_params)
      else
        base_params
      end
    end

    ##
    # Get extra headers if any
    #
    # @return [Hash] extra headers for HTTP requests
    def headers
      @extra_headers || {}
    end

    ##
    # Check if streaming is enabled
    #
    # @return [Boolean] true if streaming is enabled
    def streaming?
      @stream == true
    end

    ##
    # Check if tools are configured
    #
    # @return [Boolean] true if tool choice is set
    def tools_configured?
      !@tool_choice.nil?
    end

    ##
    # Check if structured output is configured
    #
    # @return [Boolean] true if response format is set
    def structured_output?
      !@response_format.nil?
    end

    ##
    # Create a copy with specific parameters modified
    #
    # @param kwargs [Hash] parameters to modify
    # @return [ModelSettings] new instance with modifications
    def with(**kwargs)
      merge(kwargs)
    end

    ##
    # Create ModelSettings from hash (factory method)
    #
    # @param hash [Hash, ModelSettings, nil] settings hash
    # @return [ModelSettings, nil] model settings or nil if input is nil
    def self.from_hash(hash)
      return nil if hash.nil?
      return hash if hash.is_a?(ModelSettings)

      new(**hash)
    end

    ##
    # Validate parameter values
    #
    # @raise [ArgumentError] if parameters are invalid
    def validate_parameters
      validate_temperature
      validate_penalties
      validate_top_p
      validate_max_tokens
      validate_tool_choice
      validate_truncation
    end

    private

    def validate_temperature
      return unless @temperature

      return if @temperature.is_a?(Numeric) && @temperature >= 0.0 && @temperature <= 2.0

      raise ArgumentError, "temperature must be between 0.0 and 2.0"
    end

    def validate_penalties
      [@frequency_penalty, @presence_penalty].each do |penalty|
        next unless penalty

        raise ArgumentError, "penalties must be between -2.0 and 2.0" unless penalty.is_a?(Numeric) && penalty >= -2.0 && penalty <= 2.0
      end
    end

    def validate_top_p
      return unless @top_p

      return if @top_p.is_a?(Numeric) && @top_p >= 0.0 && @top_p <= 1.0

      raise ArgumentError, "top_p must be between 0.0 and 1.0"
    end

    def validate_max_tokens
      return unless @max_tokens

      return if @max_tokens.is_a?(Integer) && @max_tokens.positive?

      raise ArgumentError, "max_tokens must be a positive integer"
    end

    def validate_tool_choice
      return unless @tool_choice

      valid_choices = %w[auto none required]
      return if valid_choices.include?(@tool_choice)
      return if @tool_choice.is_a?(Hash) # Custom tool choice
      return if @tool_choice.is_a?(String) && @tool_choice.start_with?("function:")

      raise ArgumentError, "tool_choice must be 'auto', 'none', 'required', a hash, or 'function:name'"
    end

    def validate_truncation
      return unless @truncation

      valid_truncation = %w[auto disabled]
      return if valid_truncation.include?(@truncation)

      raise ArgumentError, "truncation must be 'auto' or 'disabled'"
    end

    # Provider-specific formatting
    def format_for_anthropic(params)
      # Anthropic-specific parameter mapping
      anthropic_params = params.dup

      # Map max_tokens to max_tokens_to_sample for older Anthropic API
      anthropic_params[:max_tokens_to_sample] = anthropic_params.delete(:max_tokens) if anthropic_params[:max_tokens]

      # Remove unsupported parameters
      anthropic_params.delete(:frequency_penalty)
      anthropic_params.delete(:presence_penalty)
      anthropic_params.delete(:parallel_tool_calls)
      anthropic_params.delete(:truncation)

      anthropic_params
    end

    def format_for_cohere(params)
      # Cohere-specific parameter mapping
      cohere_params = params.dup

      # Map parameters to Cohere names
      cohere_params[:max_tokens] = cohere_params.delete(:max_tokens) if cohere_params[:max_tokens]

      cohere_params[:stop_sequences] = cohere_params.delete(:stop) if cohere_params[:stop]

      # Remove unsupported parameters
      cohere_params.delete(:frequency_penalty)
      cohere_params.delete(:presence_penalty)
      cohere_params.delete(:top_p) # Cohere uses p instead
      cohere_params[:p] = params[:top_p] if params[:top_p]

      cohere_params
    end

    def format_for_gemini(params)
      # Gemini-specific parameter mapping
      gemini_params = params.dup

      # Gemini uses different parameter names
      gemini_params[:maxOutputTokens] = gemini_params.delete(:max_tokens) if gemini_params[:max_tokens]

      # temperature is already correctly named for Gemini

      gemini_params[:topP] = gemini_params.delete(:top_p) if gemini_params[:top_p]

      gemini_params[:topK] = gemini_params.delete(:top_k) if gemini_params[:top_k]

      # Remove unsupported parameters
      gemini_params.delete(:frequency_penalty)
      gemini_params.delete(:presence_penalty)
      gemini_params.delete(:tool_choice)
      gemini_params.delete(:parallel_tool_calls)

      gemini_params
    end

  end

end

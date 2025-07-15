# frozen_string_literal: true

module RubyAIAgentsFactory
  module Config
    ##
    # Configuration for AI model parameters
    #
    # This class handles all parameters that are sent directly to the AI model,
    # including sampling parameters, token limits, and model selection.
    #
    # @example Basic model configuration
    #   config = ModelConfig.new(
    #     temperature: 0.7,
    #     max_tokens: 1000,
    #     model: "gpt-4o"
    #   )
    #
    # @example Converting to API parameters
    #   api_params = config.to_model_params
    #   # => { temperature: 0.7, max_tokens: 1000, stream: false }
    #
    # @example Merging configurations
    #   base_config = ModelConfig.new(temperature: 0.5)
    #   override_config = ModelConfig.new(temperature: 0.9, max_tokens: 500)
    #   merged = base_config.merge(override_config)
    #   # => ModelConfig with temperature: 0.9, max_tokens: 500
    #
    class ModelConfig
      # @return [Float, nil] Temperature for model sampling (0.0-2.0)
      attr_accessor :temperature

      # @return [Integer, nil] Maximum tokens to generate
      attr_accessor :max_tokens

      # @return [String, nil] Override model for this run
      attr_accessor :model

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

      # @return [Boolean] Whether to stream responses
      attr_accessor :stream

      # @return [Hash] Additional model-specific parameters
      attr_accessor :model_kwargs

      # @return [String, nil] Previous response ID for Responses API continuity
      attr_accessor :previous_response_id

      def initialize(
        temperature: nil,
        max_tokens: nil,
        model: nil,
        top_p: nil,
        stop: nil,
        frequency_penalty: nil,
        presence_penalty: nil,
        user: nil,
        stream: false,
        previous_response_id: nil,
        **model_kwargs
      )
        @temperature = temperature
        @max_tokens = max_tokens
        @model = model
        @top_p = top_p
        @stop = stop
        @frequency_penalty = frequency_penalty
        @presence_penalty = presence_penalty
        @user = user
        @stream = stream
        @model_kwargs = model_kwargs
        @previous_response_id = previous_response_id
      end

      ##
      # Convert to parameters suitable for model API calls
      #
      # @return [Hash] Parameters for the model API
      #
      def to_model_params
        # Define parameters that should be included in model calls
        model_params = %i[temperature max_tokens top_p stop frequency_penalty presence_penalty user stream]

        # Use Ruby's send method for dynamic parameter mapping
        params = model_params.each_with_object({}) do |param, hash|
          value = send(param)
          hash[param] = value if value
        end

        # Merge any additional model kwargs
        params.merge!(model_kwargs) if model_kwargs

        params
      end

      ##
      # Merge with another ModelConfig, with other taking precedence
      #
      # @param other [ModelConfig] Config to merge
      # @return [ModelConfig] New merged config
      #
      def merge(other)
        return self unless other

        self.class.new(
          temperature: other.temperature || temperature,
          max_tokens: other.max_tokens || max_tokens,
          model: other.model || model,
          top_p: other.top_p || top_p,
          stop: other.stop || stop,
          frequency_penalty: other.frequency_penalty || frequency_penalty,
          presence_penalty: other.presence_penalty || presence_penalty,
          user: other.user || user,
          stream: other.stream.nil? ? stream : other.stream,
          previous_response_id: other.previous_response_id || previous_response_id,
          **model_kwargs.merge(other.model_kwargs || {})
        )
      end

      ##
      # Convert to hash representation
      #
      # @return [Hash] All configuration as hash
      #
      def to_h
        {
          temperature: temperature,
          max_tokens: max_tokens,
          model: model,
          top_p: top_p,
          stop: stop,
          frequency_penalty: frequency_penalty,
          presence_penalty: presence_penalty,
          user: user,
          stream: stream,
          model_kwargs: model_kwargs,
          previous_response_id: previous_response_id
        }
      end
    end
  end
end
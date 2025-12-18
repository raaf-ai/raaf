# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # SpanReplayer replays an LLM API call using the data captured in a span.
    #
    # This is a much simpler approach than re-instantiating agents because:
    # - We don't need to resolve prompt classes (no more context.account errors)
    # - We don't need to deserialize ActiveRecord objects from context
    # - We use exactly the same prompts that were originally sent
    # - It's a true "replay" of the original API call
    #
    # The span already contains everything we need:
    # - agent.conversation_messages: The exact messages sent to the LLM
    # - agent.model: The model name
    # - agent.temperature, agent.max_tokens, etc.: Model settings
    # - agent.response_format: The JSON schema (if used)
    #
    # @example Basic usage
    #   span = RAAF::Rails::Tracing::SpanRecord.find_by(span_id: "span_abc123")
    #   replayer = RAAF::Eval::SpanReplayer.new(span)
    #   result = replayer.replay
    #
    # @example With configuration overrides
    #   result = replayer.replay(
    #     model: "gpt-4-turbo",      # Override model
    #     temperature: 0.5           # Override temperature
    #   )
    #
    class SpanReplayer
      attr_reader :span

      ##
      # Initialize with a span record
      # @param span [SpanRecord] The span to replay
      def initialize(span)
        @span = span
        @attrs = span.span_attributes || {}
      end

      ##
      # Replay the API call captured in the span
      #
      # @param overrides [Hash] Override any settings (model, temperature, etc.)
      # @return [Hash] Result with :success, :content, :usage, :raw_response keys
      def replay(**overrides)
        started_at = Time.current

        # Extract original configuration
        messages = extract_messages
        model = overrides[:model] || extract_model
        settings = extract_model_settings.merge(overrides.except(:model))
        response_format = extract_response_format

        # Validate we have the minimum required data
        validate_messages!(messages)
        validate_model!(model)

        # Get the appropriate provider
        provider = build_provider(model, overrides)

        # Build the request parameters
        request_params = build_request_params(
          messages: messages,
          model: model,
          settings: settings,
          response_format: response_format
        )

        RAAF.logger.info "[SpanReplayer] Replaying span #{span.span_id} with model: #{model}"
        RAAF.logger.debug "[SpanReplayer] Messages count: #{messages.size}"
        RAAF.logger.debug "[SpanReplayer] Settings: #{settings.inspect}"
        RAAF.logger.debug "[SpanReplayer] Response format present: #{response_format.present?}"
        if response_format.present?
          RAAF.logger.debug "[SpanReplayer] Response format type: #{response_format[:type]}"
        end

        # Log first message for debugging (truncated)
        if messages.any?
          first_msg = messages.first
          content_preview = (first_msg[:content] || first_msg['content']).to_s[0..200]
          RAAF.logger.debug "[SpanReplayer] First message role: #{first_msg[:role] || first_msg['role']}"
          RAAF.logger.debug "[SpanReplayer] First message preview: #{content_preview}..."
        end

        # Make the API call
        response = provider.responses_completion(**request_params)

        completed_at = Time.current
        duration_ms = ((completed_at - started_at) * 1000).round

        {
          success: true,
          content: extract_response_content(response),
          usage: extract_usage(response),
          raw_response: response,
          duration_ms: duration_ms,
          model: model,
          settings: settings
        }
      rescue StandardError => e
        RAAF.logger.error "[SpanReplayer] Replay failed: #{e.message}"
        RAAF.logger.error "[SpanReplayer] Backtrace: #{e.backtrace.first(5).join("\n")}"

        {
          success: false,
          error: e.message,
          error_class: e.class.name,
          content: nil,
          usage: nil
        }
      end

      ##
      # Check if this span can be replayed
      # @return [Boolean] True if span has required data for replay
      def replayable?
        messages = extract_messages
        model = extract_model

        messages.present? && model.present?
      end

      ##
      # Get the original model from the span
      # @return [String, nil] Model name
      def original_model
        extract_model
      end

      ##
      # Get the original settings from the span
      # @return [Hash] Model settings
      def original_settings
        extract_model_settings
      end

      ##
      # Get the original messages from the span
      # @return [Array<Hash>] Messages array
      def original_messages
        extract_messages
      end

      private

      ##
      # Extract messages from span attributes
      # @return [Array<Hash>] Array of message hashes
      def extract_messages
        messages_json = @attrs['agent.conversation_messages']
        return [] unless messages_json.present?

        begin
          messages = messages_json.is_a?(String) ? JSON.parse(messages_json) : messages_json
          # Ensure messages have the correct structure
          messages.map do |msg|
            {
              role: msg['role'] || msg[:role],
              content: msg['content'] || msg[:content]
            }.compact
          end
        rescue JSON::ParserError => e
          RAAF.logger.warn "[SpanReplayer] Failed to parse messages: #{e.message}"
          []
        end
      end

      ##
      # Extract model from span attributes
      # @return [String, nil] Model name
      def extract_model
        @attrs['agent.model'] || @attrs['model'] || @attrs.dig('llm', 'request', 'model')
      end

      ##
      # Extract model settings from span attributes
      # @return [Hash] Settings hash with symbolized keys
      def extract_model_settings
        settings = {}

        # Try to get from model_settings_json first (most complete)
        if @attrs['agent.model_settings_json'].present?
          begin
            parsed = JSON.parse(@attrs['agent.model_settings_json'])
            settings = parsed.transform_keys(&:to_sym)
          rescue JSON::ParserError
            # Fall through to individual attributes
          end
        end

        # Override with individual attributes if present
        settings[:temperature] = @attrs['agent.temperature'].to_f if @attrs['agent.temperature'].present?
        settings[:max_tokens] = @attrs['agent.max_tokens'].to_i if @attrs['agent.max_tokens'].present?
        settings[:top_p] = @attrs['agent.top_p'].to_f if @attrs['agent.top_p'].present?
        settings[:frequency_penalty] = @attrs['agent.frequency_penalty'].to_f if @attrs['agent.frequency_penalty'].present?
        settings[:presence_penalty] = @attrs['agent.presence_penalty'].to_f if @attrs['agent.presence_penalty'].present?

        # Remove zero/nil values that shouldn't override defaults
        settings.reject { |_, v| v.nil? || v == 0 }
      end

      ##
      # Extract response format (JSON schema) from span attributes
      # @return [Hash, nil] Response format hash with symbolized keys
      def extract_response_format
        format_json = @attrs['agent.response_format']
        return nil unless format_json.present?

        begin
          parsed = format_json.is_a?(String) ? JSON.parse(format_json) : format_json
          # Deep symbolize keys - providers expect symbol keys (:type, :json_schema, etc.)
          deep_symbolize_keys(parsed)
        rescue JSON::ParserError
          nil
        end
      end

      ##
      # Deep symbolize keys in a hash/array structure
      # @param obj [Hash, Array, Object] Object to transform
      # @return [Hash, Array, Object] Transformed object with symbol keys
      def deep_symbolize_keys(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(key, value), result|
            result[key.to_sym] = deep_symbolize_keys(value)
          end
        when Array
          obj.map { |item| deep_symbolize_keys(item) }
        else
          obj
        end
      end

      ##
      # Validate that we have messages to replay
      # @raise [ArgumentError] If messages are empty
      def validate_messages!(messages)
        if messages.empty?
          raise ArgumentError, "Cannot replay span: no messages found in span #{span.span_id}"
        end
      end

      ##
      # Validate that we have a model
      # @raise [ArgumentError] If model is missing
      def validate_model!(model)
        if model.blank?
          raise ArgumentError, "Cannot replay span: no model found in span #{span.span_id}"
        end
      end

      ##
      # Build the appropriate provider for the model
      # @param model [String] Model name
      # @param overrides [Hash] Override options
      # @return [Object] Provider instance
      def build_provider(model, overrides)
        # Use provider override if specified (can be a provider instance or a string name)
        if overrides[:provider]
          # If it's already a provider instance, return it directly
          unless overrides[:provider].is_a?(String) || overrides[:provider].is_a?(Symbol)
            return overrides[:provider]
          end

          # It's a provider name string/symbol, use it to determine provider type
          provider_type = overrides[:provider].to_sym
        else
          # Detect provider from model name
          provider_type = RAAF::ProviderRegistry.detect(model)
        end

        RAAF.logger.info "[SpanReplayer] Detected provider type: #{provider_type} for model: #{model}"

        case provider_type
        when :openai, :responses
          RAAF::Models::ResponsesProvider.new
        when :anthropic
          if defined?(RAAF::Models::AnthropicProvider)
            RAAF::Models::AnthropicProvider.new
          else
            RAAF.logger.warn "[SpanReplayer] AnthropicProvider not available, falling back to ResponsesProvider"
            RAAF::Models::ResponsesProvider.new
          end
        when :gemini, :google
          if defined?(RAAF::Models::GeminiProvider)
            RAAF::Models::GeminiProvider.new
          else
            RAAF.logger.warn "[SpanReplayer] GeminiProvider not available, falling back to ResponsesProvider"
            RAAF::Models::ResponsesProvider.new
          end
        when :groq
          if defined?(RAAF::Models::GroqProvider)
            RAAF::Models::GroqProvider.new
          else
            RAAF.logger.warn "[SpanReplayer] GroqProvider not available, falling back to ResponsesProvider"
            RAAF::Models::ResponsesProvider.new
          end
        when :perplexity
          if defined?(RAAF::Models::PerplexityProvider)
            RAAF::Models::PerplexityProvider.new
          else
            RAAF.logger.warn "[SpanReplayer] PerplexityProvider not available, falling back to ResponsesProvider"
            RAAF::Models::ResponsesProvider.new
          end
        when :xai
          if defined?(RAAF::Models::XAIProvider)
            RAAF::Models::XAIProvider.new
          else
            RAAF.logger.warn "[SpanReplayer] XAIProvider not available, falling back to ResponsesProvider"
            RAAF::Models::ResponsesProvider.new
          end
        else
          # Default to ResponsesProvider
          RAAF.logger.info "[SpanReplayer] Using default ResponsesProvider for provider type: #{provider_type}"
          RAAF::Models::ResponsesProvider.new
        end
      end

      ##
      # Build the request parameters for the API call
      # @param messages [Array<Hash>] Messages
      # @param model [String] Model name
      # @param settings [Hash] Model settings
      # @param response_format [Hash, nil] Response format
      # @return [Hash] Request parameters
      def build_request_params(messages:, model:, settings:, response_format:)
        params = {
          messages: messages,
          model: model
        }

        # Add settings
        params[:temperature] = settings[:temperature] if settings[:temperature]
        params[:max_tokens] = settings[:max_tokens] if settings[:max_tokens]
        params[:top_p] = settings[:top_p] if settings[:top_p]

        # Add response format if present
        if response_format.present?
          params[:response_format] = response_format
        end

        params
      end

      ##
      # Extract content from the API response
      # Handles both symbol and string keys since different providers may use different key types.
      # @param response [Hash] API response
      # @return [String] Response content
      def extract_response_content(response)
        RAAF.logger.debug "[SpanReplayer] Extracting content from response keys: #{response.keys.inspect rescue 'no keys'}"

        # Helper to access keys with indifferent access (both string and symbol)
        get = ->(hash, key) { hash[key.to_s] || hash[key.to_sym] }

        # Handle different response structures
        content = nil

        choices = get.call(response, :choices)
        output = get.call(response, :output)
        direct_content = get.call(response, :content)

        if choices
          # Standard OpenAI Chat Completions format: choices[0]['message']['content']
          first_choice = choices.is_a?(Array) ? choices.first : nil
          if first_choice.is_a?(Hash)
            message = get.call(first_choice, :message)
            content = get.call(message, :content) if message.is_a?(Hash)
          end
          RAAF.logger.debug "[SpanReplayer] Extracted from 'choices' format: #{content.present?}"
        elsif output
          # Responses API format or Gemini format (both use 'output')
          RAAF.logger.debug "[SpanReplayer] Processing 'output' format, is_array: #{output.is_a?(Array)}, size: #{output.is_a?(Array) ? output.size : 'n/a'}"

          if output.is_a?(Array) && output.any?
            first_item = output.first
            RAAF.logger.debug "[SpanReplayer] first_item keys: #{first_item.keys.inspect rescue 'n/a'}"

            if first_item.is_a?(Hash)
              # Gemini format: output[0]['message']['content']
              message = get.call(first_item, :message)
              if message.is_a?(Hash)
                content = get.call(message, :content)
                RAAF.logger.debug "[SpanReplayer] Extracted from Gemini output format: #{content.present?}"
              end

              # OpenAI Responses API format: output[0] has 'type' => 'message'
              if content.nil?
                item_type = get.call(first_item, :type)
                if item_type == 'message'
                  # Try nested content[0]['text'] first
                  item_content = get.call(first_item, :content)
                  if item_content.is_a?(Array) && item_content.any?
                    first_content = item_content.first
                    content = get.call(first_content, :text) if first_content.is_a?(Hash)
                  end
                  # Fallback to direct content string
                  content ||= item_content if item_content.is_a?(String)
                  RAAF.logger.debug "[SpanReplayer] Extracted from OpenAI Responses API format: #{content.present?}"
                end
              end

              # Final fallback for first_item: try text or content directly
              if content.nil?
                content = get.call(first_item, :text) || get.call(first_item, :content)
                content = nil if content.is_a?(Hash) || content.is_a?(Array)  # Only accept strings
                RAAF.logger.debug "[SpanReplayer] Extracted from fallback format: #{content.present?}"
              end
            end
          elsif output.is_a?(String)
            content = output
            RAAF.logger.debug "[SpanReplayer] Output is string directly"
          end
        elsif direct_content
          content = direct_content if direct_content.is_a?(String)
          RAAF.logger.debug "[SpanReplayer] Extracted from direct 'content' key: #{content.present?}"
        end

        # Final fallback
        if content.nil? || (content.is_a?(String) && content.empty?)
          RAAF.logger.warn "[SpanReplayer] Could not extract content, response structure: #{response.inspect[0..1000]}"
          content = nil
        else
          RAAF.logger.info "[SpanReplayer] Successfully extracted content (#{content.to_s.length} chars)"
        end

        content
      end

      ##
      # Extract usage statistics from the API response
      # Handles both symbol and string keys.
      # @param response [Hash] API response
      # @return [Hash] Usage statistics
      def extract_usage(response)
        # Helper for indifferent access
        get = ->(hash, key) { hash[key.to_s] || hash[key.to_sym] }

        usage = get.call(response, :usage) || {}
        {
          input_tokens: get.call(usage, :input_tokens) || get.call(usage, :prompt_tokens) || 0,
          output_tokens: get.call(usage, :output_tokens) || get.call(usage, :completion_tokens) || 0,
          total_tokens: get.call(usage, :total_tokens) || 0
        }
      end
    end
  end
end

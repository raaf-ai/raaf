# frozen_string_literal: true

module OpenAIAgents
  module Models
    # Abstract base class for model providers
    class ModelInterface
      def initialize(api_key: nil, api_base: nil, **options)
        @api_key = api_key
        @api_base = api_base
        @options = options
      end

      # Abstract method - must be implemented by subclasses
      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        raise NotImplementedError, "Subclasses must implement chat_completion"
      end

      # Abstract method - must be implemented by subclasses
      def stream_completion(messages:, model:, tools: nil, &block)
        raise NotImplementedError, "Subclasses must implement stream_completion"
      end

      # Abstract method - must be implemented by subclasses
      def supported_models
        raise NotImplementedError, "Subclasses must implement supported_models"
      end

      # Abstract method - must be implemented by subclasses
      def provider_name
        raise NotImplementedError, "Subclasses must implement provider_name"
      end

      protected

      def validate_model(model)
        return if supported_models.include?(model)

        raise ArgumentError, "Model '#{model}' not supported by #{provider_name}"
      end

      def prepare_tools(tools)
        return nil if tools.nil? || tools.empty?

        prepared = tools.map do |tool|
          case tool
          when Hash
            tool
          when FunctionTool
            tool_hash = tool.to_h
            # DEBUG: Log the tool definition being sent to OpenAI
            if defined?(Rails) && Rails.logger && Rails.env.development?
              Rails.logger.debug "🔧 [OPENAI TOOLS DEBUG] Preparing tool for OpenAI API:"
              Rails.logger.debug "   Tool name: #{tool_hash.dig(:function, :name)}"
              Rails.logger.debug "   Tool type: #{tool_hash[:type]}"
              Rails.logger.debug "   Parameters: #{tool_hash.dig(:function, :parameters).inspect}"
              if tool_hash.dig(:function, :parameters, :properties)
                Rails.logger.debug "   Properties: #{tool_hash.dig(:function, :parameters, :properties).keys.join(', ')}"
                Rails.logger.debug "   Required: #{tool_hash.dig(:function, :parameters, :required) || 'none'}"
              end
            end
            tool_hash
          when OpenAIAgents::Tools::WebSearchTool, OpenAIAgents::Tools::HostedFileSearchTool, OpenAIAgents::Tools::HostedComputerTool
            tool.to_tool_definition
          else
            raise ArgumentError, "Invalid tool type: #{tool.class}"
          end
        end
        
        # DEBUG: Log the final prepared tools
        if defined?(Rails) && Rails.logger && Rails.env.development?
          Rails.logger.debug "🚀 [OPENAI TOOLS DEBUG] Final tools being sent to OpenAI API:"
          prepared.each_with_index do |tool, index|
            Rails.logger.debug "   Tool #{index + 1}: #{tool.inspect}"
          end
        end
        
        prepared
      end

      def handle_api_error(response, provider)
        case response.code.to_i
        when 401
          raise AuthenticationError, "Invalid API key for #{provider}"
        when 429
          raise RateLimitError, "Rate limit exceeded for #{provider}"
        when 500..599
          raise ServerError, "Server error from #{provider}: #{response.code}"
        else
          raise APIError, "API error from #{provider}: #{response.code} - #{response.body}"
        end
      end
    end

    # Custom error classes for model providers
    class AuthenticationError < Error; end
    class RateLimitError < Error; end
    class ServerError < Error; end
    class APIError < Error; end
  end
end

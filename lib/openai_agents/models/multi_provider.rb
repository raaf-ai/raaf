# frozen_string_literal: true

require_relative "openai_provider"
require_relative "anthropic_provider"
require_relative "cohere_provider"
require_relative "groq_provider"
require_relative "ollama_provider"
require_relative "together_provider"
require_relative "litellm_provider"

module OpenAIAgents
  module Models
    class MultiProvider
      def self.providers
        @providers ||= {
          "openai" => OpenAIProvider,
          "anthropic" => AnthropicProvider,
          "gemini" => GeminiProvider,
          "cohere" => CohereProvider,
          "groq" => GroqProvider,
          "ollama" => OllamaProvider,
          "together" => TogetherProvider,
          "litellm" => LitellmProvider
        }
      end

      def self.create_provider(provider_name, **)
        provider_class = providers[provider_name.to_s.downcase]
        raise ArgumentError, "Unknown provider: #{provider_name}" unless provider_class

        provider_class.new(**)
      end

      def self.supported_providers
        providers.keys
      end

      def self.get_provider_for_model(model)
        case model
        when /^gpt-/, /^o1-/
          "openai"
        when /^claude-/
          "anthropic"
        when /^gemini-/
          "gemini"
        when /^command-/
          "cohere"
        when /^llama/, /^mixtral/, /^gemma/
          # Could be Groq, Together, or Ollama - default to Groq for speed
          "groq"
        when /^meta-llama/, /^mistralai/, /^NousResearch/, /^togethercomputer/
          "together"
        when /^codellama/, /^phi/, /^orca/, /^vicuna/
          "ollama"
        # rubocop:disable Lint/DuplicateBranch
        else
          "openai" # Default fallback
          # rubocop:enable Lint/DuplicateBranch
        end
      end

      def self.auto_provider(model:, **)
        provider_name = get_provider_for_model(model)
        create_provider(provider_name, **)
      end
    end

    # Gemini Provider (Google)
    class GeminiProvider < ModelInterface
      DEFAULT_API_BASE = "https://generativelanguage.googleapis.com"

      SUPPORTED_MODELS = %w[
        gemini-1.5-pro gemini-1.5-flash gemini-1.0-pro
      ].freeze

      # rubocop:disable Lint/MissingSuper
      def initialize(api_key: nil, api_base: nil, **options)
        @api_key = api_key || ENV.fetch("GEMINI_API_KEY", nil)
        @api_base = api_base || ENV["GEMINI_API_BASE"] || DEFAULT_API_BASE
        @options = options

        raise AuthenticationError, "Gemini API key is required" unless @api_key
      end
      # rubocop:enable Lint/MissingSuper

      # rubocop:disable Lint/UnusedMethodArgument
      def chat_completion(messages:, model:, tools: nil, stream: false, **_kwargs)
        validate_model(model)

        uri = URI("#{@api_base}/v1beta/models/#{model}:generateContent?key=#{@api_key}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"

        body = {
          contents: convert_messages_to_gemini(messages)
        }
        body[:tools] = convert_tools_to_gemini(tools) if tools

        request.body = JSON.generate(body)

        response = http.request(request)

        handle_api_error(response, "Gemini") unless response.is_a?(Net::HTTPSuccess)

        result = JSON.parse(response.body)
        convert_gemini_to_openai_format(result)
      end

      def stream_completion(messages:, model:, tools: nil)
        # Simplified implementation - Gemini streaming is more complex
        result = chat_completion(messages: messages, model: model, tools: tools)
        content = result.dig("choices", 0, "message", "content") || ""

        # Simulate streaming by yielding chunks
        content.chars.each_slice(10) do |chunk_chars|
          chunk = chunk_chars.join
          next unless block_given?

          yield({
            type: "content",
            content: chunk,
            accumulated_content: content
          })
        end

        { content: content, tool_calls: [] }
      end

      def supported_models
        SUPPORTED_MODELS
      end

      def provider_name
        "Gemini"
      end

      private

      def convert_messages_to_gemini(messages)
        messages.map do |message|
          {
            role: message[:role] == "assistant" ? "model" : "user",
            parts: [{ text: message[:content] }]
          }
        end
      end

      def convert_tools_to_gemini(tools)
        return [] unless tools

        [{
          function_declarations: tools.map do |tool|
            if tool.is_a?(Hash) && tool[:type] == "function"
              {
                name: tool.dig(:function, :name),
                description: tool.dig(:function, :description),
                parameters: tool.dig(:function, :parameters) || {}
              }
            else
              tool
            end
          end
        }]
      end
      # rubocop:enable Lint/UnusedMethodArgument

      def convert_gemini_to_openai_format(result)
        content = result.dig("candidates", 0, "content", "parts", 0, "text") || ""

        {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => content
            },
            "finish_reason" => result.dig("candidates", 0, "finishReason")&.downcase || "stop"
          }],
          "usage" => result["usageMetadata"],
          "model" => result["modelVersion"]
        }
      end
    end
  end
end

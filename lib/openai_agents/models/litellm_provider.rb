# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "interface"
require_relative "../errors"

module OpenAIAgents
  module Models
    # LiteLLM provider enables using any model via LiteLLM proxy
    # Supports 100+ LLM providers including OpenAI, Anthropic, Gemini, Mistral, etc.
    # See supported models at: https://docs.litellm.ai/docs/providers
    class LitellmProvider < ModelInterface
      attr_reader :model, :base_url, :api_key

      # Common LiteLLM model prefixes for different providers
      PROVIDER_PREFIXES = {
        "openai/" => "OpenAI",
        "anthropic/" => "Anthropic",
        "gemini/" => "Google Gemini",
        "bedrock/" => "AWS Bedrock",
        "azure/" => "Azure OpenAI",
        "vertex_ai/" => "Google Vertex AI",
        "palm/" => "Google PaLM",
        "cohere/" => "Cohere",
        "replicate/" => "Replicate",
        "huggingface/" => "Hugging Face",
        "together_ai/" => "Together AI",
        "openrouter/" => "OpenRouter",
        "ai21/" => "AI21 Labs",
        "baseten/" => "Baseten",
        "vllm/" => "vLLM",
        "nlp_cloud/" => "NLP Cloud",
        "aleph_alpha/" => "Aleph Alpha",
        "petals/" => "Petals",
        "ollama/" => "Ollama",
        "deepinfra/" => "DeepInfra",
        "perplexity/" => "Perplexity",
        "anyscale/" => "Anyscale",
        "groq/" => "Groq",
        "mistral/" => "Mistral AI",
        "claude-3" => "Anthropic Claude 3",
        "gpt-" => "OpenAI GPT"
      }.freeze

      # Initialize LiteLLM provider
      # @param model [String] Model name with optional provider prefix (e.g., "openai/gpt-4", "anthropic/claude-3-opus")
      # @param base_url [String, nil] LiteLLM proxy URL (default: http://localhost:8000)
      # @param api_key [String, nil] API key for the provider or LiteLLM proxy
      def initialize(model:, base_url: nil, api_key: nil)
        @model = model
        @base_url = base_url || ENV["LITELLM_BASE_URL"] || "http://localhost:8000"
        @api_key = api_key || ENV["LITELLM_API_KEY"] || ENV["OPENAI_API_KEY"]
        
        # Ensure base_url doesn't end with /
        @base_url = @base_url.chomp("/")
      end

      # Get a human-readable provider name from the model string
      def provider_name
        PROVIDER_PREFIXES.each do |prefix, name|
          return name if @model.start_with?(prefix)
        end
        "Unknown Provider"
      end

      # Chat completion using LiteLLM
      def chat_completion(messages:, model: nil, tools: nil, stream: false, **kwargs)
        model ||= @model
        
        # LiteLLM uses the standard OpenAI-compatible API format
        body = {
          model: model,
          messages: prepare_messages(messages)
        }

        # Add tools if provided
        if tools && !tools.empty?
          body[:tools] = prepare_tools(tools)
          body[:tool_choice] = kwargs[:tool_choice] if kwargs[:tool_choice]
        end

        # Add model-specific parameters
        add_model_parameters(body, kwargs)

        # Handle streaming
        if stream
          stream_completion(body)
        else
          make_request(body)
        end
      end

      # Check if provider supports prompts (for Responses API)
      def supports_prompts?
        # Most providers through LiteLLM use chat completions format
        false
      end

      private

      def make_request(body)
        uri = URI("#{@base_url}/v1/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 120 # Longer timeout for some models

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}" if @api_key
        request["Content-Type"] = "application/json"
        request.body = body.to_json

        response = http.request(request)

        unless response.code.start_with?("2")
          error_body = JSON.parse(response.body) rescue { "error" => response.body }
          handle_error(response.code.to_i, error_body)
        end

        JSON.parse(response.body)
      rescue Net::ReadTimeout => e
        raise APIError, "Request timeout: #{e.message}. Consider increasing timeout for large models."
      rescue StandardError => e
        raise APIError, "LiteLLM request failed: #{e.message}"
      end

      def stream_completion(body)
        uri = URI("#{@base_url}/v1/chat/completions")
        body[:stream] = true

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{@api_key}" if @api_key
          request["Content-Type"] = "application/json"
          request["Accept"] = "text/event-stream"
          request.body = body.to_json

          http.request(request) do |response|
            unless response.code.start_with?("2")
              error_body = response.read_body
              handle_error(response.code.to_i, error_body)
            end

            response.read_body do |chunk|
              # Parse SSE format
              chunk.split("\n").each do |line|
                next if line.empty? || !line.start_with?("data: ")
                
                data = line[6..] # Remove "data: " prefix
                next if data == "[DONE]"

                begin
                  yield JSON.parse(data)
                rescue JSON::ParserError
                  # Skip invalid JSON
                end
              end
            end
          end
        end
      end

      def prepare_messages(messages)
        messages.map do |msg|
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"]
          
          # Handle tool messages
          if role == "tool"
            {
              role: "tool",
              content: content,
              tool_call_id: msg[:tool_call_id] || msg["tool_call_id"]
            }
          else
            base_msg = { role: role, content: content }
            
            # Add tool calls if present
            if msg[:tool_calls] || msg["tool_calls"]
              base_msg[:tool_calls] = msg[:tool_calls] || msg["tool_calls"]
            end
            
            base_msg
          end
        end
      end

      def prepare_tools(tools)
        tools.map do |tool|
          if tool.respond_to?(:to_h)
            tool_hash = tool.to_h
            {
              type: "function",
              function: {
                name: tool_hash[:name],
                description: tool_hash[:description],
                parameters: tool_hash[:parameters] || tool_hash[:input_schema]
              }
            }
          else
            tool
          end
        end
      end

      def add_model_parameters(body, kwargs)
        # Standard OpenAI parameters
        body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        body[:max_tokens] = kwargs[:max_tokens] || kwargs[:max_completion_tokens]
        body[:top_p] = kwargs[:top_p] if kwargs[:top_p]
        body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]
        body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
        body[:stop] = kwargs[:stop] if kwargs[:stop]
        body[:seed] = kwargs[:seed] if kwargs[:seed]
        
        # Response format
        if kwargs[:response_format]
          body[:response_format] = kwargs[:response_format]
        end

        # Provider-specific parameters can be passed through extra_body
        if kwargs[:extra_body].is_a?(Hash)
          body.merge!(kwargs[:extra_body])
        end

        # Some providers need special handling
        handle_provider_specifics(body, kwargs)
      end

      def handle_provider_specifics(body, kwargs)
        case @model
        when /^anthropic\//
          # Anthropic uses max_tokens instead of max_completion_tokens
          body[:max_tokens] ||= 4096
          
          # Anthropic-specific system prompt handling
          if body[:messages].first && body[:messages].first[:role] == "system"
            system_msg = body[:messages].shift
            body[:system] = system_msg[:content]
          end
          
        when /^gemini\//
          # Gemini specific adjustments
          body[:generation_config] = {
            temperature: body.delete(:temperature),
            max_output_tokens: body.delete(:max_tokens),
            top_p: body.delete(:top_p)
          }.compact
          
        when /^cohere\//
          # Cohere specific parameters
          body[:max_tokens] ||= 4000
          body[:connectors] = kwargs[:connectors] if kwargs[:connectors]
          
        when /^replicate\//
          # Replicate needs input wrapped
          body[:input] = {
            prompt: body[:messages].map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n")
          }
          body.delete(:messages)
        end
      end

      def handle_error(status_code, error_body)
        error_message = extract_error_message(error_body)
        
        case status_code
        when 400
          raise APIError, "Bad request: #{error_message}"
        when 401
          raise AuthenticationError, "Authentication failed: #{error_message}"
        when 403
          raise APIError, "Forbidden: #{error_message}"
        when 404
          raise APIError, "Model not found: #{@model}. #{error_message}"
        when 429
          raise RateLimitError, "Rate limit exceeded: #{error_message}"
        when 500..599
          raise ServerError, "LiteLLM server error: #{error_message}"
        else
          raise APIError, "LiteLLM error (#{status_code}): #{error_message}"
        end
      end

      def extract_error_message(error_body)
        case error_body
        when Hash
          error_body.dig("error", "message") || 
          error_body["error"] || 
          error_body["message"] || 
          error_body.to_s
        when String
          error_body
        else
          "Unknown error"
        end
      end
    end

    # Convenience class for easy setup with LiteLLM
    class LiteLLM
      # List of popular models available through LiteLLM
      MODELS = {
        # OpenAI
        gpt4o: "openai/gpt-4o",
        gpt4: "openai/gpt-4",
        gpt35: "openai/gpt-3.5-turbo",
        
        # Anthropic
        claude3_opus: "anthropic/claude-3-opus-20240229",
        claude3_sonnet: "anthropic/claude-3-sonnet-20240229",
        claude3_haiku: "anthropic/claude-3-haiku-20240307",
        claude2: "anthropic/claude-2.1",
        
        # Google
        gemini_pro: "gemini/gemini-pro",
        gemini_pro_vision: "gemini/gemini-pro-vision",
        palm2: "palm/chat-bison",
        
        # Cohere
        command: "cohere/command",
        command_light: "cohere/command-light",
        
        # Together AI
        llama2_70b: "together_ai/togethercomputer/llama-2-70b-chat",
        mistral_7b: "together_ai/mistralai/Mistral-7B-Instruct-v0.1",
        
        # Replicate
        llama2_13b: "replicate/meta/llama-2-13b-chat",
        
        # Ollama (local)
        ollama_llama2: "ollama/llama2",
        ollama_mistral: "ollama/mistral",
        ollama_codellama: "ollama/codellama"
      }.freeze

      # Create a LiteLLM provider for a specific model
      def self.provider(model_key_or_name, **options)
        model_name = MODELS[model_key_or_name] || model_key_or_name.to_s
        LitellmProvider.new(model: model_name, **options)
      end

      # Get all available models
      def self.available_models
        MODELS
      end
    end
  end
end
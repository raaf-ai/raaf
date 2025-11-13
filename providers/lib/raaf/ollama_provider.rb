# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "securerandom"
# ModelInterface is required from raaf-core gem

module RAAF
  module Models
    # Provider-specific error classes
    class ConnectionError < APIError; end
    class ModelNotFoundError < APIError; end

    # OllamaProvider enables local LLM usage through Ollama's API
    #
    # Ollama provides a local LLM runtime with HTTP API for running models
    # like Llama, Mistral, and Gemma without external API dependencies.
    #
    # @example Basic usage
    #   provider = RAAF::Models::OllamaProvider.new
    #   agent = RAAF::Agent.new(name: "Assistant", model: "llama3.2")
    #   runner = RAAF::Runner.new(agent: agent, provider: provider)
    #   result = runner.run("Hello!")
    #
    # @example Custom host
    #   provider = RAAF::Models::OllamaProvider.new(
    #     host: "http://192.168.1.100:11434"
    #   )
    #
    # @example Custom timeout
    #   provider = RAAF::Models::OllamaProvider.new(timeout: 300)
    class OllamaProvider < ModelInterface
      # Default Ollama API host
      API_DEFAULT_HOST = "http://localhost:11434"

      # Default timeout for Ollama requests (120 seconds for model loading)
      DEFAULT_TIMEOUT = 120

      # Initialize OllamaProvider with optional configuration
      #
      # @param host [String, nil] Ollama API host (default: localhost:11434)
      # @param timeout [Integer, nil] Request timeout in seconds (default: 120)
      # @param options [Hash] Additional options
      #
      # Configuration priority:
      #   1. Explicit parameter (highest)
      #   2. Environment variable
      #   3. Default value (lowest)
      #
      # Environment variables:
      #   - OLLAMA_HOST: API host
      #   - RAAF_OLLAMA_TIMEOUT: Request timeout
      def initialize(host: nil, timeout: nil, **options)
        super
        @host = host || ENV["OLLAMA_HOST"] || API_DEFAULT_HOST
        @http_timeout = timeout || ENV.fetch("RAAF_OLLAMA_TIMEOUT", DEFAULT_TIMEOUT.to_s).to_i
      end

      # Get the provider name
      #
      # @return [String] "Ollama"
      def provider_name
        "Ollama"
      end

      # Get supported models
      #
      # Ollama is extensible and supports any model pulled via `ollama pull`.
      # Returns empty array to indicate no hardcoded model list.
      #
      # @return [Array<String>] Empty array (no hardcoded model list)
      def supported_models
        []
      end

      # Read-only accessor for http_timeout to support RSpec testing
      #
      # @return [Integer] Current HTTP timeout in seconds
      attr_reader :http_timeout

      # Perform chat completion using Ollama
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Ollama model to use (e.g., "llama3.2")
      # @param tools [Array<Hash>, nil] Tools/functions (optional)
      # @param stream [Boolean] Whether to stream the response
      # @param kwargs [Hash] Additional parameters (temperature, max_tokens, etc.)
      # @return [Hash] Response in OpenAI-compatible format
      def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        # Log model loading (first request may take time)
        log_info("Loading model #{model} (may take 5-10 seconds)...",
                 provider: "OllamaProvider", model: model)

        body = {
          model: model,
          messages: messages,
          stream: stream
        }

        # Add tools if provided
        body[:tools] = prepare_tools(tools) if tools && !tools.empty?

        # Add optional parameters
        options = build_options(kwargs)
        body[:options] = options unless options.empty?

        make_request(body)
      end

      # Perform streaming chat completion using Ollama
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Ollama model to use
      # @param tools [Array<Hash>, nil] Tools/functions (optional)
      # @param kwargs [Hash] Additional parameters
      # @yield [Hash] Streaming chunks with type, content, and metadata
      # @return [Hash] Final accumulated response
      def perform_stream_completion(messages:, model:, tools: nil, **kwargs, &block)
        log_info("Loading model #{model} (may take 5-10 seconds)...",
                 provider: "OllamaProvider", model: model)

        body = {
          model: model,
          messages: messages,
          stream: true
        }

        # Add tools if provided
        body[:tools] = prepare_tools(tools) if tools && !tools.empty?

        # Add optional parameters
        options = build_options(kwargs)
        body[:options] = options unless options.empty?

        stream_response(body, &block)
      end

      private

      # Build Ollama options from kwargs
      #
      # Maps OpenAI-style parameters to Ollama format
      #
      # @param kwargs [Hash] Optional parameters
      # @return [Hash] Ollama options
      def build_options(kwargs)
        options = {}

        # Map standard parameters to Ollama format
        options[:temperature] = kwargs[:temperature] if kwargs[:temperature]
        options[:top_p] = kwargs[:top_p] if kwargs[:top_p]
        options[:num_predict] = kwargs[:max_tokens] if kwargs[:max_tokens]
        options[:stop] = kwargs[:stop] if kwargs[:stop]

        options
      end

      # Prepare tools for Ollama (OpenAI-compatible format)
      #
      # @param tools [Array<Hash>] RAAF tools
      # @return [Array<Hash>] Ollama-formatted tools
      def prepare_tools(tools)
        tools.map do |tool|
          {
            type: "function",
            function: {
              name: tool[:name] || tool["name"],
              description: tool[:description] || tool["description"],
              parameters: tool[:parameters] || tool["parameters"]
            }
          }
        end
      end

      # Make HTTP request to Ollama API
      #
      # @param body [Hash] Request body
      # @return [Hash] Parsed response in OpenAI format
      def make_request(body)
        uri = URI("#{@host}/api/chat")
        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = @http_timeout

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = body.to_json

        response = http.request(request)

        handle_api_error(response) unless response.code.start_with?("2")

        parse_response(JSON.parse(response.body))
      rescue Errno::ECONNREFUSED
        raise ConnectionError, "Ollama not running. Start with: ollama serve"
      end

      # Parse Ollama response to OpenAI format
      #
      # @param ollama_response [Hash] Raw Ollama response
      # @return [Hash] OpenAI-compatible response
      def parse_response(ollama_response)
        {
          "content" => ollama_response.dig("message", "content"),
          "tool_calls" => parse_tool_calls(ollama_response),
          "model" => ollama_response["model"],
          "finish_reason" => map_finish_reason(ollama_response["done_reason"]),
          "usage" => {
            "prompt_tokens" => ollama_response["prompt_eval_count"] || 0,
            "completion_tokens" => ollama_response["eval_count"] || 0,
            "total_tokens" => (ollama_response["prompt_eval_count"] || 0) + (ollama_response["eval_count"] || 0),
            # Ollama-specific metadata
            "total_duration" => ollama_response["total_duration"],
            "load_duration" => ollama_response["load_duration"],
            "prompt_eval_count" => ollama_response["prompt_eval_count"],
            "eval_count" => ollama_response["eval_count"]
          }
        }
      end

      # Parse tool calls from Ollama response
      #
      # @param ollama_response [Hash] Ollama response
      # @return [Array<Hash>] Tool calls in OpenAI format
      def parse_tool_calls(ollama_response)
        tool_calls = ollama_response.dig("message", "tool_calls")
        return [] unless tool_calls

        tool_calls.map do |call|
          {
            "id" => call["id"] || SecureRandom.uuid,
            "type" => "function",
            "function" => {
              "name" => call.dig("function", "name"),
              "arguments" => call.dig("function", "arguments")
            }
          }
        end
      end

      # Map Ollama finish reason to OpenAI format
      #
      # @param ollama_reason [String, nil] Ollama done_reason
      # @return [String] OpenAI finish_reason
      def map_finish_reason(ollama_reason)
        case ollama_reason
        when "stop", nil then "stop"
        when "length" then "length"
        else "stop"
        end
      end

      # Handle API errors
      #
      # @param response [Net::HTTPResponse] HTTP response
      # @raise [ModelNotFoundError, APIError] Appropriate error
      def handle_api_error(response)
        case response.code
        when "404"
          raise ModelNotFoundError, "Model not found. Pull with: ollama pull <model>"
        else
          raise APIError, "Ollama API error: #{response.code} - #{response.body}"
        end
      end

      # Stream response from Ollama
      #
      # Ollama streams responses as newline-delimited JSON chunks.
      # Each chunk contains incremental content or tool calls.
      #
      # @param body [Hash] Request body
      # @yield [Hash] Streaming chunks
      # @return [Hash] Final accumulated response
      def stream_response(body, &block)
        accumulated_content = ""
        accumulated_tool_calls = []
        final_metadata = {}

        make_streaming_request(body) do |chunk|
          next if chunk.strip.empty?

          begin
            parsed = JSON.parse(chunk)

            # Handle content streaming
            if parsed.dig("message", "content")
              content = parsed["message"]["content"]
              accumulated_content += content

              yield({
                type: "content",
                content: content,
                accumulated_content: accumulated_content
              }) if block_given? && !content.empty?
            end

            # Handle tool calls streaming
            if parsed.dig("message", "tool_calls")
              tool_calls = parsed["message"]["tool_calls"]
              accumulated_tool_calls.concat(tool_calls)

              yield({
                type: "tool_calls",
                tool_calls: tool_calls,
                accumulated_tool_calls: accumulated_tool_calls
              }) if block_given?
            end

            # Handle final chunk with metadata
            if parsed["done"]
              final_metadata = {
                model: parsed["model"],
                finish_reason: map_finish_reason(parsed["done_reason"]),
                usage: {
                  "prompt_tokens" => parsed["prompt_eval_count"] || 0,
                  "completion_tokens" => parsed["eval_count"] || 0,
                  "total_tokens" => (parsed["prompt_eval_count"] || 0) + (parsed["eval_count"] || 0),
                  "total_duration" => parsed["total_duration"],
                  "load_duration" => parsed["load_duration"],
                  "prompt_eval_count" => parsed["prompt_eval_count"],
                  "eval_count" => parsed["eval_count"]
                }
              }

              yield({
                type: "finish",
                finish_reason: final_metadata[:finish_reason],
                usage: final_metadata[:usage]
              }) if block_given?
            end
          rescue JSON::ParserError => e
            log_warn("Failed to parse streaming chunk: #{e.message}",
                     provider: "OllamaProvider", chunk: chunk[0..100])
          end
        end

        # Return final accumulated response
        {
          content: accumulated_content,
          tool_calls: parse_tool_calls({ "message" => { "tool_calls" => accumulated_tool_calls } }),
          model: final_metadata[:model],
          finish_reason: final_metadata[:finish_reason],
          usage: final_metadata[:usage]
        }
      end

      # Make streaming HTTP request to Ollama API
      #
      # @param body [Hash] Request body
      # @yield [String] Raw chunk data (newline-delimited JSON)
      def make_streaming_request(body)
        uri = URI("#{@host}/api/chat")
        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = @http_timeout

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = body.to_json

        http.request(request) do |response|
          handle_api_error(response) unless response.code.start_with?("2")

          response.read_body do |chunk|
            # Ollama sends newline-delimited JSON
            chunk.each_line do |line|
              yield(line.strip) if block_given?
            end
          end
        end
      rescue Errno::ECONNREFUSED
        raise ConnectionError, "Ollama not running. Start with: ollama serve"
      end
    end
  end
end

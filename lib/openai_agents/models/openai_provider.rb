# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "interface"

module OpenAIAgents
  module Models
    class OpenAIProvider < ModelInterface
      DEFAULT_API_BASE = "https://api.openai.com/v1"

      SUPPORTED_MODELS = %w[
        gpt-4o gpt-4o-mini gpt-4-turbo gpt-4 gpt-4-32k
        gpt-3.5-turbo gpt-3.5-turbo-16k
        o1-preview o1-mini
      ].freeze

      # rubocop:disable Lint/MissingSuper
      def initialize(api_key: nil, api_base: nil, **options)
        @api_key = api_key || ENV.fetch("OPENAI_API_KEY", nil)
        @api_base = api_base || ENV["OPENAI_API_BASE"] || DEFAULT_API_BASE
        @options = options

        raise AuthenticationError, "OpenAI API key is required" unless @api_key
      end
      # rubocop:enable Lint/MissingSuper

      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        validate_model(model)

        uri = URI("#{@api_base}/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"

        body = {
          model: model,
          messages: messages,
          stream: stream,
          **kwargs
        }
        body[:tools] = prepare_tools(tools) if tools

        request.body = JSON.generate(body)

        response = http.request(request)

        handle_api_error(response, "OpenAI") unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end

      def stream_completion(messages:, model:, tools: nil, &block)
        validate_model(model)

        uri = URI("#{@api_base}/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "text/event-stream"

        body = {
          model: model,
          messages: messages,
          stream: true
        }
        body[:tools] = prepare_tools(tools) if tools

        request.body = JSON.generate(body)

        accumulated_content = String.new
        accumulated_tool_calls = {}

        http.request(request) do |response|
          handle_api_error(response, "OpenAI") unless response.is_a?(Net::HTTPSuccess)

          response.read_body do |chunk|
            process_stream_chunk(chunk, accumulated_content, accumulated_tool_calls, &block)
          end
        end

        {
          content: accumulated_content,
          tool_calls: accumulated_tool_calls.values
        }
      end

      def supported_models
        SUPPORTED_MODELS
      end

      def provider_name
        "OpenAI"
      end

      private

      def process_stream_chunk(chunk, accumulated_content, accumulated_tool_calls, &block)
        chunk.split("\n").each do |line|
          next unless line.start_with?("data: ")

          data = line[6..].strip
          next if data.empty? || data == "[DONE]"

          begin
            json_data = JSON.parse(data)
            delta = json_data.dig("choices", 0, "delta")

            if delta
              process_content_delta(delta, accumulated_content, &block)
              process_tool_call_delta(delta, accumulated_tool_calls, &block)
              process_finish_reason(json_data, accumulated_content, accumulated_tool_calls, &block)
            end
          rescue JSON::ParserError
            next
          end
        end
      end

      def process_content_delta(delta, accumulated_content)
        return unless delta["content"]

        accumulated_content << delta["content"]
        return unless block_given?

        yield({
          type: "content",
          content: delta["content"],
          accumulated_content: accumulated_content
        })
      end

      def process_tool_call_delta(delta, accumulated_tool_calls)
        return unless delta["tool_calls"]

        delta["tool_calls"].each do |tool_call|
          index = tool_call["index"]
          accumulated_tool_calls[index] ||= {
            "id" => "",
            "type" => "function",
            "function" => { "name" => "", "arguments" => "" }
          }

          accumulated_tool_calls[index]["id"] += tool_call["id"] if tool_call["id"]

          if tool_call.dig("function", "name")
            accumulated_tool_calls[index]["function"]["name"] += tool_call["function"]["name"]
          end

          if tool_call.dig("function", "arguments")
            accumulated_tool_calls[index]["function"]["arguments"] += tool_call["function"]["arguments"]
          end

          next unless block_given?

          yield({
            type: "tool_call",
            tool_call: tool_call,
            accumulated_tool_calls: accumulated_tool_calls.values
          })
        end
      end

      def process_finish_reason(json_data, accumulated_content, accumulated_tool_calls)
        finish_reason = json_data.dig("choices", 0, "finish_reason")
        return unless finish_reason

        return unless block_given?

        yield({
          type: "finish",
          finish_reason: finish_reason,
          accumulated_content: accumulated_content,
          accumulated_tool_calls: accumulated_tool_calls.values
        })
      end
    end
  end
end

# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "interface"

module OpenAIAgents
  module Models
    class AnthropicProvider < ModelInterface
      DEFAULT_API_BASE = "https://api.anthropic.com"

      SUPPORTED_MODELS = %w[
        claude-3-5-sonnet-20241022 claude-3-5-haiku-20241022
        claude-3-opus-20240229 claude-3-sonnet-20240229 claude-3-haiku-20240307
      ].freeze

      # rubocop:disable Lint/MissingSuper
      def initialize(api_key: nil, api_base: nil, **options)
        @api_key = api_key || ENV.fetch("ANTHROPIC_API_KEY", nil)
        @api_base = api_base || ENV["ANTHROPIC_API_BASE"] || DEFAULT_API_BASE
        @options = options

        raise AuthenticationError, "Anthropic API key is required" unless @api_key
      end
      # rubocop:enable Lint/MissingSuper

      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        validate_model(model)

        uri = URI("#{@api_base}/v1/messages")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["x-api-key"] = @api_key
        request["Content-Type"] = "application/json"
        request["anthropic-version"] = "2023-06-01"

        # Convert OpenAI format to Anthropic format
        system_message, user_messages = extract_system_message(messages)

        body = {
          model: model,
          messages: user_messages,
          max_tokens: kwargs[:max_tokens] || 1024,
          stream: stream
        }
        body[:system] = system_message if system_message
        body[:tools] = convert_tools_to_anthropic(tools) if tools

        # Add response_format support - Anthropic doesn't support JSON schema directly
        # but we can enhance the system message for structured output
        if kwargs[:response_format] && kwargs[:response_format][:type] == "json_schema"
          # rubocop:disable Layout/LineLength
          json_instruction = "\n\nIMPORTANT: Please respond with valid JSON only. Do not include any other text or explanation."
          # rubocop:enable Layout/LineLength
          if kwargs[:response_format][:json_schema] && kwargs[:response_format][:json_schema][:schema]
            schema = kwargs[:response_format][:json_schema][:schema]
            json_instruction += " Follow this JSON schema: #{schema.to_json}"
          end
          body[:system] = (body[:system] || "") + json_instruction
        end

        request.body = JSON.generate(body)

        response = http.request(request)

        handle_api_error(response, "Anthropic") unless response.is_a?(Net::HTTPSuccess)

        result = JSON.parse(response.body)
        convert_anthropic_to_openai_format(result)
      end

      def stream_completion(messages:, model:, tools: nil, &block)
        validate_model(model)

        uri = URI("#{@api_base}/v1/messages")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["x-api-key"] = @api_key
        request["Content-Type"] = "application/json"
        request["anthropic-version"] = "2023-06-01"
        request["Accept"] = "text/event-stream"

        system_message, user_messages = extract_system_message(messages)

        body = {
          model: model,
          messages: user_messages,
          max_tokens: 1024,
          stream: true
        }
        body[:system] = system_message if system_message
        body[:tools] = convert_tools_to_anthropic(tools) if tools

        # Add response_format support for streaming
        if kwargs[:response_format] && kwargs[:response_format][:type] == "json_schema"
          # rubocop:disable Layout/LineLength
          json_instruction = "\n\nIMPORTANT: Please respond with valid JSON only. Do not include any other text or explanation."
          # rubocop:enable Layout/LineLength
          if kwargs[:response_format][:json_schema] && kwargs[:response_format][:json_schema][:schema]
            schema = kwargs[:response_format][:json_schema][:schema]
            json_instruction += " Follow this JSON schema: #{schema.to_json}"
          end
          body[:system] = (body[:system] || "") + json_instruction
        end

        request.body = JSON.generate(body)

        accumulated_content = ""

        http.request(request) do |response|
          handle_api_error(response, "Anthropic") unless response.is_a?(Net::HTTPSuccess)

          response.read_body do |chunk|
            process_anthropic_stream_chunk(chunk, accumulated_content, &block)
          end
        end

        { content: accumulated_content, tool_calls: [] }
      end

      def supported_models
        SUPPORTED_MODELS
      end

      def provider_name
        "Anthropic"
      end

      private

      def extract_system_message(messages)
        system_message = nil
        user_messages = []

        messages.each do |message|
          if message[:role] == "system"
            system_message = message[:content]
          else
            user_messages << message
          end
        end

        [system_message, user_messages]
      end

      def convert_tools_to_anthropic(tools)
        return [] unless tools

        tools.map do |tool|
          if tool.is_a?(Hash) && tool[:type] == "function"
            {
              name: tool.dig(:function, :name),
              description: tool.dig(:function, :description),
              input_schema: tool.dig(:function, :parameters) || {}
            }
          else
            tool
          end
        end
      end

      def convert_anthropic_to_openai_format(result)
        {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => result["content"]&.first&.dig("text") || ""
            },
            "finish_reason" => result["stop_reason"]
          }],
          "usage" => result["usage"],
          "model" => result["model"]
        }
      end

      def process_anthropic_stream_chunk(chunk, accumulated_content)
        chunk.split("\n").each do |line|
          next unless line.start_with?("data: ")

          data = line[6..].strip
          next if data.empty?

          begin
            json_data = JSON.parse(data)

            if json_data["type"] == "content_block_delta"
              delta = json_data.dig("delta", "text")
              if delta
                accumulated_content << delta
                if block_given?
                  yield({
                    type: "content",
                    content: delta,
                    accumulated_content: accumulated_content
                  })
                end
              end
            elsif json_data["type"] == "message_stop"
              if block_given?
                yield({
                  type: "finish",
                  finish_reason: "stop",
                  accumulated_content: accumulated_content,
                  accumulated_tool_calls: []
                })
              end
            end
          rescue JSON::ParserError
            next
          end
        end
      end
    end
  end
end

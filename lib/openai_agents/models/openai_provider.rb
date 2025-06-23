# frozen_string_literal: true

require "openai"
require_relative "interface"

module OpenAIAgents
  module Models
    class OpenAIProvider < ModelInterface
      SUPPORTED_MODELS = %w[
        gpt-4o gpt-4o-mini gpt-4-turbo gpt-4 gpt-4-32k
        gpt-3.5-turbo gpt-3.5-turbo-16k
        o1-preview o1-mini
      ].freeze

      # rubocop:disable Lint/MissingSuper
      def initialize(api_key: nil, api_base: nil, **options)
        @api_key = api_key || ENV.fetch("OPENAI_API_KEY", nil)
        @api_base = api_base || ENV["OPENAI_API_BASE"] || "https://api.openai.com/v1"
        raise AuthenticationError, "OpenAI API key is required" unless @api_key

        @client = OpenAI::Client.new(
          api_key: @api_key,
          base_url: @api_base,
          **options
        )
      end
      # rubocop:enable Lint/MissingSuper

      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        validate_model(model)

        parameters = {
          model: model,
          messages: messages,
          stream: stream,
          **kwargs
        }
        parameters[:tools] = prepare_tools(tools) if tools

        begin
          @client.chat.completions.create(**parameters)
        rescue OpenAI::Errors::Error => e
          handle_openai_error(e)
        end
      end

      def stream_completion(messages:, model:, tools: nil, &block)
        validate_model(model)

        parameters = {
          model: model,
          messages: messages,
          stream: true
        }
        parameters[:tools] = prepare_tools(tools) if tools

        accumulated_content = String.new
        accumulated_tool_calls = {}

        begin
          stream = @client.chat.completions.stream_raw(parameters)
          stream.each do |chunk|
            process_openai_chunk(chunk, accumulated_content, accumulated_tool_calls, &block)
          end
        rescue OpenAI::Errors::Error => e
          handle_openai_error(e)
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

      def process_openai_chunk(chunk, accumulated_content, accumulated_tool_calls, &block)
        return if chunk.nil? || chunk.empty?

        delta = chunk.dig("choices", 0, "delta")
        return unless delta

        process_content_delta(delta, accumulated_content, &block)
        process_tool_call_delta(delta, accumulated_tool_calls, &block)
        process_finish_reason(chunk, accumulated_content, accumulated_tool_calls, &block)
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

      def process_finish_reason(chunk, accumulated_content, accumulated_tool_calls)
        finish_reason = chunk.dig("choices", 0, "finish_reason")
        return unless finish_reason

        return unless block_given?

        yield({
          type: "finish",
          finish_reason: finish_reason,
          accumulated_content: accumulated_content,
          accumulated_tool_calls: accumulated_tool_calls.values
        })
      end

      def handle_openai_error(error)
        case error
        when OpenAI::Errors::AuthenticationError
          raise AuthenticationError, "Invalid API key for OpenAI"
        when OpenAI::Errors::RateLimitError
          raise RateLimitError, "Rate limit exceeded for OpenAI"
        when OpenAI::Errors::InternalServerError
          raise ServerError, "Server error from OpenAI: #{error.message}"
        else
          raise APIError, "API error from OpenAI: #{error.message}"
        end
      end
    end
  end
end

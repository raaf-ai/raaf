# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "interface"
require_relative "../tracing/spans"

module OpenAIAgents
  module Models
    # OpenAI Responses API provider - matches Python default behavior
    class ResponsesProvider < ModelInterface
      SUPPORTED_MODELS = %w[
        gpt-4o gpt-4o-mini gpt-4-turbo gpt-4
        o1-preview o1-mini
      ].freeze

      def initialize(api_key: nil, api_base: nil, **_options)
        @api_key = api_key || ENV.fetch("OPENAI_API_KEY", nil)
        @api_base = api_base || ENV["OPENAI_API_BASE"] || "https://api.openai.com/v1"
        raise AuthenticationError, "OpenAI API key is required" unless @api_key
      end

      def chat_completion(messages:, model:, tools: nil, stream: false, **)
        validate_model(model)
        responses_completion(messages: messages, model: model, tools: tools, **)
      end

      private

      def validate_model(model)
        return if SUPPORTED_MODELS.include?(model)

        warn "Model #{model} is not in the list of supported models: #{SUPPORTED_MODELS.join(", ")}"
      end

      def responses_completion(messages:, model:, **kwargs)
        # Get the current tracer from the trace context
        current_tracer = OpenAIAgents.tracer

        # Check if tracing is actually enabled (not a NoOpTracer)
        if current_tracer && !current_tracer.is_a?(OpenAIAgents::Tracing::NoOpTracer)
          # Create a response span exactly like Python - only response_id attribute
          current_tracer.start_span("POST /v1/responses", kind: :response) do |response_span|
            # Make the actual API call
            response = call_responses_api(
              model: model,
              input: extract_input_from_messages(messages),
              instructions: extract_system_instructions(messages),
              **kwargs
            )

            # Set only the response_id attribute like Python ResponseSpanData.export()
            response_span.set_attribute("response_id", response["id"]) if response && response["id"]

            # Convert response to chat completion format for compatibility
            convert_response_to_chat_format(response)
          end

        else
          # No tracing, just make the API call directly
          response = call_responses_api(
            model: model,
            input: extract_input_from_messages(messages),
            instructions: extract_system_instructions(messages),
            **kwargs
          )
          convert_response_to_chat_format(response)
        end
      end

      def call_responses_api(model:, input:, instructions: nil, **kwargs)
        uri = URI("#{@api_base}/responses")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "Agents/Ruby #{OpenAIAgents::VERSION}"

        body = {
          model: model,
          input: input
        }
        body[:instructions] = instructions if instructions

        # Convert response_format to text.format for Responses API (matching Python implementation)
        if kwargs[:response_format]
          response_format = kwargs[:response_format]
          if response_format[:type] == "json_schema" && response_format[:json_schema]
            body[:text] = {
              format: {
                type: "json_schema",
                name: response_format[:json_schema][:name],
                schema: response_format[:json_schema][:schema],
                strict: response_format[:json_schema][:strict]
              }
            }
          end
          # Remove response_format from kwargs since we converted it to text
          kwargs_without_response_format = kwargs.dup
          kwargs_without_response_format.delete(:response_format)
          body.merge!(kwargs_without_response_format)
        else
          body.merge!(kwargs)
        end

        request.body = body.to_json

        response = http.request(request)

        unless response.code.start_with?("2")
          raise APIError, "Responses API returned #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      end

      def extract_input_from_messages(messages)
        # Extract the last user message as input (matching Python behavior)
        user_msg = messages.reverse.find { |m| m[:role] == "user" }
        user_msg&.dig(:content) || ""
      end

      def extract_system_instructions(messages)
        system_msg = messages.find { |m| m[:role] == "system" }
        system_msg&.dig(:content)
      end

      def convert_response_to_chat_format(response)
        # Convert OpenAI Responses API format to chat completion format
        # for compatibility with existing Ruby code
        return nil unless response && response["output"]

        # Extract the text content from response output
        # New Responses API format: output is array of message objects with content arrays
        content = if response["output"].is_a?(Array) && !response["output"].empty?
                    # Get the first output item (should be the assistant message)
                    output_item = response["output"][0]
                    if output_item.is_a?(Hash) && output_item["content"].is_a?(Array)
                      # Extract text from content array
                      output_item["content"].map do |content_item|
                        if content_item.is_a?(Hash) && content_item["type"] == "output_text"
                          content_item["text"] || ""
                        else
                          content_item.to_s
                        end
                      end.join
                    else
                      # Fallback for older format
                      output_item["text"] || output_item["content"] || output_item.to_s
                    end
                  else
                    # Fallback for other formats
                    response["output"].to_s
                  end

        {
          "id" => response["id"],
          "object" => "chat.completion",
          "created" => Time.now.to_i,
          "model" => response["model"] || "gpt-4o",
          "choices" => [
            {
              "index" => 0,
              "message" => {
                "role" => "assistant",
                "content" => content
              },
              "finish_reason" => "stop"
            }
          ],
          "usage" => response["usage"] || {
            "prompt_tokens" => 0,
            "completion_tokens" => 0,
            "total_tokens" => 0
          }
        }
      end
    end
  end
end

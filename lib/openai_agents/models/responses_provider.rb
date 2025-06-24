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

      def initialize(api_key: nil, api_base: nil, **options)
        @api_key = api_key || ENV.fetch("OPENAI_API_KEY", nil)
        @api_base = api_base || ENV["OPENAI_API_BASE"] || "https://api.openai.com/v1"
        raise AuthenticationError, "OpenAI API key is required" unless @api_key
      end

      def chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        validate_model(model)
        responses_completion(messages: messages, model: model, tools: tools, **kwargs)
      end

      private

      def validate_model(model)
        return if SUPPORTED_MODELS.include?(model)
        
        warn "Model #{model} is not in the list of supported models: #{SUPPORTED_MODELS.join(', ')}"
      end

      def responses_completion(messages:, model:, **kwargs)
        # Get the current tracer from the trace context
        current_tracer = OpenAIAgents.tracer
        
        if current_tracer
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
            if response && response["id"]
              response_span.set_attribute("response_id", response["id"])
            end
            
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
        body.merge!(kwargs)

        request.body = body.to_json

        response = http.request(request)
        
        if response.code.start_with?("2")
          JSON.parse(response.body)
        else
          raise APIError, "Responses API returned #{response.code}: #{response.body}"
        end
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
        content = if response["output"].is_a?(Array)
                   response["output"].map { |item| 
                     if item.is_a?(Hash)
                       item["text"] || item["content"] || item.to_s
                     else
                       item.to_s 
                     end
                   }.join("")
                 elsif response["output"].is_a?(Hash)
                   response["output"]["text"] || response["output"]["content"] || response["output"].to_s
                 else
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
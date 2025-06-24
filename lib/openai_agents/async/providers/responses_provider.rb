# frozen_string_literal: true

require "async"
require "async/http"
require "async/http/endpoint"
require_relative "../../models/responses_provider"
require_relative "../base"

module OpenAIAgents
  module Async
    module Providers
      # Async version of ResponsesProvider using Async::HTTP
      class ResponsesProvider < OpenAIAgents::Models::ResponsesProvider
        include OpenAIAgents::Async::Base

        def initialize(api_key: nil, base_url: nil, default_model: nil)
          super
          @endpoint = Async::HTTP::Endpoint.parse(@base_url)
          @client = nil
        end

        # Async version of chat_completion
        async def async_chat_completion(messages:, model: nil, tools: nil, output_schema: nil, **kwargs)
          model ||= @default_model || "gpt-4o-mini"
          
          # Build request body
          body = build_request_body(messages, model, tools, output_schema, kwargs)
          
          # Make async HTTP request
          response = await make_async_request("/v1/responses", body)
          
          # Parse and return response
          parse_response(response)
        end

        # Synchronous wrapper
        def chat_completion(**kwargs)
          if in_async_context?
            async_chat_completion(**kwargs).wait
          else
            # Fall back to synchronous implementation
            super
          end
        end

        private

        def async_client
          @client ||= Async::HTTP::Client.new(@endpoint)
        end

        async def make_async_request(path, body)
          headers = build_headers
          
          # Create request
          request = Async::HTTP::Request.new(
            @endpoint.scheme,
            @endpoint.authority,
            :post,
            path,
            nil,
            Async::HTTP::Headers.new(headers),
            Async::HTTP::Body::Buffered.wrap(JSON.generate(body))
          )

          # Send request and get response
          response = await async_client.call(request)
          
          # Check response status
          unless response.success?
            error_body = await response.read
            handle_error(response.status, error_body)
          end

          # Read and parse response body
          response_body = await response.read
          JSON.parse(response_body)
        rescue Async::TimeoutError => e
          raise APIError, "Request timeout: #{e.message}"
        rescue StandardError => e
          raise APIError, "Request failed: #{e.message}"
        end

        def build_headers
          {
            "Content-Type" => "application/json",
            "Authorization" => "Bearer #{@api_key}",
            "OpenAI-Beta" => "agents-v1"
          }
        end

        def build_request_body(messages, model, tools, output_schema, kwargs)
          body = {
            model: model,
            messages: prepare_messages(messages)
          }

          # Add tools if provided
          if tools && !tools.empty?
            body[:tools] = tools.map { |tool| prepare_tool(tool) }
          end

          # Add output schema if provided
          if output_schema
            schema = StrictSchema.ensure_strict_json_schema(output_schema)
            body[:response_format] = {
              type: "json_schema",
              json_schema: {
                name: "final_output",
                strict: true,
                schema: schema
              }
            }
          end

          # Add additional parameters
          body.merge!(kwargs.slice(:temperature, :max_completion_tokens, :top_p, :frequency_penalty, :presence_penalty))
          
          body
        end

        def parse_response(response)
          # Convert from Responses API format to chat completion format
          if response["choices"] && response["choices"].first
            choice = response["choices"].first
            message = choice["message"]
            
            # Build response in expected format
            {
              "id" => response["id"],
              "object" => "chat.completion",
              "created" => response["created"],
              "model" => response["model"],
              "choices" => [{
                "index" => 0,
                "message" => message,
                "finish_reason" => choice["finish_reason"]
              }],
              "usage" => response["usage"]
            }
          else
            response
          end
        end

        def handle_error(status, body)
          error_data = JSON.parse(body) rescue { "error" => { "message" => body } }
          error_message = error_data.dig("error", "message") || "Unknown error"

          case status
          when 401
            raise AuthenticationError, "Invalid API key: #{error_message}"
          when 429
            raise RateLimitError, "Rate limit exceeded: #{error_message}"
          when 500..599
            raise ServerError, "Server error: #{error_message}"
          else
            raise APIError, "API error (#{status}): #{error_message}"
          end
        end
      end
    end
  end
end
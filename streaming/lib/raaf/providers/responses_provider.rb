# frozen_string_literal: true

require "async"
require "async/http"
require "async/http/endpoint"
require "json"
require_relative "../../models/responses_provider"
require_relative "../base"

module RubyAIAgentsFactory
  module Async
    module Providers
      # Async version of ResponsesProvider using Async::HTTP
      class ResponsesProvider < RubyAIAgentsFactory::Models::ResponsesProvider
        include RubyAIAgentsFactory::Async::Base

        def initialize(api_key: nil, base_url: nil, default_model: nil)
          super(api_key: api_key, api_base: base_url)
          @default_model = default_model
          @endpoint = ::Async::HTTP::Endpoint.parse(@api_base)
          @client = nil
        end

        # Async version of chat_completion
        def async_chat_completion(messages:, model: nil, tools: nil, response_format: nil, **kwargs)
          model ||= @default_model || "gpt-4o-mini"

          # Build request body
          body = build_request_body(messages, model, tools, response_format, kwargs)

          # Make async HTTP request
          Async do
            response = make_async_request("/v1/responses", body)

            # Parse and return response
            parse_response(response)
          end
        end

        # Synchronous wrapper
        def chat_completion(**)
          if in_async_context?
            async_chat_completion(**).wait
          else
            # Fall back to synchronous implementation
            super
          end
        end

        private

        def async_client
          @async_client ||= ::Async::HTTP::Client.new(@endpoint)
        end

        def make_async_request(path, body)
          Async do
            headers = build_headers

            # Send request using client
            response = async_client.post(path, headers, JSON.generate(body))

            # Check response status
            unless response.success?
              error_body = response.read
              handle_error(response.status, error_body)
            end

            # Read and parse response body
            response_body = response.read
            JSON.parse(response_body)
          rescue ::Async::TimeoutError => e
            raise APIError, "Request timeout: #{e.message}"
          rescue AuthenticationError, RateLimitError, ServerError, APIError
            # Re-raise our custom errors as-is
            raise
          rescue StandardError => e
            raise APIError, "Request failed: #{e.message}"
          end
        end

        def build_headers
          {
            "Content-Type" => "application/json",
            "Authorization" => "Bearer #{@api_key}",
            "OpenAI-Beta" => "agents-v1"
          }
        end

        def build_request_body(messages, model, tools, response_format, kwargs)
          body = {
            model: model,
            messages: messages
          }

          # Add tools if provided
          body[:tools] = tools if tools && !tools.empty?

          # Add response format if provided
          body[:response_format] = response_format if response_format

          # Add additional parameters
          body.merge!(kwargs.slice(:temperature, :max_completion_tokens, :top_p, :frequency_penalty, :presence_penalty))

          body
        end

        def parse_response(response)
          # Convert from Responses API format to chat completion format
          if response["choices"]&.first
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
          error_data = begin
            JSON.parse(body)
          rescue StandardError
            { "error" => { "message" => body } }
          end
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

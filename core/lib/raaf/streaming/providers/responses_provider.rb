# frozen_string_literal: true

require "async/http"
require "async/http/endpoint"
require "json"
require_relative "../../models/responses_provider"
require_relative "../base"

module RAAF

  module Async

    module Providers

      ##
      # Async-enhanced ResponsesProvider
      #
      # Provides async HTTP capabilities for OpenAI Responses API
      # with non-blocking I/O operations and concurrent request handling.
      #
      class ResponsesProvider < RAAF::Models::ResponsesProvider

        include RAAF::Async::Base

        ##
        # Initialize async responses provider
        #
        # @param api_key [String] OpenAI API key
        # @param base_url [String] Custom base URL for API
        # @param kwargs [Hash] Additional configuration options
        #
        def initialize(api_key: nil, base_url: "https://api.openai.com", **)
          super(api_key: api_key, **)
          @base_url = base_url
          @endpoint = ::Async::HTTP::Endpoint.parse(base_url)
        end

        ##
        # Make async chat completion request
        #
        # @param messages [Array<Hash>] Message history
        # @param model [String] Model to use (defaults to gpt-4o-mini)
        # @param tools [Array<Hash>] Available tools
        # @param response_format [Hash] Response format specification
        # @param kwargs [Hash] Additional parameters
        # @return [Async::Task] Task that resolves to API response
        #
        def async_chat_completion(messages:, model: "gpt-4o-mini", tools: nil, response_format: nil, **kwargs)
          Async do
            body = build_request_body(messages, model, tools, response_format, kwargs)
            response = make_async_request("/v1/responses", body)
            parsed = parse_response(response.wait)
            parsed
          end
        end

        ##
        # Chat completion with async context detection
        #
        # Uses async version when in async context, falls back to synchronous otherwise.
        #
        # @param messages [Array<Hash>] Message history
        # @param kwargs [Hash] Additional parameters
        # @return [Hash] API response
        #
        def chat_completion(messages:, **)
          if in_async_context?
            async_chat_completion(messages: messages, **).wait
          else
            super
          end
        end

        private

        ##
        # Build request body for API call
        #
        # @param messages [Array<Hash>] Message history
        # @param model [String] Model name
        # @param tools [Array<Hash>] Available tools
        # @param response_format [Hash] Response format
        # @param kwargs [Hash] Additional parameters
        # @return [Hash] Request body
        #
        def build_request_body(messages, model, tools, response_format, kwargs)
          body = {
            model: model,
            messages: messages
          }

          body[:tools] = tools if tools
          body[:response_format] = response_format if response_format
          body.merge!(kwargs)

          body
        end

        ##
        # Make async HTTP request
        #
        # @param path [String] API endpoint path
        # @param body [Hash] Request body
        # @return [Async::Task] Task that resolves to parsed response
        #
        def make_async_request(path, body)
          Async do
            response = async_client.post(
              path,
              {
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{@api_key}",
                "OpenAI-Beta" => "agents-v1"
              },
              JSON.generate(body)
            )

            if response.success?
              JSON.parse(response.read)
            else
              handle_error(response.status, response.read)
            end
          rescue ::Async::TimeoutError => e
            raise RAAF::APIError, "Request timeout: #{e.message}"
          rescue RAAF::Error => e
            # Re-raise RAAF errors (including AuthenticationError) as-is
            raise e
          rescue StandardError => e
            raise RAAF::APIError, "Request failed: #{e.message}"
          end
        end

        ##
        # Get or create async HTTP client
        #
        # @return [Async::HTTP::Client] HTTP client instance
        #
        def async_client
          @async_client ||= ::Async::HTTP::Client.new(@endpoint)
        end

        ##
        # Parse API response and convert to chat completion format
        #
        # @param response [Hash] Raw API response
        # @return [Hash] Parsed response in chat completion format
        #
        def parse_response(response)
          if response.is_a?(Hash) && response["choices"]
            # Convert responses API format to chat completion format
            {
              "id" => response["id"],
              "object" => "chat.completion",
              "created" => response["created"],
              "model" => response["model"],
              "choices" => response["choices"].map.with_index do |choice, index|
                {
                  "index" => index,
                  "message" => choice["message"],
                  "finish_reason" => choice["finish_reason"]
                }
              end,
              "usage" => response["usage"]
            }
          else
            response
          end
        end

        ##
        # Handle API errors
        #
        # @param status [Integer] HTTP status code
        # @param body [String] Response body
        # @raise [RAAF::Error] Appropriate error for status code
        #
        def handle_error(status, body)
          begin
            error_data = JSON.parse(body)
            message = error_data.dig("error", "message") || body
          rescue JSON::ParserError
            message = body
          end

          case status
          when 401
            raise RAAF::AuthenticationError, message
          when 429
            raise RAAF::RateLimitError, message
          when 500..599
            raise RAAF::ServerError, message
          else
            raise RAAF::APIError, message
          end
        end

      end

    end

  end

end

# frozen_string_literal: true

# NOTE: FOR CLAUDE: This file is DEPRECATED and should NOT be modified except for critical bug fixes.
# DO NOT update this file for new features or improvements. Use ResponsesProvider instead.
# This provider is maintained only for backwards compatibility and streaming support.

require_relative "interface"
require_relative "responses_provider"
require_relative "../http_client"

module RAAF

  module Models

    # @deprecated Use ResponsesProvider instead. This provider uses the legacy Chat Completions API
    # and is maintained only for backwards compatibility and streaming support.
    # ResponsesProvider is the recommended default provider with better features and usage tracking.
    class OpenAIProvider < ModelInterface

      SUPPORTED_MODELS = %w[
        gpt-4.1 gpt-4.1-mini gpt-4.1-nano
        gpt-4o gpt-4o-mini gpt-4-turbo gpt-4 gpt-4-32k
        gpt-3.5-turbo gpt-3.5-turbo-16k
        o1-preview o1-mini
      ].freeze

      # rubocop:disable Lint/MissingSuper
      def initialize(api_key: nil, api_base: nil, **)
        # Issue deprecation warning unless suppressed
        unless ENV["RAAF_SUPPRESS_WARNINGS"] == "true"
          warn "DEPRECATION WARNING: OpenAIProvider is deprecated and will be removed in a future version. " \
               "Use ResponsesProvider instead (it's the default). OpenAIProvider is maintained only for " \
               "backwards compatibility and streaming support. " \
               "Called from #{caller_locations(1, 1).first}"
        end

        @api_key = api_key || ENV.fetch("OPENAI_API_KEY", nil)
        @api_base = api_base || ENV["OPENAI_API_BASE"] || "https://api.openai.com/v1"
        raise AuthenticationError, "OpenAI API key is required" unless @api_key

        @client = HTTPClient::Client.new(
          api_key: @api_key,
          base_url: @api_base,
          **
        )
      end
      # rubocop:enable Lint/MissingSuper

      def chat_completion(messages:, model:, tools: nil, stream: false, **)
        validate_model(model)

        # For now, fall back to standard completion to avoid breaking the runner
        # TODO: Implement full Responses API integration
        standard_completion(messages: messages, model: model, tools: tools, stream: stream, **)
      end

      def responses_completion(messages:, model:, tools: nil, **kwargs)
        # Use Responses API for hosted tools like web_search
        require "net/http"
        require "json"

        uri = URI("https://api.openai.com/v1/responses")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"

        # Convert messages to input format
        input = messages.last[:content] if messages.last

        prepared_tools = prepare_tools_for_responses_api(tools)

        body = {
          model: model,
          input: input,
          tools: prepared_tools,
          **kwargs
        }

        request.body = body.to_json

        response = http.request(request)
        handle_responses_api_response(response)
      end

      def supported_models
        SUPPORTED_MODELS
      end

      def provider_name
        "OpenAI"
      end

      def stream_completion(messages:, model:, tools: nil, **)
        validate_model(model)
        standard_completion(messages: messages, model: model, tools: tools, stream: true, **)
      end

      # Alias for compatibility with API strategies
      alias complete chat_completion

      private

      def prepare_tools_for_responses_api(tools)
        return nil unless tools.respond_to?(:empty?) && tools.respond_to?(:map)
        return nil if tools.empty?

        tools.map do |tool|
          case tool
          when Hash
            # Assume hash already has correct format, but ensure name is at top level
            if tool[:function] && tool[:function][:name] && !tool[:name]
              tool.merge(name: tool[:function][:name])
            else
              tool
            end
          when FunctionTool
            # Convert FunctionTool to proper OpenAI API format
            {
              type: "function",
              function: {
                name: tool.name,
                description: tool.description,
                parameters: tool.parameters
              }
            }
          when RAAF::Tools::WebSearchTool, RAAF::Tools::HostedFileSearchTool, RAAF::Tools::HostedComputerTool
            tool.to_tool_definition
          else
            raise ArgumentError, "Invalid tool type: #{tool.class}"
          end
        end
      end

      def standard_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        parameters = {
          model: model,
          messages: messages,
          stream: stream,
          **kwargs
        }
        parameters[:tools] = prepare_tools(tools) if tools

        # Handle response_format for structured output
        parameters[:response_format] = kwargs[:response_format] if kwargs[:response_format]

        begin
          # CORE DEBUG: Log exactly what's being sent to OpenAI
          puts "\n🚀 [RAAF CORE] === SENDING TO OPENAI ==="
          puts "🚀 [RAAF CORE] Model: #{parameters[:model]}"
          puts "🚀 [RAAF CORE] Stream: #{parameters[:stream]}"
          
          # Log messages array
          puts "🚀 [RAAF CORE] Messages count: #{parameters[:messages].length}"
          parameters[:messages].each_with_index do |msg, idx|
            puts "🚀 [RAAF CORE] Message #{idx} (#{msg[:role]}): #{msg[:content].to_s[0..200]}#{msg[:content].to_s.length > 200 ? '...' : ''}"
          end
          
          # Log response format (structured output)
          if parameters[:response_format]
            puts "🚀 [RAAF CORE] Using Structured Output: YES"
            puts "🚀 [RAAF CORE] Response Format Type: #{parameters[:response_format][:type]}"
            if parameters[:response_format][:json_schema]
              schema_name = parameters[:response_format][:json_schema][:name]
              puts "🚀 [RAAF CORE] Schema Name: #{schema_name}"
              puts "🚀 [RAAF CORE] Schema: #{parameters[:response_format][:json_schema][:schema].to_json[0..500]}..."
            end
          else
            puts "🚀 [RAAF CORE] Using Structured Output: NO"
          end
          
          # Debug log the final parameters being sent to OpenAI
          if parameters[:tools]
            log_debug_tools("📤 FINAL PARAMETERS SENT TO OPENAI API",
                            tools_count: parameters[:tools].length,
                            tools_json: parameters[:tools].to_json)

            # Check each tool for array parameters
            parameters[:tools].each do |tool|
              next unless tool[:function] && tool[:function][:parameters] && tool[:function][:parameters][:properties]

              tool[:function][:parameters][:properties].each do |prop_name, prop_def|
                next unless prop_def[:type] == "array"

                log_debug_tools("🔍 FINAL ARRAY PROPERTY #{prop_name} SENT TO OPENAI",
                                has_items: prop_def.key?(:items),
                                items_value: prop_def[:items].inspect)
              end
            end
          end
          
          puts "🚀 [RAAF CORE] === CALLING OPENAI API ==="
          response = @client.chat.completions.create(**parameters)
          
          # CORE DEBUG: Log exactly what OpenAI returned
          puts "\n📥 [RAAF CORE] === RECEIVED FROM OPENAI ==="
          puts "📥 [RAAF CORE] Response ID: #{response.id}"
          puts "📥 [RAAF CORE] Model: #{response.model}"
          puts "📥 [RAAF CORE] Finish Reason: #{response.choices.first&.finish_reason}"
          
          if response.choices.first&.message&.content
            content = response.choices.first.message.content
            puts "📥 [RAAF CORE] Content Type: #{content.class}"
            puts "📥 [RAAF CORE] Content Length: #{content.to_s.length}"
            puts "📥 [RAAF CORE] Raw Content (first 1000 chars): #{content.to_s[0..1000]}"
            
            # Try to parse as JSON to see structure
            if content.is_a?(String) && content.strip.start_with?('{', '[')
              begin
                parsed = JSON.parse(content)
                puts "📥 [RAAF CORE] Parsed JSON Type: #{parsed.class}"
                if parsed.is_a?(Hash)
                  puts "📥 [RAAF CORE] JSON Keys: #{parsed.keys.inspect}"
                  if parsed['markets'] || parsed[:markets]
                    markets = parsed['markets'] || parsed[:markets]
                    puts "📥 [RAAF CORE] Markets in response: #{markets.length}" if markets.respond_to?(:length)
                    if markets.respond_to?(:first) && markets.first
                      puts "📥 [RAAF CORE] First market keys: #{markets.first.keys.inspect}" if markets.first.respond_to?(:keys)
                      # Check specifically for scoring data
                      first_market = markets.first
                      if first_market['scoring'] || first_market[:scoring]
                        scoring = first_market['scoring'] || first_market[:scoring]
                        puts "📥 [RAAF CORE] First market scoring type: #{scoring.class}"
                        puts "📥 [RAAF CORE] First market scoring keys: #{scoring.keys.inspect}" if scoring.respond_to?(:keys)
                        if scoring.respond_to?(:keys) && scoring.keys.first
                          first_dimension = scoring[scoring.keys.first]
                          puts "📥 [RAAF CORE] First dimension (#{scoring.keys.first}): #{first_dimension.inspect}"
                        end
                      else
                        puts "📥 [RAAF CORE] NO SCORING DATA in first market"
                      end
                    end
                  end
                end
              rescue JSON::ParserError => e
                puts "📥 [RAAF CORE] JSON Parse Error: #{e.message}"
              end
            end
          else
            puts "📥 [RAAF CORE] No content in response"
          end
          
          puts "📥 [RAAF CORE] === END OPENAI RESPONSE ==="
          
          normalize_response_format(response)
        rescue HTTPClient::Error => e
          handle_openai_error(e)
        end
      end

      def hosted_tools?(tools)
        return false unless tools.respond_to?(:any?)

        tools.any? do |tool|
          case tool
          when RAAF::Tools::WebSearchTool, RAAF::Tools::HostedFileSearchTool, RAAF::Tools::HostedComputerTool
            true
          when Hash
            %w[web_search file_search computer].include?(tool[:type])
          else
            false
          end
        end
      end

      def handle_responses_api_response(response)
        case response.code
        when "200"
          data = JSON.parse(response.body)
          log_debug_api("Raw Responses API response", provider: "OpenAI", response_keys: data.keys)
          # Convert to standard chat completion format
          {
            "choices" => [
              {
                "message" => {
                  "role" => "assistant",
                  "content" => extract_content_from_responses(data)
                },
                "finish_reason" => "stop"
              }
            ]
          }
        when "401"
          raise AuthenticationError, "Invalid API key for OpenAI"
        when "429"
          raise RateLimitError, "Rate limit exceeded for OpenAI"
        else
          raise APIError, "Responses API Error: #{response.code} - #{response.body}"
        end
      end

      def extract_content_from_responses(data)
        if data["output"]&.any?
          content = data["output"][0]
          return content["content"][0]["text"] if content["content"]&.any?
        end

        data["text"] || "No content returned"
      end

      def process_openai_chunk(chunk, accumulated_content, accumulated_tool_calls, &)
        return if chunk.nil? || chunk.empty?

        delta = chunk.dig("choices", 0, "delta")
        return unless delta

        process_content_delta(delta, accumulated_content, &)
        process_tool_call_delta(delta, accumulated_tool_calls, &)
        process_finish_reason(chunk, accumulated_content, accumulated_tool_calls, &)
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

          accumulated_tool_calls[index]["function"]["name"] += tool_call["function"]["name"] if tool_call.dig("function", "name")

          accumulated_tool_calls[index]["function"]["arguments"] += tool_call["function"]["arguments"] if tool_call.dig("function", "arguments")

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

      ##
      # Normalize OpenAI Chat Completions API response to match ResponsesProvider format
      #
      # This method converts the legacy usage format (prompt_tokens, completion_tokens)
      # to the new format (input_tokens, output_tokens) for backwards compatibility.
      #
      # @param response [Hash] Raw response from OpenAI Chat Completions API
      # @return [Hash] Normalized response with converted usage format
      #
      def normalize_response_format(response)
        # Convert usage format if present
        if response.respond_to?(:[]) && response[:usage]
          usage = response[:usage]

          # Convert legacy field names to new format
          if usage[:prompt_tokens] || usage["prompt_tokens"]
            response[:usage] = {
              input_tokens: usage[:prompt_tokens] || usage["prompt_tokens"] || 0,
              output_tokens: usage[:completion_tokens] || usage["completion_tokens"] || 0,
              total_tokens: usage[:total_tokens] || usage["total_tokens"] || 0
            }
          end
        elsif response.respond_to?(:dig) && response["usage"]
          usage = response["usage"]

          # Convert legacy field names to new format for string keys
          if usage["prompt_tokens"] || usage["completion_tokens"]
            response["usage"] = {
              "input_tokens" => usage["prompt_tokens"] || 0,
              "output_tokens" => usage["completion_tokens"] || 0,
              "total_tokens" => usage["total_tokens"] || 0
            }
          end
        end

        response
      end

      def handle_openai_error(error)
        case error
        when HTTPClient::AuthenticationError
          raise AuthenticationError, "Invalid API key for OpenAI"
        when HTTPClient::RateLimitError
          raise RateLimitError, "Rate limit exceeded for OpenAI"
        when HTTPClient::InternalServerError
          raise ServerError, "Server error from OpenAI: #{error.message}"
        when HTTPClient::BadRequestError
          raise APIError, "Bad request to OpenAI: #{error.message}"
        when HTTPClient::APIConnectionError
          raise APIError, "Connection error to OpenAI: #{error.message}"
        when HTTPClient::APITimeoutError
          raise APIError, "Timeout error from OpenAI: #{error.message}"
        else
          raise APIError, "API error from OpenAI: #{error.message}"
        end
      end

    end

  end

end

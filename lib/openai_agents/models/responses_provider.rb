# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "securerandom"
require_relative "interface"
require_relative "../tracing/spans"
require_relative "../token_estimator"

module OpenAIAgents
  module Models
    # OpenAI Responses API provider - matches Python implementation exactly
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

      # Indicates this provider supports prompts (for Responses API)
      def supports_prompts?
        true
      end

      # Main entry point matching Python's get_response
      # Calls the Responses API (/v1/responses), not Chat Completions API
      def responses_completion(messages:, model:, tools: nil, stream: false, previous_response_id: nil, input: nil, **)
        validate_model(model)

        # For Responses API, we can pass input items directly
        if input
          # Use provided input items directly
          list_input = input
          system_instructions = extract_system_instructions(messages)
        else
          # Convert messages to Responses API format
          system_instructions = extract_system_instructions(messages)
          list_input = convert_messages_to_input(messages)
        end

        # Make the API call
        fetch_response(
          system_instructions: system_instructions,
          input: list_input,
          model: model,
          tools: tools,
          stream: stream,
          previous_response_id: previous_response_id,
          **
        )

        # Return the raw response in a format compatible with the runner
        # The response already contains the output items that can be processed
      end

      private

      def validate_model(model)
        return if SUPPORTED_MODELS.include?(model)

        warn "Model #{model} is not in the list of supported models: #{SUPPORTED_MODELS.join(", ")}"
      end

      # Matches Python's _fetch_response
      def fetch_response(system_instructions:, input:, model:, tools: nil, stream: false,
                         previous_response_id: nil, tool_choice: nil, parallel_tool_calls: nil,
                         temperature: nil, top_p: nil, max_tokens: nil, response_format: nil, **)
        # Convert input to list format if it's a string
        list_input = input.is_a?(String) ? [{ type: "user_text", text: input }] : input

        # Convert tools to Responses API format
        converted_tools = convert_tools(tools)

        # Build request body
        body = {
          model: model,
          input: list_input
        }

        # Add optional parameters
        body[:previous_response_id] = previous_response_id if previous_response_id
        body[:instructions] = system_instructions if system_instructions
        body[:tools] = converted_tools[:tools] if converted_tools[:tools]&.any?
        body[:include] = converted_tools[:includes] if converted_tools[:includes]&.any?
        body[:tool_choice] = convert_tool_choice(tool_choice) if tool_choice
        body[:parallel_tool_calls] = parallel_tool_calls unless parallel_tool_calls.nil?
        body[:temperature] = temperature if temperature
        body[:top_p] = top_p if top_p
        body[:max_output_tokens] = max_tokens if max_tokens
        body[:stream] = stream if stream

        # Handle response format
        body[:text] = convert_response_format(response_format) if response_format

        # Debug logging
        if defined?(Rails) && Rails.logger && Rails.env.development?
          Rails.logger.info "🚀 Calling OpenAI Responses API:"
          Rails.logger.info "   Model: #{model}"
          Rails.logger.info "   Input: #{list_input.inspect}"
          Rails.logger.info "   Tools: #{converted_tools[:tools]&.length || 0}"
          Rails.logger.info "   Previous Response ID: #{previous_response_id}" if previous_response_id
          Rails.logger.info "   Stream: #{stream}"
        end

        # Make the API call
        raise NotImplementedError, "Streaming not yet implemented for Responses API" if stream

        call_responses_api(body)
      end

      def call_responses_api(body)
        uri = URI("#{@api_base}/responses")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "Agents/Ruby #{OpenAIAgents::VERSION}"

        request.body = body.to_json

        response = http.request(request)

        unless response.code.start_with?("2")
          Rails.logger.error "🚨 OpenAI Responses API Error:" if defined?(Rails) && Rails.logger
          Rails.logger.error "   Status Code: #{response.code}" if defined?(Rails) && Rails.logger
          Rails.logger.error "   Response Body: #{response.body}" if defined?(Rails) && Rails.logger
          Rails.logger.error "   Request Body: #{body.to_json}" if defined?(Rails) && Rails.logger
          raise APIError, "Responses API returned #{response.code}: #{response.body}"
        end

        parsed_response = JSON.parse(response.body, symbolize_names: true)

        # Debug logging for successful responses
        if defined?(Rails) && Rails.logger && Rails.env.development?
          Rails.logger.info "✅ OpenAI Responses API Success:"
          Rails.logger.info "   Response ID: #{parsed_response[:id]}"
          Rails.logger.info "   Output items: #{parsed_response[:output]&.length || 0}"
          Rails.logger.info "   Usage: #{parsed_response[:usage]}"
        end

        # Return the raw Responses API response
        # The runner will need to handle the items-based format
        parsed_response
      end

      # Convert messages to Responses API input format
      def convert_messages_to_input(messages)
        input_items = []

        messages.each do |msg|
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"]

          case role
          when "user"
            input_items << { type: "user_text", text: content }
          when "assistant"
            # Assistant messages become output items in the input
            if msg[:tool_calls]
              # Handle tool calls
              msg[:tool_calls].each do |tool_call|
                input_items << convert_tool_call_to_input(tool_call)
              end
            else
              # Regular text message
              input_items << { type: "text", text: content }
            end
          when "tool"
            # Tool results become function call outputs
            input_items << {
              type: "function_call_output",
              call_id: msg[:tool_call_id] || msg["tool_call_id"],
              output: msg[:content] || msg["content"]
            }
          when "system"
            # System messages are handled separately as instructions
            next
          end
        end

        input_items
      end

      def convert_tool_call_to_input(tool_call)
        {
          type: "function_call",
          name: tool_call.dig("function", "name") || tool_call.dig(:function, :name),
          arguments: tool_call.dig("function", "arguments") || tool_call.dig(:function, :arguments),
          call_id: tool_call["id"] || tool_call[:id]
        }
      end

      # Extract system instructions from messages
      def extract_system_instructions(messages)
        system_msg = messages.find { |m| m[:role] == "system" }
        system_msg&.dig(:content)
      end

      # Convert tools to Responses API format (matches Python's Converter.convert_tools)
      def convert_tools(tools)
        return { tools: [], includes: [] } unless tools && !tools.empty?

        converted_tools = []
        includes = []

        tools.each do |tool|
          case tool
          when Hash
            # Handle hash-based tools
            if tool[:type] == "web_search" || tool["type"] == "web_search"
              converted_tools << { type: "web_search" }
              includes << "web_search_call.results"
            else
              converted_tools << tool
            end
          when OpenAIAgents::FunctionTool
            # Convert FunctionTool to Responses API format
            converted_tools << {
              type: "function",
              name: tool.name,
              description: tool.description,
              parameters: prepare_function_parameters(tool.parameters),
              strict: determine_strict_mode(tool.parameters)
            }
          when OpenAIAgents::Tools::WebSearchTool
            # Convert to hosted web search tool
            converted_tools << { type: "web_search" }
            includes << "web_search_call.results"
          else
            # Let other tools convert themselves if they implement the method
            raise ArgumentError, "Unknown tool type: #{tool.class}" unless tool.respond_to?(:to_tool_definition)

            converted_tools << tool.to_tool_definition

          end
        end

        { tools: converted_tools, includes: includes.uniq }
      end

      def prepare_function_parameters(parameters)
        return {} unless parameters.is_a?(Hash)

        params = parameters.dup

        # Ensure required fields for Responses API
        if params[:properties].is_a?(Hash)
          params[:additionalProperties] = false unless params.key?(:additionalProperties)

          # For strict mode, all properties must be in required array
          if params[:additionalProperties] == false
            all_properties = params[:properties].keys.map(&:to_s)
            params[:required] = all_properties unless params[:required] == all_properties
          end
        end

        params
      end

      def determine_strict_mode(parameters)
        return false unless parameters.is_a?(Hash)

        # Use strict mode if we have a well-defined schema
        parameters[:properties].is_a?(Hash) &&
          parameters[:additionalProperties] == false &&
          parameters[:required].is_a?(Array)
      end

      def convert_tool_choice(tool_choice)
        case tool_choice
        when "auto", "required", "none"
          tool_choice
        when String
          # Assume it's a specific tool name
          { type: "function", name: tool_choice }
        when Hash
          tool_choice
        end
      end

      def convert_response_format(response_format)
        return unless response_format.is_a?(Hash) && response_format[:type] == "json_schema"

        {
          format: {
            type: "json_schema",
            name: response_format.dig(:json_schema, :name),
            schema: response_format.dig(:json_schema, :schema),
            strict: response_format.dig(:json_schema, :strict)
          }
        }
      end
    end
  end
end

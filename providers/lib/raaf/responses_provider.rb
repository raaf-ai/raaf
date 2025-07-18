# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "securerandom"
require_relative "interface"
require_relative "../tracing/spans"
require_relative "../token_estimator"
require_relative "../logging"
require_relative "../streaming_events"

module RAAF
  module Models
    ##
    # Provider for OpenAI's Responses API (recommended default)
    #
    # This provider implements support for OpenAI's newer Responses API endpoint
    # (/v1/responses) which offers better features than the traditional Chat
    # Completions API:
    # - Items-based conversation model
    # - Built-in conversation continuity
    # - More detailed usage statistics
    # - Better streaming support
    #
    # This provider maintains exact structural alignment with the Python
    # RAAF SDK for full compatibility.
    #
    # @example Basic usage
    #   provider = ResponsesProvider.new(api_key: ENV['OPENAI_API_KEY'])
    #   response = provider.responses_completion(
    #     messages: [{ role: "user", content: "Hello" }],
    #     model: "gpt-4o"
    #   )
    #
    # @example With tools
    #   response = provider.responses_completion(
    #     messages: messages,
    #     model: "gpt-4o",
    #     tools: [weather_tool, calculator_tool]
    #   )
    #
    # @example Continuing a conversation
    #   response = provider.responses_completion(
    #     messages: [],
    #     model: "gpt-4o",
    #     previous_response_id: "resp_123",
    #     input: [{ type: "function_call_output", ... }]
    #   )
    #
    class ResponsesProvider < ModelInterface
      include Logger
      
      # Models supported by the Responses API
      SUPPORTED_MODELS = %w[
        gpt-4o gpt-4o-mini gpt-4-turbo gpt-4
        o1-preview o1-mini
      ].freeze

      ##
      # Initialize the Responses API provider
      #
      # @param api_key [String, nil] OpenAI API key (defaults to ENV['OPENAI_API_KEY'])
      # @param api_base [String, nil] Custom API base URL
      # @param _options [Hash] Additional options (currently unused)
      #
      # @raise [AuthenticationError] If no API key is provided
      #
      def initialize(api_key: nil, api_base: nil, **_options)
        @api_key = api_key || ENV.fetch("OPENAI_API_KEY", nil)
        @api_base = api_base || ENV["OPENAI_API_BASE"] || "https://api.openai.com/v1"
        raise AuthenticationError, "OpenAI API key is required" unless @api_key
      end

      ##
      # Check if this provider supports prompt parameter
      #
      # @return [Boolean] Always true for Responses API
      #
      def supports_prompts?
        true
      end

      ##
      # Execute a completion using the Responses API
      #
      # This is the main entry point for the Responses API provider.
      # It uses the /v1/responses endpoint instead of /v1/chat/completions.
      #
      # @param messages [Array<Hash>] Traditional message format (converted internally)
      # @param model [String] Model to use
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param stream [Boolean] Whether to stream the response
      # @param previous_response_id [String, nil] ID of previous response for continuity
      # @param input [Array<Hash>, nil] Direct input items (bypasses message conversion)
      # @param kwargs [Hash] Additional parameters (temperature, max_tokens, etc.)
      #
      # @return [Hash] Response with :id, :output, :usage, etc.
      #
      # @example Basic call
      #   response = provider.responses_completion(
      #     messages: [{ role: "user", content: "Hello" }],
      #     model: "gpt-4o"
      #   )
      #   response[:output] # => [{ type: "message", content: "Hi!" }]
      #
      # @example Continuing a conversation
      #   response = provider.responses_completion(
      #     messages: [],
      #     model: "gpt-4o", 
      #     previous_response_id: previous_response[:id],
      #     input: [{ type: "function_call_output", output: "..." }]
      #   )
      #
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

      # Implement streaming completion to match ModelInterface
      def stream_completion(messages:, model:, tools: nil, &block)
        validate_model(model)
        
        # Use responses_completion with streaming enabled
        responses_completion(
          messages: messages,
          model: model,
          tools: tools,
          stream: true,
          &block
        )
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
        log_info("Calling OpenAI Responses API",
          model: model,
          input_length: list_input.length,
          tools_count: converted_tools[:tools]&.length || 0,
          previous_response_id: previous_response_id,
          stream: stream
        )

        # Make the API call
        if stream
          final_response = nil
          call_responses_api_stream(body) do |event|
            # Capture the final response from the completed event
            if event.is_a?(StreamingEvents::ResponseCompletedEvent)
              final_response = event.response
            end
            yield event if block_given?
          end
          final_response
        else
          call_responses_api(body)
        end
      end

      ##
      # Make a synchronous call to the Responses API
      #
      # @param body [Hash] Request body with model, input, tools, etc.
      # @return [Hash] Parsed API response
      # @raise [APIError] If the API returns an error
      #
      # @api private
      #
      def call_responses_api(body)
        uri = URI("#{@api_base}/responses")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "Agents/Ruby #{RAAF::VERSION}"

        request.body = body.to_json

        # DEBUG: Log the actual request body being sent to OpenAI
        if body[:tools]
          log_debug_tools("📤 ACTUAL REQUEST BODY SENT TO OPENAI RESPONSES API",
            tools_count: body[:tools].length,
            request_body_json: body.to_json
          )
          
          # Check each tool for array parameters in the actual request
          body[:tools].each do |tool|
            if tool[:function] && tool[:function][:parameters] && tool[:function][:parameters][:properties]
              tool[:function][:parameters][:properties].each do |prop_name, prop_def|
                if prop_def[:type] == "array"
                  log_debug_tools("🔍 ACTUAL REQUEST ARRAY PROPERTY #{prop_name} SENT TO OPENAI",
                    has_items: prop_def.key?(:items),
                    items_value: prop_def[:items].inspect,
                    items_nil: prop_def[:items].nil?
                  )
                end
              end
            end
          end
        end

        response = http.request(request)

        unless response.code.start_with?("2")
          log_error("OpenAI Responses API Error",
            status_code: response.code,
            response_body: response.body,
            request_body: body.to_json
          )
          raise APIError, "Responses API returned #{response.code}: #{response.body}"
        end

        parsed_response = JSON.parse(response.body, symbolize_names: true)

        # Debug logging for successful responses
        log_info("OpenAI Responses API Success",
          response_id: parsed_response[:id],
          output_items: parsed_response[:output]&.length || 0,
          usage: parsed_response[:usage]
        )

        # Return the raw Responses API response
        # The runner will need to handle the items-based format
        parsed_response
      end

      ##
      # Make a streaming call to the Responses API
      #
      # This method handles Server-Sent Events (SSE) streaming from the API,
      # parsing events and yielding them as Ruby objects.
      #
      # @param body [Hash] Request body
      # @yield [event] Yields streaming events as they arrive
      # @yieldparam event [StreamingEvents::Base] Parsed streaming event
      #
      # @raise [APIError] If the API returns an error
      #
      # @api private
      #
      def call_responses_api_stream(body, &block)
        uri = URI("#{@api_base}/responses")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120 # Longer timeout for streaming

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request["User-Agent"] = "Agents/Ruby #{RAAF::VERSION}"
        request["Accept"] = "text/event-stream"
        request["Cache-Control"] = "no-cache"

        # Add streaming to request body
        stream_body = body.merge(stream: true)
        request.body = stream_body.to_json

        log_debug_api("Starting Responses API streaming request", 
          url: uri.to_s,
          model: body[:model]
        )

        http.request(request) do |response|
          unless response.code.start_with?("2")
            error_body = response.read_body
            log_error("OpenAI Responses API Streaming Error",
              status_code: response.code,
              response_body: error_body,
              request_body: stream_body.to_json
            )
            raise APIError, "Responses API streaming returned #{response.code}: #{error_body}"
          end

          # Process Server-Sent Events
          buffer = ""
          response.read_body do |chunk|
            buffer += chunk
            
            # Process complete lines
            while buffer.include?("\n")
              line, buffer = buffer.split("\n", 2)
              process_sse_line(line.strip, &block)
            end
          end

          # Process any remaining buffer
          process_sse_line(buffer.strip, &block) unless buffer.strip.empty?
        end
      end

      # Process individual Server-Sent Event lines
      def process_sse_line(line, &block)
        return if line.empty? || line.start_with?(":")

        if line.start_with?("data:")
          data = line[5..-1].strip
          
          # Handle end of stream
          return if data == "[DONE]"

          begin
            event_data = JSON.parse(data, symbolize_names: true)
            
            # Create and yield appropriate streaming event
            streaming_event = create_streaming_event(event_data)
            block.call(streaming_event) if streaming_event && block
            
            log_debug_api("Processed streaming event", 
              type: event_data[:type],
              sequence: event_data[:sequence_number]
            )
          rescue JSON::ParserError => e
            log_debug_api("Failed to parse streaming data", 
              data: data,
              error: e.message
            )
          end
        end
      end

      # Create appropriate streaming event objects based on API response
      def create_streaming_event(event_data)
        case event_data[:type]
        when "response.created"
          StreamingEvents::ResponseCreatedEvent.new(
            response: event_data[:response],
            sequence_number: event_data[:sequence_number]
          )
        when "response.output_item.added"
          StreamingEvents::ResponseOutputItemAddedEvent.new(
            item: event_data[:item],
            output_index: event_data[:output_index],
            sequence_number: event_data[:sequence_number]
          )
        when "response.output_item.done"
          StreamingEvents::ResponseOutputItemDoneEvent.new(
            item: event_data[:item],
            output_index: event_data[:output_index],
            sequence_number: event_data[:sequence_number]
          )
        when "response.done"
          StreamingEvents::ResponseCompletedEvent.new(
            response: event_data[:response],
            sequence_number: event_data[:sequence_number]
          )
        else
          # Return raw event data for unknown types
          event_data
        end
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
          when RAAF::FunctionTool
            # Convert FunctionTool to Responses API format
            converted_tools << {
              type: "function",
              name: tool.name,
              description: tool.description,
              parameters: prepare_function_parameters(tool.parameters),
              strict: determine_strict_mode(tool.parameters)
            }
          when RAAF::Tools::WebSearchTool
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

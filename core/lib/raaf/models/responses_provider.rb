# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "securerandom"
require_relative "interface"
require_relative "../token_estimator"
require_relative "../logging"
require_relative "../streaming_events"

# Streaming support is now included in core

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
    # @note Parameter Compatibility
    #   The Responses API does NOT support these Chat Completions parameters:
    #   - frequency_penalty
    #   - presence_penalty
    #   - best_of
    #   - logit_bias
    #
    #   If these parameters are provided, a warning will be logged and they will be
    #   silently filtered from the API request. Use OpenAIProvider (Chat Completions API)
    #   if you need these parameters.
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

      attr_accessor :http_timeout

      # Models supported by the Responses API
      SUPPORTED_MODELS = %w[
        gpt-5 gpt-5-mini gpt-5-nano gpt-5-chat-latest
        gpt-4o gpt-4o-mini gpt-4-turbo gpt-4
        gpt-3.5-turbo gpt-3.5-turbo-16k
        o1-preview o1-mini
      ].freeze

      # Reasoning models that don't support temperature/top_p
      REASONING_MODELS = %w[
        gpt-5 gpt-5-mini gpt-5-nano gpt-5-chat-latest
        o1-preview o1-mini
      ].freeze

      ##
      # Initialize the Responses API provider
      #
      # @param api_key [String, nil] OpenAI API key (defaults to ENV['OPENAI_API_KEY'])
      # @param api_base [String, nil] Custom API base URL
      # @param timeout [Integer, nil] HTTP read timeout in seconds (default: 300 via OPENAI_HTTP_TIMEOUT env var)
      # @param _options [Hash] Additional options (currently unused)
      #
      # @raise [AuthenticationError] If no API key is provided
      #
      def initialize(api_key: nil, api_base: nil, timeout: nil, **_options)
        super()
        @api_key = api_key || ENV.fetch("OPENAI_API_KEY", nil)
        @api_base = api_base || ENV["OPENAI_API_BASE"] || "https://api.openai.com/v1"
        @http_timeout = timeout || ENV.fetch("OPENAI_HTTP_TIMEOUT", "300").to_i
        raise AuthenticationError, "OpenAI API key is required" unless @api_key
      end

      ##
      # Get supported models for this provider
      #
      # @return [Array<String>] List of supported model names
      #
      def supported_models
        SUPPORTED_MODELS
      end

      ##
      # Get the provider name
      #
      # @return [String] Provider name
      #
      def provider_name
        "OpenAI"
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
      # Check if this provider supports function calling
      #
      # @return [Boolean] Always true for Responses API
      #
      def supports_function_calling?
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
      def responses_completion(messages:, model:, tools: nil, stream: false, previous_response_id: nil, input: nil,
                               auto_continuation: true, max_continuation_attempts: 10,
                               frequency_penalty: nil, presence_penalty: nil, best_of: nil, logit_bias: nil, **kwargs)
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

        # Continuation loop for handling truncated responses
        # Automatically continues until response is complete or max chunks reached
        max_chunks = max_continuation_attempts
        chunk_number = 1
        current_response_id = previous_response_id
        collected_chunks = []

        loop do
          log_debug("🔄 Continuation sequence iteration",
                    chunk_number: chunk_number,
                    max_chunks: max_chunks,
                    current_response_id: current_response_id)

          # Make the API call
          response = fetch_response(
            system_instructions: system_instructions,
            input: list_input,
            model: model,
            tools: tools,
            stream: stream,
            previous_response_id: current_response_id,
            chunk_number: chunk_number,
            frequency_penalty: frequency_penalty,
            presence_penalty: presence_penalty,
            best_of: best_of,
            logit_bias: logit_bias,
            **kwargs
          )

          # Collect this chunk
          collected_chunks << response

          # Check if we need to continue
          # Use infer_finish_reason to properly detect truncation in Responses API
          # This method checks incomplete_details and truncation fields from OpenAI
          finish_reason = infer_finish_reason(response)
          is_truncated = (finish_reason == "length" || finish_reason == "incomplete")

          # Determine if response is complete
          response_complete = finish_reason == "stop" && !is_truncated

          log_debug("🔍 Checking if continuation needed",
                    finish_reason: finish_reason,
                    truncation: is_truncated,
                    response_complete: response_complete,
                    chunk_number: chunk_number,
                    max_chunks: max_chunks)

          # Exit loop if response is complete
          if response_complete
            log_debug("✅ Response complete, exiting continuation loop",
                      finish_reason: finish_reason,
                      total_chunks: chunk_number)
            break
          end

          # Check if we've exceeded max chunks
          if chunk_number >= max_chunks
            log_warn("⚠️ Max continuation chunks reached",
                     max_chunks: max_chunks,
                     response_id: response["id"])
            break
          end

          # Prepare for next iteration
          chunk_number += 1
          current_response_id = response["id"]

          log_debug("🔄 Continuation needed, preparing next chunk",
                    next_chunk: chunk_number,
                    response_id: current_response_id)
        end

        # Return the final response (or merged response if multiple chunks)
        final_response = collected_chunks.last
        final_response
      end

      # Implement streaming completion to match ModelInterface
      def stream_completion(messages:, model:, tools: nil, &)
        validate_model(model)

        # Use responses_completion with streaming enabled
        responses_completion(
          messages: messages,
          model: model,
          tools: tools,
          stream: true,
          &
        )
      end

      # Alias for API strategy compatibility
      alias complete responses_completion

      private

      def validate_model(model)
        return if SUPPORTED_MODELS.include?(model)

        raise ArgumentError, "Model #{model} is not supported. Supported models: #{SUPPORTED_MODELS.join(", ")}"
      end

      def reasoning_model?(model)
        REASONING_MODELS.include?(model)
      end

      # Infers finish_reason from Responses API fields
      # OpenAI Responses API uses "truncation" and "status" fields instead of "finish_reason"
      # This method maps those fields to finish_reason for compatibility
      def infer_finish_reason(response)
        # If finish_reason is already set, return it
        finish_reason = response["finish_reason"]
        return finish_reason if finish_reason && !finish_reason.empty?

        # Extract Responses API fields
        truncation = response["truncation"]
        status = response["status"]
        incomplete_details = response["incomplete_details"]

        # Determine finish_reason based on Responses API response structure
        if truncation == true || truncation == "true"
          log_debug("📌 Detected truncation from 'truncation' field",
                    detected_reason: "length",
                    truncation: truncation,
                    incomplete_details: incomplete_details)
          "length"
        elsif incomplete_details && !incomplete_details.empty?
          log_debug("📌 Detected incomplete response from 'incomplete_details' field",
                    detected_reason: "incomplete",
                    incomplete_details: incomplete_details)
          "incomplete"
        elsif status == "completed" || status == "completed_successfully"
          log_debug("📌 Response completed normally",
                    detected_reason: "stop",
                    status: status)
          "stop"
        else
          # Default to "stop" if we can't determine
          log_debug("📌 Defaulting finish_reason to 'stop'",
                    status: status,
                    truncation: truncation,
                    incomplete_details: incomplete_details)
          "stop"
        end
      end

      # Extracts text content from Responses API response
      # Handles nested structure: response -> output -> content -> text
      def extract_response_text(response)
        # Try to extract from Responses API structure
        text = response.dig("output", 0, "content", 0, "text")
        return text if text

        # Fallback: try to get content as string
        content = response.dig("output", 0, "content")
        return content.to_s if content

        # No text found
        ""
      end

      # Unsupported parameters that belong to Chat Completions API
      UNSUPPORTED_PARAMS = [
        :frequency_penalty,
        :presence_penalty,
        :best_of,
        :logit_bias
      ].freeze

      # Parameters not supported by reasoning models (GPT-5, o1)
      REASONING_UNSUPPORTED_PARAMS = [
        :temperature,
        :top_p,
        :frequency_penalty,
        :presence_penalty,
        :logit_bias,
        :best_of
      ].freeze

      # Matches Python's _fetch_response
      def fetch_response(system_instructions:, input:, model:, tools: nil, stream: false,
                         previous_response_id: nil, chunk_number: 1, tool_choice: nil, parallel_tool_calls: nil,
                         temperature: nil, top_p: nil, max_tokens: nil, response_format: nil,
                         frequency_penalty: nil, presence_penalty: nil, best_of: nil, logit_bias: nil, **kwargs)
        # Validate and warn about unsupported parameters
        validate_unsupported_parameters(
          model: model,
          temperature: temperature,
          top_p: top_p,
          frequency_penalty: frequency_penalty,
          presence_penalty: presence_penalty,
          best_of: best_of,
          logit_bias: logit_bias,
          **kwargs
        )

        # Convert input to list format if it's a string
        # Use "message" type instead of "user_text" as per OpenAI Responses API requirements
        list_input = input.is_a?(String) ? [{ type: "message", role: "user", content: [{ type: "input_text", text: input }] }] : input

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

        # Only add temperature and top_p for non-reasoning models
        # Reasoning models (GPT-5, o1) don't support these parameters
        unless reasoning_model?(model)
          body[:temperature] = temperature if temperature
          body[:top_p] = top_p if top_p
        end

        body[:max_output_tokens] = max_tokens if max_tokens # OpenAI Responses API uses max_output_tokens
        body[:stream] = stream if stream
        # Note: frequency_penalty, presence_penalty, best_of, logit_bias are NOT added
        # They are unsupported by Responses API and have been filtered out with warnings
        # For reasoning models, temperature and top_p are also filtered

        # Add response_format for structured output via text.format parameter
        # Responses API uses different parameter structure than Chat Completions API
        # See: https://platform.openai.com/docs/api-reference/responses/create
        #
        # Chat Completions API format (OLD):
        # response_format: { type: "json_schema", json_schema: { name: "...", schema: {...} } }
        #
        # Responses API format (NEW):
        # text: { format: { name: "...", type: "json_schema", schema: {...} } }
        #
        # We need to flatten the json_schema contents into format
        if response_format
          if response_format[:type] == "json_schema" && response_format[:json_schema]
            # Flatten json_schema contents into format
            json_schema = response_format[:json_schema]
            body[:text] = {
              format: {
                name: json_schema[:name],
                type: "json_schema",
                strict: json_schema[:strict],
                schema: json_schema[:schema]
              }
            }
          else
            # Fallback: pass as-is (shouldn't happen with RAAF)
            body[:text] = { format: response_format }
          end
        end

        # Debug logging for continuation chunk
        log_debug("Continuation chunk #{chunk_number}",
                  model: model,
                  input_length: list_input.length,
                  tools_count: converted_tools[:tools]&.length || 0,
                  previous_response_id: previous_response_id,
                  stream: stream)

        # DETAILED INPUT DEBUGGING - Check for duplicates in the actual API request
        all_input_ids = list_input.map { |item| item[:id] || item["id"] }.compact
        duplicate_input_ids = all_input_ids.group_by(&:itself).select { |_, v| v.size > 1 }.keys

        log_debug("📤 RESPONSES_PROVIDER: Final API request input composition",
                  category: "api_request",
                  total_items: list_input.length,
                  item_ids: all_input_ids,
                  duplicate_ids: duplicate_input_ids,
                  has_duplicates: duplicate_input_ids.any?,
                  previous_response_id: previous_response_id)

        if duplicate_input_ids.any?
          log_error("🚨 RESPONSES_PROVIDER: DUPLICATES DETECTED IN API REQUEST!",
                    category: "api_request",
                    duplicate_ids: duplicate_input_ids,
                    full_input_dump: list_input.map.with_index { |item, i| "#{i}: #{item.inspect}" })
        end

        # Make the API call
        if stream
          final_response = nil
          call_responses_api_stream(body) do |event|
            # Capture the final response from the completed event
            final_response = event.response if event.is_a?(RAAF::StreamingEvents::ResponseCompletedEvent)
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
        # Wrap the API call with retry logic if available
        api_call = lambda do
          uri = URI("#{@api_base}/responses")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          # Set configurable HTTP timeouts (default to 120 seconds)
          timeout_value = @http_timeout || 120
          http.read_timeout = timeout_value
          http.open_timeout = [timeout_value / 4, 30].min  # 1/4 of read timeout, max 30s

          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{@api_key}"
          request["Content-Type"] = "application/json"
          request["User-Agent"] = "Agents/Ruby #{RAAF::VERSION}"

          request.body = body.to_json

          # DEBUG: Log the actual request body being sent to OpenAI
          if body[:tools]
            log_debug_tools("📤 ACTUAL REQUEST BODY SENT TO OPENAI RESPONSES API",
                            tools_count: body[:tools].length,
                            request_body_json: body.to_json)

            # Check each tool for array parameters in the actual request
            body[:tools].each do |tool|
              next unless tool[:function] && tool[:function][:parameters] && tool[:function][:parameters][:properties]

              tool[:function][:parameters][:properties].each do |prop_name, prop_def|
                next unless prop_def[:type] == "array"

                log_debug_tools("🔍 ACTUAL REQUEST ARRAY PROPERTY #{prop_name} SENT TO OPENAI",
                                has_items: prop_def.key?(:items),
                                items_value: prop_def[:items].inspect,
                                items_nil: prop_def[:items].nil?)
              end
            end
          end

          http.request(request)
        end

        # Use retry logic from ModelInterface
        response = with_retry("responses_completion", &api_call)

        unless response.code.start_with?("2")
          log_error("OpenAI Responses API Error",
                    status_code: response.code,
                    response_body: response.body,
                    request_body: body.to_json)
          handle_api_error(response, provider_name)
        end

        parsed_response = RAAF::Utils.parse_json(response.body)

        # DEBUG: Log raw response to see all fields
        log_debug("📥 RAW OPENAI RESPONSES API RESPONSE",
                  category: "api_response",
                  response_keys: parsed_response.keys,
                  full_response: parsed_response.to_json)

        # Handle truncation detection and continuation
        # NOTE: OpenAI Responses API uses "truncation" field, not "finish_reason"
        # Maps truncation status to finish_reason for compatibility
        finish_reason = infer_finish_reason(parsed_response)

        # Log based on finish_reason
        case finish_reason
        when "length"
          log_debug("Response truncated - will continue sequence",
                    finish_reason: "length",
                    response_id: parsed_response["id"])
        when "content_filter"
          log_warn("Content filtered by safety system",
                   filter_type: parsed_response.dig("metadata", "filter_type"))
        when "incomplete"
          log_warn("Response marked as incomplete",
                   reason: parsed_response.dig("metadata", "reason"),
                   suggestion: "Use previous_response_id to continue: #{parsed_response["id"]}")
        when "error"
          log_error("API returned error finish_reason",
                    error: parsed_response["error"])
        end

        # Debug logging for successful responses
        log_debug("OpenAI Responses API Success",
                  response_id: parsed_response["id"],
                  output_items: parsed_response["output"]&.length || 0,
                  finish_reason: finish_reason,
                  usage: parsed_response["usage"])

        # Return the raw Responses API response with indifferent access
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
      # @yieldparam event [RAAF::StreamingEvents::Base] Parsed streaming event
      #
      # @raise [APIError] If the API returns an error
      #
      # @api private
      #
      def call_responses_api_stream(body, &block)
        uri = URI("#{@api_base}/responses")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        # Set configurable HTTP timeouts (default to 120 seconds, streaming may need longer)
        timeout_value = @http_timeout || 120
        http.read_timeout = timeout_value
        http.open_timeout = [timeout_value / 4, 30].min  # 1/4 of read timeout, max 30s

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
                      model: body[:model])

        http.request(request) do |response|
          unless response.code.start_with?("2")
            error_body = response.read_body
            log_error("OpenAI Responses API Streaming Error",
                      status_code: response.code,
                      response_body: error_body,
                      request_body: stream_body.to_json)
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

        return unless line.start_with?("data:")

        data = line[5..].strip

        # Handle end of stream
        return if data == "[DONE]"

        begin
          event_data = RAAF::Utils.parse_json(data)

          # Create and yield appropriate streaming event
          streaming_event = create_streaming_event(event_data)
          block.call(streaming_event) if streaming_event && block

          log_debug_api("Processed streaming event",
                        type: event_data[:type],
                        sequence: event_data[:sequence_number])
        rescue JSON::ParserError => e
          log_debug_api("Failed to parse streaming data",
                        data: data,
                        error: e.message)
        end
      end

      # Create appropriate streaming event objects based on API response
      def create_streaming_event(event_data)
        case event_data[:type]
        when "response.created"
          RAAF::StreamingEvents::ResponseCreatedEvent.new(
            response: event_data[:response],
            sequence_number: event_data[:sequence_number]
          )
        when "response.output_item.added"
          RAAF::StreamingEvents::ResponseOutputItemAddedEvent.new(
            item: event_data[:item],
            output_index: event_data[:output_index],
            sequence_number: event_data[:sequence_number]
          )
        when "response.output_item.done"
          RAAF::StreamingEvents::ResponseOutputItemDoneEvent.new(
            item: event_data[:item],
            output_index: event_data[:output_index],
            sequence_number: event_data[:sequence_number]
          )
        when "response.done"
          RAAF::StreamingEvents::ResponseCompletedEvent.new(
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
            input_items << { type: "message", role: "user", content: [{ type: "input_text", text: content }] }
          when "assistant"
            # Assistant messages become output items in the input
            if msg[:tool_calls]
              # Handle assistant message with both content and tool calls
              input_items << { type: "message", text: content } if content && !content.empty?
              # Handle tool calls
              msg[:tool_calls].each do |tool_call|
                input_items << convert_tool_call_to_input(tool_call)
              end
            else
              # Regular text message
              input_items << {
                type: "message",
                role: "assistant",
                content: [{ type: "output_text", text: content }]
              }
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
        arguments = tool_call.dig("function", "arguments") || tool_call.dig(:function, :arguments)
        # Parse JSON arguments if they're a string
        parsed_arguments = arguments.is_a?(String) ? JSON.parse(arguments) : arguments

        {
          type: "function_call",
          name: tool_call.dig("function", "name") || tool_call.dig(:function, :name),
          arguments: parsed_arguments,
          call_id: tool_call["id"] || tool_call[:id]
        }
      end

      # Extract system instructions from messages
      def extract_system_instructions(messages)
        system_msg = messages.find { |m| m[:role] == "system" || m["role"] == "system" }
        system_msg&.dig(:content) || system_msg&.dig("content")
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
          else
            # Check for WebSearchTool if it's defined
            if defined?(RAAF::Tools::WebSearchTool) && tool.is_a?(RAAF::Tools::WebSearchTool)
              converted_tools << { type: "web_search" }
              includes << "web_search_call.results"
              next
            end

            # Handle DSL tools that respond to tool_definition or tool_configuration
            if tool.respond_to?(:tool_definition)
              tool_def = tool.tool_definition
              if %w[web_search tavily_search].include?(tool_def[:type])
                converted_tools << { type: "web_search" }
                includes << "web_search_call.results"
              else
                # Convert DSL tool to function format
                function_def = tool_def[:function] || {}
                converted_tools << {
                  type: "function",
                  name: function_def[:name] || tool_def[:name] || (tool.respond_to?(:tool_name) ? tool.tool_name : "unknown_tool"),
                  description: function_def[:description] || tool_def[:description] || "AI tool",
                  parameters: prepare_function_parameters(function_def[:parameters] || tool_def[:parameters] || {}),
                  strict: determine_strict_mode(function_def[:parameters] || tool_def[:parameters] || {})
                }
              end
            elsif tool.respond_to?(:to_tool_definition)
              converted_tools << tool.to_tool_definition
            else
              raise ArgumentError,
                    "Unknown tool type: #{tool.class}. Tool must respond to :tool_definition or :to_tool_definition"
            end

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
          # Only set required if it was explicitly provided or already set to strict mode
          if params[:additionalProperties] == false && params.key?(:required)
            all_properties = params[:properties].keys.map(&:to_s)
            params[:required] = all_properties unless params[:required] == all_properties
          elsif !params.key?(:required)
            # If no required field was specified, keep it empty
            params[:required] = []
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
        when "auto", "required", "none", Hash
          # Standard tool choice strings and properly formatted Hashes
          tool_choice
        when String
          # Assume it's a specific tool name
          { type: "function", name: tool_choice }
        else
          # Default to auto for unrecognized types
          "auto"
        end
      end

      # Validates and warns about unsupported parameters
      # These parameters work with Chat Completions API but not Responses API
      # For reasoning models (GPT-5, o1), additional parameters are unsupported
      def validate_unsupported_parameters(model:, **params)
        # Determine which parameters are unsupported based on model type
        unsupported_params = if reasoning_model?(model)
                               REASONING_UNSUPPORTED_PARAMS
                             else
                               UNSUPPORTED_PARAMS
                             end

        unsupported = params.select { |key, value| unsupported_params.include?(key) && !value.nil? }

        unsupported.each do |param_name, param_value|
          if reasoning_model?(model)
            log_warn(
              "⚠️ Parameter '#{param_name}' is not supported by reasoning model #{model}",
              parameter: param_name,
              value: param_value,
              model: model,
              suggestion: "Remove this parameter - reasoning models (GPT-5, o1) only support default settings",
              documentation: "https://platform.openai.com/docs/guides/reasoning"
            )
          else
            log_warn(
              "⚠️ Parameter '#{param_name}' is not supported by OpenAI Responses API",
              parameter: param_name,
              value: param_value,
              suggestion: "Remove this parameter or use Chat Completions API (OpenAIProvider) instead",
              documentation: "https://platform.openai.com/docs/api-reference/responses"
            )
          end
        end
      end

      def convert_response_format(response_format)
        return unless response_format.is_a?(Hash) && response_format[:type] == "json_schema"

        schema = response_format.dig(:json_schema, :schema)
        is_strict = response_format.dig(:json_schema, :strict)

        # Process schema through StrictSchema if strict mode is enabled
        if is_strict && schema
          schema = RAAF::StrictSchema.ensure_strict_json_schema(schema)
        end

        {
          format: {
            type: "json_schema",
            name: response_format.dig(:json_schema, :name),
            schema: schema,
            strict: is_strict
          }
        }
      end

    end

  end

end

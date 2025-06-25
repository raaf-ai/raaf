# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "securerandom"
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

      # Indicates this provider supports prompts (for Responses API)
      def supports_prompts?
        true
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

      # Prepares tools for the Responses API format
      #
      # @param tools [Array] array of tools to prepare
      # @return [Array, nil] prepared tools or nil if no tools
      # @api private
      def prepare_tools_for_responses_api(tools)
        return nil unless tools.respond_to?(:empty?) && tools.respond_to?(:map)
        return nil if tools.empty?

        tools.map do |tool|
          case tool
          when Hash
            # Handle simple web search tool format
            if tool[:type] == "web_search" || tool["type"] == "web_search"
              { type: "web_search" }
            # Handle function tools
            elsif tool[:function] && tool[:function][:name] && !tool[:name]
              tool.merge(name: tool[:function][:name])
            else
              tool
            end
          when OpenAIAgents::FunctionTool
            # Convert FunctionTool to Responses API format with top-level name
            {
              type: "function",
              name: tool.name,
              function: {
                name: tool.name,
                description: tool.description,
                parameters: tool.parameters
              }
            }
          else
            raise ArgumentError, "Invalid tool type: #{tool.class}" unless tool.respond_to?(:to_tool_definition)

            tool.to_tool_definition

          end
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

        # Add prompt support if provided
        if kwargs[:prompt]
          body[:prompt] = kwargs[:prompt]
          kwargs = kwargs.dup
          kwargs.delete(:prompt)
        end

        # Process tools before merging kwargs
        if kwargs[:tools]
          kwargs = kwargs.dup
          kwargs[:tools] = prepare_tools_for_responses_api(kwargs[:tools])
        end

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

      # Extracts input from messages for Responses API
      #
      # @param messages [Array] array of conversation messages
      # @return [String] the last user message content
      # @api private
      def extract_input_from_messages(messages)
        # Extract the last user message as input (matching Python behavior)
        user_msg = messages.reverse.find { |m| m[:role] == "user" }
        user_msg&.dig(:content) || ""
      end

      # Extracts system instructions from messages
      #
      # @param messages [Array] array of conversation messages
      # @return [String, nil] system message content if found
      # @api private
      def extract_system_instructions(messages)
        system_msg = messages.find { |m| m[:role] == "system" }
        system_msg&.dig(:content)
      end

      # Converts Responses API format to chat completion format
      #
      # @param response [Hash] the response from Responses API
      # @return [Hash, nil] converted response in chat format
      # @api private
      def convert_response_to_chat_format(response)
        # Convert OpenAI Responses API format to chat completion format
        # for compatibility with existing Ruby code
        return nil unless response && response["output"]

        # Debug logging in development
        if %w[development test].include?(ENV["RAILS_ENV"])
          puts "[ResponsesProvider] Raw API response output: #{response["output"].inspect}"
        end

        # Extract the text content from response output
        # Handle both tool calls and structured output properly
        content = extract_content_from_output(response["output"])
        tool_calls = extract_tool_calls_from_output(response["output"])

        # Debug logging for tool calls
        if tool_calls && ENV["RAILS_ENV"] == "development"
          puts "[ResponsesProvider] Extracted tool calls: #{tool_calls.inspect}"
        end

        message = {
          "role" => "assistant",
          "content" => content
        }

        # Add tool calls if present
        message["tool_calls"] = tool_calls if tool_calls && !tool_calls.empty?

        {
          "id" => response["id"],
          "object" => "chat.completion",
          "created" => Time.now.to_i,
          "model" => response["model"] || "gpt-4o",
          "choices" => [
            {
              "index" => 0,
              "message" => message,
              "finish_reason" => tool_calls && !tool_calls.empty? ? "tool_calls" : "stop"
            }
          ],
          "usage" => response["usage"] || {
            "prompt_tokens" => 0,
            "completion_tokens" => 0,
            "total_tokens" => 0
          }
        }
      end

      def extract_content_from_output(output)
        return "" unless output

        if output.is_a?(Array) && !output.empty?
          # Handle array format - look for text content
          output.map do |item|
            if item.is_a?(Hash)
              # Check for structured text content
              if item["content"].is_a?(Array)
                item["content"].map do |content_item|
                  if content_item.is_a?(Hash) && content_item["type"] == "output_text"
                    content_item["text"] || ""
                  else
                    content_item.to_s
                  end
                end.join
              elsif item["type"] == "output_text"
                item["text"] || ""
              elsif item["text"]
                item["text"]
              elsif item["content"]
                item["content"]
              else
                # Skip tool call items, only extract text content
                next if item["type"] == "function_call" || item["function"]

                item.to_s
              end
            else
              item.to_s
            end
          end.compact.join
        elsif output.is_a?(Hash)
          # Handle single hash format
          if output["text"]
            output["text"]
          elsif output["content"]
            output["content"]
          else
            # Don't include tool call results as content
            return "" if output["type"] == "function_call" || output["function"]

            output.to_s
          end
        else
          # Fallback for other formats
          output.to_s
        end
      end

      def extract_tool_calls_from_output(output)
        return nil unless output

        tool_calls = []

        if output.is_a?(Array)
          output.each do |item|
            next unless item.is_a?(Hash)

            # Check for function call format
            next unless item["type"] == "function_call" || item["function"]

            # Extract arguments properly - they might be in different formats
            arguments = extract_function_arguments(item)

            tool_call = {
              "id" => item["id"] || item["call_id"] || "call_#{SecureRandom.hex(8)}",
              "type" => "function",
              "function" => {
                "name" => item["name"] || item.dig("function", "name"),
                "arguments" => arguments
              }
            }
            tool_calls << tool_call
          end
        elsif output.is_a?(Hash) && (output["type"] == "function_call" || output["function"])
          # Extract arguments properly - they might be in different formats
          arguments = extract_function_arguments(output)

          tool_call = {
            "id" => output["id"] || output["call_id"] || "call_#{SecureRandom.hex(8)}",
            "type" => "function",
            "function" => {
              "name" => output["name"] || output.dig("function", "name"),
              "arguments" => arguments
            }
          }
          tool_calls << tool_call
        end

        tool_calls.empty? ? nil : tool_calls
      end

      def extract_function_arguments(item)
        # Try different sources for arguments
        args = item["arguments"] || item.dig("function", "arguments")

        # If arguments is already a string, return it
        return args if args.is_a?(String) && args != "{}"

        # If arguments is a hash, convert to JSON
        return args.to_json if args.is_a?(Hash) && !args.empty?

        # If no arguments found, check for direct parameters
        if item["parameters"] || item.dig("function", "parameters")
          params = item["parameters"] || item.dig("function", "parameters")
          return params.to_json if params.is_a?(Hash) && !params.empty?
          return params if params.is_a?(String) && params != "{}"
        end

        # For web search tools, provide a default query if none specified
        tool_name = item["name"] || item.dig("function", "name")
        return '{"query": "company information research"}' if tool_name&.include?("web_search")

        # Default to empty object
        "{}"
      end
    end
  end
end

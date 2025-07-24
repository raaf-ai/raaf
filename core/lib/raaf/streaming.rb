# frozen_string_literal: true

require "net/http"
require "json"
require_relative "models/responses_provider"

module RAAF

  ##
  # StreamingClient handles real-time streaming responses from AI providers
  #
  # This client manages streaming connections to both the Chat Completions API
  # and the Responses API, automatically selecting the appropriate endpoint
  # based on the tools being used. It provides real-time token streaming
  # for improved user experience.
  #
  # @example Basic streaming
  #   client = StreamingClient.new(api_key: ENV['OPENAI_API_KEY'])
  #
  #   client.stream_completion(
  #     messages: [{ role: "user", content: "Tell me a story" }],
  #     model: "gpt-4o"
  #   ) do |chunk|
  #     print chunk[:content] if chunk[:type] == "content"
  #   end
  #
  # @example With tool calls
  #   client.stream_completion(
  #     messages: messages,
  #     model: "gpt-4o",
  #     tools: [weather_tool]
  #   ) do |chunk|
  #     case chunk[:type]
  #     when "content"
  #       print chunk[:content]
  #     when "tool_call"
  #       puts "Calling tool: #{chunk[:tool_call]["function"]["name"]}"
  #     end
  #   end
  #
  class StreamingClient

    ##
    # Initialize a new streaming client
    #
    # @param api_key [String] OpenAI API key
    # @param api_base [String] Base URL for API (default: OpenAI)
    # @param provider [Models::Interface, nil] Optional custom provider
    #
    def initialize(api_key:, api_base: "https://api.openai.com/v1", provider: nil)
      @api_key = api_key
      @api_base = api_base
      # Use ResponsesProvider as the default for modern API compatibility
      @provider = provider || Models::ResponsesProvider.new(api_key: api_key, api_base: api_base)
    end

    ##
    # Stream a completion from the AI model
    #
    # Automatically selects the appropriate API endpoint based on the tools
    # being used. Hosted tools (web_search, file_search, computer) require
    # the Responses API.
    #
    # @param messages [Array<Hash>] Conversation messages
    # @param model [String] Model to use
    # @param tools [Array<Hash, FunctionTool>, nil] Available tools
    #
    # @yield [chunk] Yields streaming chunks as they arrive
    # @yieldparam chunk [Hash] Streaming chunk with type and data
    #
    # @return [Hash] Final accumulated response
    #
    def stream_completion(messages:, model:, tools: nil)
      # Check if we have hosted tools that require Responses API
      if tools && hosted_tools?(tools)
        stream_with_responses_api(messages: messages, model: model, tools: tools)
      else
        stream_with_chat_api(messages: messages, model: model, tools: tools)
      end
    end

    private

    def hosted_tools?(tools)
      return false unless tools

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

    def stream_with_responses_api(messages:, model:, tools:)
      uri = URI("https://api.openai.com/v1/responses")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"

      # Convert messages to input format for Responses API
      input = safe_extract_last_message_content(messages)

      body = {
        model: model,
        input: input,
        stream: true,
        tools: prepare_tools_for_responses_api(tools)
      }

      request.body = JSON.generate(body)

      accumulated_content = ""

      http.request(request) do |response|
        response.read_body do |chunk|
          chunk.split("\n").each do |line|
            next unless line.start_with?("data: ")

            data = line[6..].strip
            next if data.empty? || data == "[DONE]"

            begin
              json_data = JSON.parse(data)
              content = extract_content_from_responses_stream(json_data)
              if content
                accumulated_content += content
                yield(content) if block_given?
              end
            rescue JSON::ParserError
              # Skip invalid JSON
            end
          end
        end
      end

      { content: accumulated_content }
    end

    def stream_with_chat_api(messages:, model:, tools:)
      uri = URI("#{@api_base}/chat/completions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request["Accept"] = "text/event-stream"

      body = {
        model: model,
        messages: messages,
        stream: true,
        max_tokens: 1000
      }
      body[:tools] = tools if tools

      request.body = JSON.generate(body)

      accumulated_content = ""
      accumulated_tool_calls = {}

      http.request(request) do |response|
        response.read_body do |chunk|
          chunk.split("\n").each do |line|
            next unless line.start_with?("data: ")

            data = line[6..].strip
            next if data.empty? || data == "[DONE]"

            begin
              json_data = JSON.parse(data)
              delta = json_data.dig("choices", 0, "delta")

              if delta
                # Handle content streaming
                if delta["content"]
                  accumulated_content += delta["content"]
                  if block_given?
                    yield({
                      type: "content",
                      content: delta["content"],
                      accumulated_content: accumulated_content
                    })
                  end
                end

                # Handle tool call streaming
                delta["tool_calls"]&.each do |tool_call|
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

                # Handle finish reason
                if json_data.dig("choices", 0, "finish_reason") && block_given?
                  yield({
                    type: "finish",
                    finish_reason: json_data.dig("choices", 0, "finish_reason"),
                    accumulated_content: accumulated_content,
                    accumulated_tool_calls: accumulated_tool_calls.values
                  })
                end
              end
            rescue JSON::ParserError
              # Skip malformed JSON
              next
            end
          end
        end
      end

      {
        content: accumulated_content,
        tool_calls: accumulated_tool_calls.values
      }
    end

    def prepare_tools_for_responses_api(tools)
      tools.map do |tool|
        case tool
        when RAAF::Tools::WebSearchTool, RAAF::Tools::HostedFileSearchTool, RAAF::Tools::HostedComputerTool
          tool.to_tool_definition
        when Hash
          tool
        else
          # Convert FunctionTool to hash format
          tool.respond_to?(:to_h) ? tool.to_h : tool
        end
      end
    end

    def extract_content_from_responses_stream(event)
      # Extract content from Responses API streaming event
      if event["output"] && event["output"][0] && event["output"][0]["content"]
        content = event["output"][0]["content"][0]["text"]
        return content if content
      end
      nil
    end

  end

end

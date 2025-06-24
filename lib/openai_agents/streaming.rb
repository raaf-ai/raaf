# frozen_string_literal: true

require "net/http"
require "json"
require_relative "models/openai_provider"

module OpenAIAgents
  class StreamingClient
    def initialize(api_key:, api_base: "https://api.openai.com/v1", provider: nil)
      @api_key = api_key
      @api_base = api_base
      @provider = provider || Models::OpenAIProvider.new(api_key: api_key, api_base: api_base)
    end

    def stream_completion(messages:, model:, tools: nil)
      # Check if we have hosted tools that require Responses API
      if tools && has_hosted_tools?(tools)
        stream_with_responses_api(messages: messages, model: model, tools: tools)
      else
        stream_with_chat_api(messages: messages, model: model, tools: tools)
      end
    end

    private

    def has_hosted_tools?(tools)
      return false unless tools

      tools.any? do |tool|
        case tool
        when OpenAIAgents::Tools::WebSearchTool, OpenAIAgents::Tools::HostedFileSearchTool, OpenAIAgents::Tools::HostedComputerTool
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

                  if tool_call.dig("function", "name")
                    accumulated_tool_calls[index]["function"]["name"] += tool_call["function"]["name"]
                  end

                  if tool_call.dig("function", "arguments")
                    accumulated_tool_calls[index]["function"]["arguments"] += tool_call["function"]["arguments"]
                  end

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
        when OpenAIAgents::Tools::WebSearchTool, OpenAIAgents::Tools::HostedFileSearchTool, OpenAIAgents::Tools::HostedComputerTool
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

  class StreamingRunner < Runner
    def initialize(agent:, tracer: nil)
      super
      @streaming_client = StreamingClient.new(
        api_key: @api_key,
        api_base: @api_base
      )
    end

    def run_streaming(messages)
      @tracer.trace("streaming_run_start", { agent: @agent.name, messages: messages.size })

      conversation = messages.dup
      current_agent = @agent
      turns = 0

      while turns < current_agent.max_turns
        @tracer.trace("streaming_turn_start", { turn: turns, agent: current_agent.name })

        api_messages = build_messages(conversation, current_agent)
        tools = current_agent.tools? ? current_agent.tools.map(&:to_h) : nil

        # Stream the completion
        result = @streaming_client.stream_completion(
          messages: api_messages,
          model: current_agent.model,
          tools: tools
        ) do |chunk|
          yield(chunk) if block_given?
        end

        # Process the complete response
        assistant_message = {
          role: "assistant",
          content: result[:content]
        }
        assistant_message[:tool_calls] = result[:tool_calls] if result[:tool_calls].any?

        conversation << assistant_message

        # Handle tool calls
        if result[:tool_calls].any?
          process_tool_calls(result[:tool_calls], current_agent, conversation)
        else
          # Check for handoff
          if result[:content].include?("HANDOFF:")
            handoff_match = result[:content].match(/HANDOFF:\s*(\w+)/)
            if handoff_match
              handoff_agent = current_agent.find_handoff(handoff_match[1])
              if handoff_agent
                @tracer.trace("handoff", { from: current_agent.name, to: handoff_agent.name })
                current_agent = handoff_agent
                turns = 0
                next
              end
            end
          end

          break # No tool calls and no handoff, we're done
        end

        turns += 1
      end

      raise MaxTurnsError, "Maximum turns (#{current_agent.max_turns}) exceeded" if turns >= current_agent.max_turns

      @tracer.trace("streaming_run_complete", { final_agent: current_agent.name, total_turns: turns })

      {
        messages: conversation,
        agent: current_agent,
        turns: turns,
        traces: @tracer.traces
      }
    end

    private

    def safe_extract_last_message_content(messages)
      return "" unless messages.is_a?(Array) && !messages.empty?

      last_message = messages.last
      return "" unless last_message.is_a?(Hash)

      last_message[:content] || last_message["content"] || ""
    end
  end
end

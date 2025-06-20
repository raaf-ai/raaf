# frozen_string_literal: true

require "async"
require "json"
require "net/http"
require "uri"
require_relative "agent"
require_relative "tracing"
require_relative "errors"

module OpenAIAgents
  class Runner
    attr_reader :agent, :tracer

    def initialize(agent:, tracer: nil)
      @agent = agent
      @tracer = tracer || Tracer.new
      @api_key = ENV.fetch("OPENAI_API_KEY", nil)
      @api_base = ENV["OPENAI_API_BASE"] || "https://api.openai.com/v1"
    end

    def run(messages, stream: false)
      @tracer.trace("run_start", { agent: @agent.name, messages: messages.size })

      conversation = messages.dup
      current_agent = @agent
      turns = 0

      while turns < current_agent.max_turns
        @tracer.trace("turn_start", { turn: turns, agent: current_agent.name })

        # Prepare messages for API call
        api_messages = build_messages(conversation, current_agent)

        # Make API call
        response = if stream
                     stream_completion(api_messages, current_agent)
                   else
                     create_completion(api_messages, current_agent)
                   end

        @tracer.trace("api_response", { response: response })

        # Process response
        result = process_response(response, current_agent, conversation)

        turns += 1

        # Check for handoff
        if result[:handoff]
          handoff_agent = current_agent.find_handoff(result[:handoff])
          raise HandoffError, "Cannot handoff to '#{result[:handoff]}'" unless handoff_agent

          @tracer.trace("handoff", { from: current_agent.name, to: handoff_agent.name })
          current_agent = handoff_agent
          turns = 0 # Reset turn counter for new agent
          next

        end

        # Check if we're done
        break if result[:done]

        # Check max turns for current agent
        raise MaxTurnsError, "Maximum turns (#{current_agent.max_turns}) exceeded" if turns >= current_agent.max_turns
      end

      @tracer.trace("run_complete", { final_agent: current_agent.name, total_turns: turns })

      {
        messages: conversation,
        agent: current_agent,
        turns: turns,
        traces: @tracer.traces
      }
    end

    def run_async(messages, stream: false)
      Async do
        run(messages, stream: stream)
      end
    end

    private

    def build_messages(conversation, agent)
      system_message = {
        role: "system",
        content: build_system_prompt(agent)
      }

      [system_message] + conversation
    end

    def build_system_prompt(agent)
      prompt = ""
      prompt += "Name: #{agent.name}\n" if agent.name
      prompt += "Instructions: #{agent.instructions}\n" if agent.instructions

      if agent.tools?
        prompt += "\nAvailable tools:\n"
        agent.tools.each do |tool|
          prompt += "- #{tool.name}: #{tool.description}\n"
        end
      end

      unless agent.handoffs.empty?
        prompt += "\nAvailable handoffs:\n"
        agent.handoffs.each do |handoff_agent|
          prompt += "- #{handoff_agent.name}\n"
        end
        prompt += "\nTo handoff to another agent, include 'HANDOFF: <agent_name>' in your response.\n"
      end

      prompt
    end

    def create_completion(messages, agent)
      uri = URI("#{@api_base}/chat/completions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"

      tools = agent.tools? ? agent.tools.map(&:to_h) : nil

      body = {
        model: agent.model,
        messages: messages,
        max_tokens: 1000
      }
      body[:tools] = tools if tools

      request.body = JSON.generate(body)

      response = http.request(request)
      JSON.parse(response.body)
    end

    def stream_completion(messages, agent)
      # Simplified streaming implementation
      # In a real implementation, you'd handle Server-Sent Events
      create_completion(messages, agent)
    end

    def process_response(response, agent, conversation)
      choice = response.dig("choices", 0)
      message = choice["message"]

      conversation << {
        role: "assistant",
        content: message["content"]
      }

      result = { done: false, handoff: nil }

      # Check for tool calls
      result[:done] = process_tool_calls(message["tool_calls"], agent, conversation) if message["tool_calls"]

      # Check for handoff
      if message["content"]&.include?("HANDOFF:")
        handoff_match = message["content"].match(/HANDOFF:\s*(\w+)/)
        result[:handoff] = handoff_match[1] if handoff_match
      end

      # If no tool calls and no handoff, we're done
      result[:done] = true if !message["tool_calls"] && !result[:handoff]

      result
    end

    def process_tool_calls(tool_calls, agent, conversation)
      tool_calls.each do |tool_call|
        tool_name = tool_call.dig("function", "name")
        arguments = JSON.parse(tool_call.dig("function", "arguments") || "{}")

        @tracer.trace("tool_call", { tool: tool_name, arguments: arguments })

        begin
          result = agent.execute_tool(tool_name, **arguments.transform_keys(&:to_sym))

          conversation << {
            role: "tool",
            tool_call_id: tool_call["id"],
            content: result.to_s
          }

          @tracer.trace("tool_result", { tool: tool_name, result: result })
        rescue StandardError => e
          @tracer.trace("tool_error", { tool: tool_name, error: e.message })

          conversation << {
            role: "tool",
            tool_call_id: tool_call["id"],
            content: "Error: #{e.message}"
          }
        end
      end

      false # Continue conversation after tool calls
    end
  end
end

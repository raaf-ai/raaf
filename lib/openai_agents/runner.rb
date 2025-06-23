# frozen_string_literal: true

require "async"
require "json"
require "net/http"
require "uri"
require_relative "agent"
require_relative "tracing"
require_relative "tracing/spans"
require_relative "errors"

module OpenAIAgents
  class Runner
    attr_reader :agent, :tracer

    def initialize(agent:, tracer: nil)
      @agent = agent
      @tracer = tracer || setup_default_tracer
      @api_key = ENV.fetch("OPENAI_API_KEY", nil)
      @api_base = ENV["OPENAI_API_BASE"] || "https://api.openai.com/v1"
    end

    def run(messages, stream: false)
      # Start main execution span
      @tracer.start_span("agent.run", kind: :agent, 
                         "agent.name" => @agent.name, 
                         "messages.count" => messages.size) do |run_span|
        
        conversation = messages.dup
        current_agent = @agent
        turns = 0

        while turns < current_agent.max_turns
          @tracer.start_span("agent.turn", kind: :agent,
                            "turn.number" => turns,
                            "agent.name" => current_agent.name) do |turn_span|

            # Prepare messages for API call
            api_messages = build_messages(conversation, current_agent)

            # Make API call
            response = if stream
                         stream_completion(api_messages, current_agent)
                       else
                         create_completion(api_messages, current_agent)
                       end

            turn_span.set_attribute("response.model", response.dig("model"))
            turn_span.set_attribute("response.usage.prompt_tokens", response.dig("usage", "prompt_tokens"))
            turn_span.set_attribute("response.usage.completion_tokens", response.dig("usage", "completion_tokens"))

            # Process response
            result = process_response(response, current_agent, conversation)

            turns += 1

            # Check for handoff
            if result[:handoff]
              handoff_agent = current_agent.find_handoff(result[:handoff])
              raise HandoffError, "Cannot handoff to '#{result[:handoff]}'" unless handoff_agent

              @tracer.handoff_span(current_agent.name, handoff_agent.name) do |handoff_span|
                handoff_span.set_attribute("handoff.reason", result[:handoff])
                current_agent = handoff_agent
                turns = 0 # Reset turn counter for new agent
              end
              next
            end

            # Check if we're done
            break if result[:done]

            # Check max turns for current agent
            raise MaxTurnsError, "Maximum turns (#{current_agent.max_turns}) exceeded" if turns >= current_agent.max_turns
          end
        end

        run_span.set_attribute("run.final_agent", current_agent.name)
        run_span.set_attribute("run.total_turns", turns)
        run_span.set_attribute("run.status", "completed")

        {
          messages: conversation,
          agent: current_agent,
          turns: turns,
          traces: respond_to?(:export_spans) ? @tracer.export_spans : @tracer.traces
        }
      end
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
      @tracer.llm_span(agent.model, 
                       "llm.request.type" => "chat.completions",
                       "llm.request.model" => agent.model) do |llm_span|
        
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

        llm_span.set_attribute("llm.request.messages", messages)
        llm_span.set_attribute("llm.request.max_tokens", 1000)
        llm_span.set_attribute("llm.request.tools.count", tools&.size || 0)

        request.body = JSON.generate(body)

        response = http.request(request)
        parsed_response = JSON.parse(response.body)

        # Add response attributes to span
        if parsed_response["usage"]
          llm_span.set_attribute("llm.usage.prompt_tokens", parsed_response["usage"]["prompt_tokens"])
          llm_span.set_attribute("llm.usage.completion_tokens", parsed_response["usage"]["completion_tokens"])
          llm_span.set_attribute("llm.usage.total_tokens", parsed_response["usage"]["total_tokens"])
        end
        
        # Add response content
        if parsed_response.dig("choices", 0, "message", "content")
          llm_span.set_attribute("llm.response.content", parsed_response.dig("choices", 0, "message", "content"))
        end
        
        if parsed_response["error"]
          llm_span.set_status(:error, description: parsed_response["error"]["message"])
        else
          llm_span.set_status(:ok)
        end

        parsed_response
      end
    end

    def stream_completion(messages, agent)
      # Simplified streaming implementation
      # In a real implementation, you'd handle Server-Sent Events
      create_completion(messages, agent)
    end

    def process_response(response, agent, conversation)
      # Handle error responses
      if response["error"]
        @tracer.add_event("api_error", error: response["error"])
        return { done: true, handoff: nil, error: response["error"] }
      end

      choice = response.dig("choices", 0)
      return { done: true, handoff: nil } unless choice
      
      message = choice["message"]
      return { done: true, handoff: nil } unless message

      # Build assistant message - handle both content and tool calls
      assistant_message = { role: "assistant" }
      
      # Add content if present and not null
      assistant_message[:content] = message["content"] if message["content"]
      
      # Add tool calls if present
      assistant_message[:tool_calls] = message["tool_calls"] if message["tool_calls"]
      
      # Only add message to conversation if it has content or tool calls
      if assistant_message[:content] || assistant_message[:tool_calls]
        conversation << assistant_message
      end

      result = { done: false, handoff: nil }

      # Check for tool calls
      if message["tool_calls"]
        result[:done] = process_tool_calls(message["tool_calls"], agent, conversation)
      end

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

        @tracer.tool_span(tool_name, 
                          "tool.call_id" => tool_call["id"],
                          "tool.arguments" => arguments) do |tool_span|
          
          begin
            result = agent.execute_tool(tool_name, **arguments.transform_keys(&:to_sym))

            conversation << {
              role: "tool",
              tool_call_id: tool_call["id"],
              content: result.to_s
            }

            tool_span.set_attribute("tool.result", result.to_s[0...1000]) # Limit size
            tool_span.set_status(:ok)
          rescue StandardError => e
            conversation << {
              role: "tool",
              tool_call_id: tool_call["id"],
              content: "Error: #{e.message}"
            }

            tool_span.set_status(:error, description: e.message)
            tool_span.add_event("exception", 
                               "exception.type" => e.class.name,
                               "exception.message" => e.message)
          end
        end
      end

      false # Continue conversation after tool calls
    end

    private

    def setup_default_tracer
      # Always use SpanTracer for consistency
      tracer = OpenAIAgents::Tracing::SpanTracer.new

      # Only add processors if tracing is enabled
      unless ENV["OPENAI_AGENTS_DISABLE_TRACING"] == "1"
        # Add OpenAI processor if API key is available
        if @api_key || ENV["OPENAI_API_KEY"]
          tracer.add_processor(OpenAIAgents::Tracing::OpenAIProcessor.new)
        end
        
        # Always add console processor for local debugging (unless tracing disabled)
        tracer.add_processor(OpenAIAgents::Tracing::ConsoleSpanProcessor.new) if $DEBUG
      end

      tracer
    end
  end
end

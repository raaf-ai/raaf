# frozen_string_literal: true

require "async"
require "json"
require "net/http"
require "uri"
require_relative "agent"
require_relative "errors"
require_relative "models/responses_provider"
require_relative "tracing/trace_provider"
require_relative "structured_output"
require_relative "result"
require_relative "run_config"

module OpenAIAgents
  class Runner
    attr_reader :agent, :tracer

    def initialize(agent:, provider: nil, tracer: nil, disabled_tracing: false)
      @agent = agent
      @provider = provider || Models::ResponsesProvider.new
      @disabled_tracing = disabled_tracing || ENV["OPENAI_AGENTS_DISABLE_TRACING"] == "true"
      @tracer = tracer || (@disabled_tracing ? nil : OpenAIAgents.tracer)
    end

    def run(messages, stream: false, config: nil, **kwargs)
      # Normalize messages input - handle both string and array formats
      messages = normalize_messages(messages)

      # Handle both config object and legacy parameters
      if config.nil? && !kwargs.empty?
        # Legacy support: create config from kwargs
        config = RunConfig.new(
          stream: stream,
          workflow_name: kwargs[:workflow_name] || "Agent workflow",
          trace_id: kwargs[:trace_id],
          group_id: kwargs[:group_id],
          metadata: kwargs[:metadata],
          **kwargs
        )
      elsif config.nil?
        config = RunConfig.new(stream: stream)
      end

      # Check if tracing is disabled
      if config.tracing_disabled || @disabled_tracing || @tracer.nil?
        return run_without_tracing(messages, config: config)
      end

      # Check if we're already inside a trace
      require_relative "tracing/trace"
      current_trace = Tracing::Context.current_trace

      if current_trace && current_trace.active?
        # We're inside an existing trace, just run normally
        run_with_tracing(messages, config: config, parent_span: nil)
      else
        # Create a new trace for this run
        workflow_name = config.workflow_name || "Agent workflow"

        Tracing.trace(workflow_name,
                      trace_id: config.trace_id,
                      group_id: config.group_id,
                      metadata: config.metadata) do |_trace|
          run_with_tracing(messages, config: config, parent_span: nil)
        end
      end
    end

    def run_async(messages, stream: false, config: nil, **kwargs)
      Async do
        run(messages, stream: stream, config: config, **kwargs)
      end
    end

    private

    def run_with_tracing(messages, config:, parent_span: nil)
      @current_config = config # Store for tool calls
      conversation = messages.dup
      current_agent = @agent
      turns = 0

      max_turns = config.max_turns || current_agent.max_turns

      while turns < max_turns
        # Create agent span as root span (matching Python implementation where agent span has parent_id: null)
        # Temporarily clear the span stack to make this span root
        original_span_stack = @tracer.instance_variable_get(:@context).instance_variable_get(:@span_stack).dup
        @tracer.instance_variable_get(:@context).instance_variable_set(:@span_stack, [])

        agent_result = @tracer.start_span("agent.#{current_agent.name || "agent"}", kind: :agent) do |agent_span|
          # Set agent span attributes to match Python implementation
          agent_span.set_attribute("agent.name", current_agent.name || "agent")
          agent_span.set_attribute("agent.handoffs", safe_map_names(current_agent.handoffs))
          agent_span.set_attribute("agent.tools", safe_map_names(current_agent.tools))
          agent_span.set_attribute("agent.output_type", "str")

          # Prepare messages for API call
          api_messages = build_messages(conversation, current_agent)
          model = config.model || current_agent.model

          # Add comprehensive agent span attributes matching Python implementation
          if config.trace_include_sensitive_data
            agent_span.set_attribute("agent.instructions", current_agent.instructions || "")
            agent_span.set_attribute("agent.input", conversation.last&.dig(:content) || "")
          else
            agent_span.set_attribute("agent.instructions", "[REDACTED]")
            agent_span.set_attribute("agent.input", "[REDACTED]")
          end
          agent_span.set_attribute("agent.model", model)

          # Make API call using provider - the ResponsesProvider handles its own tracing
          # Merge config parameters with API call
          model_params = config.to_model_params

          response = if config.stream
                       @provider.stream_completion(
                         messages: api_messages,
                         model: model,
                         tools: current_agent.tools? ? current_agent.tools : nil,
                         **model_params
                       )
                     else
                       @provider.chat_completion(
                         messages: api_messages,
                         model: model,
                         tools: current_agent.tools? ? current_agent.tools : nil,
                         stream: false,
                         **model_params
                       )
                     end

          # Set agent output after API call
          if config.trace_include_sensitive_data
            assistant_response = response.dig("choices", 0, "message", "content") || ""
            agent_span.set_attribute("agent.output", assistant_response)
          else
            agent_span.set_attribute("agent.output", "[REDACTED]")
          end

          # Add token information to agent span to match Python format
          if response.is_a?(Hash) && response["usage"]
            total_tokens = response["usage"]["total_tokens"]
            agent_span.set_attribute("agent.tokens", "#{total_tokens} total") if total_tokens
          end

          # Process response
          result = process_response(response, current_agent, conversation)

          # Restore original span stack
          @tracer.instance_variable_get(:@context).instance_variable_set(:@span_stack, original_span_stack)

          result
        end # End of agent_span

        turns += 1

        # Check for handoff
        if agent_result[:handoff]
          handoff_agent = current_agent.find_handoff(agent_result[:handoff])
          raise HandoffError, "Cannot handoff to '#{agent_result[:handoff]}'" unless handoff_agent

          @tracer.handoff_span(current_agent.name || "agent",
                               handoff_agent.name || agent_result[:handoff]) do |handoff_span|
            handoff_span.add_event("handoff.initiated", attributes: {
                                     "handoff.from" => current_agent.name || "agent",
                                     "handoff.to" => handoff_agent.name || agent_result[:handoff]
                                   })
          end

          current_agent = handoff_agent
          turns = 0 # Reset turn counter for new agent
          next
        end

        # Check if we're done
        break if agent_result[:done]

        # Check max turns for current agent
        raise MaxTurnsError, "Maximum turns (#{current_agent.max_turns}) exceeded" if turns >= current_agent.max_turns
      end

      RunResult.success(
        messages: conversation,
        last_agent: current_agent,
        turns: turns
      )
    end

    def run_without_tracing(messages, config:)
      @current_config = config # Store for tool calls
      conversation = messages.dup
      current_agent = @agent
      turns = 0

      max_turns = config.max_turns || current_agent.max_turns

      while turns < max_turns
        # Prepare messages for API call
        api_messages = build_messages(conversation, current_agent)

        # Make API call using provider (supports hosted tools)
        model = config.model || current_agent.model
        model_params = config.to_model_params

        response = if config.stream
                     @provider.stream_completion(
                       messages: api_messages,
                       model: model,
                       tools: current_agent.tools? ? current_agent.tools : nil,
                       **model_params
                     )
                   else
                     @provider.chat_completion(
                       messages: api_messages,
                       model: model,
                       tools: current_agent.tools? ? current_agent.tools : nil,
                       stream: false,
                       **model_params
                     )
                   end

        # Process response
        result = process_response(response, current_agent, conversation)

        turns += 1

        # Check for handoff
        if result[:handoff]
          handoff_agent = current_agent.find_handoff(result[:handoff])
          raise HandoffError, "Cannot handoff to '#{result[:handoff]}'" unless handoff_agent

          current_agent = handoff_agent
          turns = 0 # Reset turn counter for new agent
          next
        end

        # Check if we're done
        break if result[:done]

        # Check max turns for current agent
        raise MaxTurnsError, "Maximum turns (#{current_agent.max_turns}) exceeded" if turns >= current_agent.max_turns
      end

      RunResult.success(
        messages: conversation,
        last_agent: current_agent,
        turns: turns
      )
    end

    def build_messages(conversation, agent)
      system_message = {
        role: "system",
        content: build_system_prompt(agent)
      }

      # Convert to symbol keys for consistency with provider expectations
      formatted_conversation = conversation.map do |msg|
        {
          role: msg[:role] || msg["role"],
          content: msg[:content] || msg["content"]
        }
      end

      [system_message] + formatted_conversation
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

    def process_response(response, agent, conversation)
      # Handle error responses
      if response["error"]
        puts "[Runner] API Error: #{response["error"]}"
        return { done: true, handoff: nil, error: response["error"] }
      end

      choice = response.dig("choices", 0)
      return { done: true, handoff: nil } unless choice

      message = choice["message"]
      return { done: true, handoff: nil } unless message

      # Build assistant message - handle both content and tool calls
      assistant_message = { role: "assistant" }

      # Add content - set to empty string if null to avoid API errors
      content = message["content"] || ""

      # Validate structured output if agent has output schema
      if agent.output_schema && !content.empty? && !message["tool_calls"]
        validated_content = validate_structured_output(content, agent.output_schema)
        assistant_message[:content] = validated_content
      else
        assistant_message[:content] = content
      end

      # Add tool calls if present
      assistant_message[:tool_calls] = message["tool_calls"] if message["tool_calls"]

      # Only add message to conversation if it has content or tool calls
      if assistant_message[:content] || assistant_message[:tool_calls]
        conversation << assistant_message
        puts "[Runner] Added assistant message with #{assistant_message[:tool_calls]&.size || 0} tool calls"
      end

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
      puts "[Runner] Processing #{tool_calls.size} tool calls"

      tool_calls.each do |tool_call|
        tool_name = tool_call.dig("function", "name")
        arguments = JSON.parse(tool_call.dig("function", "arguments") || "{}")

        puts "[Runner] Executing tool: #{tool_name} with call_id: #{tool_call["id"]}"

        begin
          puts "[Runner] About to execute agent.execute_tool(#{tool_name}, #{arguments})"

          # function_span in Python implementation
          result = if @tracer && !@disabled_tracing
                     # Get config from instance variable set by run methods
                     trace_sensitive = @current_config&.trace_include_sensitive_data != false

                     @tracer.tool_span(tool_name) do |tool_span|
                       tool_span.set_attribute("function.name", tool_name)

                       if trace_sensitive
                         tool_span.set_attribute("function.input", arguments)
                       else
                         tool_span.set_attribute("function.input", "[REDACTED]")
                       end

                       tool_span.add_event("function.start")

                       res = agent.execute_tool(tool_name, **arguments.transform_keys(&:to_sym))

                       if trace_sensitive
                         tool_span.set_attribute("function.output", res.to_s[0..1000]) # Limit size
                       else
                         tool_span.set_attribute("function.output", "[REDACTED]")
                       end

                       tool_span.add_event("function.complete")
                       res
                     end
                   else
                     agent.execute_tool(tool_name, **arguments.transform_keys(&:to_sym))
                   end

          puts "[Runner] Tool execution returned: #{result.class.name}"
          puts "[Runner] Tool result: #{result.to_s[0..200]}..."

          tool_message = {
            role: "tool",
            tool_call_id: tool_call["id"],
            content: result.to_s
          }

          conversation << tool_message
          puts "[Runner] Added tool message to conversation. Total messages: #{conversation.size}"
        rescue StandardError => e
          puts "[Runner] Tool execution error: #{e.message}"
          puts "[Runner] Error backtrace: #{e.backtrace[0..2].join('\n')}"

          @tracer.record_exception(e) if @tracer && !@disabled_tracing

          error_message = {
            role: "tool",
            tool_call_id: tool_call["id"],
            content: "Error: #{e.message}"
          }

          conversation << error_message
          puts "[Runner] Added error message to conversation. Total messages: #{conversation.size}"
        end
      end

      puts "[Runner] Tool processing complete. Conversation now has #{conversation.size} messages"
      false # Continue conversation after tool calls
    end

    def validate_structured_output(content, schema)
      # Try to parse as JSON if it looks like JSON
      if content.strip.start_with?("{", "[")
        begin
          data = JSON.parse(content)
          validator = StructuredOutput::ResponseFormatter.new(schema)
          result = validator.format_response(data)

          if result[:valid]
            # Return the validated data as JSON string
            JSON.generate(result[:data])
          else
            # Log validation error but return original content
            puts "[Runner] Structured output validation failed: #{result[:error]}"
            content
          end
        rescue JSON::ParserError => e
          # Not valid JSON, return as-is
          puts "[Runner] Failed to parse structured output as JSON: #{e.message}"
          content
        end
      else
        # Not JSON format, return as-is
        content
      end
    end

    def normalize_messages(messages)
      case messages
      when String
        # Convert string to user message
        [{ role: "user", content: messages }]
      when Array
        # Already an array, return as-is
        messages
      else
        # Convert to string then to user message
        [{ role: "user", content: messages.to_s }]
      end
    end

    def safe_map_names(collection)
      return [] unless collection.respond_to?(:map)

      collection.map do |item|
        if item.respond_to?(:name)
          item.name
        else
          item.to_s
        end
      end
    rescue StandardError
      []
    end
  end
end

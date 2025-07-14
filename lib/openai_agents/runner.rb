# frozen_string_literal: true

require "async"
require "json"
require "net/http"
require "uri"
require_relative "agent"
require_relative "errors"
require_relative "models/responses_provider"
require_relative "tracing/trace_provider"
require_relative "strict_schema"
require_relative "structured_output"
require_relative "result"
require_relative "run_config"
require_relative "run_context"
require_relative "lifecycle"
require_relative "run_result_streaming"
require_relative "streaming_events_semantic"
require_relative "items"
require_relative "context_manager"
require_relative "context_config"
require_relative "run_executor"

module OpenAIAgents
  ##
  # The Runner class is the core execution engine for OpenAI Agents.
  # It orchestrates the conversation flow between users and AI agents,
  # managing tool calls, handoffs between agents, and conversation state.
  #
  # This class handles:
  # - Multi-turn conversations with AI agents
  # - Tool execution (both local and OpenAI-hosted tools)
  # - Agent handoffs for multi-agent workflows
  # - Tracing and monitoring of agent execution
  # - Context management for memory-aware conversations
  # - Guardrails for input/output validation
  # - Streaming responses for real-time interaction
  #
  # @example Basic usage
  #   agent = OpenAIAgents::Agent.new(
  #     name: "Assistant",
  #     instructions: "You are a helpful assistant",
  #     model: "gpt-4o"
  #   )
  #   runner = OpenAIAgents::Runner.new(agent: agent)
  #   result = runner.run("Hello, how can you help?")
  #   puts result.messages.last[:content]
  #
  # @example With tracing enabled
  #   tracer = OpenAIAgents::Tracing::SpanTracer.new
  #   runner = OpenAIAgents::Runner.new(agent: agent, tracer: tracer)
  #   result = runner.run("What's the weather?")
  #
  # @example Multi-agent handoffs
  #   support_agent = OpenAIAgents::Agent.new(name: "Support", instructions: "...")
  #   billing_agent = OpenAIAgents::Agent.new(name: "Billing", instructions: "...")
  #   support_agent.add_handoff(billing_agent)
  #   
  #   runner = OpenAIAgents::Runner.new(agent: support_agent)
  #   # Agent will automatically handoff to billing when needed
  #
  class Runner
    include Logger
    attr_reader :agent, :tracer, :stop_checker

    ##
    # Initialize a new Runner instance
    #
    # @param agent [Agent] The initial agent to run conversations with
    # @param provider [Models::Interface, nil] The LLM provider (defaults to ResponsesProvider)
    # @param tracer [Tracing::SpanTracer, nil] The tracer for monitoring execution
    # @param disabled_tracing [Boolean] Whether to disable tracing completely
    # @param stop_checker [Proc, nil] A callable that returns true to stop execution
    # @param context_manager [ContextManager, nil] Custom context manager for memory
    # @param context_config [ContextConfig, nil] Configuration for automatic context management
    #
    # @example With custom provider
    #   provider = OpenAIAgents::Models::AnthropicProvider.new
    #   runner = OpenAIAgents::Runner.new(agent: agent, provider: provider)
    #
    # @example With stop checker
    #   stop_checker = -> { File.exist?('/tmp/stop') }
    #   runner = OpenAIAgents::Runner.new(agent: agent, stop_checker: stop_checker)
    #
    def initialize(agent:, provider: nil, tracer: nil, disabled_tracing: false, stop_checker: nil,
                   context_manager: nil, context_config: nil)
      @agent = agent
      @provider = provider || Models::ResponsesProvider.new
      @disabled_tracing = disabled_tracing || ENV["OPENAI_AGENTS_DISABLE_TRACING"] == "true"
      @tracer = tracer || (@disabled_tracing ? nil : OpenAIAgents.tracer)
      @stop_checker = stop_checker

      # Context management setup
      if context_manager
        @context_manager = context_manager
      elsif context_config
        @context_manager = context_config.build_context_manager(model: @agent.model)
      elsif ENV["OPENAI_AGENTS_CONTEXT_MANAGEMENT"] == "true"
        # Auto-enable with balanced settings if env var is set
        config = ContextConfig.balanced(model: @agent.model)
        @context_manager = config.build_context_manager(model: @agent.model)
      end

      # Initialize handoff tracking for circular protection
      @handoff_chain = []
    end

    ##
    # Checks if tracing is enabled for this runner
    #
    # @return [Boolean] true if tracing is enabled, false otherwise
    def tracing_enabled?
      !@disabled_tracing && !@tracer.nil?
    end

    ##
    # Checks if execution should be stopped
    #
    # @return [Boolean] true if execution should stop, false otherwise
    def should_stop?
      return false unless @stop_checker

      @stop_checker.call
    rescue StandardError => e
      log_error("Error checking stop condition", error: e.message, error_class: e.class.name)
      false
    end

    ##
    # Checks if the runner is currently configured for streaming
    #
    # @return [Boolean] true if streaming is supported, false otherwise
    def streaming_capable?
      @provider.respond_to?(:stream_completion)
    end

    ##
    # Checks if tools are available for the current agent
    #
    # @param context [RunContextWrapper, nil] current run context
    # @return [Boolean] true if agent has tools available, false otherwise
    def tools_available?(context = nil)
      @agent.tools?(context)
    end

    ##
    # Execute a conversation with the agent
    #
    # This is the main entry point for running agent conversations. It handles
    # the complete conversation lifecycle including tool calls, handoffs, and
    # multiple turns of interaction.
    #
    # @param messages [String, Array<Hash>] The input messages (string or conversation array)
    # @param stream [Boolean] Whether to stream responses (requires streaming-capable provider)
    # @param config [RunConfig, nil] Configuration object for the run
    # @param hooks [Object, nil] Object with lifecycle hook methods (on_agent_start, on_tool_start, etc)
    # @param input_guardrails [Array<Guardrails::InputGuardrail>] Input validation guardrails
    # @param output_guardrails [Array<Guardrails::OutputGuardrail>] Output validation guardrails
    # @param kwargs [Hash] Additional parameters passed to RunConfig
    #
    # @return [RunResult] The result containing conversation messages, usage stats, and metadata
    #
    # @raise [ExecutionStoppedError] If execution is stopped by stop_checker
    # @raise [MaxTurnsError] If maximum conversation turns are exceeded
    # @raise [HandoffError] If an invalid handoff is attempted
    # @raise [Guardrails::InputGuardrailTripwireTriggered] If input guardrail is triggered
    # @raise [Guardrails::OutputGuardrailTripwireTriggered] If output guardrail is triggered
    #
    # @example Simple conversation
    #   result = runner.run("What's the capital of France?")
    #   puts result.messages.last[:content]  # "The capital of France is Paris."
    #
    # @example With configuration
    #   config = RunConfig.new(
    #     max_turns: 5,
    #     model: "gpt-4o-mini",
    #     temperature: 0.7
    #   )
    #   result = runner.run("Tell me a story", config: config)
    #
    # @example With guardrails
    #   pii_guardrail = PIIDetectorGuardrail.new
    #   result = runner.run(
    #     "My SSN is 123-45-6789",
    #     input_guardrails: [pii_guardrail]
    #   )
    #
    def run(messages, stream: false, config: nil, hooks: nil, input_guardrails: nil, output_guardrails: nil, **kwargs)
      # Normalize messages input - handle both string and array formats
      messages = normalize_messages(messages)

      # Create config if not provided
      if config.nil?
        config = RunConfig.new(
          stream: stream,
          **kwargs  # Pass any additional parameters to RunConfig
        )
      end

      # Store hooks in config for later use
      config.hooks = hooks if hooks
      config.input_guardrails = input_guardrails if input_guardrails
      config.output_guardrails = output_guardrails if output_guardrails

      # Create appropriate executor based on tracing configuration
      executor = if config.tracing_disabled || @disabled_tracing || @tracer.nil?
                   BasicRunExecutor.new(
                     runner: self,
                     provider: @provider,
                     agent: @agent,
                     config: config
                   )
                 else
                   TracedRunExecutor.new(
                     runner: self,
                     provider: @provider,
                     agent: @agent,
                     config: config,
                     tracer: @tracer
                   )
                 end

      # Execute the conversation
      executor.execute(messages)
    end

    ##
    # Execute a conversation asynchronously
    #
    # This method wraps the regular run method in an Async block for
    # concurrent execution. Useful when running multiple agents in parallel.
    #
    # @param messages [String, Array<Hash>] The input messages
    # @param stream [Boolean] Whether to stream responses
    # @param config [RunConfig, nil] Configuration for the run
    # @param kwargs [Hash] Additional parameters
    #
    # @return [Async::Task] An async task that resolves to a RunResult
    #
    # @example Running multiple agents concurrently
    #   task1 = runner1.run_async("Analyze this data")
    #   task2 = runner2.run_async("Generate a report")
    #   
    #   results = Async do
    #     [task1.wait, task2.wait]
    #   end
    #
    def run_async(messages, stream: false, config: nil, **kwargs)
      Async do
        run(messages, stream: stream, config: config, **kwargs)
      end
    end

    ##
    # Execute a streaming conversation with the agent
    #
    # This method returns a streaming result object that yields events
    # as the conversation progresses. It matches the Python SDK's run_streamed
    # method for compatibility.
    #
    # @param messages [String, Array<Hash>] The input messages
    # @param config [RunConfig, nil] Configuration for the run
    # @param kwargs [Hash] Additional parameters
    #
    # @return [RunResultStreaming] A streaming result object
    #
    # @example Streaming conversation
    #   streaming = runner.run_streamed("Tell me a long story")
    #   
    #   streaming.each_event do |event|
    #     case event.type
    #     when :text
    #       print event.content
    #     when :tool_call
    #       puts "Calling tool: #{event.tool_name}"
    #     end
    #   end
    #
    #   # Get final result after streaming completes
    #   result = streaming.result
    #
    def run_streamed(messages, config: nil, **kwargs)
      # Normalize messages and config
      messages = normalize_messages(messages)

      if config.nil? && !kwargs.empty?
        config = RunConfig.new(**kwargs)
      elsif config.nil?
        config = RunConfig.new
      end

      # Initialize hooks context for consistency
      initialize_run_context(messages, config)

      # Create streaming result
      streaming_result = RunResultStreaming.new(
        agent: @agent,
        input: messages,
        run_config: config,
        tracer: @tracer,
        provider: @provider
      )

      # Start streaming in background
      streaming_result.start_streaming

      streaming_result
    end

    ##
    # @!group Executor Callback Methods
    #
    # These public methods are designed to be called by RunExecutor instances
    # during agent execution. They provide access to runner functionality
    # while maintaining proper encapsulation.
    #
    public

    # Hook and guardrail methods for executor
    attr_reader :current_config

    ##
    # Execute lifecycle hooks for agent execution events
    #
    # This method is called by executors to trigger hooks at various
    # points in the execution lifecycle. It handles both run-level
    # and agent-level hooks.
    #
    # @api private Used by RunExecutor classes
    # @param hook_method [Symbol] The hook to execute (e.g., :on_agent_start)
    # @param context_wrapper [RunContextWrapper] Current execution context
    # @param args [Array] Additional arguments passed to the hook
    # @return [void]
    #
    # @example Hook methods available:
    #   - :on_agent_start - Called when agent begins processing
    #   - :on_agent_end - Called when agent completes
    #   - :on_tool_start - Called before tool execution
    #   - :on_tool_end - Called after tool execution
    #   - :on_tool_error - Called when tool execution fails
    #   - :on_handoff - Called when agent handoff occurs
    #
    def call_hook(hook_method, context_wrapper, *args)
      log_debug_general("Calling hook", hook: hook_method, config_class: @current_config&.hooks&.class&.name)
      
      # Call run-level hooks
      if @current_config&.hooks.respond_to?(hook_method)
        log_debug_general("Executing run-level hook", hook: hook_method)
        @current_config.hooks.send(hook_method, context_wrapper, *args)
      end

      # Call agent-level hooks if applicable
      agent = args.first if args.first.is_a?(Agent)
      agent_hook_method = hook_method.to_s.sub("on_agent_", "on_")
      if agent&.hooks.respond_to?(agent_hook_method)
        log_debug_general("Executing agent-level hook", hook: agent_hook_method, agent: agent.name)
        agent.hooks.send(agent_hook_method, context_wrapper, *args)
      end
    rescue StandardError => e
      warn "Error in hook #{hook_method}: #{e.message}"
    end

    ##
    # Execute input guardrails to validate and filter user input
    #
    # This method runs all configured input guardrails (both run-level
    # and agent-level) before processing user messages. Guardrails can
    # modify content or trigger exceptions to prevent processing.
    #
    # @api private Used by RunExecutor classes
    # @param context_wrapper [RunContextWrapper] Current execution context
    # @param agent [Agent] The current agent instance
    # @param input [String] The user input to validate
    # @return [void]
    # @raise [Guardrails::InputGuardrailTripwireTriggered] If a guardrail blocks the input
    #
    def run_input_guardrails(context_wrapper, agent, input)
      # Collect all guardrails (run-level and agent-level)
      guardrails = []
      guardrails.concat(@current_config.input_guardrails) if @current_config&.input_guardrails
      guardrails.concat(agent.input_guardrails) if agent.respond_to?(:input_guardrails)

      return if guardrails.empty?

      guardrails.each do |guardrail|
        result = guardrail.run(context_wrapper, agent, input)

        next unless result.tripwire_triggered?

        raise Guardrails::InputGuardrailTripwireTriggered.new(
          "Input guardrail '#{guardrail.get_name}' triggered",
          triggered_by: guardrail.get_name,
          content: input,
          metadata: result.output.output_info
        )
      end
    end

    ##
    # Execute output guardrails to validate and filter agent responses
    #
    # This method runs all configured output guardrails (both run-level
    # and agent-level) after receiving agent responses. Guardrails can
    # modify content or trigger exceptions to prevent output.
    #
    # @api private Used by RunExecutor classes
    # @param context_wrapper [RunContextWrapper] Current execution context
    # @param agent [Agent] The current agent instance
    # @param output [String] The agent output to validate
    # @return [void]
    # @raise [Guardrails::OutputGuardrailTripwireTriggered] If a guardrail blocks the output
    #
    def run_output_guardrails(context_wrapper, agent, output)
      # Collect all guardrails (run-level and agent-level)
      guardrails = []
      guardrails.concat(@current_config.output_guardrails) if @current_config&.output_guardrails
      guardrails.concat(agent.output_guardrails) if agent.respond_to?(:output_guardrails)

      return if guardrails.empty?

      guardrails.each do |guardrail|
        result = guardrail.run(context_wrapper, agent, output)

        next unless result.tripwire_triggered?

        raise Guardrails::OutputGuardrailTripwireTriggered.new(
          "Output guardrail '#{guardrail.get_name}' triggered",
          triggered_by: guardrail.get_name,
          content: output,
          metadata: result.output.output_info
        )
      end
    end

    ##
    # Build formatted messages array for API provider calls
    #
    # This method prepares the conversation messages for the AI provider,
    # including system prompts, conversation history, and applying any
    # context management strategies.
    #
    # @api private Used by RunExecutor classes
    # @param conversation [Array<Hash>] The conversation history
    # @param agent [Agent] The current agent instance
    # @param context_wrapper [RunContextWrapper, nil] Optional execution context
    # @return [Array<Hash>] Formatted messages ready for API call
    #
    def build_messages(conversation, agent, context_wrapper = nil)
      system_message = {
        role: "system",
        content: build_system_prompt(agent, context_wrapper)
      }

      # Convert to symbol keys for consistency with provider expectations
      formatted_conversation = conversation.map do |msg|
        {
          role: msg[:role] || msg["role"],
          content: msg[:content] || msg["content"]
        }
      end

      messages = [system_message] + formatted_conversation

      # Apply context management if enabled
      messages = @context_manager.manage_context(messages) if @context_manager

      messages
    end

    ##
    # Process and execute tool calls from the assistant
    #
    # This method handles the execution of one or more tool calls requested
    # by the AI assistant. It manages tool execution, error handling, and
    # appending results back to the conversation.
    #
    # @api private Used by RunExecutor classes
    # @param tool_calls [Array<Hash>] Array of tool call requests from the assistant
    # @param agent [Agent] The current agent instance
    # @param conversation [Array<Hash>] The conversation to append results to
    # @param context_wrapper [RunContextWrapper, nil] Optional execution context
    # @param full_response [Hash, nil] The full API response (for hosted tools)
    # @return [Boolean, String] Returns true if should stop, String for handoff agent, false to continue
    #
    def process_tool_calls(tool_calls, agent, conversation, context_wrapper = nil, full_response = nil)
      # Implementation defined elsewhere in the file
    end

    ##
    # Detect agent handoff requests in message content
    #
    # This method analyzes message content to identify handoff patterns
    # that indicate the current agent wants to transfer control to another agent.
    #
    # @api private Used by RunExecutor classes
    # @param content [String] The message content to analyze
    # @param agent [Agent] The current agent instance
    # @return [String, nil] Target agent name if handoff detected, nil otherwise
    #
    def detect_handoff_in_content(content, agent)
      # Implementation defined elsewhere in the file
    end

    ##
    # Find a handoff agent by name
    #
    # This method searches for a handoff agent in the current agent's
    # handoff list by name, enabling agent-to-agent transfers.
    #
    # @api private Used by RunExecutor classes
    # @param target_name [String] The name of the target agent
    # @param current_agent [Agent] The current agent with handoff list
    # @return [Agent, nil] The target agent if found, nil otherwise
    #
    def find_handoff_agent(target_name, current_agent)
      # Implementation defined elsewhere in the file
    end

    ##
    # Execute a tool by name with given arguments
    #
    # This method finds and executes a tool from the agent's tool list,
    # handling both function tools and other tool types.
    #
    # @api private Used by RunExecutor classes
    # @param tool_name [String] The name of the tool to execute
    # @param arguments [Hash] The arguments to pass to the tool
    # @param agent [Agent] The agent that owns the tool
    # @param context_wrapper [RunContextWrapper, nil] Optional execution context
    # @return [String] The tool execution result
    # @raise [StandardError] If tool execution fails
    #
    def execute_tool(tool_name, arguments, agent, context_wrapper = nil)
      # Implementation defined elsewhere in the file
    end

    # @!endgroup

    protected

    ##
    # Get all tools available to an agent, including handoff tools
    #
    # This method combines regular tools with handoff agents converted to tools.
    # Handoff agents are automatically converted to tool definitions that the
    # LLM can call to transfer control to another agent.
    #
    # @param agent [Agent] The agent to get tools for
    # @return [Array<Hash>, nil] Array of tool definitions or nil if no tools
    #
    # @example Tool definition format
    #   {
    #     type: "function",
    #     name: "transfer_to_billing",
    #     function: {
    #       name: "transfer_to_billing",
    #       description: "Transfer to Billing agent for billing inquiries",
    #       parameters: { type: "object", properties: {}, required: [] }
    #     }
    #   }
    #
    def get_all_tools_for_api(agent)
      all_tools = []

      # Add regular tools
      all_tools.concat(agent.tools) if agent.tools?

      # Add handoff tools
      agent.handoffs.each do |handoff|
        if handoff.is_a?(Agent)
          # Convert Agent to handoff tool
          tool_name = Handoff.default_tool_name(handoff)
          tool_description = Handoff.default_tool_description(handoff)

          handoff_tool = {
            type: "function",
            name: tool_name,
            function: {
              name: tool_name,
              description: tool_description,
              parameters: {
                type: "object",
                properties: {},
                required: []
              }
            }
          }
          all_tools << handoff_tool

          log_debug_handoff("Added handoff tool to API tools",
                            agent: agent.name,
                            handoff_tool: tool_name,
                            target_agent: handoff.name)
        else
          # Already a Handoff object, use its tool definition
          all_tools << handoff.to_tool_definition

          log_debug_handoff("Added handoff tool to API tools",
                            agent: agent.name,
                            handoff_tool: handoff.tool_name,
                            target_agent: handoff.agent_name)
        end
      end

      all_tools.empty? ? nil : all_tools
    end

    ##
    # Process output items from the Responses API
    #
    # This method handles the output format from OpenAI's Responses API,
    # which uses an items-based conversation model. It processes different
    # types of output items (messages, tool calls) and detects handoffs.
    #
    # @param response [Hash] The API response containing output items
    # @param agent [Agent] The current agent
    # @param generated_items [Array<Items::Base>] Array to append new items to
    # @param span [Tracing::Span, nil] Optional tracing span
    #
    # @return [Hash] Result hash with :done and :handoff keys
    #   - :done [Boolean] Whether the conversation is complete
    #   - :handoff [Hash, nil] Handoff data if a handoff was detected
    #
    def process_responses_api_output(response, agent, generated_items, span = nil)
      output = response&.dig(:output) || response&.dig("output") || []

      result = { done: false, handoff: nil }
      handoff_results = [] # Track all handoffs detected

      output.each do |item|
        item_type = item[:type] || item["type"]

        case item_type
        when "message", "text", "output_text"
          # Text output from the model
          generated_items << Items::MessageOutputItem.new(agent: agent, raw_item: item)

          # Unified handoff detection system for Responses API
          content = item[:content] || item["content"]
          if content
            # Handle both string and array formats
            text_content = if content.is_a?(Array)
                             content.map { |c| c.is_a?(Hash) ? c[:text] || c["text"] : c.to_s }.join(" ")
                           else
                             content.to_s
                           end

            if text_content && !text_content.empty?
              handoff_target = detect_handoff_in_content(text_content, agent)
              if handoff_target
                handoff_results << {
                  tool_name: "json_handoff",
                  handoff_target: handoff_target,
                  handoff_data: { assistant: handoff_target }
                }

                log_debug_handoff("JSON handoff detected in Responses API text output",
                                  from_agent: agent.name,
                                  to_agent: handoff_target,
                                  source: "text content")
              end
            end
          end

        when "function_call"
          # Tool call from the model
          generated_items << Items::ToolCallItem.new(agent: agent, raw_item: item)

          # Execute the tool
          tool_result = execute_tool_for_responses_api(item, agent)

          # Check if tool_result is a handoff
          if tool_result.is_a?(Hash) && tool_result.key?(:assistant)
            handoff_results << {
              tool_name: item[:name] || item["name"],
              handoff_target: tool_result[:assistant],
              handoff_data: tool_result
            }

            log_debug_handoff("Handoff detected from tool execution in Responses API",
                              from_agent: agent.name,
                              to_agent: tool_result[:assistant],
                              tool_name: item[:name] || item["name"])
          end

          # Add tool result as an item
          # Convert handoff results to string format for API compatibility
          tool_output_value = if tool_result.is_a?(Hash) && tool_result.key?(:assistant)
                                JSON.generate(tool_result)
                              else
                                tool_result.to_s
                              end

          tool_output_item = {
            type: "function_call_output",
            call_id: item[:call_id] || item["call_id"] || item[:id] || item["id"],
            output: tool_output_value
          }
          generated_items << Items::ToolCallOutputItem.new(
            agent: agent,
            raw_item: tool_output_item,
            output: tool_result
          )

        when "function_call_output"
          # This is already a tool result (shouldn't happen in output, but handle it)
          generated_items << Items::ToolCallOutputItem.new(
            agent: agent,
            raw_item: item,
            output: item[:output] || item["output"]
          )
        end
      end

      # Handle multiple handoffs with same logic as Chat Completions API
      if handoff_results.size > 1
        # Multiple handoffs detected - this is an error condition
        handoff_targets = handoff_results.map { |r| r[:handoff_target] }
        log_error("Multiple handoffs detected in Responses API - this is not supported",
                  from_agent: agent.name,
                  handoff_targets: handoff_targets,
                  count: handoff_results.size)

        # Add error message as output item with proper format
        error_message = {
          type: "message",
          role: "assistant",
          content: [{
            type: "text",
            text: "Error: Multiple agent handoffs detected in single response. Only one handoff per turn is supported. Staying with current agent."
          }]
        }
        generated_items << Items::MessageOutputItem.new(agent: agent, raw_item: error_message)

        # Don't set handoff - stay with current agent
        result[:handoff] = nil
      elsif handoff_results.size == 1
        # Single handoff - proceed normally
        handoff_info = handoff_results.first
        result[:handoff] = handoff_info[:handoff_data]

        log_debug_handoff("Single handoff approved in Responses API",
                          from_agent: agent.name,
                          to_agent: handoff_info[:handoff_target],
                          tool_name: handoff_info[:tool_name])
      end

      # Check if there are no tool calls in this output
      has_tool_calls = output.any? { |item| (item[:type] || item["type"]) == "function_call" }

      # Only set done to true if there are no tool calls AND no handoff was detected
      result[:done] = if !has_tool_calls && result[:handoff].nil?
                        true
                      elsif result[:handoff]
                        # When handoff is detected, we should continue execution with the new agent
                        false
                      else
                        false
                      end

      result
    end

    ##
    # Execute a tool call for the Responses API
    #
    # This method executes tool calls from the Responses API format,
    # handling both regular tools and handoff tools. It includes proper
    # error handling and tracing support.
    #
    # @param tool_call_item [Hash] The tool call item from the API
    #   - :name [String] The tool name
    #   - :arguments [String] JSON-encoded tool arguments
    # @param agent [Agent] The agent executing the tool
    #
    # @return [String, Hash] Tool execution result or error message
    #   Returns a Hash with :assistant key for handoff results
    #
    def execute_tool_for_responses_api(tool_call_item, agent)
      tool_name = tool_call_item[:name] || tool_call_item["name"]
      arguments_str = tool_call_item[:arguments] || tool_call_item["arguments"] || "{}"

      begin
        arguments = JSON.parse(arguments_str)
      rescue JSON::ParserError
        return "Error: Invalid tool arguments"
      end

      # Check if this is a handoff tool (starts with "transfer_to_")
      return process_handoff_tool_call_for_responses_api(tool_call_item, agent) if tool_name.start_with?("transfer_to_")

      # Find the tool
      tool = agent.tools.find { |t| t.respond_to?(:name) && t.name == tool_name }

      return "Error: Tool '#{tool_name}' not found" if tool.nil?

      # Execute the tool
      begin
        if @tracer && !@disabled_tracing
          @tracer.tool_span(tool_name) do |tool_span|
            tool_span.set_attribute("function.name", tool_name)
            tool_span.set_attribute("function.input", arguments)

            result = tool.call(**arguments.transform_keys(&:to_sym))

            tool_span.set_attribute("function.output", result.to_s)
            result
          end
        else
          tool.call(**arguments.transform_keys(&:to_sym))
        end
      rescue StandardError => e
        "Error executing tool: #{e.message}"
      end
    end

    # Process handoff tool calls for Responses API
    def process_handoff_tool_call_for_responses_api(tool_call_item, agent)
      tool_name = tool_call_item[:name] || tool_call_item["name"]
      arguments_str = tool_call_item[:arguments] || tool_call_item["arguments"] || "{}"

      begin
        arguments = JSON.parse(arguments_str)
      rescue JSON::ParserError
        return "Error: Invalid tool arguments"
      end

      # Find the handoff target by matching the tool name to the expected tool name for each handoff
      log_debug_handoff("Processing handoff tool call in Responses API",
                        from_agent: agent.name,
                        tool_name: tool_name)

      # Find the handoff target by checking if the tool name matches the expected tool name for each handoff
      handoff_target = agent.handoffs.find do |handoff|
        if handoff.is_a?(Agent)
          # Check if this agent would generate the same tool name
          expected_tool_name = OpenAIAgents::Handoff.default_tool_name(handoff)
          expected_tool_name == tool_name
        else
          # For handoff objects, check both agent name match and tool name match
          handoff.tool_name == tool_name
        end
      end

      unless handoff_target
        log_debug_handoff("Handoff target not found for tool call in Responses API",
                          from_agent: agent.name,
                          tool_name: tool_name)

        return "Error: Handoff target for tool '#{tool_name}' not found"
      end

      # Execute the handoff
      if handoff_target.is_a?(Agent)
        # Simple agent handoff
        handoff_result = { assistant: handoff_target.name }

        log_debug_handoff("Agent handoff tool executed successfully in Responses API",
                          from_agent: agent.name,
                          to_agent: handoff_target.name,
                          tool_name: tool_name)

        handoff_result
      else
        # Handoff object with custom logic
        begin
          # NOTE: For Responses API, we need a simpler context since RunContextWrapper may not be available
          # Create a minimal context for compatibility
          context_wrapper = @current_context_wrapper
          handoff_result = handoff_target.invoke(context_wrapper, arguments)

          log_debug_handoff("Handoff object tool executed successfully in Responses API",
                            from_agent: agent.name,
                            to_agent: handoff_target.agent_name,
                            tool_name: tool_name)

          handoff_result
        rescue StandardError => e
          log_debug_handoff("Handoff object tool execution failed in Responses API",
                            from_agent: agent.name,
                            to_agent: handoff_target.agent_name,
                            tool_name: tool_name,
                            error: e.message)

          "Error: Handoff failed - #{e.message}"
        end
      end
    end

    # Check if response has tool calls
    def has_tool_calls_in_response?(response)
      return false unless response

      output = response[:output] || response["output"] || []
      output.any? { |item| (item[:type] || item["type"]) == "function_call" }
    end

    # Build conversation from items (for compatibility)
    def build_conversation_from_items(input, generated_items)
      conversation = []

      # Add initial input as user message
      if input.any?
        first_input = input.first
        if first_input[:type] == "user_text" || first_input["type"] == "user_text"
          conversation << { role: "user", content: first_input[:text] || first_input["text"] }
        end
      end

      # Convert generated items to messages
      generated_items.each do |item|
        case item
        when Items::MessageOutputItem
          raw = item.raw_item
          # Extract text from Responses API format: content[0][:text]
          text = if raw[:content].is_a?(Array) && raw[:content].first
                   content_item = raw[:content].first
                   content_item[:text] || content_item["text"] || ""
                 else
                   raw[:text] || raw["text"] || ""
                 end
          conversation << { role: "assistant", content: text }
        end
      end

      conversation
    end

    # Run with Responses API without tracing
    def run_with_responses_api_no_trace(messages, config:)
      # Use shared execution core with hooks support
      execute_responses_api_core(messages, config, with_tracing: false)
    end

    ##
    # Run input guardrails to validate user input
    #
    # This method executes all configured input guardrails (both run-level
    # and agent-level) to validate the input before processing. If any
    # guardrail is triggered, it raises an exception.
    #
    # @param context_wrapper [RunContextWrapper] The run context
    # @param agent [Agent] The current agent
    # @param input [String] The input to validate
    #
    # @raise [Guardrails::InputGuardrailTripwireTriggered] If a guardrail is triggered
    #
    def run_input_guardrails(context_wrapper, agent, input)
      # Collect all guardrails (run-level and agent-level)
      guardrails = []
      guardrails.concat(@current_config.input_guardrails) if @current_config&.input_guardrails
      guardrails.concat(agent.input_guardrails) if agent.respond_to?(:input_guardrails)

      return if guardrails.empty?

      guardrails.each do |guardrail|
        result = guardrail.run(context_wrapper, agent, input)

        next unless result.tripwire_triggered?

        raise Guardrails::InputGuardrailTripwireTriggered.new(
          "Input guardrail '#{guardrail.get_name}' triggered",
          triggered_by: guardrail.get_name,
          content: input,
          metadata: result.output.output_info
        )
      end
    end

    # Run output guardrails for an agent
    def run_output_guardrails(context_wrapper, agent, output)
      # Collect all guardrails (run-level and agent-level)
      guardrails = []
      guardrails.concat(@current_config.output_guardrails) if @current_config&.output_guardrails
      guardrails.concat(agent.output_guardrails) if agent.respond_to?(:output_guardrails)

      return if guardrails.empty?

      guardrails.each do |guardrail|
        result = guardrail.run(context_wrapper, agent, output)

        next unless result.tripwire_triggered?

        raise Guardrails::OutputGuardrailTripwireTriggered.new(
          "Output guardrail '#{guardrail.get_name}' triggered",
          triggered_by: guardrail.get_name,
          content: output,
          metadata: result.output.output_info
        )
      end
    end

    ##
    # Safely call lifecycle hooks
    #
    # This method calls both run-level and agent-level hooks, handling
    # any errors that occur during hook execution. Hooks are used to
    # implement custom behavior at different points in the conversation.
    #
    # @param hook_method [Symbol] The hook method name (e.g., :on_agent_start)
    # @param context_wrapper [RunContextWrapper] The run context
    # @param args [Array] Additional arguments to pass to the hook
    #
    # Available hooks:
    # - on_agent_start: Called when an agent begins processing
    # - on_agent_end: Called when an agent completes processing
    # - on_tool_start: Called before a tool is executed
    # - on_tool_end: Called after a tool completes
    # - on_handoff: Called when an agent handoff occurs
    #
    # (Method moved to public section above)

    # Initialize context and hooks for any run variant
    def initialize_run_context(messages, config)
      @current_config = config

      # Create run context for hooks
      context = RunContext.new(
        messages: messages,
        metadata: config.metadata || {},
        trace_id: config.trace_id,
        group_id: config.group_id
      )
      context_wrapper = RunContextWrapper.new(context)
      @current_context_wrapper = context_wrapper

      context_wrapper
    end

    # Initialize common execution state
    def initialize_execution_state(agent, config)
      {
        current_agent: agent,
        turns: 0,
        accumulated_usage: {
          input_tokens: 0,
          output_tokens: 0,
          total_tokens: 0
        },
        max_turns: config.max_turns || agent.max_turns
      }
    end

    # Shared execution core for Responses API with hooks
    def execute_responses_api_core(messages, config, with_tracing: false)
      context_wrapper = initialize_run_context(messages, config)
      state = initialize_execution_state(@agent, config)

      # Convert initial messages to input items
      input = Items::ItemHelpers.input_to_new_input_list(messages)
      generated_items = []
      model_responses = []
      previous_response_id = config.previous_response_id

      while state[:turns] < state[:max_turns]
        # Check if execution should stop
        raise ExecutionStoppedError, "Execution stopped by user request" if should_stop?

        # Call agent start hook
        call_hook(:on_agent_start, context_wrapper, state[:current_agent])

        # Build current input including all generated items
        current_input = if previous_response_id
                          # For continuing responses, start fresh - the API knows about the previous messages
                          []
                        else
                          # For initial request, include the original input
                          input.dup
                        end

        generated_items.each do |item|
          # Skip tool calls when we have a previous_response_id to avoid duplicates
          next if previous_response_id && item.is_a?(Items::ToolCallItem)

          current_input << item.to_input_item
        end

        # Get system instructions
        system_instructions = state[:current_agent].instructions

        # Prepare model parameters
        model = config.model || state[:current_agent].model
        model_params = config.to_model_params
        model_params[:response_format] = state[:current_agent].response_format if state[:current_agent].response_format

        # Make API call
        response = @provider.responses_completion(
          messages: [{ role: "system", content: system_instructions }],
          model: model,
          tools: get_all_tools_for_api(state[:current_agent]),
          previous_response_id: previous_response_id,
          input: current_input,
          **model_params
        )

        # Accumulate usage
        if response[:usage] || response["usage"]
          usage = response[:usage] || response["usage"]
          state[:accumulated_usage][:input_tokens] += usage[:input_tokens] || usage["input_tokens"] || 0
          state[:accumulated_usage][:output_tokens] += usage[:output_tokens] || usage["output_tokens"] || 0
          state[:accumulated_usage][:total_tokens] += usage[:total_tokens] || usage["total_tokens"] || 0
        end

        model_responses << response
        context_wrapper.add_message({ role: "assistant", content: response[:content] || response["content"] || "" })

        # Process Responses API output
        process_result = process_responses_api_output(response, state[:current_agent], generated_items)
        
        # Handle handoffs
        if process_result[:handoff]
          # For now, just log handoffs - full handoff support would require more complex state management
          log_debug_handoff("Handoff detected", 
            from_agent: state[:current_agent].name,
            to_agent: process_result[:handoff][:assistant] || "unknown")
        end
        
        # Check if we should continue (has tool calls)
        if !process_result[:done]
          # Set previous_response_id for next iteration
          previous_response_id = response[:id] || response["id"]
          state[:turns] += 1
          
          # Check if max turns exceeded after incrementing
          if state[:turns] >= state[:max_turns]
            raise MaxTurnsError, "Maximum turns (#{state[:max_turns]}) exceeded"
          end
          
          next
        end

        # No tool calls or done - conversation is complete
        break
      end

      # Call agent end hook
      final_output = if model_responses.last
                       model_responses.last[:content] || model_responses.last["content"] || ""
                     else
                       ""
                     end
      call_hook(:on_agent_end, context_wrapper, state[:current_agent], final_output)

      # Build final messages
      final_messages = messages.dup
      model_responses.each do |response|
        final_messages << { role: "assistant", content: response[:content] || response["content"] || "" }
      end

      RunResult.new(
        messages: final_messages,
        last_agent: state[:current_agent],
        turns: state[:turns],
        usage: state[:accumulated_usage],
        metadata: { responses: model_responses }
      )
    end

    # REMOVED: Custom context extraction and injection
    # The OpenAI agents framework handles context natively through structured outputs
    # and conversation continuity. The DSL should be a pure configuration layer.

    def run_with_tracing(messages, config:, parent_span: nil)
      @current_config = config # Store for tool calls

      # For Responses API, convert messages to items-based format
      return run_with_responses_api(messages, config: config) if @provider.is_a?(Models::ResponsesProvider)

      # Original Chat Completions flow for other providers
      conversation = messages.dup
      current_agent = @agent
      turns = 0
      accumulated_usage = {
        input_tokens: 0,
        output_tokens: 0,
        total_tokens: 0
      }

      # Create run context for hooks
      context = RunContext.new(
        messages: conversation,
        metadata: config.metadata || {},
        trace_id: config.trace_id,
        group_id: config.group_id
      )
      context_wrapper = RunContextWrapper.new(context)
      @current_context_wrapper = context_wrapper # Store for access in other methods

      max_turns = config.max_turns || current_agent.max_turns

      while turns < max_turns
        # Check if execution should stop
        if should_stop?
          conversation << { role: "assistant", content: "Execution stopped by user request." }
          raise ExecutionStoppedError, "Execution stopped by user request"
        end

        # Create agent span as root span (matching Python implementation where agent span has parent_id: null)
        # Temporarily clear the span stack to make this span root
        original_span_stack = @tracer.instance_variable_get(:@context).instance_variable_get(:@span_stack).dup
        @tracer.instance_variable_get(:@context).instance_variable_set(:@span_stack, [])

        agent_result = @tracer.start_span("agent.#{current_agent.name || "agent"}", kind: :agent) do |agent_span|
          # Update context for current agent
          context.current_agent = current_agent
          context.current_turn = turns

          # Call agent start hooks
          call_hook(:on_agent_start, context_wrapper, current_agent)

          # Run input guardrails
          current_input = conversation.last[:content] if conversation.last && conversation.last[:role] == "user"
          run_input_guardrails(context_wrapper, current_agent, current_input) if current_input

          # Set agent span attributes to match Python implementation
          agent_span.set_attribute("agent.name", current_agent.name || "agent")
          agent_span.set_attribute("agent.handoffs", safe_map_names(current_agent.handoffs))
          agent_span.set_attribute("agent.tools", safe_map_names(current_agent.tools))
          agent_span.set_attribute("agent.output_type", "str")

          # Prepare messages for API call
          api_messages = build_messages(conversation, current_agent, context_wrapper)
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

          # Add structured output support (matching Python implementation)
          if current_agent.response_format
            # Use the response_format directly if provided
            model_params[:response_format] = current_agent.response_format
          end

          # Add tool choice support if configured
          if current_agent.respond_to?(:tool_choice) && current_agent.tool_choice
            model_params[:tool_choice] = current_agent.tool_choice
          end

          # Add prompt support for Responses API
          if current_agent.prompt && @provider.respond_to?(:supports_prompts?) && @provider.supports_prompts?
            prompt_input = PromptUtil.to_model_input(current_agent.prompt, context_wrapper, current_agent)
            model_params[:prompt] = prompt_input if prompt_input
          end

          response = if config.stream
                       @provider.stream_completion(
                         messages: api_messages,
                         model: model,
                         tools: get_all_tools_for_api(current_agent),
                         **model_params
                       )
                     else
                       # Create an LLM span for the API call
                       @tracer.start_span("llm.#{model}", kind: :llm) do |llm_span|
                         llm_response = @provider.chat_completion(
                           messages: api_messages,
                           model: model,
                           tools: get_all_tools_for_api(current_agent),
                           stream: false,
                           **model_params
                         )

                         # Capture usage data if available
                         if llm_response.is_a?(Hash) && llm_response["usage"]
                           usage = llm_response["usage"]
                           # Only set usage attributes if we have actual token counts
                           if usage["input_tokens"] && usage["output_tokens"] &&
                              (usage["input_tokens"] > 0 || usage["output_tokens"] > 0)
                             # Set individual usage attributes for OpenAI processor
                             llm_span.set_attribute("llm.usage.input_tokens", usage["input_tokens"])
                             llm_span.set_attribute("llm.usage.output_tokens", usage["output_tokens"])

                             # Also set the full llm attribute for cost manager
                             llm_span.set_attribute("llm", {
                                                      "request" => {
                                                        "model" => model,
                                                        "messages" => api_messages
                                                      },
                                                      "response" => llm_response,
                                                      "usage" => usage
                                                    })
                           end
                         end

                         # Accumulate usage data for final result
                         if llm_response.is_a?(Hash) && llm_response["usage"]
                           usage = llm_response["usage"]
                           accumulated_usage[:input_tokens] += usage["prompt_tokens"] || 0
                           accumulated_usage[:output_tokens] += usage["completion_tokens"] || 0
                           accumulated_usage[:total_tokens] += usage["total_tokens"] || 0
                         end

                         # Always set request attributes
                         llm_span.set_attribute("llm.request.model", model)
                         llm_span.set_attribute("llm.request.messages", api_messages)

                         # Set response content if available
                         if llm_response.dig("choices", 0, "message", "content")
                           llm_span.set_attribute("llm.response.content",
                                                  llm_response["choices"][0]["message"]["content"])
                         end

                         llm_response
                       end
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

          # Check if execution should stop after processing response
          if should_stop?
            conversation << { role: "assistant", content: "Execution stopped by user request." }
            raise ExecutionStoppedError, "Execution stopped by user request after processing response"
          end

          result
        end

        # Restore original span stack after span block completes
        @tracer.instance_variable_get(:@context).instance_variable_set(:@span_stack, original_span_stack)

        turns += 1

        # Check if execution was stopped
        if agent_result[:stopped]
          conversation << { role: "assistant", content: "Execution stopped by user request." }
          raise ExecutionStoppedError, "Execution stopped by user request"
        end

        # Check for handoff
        if agent_result[:handoff]
          log_debug_handoff("Processing handoff request",
                            from_agent: current_agent.name,
                            requested_agent: agent_result[:handoff])

          handoff_agent = current_agent.find_handoff(agent_result[:handoff])

          if handoff_agent.nil?
            log_debug_handoff("Handoff target not found",
                              from_agent: current_agent.name,
                              requested_agent: agent_result[:handoff],
                              available_handoffs: current_agent.handoffs.map(&:name).join(", "))
            raise HandoffError, "Cannot handoff to '#{agent_result[:handoff]}'"
          end

          log_debug_handoff("Handoff target found, executing handoff",
                            from_agent: current_agent.name,
                            to_agent: handoff_agent.name)

          # Call handoff hooks
          call_hook(:on_handoff, context_wrapper, current_agent, handoff_agent)

          # Update context for handoff tracking
          context_wrapper.add_handoff(current_agent, handoff_agent)

          @tracer.handoff_span(current_agent.name || "agent",
                               handoff_agent.name || agent_result[:handoff]) do |handoff_span|
            handoff_span.add_event("handoff.initiated", attributes: {
                                     "handoff.from" => current_agent.name || "agent",
                                     "handoff.to" => handoff_agent.name || agent_result[:handoff]
                                   })
          end

          log_debug_handoff("Handoff completed, switching to new agent",
                            from_agent: current_agent.name,
                            to_agent: handoff_agent.name)

          current_agent = handoff_agent
          turns = 0 # Reset turn counter for new agent

          # Continue execution with the new agent instead of skipping to next iteration
          # This matches the behavior of the Python SDK's automatic handoff execution
          # Reset agent_result to ensure the loop continues with the new agent
          agent_result = { done: false, handoff: nil }
        end

        # Check if we're done
        break if agent_result[:done]

        # Check max turns for current agent
        if turns >= current_agent.max_turns
          raise MaxTurnsError,
                "Maximum turns (#{current_agent.max_turns}) on #{current_agent.name} exceeded"
        end
      end

      # Get final output for agent end hook
      final_output = conversation.last[:content] if conversation.last[:role] == "assistant"

      # Run output guardrails
      run_output_guardrails(context_wrapper, current_agent, final_output) if final_output

      # Call agent end hooks
      call_hook(:on_agent_end, context_wrapper, current_agent, final_output)

      RunResult.success(
        messages: conversation,
        last_agent: current_agent,
        turns: turns,
        usage: accumulated_usage
      )
    end

    # New method for Responses API using items-based conversation model (matches Python)
    def run_with_responses_api(messages, config:)
      # Use shared execution core with hooks support
      execute_responses_api_core(messages, config, with_tracing: true)
    end

    def run_without_tracing(messages, config:)
      # Always use Responses API execution core
      run_with_responses_api_no_trace(messages, config: config)

      conversation = messages.dup
      current_agent = @agent
      turns = 0
      accumulated_usage = {
        input_tokens: 0,
        output_tokens: 0,
        total_tokens: 0
      }

      max_turns = config.max_turns || current_agent.max_turns

      while turns < max_turns
        # Check if execution should stop
        if should_stop?
          conversation << { role: "assistant", content: "Execution stopped by user request." }
          raise ExecutionStoppedError, "Execution stopped by user request"
        end

        # Call agent start hook
        call_hook(:on_agent_start, context_wrapper, current_agent)

        # Prepare messages for API call
        api_messages = build_messages(conversation, current_agent, context_wrapper)

        # Make API call using provider (supports hosted tools)
        model = config.model || current_agent.model
        model_params = config.to_model_params

        # Add structured output support (matching Python implementation)
        if current_agent.response_format
          # Use the response_format directly if provided
          model_params[:response_format] = current_agent.response_format
        end

        # Add tool choice support if configured
        if current_agent.respond_to?(:tool_choice) && current_agent.tool_choice
          model_params[:tool_choice] = current_agent.tool_choice
        end

        response = if config.stream
                     @provider.stream_completion(
                       messages: api_messages,
                       model: model,
                       tools: get_all_tools_for_api(current_agent),
                       **model_params
                     )
                   else
                     @provider.chat_completion(
                       messages: api_messages,
                       model: model,
                       tools: get_all_tools_for_api(current_agent),
                       stream: false,
                       **model_params
                     )
                   end

        # Accumulate usage data
        if response.is_a?(Hash) && response["usage"]
          usage = response["usage"]
          accumulated_usage[:input_tokens] += usage["prompt_tokens"] || 0
          accumulated_usage[:output_tokens] += usage["completion_tokens"] || 0
          accumulated_usage[:total_tokens] += usage["total_tokens"] || 0
        end

        # Process response
        result = process_response(response, current_agent, conversation)

        # Check if execution should stop after processing response
        if should_stop?
          conversation << { role: "assistant", content: "Execution stopped by user request." }
          raise ExecutionStoppedError, "Execution stopped by user request after processing response"
        end

        turns += 1

        # Check if execution was stopped
        if result[:stopped]
          conversation << { role: "assistant", content: "Execution stopped by user request." }
          raise ExecutionStoppedError, "Execution stopped by user request"
        end

        # Check for handoff
        if result[:handoff]
          log_debug_handoff("Processing handoff request",
                            from_agent: current_agent.name,
                            requested_agent: result[:handoff])

          handoff_agent = current_agent.find_handoff(result[:handoff])

          if handoff_agent.nil?
            log_debug_handoff("Handoff target not found",
                              from_agent: current_agent.name,
                              requested_agent: result[:handoff],
                              available_handoffs: current_agent.handoffs.map(&:name).join(", "))
            raise HandoffError, "Cannot handoff to '#{result[:handoff]}'"
          end

          # Call handoff hook
          call_hook(:on_handoff, context_wrapper, current_agent, handoff_agent)

          log_debug_handoff("Handoff completed",
                            from_agent: current_agent.name,
                            to_agent: handoff_agent.name)

          current_agent = handoff_agent
          turns = 0 # Reset turn counter for new agent
          next
        end

        # Check if we're done
        break if result[:done]

        # Check max turns for current agent
        raise MaxTurnsError, "Maximum turns (#{current_agent.max_turns}) exceeded" if turns >= current_agent.max_turns
      end

      # Call agent end hook
      final_output = conversation.last[:content] if conversation.last[:role] == "assistant"
      call_hook(:on_agent_end, context_wrapper, current_agent, final_output)

      RunResult.success(
        messages: conversation,
        last_agent: current_agent,
        turns: turns,
        usage: accumulated_usage
      )
    end

    def build_messages(conversation, agent, context_wrapper = nil)
      system_message = {
        role: "system",
        content: build_system_prompt(agent, context_wrapper)
      }

      # Convert to symbol keys for consistency with provider expectations
      formatted_conversation = conversation.map do |msg|
        {
          role: msg[:role] || msg["role"],
          content: msg[:content] || msg["content"]
        }
      end

      messages = [system_message] + formatted_conversation

      # Apply context management if enabled
      messages = @context_manager.manage_context(messages) if @context_manager

      messages
    end

    def build_system_prompt(agent, context_wrapper = nil)
      prompt_parts = []
      prompt_parts << "Name: #{agent.name}" if agent.name

      # Get instructions (may be dynamic)
      instructions = if agent.respond_to?(:get_instructions)
                       agent.get_instructions(context_wrapper)
                     else
                       agent.instructions
                     end
      prompt_parts << "Instructions: #{instructions}" if instructions

      if agent.tools?
        tool_descriptions = agent.tools.map do |tool|
          if tool.is_a?(Hash)
            # Handle simple hash tools like web_search
            tool_type = tool[:type] || tool["type"]
            "- #{tool_type}: Search the web for current information"
          else
            "- #{tool.name}: #{tool.description}"
          end
        end
        prompt_parts << "\nAvailable tools:\n#{tool_descriptions.join("\n")}"
      end

      # Handoffs are now available as tools, no need for text instructions
      unless agent.handoffs.empty?
        log_debug_handoff("Handoffs available as tools (no prompt instructions needed)",
                          agent: agent.name,
                          handoff_count: agent.handoffs.size)
      end

      prompt_parts.join("\n")
    end

    ##
    # Process a response from the Chat Completions API
    #
    # This method handles responses from the traditional Chat Completions API,
    # processing the assistant's message, executing any tool calls, and
    # detecting handoffs in the response content.
    #
    # @param response [Hash] The API response
    # @param agent [Agent] The current agent
    # @param conversation [Array<Hash>] The conversation array to append to
    #
    # @return [Hash] Result hash with processing status
    #   - :done [Boolean] Whether the conversation is complete
    #   - :handoff [String, nil] Target agent name if handoff detected
    #   - :stopped [Boolean] Whether execution was stopped
    #   - :error [Hash, nil] Error information if an error occurred
    #
    def process_response(response, agent, conversation)
      # Handle error responses
      if response["error"]
        log_error("API Error", error: response["error"], agent: agent.name)
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

      assistant_message[:content] = content

      # Add tool calls if present
      assistant_message[:tool_calls] = message["tool_calls"] if message["tool_calls"]

      # Only add message to conversation if it has content or tool calls
      if assistant_message[:content] || assistant_message[:tool_calls]
        conversation << assistant_message
        log_debug("Added assistant message",
                  agent: agent.name,
                  tool_calls: assistant_message[:tool_calls]&.size || 0,
                  content_length: assistant_message[:content]&.length || 0)

        # Debug assistant response if enabled
        if OpenAIAgents::Logging.configuration.debug_enabled?(:context)
          content_preview = assistant_message[:content].to_s[0..500]
          content_preview += "..." if assistant_message[:content].to_s.length > 500

          log_debug("Assistant response details",
                    agent: agent.name,
                    content_preview: content_preview,
                    tool_calls_count: assistant_message[:tool_calls]&.size || 0)

          assistant_message[:tool_calls]&.each_with_index do |tc, i|
            log_debug("Tool call detail",
                      agent: agent.name,
                      tool_index: i,
                      tool_name: tc.dig("function", "name"),
                      arguments: tc.dig("function", "arguments"))
          end
        end
      end

      result = { done: false, handoff: nil }

      # Check for tool calls
      if message["tool_calls"]
        # Pass context_wrapper if we have it (only in run_with_tracing)
        context_wrapper = @current_context_wrapper if defined?(@current_context_wrapper)
        # Also pass the full response to capture OpenAI-hosted tool results
        tool_result = process_tool_calls(message["tool_calls"], agent, conversation, context_wrapper, response)

        # Handle different return types from process_tool_calls
        if tool_result == true
          # Stop was requested
          result[:done] = true
          result[:stopped] = true
        elsif tool_result.is_a?(String)
          # Handoff was requested - tool_result is the target agent name
          result[:handoff] = tool_result
          result[:done] = false
          log_debug_handoff("Handoff set from tool execution",
                            from_agent: agent.name,
                            to_agent: tool_result)
        else
          # Boolean false or other values
          result[:done] = tool_result
        end
      end

      # NOTE: Text-based handoff detection now implemented through unified detection system

      # Unified handoff detection system
      if !result[:handoff] && message["content"]
        handoff_target = detect_handoff_in_content(message["content"], agent)
        if handoff_target
          result[:handoff] = handoff_target
          result[:done] = false
        end
      end

      # If no tool calls and no handoff, we're done
      # Only set done to true if there are no tool calls AND no handoff was detected
      if !message["tool_calls"] && !result[:handoff]
        result[:done] = true
      elsif result[:handoff]
        # When handoff is detected, we should continue execution with the new agent
        result[:done] = false
      end

      result
    end

    ##
    # Process multiple tool calls from the LLM
    #
    # This method handles the execution of one or more tool calls, including
    # local tools, OpenAI-hosted tools, and handoff tools. It manages proper
    # error handling, stop checking, and handoff detection.
    #
    # @param tool_calls [Array<Hash>] Array of tool call objects from the API
    # @param agent [Agent] The current agent
    # @param conversation [Array<Hash>] The conversation to append tool results to
    # @param context_wrapper [RunContextWrapper, nil] The run context for hooks
    # @param full_response [Hash, nil] The full API response (for hosted tools)
    #
    # @return [Boolean, String] Returns:
    #   - true if execution should stop
    #   - String with agent name if handoff detected
    #   - false to continue conversation
    #
    def process_tool_calls(tool_calls, agent, conversation, context_wrapper = nil, full_response = nil)
      log_debug_tools("Processing tool calls",
                      agent: agent.name,
                      tool_count: tool_calls.size)

      # Check if we should stop before processing ANY tools
      if should_stop?
        log_warn("Stop requested - cancelling tool calls",
                 agent: agent.name,
                 cancelled_tools: tool_calls.size)
        # Add a single tool result indicating all tools were cancelled
        conversation << {
          role: "tool",
          tool_call_id: tool_calls.first["id"],
          content: "All tool executions cancelled: Execution stopped by user request"
        }
        return true # Indicate we should stop the conversation
      end

      # Process each tool call and collect results using Ruby iterators
      # But stop early if a stop is detected
      results = tool_calls.map do |tool_call|
        # Check stop before each tool
        if should_stop?
          {
            role: "tool",
            tool_call_id: tool_call["id"],
            content: "Tool execution cancelled: Execution stopped by user request"
          }
        else
          process_single_tool_call(tool_call, agent, context_wrapper, full_response)
        end
      end

      # Add all results to conversation
      results.each { |message| conversation << message }

      log_debug_tools("Tool processing complete",
                      agent: agent.name,
                      total_messages: conversation.size,
                      tool_results: results.size)

      # Check for handoffs with proper multiple handoff handling
      handoff_results = results.select { |result| result[:handoff] }

      if handoff_results.size > 1
        # Multiple handoffs detected - this is an error condition
        handoff_targets = handoff_results.map { |r| r[:handoff] }
        log_error("Multiple handoffs detected in single turn - this is not supported",
                  from_agent: agent.name,
                  handoff_targets: handoff_targets,
                  count: handoff_results.size)

        # Fail fast - add error message to conversation and continue with original agent
        conversation << {
          role: "assistant",
          content: "Error: Multiple agent handoffs detected in single response. Only one handoff per turn is supported. Staying with current agent."
        }

        return false # Continue with current agent
      elsif handoff_results.size == 1
        handoff_result = handoff_results.first
        log_debug_handoff("Single handoff detected from tool execution",
                          from_agent: agent.name,
                          to_agent: handoff_result[:handoff],
                          tool_result: true)
        # Return the handoff target to trigger agent switching
        return handoff_result[:handoff]
      end

      # Check if any tool result indicates a stop
      stop_requested = results.any? do |result|
        result[:content]&.include?("cancelled") && result[:content].include?("stopped by user")
      end

      # Debug conversation if enabled
      if OpenAIAgents::Logging.configuration.debug_enabled?(:context)
        log_debug("Full conversation dump",
                  agent: agent.name,
                  message_count: conversation.size)
        conversation.each_with_index do |msg, i|
          content_preview = msg[:content].to_s[0..200]
          content_preview += "..." if msg[:content].to_s.length > 200
          log_debug("Conversation message",
                    agent: agent.name,
                    message_index: i,
                    role: msg[:role],
                    content_preview: content_preview)
        end
      end

      # Return true if stop was requested, otherwise false to continue
      stop_requested
    end

    ##
    # Process a single tool call
    #
    # This method executes an individual tool call, handling different types:
    # - OpenAI-hosted tools (web_search, code_interpreter, file_search)
    # - Handoff tools (transfer_to_* functions)
    # - Local custom tools defined by the user
    #
    # @param tool_call [Hash] The tool call object with id and function details
    # @param agent [Agent] The agent executing the tool
    # @param context_wrapper [RunContextWrapper, nil] The run context
    # @param full_response [Hash, nil] Full API response for hosted tools
    #
    # @return [Hash] Tool result message with:
    #   - :role [String] Always "tool"
    #   - :tool_call_id [String] The tool call ID
    #   - :content [String] The tool execution result
    #   - :handoff [String, nil] Target agent if handoff occurred
    #
    def process_single_tool_call(tool_call, agent, context_wrapper, full_response = nil)
      # Check if execution should stop before processing tool
      if should_stop?
        return {
          role: "tool",
          tool_call_id: tool_call["id"],
          content: "Tool execution cancelled: Execution stopped by user request"
        }
      end

      tool_name = tool_call.dig("function", "name")
      arguments = JSON.parse(tool_call.dig("function", "arguments") || "{}")

      # Check if this is an OpenAI-hosted tool (web_search, code_interpreter, etc.)
      # These tools are executed by OpenAI, not locally
      openai_hosted_tools = %w[web_search code_interpreter file_search]
      if openai_hosted_tools.include?(tool_name)
        log_debug("Processing OpenAI-hosted tool", tool_name: tool_name)

        # Extract the actual results from the response if available
        tool_result = extract_openai_tool_result(tool_call["id"], full_response)

        # Create a detailed trace for the OpenAI-hosted tool
        if @tracer && !@disabled_tracing
          @tracer.tool_span(tool_name) do |tool_span|
            tool_span.set_attribute("function.name", tool_name)
            tool_span.set_attribute("function.input", arguments)

            # Add the actual results if we found them
            if tool_result
              tool_span.set_attribute("function.output", tool_result)
              tool_span.set_attribute("function.has_results", true)
            else
              tool_span.set_attribute("function.output", "[Results embedded in assistant response]")
              tool_span.set_attribute("function.has_results", false)
            end

            tool_span.add_event("openai_hosted_tool")

            # Add detailed attributes for web_search
            if tool_name == "web_search" && arguments["query"]
              tool_span.set_attribute("web_search.query", arguments["query"])
            end
          end
        end

        # Return a message that includes extracted results if available
        content = if tool_result
                    "OpenAI-hosted tool '#{tool_name}' executed successfully."
                  else
                    "OpenAI-hosted tool '#{tool_name}' executed. Results in assistant response."
                  end

        # Debug OpenAI-hosted tool result if enabled
        if OpenAIAgents::Logging.configuration.debug_enabled?(:context)
          log_debug("OpenAI-hosted tool result", tool_name: tool_name)
          log_debug("Tool arguments", arguments: arguments)

          # For web_search and other hosted tools, show the integrated results
          if tool_result
            result_preview = tool_result.to_s[0..2000] # Show more content for search results
            result_preview += "..." if tool_result.to_s.length > 2000
            log_debug("Tool integrated results", result_preview: result_preview)
          else
            log_debug("Tool result", status: "no extractable results")
          end

          # Also show the raw response structure for debugging
          if full_response && OpenAIAgents::Logging.configuration.debug_enabled?(:api)
            log_debug("Raw response keys", keys: full_response.keys)
            if full_response["choices"]&.first&.dig("message")
              msg = full_response["choices"].first["message"]
              log_debug("Message keys", keys: msg.keys)
            end
          end

          log_debug("Completed OpenAI-hosted tool result processing")
        end

        return {
          role: "tool",
          tool_call_id: tool_call["id"],
          content: content
        }
      end

      # Check if this is a handoff tool (starts with "transfer_to_")
      return process_handoff_tool_call(tool_call, agent, context_wrapper) if tool_name.start_with?("transfer_to_")

      # Find the tool object for local tools
      tool = agent.tools.find { |t| t.respond_to?(:name) && t.name == tool_name }

      # Call tool start hooks if context is available
      call_hook(:on_tool_start, context_wrapper, agent, tool, arguments) if context_wrapper && tool

      log_debug("Executing tool", tool_name: tool_name, call_id: tool_call["id"])

      begin
        log_debug("About to execute agent tool", tool_name: tool_name, arguments: arguments)

        # function_span in Python implementation
        result = if @tracer && !@disabled_tracing
                   execute_tool_with_tracing(tool_name, arguments, agent)
                 else
                   agent.execute_tool(tool_name, **arguments.transform_keys(&:to_sym))
                 end

        log_debug("Tool execution completed", result_class: result.class.name)
        log_debug("Tool result", result: result.to_s[0..200])

        # Call tool end hooks if context is available
        call_hook(:on_tool_end, context_wrapper, agent, tool, result) if context_wrapper && tool

        formatted_result = format_tool_result(result)

        # Debug tool result if enabled
        if OpenAIAgents::Logging.configuration.debug_enabled?(:context)
          log_debug("Tool execution result", tool_name: tool_name)
          result_preview = formatted_result.to_s[0..1000]
          result_preview += "..." if formatted_result.to_s.length > 1000
          log_debug("Tool result preview", result: result_preview)
          log_debug("Completed tool result processing")
        end

        {
          role: "tool",
          tool_call_id: tool_call["id"],
          content: formatted_result
        }
      rescue StandardError => e
        log_error("Tool execution error", error: e.message)
        log_error("Tool execution backtrace", backtrace: e.backtrace[0..2].join('\n'))

        @tracer.record_exception(e) if @tracer && !@disabled_tracing

        {
          role: "tool",
          tool_call_id: tool_call["id"],
          content: "Error: #{e.message}"
        }
      end
    end

    def execute_tool_with_tracing(tool_name, arguments, agent)
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
          tool_span.set_attribute("function.output", format_tool_result(res)[0..1000]) # Limit size
        else
          tool_span.set_attribute("function.output", "[REDACTED]")
        end

        tool_span.add_event("function.complete")
        res
      end
    end

    ##
    # Normalize input messages to a consistent format
    #
    # This method converts various input formats to the standard
    # array of message hashes format expected by the API.
    #
    # @param messages [String, Array<Hash>, Object] The input messages
    #
    # @return [Array<Hash>] Normalized array of message hashes
    #
    # @example String input
    #   normalize_messages("Hello")
    #   # => [{ role: "user", content: "Hello" }]
    #
    # @example Array input
    #   normalize_messages([{ role: "user", content: "Hi" }])
    #   # => [{ role: "user", content: "Hi" }]
    #
    def normalize_messages(messages)
      case messages
      when String
        # Convert string to user message
        [{ role: "user", content: messages }]
      when Array
        # Already an array, create a deep copy to avoid mutating original
        messages.map(&:dup)
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
        elsif item.is_a?(Hash)
          # For hash tools like { type: "web_search" }, return JSON instead of Ruby hash syntax
          item.to_json
        else
          item.to_s
        end
      end
    rescue StandardError
      []
    end

    # Format tool results for proper JSON serialization instead of Ruby hash syntax
    def format_tool_result(result)
      case result
      when Hash, Array
        # Convert structured data to JSON to avoid Ruby hash syntax (=>)
        result.to_json
      when nil
        ""
      else
        # For simple values (strings, numbers, etc.), use to_s
        result.to_s
      end
    end

    # Extract results from OpenAI-hosted tools in the response
    def extract_openai_tool_result(tool_call_id, full_response)
      return nil unless full_response

      # OpenAI sometimes includes tool results in a parallel structure
      # Check if there's a tool_outputs or similar field
      if full_response["tool_outputs"]
        output = full_response["tool_outputs"].find { |o| o["tool_call_id"] == tool_call_id }
        return output["output"] if output
      end

      # For web_search and other hosted tools, check if there are structured results
      # in the response that we can extract for debugging
      choice = full_response.dig("choices", 0)
      return nil unless choice

      # Check for tool-specific result structures in the response
      # OpenAI may include search results in various formats
      if full_response["search_results"] || full_response["web_search_results"]
        search_results = full_response["search_results"] || full_response["web_search_results"]
        return search_results if search_results.is_a?(Array) || search_results.is_a?(Hash)
      end

      # Check the message content for embedded results
      message_content = choice.dig("message", "content")
      return nil unless message_content

      # For debugging purposes, always return the message content for hosted tools
      # since the results are integrated into the AI's response
      message_content
    end

    # Process handoff tool calls (transfer_to_* functions)
    def process_handoff_tool_call(tool_call, agent, context_wrapper)
      tool_name = tool_call.dig("function", "name")
      arguments = JSON.parse(tool_call.dig("function", "arguments") || "{}")

      # Extract target agent name from tool name with robust parsing
      # Handle various naming patterns: transfer_to_agent_name, transfer_to_AgentName, etc.
      target_agent_name = extract_agent_name_from_tool(tool_name)

      log_debug_handoff("Processing handoff tool call",
                        from_agent: agent.name,
                        tool_name: tool_name,
                        target_agent: target_agent_name,
                        call_id: tool_call["id"])

      # Find handoff target using the same validation logic as text handoffs
      available_targets = get_available_handoff_targets(agent)
      validated_target = validate_handoff_target(target_agent_name, available_targets)

      # Track handoff chain for circular detection
      @handoff_chain ||= []
      @handoff_chain << agent.name if @handoff_chain.empty? # Add starting agent

      # Find the handoff target with circular handoff protection
      if @handoff_chain&.include?(validated_target)
        log_error("Circular handoff detected",
                  from_agent: agent.name,
                  target_agent: validated_target,
                  handoff_chain: @handoff_chain)

        return {
          role: "tool",
          tool_call_id: tool_call["id"],
          content: "Error: Circular handoff detected. Cannot transfer to #{validated_target} as it would create a loop.",
          handoff_error: true
        }
      end

      if validated_target
        handoff_target = agent.handoffs.find do |handoff|
          if handoff.is_a?(Agent)
            handoff.name == validated_target
          else
            handoff.agent_name == validated_target || handoff.tool_name == tool_name
          end
        end
      end

      unless handoff_target
        available_handoffs = agent.handoffs.map do |h|
          h.is_a?(Agent) ? h.name : h.agent_name
        end.join(", ")

        log_error("Handoff target not found for tool call",
                  from_agent: agent.name,
                  tool_name: tool_name,
                  target_agent: validated_target || target_agent_name,
                  available_handoffs: available_handoffs)

        # This is a critical error that should be handled properly
        error_message = "Error: Handoff target '#{validated_target || target_agent_name}' not found. Available targets: #{available_handoffs}"

        return {
          role: "tool",
          tool_call_id: tool_call["id"],
          content: error_message,
          handoff_error: true # Mark this as a handoff error for better handling
        }
      end

      # Execute the handoff
      if handoff_target.is_a?(Agent)
        # Simple agent handoff
        handoff_result = { assistant: handoff_target.name }

        log_debug_handoff("Agent handoff tool executed successfully",
                          from_agent: agent.name,
                          to_agent: handoff_target.name,
                          tool_name: tool_name)
      else
        # Handoff object with custom logic
        begin
          handoff_result = handoff_target.invoke(context_wrapper, arguments)

          log_debug_handoff("Handoff object tool executed successfully",
                            from_agent: agent.name,
                            to_agent: handoff_target.agent_name,
                            tool_name: tool_name)
        rescue StandardError => e
          log_error("Handoff object tool execution failed",
                    from_agent: agent.name,
                    to_agent: handoff_target.agent_name,
                    tool_name: tool_name,
                    error: e.message,
                    error_class: e.class.name)

          return {
            role: "tool",
            tool_call_id: tool_call["id"],
            content: "Error executing handoff: #{e.message}",
            handoff_error: true # Mark this as a handoff error
          }
        end
      end

      # Track this handoff in the chain
      @handoff_chain << validated_target

      # Limit handoff chain length
      if @handoff_chain.length > 5
        log_error("Maximum handoff chain length exceeded",
                  from_agent: agent.name,
                  target_agent: target_agent_name,
                  handoff_chain: @handoff_chain)

        return {
          role: "tool",
          tool_call_id: tool_call["id"],
          content: "Error: Maximum handoff chain length (5) exceeded. Stopping handoff chain.",
          handoff_error: true
        }
      end

      log_debug_handoff("Handoff chain updated",
                        from_agent: agent.name,
                        target_agent: target_agent_name,
                        handoff_chain: @handoff_chain)

      # Return success response with handoff signal
      {
        role: "tool",
        tool_call_id: tool_call["id"],
        content: JSON.generate(handoff_result),
        handoff: validated_target # Signal to runner that handoff occurred
      }
    end

    # Extract agent name from handoff tool name with robust parsing
    def extract_agent_name_from_tool(tool_name)
      # Remove the transfer_to_ prefix
      agent_part = tool_name.sub(/^transfer_to_/, "")

      # Try different parsing strategies

      # Strategy 1: Check if it's already in proper case (e.g., "SupportAgent")
      return agent_part if agent_part =~ /^[A-Z][a-zA-Z]*$/

      # Strategy 2: Split on underscores and capitalize each part
      return agent_part.split("_").map(&:capitalize).join if agent_part.include?("_")

      # Strategy 3: Just capitalize the first letter for simple names
      agent_part.capitalize
    end

    ##
    # Detect handoff requests in response content
    #
    # This unified method detects handoff requests in agent responses using
    # multiple strategies:
    # 1. JSON-based handoffs (e.g., {"handoff_to": "BillingAgent"})
    # 2. Text-based handoffs (e.g., "I'll transfer you to Support")
    #
    # @param content [String] The response content to analyze
    # @param agent [Agent] The current agent (for available handoffs)
    #
    # @return [String, nil] The validated target agent name or nil
    #
    # @example JSON handoff
    #   content = '{"handoff_to": "BillingAgent", "reason": "payment issue"}'
    #   detect_handoff_in_content(content, agent)  # => "BillingAgent"
    #
    # @example Text handoff
    #   content = "I'll transfer you to the Support team for this issue."
    #   detect_handoff_in_content(content, agent)  # => "Support"
    #
    def detect_handoff_in_content(content, agent)
      return nil unless content && !content.empty?

      # Strategy 1: JSON-based handoff detection
      handoff_target = detect_json_handoff(content, agent)
      return handoff_target if handoff_target

      # Strategy 2: Text-based handoff detection
      handoff_target = detect_text_handoff(content, agent)
      return handoff_target if handoff_target

      # No handoff detected
      nil
    end

    # Detect JSON-based handoffs in response content
    def detect_json_handoff(content, agent)
      begin
        # Try to parse the content as JSON
        parsed_content = JSON.parse(content)

        # Check for handoff_to field (multiple possible formats)
        if parsed_content.is_a?(Hash)
          # Check various field names for handoff target
          handoff_target = parsed_content["handoff_to"] ||
                           parsed_content[:handoff_to] ||
                           parsed_content["transfer_to"] ||
                           parsed_content[:transfer_to] ||
                           parsed_content["next_agent"] ||
                           parsed_content[:next_agent]

          if handoff_target
            # Validate the handoff target against available targets
            available_targets = get_available_handoff_targets(agent)
            validated_target = validate_handoff_target(handoff_target, available_targets)

            if validated_target
              log_debug_handoff("JSON handoff detected in agent response",
                                from_agent: agent.name,
                                to_agent: validated_target,
                                source: "JSON response content",
                                detection_method: "json_field")

              return validated_target
            end
          end

          # Check for nested handoff structures
          if parsed_content["handoff"] && parsed_content["handoff"]["to"]
            handoff_target = parsed_content["handoff"]["to"]

            # Validate the handoff target against available targets
            available_targets = get_available_handoff_targets(agent)
            validated_target = validate_handoff_target(handoff_target, available_targets)

            if validated_target
              log_debug_handoff("JSON handoff detected in nested structure",
                                from_agent: agent.name,
                                to_agent: validated_target,
                                source: "JSON response content",
                                detection_method: "json_nested")

              return validated_target
            end
          end
        end
      rescue JSON::ParserError
        # Not JSON, continue to text-based detection
      end

      nil
    end

    # Detect text-based handoffs in response content
    def detect_text_handoff(content, agent)
      # Get available handoff targets for validation
      available_targets = get_available_handoff_targets(agent)
      return nil if available_targets.empty?

      # Pattern 1: Direct handoff statements
      # "I'll transfer you to the SupportAgent"
      # "Transferring to CustomerService"
      # "Let me hand this off to TechnicalSupport"
      transfer_patterns = [
        /(?:transfer|handoff|hand\s*off|delegate|switch|redirect)(?:ing|ring)?\s+(?:you\s+)?to\s+(?:the\s+)?(\w+)/i,
        /(?:I'll|I\s+will|Let\s+me)\s+(?:transfer|handoff|hand\s*off|delegate|switch|redirect)\s+(?:you\s+)?(?:to\s+)?(?:the\s+)?(\w+)/i,
        /(?:routing|directing|forwarding)\s+(?:you\s+)?to\s+(?:the\s+)?(\w+)/i
      ]

      transfer_patterns.each do |pattern|
        match = content.match(pattern)
        next unless match

        potential_target = match[1]
        # Validate against available targets
        validated_target = validate_handoff_target(potential_target, available_targets)
        next unless validated_target

        log_debug_handoff("Text handoff detected in agent response",
                          from_agent: agent.name,
                          to_agent: validated_target,
                          source: "text response content",
                          detection_method: "text_pattern",
                          pattern: pattern.inspect,
                          matched_text: match[0])

        return validated_target
      end

      # Pattern 2: Specific agent mentions
      # "Please contact CustomerService for billing issues"
      # "You should speak with TechnicalSupport about this"
      mention_patterns = [
        /(?:contact|speak\s+with|talk\s+to|reach\s+out\s+to|connect\s+with)\s+(?:the\s+)?(\w+)/i,
        /(?:please|you\s+should|you\s+need\s+to|you\s+can)\s+(?:contact|speak\s+with|talk\s+to|reach\s+out\s+to|connect\s+with)\s+(?:the\s+)?(\w+)/i
      ]

      mention_patterns.each do |pattern|
        match = content.match(pattern)
        next unless match

        potential_target = match[1]
        validated_target = validate_handoff_target(potential_target, available_targets)
        next unless validated_target

        log_debug_handoff("Text handoff detected via agent mention",
                          from_agent: agent.name,
                          to_agent: validated_target,
                          source: "text response content",
                          detection_method: "text_mention",
                          pattern: pattern.inspect,
                          matched_text: match[0])

        return validated_target
      end

      # Pattern 3: Explicit agent name references
      # Check if any available target is explicitly mentioned as a standalone word
      available_targets.each do |target|
        # Case-insensitive word boundary matching
        next unless content.match(/\b#{Regexp.escape(target)}\b/i)

        log_debug_handoff("Text handoff detected via explicit agent name",
                          from_agent: agent.name,
                          to_agent: target,
                          source: "text response content",
                          detection_method: "text_explicit",
                          matched_agent: target)

        return target
      end

      nil
    end

    # Get available handoff targets for an agent
    def get_available_handoff_targets(agent)
      return [] unless agent.respond_to?(:handoffs)

      agent.handoffs.map do |handoff|
        if handoff.is_a?(Agent)
          handoff.name
        elsif handoff.respond_to?(:agent_name)
          handoff.agent_name
        else
          nil
        end
      end.compact
    end

    # Validate a potential handoff target against available targets
    def validate_handoff_target(potential_target, available_targets)
      return nil if potential_target.nil? || potential_target.empty?

      # Direct match (case-insensitive)
      direct_match = available_targets.find { |target| target.downcase == potential_target.downcase }
      return direct_match if direct_match

      # Fuzzy matching for variations
      # Check if potential_target is a substring of any available target
      substring_match = available_targets.find { |target| target.downcase.include?(potential_target.downcase) }
      return substring_match if substring_match

      # Check if any available target is a substring of potential_target
      contains_match = available_targets.find { |target| potential_target.downcase.include?(target.downcase) }
      return contains_match if contains_match

      # No match found
      nil
    end

    # Extract content from a message item, handling different content formats
    def extract_content_from_message_item(message_item)
      return nil unless message_item&.raw_item

      raw_item = message_item.raw_item
      content = raw_item[:content] || raw_item["content"]

      # Handle different content formats
      case content
      when String
        content
      when Array
        # Handle array format like [{ type: "text", text: "content" }]
        content.map do |item|
          if item.is_a?(Hash)
            item[:text] || item["text"] || item.to_s
          else
            item.to_s
          end
        end.join(" ")
      when Hash
        # Handle hash format
        content[:text] || content["text"] || content.to_s
      else
        content.to_s
      end
    end
  end
end

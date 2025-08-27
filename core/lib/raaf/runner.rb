# frozen_string_literal: true

require "async"
require "json"
require "net/http"
require "uri"
require_relative "agent"
require_relative "errors"
require_relative "models/responses_provider"
# require_relative "tracing/trace_provider"  # AIDEV-FIXED: Moved to raaf-tracing gem
require_relative "strict_schema"
require_relative "structured_output"
require_relative "result"
require_relative "run_config"
require_relative "session"
require_relative "run_context"
require_relative "lifecycle"
# require_relative "run_result_streaming"  # AIDEV-FIXED: Moved to raaf-streaming gem
# require_relative "streaming_events_semantic"  # AIDEV-FIXED: Moved to raaf-streaming gem
require_relative "items"
require_relative "context_manager"
require_relative "context_config"
require_relative "run_executor"
require_relative "unified_step_executor"
require_relative "step_result"
require_relative "processed_response"
require_relative "response_processor"
require_relative "tool_use_tracker"
require_relative "step_processor"
require_relative "step_errors"

module RAAF

  ##
  # The Runner class is the core execution engine for RAAF.
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
  #   agent = RAAF::Agent.new(
  #     name: "Assistant",
  #     instructions: "You are a helpful assistant",
  #     model: "gpt-4o"
  #   )
  #   runner = RAAF::Runner.new(agent: agent)
  #   result = runner.run("Hello, how can you help?")
  #   puts result.messages.last[:content]
  #
  # @example With tracing enabled
  #   tracer = RAAF::Tracing::SpanTracer.new
  #   runner = RAAF::Runner.new(agent: agent, tracer: tracer)
  #   result = runner.run("What's the weather?")
  #
  # @example Multi-agent handoffs
  #   support_agent = RAAF::Agent.new(name: "Support", instructions: "...")
  #   billing_agent = RAAF::Agent.new(name: "Billing", instructions: "...")
  #   support_agent.add_handoff(billing_agent)
  #
  #   runner = RAAF::Runner.new(agent: support_agent)
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
    # @param memory_manager [MemoryManager, nil] Memory manager for semantic memory storage
    #
    # @example With custom provider
    #   provider = RAAF::Models::AnthropicProvider.new
    #   runner = RAAF::Runner.new(agent: agent, provider: provider)
    #
    # @example With stop checker
    #   stop_checker = -> { File.exist?('/tmp/stop') }
    #   runner = RAAF::Runner.new(agent: agent, stop_checker: stop_checker)
    #
    # @example With memory manager
    #   # Note: Requires 'raaf-memory' gem
    #   require 'raaf/memory'
    #   require 'raaf/memory_manager'
    #
    #   memory_manager = RAAF::MemoryManager.new(store: RAAF::Memory.create(:file))
    #   runner = RAAF::Runner.new(agent: agent, memory_manager: memory_manager)
    #
    def initialize(agent:, provider: nil, tracer: nil, disabled_tracing: false, stop_checker: nil,
                   context_manager: nil, context_config: nil, memory_manager: nil)
      @agent = agent
      @provider = provider || create_default_provider
      @disabled_tracing = disabled_tracing || ENV["RAAF_DISABLE_TRACING"] == "true"
      @tracer = tracer || (@disabled_tracing ? nil : get_default_tracer)
      @stop_checker = stop_checker
      @memory_manager = memory_manager

      # Context management setup
      if context_manager
        @context_manager = context_manager
      elsif context_config
        @context_manager = context_config.build_context_manager(model: @agent.model)
      elsif ENV["RAAF_CONTEXT_MANAGEMENT"] == "true"
        # Auto-enable with balanced settings if env var is set
        config = ContextConfig.balanced(model: @agent.model)
        @context_manager = config.build_context_manager(model: @agent.model)
      end

      # Initialize handoff tracking for circular protection
      @handoff_chain = []

      # Initialize unified step executor (the primary processing engine)
      @unified_step_executor = UnifiedStepExecutor.new(runner: self)
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
      log_exception(e, message: "Error checking stop condition")
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
    def run(starting_agent, input = nil, stream: false, config: nil, hooks: nil, input_guardrails: nil, output_guardrails: nil,
            context: nil, max_turns: nil, session: nil, previous_response_id: nil, **)
      # Detect usage pattern to maintain backward compatibility
      if (starting_agent.is_a?(String) || starting_agent.is_a?(Array)) && input.nil?
        # Legacy pattern: run("message") or run([messages]) - use instance agent
        agent = @agent
        messages = normalize_messages(starting_agent)
      else
        # New Python SDK pattern: run(agent, "message")
        agent = starting_agent
        messages = normalize_messages(input)
      end

      # Create config if not provided
      if config.nil?
        config = RunConfig.new(
          stream: stream,
          max_turns: max_turns,
          context: context,
          session: session,
          previous_response_id: previous_response_id,
          ** # Pass any additional parameters to RunConfig
        )
      end

      # Store hooks in config for later use
      config.hooks = hooks if hooks
      config.input_guardrails = input_guardrails if input_guardrails
      config.output_guardrails = output_guardrails if output_guardrails

      # Handle session processing
      messages = process_session(session, messages) if session

      # Create appropriate executor based on tracing configuration
      executor = if config.tracing_disabled || @disabled_tracing || @tracer.nil?
                   BasicRunExecutor.new(
                     runner: self,
                     provider: @provider,
                     agent: agent,
                     config: config
                   )
                 else
                   TracedRunExecutor.new(
                     runner: self,
                     provider: @provider,
                     agent: agent,
                     config: config,
                     tracer: @tracer
                   )
                 end

      # Execute the conversation
      result = executor.execute(messages)

      # Update session with result if session was provided
      update_session_with_result(session, result) if session

      result
    end

    ##
    # Execute a conversation synchronously (Python SDK compatible alias)
    #
    # This method is an alias for run() to match the Python SDK's naming convention.
    # In Python SDK, run() is async and run_sync() is synchronous.
    #
    # @param starting_agent [Agent] The agent to start the conversation with
    # @param input [String, Array<Hash>] The input messages
    # @param stream [Boolean] Whether to stream responses
    # @param config [RunConfig, nil] Configuration for the run
    # @param kwargs [Hash] Additional parameters
    #
    # @return [Result] The result of the conversation
    #
    # @example Python SDK compatible usage
    #   result = runner.run_sync(agent, "Hello")
    #
    def run_sync(starting_agent, input, **)
      run(starting_agent, input, **)
    end

    ##
    # Execute a conversation asynchronously
    #
    # This method wraps the regular run method in an Async block for
    # concurrent execution. Useful when running multiple agents in parallel.
    #
    # @param starting_agent [Agent, String, Array<Hash>] The agent (new)
    # @param input [String, Array<Hash>, nil] The input messages (new signature)
    # @param stream [Boolean] Whether to stream responses
    # @param config [RunConfig, nil] Configuration for the run
    # @param kwargs [Hash] Additional parameters
    #
    # @return [Async::Task] An async task that resolves to a RunResult
    #
    # @example Running multiple agents concurrently (new signature)
    #   task1 = runner.run_async(agent1, "Analyze this data")
    #   task2 = runner.run_async(agent2, "Generate a report")
    #
    # @example  signature
    #   task1 = runner.run_async("Analyze this data")
    #
    def run_async(starting_agent, input = nil, stream: false, config: nil, **kwargs)
      Async do
        run(starting_agent, input, stream: stream, config: config, **kwargs)
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
      # Streaming support is now included in core

      # Normalize messages and config
      messages = normalize_messages(messages)

      if config.nil? && !kwargs.empty?
        config = RunConfig.new(**kwargs)
      elsif config.nil?
        config = RunConfig.new
      end

      # Initialize hooks context for consistency
      initialize_run_context(messages, config)
      log_debug("Run context initialized", current_config_class: @current_config&.class&.name)

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
      hooks = @current_config&.hooks
      hooks_class_name = hooks&.class&.name
      log_debug("Calling hook", hook: hook_method, config_class: hooks_class_name)

      # Call run-level hooks
      if @current_config&.hooks.respond_to?(hook_method)
        log_debug("Executing run-level hook", hook: hook_method)
        @current_config.hooks.send(hook_method, context_wrapper, *args)
      end

      # Call agent-level hooks if applicable
      agent = args.first if args.first.is_a?(Agent)
      agent_hook_method = hook_method.to_s.sub("on_agent_", "on_")
      if agent&.hooks.respond_to?(agent_hook_method)
        log_debug("Executing agent-level hook", hook: agent_hook_method, agent: agent.name)
        agent.hooks.send(agent_hook_method, context_wrapper, *args)
      end
    rescue StandardError => e
      log_exception(e, message: "Error in hook #{hook_method}", hook: hook_method)
    end

    ##
    # Content-based handoff detection (disabled - RAAF uses tool-based handoffs only)
    #
    # RAAF uses tool-based handoffs exclusively. Handoffs are implemented as function calls (tools)
    # that the LLM must explicitly invoke. Text-based or JSON-based handoff detection in message
    # content is not supported.
    #
    # @param content [String] Message content to analyze
    # @param current_agent [Agent] Current agent instance
    # @return [nil] Always returns nil as content-based handoffs are not supported
    #
    def detect_handoff_in_content(_content, _current_agent = nil)
      log_debug("Content-based handoff detection disabled - RAAF uses tool-based handoffs only")
      nil
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

        # Use the specific blocked reason from the guardrail if available
        blocked_reason = result.output.output_info[:blocked_reason] || "Input blocked by guardrail"

        raise Guardrails::InputGuardrailTripwireTriggered.new(
          blocked_reason,
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

      return output if guardrails.empty?

      filtered_output = output

      guardrails.each do |guardrail|
        result = guardrail.run(context_wrapper, agent, filtered_output)

        # Check if output was filtered (modified but not blocked)
        filtered_output = result.output.output_info[:filtered_output] if result.output.output_info && result.output.output_info[:filtered_output]

        # Check if guardrail was triggered (blocking case)
        next unless result.tripwire_triggered?

        # Use the specific blocked reason from the guardrail if available
        blocked_reason = result.output.output_info[:blocked_reason] || "Output blocked by guardrail"

        raise Guardrails::OutputGuardrailTripwireTriggered.new(
          blocked_reason,
          triggered_by: guardrail.get_name,
          content: output,
          metadata: result.output.output_info
        )
      end

      filtered_output
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

    # Text-based handoffs have been removed - only tool-based handoffs are supported

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
    # Get all tools available to an agent, including tools from chained handoffs
    #
    # Collects all tools from the agent and recursively traverses the handoff chain
    # to collect tools from all connected agents. Includes circular reference detection
    # to prevent infinite loops in complex handoff networks.
    #
    # @param agent [Agent] The agent to get tools for
    # @param visited_agents [Set<String>] Set of already visited agent names (for circular detection)
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
    def get_all_tools_for_api(agent, visited_agents = Set.new)
      log_debug("🔧 HANDOFF FLOW: Starting tool collection for agent", agent: agent.name)

      # Circular reference detection
      if visited_agents.include?(agent.name)
        log_debug("🔧 HANDOFF FLOW: Circular reference detected, skipping", agent: agent.name)
        return []
      end

      visited_agents = visited_agents.dup.add(agent.name)
      all_tools = []

      # Add regular tools from current agent
      if agent.tools?
        regular_tools_count = agent.tools.count
        all_tools.concat(agent.tools)
        log_debug("🔧 HANDOFF FLOW: Added regular tools",
                  agent: agent.name,
                  regular_tools_count: regular_tools_count,
                  tool_names: agent.tools.map(&:name).join(", "))
      else
        log_debug("🔧 HANDOFF FLOW: No regular tools found", agent: agent.name)
      end

      # Recursively collect tools from handoff targets
      if agent.handoffs?
        handoff_agents = collect_handoff_agents(agent)
        handoff_agents.each do |target_agent|
          next if visited_agents.include?(target_agent.name)

          log_debug("🔧 HANDOFF FLOW: Collecting tools from handoff target",
                    from_agent: agent.name,
                    target_agent: target_agent.name)

          target_tools = get_all_tools_for_api(target_agent, visited_agents)
          next unless target_tools&.any?

          # Filter out duplicate tools by name to avoid conflicts
          new_tools = target_tools.reject do |tool|
            tool_name = tool.respond_to?(:name) ? tool.name : (tool[:name] || tool["name"])
            all_tools.any? do |existing|
              existing_name = existing.respond_to?(:name) ? existing.name : (existing[:name] || existing["name"])
              existing_name == tool_name
            end
          end

          next unless new_tools.any?

          all_tools.concat(new_tools)
          log_debug("🔧 HANDOFF FLOW: Added tools from handoff target",
                    from_agent: agent.name,
                    target_agent: target_agent.name,
                    added_tools: new_tools.size,
                    tool_names: new_tools.map do |t|
                      t.respond_to?(:name) ? t.name : (t[:name] || t["name"])
                    end.join(", "))
        end
      end

      final_tools_count = all_tools.count
      log_debug("🔧 HANDOFF FLOW: Tool collection complete",
                agent: agent.name,
                final_tools_count: final_tools_count,
                visited_agents: visited_agents.to_a.join(", "),
                returning_nil: all_tools.empty?)

      all_tools.empty? ? nil : all_tools
    end

    ##
    # Collect all Agent objects from handoffs
    #
    # Extracts Agent objects from the handoffs array, resolving them from the
    # agents registry when handoffs are specified as Handoff objects.
    #
    # @param agent [Agent] The agent whose handoffs to collect from
    # @return [Array<Agent>] Array of Agent objects that can be handed off to
    #
    def collect_handoff_agents(agent)
      handoff_agents = []

      agent.instance_variable_get(:@handoffs).each do |handoff|
        case handoff
        when Agent
          handoff_agents << handoff
        when Handoff
          # Look up the target agent from the agents registry
          target_agent = @agents&.find { |a| a.name == handoff.agent.name }
          if target_agent
            handoff_agents << target_agent
          else
            log_debug("🔧 HANDOFF FLOW: Target agent not found in registry",
                      target_name: handoff.agent.name,
                      available_agents: @agents&.map(&:name)&.join(", ") || "none")
          end
        end
      end

      handoff_agents
    end

    ##
    # DEPRECATED: Legacy response processing method
    #
    # This method is deprecated and replaced by unified step processing.
    # It's kept temporarily for compatibility but will be removed.
    # Use UnifiedStepExecutor instead.
    #
    # @deprecated Use UnifiedStepExecutor.execute_step instead
    # @param response [Hash] The API response containing output items
    # @param agent [Agent] The current agent
    # @param generated_items [Array<Items::Base>] Array to append new items to
    # @param span [Tracing::Span, nil] Optional tracing span
    # @return [Hash] Result hash with :done and :handoff keys
    #
    def process_responses_api_output(response, agent, generated_items, _span = nil)
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
            if content.is_a?(Array)
              content.map { |c| c.is_a?(Hash) ? c[:text] || c["text"] : c.to_s }.join(" ")
            else
              content.to_s
            end

            # Text-based handoffs have been removed - only tool-based handoffs are supported
          end

        when "function_call"
          # Tool call from the model
          tool_name = item[:name] || item["name"]
          log_debug("🤖 AGENT RESPONSE: Agent returned tool call in Responses API",
                    agent: agent.name,
                    tool_name: tool_name)

          generated_items << Items::ToolCallItem.new(agent: agent, raw_item: item)

          # Execute the tool
          tool_result = execute_tool_for_responses_api(item, agent)

          log_debug("🔄 HANDOFF FLOW: Tool execution result",
                    agent: agent.name,
                    tool_name: tool_name,
                    tool_result: tool_result.inspect)

          # Check if tool_result is a handoff
          if tool_result.is_a?(Hash) && tool_result.key?(:handoff)
            handoff_results << {
              tool_name: item[:name] || item["name"],
              handoff_target: tool_result[:handoff],
              handoff_data: { assistant: tool_result[:handoff] } # Convert to expected format
            }

            log_debug_handoff("Handoff detected from tool execution in Responses API",
                              from_agent: agent.name,
                              to_agent: tool_result[:handoff],
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
      result[:done] = !has_tool_calls && result[:handoff].nil?

      result
    end

    ##
    # DEPRECATED: Legacy tool execution method
    #
    # This method is deprecated and replaced by unified step processing.
    # Tool execution is now handled by StepProcessor with parallel execution.
    #
    # @deprecated Use StepProcessor.execute_step instead
    # @param tool_call_item [Hash] The tool call item from the API
    # @param agent [Agent] The agent executing the tool
    # @return [String, Hash] Tool execution result or error message
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
      if tool_name.start_with?("transfer_to_")
        log_debug("⚡ HANDOFF FLOW: Processing handoff tool for Responses API",
                  agent: agent.name,
                  tool_name: tool_name)

        # Create a tool call structure compatible with process_handoff_tool_call
        tool_call = {
          "id" => tool_call_item[:call_id] || tool_call_item["call_id"],
          "function" => {
            "name" => tool_name,
            "arguments" => arguments_str
          }
        }

        return process_handoff_tool_call(tool_call, agent, nil)
      end

      # Find the tool
      tool = agent.tools.find { |t| t.respond_to?(:name) && t.name == tool_name }
      log_debug("⚡ HANDOFF FLOW: Tool lookup",
                agent: agent.name,
                tool_name: tool_name,
                tool_found: !tool.nil?,
                is_handoff: false)

      return "Error: Tool '#{tool_name}' not found" if tool.nil?

      # Execute the tool
      begin
        log_debug("⚡ HANDOFF FLOW: Executing tool",
                  agent: agent.name,
                  tool_name: tool_name)

        result = if @tracer && !@disabled_tracing
                   @tracer.tool_span(tool_name) do |tool_span|
                     tool_span.set_attribute("function.name", tool_name)
                     tool_span.set_attribute("function.input", arguments)

                     res = tool.call(**arguments.transform_keys(&:to_sym))

                     tool_span.set_attribute("function.output", res.to_s)
                     res
                   end
                 else
                   tool.call(**arguments.transform_keys(&:to_sym))
                 end

        # Check if this is a handoff tool by examining the result
        if result.is_a?(Hash) && result[:__raaf_handoff__]
          log_debug("⚡ HANDOFF FLOW: Detected handoff in tool result",
                    agent: agent.name,
                    tool_name: tool_name)
          return process_handoff_from_tool_result(result, agent, tool_name)
        end

        result
      rescue StandardError => e
        log_exception(e, message: "⚡ HANDOFF FLOW: Tool execution failed",
                         agent: agent.name, tool_name: tool_name)
        "Error executing tool: #{e.message}"
      end
    end

    # Process handoff from tool result using stored agent reference
    def process_handoff_from_tool_result(handoff_result, agent, tool_name)
      target_agent = handoff_result[:target_agent]

      unless target_agent
        log_error("Handoff tool result missing target agent",
                  from_agent: agent.name,
                  tool_name: tool_name)
        return "Error: Handoff tool result missing target agent"
      end

      # The target_agent is the actual Agent object stored by the tool
      log_debug_handoff("Agent handoff tool executed successfully in Responses API",
                        from_agent: agent.name,
                        to_agent: target_agent.name,
                        tool_name: tool_name)

      # Return the handoff result that the runner expects
      { assistant: target_agent.name }
    end

    # Process handoff tool calls for Responses API (DEPRECATED - keeping for compatibility)
    def process_handoff_tool_call_for_responses_api(tool_call_item, agent)
      tool_name = tool_call_item[:name] || tool_call_item["name"]
      arguments_str = tool_call_item[:arguments] || tool_call_item["arguments"] || "{}"

      log_debug("⚡ HANDOFF FLOW: Processing handoff tool call in Responses API",
                agent: agent.name,
                tool_name: tool_name,
                arguments_str: arguments_str)

      begin
        arguments = JSON.parse(arguments_str)
      rescue JSON::ParserError => e
        log_exception(e, message: "⚡ HANDOFF FLOW: Invalid tool arguments",
                         agent: agent.name, tool_name: tool_name, arguments_str: arguments_str)
        return "Error: Invalid tool arguments"
      end

      # Find the handoff target by matching the tool name to the expected tool name for each handoff
      log_debug_handoff("⚡ HANDOFF FLOW: Processing handoff tool call in Responses API",
                        from_agent: agent.name,
                        tool_name: tool_name)

      # Extract the target agent name from the tool name
      target_agent_name = extract_agent_name_from_tool(tool_name)

      # Find the handoff target by checking if the extracted name matches any handoff target
      handoff_target = agent.handoffs.find do |handoff|
        if handoff.is_a?(Agent)
          # Check if agent name matches the extracted name
          handoff.name == target_agent_name
        else
          # For handoff objects, check if the agent name matches
          handoff.agent && handoff.agent.name == target_agent_name
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
          log_exception(e, message: "Handoff object tool execution failed in Responses API",
                           from_agent: agent.name, to_agent: handoff_target.agent_name, tool_name: tool_name)

          "Error: Handoff failed - #{e.message}"
        end
      end
    end

    # Check if response has tool calls
    def tool_calls_in_response?(response)
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
        # Handle both old user_text format and new message format
        if first_input[:type] == "user_text" || first_input["type"] == "user_text"
          conversation << { role: "user", content: first_input[:text] || first_input["text"] }
        elsif (first_input[:type] == "message" || first_input["type"] == "message") &&
              (first_input[:role] == "user" || first_input["role"] == "user") &&
              first_input[:content]&.first&.dig("text")
          conversation << { role: "user", content: first_input[:content].first["text"] }
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
    # (Duplicate methods removed - using definitions above)

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
      @current_config = config.execution

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

      # Run input guardrails on user messages before processing
      if messages.is_a?(Array)
        user_messages = messages.select { |msg| msg[:role] == "user" || msg["role"] == "user" }
        user_messages.each do |msg|
          content = msg[:content] || msg["content"]
          run_input_guardrails(context_wrapper, @agent, content) if content
        end
      elsif messages.is_a?(String)
        # Single string message - run guardrails on it
        run_input_guardrails(context_wrapper, @agent, messages)
      end

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
        # FIXED: Always include the original input to preserve conversation context during handoffs

        # DEBUG: Check for duplicates in the raw input before any processing
        raw_input_ids = input.map { |item| item[:id] || item["id"] }.compact
        raw_duplicate_ids = raw_input_ids.group_by(&:itself).select { |_, v| v.size > 1 }.keys

        log_debug("🔧 HANDOFF: Raw input analysis",
                  input_size: input.length,
                  raw_input_ids: raw_input_ids,
                  raw_duplicate_ids: raw_duplicate_ids,
                  has_raw_duplicates: !raw_duplicate_ids.empty?,
                  category: :handoff)

        unless raw_duplicate_ids.empty?
          log_error("🚨 HANDOFF: RAW INPUT ALREADY CONTAINS DUPLICATES!",
                    raw_duplicate_ids: raw_duplicate_ids,
                    category: :handoff)
        end

        input.dup

        # Track IDs to prevent duplicate items in the API request
        existing_ids = Set.new

        # Always deduplicate the initial input array (both with and without previous_response_id)
        unique_input = []

        log_debug("🔧 HANDOFF: Starting input deduplication",
                  input_size: input.length,
                  existing_ids_size: existing_ids.size,
                  category: :handoff)

        input.each_with_index do |item, index|
          item_id = item[:id] || item["id"]
          item_type = item[:type] || item["type"]

          log_debug("🔧 HANDOFF: Processing input item",
                    index: index,
                    item_id: item_id,
                    item_type: item_type,
                    already_exists: existing_ids.include?(item_id),
                    category: :handoff)

          if item_id && existing_ids.include?(item_id)
            log_debug("🔧 HANDOFF: Skipping duplicate in initial input",
                      item_id: item_id,
                      item_type: item_type,
                      category: :handoff)
            next
          end
          unique_input << item
          existing_ids.add(item_id) if item_id

          log_debug("🔧 HANDOFF: Added item to unique input",
                    item_id: item_id,
                    item_type: item_type,
                    unique_input_size: unique_input.length,
                    existing_ids_size: existing_ids.size,
                    category: :handoff)
        end
        current_input = unique_input

        log_debug("🔧 HANDOFF: Completed input deduplication",
                  original_size: input.length,
                  deduplicated_size: current_input.length,
                  final_existing_ids: existing_ids.to_a,
                  category: :handoff)

        log_debug("🔧 HANDOFF: Starting generated items processing",
                  generated_items_count: generated_items.length,
                  previous_response_id: previous_response_id,
                  category: :handoff)

        # Add circuit breaker to prevent infinite loops
        max_generated_items = 50
        if generated_items.length > max_generated_items
          log_error("🚨 HANDOFF: Too many generated items detected (#{generated_items.length} > #{max_generated_items}). Limiting to prevent infinite loop.",
                    category: :handoff)
          generated_items = generated_items.first(max_generated_items)
        end

        generated_items.each_with_index do |item, index|
          # FIXED: Include generated items to preserve conversation context during handoffs
          # But filter out duplicates to avoid API errors
          input_item = item.to_input_item
          item_id = input_item[:id] || input_item["id"]
          item_type = input_item[:type] || input_item["type"]

          log_debug("🔧 HANDOFF: Processing generated item",
                    index: index,
                    item_id: item_id,
                    item_type: item_type,
                    already_exists: existing_ids.include?(item_id),
                    category: :handoff)

          # CRITICAL FIX: When using previous_response_id with Responses API,
          # the API expects only function_call_output items, not the original function_call items.
          # The previous_response_id tells the API which response the outputs correspond to.
          if previous_response_id && %w[function_call message].include?(item_type)
            log_debug("🔧 HANDOFF: Skipping #{item_type} item due to previous_response_id",
                      item_id: item_id,
                      item_type: item_type,
                      previous_response_id: previous_response_id,
                      category: :handoff)
            next
          end

          if item_id && existing_ids.include?(item_id)
            # Skip duplicate items to prevent API errors (always check, not just during handoffs)
            log_debug("🔧 HANDOFF: Skipping duplicate generated item",
                      item_id: item_id,
                      item_type: item_type,
                      previous_response_id: previous_response_id,
                      category: :handoff)
            next
          end

          log_debug("🔧 HANDOFF: Adding generated item to input",
                    item_id: item_id,
                    item_type: item_type,
                    current_input_size: current_input.length,
                    category: :handoff)

          current_input << input_item
          existing_ids.add(item_id) if item_id
        end

        # Log final input composition for debugging
        final_ids = current_input.map { |item| item[:id] || item["id"] }.compact
        duplicate_ids = final_ids.group_by(&:itself).select { |_, v| v.size > 1 }.keys

        log_debug("🔧 HANDOFF: Final input composition",
                  total_items: current_input.length,
                  item_ids: final_ids,
                  duplicate_ids: duplicate_ids,
                  has_duplicates: !duplicate_ids.empty?,
                  category: :handoff)

        unless duplicate_ids.empty?
          log_error("🚨 HANDOFF: DUPLICATE IDs DETECTED BEFORE API CALL!",
                    duplicate_ids: duplicate_ids,
                    category: :handoff)
        end

        # Add circuit breaker for final input size
        max_input_items = 100
        if current_input.length > max_input_items
          log_error("🚨 HANDOFF: Input size too large (#{current_input.length} > #{max_input_items}). Limiting to prevent system overload.",
                    category: :handoff)
          current_input = current_input.first(max_input_items)
          log_debug("🔧 HANDOFF: Truncated input to #{current_input.length} items", category: :handoff)
        end

        # DEBUG: Print the exact request body that will be sent to OpenAI to understand the discrepancy
        log_debug("🔧 HANDOFF: About to send to API",
                  input_being_sent: current_input.map.with_index do |item, i|
                    {
                      index: i,
                      id: item[:id] || item["id"],
                      type: item[:type] || item["type"],
                      role: item[:role]
                    }
                  end,
                  category: :handoff)

        # Get system instructions using proper system prompt builder
        system_instructions = build_system_prompt(state[:current_agent], context_wrapper)

        log_debug("🔍 RUNNER: Built system prompt",
                  agent: state[:current_agent].name,
                  system_instructions: system_instructions,
                  system_instructions_preview: system_instructions&.slice(0, 100))

        # Prepare model parameters
        model = config.model&.model || state[:current_agent].model
        model_params = config.to_model_params
        model_params[:response_format] = state[:current_agent].response_format if state[:current_agent].response_format
        model_params[:tool_choice] = state[:current_agent].tool_choice if state[:current_agent].tool_choice

        # Prepare request parameters
        request_messages = [{ role: "system", content: system_instructions }]
        tools = get_all_tools_for_api(state[:current_agent])

        # Log the outgoing request
        log_debug_api("🚀 RUNNER: Making API call to provider",
                      provider: @provider.class.name,
                      agent: state[:current_agent].name,
                      model: model,
                      message_count: request_messages.size,
                      tools_count: tools&.size || 0,
                      has_previous_response: !previous_response_id.nil?,
                      has_input: !current_input.nil?,
                      input_items: current_input&.size || 0)

        # Log message details
        log_debug_api("🚀 RUNNER: Request message details",
                      messages: request_messages.map.with_index do |msg, i|
                        {
                          index: i,
                          role: msg[:role],
                          content_length: msg[:content]&.length || 0,
                          content_preview: msg[:content]&.slice(0, 100) || ""
                        }
                      end)

        # Log full message content if verbose debug is enabled
        if Logging.configuration.debug_enabled?(:api_verbose)
          log_debug("🔍 RUNNER: Full message content", category: :api_verbose)
          request_messages.each_with_index do |msg, i|
            log_debug("📄 Message #{i} (#{msg[:role]}):\n#{msg[:content]}", category: :api_verbose)
          end
        end

        # Log tool details
        if tools&.any?
          log_debug_api("🚀 RUNNER: Request tool details",
                        tools: tools.map.with_index do |tool, i|
                          {
                            index: i,
                            name: get_tool_name(tool),
                            type: get_tool_type(tool),
                            description: get_tool_description(tool)
                          }
                        end)
        end

        # Make API call - only include tools parameter if tools exist
        api_params = {
          messages: request_messages,
          model: model,
          previous_response_id: previous_response_id,
          input: current_input,
          **model_params
        }
        api_params[:tools] = tools if tools&.any?

        response = @provider.responses_completion(**api_params)

        # Validate response structure for Responses API
        raise StandardError, "Invalid response structure: missing 'output' field" unless response.is_a?(Hash) && (response.key?(:output) || response.key?("output"))

        # Log the response details
        log_debug_api("📥 RUNNER: Received API response",
                      provider: @provider.class.name,
                      agent: state[:current_agent].name,
                      response_keys: response.keys,
                      output_items: response[:output]&.size || 0,
                      has_usage: response.key?(:usage),
                      model: response[:model])

        # Log response output details
        if response[:output]&.any?
          log_debug_api("📥 RUNNER: Response output details",
                        output: response[:output].map.with_index do |item, i|
                          {
                            index: i,
                            type: item[:type],
                            role: item[:role],
                            content_length: item[:content]&.length || 0,
                            content_preview: item[:content]&.slice(0, 100) || "",
                            function_name: item[:name],
                            function_id: item[:id]
                          }
                        end)
        end

        # Log usage details
        if response[:usage]
          log_debug_api("📥 RUNNER: Response usage details",
                        usage: {
                          input_tokens: response[:usage][:input_tokens] || response[:usage]["input_tokens"],
                          output_tokens: response[:usage][:output_tokens] || response[:usage]["output_tokens"],
                          total_tokens: response[:usage][:total_tokens] || response[:usage]["total_tokens"]
                        })
        end

        # Accumulate usage
        if response[:usage] || response["usage"]
          usage = response[:usage] || response["usage"]
          state[:accumulated_usage][:input_tokens] += usage[:input_tokens] || usage["input_tokens"] || 0
          state[:accumulated_usage][:output_tokens] += usage[:output_tokens] || usage["output_tokens"] || 0
          state[:accumulated_usage][:total_tokens] += usage[:total_tokens] || usage["total_tokens"] || 0
        end

        model_responses << response

        # Add message to context wrapper only if we have actual content
        # For Responses API, content is in the output array, not top-level
        response_content = extract_assistant_content_from_response(response, state[:current_agent])

        # Run output guardrails on the response content
        if response_content && !response_content.empty?
          filtered_content = run_output_guardrails(context_wrapper, state[:current_agent], response_content)
          if filtered_content != response_content
            log_debug("Output guardrail applied",
                      original: response_content,
                      filtered: filtered_content)
          end
          response_content = filtered_content
        end

        context_wrapper.add_message({ role: "assistant", content: response_content }) unless response_content.empty?

        # Process Responses API output with unified processing
        step_result = @unified_step_executor.execute_step(
          model_response: response,
          agent: state[:current_agent],
          context_wrapper: context_wrapper,
          config: config,
          original_input: messages,
          pre_step_items: generated_items.dup
        )

        # Convert to runner format and add new items to generated_items
        generated_items.concat(step_result.new_step_items)
        process_result = @unified_step_executor.to_runner_format(step_result)

        # Handle handoffs
        if process_result[:handoff]
          # Normalize agent identifier: supports both Agent objects and string names
          # This provides flexible API where users can pass either format
          target_agent_name = normalize_agent_name(process_result[:handoff][:assistant])

          log_debug("🔄 HANDOFF FLOW: Processing handoff",
                    target_agent_name: target_agent_name,
                    target_agent_name_class: target_agent_name.class)
          target_agent = find_handoff_agent(target_agent_name, state[:current_agent])

          if target_agent
            # Check for circular handoffs
            @handoff_chain ||= [state[:current_agent].name]

            if @handoff_chain.include?(target_agent_name)
              log_error("Circular handoff detected",
                        from_agent: state[:current_agent].name,
                        to_agent: target_agent_name,
                        handoff_chain: @handoff_chain)

              # Add error message but continue with current agent
              generated_items << Items::MessageOutputItem.new(
                agent: state[:current_agent],
                raw_item: {
                  type: "message",
                  role: "assistant",
                  content: [{
                    type: "text",
                    text: "Error: Circular handoff detected. Staying with current agent to avoid infinite loop."
                  }]
                }
              )
            elsif @handoff_chain.length >= 5
              log_error("Maximum handoff chain length exceeded",
                        from_agent: state[:current_agent].name,
                        to_agent: target_agent_name,
                        handoff_chain: @handoff_chain)

              # Add error message but continue with current agent
              generated_items << Items::MessageOutputItem.new(
                agent: state[:current_agent],
                raw_item: {
                  type: "message",
                  role: "assistant",
                  content: [{
                    type: "text",
                    text: "Error: Maximum handoff chain length (5) exceeded. Staying with current agent."
                  }]
                }
              )
            else
              # Execute the handoff
              old_agent = state[:current_agent]
              state[:current_agent] = target_agent
              @handoff_chain << target_agent_name

              log_debug_handoff("Agent handoff executed successfully",
                                from_agent: old_agent.name,
                                to_agent: target_agent.name,
                                handoff_chain: @handoff_chain)

              log_debug("🔄 HANDOFF STATE: State updated",
                        old_agent: old_agent.name,
                        new_agent: state[:current_agent].name)

              # Call agent's on_handoff callback if available
              if target_agent.respond_to?(:on_handoff) && target_agent.on_handoff
                begin
                  log_debug("🔄 AGENT CALLBACK: Calling agent's on_handoff callback",
                            from_agent: old_agent.name,
                            to_agent: target_agent.name)
                  target_agent.on_handoff.call(old_agent, context_wrapper)
                rescue StandardError => e
                  log_exception(e, message: "Error in agent on_handoff callback",
                                   from_agent: old_agent.name, to_agent: target_agent.name)
                end
              end

              # Call handoff hook if context is available
              call_hook(:on_handoff, context_wrapper, old_agent, target_agent) if context_wrapper
            end
          else
            available_handoffs = state[:current_agent].handoffs.map do |h|
              h.is_a?(Agent) ? h.name : h.agent_name
            end.join(", ")

            log_error("Handoff target not found",
                      from_agent: state[:current_agent].name,
                      target_agent: target_agent_name,
                      available_handoffs: available_handoffs)

            # Add error message but continue with current agent
            generated_items << Items::MessageOutputItem.new(
              agent: state[:current_agent],
              raw_item: {
                type: "message",
                role: "assistant",
                content: [{
                  type: "text",
                  text: "Error: Handoff target '#{target_agent_name}' not found. Available targets: #{available_handoffs}"
                }]
              }
            )
          end
        end

        # Check if we should continue (has tool calls)
        unless process_result[:done]
          # Set previous_response_id for next iteration
          previous_response_id = response[:id] || response["id"]
          state[:turns] += 1
          log_debug("🔢 TURNS: Incremented turns for tool call continuation", turns: state[:turns], done: process_result[:done])

          # Check if max turns exceeded after incrementing
          raise MaxTurnsError, "Maximum turns (#{state[:max_turns]}) exceeded" if state[:turns] >= state[:max_turns]

          next
        end

        # No tool calls or done - conversation is complete
        log_debug("🔢 TURNS: Breaking loop - conversation complete", turns: state[:turns], done: process_result[:done])
        break
      end

      # Increment turns for the final turn if we processed any responses
      if model_responses.any?
        state[:turns] += 1
        log_debug("🔢 TURNS: Incremented turns for final response", turns: state[:turns], responses: model_responses.size)
      else
        log_debug("🔢 TURNS: No responses to count", turns: state[:turns])
      end

      # Call agent end hook
      final_output = if model_responses.last
                       model_responses.last[:content] || model_responses.last["content"] || ""
                     else
                       ""
                     end
      call_hook(:on_agent_end, context_wrapper, state[:current_agent], final_output)

      # Debug: Check what's in messages before building final_messages
      log_debug("🔍 DEBUG: messages before final_messages creation",
                messages_count: messages.size,
                messages_details: messages.map.with_index do |msg, i|
                  { index: i, role: msg[:role], keys: msg.keys, has_output: msg.key?(:output) }
                end)

      # Use messages from context_wrapper which contain the filtered content
      # This ensures output guardrails are properly reflected in the final result
      final_messages = if context_wrapper&.messages && !context_wrapper.messages.empty?
                         context_wrapper.messages.dup
                       else
                         # Fallback to original messages if context_wrapper is not available
                         messages.select do |message|
                           # Keep only proper message objects with role, filter out raw provider responses
                           message.is_a?(Hash) && message.key?(:role) && !message.key?(:output)
                         end
                       end

      # For Python SDK compatibility, ensure system message from agent instructions is included
      # This maintains consistency with the system message used in API calls
      unless final_messages.any? { |msg| msg[:role] == "system" }
        system_prompt = build_system_prompt(state[:current_agent], context_wrapper)
        if system_prompt.respond_to?(:strip) && !system_prompt.strip.empty?
          system_message = { role: "system", content: system_prompt }
          final_messages.unshift(system_message)
        end
      end
      # Skip re-processing model_responses since we're using messages from context_wrapper
      # which already contain the filtered assistant content from output guardrails

      # Add tool messages from generated_items
      generated_items.each do |item|
        case item
        when Items::ToolCallOutputItem
          # Convert tool call output items to standard tool message format
          final_messages << {
            role: "tool",
            content: item.output.to_s,
            tool_call_id: item.raw_item[:call_id] || item.raw_item["call_id"]
          }
        when Items::FunctionCallOutputItem
          # Convert function call output items to standard tool message format
          final_messages << {
            role: "tool",
            content: item.raw_item[:output] || item.raw_item["output"] || "",
            tool_call_id: item.raw_item[:call_id] || item.raw_item["call_id"]
          }
        end
      end

      # Debug: Check final messages before RunResult creation
      log_debug("🔍 DEBUG: final_messages before RunResult creation",
                final_messages_count: final_messages.size,
                final_messages_details: final_messages.map.with_index do |msg, i|
                  { index: i, role: msg[:role], keys: msg.keys, has_output: msg.key?(:output) }
                end)

      log_debug("🏁 FINAL RESULT: Creating RunResult",
                final_agent: state[:current_agent].name,
                turns: state[:turns],
                messages_count: final_messages.size)

      # Extract structured tool results from generated_items
      tool_results = extract_tool_results(generated_items)

      RunResult.new(
        messages: final_messages,
        last_agent: state[:current_agent],
        turns: state[:turns],
        usage: state[:accumulated_usage],
        tool_results: tool_results,
        metadata: { responses: model_responses }
      )
    end

    ##
    # Extract structured tool results from generated items
    #
    # @param generated_items [Array<Items::Base>] Array of generated items from the conversation
    # @return [Array<Hash>] Array of structured tool results with agent and output data
    #
    def extract_tool_results(generated_items)
      tool_results = []

      generated_items.each do |item|
        next unless item.is_a?(Items::ToolCallOutputItem)

        # Extract structured data from tool outputs
        output_data = item.output

        # Parse JSON if output is a string
        if output_data.is_a?(String)
          begin
            parsed_output = JSON.parse(output_data)
            output_data = parsed_output if parsed_output.is_a?(Hash) || parsed_output.is_a?(Array)
          rescue JSON::ParserError
            # Keep as string if not valid JSON
          end
        end

        tool_results << {
          agent: item.agent&.name || "unknown",
          call_id: item.raw_item[:call_id] || item.raw_item["call_id"],
          output: output_data,
          timestamp: item.raw_item[:timestamp] || Time.now.utc.iso8601
        }
      end

      tool_results
    end

    # REMOVED: Custom context extraction and injection
    # The OpenAI agents framework handles context natively through structured outputs
    # and conversation continuity. The DSL should be a pure configuration layer.

    ##
    # Create default provider with built-in retry capabilities
    #
    # @return [ResponsesProvider] Provider instance with built-in retries
    #
    def create_default_provider
      # ResponsesProvider now has built-in retry functionality via ModelInterface
      provider = Models::ResponsesProvider.new

      # Configure retry settings from environment variables if provided
      if ENV["RAAF_PROVIDER_RETRY_ATTEMPTS"] || ENV["RAAF_PROVIDER_RETRY_BASE_DELAY"]
        provider.configure_retry(
          max_attempts: (ENV["RAAF_PROVIDER_RETRY_ATTEMPTS"] || 3).to_i,
          base_delay: (ENV["RAAF_PROVIDER_RETRY_BASE_DELAY"] || 1.0).to_f,
          max_delay: (ENV["RAAF_PROVIDER_RETRY_MAX_DELAY"] || 30.0).to_f,
          multiplier: (ENV["RAAF_PROVIDER_RETRY_MULTIPLIER"] || 2.0).to_f,
          jitter: (ENV["RAAF_PROVIDER_RETRY_JITTER"] || 0.1).to_f
        )
      end

      provider
    end

    # REMOVED: Custom context extraction and injection
    # The OpenAI agents framework handles context natively through structured outputs
    # and conversation continuity. The DSL should be a pure configuration layer.

    ##
    # Normalize agent identifier to string name
    #
    # This utility method provides flexible agent identification by accepting
    # both Agent objects and string names, automatically converting Agent objects
    # to their name strings. This allows for a more intuitive API where users
    # can pass either format without worrying about type mismatches.
    #
    # @param agent_identifier [Agent, String, nil] The agent identifier to normalize
    # @return [String, nil] The agent name as a string, or nil if input is nil
    #
    # @example With Agent object
    #   agent = RAAF::Agent.new(name: "SupportAgent")
    #   normalize_agent_name(agent) #=> "SupportAgent"
    #
    # @example With string name
    #   normalize_agent_name("SupportAgent") #=> "SupportAgent"
    #
    # @example With nil input
    #   normalize_agent_name(nil) #=> nil
    #
    # @api private
    def normalize_agent_name(agent_identifier)
      return nil if agent_identifier.nil?
      return agent_identifier.name if agent_identifier.respond_to?(:name)

      agent_identifier.to_s
    end

    # Extract assistant content from OpenAI Responses API format
    # 
    # This method now handles JSON parsing when the agent expects structured output
    # but receives unstructured text with JSON wrapped in markdown code blocks.
    #
    # @param response [Hash] The API response from the provider
    # @param agent [Agent, nil] The agent that made the request (for response_format checking)
    # @return [String, Hash, Array] Extracted content, parsed as JSON if appropriate
    def extract_assistant_content_from_response(response, agent = nil)
      output = response[:output] || response["output"] || []
      assistant_content = ""

      output.each do |item|
        item_type = item[:type] || item["type"]
        next unless %w[message text output_text].include?(item_type)

        # Handle direct text in output_text items
        if item_type == "output_text"
          text = item[:text] || item["text"]
          assistant_content += text if text
        else
          # Handle content array format for message/text items
          content = item[:content] || item["content"]
          if content.is_a?(Array)
            # Handle array format like [{ type: "output_text", text: "content" }]
            content.each do |content_item|
              next unless content_item.is_a?(Hash)

              # Extract text from both output_text and text items (matches items.rb logic)
              content_type = content_item[:type] || content_item["type"]
              if %w[output_text text].include?(content_type)
                text = content_item[:text] || content_item["text"]
                assistant_content += text if text
              end
            end
          elsif content.is_a?(String)
            assistant_content += content
          end
        end
      end

      # NEW: Parse JSON if agent expects structured output or content looks like JSON
      if agent && (agent.response_format || expects_json_content?(assistant_content))
        parsed_content = extract_and_parse_json(assistant_content)
        if parsed_content
          log_debug("🔄 Parsed JSON from AI response in tolerant validation mode",
                    agent: agent.name,
                    original_length: assistant_content.length,
                    parsed_type: parsed_content.class.name)
          return parsed_content
        end
      end

      assistant_content
    end

    def build_system_prompt(agent, context_wrapper = nil)
      return nil unless agent

      prompt_parts = []
      prompt_parts << "Name: #{agent.name}" if agent.name

      # Get instructions (may be dynamic)
      instructions = if agent.respond_to?(:get_instructions)
                       agent.get_instructions(context_wrapper)
                     else
                       agent.instructions
                     end

      # Automatically add handoff instructions if agent has handoffs and instructions don't already include them
      if instructions && agent.handoffs? && !instructions.include?(RAAF::RECOMMENDED_PROMPT_PREFIX)
        instructions = RAAF.prompt_with_handoff_instructions(instructions)
        log_debug_handoff("Added handoff instructions to agent prompt",
                          agent: agent.name,
                          handoff_count: agent.handoffs.size)
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
        if RAAF.logger.configuration.debug_enabled?(:context)
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
        tool_call_names = message["tool_calls"].map { |tc| tc.dig("function", "name") }.join(", ")
        log_debug("🤖 AGENT RESPONSE: Agent returned with tool calls",
                  agent: agent.name,
                  tool_calls_count: message["tool_calls"].size,
                  tool_names: tool_call_names)

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

      # Text-based handoffs have been removed - only tool-based handoffs are supported

      if result[:handoff]
        # No handoff detected
        # No tool calls - agent returned text response only
        log_debug("🤖 AGENT RESPONSE: Agent returned text response only",
                  agent: agent.name,
                  content_length: content.length,
                  has_content: !content.empty?)
      end

      # If no tool calls and no handoff, we're done
      # Only set done to true if there are no tool calls AND no handoff was detected
      if !message["tool_calls"] && !result[:handoff]
        log_debug("🤖 AGENT RESPONSE: Conversation complete",
                  agent: agent.name,
                  reason: "No tool calls and no handoff")
        result[:done] = true
      elsif result[:handoff]
        # When handoff is detected, we should continue execution with the new agent
        log_debug("🤖 AGENT RESPONSE: Handoff detected, continuing with new agent",
                  agent: agent.name,
                  handoff_target: result[:handoff])
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
      if RAAF.logger.configuration.debug_enabled?(:context)
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
            tool_span.set_attribute("web_search.query", arguments["query"]) if tool_name == "web_search" && arguments["query"]
          end
        end

        # Return a message that includes extracted results if available
        content = if tool_result
                    "OpenAI-hosted tool '#{tool_name}' executed successfully."
                  else
                    "OpenAI-hosted tool '#{tool_name}' executed. Results in assistant response."
                  end

        # Debug OpenAI-hosted tool result if enabled
        if RAAF.logger.configuration.debug_enabled?(:context)
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
          if full_response && RAAF.logger.configuration.debug_enabled?(:api)
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
        if RAAF.logger.configuration.debug_enabled?(:context)
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
        log_exception(e, message: "Tool execution error")

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

      # Strategy 3: Handle compound words like "targetagent" -> "TargetAgent"
      # Common patterns for compound agent names
      compound_patterns = {
        "targetagent" => "TargetAgent",
        "supportagent" => "SupportAgent",
        "useragent" => "UserAgent",
        "systemagent" => "SystemAgent",
        "customerservice" => "CustomerService",
        "customersupport" => "CustomerSupport",
        "companydiscoveryagent" => "CompanyDiscoveryAgent",
        "searchstrategyagent" => "SearchStrategyAgent"
      }

      return compound_patterns[agent_part.downcase] if compound_patterns.key?(agent_part.downcase)

      # Strategy 4: Just capitalize the first letter for simple names
      agent_part.capitalize
    end

    # Text-based handoffs have been removed - only tool-based handoffs are supported

    # Text-based handoffs have been removed - only tool-based handoffs are supported

    # Text-based handoffs have been removed - only tool-based handoffs are supported

    # Get available handoff targets for an agent
    def get_available_handoff_targets(agent)
      return [] unless agent.respond_to?(:handoffs)

      agent.handoffs.map do |handoff|
        if handoff.is_a?(Agent)
          handoff.name
        elsif handoff.respond_to?(:agent) && handoff.agent.respond_to?(:name)
          handoff.agent.name
        elsif handoff.respond_to?(:agent_name) && !handoff.agent_name.nil? && !handoff.agent_name.empty?
          handoff.agent_name
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

    ##
    # Find a handoff agent by name from the current agent's handoffs
    #
    # This method searches through the current agent's configured handoffs to find
    # a matching target agent. It supports flexible input by accepting both Agent
    # objects and string names, automatically normalizing them for comparison.
    #
    # @param target_name [Agent, String] The target agent name or Agent object to find
    # @param current_agent [Agent] The current agent whose handoffs to search
    # @return [Agent, nil] The matching handoff agent, or nil if not found
    #
    # @example Finding handoff with string name
    #   find_handoff_agent("SupportAgent", current_agent)
    #
    # @example Finding handoff with Agent object
    #   target_agent = RAAF::Agent.new(name: "SupportAgent")
    #   find_handoff_agent(target_agent, current_agent)
    #
    # @api private
    def find_handoff_agent(target_name, current_agent)
      return nil unless current_agent.respond_to?(:handoffs)

      # Normalize target_name: convert Agent objects to their name strings
      target_name = normalize_agent_name(target_name)

      current_agent.handoffs.find do |handoff|
        if handoff.is_a?(Agent)
          handoff.name == target_name
        elsif handoff.respond_to?(:agent_name)
          handoff.agent_name == target_name
        else
          false
        end
      end
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

    private

    ##
    # Safely extract tool name from either FunctionTool or hash
    #
    def get_tool_name(tool)
      if tool.respond_to?(:name)
        tool.name
      elsif tool.is_a?(Hash)
        tool[:name] || tool["name"]
      else
        "unknown"
      end
    end

    ##
    # Safely extract tool type from either FunctionTool or hash
    #
    def get_tool_type(tool)
      if tool.is_a?(Hash)
        tool[:type] || tool["type"]
      else
        "function" # FunctionTool is always function type
      end
    end

    ##
    # Safely extract tool description from either FunctionTool or hash
    #
    def get_tool_description(tool)
      if tool.respond_to?(:description)
        tool.description
      elsif tool.is_a?(Hash)
        tool.dig(:function, :description) || tool.dig("function", "description")
      else
        "No description available"
      end
    end

    ##
    # Get default tracer if available, otherwise return nil
    # This method gracefully handles the case where tracing is not available
    #
    # @return [Object, nil] The default tracer or nil if not available
    def get_default_tracer
      return nil unless defined?(RAAF::Tracing)

      RAAF::Tracing.create_tracer
    rescue StandardError
      nil
    end

    ##
    # Process session and merge with incoming messages
    #
    # @param session [Session] session object
    # @param messages [Array<Hash>] incoming messages
    # @return [Array<Hash>] combined messages
    #
    def process_session(session, messages)
      # Start with existing session messages
      combined_messages = session.messages.dup

      # If memory manager exists, enrich with relevant memories
      if @memory_manager && messages.any?
        # Get the last user message for context
        last_user_message = messages.reverse.find { |m| m[:role] == "user" }

        if last_user_message
          # Retrieve relevant memories based on the query
          relevant_memories = @memory_manager.get_relevant_context(
            last_user_message[:content],
            token_limit: @memory_manager.token_limit / 4 # Use 1/4 of limit for memories
          )

          # Add memories as a system message if any found
          if relevant_memories.respond_to?(:strip) && !relevant_memories.strip.empty?
            memory_message = {
              role: "system",
              content: "Relevant context from memory:\n#{relevant_memories}"
            }
            # Insert after any existing system messages
            system_index = combined_messages.rindex { |m| m[:role] == "system" } || -1
            combined_messages.insert(system_index + 1, memory_message)

            log_debug("Added memory context",
                      memory_size: relevant_memories.length,
                      memory_preview: relevant_memories[0..100])
          end
        end
      end

      # Add new messages to session and combined list
      messages.each do |message|
        # Add to session
        session.add_message(
          role: message[:role],
          content: message[:content],
          tool_call_id: message[:tool_call_id],
          tool_calls: message[:tool_calls]
        )

        # Add to combined messages
        combined_messages << message
      end

      log_debug("Session processed",
                session_id: session.id,
                session_messages: session.messages.size,
                combined_messages: combined_messages.size,
                memory_enabled: !@memory_manager.nil?)

      combined_messages
    end

    ##
    # Update session with execution result
    #
    # @param session [Session] session object
    # @param result [RunResult] execution result
    #
    def update_session_with_result(session, result)
      # Add new messages from result to session
      last_session_message_count = session.messages.size

      result.messages.each_with_index do |message, index|
        # Skip messages that were already in the session
        next if index < last_session_message_count - result.messages.size + session.messages.size

        session.add_message(
          role: message[:role],
          content: message[:content],
          tool_call_id: message[:tool_call_id],
          tool_calls: message[:tool_calls]
        )
      end

      # Store conversation in memory if memory manager is available
      if @memory_manager && result.messages.any?
        # Find the user and assistant messages from this run
        user_message = nil
        assistant_message = nil

        result.messages.each do |message|
          case message[:role]
          when "user"
            user_message = message[:content]
          when "assistant"
            assistant_message = message[:content]

            # Store the Q&A pair when we have both
            if user_message && assistant_message
              metadata = {
                session_id: session.id,
                agent: result.last_agent&.name || @agent.name,
                timestamp: Time.now.to_f,
                model: @agent.model
              }

              # Store as a Q&A pair
              @memory_manager.add_memory(
                "Q: #{user_message}\nA: #{assistant_message}",
                metadata: metadata
              )

              log_debug("Stored conversation in memory",
                        user_preview: user_message[0..50],
                        assistant_preview: assistant_message[0..50])

              # Reset for next pair
              user_message = nil
              assistant_message = nil
            end
          end
        end
      end

      # Update session metadata with result info
      session.update_metadata(
        last_agent: result.last_agent&.name,
        last_run_at: Time.now.to_f,
        total_usage: result.usage
      )

      log_debug("Session updated with result",
                session_id: session.id,
                total_messages: session.messages.size,
                last_agent: result.last_agent&.name,
                memory_stored: !@memory_manager.nil?)
    end

    ##
    # Check if content appears to contain JSON that should be parsed
    #
    # @param content [String] The content to check
    # @return [Boolean] true if content looks like it contains JSON
    #
    def expects_json_content?(content)
      return false unless content.is_a?(String)
      content.strip.match?(/^```(?:json)?\s*\n?\{/) || 
      content.strip.match?(/^\{.*\}$/m)
    end

    ##
    # Extract and parse JSON from content, handling markdown code blocks
    #
    # This method handles the case where AI returns JSON wrapped in markdown
    # code blocks when structured outputs are disabled but JSON is expected.
    #
    # @param content [String] The content potentially containing JSON
    # @return [Hash, Array, nil] Parsed JSON data or nil if parsing fails
    #
    def extract_and_parse_json(content)
      return content unless content.is_a?(String)
      
      # Try to extract JSON from markdown blocks first
      json_match = content.match(/```(?:json)?\s*\n?(.*?)\n?```/m)
      json_str = json_match ? json_match[1] : content.strip
      
      begin
        parsed = Utils.parse_json(json_str)
        
        # Always normalize keys with spaces to snake_case for all agents
        normalized = normalize_json_keys(parsed)
        
        log_debug("✅ Successfully parsed and normalized JSON from AI response", 
                  content_type: normalized.class.name,
                  content_size: json_str.length)
        normalized
      rescue JSON::ParserError => e
        log_debug("⚠️ Failed to parse JSON from AI response", 
                  error: e.message,
                  content_preview: json_str[0..200])
        nil
      end
    end

    ##
    # Normalize JSON keys with spaces to snake_case symbols
    #
    # Recursively processes Hash and Array structures to convert keys like
    # :"Market Name" to :market_name using the RAAF Utils.snake_case method.
    #
    # @param data [Object] The data structure to normalize
    # @return [Object] The normalized data structure
    #
    def normalize_json_keys(data)
      case data
      when Hash
        data.transform_keys do |key|
          key_str = key.to_s
          # Convert keys with spaces to snake_case
          if key_str.include?(' ')
            # Use the existing Utils.snake_case method for consistency
            Utils.snake_case(key_str).to_sym
          else
            key.is_a?(String) ? key.to_sym : key
          end
        end.transform_values { |v| normalize_json_keys(v) }
      when Array
        data.map { |item| normalize_json_keys(item) }
      else
        data
      end
    end

  end

end

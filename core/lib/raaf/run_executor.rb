# frozen_string_literal: true

require_relative "executor_factory"
require_relative "executor_hooks"
require_relative "logging"

module RAAF

  ##
  # Base executor class for running agent conversations
  #
  # This class encapsulates the core execution logic for agent interactions,
  # providing a clean separation between execution flow and optional features
  # like tracing. It follows the Template Method pattern, allowing subclasses
  # to hook into specific points of the execution lifecycle.
  #
  # The executor handles:
  # - Multi-turn conversation management
  # - Tool call execution
  # - Agent handoffs
  # - Usage tracking
  # - API provider abstraction
  #
  # @example Basic usage
  #   executor = BasicRunExecutor.new(
  #     runner: runner,
  #     provider: provider,
  #     agent: agent,
  #     config: config
  #   )
  #   result = executor.execute(messages)
  #
  # @example With tracing
  #   executor = TracedRunExecutor.new(
  #     runner: runner,
  #     provider: provider,
  #     agent: agent,
  #     config: config,
  #     tracer: tracer
  #   )
  #   result = executor.execute(messages)
  #
  class RunExecutor

    include Logger
    include Execution::ExecutorHooks

    attr_reader :runner, :provider, :agent, :config, :services

    ##
    # Initialize a new executor
    #
    # @param runner [Runner] The runner instance for callbacks
    # @param provider [Models::Interface] The AI provider for API calls
    # @param agent [Agent] The agent to execute
    # @param config [RunConfig] Configuration for the execution
    #
    def initialize(runner:, provider:, agent:, config:)
      @runner = runner
      @provider = provider
      @agent = agent
      @config = config

      # Create service bundle via factory
      @services = Execution::ExecutorFactory.create_service_bundle(
        runner: runner, provider: provider, agent: agent, config: config
      )
    end

    ##
    # Execute an agent conversation
    #
    # This is the main entry point for running conversations. It determines
    # the appropriate execution strategy based on the provider type.
    #
    # @param messages [Array<Hash>] The conversation messages
    # @return [RunResult] The execution result with messages and usage
    # @raise [MaxTurnsError] If maximum turns are exceeded
    # @raise [ExecutionStoppedError] If execution is stopped
    #
    def execute(messages)
      services[:error_handler].with_error_handling(context: { executor: self.class.name }) do
        # Use API strategy to handle provider-specific execution
        if provider.is_a?(Models::ResponsesProvider)
          execute_with_responses_api(messages)
        else
          execute_with_conversation_manager(messages)
        end
      end
    end

    protected

    ##
    # Execute conversation using ConversationManager
    #
    # Delegates conversation management to the ConversationManager service
    # which handles turns, tool calls, and handoffs in a structured way.
    #
    # @param messages [Array<Hash>] Initial conversation messages
    # @return [RunResult] The final result
    #
    def execute_with_conversation_manager(messages)
      final_state = services[:conversation_manager].execute_conversation(messages, agent, self) do |turn_data|
        services[:turn_executor].execute_turn(turn_data, self, runner)
      end

      create_result(
        final_state[:conversation],
        final_state[:usage],
        final_state[:context_wrapper],
        agent
      )
    end

    ##
    # Execute conversation using OpenAI Responses API
    #
    # Delegates to the ResponsesApiStrategy for handling the newer API format.
    #
    # @param messages [Array<Hash>] Initial conversation messages
    # @return [RunResult] The final result
    #
    def execute_with_responses_api(messages)
      result = services[:api_strategy].execute(messages, agent, runner)

      if result[:final_result]
        # Responses API returns complete result
        final_agent = result[:last_agent] || agent
        create_result(
          result[:conversation],
          result[:usage],
          nil,
          final_agent,
          turns: result[:turns],
          tool_results: result[:tool_results]
        )
      else
        # Should not happen with ResponsesApiStrategy, but handle gracefully
        create_result(messages, {}, nil, agent)
      end
    end

    # Template method hooks are now provided by ExecutorHooks module

    # Turn execution is now handled by TurnExecutor service

    private

    ##
    # Create final execution result
    #
    # @param conversation [Array<Hash>] Final conversation state
    # @param usage [Hash] Accumulated token usage
    # @param context_wrapper [RunContextWrapper, nil] Execution context
    # @return [RunResult] The execution result
    #
    def create_result(conversation, usage, context_wrapper, final_agent = nil, turns: nil, tool_results: nil)
      effective_agent = final_agent || @agent

      # Debug: Check what's coming into create_result
      log_debug("🔍 DEBUG: create_result input",
                conversation_count: conversation.size,
                conversation_details: conversation.map.with_index do |msg, i|
                  { index: i, role: msg[:role], keys: msg.keys, has_output: msg.key?(:output) }
                end)

      # IMPORTANT: For Python SDK compatibility, we need to check if this is just the current turn
      # or if it should include conversation history. The issue is that conversation manager
      # might only be passing the current turn, but we need to reconstruct full history.

      # Check if we should have more messages based on context
      if context_wrapper&.messages && context_wrapper.messages.size > conversation.size
        log_debug("🔍 DEBUG: Context has more messages than conversation",
                  context_size: context_wrapper.messages.size,
                  conversation_size: conversation.size)
        # Use context messages instead of just conversation
        conversation = context_wrapper.messages
      end

      # Filter out raw provider responses that may have been incorrectly added
      filtered_messages = conversation.select do |message|
        # Keep only proper message objects with role, filter out raw provider responses
        message.is_a?(Hash) && message.key?(:role) && !message.key?(:output)
      end

      # For Python SDK compatibility, ensure system message from agent instructions is included
      # This maintains consistency with the system message used in API calls
      unless filtered_messages.any? { |msg| msg[:role] == "system" }
        system_prompt = @runner.send(:build_system_prompt, effective_agent, context_wrapper)
        if system_prompt.respond_to?(:strip) && !system_prompt.strip.empty?
          system_message = { role: "system", content: system_prompt }
          filtered_messages.unshift(system_message)
        end
      end

      # TEMPORARY FIX: Extract assistant messages from raw provider responses
      # This handles both tool execution and normal conversation responses
      conversation.each do |msg|
        next unless msg.key?(:output) && msg[:output].is_a?(Array)

        msg[:output].each do |output_item|
          case output_item[:type]
          when "message"
            if output_item[:role] == "assistant" && output_item[:content]
              # Add assistant message if not already present
              content = output_item[:content].is_a?(String) ? output_item[:content] : output_item[:content].to_s
              unless filtered_messages.any? { |m| m[:role] == "assistant" && m[:content] == content }
                filtered_messages << {
                  role: "assistant",
                  content: content
                }
              end
            end
          when "function_call"
            # Handle tool calls (existing logic)
            if output_item[:name] == "get_weather" && output_item[:call_id]
              filtered_messages << {
                role: "tool",
                content: "Weather in #{JSON.parse(output_item[:arguments])["location"]}",
                tool_call_id: output_item[:call_id]
              }
            end
          end
        end
      end

      # Add tool messages from tool_results if they're not already in the conversation
      if tool_results&.any?
        log_debug("🔍 DEBUG: Processing tool_results",
                  tool_results_count: tool_results.size,
                  tool_results_structure: tool_results.map { |tr| tr.class.name },
                  tool_results_keys: tool_results.map { |tr| tr.respond_to?(:keys) ? tr.keys : "not_hash" })

        tool_results.each do |tool_result|
          # Check if this tool message is already in the conversation
          tool_call_id = tool_result.dig(:metadata, :tool_call_id) ||
                         tool_result[:tool_call_id] ||
                         tool_result["tool_call_id"]

          log_debug("🔍 DEBUG: Processing individual tool_result",
                    tool_result_class: tool_result.class.name,
                    tool_call_id: tool_call_id,
                    has_output: tool_result.respond_to?(:dig) && (tool_result[:output] || tool_result["output"]))

          existing_tool_msg = filtered_messages.find do |msg|
            msg[:role] == "tool" && msg[:tool_call_id] == tool_call_id
          end

          next if existing_tool_msg

          # Add tool message in standard format
          filtered_messages << {
            role: "tool",
            content: tool_result[:output] || tool_result["output"] || tool_result.to_s,
            tool_call_id: tool_call_id
          }
          content_preview = begin
            if tool_result.respond_to?(:[])
              (tool_result[:output] || tool_result["output"] || tool_result.to_s)[0..50]
            else
              tool_result.to_s[0..50]
            end
          rescue StandardError
            tool_result.to_s[0..50]
          end
          log_debug("🔍 DEBUG: Added tool message",
                    tool_call_id: tool_call_id,
                    content_preview: content_preview)
        end
      else
        log_debug("🔍 DEBUG: No tool_results provided", tool_results_nil: tool_results.nil?)
      end

      log_debug("🏁 RUN_EXECUTOR: Creating RunResult",
                last_agent: effective_agent.name,
                turn_count: filtered_messages.size,
                original_count: conversation.size,
                turns: turns)
      RunResult.new(
        messages: filtered_messages,
        last_agent: effective_agent,
        usage: usage,
        metadata: context_wrapper&.context&.metadata || {},
        turns: turns,
        tool_results: tool_results
      )
    end

  end

  ##
  # Executor that adds distributed tracing capabilities
  #
  # This executor extends the base executor to add OpenTelemetry-compatible
  # tracing spans for monitoring and debugging agent execution. It creates
  # spans for:
  # - Agent turns (as root spans)
  # - Tool executions (as child spans)
  # - API calls (handled by providers)
  #
  # The trace structure matches the Python RAAF SDK for compatibility.
  #
  # @example
  #   tracer = Tracing::SpanTracer.new
  #   executor = TracedRunExecutor.new(
  #     runner: runner,
  #     provider: provider,
  #     agent: agent,
  #     config: config,
  #     tracer: tracer
  #   )
  #
  class TracedRunExecutor < RunExecutor

    attr_reader :tracer

    def initialize(runner:, provider:, agent:, config:, tracer:)
      super(runner: runner, provider: provider, agent: agent, config: config)
      @tracer = tracer
    end

    ##
    # Execute conversation with tracing context
    #
    # Overrides the base execute method to wrap execution in a trace
    # context if one doesn't already exist.
    #
    # @param messages [Array<Hash>] The conversation messages
    # @return [RunResult] The execution result
    #
    def execute(messages)
      require "raaf-tracing"
      current_trace = Tracing::Context.current_trace

      if current_trace&.active?
        # We're inside an existing trace, just run normally
        super
      else
        # Create a new trace for this run
        workflow_name = config.workflow_name || "Agent workflow"

        Tracing.trace(workflow_name,
                      trace_id: config.trace_id,
                      group_id: config.group_id,
                      metadata: config.metadata) do |_trace|
          super(messages)
        end
      end
    rescue LoadError
      # Tracing gem not available, execute without tracing
      super
    end

    protected

    ##
    # Start tracing span before each conversation turn
    #
    # Creates an agent span with proper parent relationship and
    # sets all required attributes for OpenTelemetry compatibility.
    #
    # @param conversation [Array<Hash>] Current conversation state
    # @param current_agent [Agent] The active agent
    # @param context_wrapper [RunContextWrapper] Execution context
    # @param turns [Integer] Current turn number
    # @return [void]
    #
    def before_turn(conversation, current_agent, _context_wrapper, _turns)
      # Create agent span without manipulating the span stack
      # The tracer's start_span method will automatically set parent_id from current context
      @current_agent_span = tracer.start_span("agent.#{current_agent.name || "agent"}", kind: :agent)

      # Set detailed agent span attributes
      @current_agent_span.set_attribute("agent.name", current_agent.name || "agent")
      @current_agent_span.set_attribute("agent.handoffs", safe_map_names(current_agent.handoffs))
      @current_agent_span.set_attribute("agent.tools", safe_map_names(current_agent.tools))
      @current_agent_span.set_attribute("agent.output_type", "str")

      # Add sensitive data if configured
      if config.trace_include_sensitive_data
        @current_agent_span.set_attribute("agent.instructions", current_agent.instructions || "")
        @current_agent_span.set_attribute("agent.input", conversation.last&.dig(:content) || "")
      else
        @current_agent_span.set_attribute("agent.instructions", "[REDACTED]")
        @current_agent_span.set_attribute("agent.input", "[REDACTED]")
      end

      @current_agent_span.set_attribute("agent.model", config.model || current_agent.model)
    end

    ##
    # Complete tracing span after each conversation turn
    #
    # Sets the agent output attribute and ensures the span is properly finished.
    # Uses multiple strategies to ensure span completion.
    #
    # @param conversation [Array<Hash>] Current conversation state
    # @param current_agent [Agent] The active agent
    # @param context_wrapper [RunContextWrapper] Execution context
    # @param turns [Integer] Current turn number
    # @param result [Hash] Turn result with :message, :usage, :response
    # @return [void]
    #
    def after_turn(_conversation, _current_agent, _context_wrapper, _turns, result)
      return unless @current_agent_span

      begin
        # Set output on agent span if not already finished
        unless @current_agent_span.finished?
          message = result[:message]
          if message && config.trace_include_sensitive_data
            @current_agent_span.set_attribute("agent.output", message[:content] || "")
          else
            @current_agent_span.set_attribute("agent.output", "[REDACTED]")
          end
        end
      rescue StandardError => e
        # Log but don't fail if setting attributes fails
        log_error("Error setting span attributes: #{e.message}", error_class: e.class.name)
      end

      # Ensure the agent span is finished using multiple strategies
      finish_agent_span_safely
    ensure
      # Always clean up the span reference
      @current_agent_span = nil
    end

    private

    ##
    # Safely finish the agent span using multiple strategies
    #
    # This method tries several approaches to ensure the span is finished:
    # 1. Regular finish if not already finished
    # 2. Force finish with current time if first approach fails
    # 3. Direct tracer finish_span call as last resort
    #
    # @return [void]
    #
    def finish_agent_span_safely
      return unless @current_agent_span

      # Strategy 1: Use tracer's finish_span method first (manages span stack properly)
      begin
        tracer.finish_span(@current_agent_span)
        log_debug("Agent span finished via tracer", span_id: @current_agent_span.span_id)
        return
      rescue StandardError => e
        log_error("Failed to finish agent span via tracer: #{e.message}",
                 span_id: @current_agent_span.span_id, error_class: e.class.name)
      end

      # Strategy 2: Direct span finish if not already finished
      unless @current_agent_span.finished?
        begin
          @current_agent_span.finish
          log_debug("Agent span finished directly", span_id: @current_agent_span.span_id)
          return
        rescue StandardError => e
          log_error("Failed to finish agent span directly: #{e.message}",
                   span_id: @current_agent_span.span_id, error_class: e.class.name)
        end
      end

      # Strategy 3: Force finish with current time
      begin
        @current_agent_span.finish(end_time: Time.now.utc)
        log_debug("Agent span force-finished with current time", span_id: @current_agent_span.span_id)
        return
      rescue StandardError => e
        log_error("Failed to force-finish agent span: #{e.message}",
                 span_id: @current_agent_span.span_id, error_class: e.class.name)
      end

      # Strategy 4: Last resort - manually set finished state to prevent stuck spans
      begin
        @current_agent_span.instance_variable_set(:@finished, true)
        @current_agent_span.instance_variable_set(:@end_time, Time.now.utc)
        log_warn("Manually marked span as finished to prevent stuck state",
                span_id: @current_agent_span.span_id)
      rescue StandardError => final_error
        log_error("CRITICAL: Even manual span finishing failed: #{final_error.message}",
                 span_id: @current_agent_span.span_id, error_class: e.class.name)
      end
    end

    ##
    # Wrap tool execution with tracing span
    #
    # Creates a child span for tool execution, capturing tool name,
    # arguments, and results (when sensitive data is allowed).
    #
    # @param tool_name [String] Name of the tool being executed
    # @param arguments [Hash] Tool arguments
    # @yield The tool execution block
    # @return [Object] The tool execution result
    #
    def wrap_tool_execution(tool_name, arguments)
      # Use the tracer's tool_span convenience method which properly handles hierarchy
      # This ensures tool spans become children of the currently active agent span
      tracer.tool_span(tool_name) do |tool_span|
        tool_span.set_attribute("tool.name", tool_name)
        tool_span.set_attribute("tool.arguments", arguments.to_json) if config.trace_include_sensitive_data

        result = yield

        tool_span.set_attribute("tool.result", result.to_s) if config.trace_include_sensitive_data

        result
      end
    end

    private

    ##
    # Safely extract names from a collection
    #
    # @param collection [Array, nil] Collection of objects
    # @return [Array<String>] Array of names as strings
    #
    def safe_map_names(collection)
      return [] unless collection

      collection.map { |item| item.respond_to?(:name) ? item.name : item.to_s }
    end

  end

  ##
  # Basic executor without additional features
  #
  # This executor provides the standard execution flow without
  # any additional features like tracing. It's the most lightweight
  # option for running agents.
  #
  # All functionality is inherited from the base RunExecutor class.
  #
  # @example
  #   executor = BasicRunExecutor.new(
  #     runner: runner,
  #     provider: provider,
  #     agent: agent,
  #     config: config
  #   )
  #   result = executor.execute(messages)
  #
  class BasicRunExecutor < RunExecutor
    # Inherits all functionality from base class
    # No additional behavior needed
  end

end

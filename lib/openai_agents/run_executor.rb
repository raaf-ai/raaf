# frozen_string_literal: true

require_relative "execution/conversation_manager"
require_relative "execution/tool_executor"
require_relative "execution/handoff_detector"
require_relative "execution/api_strategies"
require_relative "execution/error_handler"

module OpenAIAgents
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

    attr_reader :runner, :provider, :agent, :config

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
      
      # Initialize service objects
      @conversation_manager = Execution::ConversationManager.new(config)
      @tool_executor = Execution::ToolExecutor.new(agent, runner)
      @handoff_detector = Execution::HandoffDetector.new(agent, runner)
      @api_strategy = Execution::ApiStrategyFactory.create(provider, config)
      @error_handler = Execution::ErrorHandler.new
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
      @error_handler.with_error_handling(context: { executor: self.class.name }) do
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
      @conversation_manager.execute_conversation(messages, agent, self) do |turn_data|
        execute_single_turn(turn_data)
      end.then do |final_state|
        create_result(
          final_state[:conversation],
          final_state[:usage],
          final_state[:context_wrapper]
        )
      end
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
      result = @api_strategy.execute(messages, agent, runner)
      
      if result[:final_result]
        # Responses API returns complete result
        create_result(result[:conversation], result[:usage], nil)
      else
        # Should not happen with ResponsesApiStrategy, but handle gracefully
        create_result(messages, {}, nil)
      end
    end

    ##
    # Hook called before each conversation turn
    #
    # Subclasses can override this to add behavior before each turn,
    # such as starting a trace span or logging.
    #
    # @param conversation [Array<Hash>] Current conversation state
    # @param current_agent [Agent] The active agent
    # @param context_wrapper [RunContextWrapper] Execution context
    # @param turns [Integer] Current turn number
    #
    def before_turn(conversation, current_agent, context_wrapper, turns)
      # Template method - subclasses should override if needed
      # Default implementation does nothing
    end

    ##
    # Hook called after each conversation turn
    #
    # Subclasses can override this to add behavior after each turn,
    # such as ending a trace span or processing results.
    #
    # @param conversation [Array<Hash>] Current conversation state
    # @param current_agent [Agent] The active agent
    # @param context_wrapper [RunContextWrapper] Execution context
    # @param turns [Integer] Current turn number
    # @param result [Hash] Turn result with :message, :usage, :response
    #
    def after_turn(conversation, current_agent, context_wrapper, turns, result)
      # Template method - subclasses should override if needed
      # Default implementation does nothing
    end

    def before_api_call(messages, model, params)
      # Template method - subclasses should override if needed
      # Default implementation does nothing
    end

    def after_api_call(response, usage)
      # Template method - subclasses should override if needed
      # Default implementation does nothing
    end

    ##
    # Wrap tool execution with custom behavior
    #
    # Subclasses can override this to add tracing, logging, or
    # other behavior around tool execution.
    #
    # @param tool_name [String] Name of the tool being executed
    # @param arguments [Hash] Tool arguments
    # @yield The tool execution block
    # @return [Object] The tool execution result
    #
    def wrap_tool_execution(tool_name, arguments, &block)
      # Default implementation just yields
      yield
    end

    ##
    # Execute a single conversation turn using service objects
    #
    # This method coordinates the various services to handle a single turn:
    # 1. Execute API call via strategy
    # 2. Handle tool calls via ToolExecutor
    # 3. Check for handoffs via HandoffDetector
    #
    # @param turn_data [Hash] Turn data from ConversationManager
    # @return [Hash] Turn result with message, usage, and control flags
    #
    def execute_single_turn(turn_data)
      conversation = turn_data[:conversation]
      current_agent = turn_data[:current_agent]
      context_wrapper = turn_data[:context_wrapper]
      turns = turn_data[:turns]

      # Pre-turn hook
      before_turn(conversation, current_agent, context_wrapper, turns)
      
      # Update context
      context_wrapper.context.current_agent = current_agent
      context_wrapper.context.current_turn = turns
      
      # Run hooks
      runner.call_hook(:on_agent_start, context_wrapper, current_agent)
      
      # Run input guardrails
      current_input = conversation.last[:content] if conversation.last && conversation.last[:role] == "user"
      runner.run_input_guardrails(context_wrapper, current_agent, current_input) if current_input
      
      # Execute API call via strategy
      result = @api_strategy.execute(conversation, current_agent, runner)
      message = result[:message]
      usage = result[:usage]
      
      # Run output guardrails
      runner.run_output_guardrails(context_wrapper, current_agent, message[:content]) if message[:content]
      
      # Call agent end hook
      runner.call_hook(:on_agent_end, context_wrapper, current_agent, message)
      
      # Handle tool calls if present
      if @tool_executor.has_tool_calls?(message)
        @tool_executor.execute_tool_calls(
          message["tool_calls"] || message[:tool_calls],
          conversation,
          context_wrapper,
          result[:response]
        ) do |tool_name, arguments, &tool_block|
          wrap_tool_execution(tool_name, arguments, &tool_block)
        end
      end

      # Check for handoff
      handoff_result = @handoff_detector.check_for_handoff(message, current_agent)
      
      # Check tool calls for handoff patterns
      if @tool_executor.has_tool_calls?(message)
        tool_handoff_result = @handoff_detector.check_tool_calls_for_handoff(
          message["tool_calls"] || message[:tool_calls],
          current_agent
        )
        handoff_result = tool_handoff_result if tool_handoff_result[:handoff_occurred]
      end
      
      # Determine if execution should continue
      should_continue = @tool_executor.should_continue?(message)
      
      turn_result = {
        message: message,
        usage: usage,
        handoff_result: handoff_result,
        should_continue: should_continue
      }
      
      # Post-turn hook
      after_turn(conversation, current_agent, context_wrapper, turns, turn_result)
      
      turn_result
    end

    private

    ##
    # Create final execution result
    #
    # @param conversation [Array<Hash>] Final conversation state
    # @param usage [Hash] Accumulated token usage
    # @param context_wrapper [RunContextWrapper, nil] Execution context
    # @return [RunResult] The execution result
    #
    def create_result(conversation, usage, context_wrapper)
      RunResult.new(
        messages: conversation,
        usage: usage,
        metadata: context_wrapper&.context&.metadata || {}
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
  # The trace structure matches the Python OpenAI Agents SDK for compatibility.
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
      require_relative "tracing/trace"
      current_trace = Tracing::Context.current_trace

      if current_trace&.active?
        # We're inside an existing trace, just run normally
        super(messages)
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
    end

    protected

    ##
    # Start tracing span before each conversation turn
    #
    # Creates an agent span as a root span (matching Python SDK) and
    # sets all required attributes for OpenTelemetry compatibility.
    #
    # @param conversation [Array<Hash>] Current conversation state
    # @param current_agent [Agent] The active agent
    # @param context_wrapper [RunContextWrapper] Execution context
    # @param turns [Integer] Current turn number
    # @return [void]
    #
    def before_turn(conversation, current_agent, context_wrapper, turns)
      # Create agent span as root span (matching Python implementation)
      # Store original span stack and clear it to make this span root
      @original_span_stack = tracer.instance_variable_get(:@context).instance_variable_get(:@span_stack).dup
      tracer.instance_variable_get(:@context).instance_variable_set(:@span_stack, [])
      
      # Start the agent span
      @current_agent_span = tracer.start_span("agent.#{current_agent.name || "agent"}", kind: :agent)
      
      # Set agent span attributes
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
    # Sets the agent output attribute and ends the span created in before_turn.
    # Restores the original span stack to maintain proper span hierarchy.
    #
    # @param conversation [Array<Hash>] Current conversation state
    # @param current_agent [Agent] The active agent
    # @param context_wrapper [RunContextWrapper] Execution context
    # @param turns [Integer] Current turn number
    # @param result [Hash] Turn result with :message, :usage, :response
    # @return [void]
    #
    def after_turn(conversation, current_agent, context_wrapper, turns, result)
      # Set output on agent span
      if @current_agent_span
        message = result[:message]
        if message && config.trace_include_sensitive_data
          @current_agent_span.set_attribute("agent.output", message[:content] || "")
        else
          @current_agent_span.set_attribute("agent.output", "[REDACTED]")
        end
        
        # End the agent span
        @current_agent_span.end_span
        
        # Restore original span stack
        tracer.instance_variable_get(:@context).instance_variable_set(:@span_stack, @original_span_stack) if @original_span_stack
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
    def wrap_tool_execution(tool_name, arguments, &block)
      tracer.start_span("agent.#{agent.name}.tools.#{tool_name}", kind: :tool) do |tool_span|
        tool_span.set_attribute("tool.name", tool_name)
        tool_span.set_attribute("tool.arguments", arguments.to_json) if config.trace_include_sensitive_data
        
        result = yield
        
        if config.trace_include_sensitive_data
          tool_span.set_attribute("tool.result", result.to_s)
        end
        
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
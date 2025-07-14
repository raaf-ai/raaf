# frozen_string_literal: true

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
      # For Responses API, delegate to specialized method
      return execute_with_responses_api(messages) if provider.is_a?(Models::ResponsesProvider)

      # Standard execution flow
      execute_standard(messages)
    end

    protected

    ##
    # Execute conversation using standard chat completion API
    #
    # This method implements the core conversation loop for standard
    # providers (OpenAI, Anthropic, etc). It manages turns, handles
    # tool calls, and processes handoffs.
    #
    # @param messages [Array<Hash>] Initial conversation messages
    # @return [RunResult] The final result
    #
    def execute_standard(messages)
      conversation = messages.dup
      current_agent = agent
      turns = 0
      accumulated_usage = initialize_usage_tracking

      max_turns = config.max_turns || current_agent.max_turns
      context_wrapper = create_context_wrapper(conversation)

      while turns < max_turns
        check_execution_stop(conversation)
        
        # Execute single turn
        result = execute_turn(
          conversation: conversation,
          current_agent: current_agent,
          context_wrapper: context_wrapper,
          turns: turns
        )

        # Handle the result
        new_message = result[:message]
        usage = result[:usage]
        
        # Accumulate usage
        accumulate_usage(accumulated_usage, usage) if usage

        # Add message to conversation
        conversation << new_message

        # Handle tool calls if present
        if new_message["tool_calls"]
          handle_tool_calls(
            conversation: conversation,
            tool_calls: new_message["tool_calls"],
            context_wrapper: context_wrapper,
            response: result[:response]
          )
        end

        # Check for handoff
        handoff_result = check_for_handoff(new_message, current_agent)
        if handoff_result[:handoff_occurred]
          current_agent = handoff_result[:new_agent]
          conversation = handoff_result[:conversation]
          turns = 0 # Reset turns for new agent
          next
        end

        # Check if we should continue
        break unless should_continue?(new_message)

        turns += 1
      end

      # Check if we exceeded max turns
      if turns >= max_turns
        handle_max_turns_exceeded(conversation, max_turns)
      end

      # Create final result
      create_result(conversation, accumulated_usage, context_wrapper)
    end

    ##
    # Execute conversation using OpenAI Responses API
    #
    # This method uses the newer Responses API which provides
    # better streaming support and structured outputs.
    #
    # @param messages [Array<Hash>] Initial conversation messages
    # @return [RunResult] The final result
    #
    def execute_with_responses_api(messages)
      log_debug_api("Using Responses API executor", provider: provider.class.name)
      
      # Convert messages to items format
      items = convert_messages_to_items(messages)
      model = config.model || agent.model
      
      # Build provider parameters
      provider_params = build_provider_params(model)
      
      # Make API call
      response = make_api_call(items, provider_params)
      
      # Process response
      process_responses_api_response(messages, response)
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

    private

    ##
    # Initialize usage tracking structure
    # @return [Hash] Empty usage tracking hash
    #
    def initialize_usage_tracking
      {
        input_tokens: 0,
        output_tokens: 0,
        total_tokens: 0
      }
    end

    ##
    # Create execution context wrapper
    # @param conversation [Array<Hash>] Current conversation
    # @return [RunContextWrapper] Context wrapper for hooks
    #
    def create_context_wrapper(conversation)
      context = RunContext.new(
        messages: conversation,
        metadata: config.metadata || {},
        trace_id: config.trace_id,
        group_id: config.group_id
      )
      RunContextWrapper.new(context)
    end

    ##
    # Check if execution should be stopped
    #
    # @param conversation [Array<Hash>] Current conversation
    # @raise [ExecutionStoppedError] If execution should stop
    # @return [void]
    #
    def check_execution_stop(conversation)
      if runner.should_stop?
        conversation << { role: "assistant", content: "Execution stopped by user request." }
        raise ExecutionStoppedError, "Execution stopped by user request"
      end
    end

    ##
    # Execute a single conversation turn
    #
    # This method orchestrates all the steps of a single turn:
    # 1. Run pre-turn hooks
    # 2. Execute guardrails
    # 3. Make API call
    # 4. Process response
    # 5. Run post-turn hooks
    #
    # @param conversation [Array<Hash>] Current conversation state
    # @param current_agent [Agent] The active agent
    # @param context_wrapper [RunContextWrapper] Execution context
    # @param turns [Integer] Current turn number
    # @return [Hash] Result with :message, :usage, :response
    #
    def execute_turn(conversation:, current_agent:, context_wrapper:, turns:)
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
      
      # Prepare messages and make API call
      api_messages = runner.build_messages(conversation, current_agent, context_wrapper)
      model = config.model || current_agent.model
      model_params = build_model_params(current_agent)
      
      # Pre-API call hook
      before_api_call(api_messages, model, model_params)
      
      # Make the API call
      response = make_provider_call(api_messages, model, model_params)
      
      # Extract message and usage
      message = extract_message(response)
      usage = extract_usage(response)
      
      # Post-API call hook
      after_api_call(response, usage)
      
      # Run output guardrails
      runner.run_output_guardrails(context_wrapper, current_agent, message[:content]) if message[:content]
      
      # Call agent end hook
      runner.call_hook(:on_agent_end, context_wrapper, current_agent, message)
      
      result = { message: message, usage: usage, response: response }
      
      # Post-turn hook
      after_turn(conversation, current_agent, context_wrapper, turns, result)
      
      result
    end

    ##
    # Build model parameters for API call
    #
    # Constructs the parameters hash for the AI provider, including
    # response format, tool choice, and prompt settings.
    #
    # @param current_agent [Agent] The agent with model settings
    # @return [Hash] Parameters for the model API call
    #
    def build_model_params(current_agent)
      model_params = config.to_model_params
      
      # Add structured output support
      if current_agent.response_format
        model_params[:response_format] = current_agent.response_format
      end
      
      # Add tool choice support
      if current_agent.respond_to?(:tool_choice) && current_agent.tool_choice
        model_params[:tool_choice] = current_agent.tool_choice
      end
      
      # Add prompt support for Responses API
      if current_agent.prompt && provider.respond_to?(:supports_prompts?) && provider.supports_prompts?
        prompt_input = PromptUtil.to_model_input(current_agent.prompt, nil, current_agent)
        model_params[:prompt] = prompt_input if prompt_input
      end
      
      model_params
    end

    ##
    # Make API call to the AI provider
    #
    # @param api_messages [Array<Hash>] Formatted messages
    # @param model [String] Model identifier
    # @param model_params [Hash] Additional model parameters
    # @return [Hash] Provider response
    #
    def make_provider_call(api_messages, model, model_params)
      if config.stream
        provider.stream_completion(
          messages: api_messages,
          model: model,
          **model_params
        )
      else
        provider.complete(
          messages: api_messages,
          model: model,
          **model_params
        )
      end
    end

    ##
    # Extract assistant message from provider response
    #
    # Handles different response formats from various providers.
    #
    # @param response [Hash] Provider API response
    # @return [Hash] Message with role and content
    #
    def extract_message(response)
      # Extract the assistant message from the API response
      if response.is_a?(Hash)
        if response[:choices] && response[:choices].first
          # Standard OpenAI format
          response[:choices].first[:message]
        elsif response[:message]
          # Direct message format
          response[:message]
        else
          # Fallback to response itself
          response
        end
      else
        # Non-hash response
        { role: "assistant", content: response.to_s }
      end
    end

    ##
    # Extract token usage data from provider response
    #
    # @param response [Hash] Provider API response
    # @return [Hash, nil] Usage data or nil if not available
    #
    def extract_usage(response)
      # Extract usage data from the API response
      return nil unless response.is_a?(Hash)
      response[:usage]
    end

    ##
    # Accumulate token usage statistics
    #
    # Updates running totals for input, output, and total tokens.
    #
    # @param accumulated [Hash] Running usage totals to update
    # @param usage [Hash, nil] New usage data to add
    # @return [void]
    #
    def accumulate_usage(accumulated, usage)
      return unless usage
      
      accumulated[:input_tokens] += usage[:input_tokens] || usage[:prompt_tokens] || 0
      accumulated[:output_tokens] += usage[:output_tokens] || usage[:completion_tokens] || 0
      accumulated[:total_tokens] += usage[:total_tokens] || 0
    end

    ##
    # Process and execute tool calls
    #
    # @param conversation [Array<Hash>] Conversation to append results to
    # @param tool_calls [Array<Hash>] Tool calls from assistant
    # @param context_wrapper [RunContextWrapper] Execution context
    # @param response [Hash] Full API response
    #
    def handle_tool_calls(conversation:, tool_calls:, context_wrapper:, response:)
      # Process tool calls through runner
      runner.process_tool_calls(
        tool_calls, 
        agent,
        conversation, 
        context_wrapper,
        response
      )
    end

    ##
    # Check if a handoff to another agent is needed
    #
    # @param message [Hash] Assistant message to check
    # @param current_agent [Agent] Current active agent
    # @return [Hash] Result with :handoff_occurred and optionally :new_agent
    #
    def check_for_handoff(message, current_agent)
      # Check if the message indicates a handoff is needed
      return { handoff_occurred: false } unless message[:content]

      # Delegate to runner's handoff detection
      handoff_target = runner.detect_handoff_in_content(message[:content], current_agent)
      
      if handoff_target
        # Find the target agent
        target_agent = runner.find_handoff_agent(handoff_target, current_agent)
        
        if target_agent
          log_info("Handoff detected", from: current_agent.name, to: target_agent.name)
          {
            handoff_occurred: true,
            new_agent: target_agent
          }
        else
          log_warn("Handoff target not found", target: handoff_target)
          { handoff_occurred: false }
        end
      else
        { handoff_occurred: false }
      end
    end

    ##
    # Determine if conversation should continue
    #
    # Checks message content for termination signals and tool calls.
    #
    # @param message [Hash] The last assistant message
    # @return [Boolean] true to continue, false to stop
    #
    def should_continue?(message)
      # Determine if we should continue the conversation
      return true if message["tool_calls"] || message[:tool_calls] # Continue if there are tool calls
      return false unless message[:content] # Stop if no content
      
      # Stop if content indicates termination
      !message[:content].match?(/\b(STOP|TERMINATE|DONE|FINISHED)\b/i)
    end

    ##
    # Handle maximum turns exceeded error
    #
    # @param conversation [Array<Hash>] Current conversation
    # @param max_turns [Integer] The maximum turns limit
    # @raise [MaxTurnsError] Always raises with error message
    #
    def handle_max_turns_exceeded(conversation, max_turns)
      error_msg = "Maximum turns (#{max_turns}) exceeded"
      conversation << { role: "assistant", content: error_msg }
      raise MaxTurnsError, error_msg
    end

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

    ##
    # Convert messages to Responses API items format
    #
    # The Responses API uses a different format where tool calls
    # and results are separate items rather than embedded in messages.
    #
    # @param messages [Array<Hash>] Standard message format
    # @return [Array<Hash>] Items in Responses API format
    #
    def convert_messages_to_items(messages)
      messages.map do |msg|
        case msg[:role]
        when "system"
          { type: "message", role: "system", content: msg[:content] }
        when "user"
          { type: "message", role: "user", content: msg[:content] }
        when "assistant"
          if msg[:tool_calls]
            [
              { type: "message", role: "assistant", content: msg[:content] || "" },
              msg[:tool_calls].map do |tc|
                {
                  type: "function",
                  name: tc.dig("function", "name") || tc[:function][:name],
                  arguments: tc.dig("function", "arguments") || tc[:function][:arguments],
                  id: tc["id"] || tc[:id]
                }
              end
            ].flatten
          else
            { type: "message", role: "assistant", content: msg[:content] }
          end
        when "tool"
          {
            type: "function_result",
            function_call_id: msg[:tool_call_id],
            content: msg[:content]
          }
        else
          msg
        end
      end.flatten
    end

    ##
    # Build parameters for Responses API call
    #
    # Constructs the specific parameters required by the Responses API,
    # including modalities, tools, and response format.
    #
    # @param model [String] Model identifier (unused but kept for consistency)
    # @return [Hash] Parameters for Responses API
    #
    def build_provider_params(model)
      params = {
        modalities: ["text"],
        prompt: agent.prompt&.to_api_format,
        tools: format_tools(agent.tools),
        temperature: config.temperature,
        max_tokens: config.max_tokens || config.max_completion_tokens,
        metadata: config.metadata
      }.compact
      
      # Add response format if specified
      if agent.response_format
        params[:response_format] = agent.response_format
      end
      
      # Add tool choice if specified
      if agent.respond_to?(:tool_choice) && agent.tool_choice
        params[:tool_choice] = agent.tool_choice
      end
      
      params
    end

    ##
    # Make API call using Responses API
    #
    # @param items [Array<Hash>] Conversation items in Responses format
    # @param provider_params [Hash] Provider-specific parameters
    # @return [Hash] API response
    #
    def make_api_call(items, provider_params)
      if config.stream
        provider.stream_responses(
          items: items,
          model: config.model || agent.model,
          **provider_params
        )
      else
        provider.create_response(
          items: items,
          model: config.model || agent.model,
          **provider_params
        )
      end
    end

    ##
    # Process Responses API response into final result
    #
    # @param original_messages [Array<Hash>] Original input messages
    # @param response [Hash] API response to process
    # @return [RunResult] Final execution result
    #
    def process_responses_api_response(original_messages, response)
      conversation = original_messages.dup
      usage = response[:usage] || {}
      
      # Convert response back to messages format
      new_messages = convert_response_to_messages(response)
      conversation.concat(new_messages)
      
      # Create result
      create_result(conversation, usage, nil)
    end

    ##
    # Format tools for API call
    #
    # Converts tool objects to their API definition format.
    #
    # @param tools [Array<Tool>] Agent tools
    # @return [Array<Hash>, nil] Formatted tool definitions or nil
    #
    def format_tools(tools)
      return nil unless tools && !tools.empty?

      tools.map do |tool|
        if tool.respond_to?(:to_tool_definition)
          tool.to_tool_definition
        else
          tool
        end
      end
    end

    ##
    # Convert Responses API response to message format
    #
    # Extracts messages from the Responses API format and converts
    # them back to the standard message format.
    #
    # @param response [Hash] Responses API response
    # @return [Array<Hash>] Messages in standard format
    #
    def convert_response_to_messages(response)
      # Convert Responses API response back to messages format
      return [] unless response[:choices]

      messages = []
      choice = response[:choices].first
      return messages unless choice[:message]

      message = choice[:message]
      messages << {
        role: "assistant",
        content: message[:content]
      }

      # Handle tool calls if present
      if message[:tool_calls]
        messages.last[:tool_calls] = message[:tool_calls]
      end

      messages
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
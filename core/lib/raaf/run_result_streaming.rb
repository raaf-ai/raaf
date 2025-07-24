# frozen_string_literal: true

require "async"

module RAAF

  ##
  # Streaming execution engine for RAAF
  #
  # The RunResultStreaming class provides real-time streaming execution of agent
  # conversations with granular event-based feedback. It enables applications to
  # receive incremental updates during agent execution rather than waiting for
  # complete responses.
  #
  # == Streaming Features
  #
  # * **Real-time Events**: Receive events as agent execution progresses
  # * **Async Execution**: Non-blocking agent execution with background processing
  # * **Event Types**: Multiple event types for different execution phases
  # * **Tool Streaming**: Real-time updates during tool execution
  # * **Guardrail Events**: Live feedback on guardrail evaluation
  # * **Handoff Support**: Events for agent-to-agent handoffs
  # * **Error Handling**: Streaming error events with context
  #
  # == Event Stream Types
  #
  # * **AgentStartEvent**: Agent begins execution
  # * **MessageStartEvent**: New message generation begins
  # * **RawContentDeltaEvent**: Incremental content updates
  # * **ToolCallEvent**: Tool invocation detected
  # * **ToolExecutionStartEvent**: Tool execution begins
  # * **ToolExecutionCompleteEvent**: Tool execution finishes
  # * **GuardrailStartEvent**: Guardrail evaluation begins
  # * **AgentHandoffEvent**: Agent handoff occurs
  # * **AgentFinishEvent**: Agent execution completes
  # * **StreamErrorEvent**: Error during execution
  #
  # == Usage Patterns
  #
  # The streaming API supports both synchronous iteration with blocks and
  # asynchronous enumeration for different application needs.
  #
  # @example Basic streaming with block
  #   streaming = RunResultStreaming.new(
  #     agent: agent,
  #     input: "Hello, how can you help me?",
  #     run_config: config
  #   )
  #
  #   streaming.start_streaming.stream_events do |event|
  #     case event
  #     when RawContentDeltaEvent
  #       print event.delta
  #     when ToolCallEvent
  #       puts "\nCalling tool: #{event.tool_call['function']['name']}"
  #     when AgentFinishEvent
  #       puts "\nAgent finished: #{event.result.messages.last[:content]}"
  #     end
  #   end
  #
  # @example Async streaming with enumeration
  #   streaming = RunResultStreaming.new(agent: agent, input: input)
  #   streaming.start_streaming
  #
  #   streaming.stream_events.each do |event|
  #     handle_event(event)
  #   end
  #
  #   final_result = streaming.wait_for_completion
  #
  # @example Error handling in streams
  #   streaming.stream_events do |event|
  #     case event
  #     when StreamErrorEvent
  #       puts "Error: #{event.error.message}"
  #       break
  #     when GuardrailStartEvent
  #       puts "Checking #{event.type} guardrail: #{event.guardrail.name}"
  #     end
  #   end
  #
  # @example Multi-agent handoff streaming
  #   streaming.stream_events do |event|
  #     case event
  #     when AgentHandoffEvent
  #       puts "Handoff: #{event.from_agent.name} -> #{event.to_agent.name}"
  #       puts "Reason: #{event.reason}"
  #     when AgentStartEvent
  #       puts "Agent #{event.agent.name} started"
  #     end
  #   end
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  # @see RunResult For non-streaming execution results
  # @see Async::Queue For the underlying async queue implementation
  class RunResultStreaming

    # @return [Agent] the agent being executed
    attr_reader :agent

    # @return [String, Array, Hash] the input provided to the agent
    attr_reader :input

    # @return [RunConfig, nil] execution configuration
    attr_reader :run_config

    # @return [Async::Queue] queue containing streaming events
    attr_reader :events_queue

    # @return [RunResult, nil] final execution result when complete
    attr_reader :final_result

    ##
    # Initialize streaming execution instance
    #
    # @param agent [Agent] the agent to execute
    # @param input [String, Array, Hash] input for the agent (message(s)
    # @param run_config [RunConfig, nil] execution configuration
    # @param tracer [Tracing::SpanTracer, nil] tracer for execution monitoring
    # @param provider [Models::Interface, nil] AI provider for execution
    #
    # @example Basic initialization
    #   streaming = RunResultStreaming.new(
    #     agent: my_agent,
    #     input: "What's the weather like?"
    #   )
    #
    # @example With configuration and tracing
    #   streaming = RunResultStreaming.new(
    #     agent: agent,
    #     input: messages,
    #     run_config: RunConfig.new(max_turns: 5),
    #     tracer: tracer
    #   )
    def initialize(agent:, input:, run_config: nil, tracer: nil, provider: nil)
      @agent = agent
      @input = input
      @run_config = run_config
      @tracer = tracer
      @provider = provider

      @events_queue = Queue.new
      @final_result = nil
      @finished = false
      @error = nil
      @background_task = nil
    end

    ##
    # Stream execution events with optional block processing
    #
    # Provides access to the event stream either through block iteration
    # (synchronous) or by returning an async enumerator. Events are yielded
    # in real-time as agent execution progresses.
    #
    # @yieldparam event [Object] streaming event (various event types)
    # @return [StreamEventEnumerator, nil] async enumerator if no block given
    #
    # @example Synchronous processing with block
    #   streaming.stream_events do |event|
    #     puts "Received: #{event.class.name}"
    #   end
    #
    # @example Asynchronous enumeration
    #   enumerator = streaming.stream_events
    #   enumerator.each { |event| process_event(event) }
    def stream_events(&)
      if block_given?
        # Synchronous iteration with block
        while (event = next_event)
          yield event
        end
      else
        # Return async enumerator
        StreamEventEnumerator.new(self)
      end
    end

    ##
    # Get the next event from the stream
    #
    # Returns the next available event from the queue, or nil if the stream
    # is finished and no more events are available. This method handles both
    # blocking and non-blocking queue operations.
    #
    # @return [Object, nil] next event or nil if stream is finished
    #
    # @example Manual event processing
    #   while (event = streaming.next_event)
    #     handle_event(event)
    #   end
    def next_event
      return nil if @finished && @events_queue.empty?

      # For non-blocking behavior, check if queue is empty first
      if @events_queue.empty?
        return nil if @finished

        # If not finished, do blocking dequeue to wait for next event
      else
        # Queue has items, dequeue immediately
      end
      @events_queue.deq
    end

    ##
    # Start the streaming execution in the background
    #
    # Initiates agent execution in a background async task, allowing the
    # main thread to continue processing events. The execution runs
    # asynchronously while events are queued for consumption.
    #
    # @return [RunResultStreaming] self for method chaining
    #
    # @example Starting streaming execution
    #   streaming = RunResultStreaming.new(agent: agent, input: input)
    #   streaming.start_streaming.stream_events do |event|
    #     # Process events as they arrive
    #   end
    def start_streaming
      @background_task = Async do |task|
        run_agent_with_streaming(task)
      rescue StandardError => e
        @error = e
        @events_queue << StreamErrorEvent.new(error: e)
      ensure
        @finished = true
        @events_queue.close if @events_queue.respond_to?(:close)
      end

      self
    end

    ##
    # Wait for streaming execution to complete
    #
    # Blocks until the background execution task finishes and returns
    # the final result. If an error occurred during execution, it will
    # be re-raised here.
    #
    # @return [RunResult] final execution result
    # @raise [StandardError] any error that occurred during execution
    #
    # @example Waiting for completion
    #   streaming.start_streaming
    #   # ... process events ...
    #   final_result = streaming.wait_for_completion
    def wait_for_completion
      @background_task&.wait
      raise @error if @error

      @final_result
    end

    ##
    # Check if streaming execution has finished
    #
    # @return [Boolean] true if execution is complete, false otherwise
    #
    # @example Checking completion status
    #   if streaming.finished?
    #     puts "Execution complete"
    #   end
    def finished?
      @finished
    end

    ##
    # Check if an error occurred during execution
    #
    # @return [Boolean] true if an error occurred, false otherwise
    #
    # @example Error checking
    #   if streaming.error?
    #     puts "Execution failed with error"
    #   end
    def error?
      !@error.nil?
    end

    private

    def run_agent_with_streaming(task)
      # Start agent span
      span = @tracer&.start_span("agent.#{@agent.name}")

      begin
        @events_queue << AgentStartEvent.new(agent: @agent)

        # Initialize conversation
        messages = normalize_input(@input)
        context = build_run_context(messages)

        # Start streaming execution
        stream_agent_execution(context, messages, task)
      ensure
        span&.finish
      end
    end

    def stream_agent_execution(context, messages, task)
      turn_count = 0
      max_turns = @run_config&.max_turns || 10
      current_agent = @agent

      while turn_count < max_turns
        turn_count += 1

        # Stream agent turn
        result = stream_agent_turn(current_agent, messages, context, task)

        # Check for handoffs
        if result[:handoff_to]
          handoff_agent = find_handoff_agent(current_agent, result[:handoff_to])
          if handoff_agent
            @events_queue << AgentHandoffEvent.new(
              from_agent: current_agent,
              to_agent: handoff_agent,
              reason: result[:handoff_reason]
            )
            current_agent = handoff_agent
            result[:messages]
            next
          end
        end

        # Check if we're done
        if result[:finished]
          @final_result = RunResult.new(
            messages: result[:messages],
            agent: current_agent,
            turn_count: turn_count
          )
          @events_queue << AgentFinishEvent.new(
            agent: current_agent,
            result: @final_result
          )
          break
        end

        messages = result[:messages]
      end

      return unless turn_count >= max_turns

      error = MaxTurnsError.new("Maximum turns (#{max_turns}) exceeded")
      @events_queue << StreamErrorEvent.new(error: error)
      raise error
    end

    def stream_agent_turn(agent, messages, context, _task)
      # Run input guardrails
      stream_input_guardrails(agent, messages.last[:content], context)

      # Stream LLM generation
      response_messages = []
      tool_calls = []

      @provider.stream_generate(
        messages: messages,
        model: agent.model || @run_config&.model,
        tools: agent.tools&.map(&:to_openai_format),
        **(@run_config&.to_model_params || {})
      ) do |chunk|
        event = process_raw_chunk(chunk, agent)
        @events_queue << event if event

        # Accumulate response
        if chunk[:type] == :content_delta
          if response_messages.empty?
            response_messages << { role: "assistant", content: chunk[:delta] }
            @events_queue << MessageStartEvent.new(
              agent: agent,
              message: response_messages.last
            )
          else
            response_messages.last[:content] += chunk[:delta]
          end
        elsif chunk[:type] == :tool_call
          tool_calls << chunk[:tool_call]
          @events_queue << ToolCallEvent.new(
            agent: agent,
            tool_call: chunk[:tool_call]
          )
        end
      end

      # Finalize message
      if response_messages.any?
        messages << response_messages.last
        @events_queue << MessageCompleteEvent.new(
          agent: agent,
          message: response_messages.last
        )
      end

      # Execute tools if present
      if tool_calls.any?
        tool_results = execute_tools_with_streaming(agent, tool_calls, context)
        messages.concat(tool_results)

        # Continue with tool results
        return {
          messages: messages,
          finished: false,
          handoff_to: nil
        }
      end

      # Check for handoffs
      handoff_info = detect_handoff(agent, response_messages.last)
      if handoff_info
        return {
          messages: messages,
          finished: false,
          handoff_to: handoff_info[:agent],
          handoff_reason: handoff_info[:reason]
        }
      end

      # Run output guardrails
      stream_output_guardrails(agent, response_messages.last[:content], context)

      {
        messages: messages,
        finished: true,
        handoff_to: nil
      }
    end

    def execute_tools_with_streaming(agent, tool_calls, _context)
      results = []

      tool_calls.each do |tool_call|
        @events_queue << ToolExecutionStartEvent.new(
          agent: agent,
          tool_call: tool_call
        )

        begin
          result = agent.execute_tool(
            tool_call["function"]["name"],
            **JSON.parse(tool_call["function"]["arguments"])
          )

          tool_message = {
            role: "tool",
            tool_call_id: tool_call["id"],
            content: result.to_s
          }

          results << tool_message

          @events_queue << ToolExecutionCompleteEvent.new(
            agent: agent,
            tool_call: tool_call,
            result: result
          )
        rescue StandardError => e
          error_message = {
            role: "tool",
            tool_call_id: tool_call["id"],
            content: "Error: #{e.message}"
          }

          results << error_message

          @events_queue << ToolExecutionErrorEvent.new(
            agent: agent,
            tool_call: tool_call,
            error: e
          )
        end
      end

      results
    end

    def stream_input_guardrails(agent, input, context)
      return unless agent.input_guardrails&.any?

      agent.input_guardrails.each do |guardrail|
        @events_queue << GuardrailStartEvent.new(
          agent: agent,
          guardrail: guardrail,
          type: :input
        )

        result = guardrail.call(context, agent, input)

        @events_queue << GuardrailCompleteEvent.new(
          agent: agent,
          guardrail: guardrail,
          type: :input,
          result: result
        )

        next unless result.tripwire_triggered

        error = InputGuardrailTripwireTriggered.new(
          "Input guardrail '#{guardrail.name}' triggered"
        )
        @events_queue << StreamErrorEvent.new(error: error)
        raise error
      end
    end

    def stream_output_guardrails(agent, output, context)
      return unless agent.output_guardrails&.any?

      agent.output_guardrails.each do |guardrail|
        @events_queue << GuardrailStartEvent.new(
          agent: agent,
          guardrail: guardrail,
          type: :output
        )

        result = guardrail.call(context, agent, output)

        @events_queue << GuardrailCompleteEvent.new(
          agent: agent,
          guardrail: guardrail,
          type: :output,
          result: result
        )

        next unless result.tripwire_triggered

        error = OutputGuardrailTripwireTriggered.new(
          "Output guardrail '#{guardrail.name}' triggered"
        )
        @events_queue << StreamErrorEvent.new(error: error)
        raise error
      end
    end

    def process_raw_chunk(chunk, agent)
      case chunk[:type]
      when :content_delta
        RawContentDeltaEvent.new(
          agent: agent,
          delta: chunk[:delta]
        )
      when :tool_call_start
        RawToolCallStartEvent.new(
          agent: agent,
          tool_call: chunk[:tool_call]
        )
      when :tool_call_delta
        RawToolCallDeltaEvent.new(
          agent: agent,
          tool_call_id: chunk[:tool_call_id],
          delta: chunk[:delta]
        )
      when :finish
        RawFinishEvent.new(
          agent: agent,
          finish_reason: chunk[:finish_reason]
        )
      end
    end

    def normalize_input(input)
      case input
      when String
        [{ role: "user", content: input }]
      when Array
        input
      when Hash
        [input]
      else
        raise ArgumentError, "Invalid input type: #{input.class}"
      end
    end

    def build_run_context(messages)
      RAAF::RunContext.new(
        messages: messages,
        run_config: @run_config,
        tracer: @tracer
      )
    end

    def find_handoff_agent(current_agent, agent_name)
      current_agent.handoffs&.find { |h| h.respond_to?(:name) ? h.name == agent_name : h == agent_name }
    end

    def detect_handoff(_agent, message)
      return nil unless message && message[:content]

      content = message[:content]
      return unless content.include?("HANDOFF:")

      parts = content.split("HANDOFF:")
      return unless parts.length > 1

      agent_info = parts[1].strip.split(/\s+/, 2)
      {
        agent: agent_info[0],
        reason: agent_info[1] || "No reason provided"
      }
    end

    ##
    # Async enumerator for streaming events
    #
    # Provides an Enumerable interface for processing streaming events
    # asynchronously. Allows for standard Ruby enumeration methods while
    # maintaining the streaming nature of the underlying event queue.
    #
    # @example Using enumerable methods
    #   enumerator = streaming.stream_events
    #   content_events = enumerator.select { |e| e.is_a?(RawContentDeltaEvent) }
    #   first_tool_call = enumerator.find { |e| e.is_a?(ToolCallEvent) }
    class StreamEventEnumerator

      include Enumerable

      ##
      # Initialize enumerator with streaming result
      #
      # @param streaming_result [RunResultStreaming] the streaming instance
      def initialize(streaming_result)
        @streaming_result = streaming_result
      end

      ##
      # Enumerate through all streaming events
      #
      # Iterates through all events in the stream until completion,
      # yielding each event to the provided block.
      #
      # @yieldparam event [Object] streaming event
      # @return [Enumerator] if no block given
      def each
        return enum_for(:each) unless block_given?

        while (event = @streaming_result.next_event)
          yield event
        end
      end

    end

  end

  ##
  # Exception raised when input guardrail tripwire is triggered
  #
  # This exception is raised during streaming execution when an input
  # guardrail detects a violation and triggers its tripwire mechanism.
  #
  # @example Handling input guardrail errors
  #   streaming.stream_events do |event|
  #     case event
  #     when StreamErrorEvent
  #       if event.error.is_a?(InputGuardrailTripwireTriggered)
  #         puts "Input guardrail blocked execution: #{event.error.message}"
  #       end
  #     end
  #   end
  class InputGuardrailTripwireTriggered < StandardError; end

  ##
  # Exception raised when output guardrail tripwire is triggered
  #
  # This exception is raised during streaming execution when an output
  # guardrail detects a violation and triggers its tripwire mechanism.
  #
  # @example Handling output guardrail errors
  #   streaming.stream_events do |event|
  #     case event
  #     when StreamErrorEvent
  #       if event.error.is_a?(OutputGuardrailTripwireTriggered)
  #         puts "Output guardrail blocked response: #{event.error.message}"
  #       end
  #     end
  #   end
  class OutputGuardrailTripwireTriggered < StandardError; end

end

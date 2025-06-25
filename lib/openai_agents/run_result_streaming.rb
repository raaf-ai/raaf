require 'async'
require 'async/queue'

module OpenAIAgents
  class RunResultStreaming
    attr_reader :agent, :input, :run_config, :events_queue, :final_result

    def initialize(agent:, input:, run_config: nil, tracer: nil, provider: nil)
      @agent = agent
      @input = input
      @run_config = run_config
      @tracer = tracer
      @provider = provider
      
      @events_queue = Async::Queue.new
      @final_result = nil
      @finished = false
      @error = nil
      @background_task = nil
    end

    def stream_events(&block)
      if block_given?
        # Synchronous iteration with block
        while event = next_event
          yield event
        end
      else
        # Return async enumerator
        StreamEventEnumerator.new(self)
      end
    end

    def next_event
      return nil if @finished && @events_queue.empty?
      
      begin
        event = @events_queue.dequeue_nonblock
        return event
      rescue Async::Queue::Empty
        if @finished
          return nil
        else
          # Wait for next event
          event = @events_queue.dequeue
          return event
        end
      end
    end

    def start_streaming
      @background_task = Async do |task|
        begin
          run_agent_with_streaming(task)
        rescue => e
          @error = e
          @events_queue.enqueue(StreamErrorEvent.new(error: e))
        ensure
          @finished = true
          @events_queue.close
        end
      end
      
      self
    end

    def wait_for_completion
      @background_task&.wait
      raise @error if @error
      @final_result
    end

    def finished?
      @finished
    end

    def error?
      !@error.nil?
    end

    private

    def run_agent_with_streaming(task)
      # Start agent span
      span = @tracer&.start_span("agent.#{@agent.name}")
      
      begin
        @events_queue.enqueue(AgentStartEvent.new(agent: @agent))
        
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
            @events_queue.enqueue(AgentHandoffEvent.new(
              from_agent: current_agent,
              to_agent: handoff_agent,
              reason: result[:handoff_reason]
            ))
            current_agent = handoff_agent
            messages = result[:messages]
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
          @events_queue.enqueue(AgentFinishEvent.new(
            agent: current_agent,
            result: @final_result
          ))
          break
        end
        
        messages = result[:messages]
      end
      
      if turn_count >= max_turns
        error = MaxTurnsError.new("Maximum turns (#{max_turns}) exceeded")
        @events_queue.enqueue(StreamErrorEvent.new(error: error))
        raise error
      end
    end

    def stream_agent_turn(agent, messages, context, task)
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
        @events_queue.enqueue(event) if event
        
        # Accumulate response
        if chunk[:type] == :content_delta
          if response_messages.empty?
            response_messages << { role: 'assistant', content: chunk[:delta] }
            @events_queue.enqueue(MessageStartEvent.new(
              agent: agent,
              message: response_messages.last
            ))
          else
            response_messages.last[:content] += chunk[:delta]
          end
        elsif chunk[:type] == :tool_call
          tool_calls << chunk[:tool_call]
          @events_queue.enqueue(ToolCallEvent.new(
            agent: agent,
            tool_call: chunk[:tool_call]
          ))
        end
      end
      
      # Finalize message
      if response_messages.any?
        messages << response_messages.last
        @events_queue.enqueue(MessageCompleteEvent.new(
          agent: agent,
          message: response_messages.last
        ))
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

    def execute_tools_with_streaming(agent, tool_calls, context)
      results = []
      
      tool_calls.each do |tool_call|
        @events_queue.enqueue(ToolExecutionStartEvent.new(
          agent: agent,
          tool_call: tool_call
        ))
        
        begin
          result = agent.execute_tool(
            tool_call['function']['name'],
            **JSON.parse(tool_call['function']['arguments'])
          )
          
          tool_message = {
            role: 'tool',
            tool_call_id: tool_call['id'],
            content: result.to_s
          }
          
          results << tool_message
          
          @events_queue.enqueue(ToolExecutionCompleteEvent.new(
            agent: agent,
            tool_call: tool_call,
            result: result
          ))
          
        rescue => e
          error_message = {
            role: 'tool',
            tool_call_id: tool_call['id'],
            content: "Error: #{e.message}"
          }
          
          results << error_message
          
          @events_queue.enqueue(ToolExecutionErrorEvent.new(
            agent: agent,
            tool_call: tool_call,
            error: e
          ))
        end
      end
      
      results
    end

    def stream_input_guardrails(agent, input, context)
      return unless agent.input_guardrails&.any?
      
      agent.input_guardrails.each do |guardrail|
        @events_queue.enqueue(GuardrailStartEvent.new(
          agent: agent,
          guardrail: guardrail,
          type: :input
        ))
        
        result = guardrail.call(context, agent, input)
        
        @events_queue.enqueue(GuardrailCompleteEvent.new(
          agent: agent,
          guardrail: guardrail,
          type: :input,
          result: result
        ))
        
        if result.tripwire_triggered
          error = InputGuardrailTripwireTriggered.new(
            "Input guardrail '#{guardrail.name}' triggered"
          )
          @events_queue.enqueue(StreamErrorEvent.new(error: error))
          raise error
        end
      end
    end

    def stream_output_guardrails(agent, output, context)
      return unless agent.output_guardrails&.any?
      
      agent.output_guardrails.each do |guardrail|
        @events_queue.enqueue(GuardrailStartEvent.new(
          agent: agent,
          guardrail: guardrail,
          type: :output
        ))
        
        result = guardrail.call(context, agent, output)
        
        @events_queue.enqueue(GuardrailCompleteEvent.new(
          agent: agent,
          guardrail: guardrail,
          type: :output,
          result: result
        ))
        
        if result.tripwire_triggered
          error = OutputGuardrailTripwireTriggered.new(
            "Output guardrail '#{guardrail.name}' triggered"
          )
          @events_queue.enqueue(StreamErrorEvent.new(error: error))
          raise error
        end
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
      else
        nil
      end
    end

    def normalize_input(input)
      case input
      when String
        [{ role: 'user', content: input }]
      when Array
        input
      when Hash
        [input]
      else
        raise ArgumentError, "Invalid input type: #{input.class}"
      end
    end

    def build_run_context(messages)
      OpenAIAgents::RunContext.new(
        messages: messages,
        run_config: @run_config,
        tracer: @tracer
      )
    end

    def find_handoff_agent(current_agent, agent_name)
      current_agent.handoffs&.find { |h| h.respond_to?(:name) ? h.name == agent_name : h == agent_name }
    end

    def detect_handoff(agent, message)
      return nil unless message && message[:content]
      
      content = message[:content]
      if content.include?('HANDOFF:')
        parts = content.split('HANDOFF:')
        if parts.length > 1
          agent_info = parts[1].strip.split(/\s+/, 2)
          {
            agent: agent_info[0],
            reason: agent_info[1] || "No reason provided"
          }
        end
      end
    end

    class StreamEventEnumerator
      include Enumerable

      def initialize(streaming_result)
        @streaming_result = streaming_result
      end

      def each
        while event = @streaming_result.next_event
          yield event
        end
      end
    end
  end

  # Exception classes
  class InputGuardrailTripwireTriggered < StandardError; end
  class OutputGuardrailTripwireTriggered < StandardError; end
  class MaxTurnsError < StandardError; end
end
# frozen_string_literal: true

require "spec_helper"

# Define stub event classes for testing if they don't exist
module RAAF

  # Stub event classes for testing streaming functionality
  RawContentDeltaEvent = Struct.new(:agent, :delta) unless defined?(RawContentDeltaEvent)
  RawToolCallStartEvent = Struct.new(:agent, :tool_call) unless defined?(RawToolCallStartEvent)
  RawToolCallDeltaEvent = Struct.new(:agent, :tool_call_id, :delta) unless defined?(RawToolCallDeltaEvent)
  RawFinishEvent = Struct.new(:agent, :finish_reason) unless defined?(RawFinishEvent)
  AgentStartEvent = Struct.new(:agent) unless defined?(AgentStartEvent)
  AgentFinishEvent = Struct.new(:agent, :result) unless defined?(AgentFinishEvent)
  AgentHandoffEvent = Struct.new(:from_agent, :to_agent, :reason) unless defined?(AgentHandoffEvent)
  MessageStartEvent = Struct.new(:agent, :message) unless defined?(MessageStartEvent)
  MessageCompleteEvent = Struct.new(:agent, :message) unless defined?(MessageCompleteEvent)
  ToolCallEvent = Struct.new(:agent, :tool_call) unless defined?(ToolCallEvent)
  ToolExecutionStartEvent = Struct.new(:agent, :tool_call) unless defined?(ToolExecutionStartEvent)
  ToolExecutionCompleteEvent = Struct.new(:agent, :tool_call, :result) unless defined?(ToolExecutionCompleteEvent)
  ToolExecutionErrorEvent = Struct.new(:agent, :tool_call, :error) unless defined?(ToolExecutionErrorEvent)
  GuardrailStartEvent = Struct.new(:agent, :guardrail, :type) unless defined?(GuardrailStartEvent)
  GuardrailCompleteEvent = Struct.new(:agent, :guardrail, :type, :result) unless defined?(GuardrailCompleteEvent)
  StreamErrorEvent = Struct.new(:error) unless defined?(StreamErrorEvent)
  RunContext = Struct.new(:messages, :run_config, :tracer) unless defined?(RunContext)

end

# Stub Async::Queue::Empty if it doesn't exist
module Async

  class Queue

    class Empty < StandardError; end unless defined?(Empty)

  end

end

RSpec.describe RAAF::RunResultStreaming do
  let(:mock_agent) { create_test_agent(name: "StreamingAgent", instructions: "Test streaming agent") }
  let(:mock_provider) { create_mock_provider }
  let(:mock_tracer) { double("Tracer") }
  let(:run_config) { double("RunConfig", max_turns: 5, model: "gpt-4o", to_model_params: {}) }
  let(:input) { "Hello, test streaming!" }

  let(:streaming) do
    described_class.new(
      agent: mock_agent,
      input: input,
      run_config: run_config,
      tracer: mock_tracer,
      provider: mock_provider
    )
  end

  before do
    # Mock provider streaming response
    allow(mock_provider).to receive(:stream_generate).and_yield(
      { type: :content_delta, delta: "Hello" }
    ).and_yield(
      { type: :content_delta, delta: " world!" }
    ).and_yield(
      { type: :finish, finish_reason: "stop" }
    )

    # Mock tracer
    allow(mock_tracer).to receive(:start_span).and_return(double("Span", finish: nil))

    # Mock agent tools and guardrails
    allow(mock_agent).to receive_messages(tools: [], input_guardrails: [], output_guardrails: [], handoffs: [], model: "gpt-4o")
  end

  describe "#initialize" do
    it "initializes with required parameters" do
      expect(streaming.agent).to eq(mock_agent)
      expect(streaming.input).to eq(input)
      expect(streaming.run_config).to eq(run_config)
      expect(streaming.events_queue).to be_a(Queue)
      expect(streaming.final_result).to be_nil
    end

    it "initializes with default parameters" do
      simple_streaming = described_class.new(agent: mock_agent, input: input)
      expect(simple_streaming.run_config).to be_nil
      expect(simple_streaming.events_queue).to be_a(Queue)
    end

    it "sets up instance variables correctly" do
      expect(streaming.finished?).to be false
      expect(streaming.error?).to be false
    end
  end

  describe "#stream_events" do
    context "with block" do
      it "yields events synchronously" do
        events = []

        # Mock next_event to return some events
        allow(streaming).to receive(:next_event).and_return(
          double("Event1", class: "Event1"),
          double("Event2", class: "Event2"),
          nil
        )

        streaming.stream_events do |event|
          events << event
        end

        expect(events.size).to eq(2)
      end
    end

    context "without block" do
      it "returns a StreamEventEnumerator" do
        enumerator = streaming.stream_events
        expect(enumerator).to be_a(RAAF::RunResultStreaming::StreamEventEnumerator)
      end
    end
  end

  describe "#next_event" do
    before do
      streaming.instance_variable_set(:@events_queue, double("Queue"))
    end

    it "returns nil when finished and queue is empty" do
      streaming.instance_variable_set(:@finished, true)
      allow(streaming.events_queue).to receive(:empty?).and_return(true)

      expect(streaming.next_event).to be_nil
    end

    it "dequeues events from queue" do
      event = double("Event")
      allow(streaming.events_queue).to receive_messages(empty?: false, deq: event)

      expect(streaming.next_event).to eq(event)
    end

    it "handles empty queue when not finished" do
      streaming.instance_variable_set(:@finished, false)
      allow(streaming.events_queue).to receive_messages(empty?: true)

      event = double("Event")
      allow(streaming.events_queue).to receive(:deq).and_return(event)

      expect(streaming.next_event).to eq(event)
    end
  end

  describe "#start_streaming" do
    it "returns self for method chaining" do
      expect(streaming.start_streaming).to eq(streaming)
    end

    it "starts background async task" do
      allow(streaming).to receive(:run_agent_with_streaming)

      streaming.start_streaming

      expect(streaming.instance_variable_get(:@background_task)).to be_a(Async::Task)
    end

    it "handles errors during streaming" do
      error = StandardError.new("Test error")
      allow(streaming).to receive(:run_agent_with_streaming).and_raise(error)

      streaming.start_streaming
      sleep(0.1) # Allow async task to run

      expect(streaming.instance_variable_get(:@error)).to eq(error)
    end

    it "ensures finished flag is set" do
      allow(streaming).to receive(:run_agent_with_streaming)
      allow(streaming.events_queue).to receive(:close)

      streaming.start_streaming
      sleep(0.1) # Allow async task to run

      expect(streaming.finished?).to be true
    end
  end

  describe "#wait_for_completion" do
    it "waits for background task" do
      task = double("Task")
      streaming.instance_variable_set(:@background_task, task)
      streaming.instance_variable_set(:@final_result, double("Result"))

      expect(task).to receive(:wait)

      result = streaming.wait_for_completion
      expect(result).to eq(streaming.final_result)
    end

    it "raises error if one occurred" do
      error = StandardError.new("Test error")
      streaming.instance_variable_set(:@error, error)

      expect { streaming.wait_for_completion }.to raise_error(error)
    end

    it "returns final result when successful" do
      final_result = double("FinalResult")
      streaming.instance_variable_set(:@final_result, final_result)

      expect(streaming.wait_for_completion).to eq(final_result)
    end
  end

  describe "#finished?" do
    it "returns false when not finished" do
      streaming.instance_variable_set(:@finished, false)
      expect(streaming.finished?).to be false
    end

    it "returns true when finished" do
      streaming.instance_variable_set(:@finished, true)
      expect(streaming.finished?).to be true
    end
  end

  describe "#error?" do
    it "returns false when no error" do
      streaming.instance_variable_set(:@error, nil)
      expect(streaming.error?).to be false
    end

    it "returns true when error exists" do
      streaming.instance_variable_set(:@error, StandardError.new("Test"))
      expect(streaming.error?).to be true
    end
  end

  describe "private methods" do
    describe "#normalize_input" do
      it "converts string to message array" do
        result = streaming.send(:normalize_input, "Hello")
        expect(result).to eq([{ role: "user", content: "Hello" }])
      end

      it "returns array as-is" do
        messages = [{ role: "user", content: "Hello" }]
        result = streaming.send(:normalize_input, messages)
        expect(result).to eq(messages)
      end

      it "converts hash to array" do
        message = { role: "user", content: "Hello" }
        result = streaming.send(:normalize_input, message)
        expect(result).to eq([message])
      end

      it "raises error for invalid input type" do
        expect { streaming.send(:normalize_input, 123) }.to raise_error(
          ArgumentError, "Invalid input type: Integer"
        )
      end
    end

    describe "#build_run_context" do
      it "creates RunContext with messages and config" do
        messages = [{ role: "user", content: "Hello" }]

        expect(RAAF::RunContext).to receive(:new).with(
          messages: messages,
          run_config: run_config,
          tracer: mock_tracer
        )

        streaming.send(:build_run_context, messages)
      end
    end

    describe "#find_handoff_agent" do
      let(:handoff_agent) { double("HandoffAgent", name: "TestAgent") }

      before do
        allow(mock_agent).to receive(:handoffs).and_return([handoff_agent])
      end

      it "finds agent by name when agent responds to name" do
        result = streaming.send(:find_handoff_agent, mock_agent, "TestAgent")
        expect(result).to eq(handoff_agent)
      end

      it "finds agent by direct comparison when agent doesn't respond to name" do
        string_agent = "TestAgent"
        allow(mock_agent).to receive(:handoffs).and_return([string_agent])

        result = streaming.send(:find_handoff_agent, mock_agent, "TestAgent")
        expect(result).to eq(string_agent)
      end

      it "returns nil when agent not found" do
        result = streaming.send(:find_handoff_agent, mock_agent, "NonExistentAgent")
        expect(result).to be_nil
      end
    end

    describe "#detect_handoff" do
      it "detects handoff with reason" do
        message = { content: "HANDOFF: AgentName This is the reason" }
        result = streaming.send(:detect_handoff, mock_agent, message)

        expect(result).to eq({
                               agent: "AgentName",
                               reason: "This is the reason"
                             })
      end

      it "detects handoff without reason" do
        message = { content: "HANDOFF: AgentName" }
        result = streaming.send(:detect_handoff, mock_agent, message)

        expect(result).to eq({
                               agent: "AgentName",
                               reason: "No reason provided"
                             })
      end

      it "returns nil when no handoff detected" do
        message = { content: "Regular message" }
        result = streaming.send(:detect_handoff, mock_agent, message)

        expect(result).to be_nil
      end

      it "returns nil for nil message" do
        result = streaming.send(:detect_handoff, mock_agent, nil)
        expect(result).to be_nil
      end

      it "returns nil for message without content" do
        message = { role: "assistant" }
        result = streaming.send(:detect_handoff, mock_agent, message)

        expect(result).to be_nil
      end
    end

    describe "#process_raw_chunk" do
      it "creates RawContentDeltaEvent for content delta" do
        chunk = { type: :content_delta, delta: "Hello" }
        result = streaming.send(:process_raw_chunk, chunk, mock_agent)

        expect(result).to be_a(RAAF::RawContentDeltaEvent)
        expect(result.agent).to eq(mock_agent)
        expect(result.delta).to eq("Hello")
      end

      it "creates RawToolCallStartEvent for tool call start" do
        chunk = { type: :tool_call_start, tool_call: { id: "call_123" } }
        result = streaming.send(:process_raw_chunk, chunk, mock_agent)

        expect(result).to be_a(RAAF::RawToolCallStartEvent)
        expect(result.agent).to eq(mock_agent)
        expect(result.tool_call).to eq({ id: "call_123" })
      end

      it "creates RawToolCallDeltaEvent for tool call delta" do
        chunk = { type: :tool_call_delta, tool_call_id: "call_123", delta: "arg" }
        result = streaming.send(:process_raw_chunk, chunk, mock_agent)

        expect(result).to be_a(RAAF::RawToolCallDeltaEvent)
        expect(result.agent).to eq(mock_agent)
        expect(result.tool_call_id).to eq("call_123")
        expect(result.delta).to eq("arg")
      end

      it "creates RawFinishEvent for finish" do
        chunk = { type: :finish, finish_reason: "stop" }
        result = streaming.send(:process_raw_chunk, chunk, mock_agent)

        expect(result).to be_a(RAAF::RawFinishEvent)
        expect(result.agent).to eq(mock_agent)
        expect(result.finish_reason).to eq("stop")
      end

      it "returns nil for unknown chunk type" do
        chunk = { type: :unknown }
        result = streaming.send(:process_raw_chunk, chunk, mock_agent)

        expect(result).to be_nil
      end
    end
  end

  describe "StreamEventEnumerator" do
    let(:enumerator) { described_class::StreamEventEnumerator.new(streaming) }

    describe "#initialize" do
      it "stores streaming result" do
        expect(enumerator.instance_variable_get(:@streaming_result)).to eq(streaming)
      end
    end

    describe "#each" do
      it "yields all events from streaming result" do
        events = [double("Event1"), double("Event2")]
        allow(streaming).to receive(:next_event).and_return(events[0], events[1], nil)

        yielded_events = enumerator.map { |event| event }

        expect(yielded_events).to eq(events)
      end

      it "returns enumerator when no block given" do
        result = enumerator.each
        expect(result).to be_a(Enumerator)
      end

      it "includes Enumerable module" do
        expect(enumerator).to be_a(Enumerable)
      end
    end
  end

  describe "guardrail streaming" do
    let(:mock_guardrail) { double("Guardrail", name: "TestGuardrail") }
    let(:guardrail_result) { double("GuardrailResult", tripwire_triggered: false) }

    describe "#stream_input_guardrails" do
      before do
        allow(mock_agent).to receive(:input_guardrails).and_return([mock_guardrail])
        allow(mock_guardrail).to receive(:call).and_return(guardrail_result)
      end

      it "processes input guardrails and enqueues events" do
        context = double("Context")
        input_text = "Test input"

        expect(streaming.events_queue).to receive(:<<).with(
          an_instance_of(RAAF::GuardrailStartEvent)
        )
        expect(streaming.events_queue).to receive(:<<).with(
          an_instance_of(RAAF::GuardrailCompleteEvent)
        )

        streaming.send(:stream_input_guardrails, mock_agent, input_text, context)
      end

      it "raises error when tripwire triggered" do
        allow(guardrail_result).to receive(:tripwire_triggered).and_return(true)

        expect(streaming.events_queue).to receive(:<<).exactly(3).times # start, complete, and error events

        expect do
          streaming.send(:stream_input_guardrails, mock_agent, "input", double("Context"))
        end.to raise_error(RAAF::InputGuardrailTripwireTriggered)
      end
    end

    describe "#stream_output_guardrails" do
      before do
        allow(mock_agent).to receive(:output_guardrails).and_return([mock_guardrail])
        allow(mock_guardrail).to receive(:call).and_return(guardrail_result)
      end

      it "processes output guardrails and enqueues events" do
        context = double("Context")
        output_text = "Test output"

        expect(streaming.events_queue).to receive(:<<).with(
          an_instance_of(RAAF::GuardrailStartEvent)
        )
        expect(streaming.events_queue).to receive(:<<).with(
          an_instance_of(RAAF::GuardrailCompleteEvent)
        )

        streaming.send(:stream_output_guardrails, mock_agent, output_text, context)
      end

      it "raises error when tripwire triggered" do
        allow(guardrail_result).to receive(:tripwire_triggered).and_return(true)

        expect(streaming.events_queue).to receive(:<<).exactly(3).times # start, complete, and error events

        expect do
          streaming.send(:stream_output_guardrails, mock_agent, "output", double("Context"))
        end.to raise_error(RAAF::OutputGuardrailTripwireTriggered)
      end
    end
  end

  describe "tool execution streaming" do
    let(:tool_calls) do
      [{
        "id" => "call_123",
        "function" => {
          "name" => "test_tool",
          "arguments" => '{"param": "value"}'
        }
      }]
    end

    describe "#execute_tools_with_streaming" do
      before do
        allow(mock_agent).to receive(:execute_tool).and_return("Tool result")
      end

      it "executes tools and enqueues events" do
        context = double("Context")

        expect(streaming.events_queue).to receive(:<<).with(
          an_instance_of(RAAF::ToolExecutionStartEvent)
        )
        expect(streaming.events_queue).to receive(:<<).with(
          an_instance_of(RAAF::ToolExecutionCompleteEvent)
        )

        results = streaming.send(:execute_tools_with_streaming, mock_agent, tool_calls, context)

        expect(results).to be_an(Array)
        expect(results.first[:role]).to eq("tool")
        expect(results.first[:tool_call_id]).to eq("call_123")
        expect(results.first[:content]).to eq("Tool result")
      end

      it "handles tool execution errors" do
        error = StandardError.new("Tool failed")
        allow(mock_agent).to receive(:execute_tool).and_raise(error)

        expect(streaming.events_queue).to receive(:<<).with(
          an_instance_of(RAAF::ToolExecutionStartEvent)
        )
        expect(streaming.events_queue).to receive(:<<).with(
          an_instance_of(RAAF::ToolExecutionErrorEvent)
        )

        results = streaming.send(:execute_tools_with_streaming, mock_agent, tool_calls, double("Context"))

        expect(results.first[:content]).to eq("Error: Tool failed")
      end
    end
  end

  # Test custom exception classes
  describe "exception classes" do
    describe "RAAF::InputGuardrailTripwireTriggered" do
      it "inherits from StandardError" do
        expect(RAAF::InputGuardrailTripwireTriggered.new).to be_a(StandardError)
      end
    end

    describe "RAAF::OutputGuardrailTripwireTriggered" do
      it "inherits from StandardError" do
        expect(RAAF::OutputGuardrailTripwireTriggered.new).to be_a(StandardError)
      end
    end
  end
end

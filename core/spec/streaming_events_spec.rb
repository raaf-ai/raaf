# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::StreamingEvents do
  describe "ResponseCreatedEvent" do
    let(:response) { { id: "resp_123", object: "response" } }
    let(:sequence_number) { 1 }
    let(:event) { RAAF::StreamingEvents::ResponseCreatedEvent.new(response: response, sequence_number: sequence_number) }

    describe "#initialize" do
      it "sets response and sequence number" do
        expect(event.response).to eq(response)
        expect(event.sequence_number).to eq(sequence_number)
        expect(event.type).to eq("response.created")
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        hash = event.to_h
        expect(hash[:response]).to eq(response)
        expect(hash[:type]).to eq("response.created")
        expect(hash[:sequence_number]).to eq(sequence_number)
      end
    end
  end

  describe "ResponseOutputItemAddedEvent" do
    let(:item) { { id: "item_123", type: "message" } }
    let(:output_index) { 0 }
    let(:sequence_number) { 2 }
    let(:event) do
      RAAF::StreamingEvents::ResponseOutputItemAddedEvent.new(
        item: item,
        output_index: output_index,
        sequence_number: sequence_number
      )
    end

    describe "#initialize" do
      it "sets item, output index, and sequence number" do
        expect(event.item).to eq(item)
        expect(event.output_index).to eq(output_index)
        expect(event.sequence_number).to eq(sequence_number)
        expect(event.type).to eq("response.output_item.added")
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        hash = event.to_h
        expect(hash[:item]).to eq(item)
        expect(hash[:output_index]).to eq(output_index)
        expect(hash[:type]).to eq("response.output_item.added")
        expect(hash[:sequence_number]).to eq(sequence_number)
      end
    end
  end

  describe "ResponseContentPartAddedEvent" do
    let(:content_index) { 0 }
    let(:item_id) { "item_123" }
    let(:output_index) { 0 }
    let(:part) { { type: "text" } }
    let(:sequence_number) { 3 }
    let(:event) do
      RAAF::StreamingEvents::ResponseContentPartAddedEvent.new(
        content_index: content_index,
        item_id: item_id,
        output_index: output_index,
        part: part,
        sequence_number: sequence_number
      )
    end

    describe "#initialize" do
      it "sets all attributes correctly" do
        expect(event.content_index).to eq(content_index)
        expect(event.item_id).to eq(item_id)
        expect(event.output_index).to eq(output_index)
        expect(event.part).to eq(part)
        expect(event.sequence_number).to eq(sequence_number)
        expect(event.type).to eq("response.content_part.added")
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        hash = event.to_h
        expect(hash[:content_index]).to eq(content_index)
        expect(hash[:item_id]).to eq(item_id)
        expect(hash[:output_index]).to eq(output_index)
        expect(hash[:part]).to eq(part)
        expect(hash[:type]).to eq("response.content_part.added")
        expect(hash[:sequence_number]).to eq(sequence_number)
      end
    end
  end

  describe "ResponseTextDeltaEvent" do
    let(:content_index) { 0 }
    let(:delta) { "Hello" }
    let(:item_id) { "item_123" }
    let(:output_index) { 0 }
    let(:sequence_number) { 4 }
    let(:event) do
      RAAF::StreamingEvents::ResponseTextDeltaEvent.new(
        content_index: content_index,
        delta: delta,
        item_id: item_id,
        output_index: output_index,
        sequence_number: sequence_number
      )
    end

    describe "#initialize" do
      it "sets all attributes correctly" do
        expect(event.content_index).to eq(content_index)
        expect(event.delta).to eq(delta)
        expect(event.item_id).to eq(item_id)
        expect(event.output_index).to eq(output_index)
        expect(event.sequence_number).to eq(sequence_number)
        expect(event.type).to eq("response.output_text.delta")
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        hash = event.to_h
        expect(hash[:content_index]).to eq(content_index)
        expect(hash[:delta]).to eq(delta)
        expect(hash[:item_id]).to eq(item_id)
        expect(hash[:output_index]).to eq(output_index)
        expect(hash[:type]).to eq("response.output_text.delta")
        expect(hash[:sequence_number]).to eq(sequence_number)
      end
    end
  end

  describe "ResponseRefusalDeltaEvent" do
    let(:content_index) { 0 }
    let(:delta) { "I cannot" }
    let(:item_id) { "item_123" }
    let(:output_index) { 0 }
    let(:sequence_number) { 5 }
    let(:event) do
      RAAF::StreamingEvents::ResponseRefusalDeltaEvent.new(
        content_index: content_index,
        delta: delta,
        item_id: item_id,
        output_index: output_index,
        sequence_number: sequence_number
      )
    end

    describe "#initialize" do
      it "sets all attributes correctly" do
        expect(event.content_index).to eq(content_index)
        expect(event.delta).to eq(delta)
        expect(event.item_id).to eq(item_id)
        expect(event.output_index).to eq(output_index)
        expect(event.sequence_number).to eq(sequence_number)
        expect(event.type).to eq("response.refusal.delta")
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        hash = event.to_h
        expect(hash[:content_index]).to eq(content_index)
        expect(hash[:delta]).to eq(delta)
        expect(hash[:item_id]).to eq(item_id)
        expect(hash[:output_index]).to eq(output_index)
        expect(hash[:type]).to eq("response.refusal.delta")
        expect(hash[:sequence_number]).to eq(sequence_number)
      end
    end
  end

  describe "ResponseFunctionCallArgumentsDeltaEvent" do
    let(:delta) { '{"name":' }
    let(:item_id) { "item_123" }
    let(:output_index) { 0 }
    let(:sequence_number) { 6 }
    let(:event) do
      RAAF::StreamingEvents::ResponseFunctionCallArgumentsDeltaEvent.new(
        delta: delta,
        item_id: item_id,
        output_index: output_index,
        sequence_number: sequence_number
      )
    end

    describe "#initialize" do
      it "sets all attributes correctly" do
        expect(event.delta).to eq(delta)
        expect(event.item_id).to eq(item_id)
        expect(event.output_index).to eq(output_index)
        expect(event.sequence_number).to eq(sequence_number)
        expect(event.type).to eq("response.function_call_arguments.delta")
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        hash = event.to_h
        expect(hash[:delta]).to eq(delta)
        expect(hash[:item_id]).to eq(item_id)
        expect(hash[:output_index]).to eq(output_index)
        expect(hash[:type]).to eq("response.function_call_arguments.delta")
        expect(hash[:sequence_number]).to eq(sequence_number)
      end
    end
  end

  describe "ResponseReasoningDeltaEvent" do
    let(:delta) { "Let me think about this..." }
    let(:item_id) { "reasoning_123" }
    let(:output_index) { 0 }
    let(:sequence_number) { 7 }
    let(:event) do
      RAAF::StreamingEvents::ResponseReasoningDeltaEvent.new(
        delta: delta,
        item_id: item_id,
        output_index: output_index,
        sequence_number: sequence_number
      )
    end

    describe "#initialize" do
      it "sets all attributes correctly" do
        expect(event.delta).to eq(delta)
        expect(event.item_id).to eq(item_id)
        expect(event.output_index).to eq(output_index)
        expect(event.sequence_number).to eq(sequence_number)
        expect(event.type).to eq("response.reasoning.delta")
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        hash = event.to_h
        expect(hash[:delta]).to eq(delta)
        expect(hash[:item_id]).to eq(item_id)
        expect(hash[:output_index]).to eq(output_index)
        expect(hash[:type]).to eq("response.reasoning.delta")
        expect(hash[:sequence_number]).to eq(sequence_number)
      end
    end
  end

  describe "ResponseCompletedEvent" do
    let(:response) { { id: "resp_123", status: "completed" } }
    let(:sequence_number) { 7 }
    let(:event) do
      RAAF::StreamingEvents::ResponseCompletedEvent.new(
        response: response,
        sequence_number: sequence_number
      )
    end

    describe "#initialize" do
      it "sets response and sequence number" do
        expect(event.response).to eq(response)
        expect(event.sequence_number).to eq(sequence_number)
        expect(event.type).to eq("response.completed")
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        hash = event.to_h
        expect(hash[:response]).to eq(response)
        expect(hash[:type]).to eq("response.completed")
        expect(hash[:sequence_number]).to eq(sequence_number)
      end
    end
  end

  # Test the streaming events handler
  describe "ChatCompletionStreamHandler" do
    let(:response) { { id: "resp_123", model: "gpt-4o" } }
    let(:events) { [] }

    describe ".handle_stream" do
      context "with text content chunks" do
        let(:stream_chunks) do
          [
            { "choices" => [{ "delta" => { "content" => "Hello" } }] },
            { "choices" => [{ "delta" => { "content" => " world" } }] },
            { "choices" => [{ "delta" => { "content" => "!" } }] },
            { "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 } }
          ]
        end

        it "creates proper event sequence for text response" do
          RAAF::StreamingEvents::ChatCompletionStreamHandler.handle_stream(response, stream_chunks) do |event|
            events << event
          end

          # Should have: created, item added, content part added, 3 text deltas, content part done, item done, completed
          expect(events.size).to eq(9)

          # Verify event types and sequence
          expect(events[0]).to be_a(RAAF::StreamingEvents::ResponseCreatedEvent)
          expect(events[1]).to be_a(RAAF::StreamingEvents::ResponseOutputItemAddedEvent)
          expect(events[2]).to be_a(RAAF::StreamingEvents::ResponseContentPartAddedEvent)
          expect(events[3]).to be_a(RAAF::StreamingEvents::ResponseTextDeltaEvent)
          expect(events[4]).to be_a(RAAF::StreamingEvents::ResponseTextDeltaEvent)
          expect(events[5]).to be_a(RAAF::StreamingEvents::ResponseTextDeltaEvent)
          expect(events[6]).to be_a(RAAF::StreamingEvents::ResponseContentPartDoneEvent)
          expect(events[7]).to be_a(RAAF::StreamingEvents::ResponseOutputItemDoneEvent)
          expect(events[8]).to be_a(RAAF::StreamingEvents::ResponseCompletedEvent)

          # Verify text deltas
          expect(events[3].delta).to eq("Hello")
          expect(events[4].delta).to eq(" world")
          expect(events[5].delta).to eq("!")

          # Verify final response includes usage
          final_event = events.last
          expect(final_event.response["usage"]).to include(
            "input_tokens" => 10,
            "output_tokens" => 5,
            "total_tokens" => 15
          )
        end

        it "accumulates text content correctly" do
          RAAF::StreamingEvents::ChatCompletionStreamHandler.handle_stream(response, stream_chunks) do |event|
            events << event
          end

          content_done_event = events.find { |e| e.is_a?(RAAF::StreamingEvents::ResponseContentPartDoneEvent) }
          expect(content_done_event.part["text"]).to eq("Hello world!")
        end
      end

      context "with refusal chunks" do
        let(:stream_chunks) do
          [
            { "choices" => [{ "delta" => { "refusal" => "I cannot" } }] },
            { "choices" => [{ "delta" => { "refusal" => " help with that" } }] }
          ]
        end

        it "creates proper event sequence for refusal response" do
          RAAF::StreamingEvents::ChatCompletionStreamHandler.handle_stream(response, stream_chunks) do |event|
            events << event
          end

          # Find refusal delta events
          refusal_events = events.select { |e| e.is_a?(RAAF::StreamingEvents::ResponseRefusalDeltaEvent) }
          expect(refusal_events.size).to eq(2)
          expect(refusal_events[0].delta).to eq("I cannot")
          expect(refusal_events[1].delta).to eq(" help with that")
        end

        it "accumulates refusal content correctly" do
          RAAF::StreamingEvents::ChatCompletionStreamHandler.handle_stream(response, stream_chunks) do |event|
            events << event
          end

          content_done_event = events.find { |e| e.is_a?(RAAF::StreamingEvents::ResponseContentPartDoneEvent) }
          expect(content_done_event.part["refusal"]).to eq("I cannot help with that")
        end
      end

      context "with tool call chunks" do
        let(:stream_chunks) do
          [
            { "choices" => [{ "delta" => { "tool_calls" => [{ "index" => 0, "id" => "call_", "function" => { "name" => "get_", "arguments" => "{\"" } }] } }] },
            { "choices" => [{ "delta" => { "tool_calls" => [{ "index" => 0, "id" => "123", "function" => { "name" => "weather", "arguments" => "location" } }] } }] },
            { "choices" => [{ "delta" => { "tool_calls" => [{ "index" => 0, "function" => { "arguments" => "\": \"NYC\"}" } }] } }] }
          ]
        end

        it "creates proper event sequence for tool calls" do
          RAAF::StreamingEvents::ChatCompletionStreamHandler.handle_stream(response, stream_chunks) do |event|
            events << event
          end

          # Should have tool call related events
          function_args_events = events.select { |e| e.is_a?(RAAF::StreamingEvents::ResponseFunctionCallArgumentsDeltaEvent) }
          expect(function_args_events.size).to eq(1)

          # Final event should show complete tool call
          completed_event = events.last
          expect(completed_event).to be_a(RAAF::StreamingEvents::ResponseCompletedEvent)

          tool_call_output = completed_event.response["output"].find { |o| o["type"] == "function_call" }
          expect(tool_call_output["name"]).to eq("get_weather")
          expect(tool_call_output["call_id"]).to eq("call_123")
          expect(tool_call_output["arguments"]).to eq("{\"location\": \"NYC\"}")
        end
      end

      context "with mixed content and tool calls" do
        let(:stream_chunks) do
          [
            { "choices" => [{ "delta" => { "content" => "Let me check the weather." } }] },
            { "choices" => [{ "delta" => { "tool_calls" => [{ "index" => 0, "id" => "call_123", "function" => { "name" => "get_weather", "arguments" => "{\"location\": \"NYC\"}" } }] } }] }
          ]
        end

        it "handles both content and tool calls in same response" do
          RAAF::StreamingEvents::ChatCompletionStreamHandler.handle_stream(response, stream_chunks) do |event|
            events << event
          end

          # Should have both text delta and function call events
          text_events = events.select { |e| e.is_a?(RAAF::StreamingEvents::ResponseTextDeltaEvent) }
          function_events = events.select { |e| e.is_a?(RAAF::StreamingEvents::ResponseFunctionCallArgumentsDeltaEvent) }

          expect(text_events.size).to eq(1)
          expect(function_events.size).to eq(1)
          expect(text_events.first.delta).to eq("Let me check the weather.")
        end
      end

      context "with empty or invalid chunks" do
        let(:stream_chunks) do
          [
            { "choices" => [] },
            { "choices" => [{ "delta" => {} }] },
            { "choices" => [{ "delta" => { "content" => nil } }] },
            { "other_field" => "ignored" }
          ]
        end

        it "handles empty chunks gracefully" do
          expect do
            RAAF::StreamingEvents::ChatCompletionStreamHandler.handle_stream(response, stream_chunks) do |event|
              events << event
            end
          end.not_to raise_error

          # Should still have created and completed events
          expect(events.size).to eq(2)
          expect(events.first).to be_a(RAAF::StreamingEvents::ResponseCreatedEvent)
          expect(events.last).to be_a(RAAF::StreamingEvents::ResponseCompletedEvent)
        end
      end

      context "sequence number generation" do
        let(:stream_chunks) do
          [
            { "choices" => [{ "delta" => { "content" => "Test" } }] }
          ]
        end

        it "generates sequential numbers for events" do
          RAAF::StreamingEvents::ChatCompletionStreamHandler.handle_stream(response, stream_chunks) do |event|
            events << event
          end

          sequence_numbers = events.map(&:sequence_number)
          expected_sequence = (0...events.size).to_a
          expect(sequence_numbers).to eq(expected_sequence)
        end
      end
    end
  end

  # Test streaming state management
  describe "StreamingState" do
    let(:state) { RAAF::StreamingEvents::StreamingState.new }

    describe "#initialize" do
      it "initializes with default values" do
        expect(state.started).to be false
        expect(state.text_content_index_and_output).to be_nil
        expect(state.refusal_content_index_and_output).to be_nil
        expect(state.function_calls).to eq({})
      end
    end

    describe "state tracking" do
      it "can track started state" do
        state.started = true
        expect(state.started).to be true
      end

      it "can track content indices" do
        state.text_content_index_and_output = [0, { "text" => "Hello" }]
        expect(state.text_content_index_and_output[0]).to eq(0)
        expect(state.text_content_index_and_output[1]["text"]).to eq("Hello")
      end

      it "can track function calls" do
        state.function_calls[0] = { "id" => "call_123", "name" => "test" }
        expect(state.function_calls[0]["name"]).to eq("test")
      end
    end
  end

  # Test sequence number generator
  describe "SequenceNumber" do
    let(:generator) { RAAF::StreamingEvents::SequenceNumber.new }

    describe "#get_and_increment" do
      it "starts at 0 and increments" do
        expect(generator.get_and_increment).to eq(0)
        expect(generator.get_and_increment).to eq(1)
        expect(generator.get_and_increment).to eq(2)
      end

      it "maintains independent counters for different instances" do
        generator2 = RAAF::StreamingEvents::SequenceNumber.new

        expect(generator.get_and_increment).to eq(0)
        expect(generator2.get_and_increment).to eq(0)
        expect(generator.get_and_increment).to eq(1)
        expect(generator2.get_and_increment).to eq(1)
      end
    end
  end

  # Test streaming processor if it exists
  if defined?(RAAF::StreamingEvents::StreamProcessor)
    describe "StreamProcessor" do
      describe ".chunk_response" do
        it "processes response in chunks" do
          content = "Hello world!"
          chunks = []

          RAAF::StreamingEvents::StreamProcessor.chunk_response(content) do |chunk|
            chunks << chunk
          end

          expect(chunks).not_to be_empty
          expect(chunks.join).to eq(content)
        end
      end
    end
  end
end

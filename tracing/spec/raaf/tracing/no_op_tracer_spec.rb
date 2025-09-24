# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing::NoOpTracer do
  let(:tracer) { described_class.new }

  describe "#initialize" do
    it "creates a new NoOpTracer instance" do
      expect(tracer).to be_a(described_class)
    end
  end

  describe "span creation methods" do
    let(:block_result) { "block executed" }

    describe "#agent_span" do
      it "executes the block without creating any span" do
        result = tracer.agent_span("test_span", { metadata: "value" }) do
          block_result
        end
        expect(result).to eq(block_result)
      end

      it "handles missing block gracefully" do
        expect { tracer.agent_span("test_span") }.not_to raise_error
      end
    end

    describe "#tool_span" do
      it "executes the block without creating any span" do
        result = tracer.tool_span("test_tool", { tool_type: "search" }) do
          block_result
        end
        expect(result).to eq(block_result)
      end

      it "handles missing block gracefully" do
        expect { tracer.tool_span("test_tool") }.not_to raise_error
      end
    end

    describe "#custom_span" do
      it "executes block without span parameter" do
        result = tracer.custom_span("custom_operation") do
          block_result
        end
        expect(result).to eq(block_result)
      end

      it "provides NoOpSpan when block expects span parameter" do
        span_received = nil
        tracer.custom_span("custom_operation") do |span|
          span_received = span
        end
        expect(span_received).to be_a(RAAF::Tracing::NoOpSpan)
      end

      it "handles missing block gracefully" do
        expect { tracer.custom_span("custom_operation") }.not_to raise_error
      end
    end

    describe "#pipeline_span" do
      it "executes the block without creating any span" do
        result = tracer.pipeline_span("test_pipeline") do
          block_result
        end
        expect(result).to eq(block_result)
      end

      it "handles missing block gracefully" do
        expect { tracer.pipeline_span("test_pipeline") }.not_to raise_error
      end
    end

    describe "#response_span" do
      it "executes the block without creating any span" do
        result = tracer.response_span("test_response") do
          block_result
        end
        expect(result).to eq(block_result)
      end

      it "handles missing block gracefully" do
        expect { tracer.response_span("test_response") }.not_to raise_error
      end
    end
  end

  describe "processor methods" do
    let(:mock_processor) { double("MockProcessor") }

    describe "#add_processor" do
      it "accepts processors without storing them" do
        expect { tracer.add_processor(mock_processor) }.not_to raise_error
      end
    end

    describe "#processors" do
      it "returns empty array" do
        expect(tracer.processors).to eq([])
        tracer.add_processor(mock_processor)
        expect(tracer.processors).to eq([])
      end

      it "returns same array instance for efficiency" do
        array1 = tracer.processors
        array2 = tracer.processors
        expect(array1).to be(array2)
      end
    end
  end

  describe "lifecycle methods" do
    describe "#force_flush" do
      it "does nothing" do
        expect { tracer.force_flush }.not_to raise_error
      end
    end

    describe "#shutdown" do
      it "does nothing" do
        expect { tracer.shutdown }.not_to raise_error
      end
    end
  end

  describe "#disabled?" do
    it "always returns true" do
      expect(tracer.disabled?).to be(true)
    end
  end

  describe "method_missing" do
    it "handles unknown methods gracefully" do
      expect { tracer.unknown_method }.not_to raise_error
    end

    it "returns self for method chaining" do
      result = tracer.unknown_method.another_unknown_method
      expect(result).to eq(tracer)
    end

    it "executes block when provided" do
      block_executed = false
      tracer.unknown_method { block_executed = true }
      expect(block_executed).to be(true)
    end

    it "provides NoOpSpan when block expects parameter" do
      span_received = nil
      tracer.unknown_span_method do |span|
        span_received = span
      end
      expect(span_received).to be_a(RAAF::Tracing::NoOpSpan)
    end
  end

  describe "#respond_to_missing?" do
    it "responds to any method" do
      expect(tracer.respond_to?(:any_method_name)).to be(true)
      expect(tracer.respond_to?(:another_method, true)).to be(true)
    end
  end

  describe "string representation" do
    describe "#to_s" do
      it "provides meaningful string representation" do
        str = tracer.to_s
        expect(str).to include("RAAF::Tracing::NoOpTracer")
        expect(str).to include("disabled")
      end
    end

    describe "#inspect" do
      it "matches to_s output" do
        expect(tracer.inspect).to eq(tracer.to_s)
      end
    end
  end

  describe "performance characteristics" do
    it "has minimal overhead for span creation" do
      # This test verifies that NoOpTracer doesn't accumulate state
      expect do
        1000.times do |i|
          tracer.agent_span("span_#{i}") { "work" }
        end
      end.not_to change { tracer.processors.size }
    end

    it "doesn't create objects during span operations" do
      # Verify that no objects are created/stored during normal operations
      initial_object_count = ObjectSpace.count_objects[:TOTAL]
      
      100.times do
        tracer.agent_span("test") { "work" }
        tracer.tool_span("test") { "work" }
      end
      
      final_object_count = ObjectSpace.count_objects[:TOTAL]
      # Allow for minimal object creation (test framework overhead)
      expect(final_object_count - initial_object_count).to be < 10
    end
  end
end

RSpec.describe RAAF::Tracing::NoOpSpan do
  let(:span) { described_class.new }

  describe "#initialize" do
    it "creates a new NoOpSpan instance" do
      expect(span).to be_a(described_class)
    end
  end

  describe "span modification methods" do
    describe "#set_attribute" do
      it "returns self for method chaining" do
        result = span.set_attribute("key", "value")
        expect(result).to eq(span)
      end

      it "accepts any key-value pairs" do
        expect { span.set_attribute("string_key", "string_value") }.not_to raise_error
        expect { span.set_attribute(:symbol_key, 123) }.not_to raise_error
        expect { span.set_attribute(nil, nil) }.not_to raise_error
      end
    end

    describe "#add_event" do
      it "returns self for method chaining" do
        result = span.add_event("test_event")
        expect(result).to eq(span)
      end

      it "accepts events with attributes" do
        expect do
          span.add_event("error", { error_code: 500, message: "Server Error" })
        end.not_to raise_error
      end
    end

    describe "#set_status" do
      it "returns self for method chaining" do
        result = span.set_status(:ok)
        expect(result).to eq(span)
      end

      it "accepts any status value" do
        expect { span.set_status(:ok) }.not_to raise_error
        expect { span.set_status(:error) }.not_to raise_error
        expect { span.set_status("unknown") }.not_to raise_error
      end
    end

    describe "#record_exception" do
      it "returns self for method chaining" do
        exception = StandardError.new("test error")
        result = span.record_exception(exception)
        expect(result).to eq(span)
      end

      it "accepts any exception object" do
        expect { span.record_exception(StandardError.new) }.not_to raise_error
        expect { span.record_exception(RuntimeError.new("runtime error")) }.not_to raise_error
      end
    end
  end

  describe "span lifecycle methods" do
    describe "#finish" do
      it "does nothing" do
        expect { span.finish }.not_to raise_error
      end
    end

    describe "#finished?" do
      it "always returns true" do
        expect(span.finished?).to be(true)
      end
    end
  end

  describe "span data access" do
    describe "#attributes" do
      it "returns empty hash" do
        expect(span.attributes).to eq({})
      end

      it "returns same hash instance for efficiency" do
        hash1 = span.attributes
        hash2 = span.attributes
        expect(hash1).to be(hash2)
      end
    end

    describe "#events" do
      it "returns empty array" do
        expect(span.events).to eq([])
      end

      it "returns same array instance for efficiency" do
        array1 = span.events
        array2 = span.events
        expect(array1).to be(array2)
      end
    end
  end

  describe "method_missing" do
    it "handles unknown methods gracefully" do
      expect { span.unknown_method }.not_to raise_error
    end

    it "returns self for method chaining" do
      result = span.unknown_method.another_unknown_method
      expect(result).to eq(span)
    end

    it "executes block when provided" do
      block_executed = false
      span.unknown_method { block_executed = true }
      expect(block_executed).to be(true)
    end
  end

  describe "#respond_to_missing?" do
    it "responds to any method" do
      expect(span.respond_to?(:any_method_name)).to be(true)
      expect(span.respond_to?(:another_method, true)).to be(true)
    end
  end

  describe "string representation" do
    describe "#to_s" do
      it "provides meaningful string representation" do
        str = span.to_s
        expect(str).to include("RAAF::Tracing::NoOpSpan")
        expect(str).to include("disabled")
      end
    end

    describe "#inspect" do
      it "matches to_s output" do
        expect(span.inspect).to eq(span.to_s)
      end
    end
  end

  describe "method chaining" do
    it "supports fluent interface patterns" do
      result = span
        .set_attribute("key1", "value1")
        .set_attribute("key2", "value2")
        .add_event("event1")
        .set_status(:ok)
        .record_exception(StandardError.new)
        
      expect(result).to eq(span)
    end
  end

  describe "performance characteristics" do
    it "has minimal memory footprint" do
      # Verify that NoOpSpan doesn't accumulate state
      initial_attributes = span.attributes
      initial_events = span.events
      
      100.times do |i|
        span.set_attribute("key_#{i}", "value_#{i}")
        span.add_event("event_#{i}")
      end
      
      expect(span.attributes).to be(initial_attributes)
      expect(span.events).to be(initial_events)
    end
  end
end
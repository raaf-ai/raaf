# frozen_string_literal: true

require 'spec_helper'
require 'raaf/tracing/spans'

RSpec.describe RAAF::Tracing::Spans do
  describe RAAF::Tracing::Span do
    let(:span_name) { "test.operation" }
    let(:trace_id) { "trace_abc123" }
    let(:parent_id) { "span_parent123" }

    describe "#initialize" do
      context "with minimal parameters" do
        subject(:span) { described_class.new(name: span_name) }

        it "creates a span with auto-generated IDs" do
          expect(span.span_id).to match(/^span_[a-f0-9]{24}$/)
          expect(span.trace_id).to match(/^trace_[a-f0-9]{32}$/)
          expect(span.name).to eq(span_name)
          expect(span.kind).to eq(:internal)
          expect(span.parent_id).to be_nil
        end

        it "sets initial timestamps and state" do
          freeze_time = Time.now.utc
          allow(Time).to receive(:now).and_return(freeze_time)

          span = described_class.new(name: span_name)

          expect(span.start_time).to eq(freeze_time)
          expect(span.end_time).to be_nil
          expect(span.attributes).to eq({})
          expect(span.events).to eq([])
          expect(span.status).to eq(:ok)
          expect(span.finished?).to be(false)
        end
      end

      context "with all parameters" do
        subject(:span) do
          described_class.new(
            name: span_name,
            trace_id: trace_id,
            parent_id: parent_id,
            kind: :pipeline
          )
        end

        it "uses provided parameters" do
          expect(span.span_id).to match(/^span_[a-f0-9]{24}$/)
          expect(span.trace_id).to eq(trace_id)
          expect(span.parent_id).to eq(parent_id)
          expect(span.name).to eq(span_name)
          expect(span.kind).to eq(:pipeline)
        end
      end

      context "with different span kinds" do
        it "accepts all documented span kinds" do
          kinds = [:pipeline, :agent, :llm, :tool, :handoff, :custom, :internal]

          kinds.each do |kind|
            span = described_class.new(name: span_name, kind: kind)
            expect(span.kind).to eq(kind)
          end
        end
      end
    end

    describe "#set_attribute" do
      subject(:span) { described_class.new(name: span_name) }

      it "sets string attributes" do
        span.set_attribute("key", "value")
        expect(span.attributes["key"]).to eq("value")
      end

      it "sets numeric attributes" do
        span.set_attribute("count", 42)
        expect(span.attributes["count"]).to eq(42)
      end

      it "converts symbol keys to strings" do
        span.set_attribute(:symbol_key, "value")
        expect(span.attributes["symbol_key"]).to eq("value")
      end

      it "returns self for method chaining" do
        result = span.set_attribute("key", "value")
        expect(result).to be(span)
      end

      it "overwrites existing attributes" do
        span.set_attribute("key", "value1")
        span.set_attribute("key", "value2")
        expect(span.attributes["key"]).to eq("value2")
      end
    end

    describe "#attributes=" do
      subject(:span) { described_class.new(name: span_name) }

      it "sets multiple attributes at once" do
        attrs = {
          "http.method" => "POST",
          "http.status_code" => 200,
          "user.id" => 123
        }

        span.attributes = attrs

        expect(span.attributes["http.method"]).to eq("POST")
        expect(span.attributes["http.status_code"]).to eq(200)
        expect(span.attributes["user.id"]).to eq(123)
      end

      it "converts symbol keys to strings" do
        attrs = { method: "GET", status: 404 }
        span.attributes = attrs

        expect(span.attributes["method"]).to eq("GET")
        expect(span.attributes["status"]).to eq(404)
      end
    end

    describe "#add_event" do
      subject(:span) { described_class.new(name: span_name) }

      it "adds event with name only" do
        span.add_event("cache.miss")

        expect(span.events).to have(1).event
        event = span.events.first
        expect(event[:name]).to eq("cache.miss")
        expect(event[:attributes]).to eq({})
        expect(event[:timestamp]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
      end

      it "adds event with attributes" do
        span.add_event("retry.attempt", attributes: { attempt: 2, delay: 1000 })

        event = span.events.first
        expect(event[:name]).to eq("retry.attempt")
        expect(event[:attributes]).to eq({ attempt: 2, delay: 1000 })
      end

      it "adds event with custom timestamp" do
        custom_time = Time.now.utc - 3600
        span.add_event("past.event", timestamp: custom_time.iso8601)

        event = span.events.first
        expect(event[:timestamp]).to eq(custom_time.iso8601)
      end

      it "returns self for method chaining" do
        result = span.add_event("test")
        expect(result).to be(span)
      end

      it "adds multiple events in order" do
        span.add_event("first")
        span.add_event("second")
        span.add_event("third")

        expect(span.events.map { |e| e[:name] }).to eq(["first", "second", "third"])
      end
    end

    describe "#set_status" do
      subject(:span) { described_class.new(name: span_name) }

      it "sets status without description" do
        span.set_status(:error)

        expect(span.status).to eq(:error)
        expect(span.attributes["status.description"]).to be_nil
      end

      it "sets status with description" do
        span.set_status(:error, description: "Connection timeout")

        expect(span.status).to eq(:error)
        expect(span.attributes["status.description"]).to eq("Connection timeout")
      end

      it "returns self for method chaining" do
        result = span.set_status(:ok)
        expect(result).to be(span)
      end

      context "with different status values" do
        it "accepts :ok status" do
          span.set_status(:ok)
          expect(span.status).to eq(:ok)
        end

        it "accepts :error status" do
          span.set_status(:error)
          expect(span.status).to eq(:error)
        end

        it "accepts :cancelled status" do
          span.set_status(:cancelled)
          expect(span.status).to eq(:cancelled)
        end
      end
    end

    describe "#finish" do
      subject(:span) { described_class.new(name: span_name) }

      it "marks span as finished and sets end time" do
        freeze_time = Time.now.utc
        allow(Time).to receive(:now).and_return(freeze_time)

        span.finish

        expect(span.finished?).to be(true)
        expect(span.end_time).to eq(freeze_time)
      end

      it "calculates and stores duration" do
        start_time = Time.now.utc
        allow(Time).to receive(:now).and_return(start_time)

        span = described_class.new(name: span_name)

        end_time = start_time + 1.5 # 1.5 seconds later
        span.finish(end_time: end_time)

        expect(span.attributes["duration_ms"]).to eq(1500.0)
      end

      it "accepts custom end time" do
        custom_end_time = Time.now.utc + 100
        span.finish(end_time: custom_end_time)

        expect(span.end_time).to eq(custom_end_time)
      end

      it "returns self for method chaining" do
        result = span.finish
        expect(result).to be(span)
      end

      it "does not overwrite finish if called multiple times" do
        first_end_time = Time.now.utc
        span.finish(end_time: first_end_time)

        second_end_time = first_end_time + 1000
        span.finish(end_time: second_end_time)

        expect(span.end_time).to eq(first_end_time)
      end
    end

    describe "#duration" do
      subject(:span) { described_class.new(name: span_name) }

      it "returns nil for unfinished span" do
        expect(span.duration).to be_nil
      end

      it "calculates duration for finished span" do
        start_time = Time.now.utc
        allow(Time).to receive(:now).and_return(start_time)

        span = described_class.new(name: span_name)

        end_time = start_time + 2.5
        span.finish(end_time: end_time)

        expect(span.duration).to eq(2.5)
      end
    end

    describe "#to_h" do
      subject(:span) { described_class.new(name: span_name, trace_id: trace_id, parent_id: parent_id, kind: :agent) }

      before do
        span.set_attribute("test.key", "test.value")
        span.add_event("test.event", attributes: { count: 5 })
        span.set_status(:error, description: "Test error")
        span.finish
      end

      it "returns complete span data as hash" do
        hash = span.to_h

        expect(hash).to include(
          span_id: span.span_id,
          trace_id: trace_id,
          parent_id: parent_id,
          name: span_name,
          kind: :agent,
          start_time: span.start_time.iso8601,
          end_time: span.end_time.iso8601,
          status: :error
        )

        expect(hash[:duration_ms]).to be_a(Float)
        expect(hash[:attributes]).to include("test.key" => "test.value", "status.description" => "Test error")
        expect(hash[:events]).to have(1).event
        expect(hash[:events].first[:name]).to eq("test.event")
      end
    end

    describe "#to_json" do
      subject(:span) { described_class.new(name: span_name) }

      it "returns valid JSON representation" do
        span.set_attribute("key", "value")
        span.finish

        json_str = span.to_json
        parsed = JSON.parse(json_str)

        expect(parsed["name"]).to eq(span_name)
        expect(parsed["attributes"]["key"]).to eq("value")
      end
    end
  end

  describe RAAF::Tracing::SpanContext do
    subject(:context) { described_class.new }

    describe "#initialize" do
      it "initializes with empty state" do
        expect(context.current_span).to be_nil
        expect(context.trace_id).to be_nil
      end
    end

    describe "#start_span" do
      it "creates and tracks a new span" do
        span = context.start_span("test.operation", kind: :agent)

        expect(span).to be_a(RAAF::Tracing::Span)
        expect(span.name).to eq("test.operation")
        expect(span.kind).to eq(:agent)
        expect(context.current_span).to eq(span)
        expect(context.trace_id).to eq(span.trace_id)
      end

      it "creates child spans with proper parent relationship" do
        parent_span = context.start_span("parent", kind: :pipeline)
        child_span = context.start_span("child", kind: :agent)

        expect(child_span.parent_id).to eq(parent_span.span_id)
        expect(child_span.trace_id).to eq(parent_span.trace_id)
      end

      it "executes block and finishes span automatically" do
        result = context.start_span("test") do |span|
          span.set_attribute("test", "value")
          "block_result"
        end

        expect(result).to eq("block_result")
        expect(context.current_span).to be_nil # Should be popped after block
      end

      it "maintains span stack for nested operations" do
        outer_result = context.start_span("outer") do |outer_span|
          expect(context.current_span).to eq(outer_span)

          inner_result = context.start_span("inner") do |inner_span|
            expect(context.current_span).to eq(inner_span)
            expect(inner_span.parent_id).to eq(outer_span.span_id)
            "inner_result"
          end

          expect(context.current_span).to eq(outer_span) # Should be restored
          inner_result
        end

        expect(outer_result).to eq("inner_result")
        expect(context.current_span).to be_nil
      end
    end

    describe "#finish_span" do
      it "finishes current span when no span provided" do
        span = context.start_span("test")
        expect(span.finished?).to be(false)

        finished_span = context.finish_span

        expect(finished_span).to eq(span)
        expect(span.finished?).to be(true)
        expect(context.current_span).to be_nil
      end

      it "finishes specific span" do
        span1 = context.start_span("span1")
        span2 = context.start_span("span2")

        finished_span = context.finish_span(span1)

        expect(finished_span).to eq(span1)
        expect(span1.finished?).to be(true)
        expect(context.current_span).to eq(span2) # Should not affect current span
      end
    end

    describe "#all_spans" do
      it "returns all created spans" do
        span1 = context.start_span("span1")
        span2 = context.start_span("span2")
        context.finish_span(span1)

        all_spans = context.all_spans
        expect(all_spans).to contain_exactly(span1, span2)
      end

      it "returns copy to prevent external modification" do
        span = context.start_span("test")
        spans_copy = context.all_spans
        spans_copy.clear

        expect(context.all_spans).to contain_exactly(span)
      end
    end

    describe "#clear" do
      it "clears all state" do
        context.start_span("test1")
        context.start_span("test2")

        context.clear

        expect(context.current_span).to be_nil
        expect(context.trace_id).to be_nil
        expect(context.all_spans).to be_empty
      end
    end

    describe "#trace_summary" do
      it "returns nil for empty trace" do
        expect(context.trace_summary).to be_nil
      end

      it "provides comprehensive trace summary" do
        freeze_time = Time.now.utc
        allow(Time).to receive(:now).and_return(freeze_time)

        root_span = context.start_span("root")
        context.start_span("child1")
        context.finish_span # finish child1
        context.start_span("child2")
        context.finish_span # finish child2
        context.finish_span(root_span)

        summary = context.trace_summary

        expect(summary).to include(
          trace_id: context.trace_id,
          total_spans: 3,
          root_spans: 1,
          status: :ok,
          start_time: freeze_time.iso8601,
          end_time: freeze_time.iso8601
        )
        expect(summary[:total_duration_ms]).to be_a(Float)
      end

      it "shows error status when any span has error" do
        context.start_span("success") { |span| span.set_status(:ok) }
        context.start_span("failure") { |span| span.set_status(:error) }

        summary = context.trace_summary
        expect(summary[:status]).to eq(:error)
      end
    end
  end

  describe RAAF::Tracing::SpanTracer do
    let(:tracer) { described_class.new }

    describe "#initialize" do
      it "initializes with empty state" do
        expect(tracer.context).to be_a(RAAF::Tracing::SpanContext)
        expect(tracer.processors).to be_empty
      end

      it "accepts optional provider" do
        provider = double("TraceProvider")
        tracer = described_class.new(provider)

        expect(tracer.instance_variable_get(:@provider)).to eq(provider)
      end
    end

    describe "#add_processor" do
      it "adds processors to the list" do
        processor1 = double("Processor1")
        processor2 = double("Processor2")

        tracer.add_processor(processor1)
        tracer.add_processor(processor2)

        expect(tracer.processors).to contain_exactly(processor1, processor2)
      end
    end

    describe "#start_span" do
      let(:processor) { double("Processor", on_span_start: nil, on_span_end: nil) }

      before { tracer.add_processor(processor) }

      it "creates span and notifies processors" do
        expect(processor).to receive(:on_span_start).with(kind_of(RAAF::Tracing::Span))

        span = tracer.start_span("test.operation", kind: :agent, custom_attr: "value")

        expect(span.name).to eq("test.operation")
        expect(span.kind).to eq(:agent)
        expect(span.attributes["custom_attr"]).to eq("value")
      end

      it "executes block and handles success" do
        expect(processor).to receive(:on_span_start)
        expect(processor).to receive(:on_span_end)

        result = tracer.start_span("test") do |span|
          span.set_attribute("executed", true)
          "success_result"
        end

        expect(result).to eq("success_result")
      end

      it "handles exceptions and sets error status" do
        expect(processor).to receive(:on_span_start)
        expect(processor).to receive(:on_span_end) do |span|
          expect(span.status).to eq(:error)
          expect(span.attributes["status.description"]).to include("Test error")
        end

        expect do
          tracer.start_span("test") do |span|
            raise StandardError, "Test error"
          end
        end.to raise_error(StandardError, "Test error")
      end

      it "captures exception details in span" do
        exception_span = nil

        expect(processor).to receive(:on_span_end) do |span|
          exception_span = span
        end

        expect do
          tracer.start_span("test") do
            raise ArgumentError, "Invalid argument"
          end
        end.to raise_error(ArgumentError)

        expect(exception_span.events).to have(1).event
        event = exception_span.events.first
        expect(event[:name]).to eq("exception")
        expect(event[:attributes]["exception.type"]).to eq("ArgumentError")
        expect(event[:attributes]["exception.message"]).to eq("Invalid argument")
        expect(event[:attributes]["exception.stacktrace"]).to be_a(String)
      end
    end

    describe "convenience span methods" do
      let(:processor) { double("Processor", on_span_start: nil, on_span_end: nil) }

      before { tracer.add_processor(processor) }

      describe "#pipeline_span" do
        it "creates pipeline span with correct attributes" do
          expect(processor).to receive(:on_span_start) do |span|
            expect(span.name).to eq("pipeline.TestPipeline")
            expect(span.kind).to eq(:pipeline)
            expect(span.attributes["pipeline.name"]).to eq("TestPipeline")
          end

          tracer.pipeline_span("TestPipeline", agent_count: 3) do |span|
            expect(span.attributes["agent_count"]).to eq(3)
          end
        end

        it "includes additional pipeline attributes" do
          result = nil
          tracer.pipeline_span("DataPipeline",
                               agent_count: 2,
                               flow_structure: "Agent1 >> Agent2",
                               execution_mode: "sequential") do |span|
            expect(span.attributes["pipeline.name"]).to eq("DataPipeline")
            expect(span.attributes["agent_count"]).to eq(2)
            expect(span.attributes["flow_structure"]).to eq("Agent1 >> Agent2")
            expect(span.attributes["execution_mode"]).to eq("sequential")
            result = "pipeline_result"
          end

          expect(result).to eq("pipeline_result")
        end

        it "creates pipeline span without block" do
          expect(processor).to receive(:on_span_start) do |span|
            expect(span.name).to eq("pipeline.ManualPipeline")
            expect(span.kind).to eq(:pipeline)
            expect(span.attributes["pipeline.name"]).to eq("ManualPipeline")
          end

          span = tracer.pipeline_span("ManualPipeline", timeout: 30)
          expect(span).to be_a(RAAF::Tracing::Span)
          expect(span.attributes["timeout"]).to eq(30)
          expect(span.finished?).to be(false)
        end

        it "automatically finishes span when block is provided" do
          span_ref = nil
          tracer.pipeline_span("AutoFinishPipeline") do |span|
            span_ref = span
            expect(span.finished?).to be(false)
          end

          expect(span_ref.finished?).to be(true)
        end

        it "propagates exceptions while finishing span" do
          span_ref = nil
          expect do
            tracer.pipeline_span("ErrorPipeline") do |span|
              span_ref = span
              raise StandardError, "test error"
            end
          end.to raise_error(StandardError, "test error")

          expect(span_ref.finished?).to be(true)
          expect(span_ref.status).to eq(:error)
        end

        it "accepts empty pipeline name" do
          expect(processor).to receive(:on_span_start) do |span|
            expect(span.name).to eq("pipeline.")
            expect(span.attributes["pipeline.name"]).to eq("")
          end

          tracer.pipeline_span("") { }
        end

        it "handles complex pipeline attributes" do
          complex_config = {
            retry_config: { max_attempts: 3, backoff: "exponential" },
            timeout_config: { default: 30, max: 300 },
            agent_list: ["Agent1", "Agent2", "Agent3"]
          }

          tracer.pipeline_span("ComplexPipeline", **complex_config) do |span|
            expect(span.attributes["retry_config"]).to eq(complex_config[:retry_config])
            expect(span.attributes["timeout_config"]).to eq(complex_config[:timeout_config])
            expect(span.attributes["agent_list"]).to eq(complex_config[:agent_list])
          end
        end
      end

      describe "#agent_span" do
        it "creates agent span with correct attributes" do
          expect(processor).to receive(:on_span_start) do |span|
            expect(span.name).to eq("agent.TestAgent")
            expect(span.kind).to eq(:agent)
            expect(span.attributes["agent.name"]).to eq("TestAgent")
          end

          tracer.agent_span("TestAgent", version: "1.0") do |span|
            expect(span.attributes["version"]).to eq("1.0")
          end
        end
      end

      describe "#tool_span" do
        it "creates tool span with correct attributes" do
          expect(processor).to receive(:on_span_start) do |span|
            expect(span.name).to eq("tool.web_search")
            expect(span.kind).to eq(:tool)
            expect(span.attributes["tool.name"]).to eq("web_search")
          end

          tracer.tool_span("web_search") { }
        end
      end

      describe "#http_span" do
        it "creates HTTP span with correct attributes" do
          expect(processor).to receive(:on_span_start) do |span|
            expect(span.name).to eq("POST /v1/responses")
            expect(span.kind).to eq(:llm)
          end

          tracer.http_span("POST /v1/responses") { }
        end
      end

      describe "#handoff_span" do
        it "creates handoff span with correct attributes" do
          expect(processor).to receive(:on_span_start) do |span|
            expect(span.name).to eq("handoff")
            expect(span.kind).to eq(:handoff)
            expect(span.attributes["handoff.from"]).to eq("Agent1")
            expect(span.attributes["handoff.to"]).to eq("Agent2")
          end

          tracer.handoff_span("Agent1", "Agent2") { }
        end
      end

      describe "#custom_span" do
        it "creates custom span with data" do
          expect(processor).to receive(:on_span_start) do |span|
            expect(span.name).to eq("custom.validation")
            expect(span.kind).to eq(:custom)
            expect(span.attributes["custom.name"]).to eq("validation")
            expect(span.attributes["custom.data"]).to eq({ records: 100 })
          end

          tracer.custom_span("validation", { records: 100 }) { }
        end
      end
    end

    describe "#current_span" do
      it "returns current active span" do
        span = nil
        tracer.start_span("test") do |s|
          span = s
          expect(tracer.current_span).to eq(s)
        end

        expect(tracer.current_span).to be_nil # Should be nil after block
      end
    end

    describe "#add_event" do
      it "adds event to current span" do
        tracer.start_span("test") do |span|
          tracer.add_event("cache.hit", key: "user:123", size: 1024)

          expect(span.events).to have(1).event
          event = span.events.first
          expect(event[:name]).to eq("cache.hit")
          expect(event[:attributes]).to eq({ key: "user:123", size: 1024 })
        end
      end

      it "does nothing when no current span" do
        expect { tracer.add_event("test") }.not_to raise_error
      end
    end

    describe "#set_attribute" do
      it "sets attribute on current span" do
        tracer.start_span("test") do |span|
          tracer.set_attribute("user.id", 123)
          expect(span.attributes["user.id"]).to eq(123)
        end
      end

      it "does nothing when no current span" do
        expect { tracer.set_attribute("key", "value") }.not_to raise_error
      end
    end

    describe "#export_spans" do
      before do
        tracer.start_span("span1") { |s| s.set_attribute("key1", "value1") }
        tracer.start_span("span2") { |s| s.set_attribute("key2", "value2") }
      end

      it "exports spans as JSON by default" do
        json_data = tracer.export_spans

        expect(json_data).to be_a(String)
        parsed = JSON.parse(json_data)

        expect(parsed["trace_id"]).to be_a(String)
        expect(parsed["spans"]).to have(2).spans
        expect(parsed["summary"]).to be_a(Hash)
      end

      it "exports spans as hash when requested" do
        hash_data = tracer.export_spans(format: :hash)

        expect(hash_data).to be_a(Hash)
        expect(hash_data[:trace_id]).to be_a(String)
        expect(hash_data[:spans]).to have(2).spans
        expect(hash_data[:summary]).to be_a(Hash)
      end

      it "raises error for unsupported format" do
        expect { tracer.export_spans(format: :xml) }.to raise_error(ArgumentError, /Unsupported format/)
      end
    end

    describe "#trace_summary" do
      it "delegates to context" do
        summary = { trace_id: "test", total_spans: 0 }
        allow(tracer.context).to receive(:trace_summary).and_return(summary)

        expect(tracer.trace_summary).to eq(summary)
      end
    end

    describe "#clear" do
      it "clears context state" do
        tracer.start_span("test")
        tracer.clear

        expect(tracer.current_span).to be_nil
        expect(tracer.context.all_spans).to be_empty
      end
    end

    describe "#flush" do
      it "calls flush on processors that support it" do
        flushable_processor = double("FlushableProcessor")
        allow(flushable_processor).to receive(:respond_to?).with(:flush).and_return(true)
        expect(flushable_processor).to receive(:flush)

        non_flushable_processor = double("NonFlushableProcessor")
        allow(non_flushable_processor).to receive(:respond_to?).with(:flush).and_return(false)

        tracer.add_processor(flushable_processor)
        tracer.add_processor(non_flushable_processor)

        tracer.flush
      end
    end

    describe "#record_exception" do
      it "records exception on current span" do
        tracer.start_span("test") do |span|
          exception = StandardError.new("Test error")
          tracer.record_exception(exception)

          expect(span.status).to eq(:error)
          expect(span.attributes["status.description"]).to eq("Test error")
          expect(span.events).to have(1).event

          event = span.events.first
          expect(event[:name]).to eq("exception")
          expect(event[:attributes]["exception.type"]).to eq("StandardError")
          expect(event[:attributes]["exception.message"]).to eq("Test error")
        end
      end

      it "does nothing when no current span" do
        exception = StandardError.new("Test error")
        expect { tracer.record_exception(exception) }.not_to raise_error
      end
    end

    describe "processor error handling" do
      it "handles processor errors gracefully" do
        failing_processor = double("FailingProcessor")
        allow(failing_processor).to receive(:respond_to?).with(:on_span_start).and_return(true)
        allow(failing_processor).to receive(:on_span_start).and_raise(StandardError, "Processor error")

        tracer.add_processor(failing_processor)

        # Should not raise error
        expect { tracer.start_span("test") }.not_to raise_error
      end
    end
  end

  describe "Processor Classes" do
    describe RAAF::Tracing::ConsoleSpanProcessor do
      let(:processor) { described_class.new }
      let(:span) { RAAF::Tracing::Span.new(name: "test.span", kind: :agent) }

      describe "#on_span_start" do
        it "logs span start event" do
          # Note: We can't easily test actual logging output without mocking the logger
          # This test ensures the method exists and doesn't raise errors
          expect { processor.on_span_start(span) }.not_to raise_error
        end
      end

      describe "#on_span_end" do
        it "logs span end event with duration" do
          span.finish
          expect { processor.on_span_end(span) }.not_to raise_error
        end

        it "logs error details for failed spans" do
          span.set_status(:error, description: "Test failure")
          span.finish
          expect { processor.on_span_end(span) }.not_to raise_error
        end
      end
    end

    describe RAAF::Tracing::FileSpanProcessor do
      let(:temp_file) { "/tmp/test_spans_#{SecureRandom.hex(8)}.jsonl" }
      let(:processor) { described_class.new(temp_file) }
      let(:span) { RAAF::Tracing::Span.new(name: "test.span") }

      after { File.delete(temp_file) if File.exist?(temp_file) }

      describe "#on_span_start" do
        it "writes span start event to file" do
          processor.on_span_start(span)

          expect(File.exist?(temp_file)).to be(true)
          content = File.read(temp_file)
          event_data = JSON.parse(content.lines.last)

          expect(event_data["event"]).to eq("start")
          expect(event_data["span"]["name"]).to eq("test.span")
        end
      end

      describe "#on_span_end" do
        it "writes span end event to file" do
          span.finish
          processor.on_span_end(span)

          content = File.read(temp_file)
          event_data = JSON.parse(content.lines.last)

          expect(event_data["event"]).to eq("end")
          expect(event_data["span"]["name"]).to eq("test.span")
          expect(event_data["span"]["end_time"]).not_to be_nil
        end
      end
    end

    describe RAAF::Tracing::MemorySpanProcessor do
      let(:processor) { described_class.new }
      let(:span) { RAAF::Tracing::Span.new(name: "test.span") }

      describe "#initialize" do
        it "starts with empty spans collection" do
          expect(processor.spans).to be_empty
        end
      end

      describe "#on_span_start" do
        it "does not collect spans on start" do
          processor.on_span_start(span)
          expect(processor.spans).to be_empty
        end
      end

      describe "#on_span_end" do
        it "collects span data on end" do
          span.set_attribute("test", "value")
          span.finish

          processor.on_span_end(span)

          expect(processor.spans).to have(1).span
          span_data = processor.spans.first
          expect(span_data[:name]).to eq("test.span")
          expect(span_data[:attributes]["test"]).to eq("value")
        end
      end

      describe "#clear" do
        it "removes all collected spans" do
          span.finish
          processor.on_span_end(span)

          processor.clear
          expect(processor.spans).to be_empty
        end
      end
    end
  end
end
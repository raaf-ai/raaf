# frozen_string_literal: true

require "spec_helper"

# Skip Rails-specific tests if Rails is not available
begin
  require "rails"
  require "active_record"
  require_relative "../../../../app/models/openai_agents/tracing/trace"
  require_relative "../../../../app/models/openai_agents/tracing/span"
  
  # Check if database connection is available
  ActiveRecord::Base.connection.migration_context.current_version
rescue LoadError, ActiveRecord::ConnectionNotDefined, ActiveRecord::NoDatabaseError => e
  puts "Skipping Rails tests: #{e.message}"
  return
end

RSpec.describe "Rails Tracing Models" do
  describe OpenAIAgents::Tracing::TraceRecord do
    let(:trace_id) { "trace_#{SecureRandom.alphanumeric(32)}" }
    let(:trace) do
      described_class.create!(
        trace_id: trace_id,
        workflow_name: "Test Workflow",
        status: "completed",
        started_at: 1.hour.ago,
        ended_at: 30.minutes.ago
      )
    end

    describe "validations" do
      it "validates trace_id format" do
        invalid_trace = described_class.new(trace_id: "invalid_format")
        expect(invalid_trace).not_to be_valid
        expect(invalid_trace.errors[:trace_id]).to include(/must be in format/)
      end

      it "requires workflow_name" do
        trace = described_class.new(trace_id: trace_id)
        expect(trace).not_to be_valid
        expect(trace.errors[:workflow_name]).to include("can't be blank")
      end

      it "validates status inclusion" do
        trace = described_class.new(trace_id: trace_id, workflow_name: "Test", status: "invalid")
        expect(trace).not_to be_valid
        expect(trace.errors[:status]).to include("is not included in the list")
      end

      it "ensures unique trace_id" do
        described_class.create!(trace_id: trace_id, workflow_name: "Test")
        duplicate = described_class.new(trace_id: trace_id, workflow_name: "Test 2")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:trace_id]).to include("has already been taken")
      end
    end

    describe "callbacks" do
      it "generates trace_id if not provided" do
        trace = described_class.create!(workflow_name: "Test")
        expect(trace.trace_id).to match(/\Atrace_[a-zA-Z0-9]{32}\z/)
      end

      it "sets default status" do
        trace = described_class.create!(workflow_name: "Test")
        expect(trace.status).to eq("pending")
      end
    end

    describe "scopes" do
      let!(:completed_trace) { described_class.create!(workflow_name: "Completed", status: "completed") }
      let!(:failed_trace) { described_class.create!(workflow_name: "Failed", status: "failed") }
      let!(:old_trace) { described_class.create!(workflow_name: "Old", started_at: 2.days.ago) }

      it "filters by status" do
        expect(described_class.completed).to include(completed_trace)
        expect(described_class.completed).not_to include(failed_trace)
      end

      it "filters by workflow" do
        expect(described_class.by_workflow("Completed")).to include(completed_trace)
        expect(described_class.by_workflow("Completed")).not_to include(failed_trace)
      end

      it "filters by timeframe" do
        recent_traces = described_class.within_timeframe(1.day.ago, Time.current)
        expect(recent_traces).to include(completed_trace)
        expect(recent_traces).not_to include(old_trace)
      end
    end

    describe "#duration_ms" do
      it "calculates duration in milliseconds" do
        expect(trace.duration_ms).to be_within(1000).of(30 * 60 * 1000) # ~30 minutes
      end

      it "returns nil if not completed" do
        incomplete_trace = described_class.create!(workflow_name: "Incomplete", started_at: 1.hour.ago)
        expect(incomplete_trace.duration_ms).to be_nil
      end
    end

    describe "#performance_summary" do
      let!(:span1) { create_span(trace, "span1", kind: "llm", duration_ms: 1000, status: "ok") }
      let!(:span2) { create_span(trace, "span2", kind: "tool", duration_ms: 500, status: "error") }

      it "returns comprehensive performance metrics" do
        summary = trace.performance_summary
        
        expect(summary[:total_duration_ms]).to eq(trace.duration_ms)
        expect(summary[:total_spans]).to eq(2)
        expect(summary[:success_rate]).to eq(50.0) # 1 success out of 2
        expect(summary[:span_breakdown]).to have_key("llm")
        expect(summary[:span_breakdown]).to have_key("tool")
      end
    end

    describe "#cost_analysis" do
      before do
        create_span(trace, "llm_span", kind: "llm", span_attributes: {
                      "llm" => {
                        "usage" => { "prompt_tokens" => 100, "completion_tokens" => 50 },
                        "request" => { "model" => "gpt-4o" }
                      }
                    })
      end

      it "calculates token usage" do
        analysis = trace.cost_analysis
        
        expect(analysis[:total_input_tokens]).to eq(100)
        expect(analysis[:total_output_tokens]).to eq(50)
        expect(analysis[:total_tokens]).to eq(150)
        expect(analysis[:llm_calls]).to eq(1)
        expect(analysis[:models_used]).to include("gpt-4o")
      end
    end

    describe ".performance_stats" do
      let!(:trace1) { described_class.create!(workflow_name: "Test", status: "completed", started_at: 2.hours.ago, ended_at: 1.hour.ago) }
      let!(:trace2) { described_class.create!(workflow_name: "Test", status: "failed", started_at: 3.hours.ago, ended_at: 2.hours.ago) }

      it "calculates aggregate statistics" do
        stats = described_class.performance_stats
        
        expect(stats[:total_traces]).to be >= 2
        expect(stats[:completed_traces]).to be >= 1
        expect(stats[:failed_traces]).to be >= 1
        expect(stats[:success_rate]).to be_a(Numeric)
      end

      it "filters by workflow" do
        stats = described_class.performance_stats(workflow_name: "Test")
        expect(stats[:total_traces]).to eq(2)
      end
    end

    describe ".cleanup_old_traces" do
      let!(:old_trace) { described_class.create!(workflow_name: "Old", started_at: 2.months.ago) }
      let!(:recent_trace) { described_class.create!(workflow_name: "Recent", started_at: 1.day.ago) }

      it "deletes traces older than threshold" do
        expect do
          described_class.cleanup_old_traces(older_than: 1.month)
        end.to change { described_class.count }.by(-1)
        
        expect(described_class.exists?(old_trace.id)).to be false
        expect(described_class.exists?(recent_trace.id)).to be true
      end
    end

    private

    def create_span(trace, span_id, **attributes)
      OpenAIAgents::Tracing::Span.create!({
        span_id: span_id,
        trace_id: trace.trace_id,
        name: "test_span",
        kind: "internal",
        start_time: 1.hour.ago,
        end_time: 30.minutes.ago,
        status: "ok",
        span_attributes: {},
        events: []
      }.merge(attributes))
    end
  end

  describe OpenAIAgents::Tracing::SpanRecord do
    let(:trace) { OpenAIAgents::Tracing::TraceRecord.create!(workflow_name: "Test Trace") }
    let(:span_id) { "span_#{SecureRandom.hex(12)}" }
    let(:span) do
      described_class.create!(
        span_id: span_id,
        trace_id: trace.trace_id,
        name: "test_operation",
        kind: "llm",
        start_time: 1.hour.ago,
        end_time: 30.minutes.ago,
        duration_ms: 1_800_000, # 30 minutes
        status: "ok",
        attributes: {
          "llm.request.model" => "gpt-4o",
          "llm.usage.prompt_tokens" => 100
        },
        events: [
          { "name" => "started", "timestamp" => 1.hour.ago.iso8601 }
        ]
      )
    end

    describe "validations" do
      it "validates span_id format" do
        invalid_span = described_class.new(
          span_id: "invalid_format",
          trace_id: trace.trace_id,
          name: "test_span"
        )
        expect(invalid_span).not_to be_valid
        expect(invalid_span.errors[:span_id]).to include(/must be in format/)
      end

      it "validates trace_id format" do
        invalid_span = described_class.new(
          span_id: span_id,
          trace_id: "invalid_format",
          name: "test_span"
        )
        expect(invalid_span).not_to be_valid
        expect(invalid_span.errors[:trace_id]).to include(/must be in format/)
      end

      it "validates kind inclusion" do
        span = described_class.new(span_id: span_id, trace_id: trace.trace_id, name: "test", kind: "invalid")
        expect(span).not_to be_valid
        expect(span.errors[:kind]).to include("is not included in the list")
      end
    end

    describe "associations" do
      it "belongs to trace" do
        expect(span.trace).to eq(trace)
      end

      it "supports parent-child relationships" do
        parent_span = described_class.create!(
          span_id: "parent_#{SecureRandom.hex(12)}",
          trace_id: trace.trace_id,
          name: "parent",
          start_time: 2.hours.ago,
          end_time: 1.hour.ago
        )
        
        child_span = described_class.create!(
          span_id: "child_#{SecureRandom.hex(12)}",
          trace_id: trace.trace_id,
          parent_id: parent_span.span_id,
          name: "child",
          start_time: 90.minutes.ago,
          end_time: 70.minutes.ago
        )
        
        expect(child_span.parent_span).to eq(parent_span)
        expect(parent_span.children).to include(child_span)
      end
    end

    describe "scopes" do
      let!(:error_span) { described_class.create!(span_id: "error_#{SecureRandom.hex(12)}", trace_id: trace.trace_id, name: "error", status: "error", start_time: 1.hour.ago) }
      let!(:slow_span) { described_class.create!(span_id: "slow_#{SecureRandom.hex(12)}", trace_id: trace.trace_id, name: "slow", duration_ms: 5000, start_time: 1.hour.ago) }
      let!(:llm_span) { described_class.create!(span_id: "llm_#{SecureRandom.hex(12)}", trace_id: trace.trace_id, name: "llm", kind: "llm", start_time: 1.hour.ago) }

      it "filters by status" do
        expect(described_class.errors).to include(error_span)
        expect(described_class.successful).to include(span)
        expect(described_class.successful).not_to include(error_span)
      end

      it "filters by kind" do
        expect(described_class.by_kind("llm")).to include(span, llm_span)
        expect(described_class.by_kind("tool")).not_to include(span)
      end

      it "filters slow spans" do
        expect(described_class.slow(3000)).to include(slow_span)
        expect(described_class.slow(3000)).not_to include(span)
      end
    end

    describe "#duration_seconds" do
      it "converts milliseconds to seconds" do
        expect(span.duration_seconds).to eq(1800) # 30 minutes = 1800 seconds
      end
    end

    describe "#error_details" do
      let(:error_span) do
        described_class.create!(
          span_id: "error_#{SecureRandom.hex(12)}",
          trace_id: trace.trace_id,
          name: "error_operation",
          status: "error",
          start_time: 1.hour.ago,
          span_attributes: { "status.description" => "Connection timeout" },
          events: [
            {
              "name" => "exception",
              "attributes" => {
                "exception.type" => "TimeoutError",
                "exception.message" => "Request timed out",
                "exception.stacktrace" => 'at line 1\nat line 2'
              }
            }
          ]
        )
      end

      it "extracts error information" do
        details = error_span.error_details
        
        expect(details["status_description"]).to eq("Connection timeout")
        expect(details["exception_type"]).to eq("TimeoutError")
        expect(details["exception_message"]).to eq("Request timed out")
        expect(details["exception_stacktrace"]).to eq('at line 1\nat line 2')
      end

      it "returns nil for successful spans" do
        expect(span.error_details).to be_nil
      end
    end

    describe "#operation_details" do
      it "extracts LLM-specific details" do
        details = span.operation_details
        
        expect(details[:model]).to eq("gpt-4o")
        expect(details[:input_tokens]).to eq(100)
      end

      it "extracts tool-specific details" do
        tool_span = described_class.create!(
          span_id: "tool_#{SecureRandom.hex(12)}",
          trace_id: trace.trace_id,
          name: "tool_operation",
          kind: "tool",
          start_time: 1.hour.ago,
          span_attributes: {
            "function.name" => "get_weather",
            "function.input" => { "location" => "San Francisco" },
            "function.output" => "Sunny, 72°F"
          }
        )
        
        details = tool_span.operation_details
        expect(details[:function_name]).to eq("get_weather")
        expect(details[:input]).to eq({ "location" => "San Francisco" })
        expect(details[:output]).to eq("Sunny, 72°F")
      end
    end

    describe "#depth" do
      it "calculates span depth in hierarchy" do
        expect(span.depth).to eq(0) # Root span
        
        child_span = described_class.create!(
          span_id: "child_#{SecureRandom.hex(12)}",
          trace_id: trace.trace_id,
          parent_id: span.span_id,
          name: "child",
          start_time: 1.hour.ago
        )
        
        expect(child_span.depth).to eq(1)
      end
    end

    describe ".performance_metrics" do
      before do
        # Create test spans with known performance characteristics
        described_class.create!(span_id: "fast_#{SecureRandom.hex(12)}", trace_id: trace.trace_id, name: "fast", kind: "llm", duration_ms: 100, status: "ok", start_time: 1.hour.ago)
        described_class.create!(span_id: "slow_#{SecureRandom.hex(12)}", trace_id: trace.trace_id, name: "slow", kind: "llm", duration_ms: 2000, status: "ok", start_time: 1.hour.ago)
        described_class.create!(span_id: "error_#{SecureRandom.hex(12)}", trace_id: trace.trace_id, name: "error", kind: "llm", duration_ms: 500, status: "error", start_time: 1.hour.ago)
      end

      it "calculates performance statistics" do
        metrics = described_class.performance_metrics(kind: "llm")
        
        expect(metrics[:total_spans]).to be >= 3
        expect(metrics[:successful_spans]).to be >= 2
        expect(metrics[:error_spans]).to be >= 1
        expect(metrics[:avg_duration_ms]).to be_a(Numeric)
        expect(metrics[:success_rate]).to be_a(Numeric)
      end
    end

    describe ".cost_analysis" do
      before do
        described_class.create!(
          span_id: "cost_#{SecureRandom.hex(12)}",
          trace_id: trace.trace_id,
          name: "llm_call",
          kind: "llm",
          start_time: 1.hour.ago,
          span_attributes: {
            "llm" => {
              "usage" => { "prompt_tokens" => 200, "completion_tokens" => 100 },
              "request" => { "model" => "gpt-4o" }
            }
          }
        )
      end

      it "calculates cost metrics" do
        analysis = described_class.cost_analysis
        
        expect(analysis[:total_llm_calls]).to be >= 1
        expect(analysis[:total_input_tokens]).to be >= 200
        expect(analysis[:total_output_tokens]).to be >= 100
        expect(analysis[:models_usage]).to have_key("gpt-4o")
      end
    end
  end
end
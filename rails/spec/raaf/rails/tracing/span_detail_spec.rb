# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Rails::Tracing::SpanDetail::Component do
  # Create mock span classes for testing
  let(:mock_span_class) do
    Struct.new(
      :span_id, :trace_id, :parent_id, :name, :kind, :status,
      :start_time, :end_time, :duration_ms, :depth, :span_attributes,
      :children, :events, :error_details
    ) do
      def parent_span_id
        parent_id
      end
    end
  end

  let(:mock_trace_class) do
    Struct.new(:workflow_name)
  end

  # Basic span data
  let(:basic_span_attributes) do
    {
      "agent.name" => "TestAgent",
      "agent.model" => "gpt-4o",
      "input.query" => "test query",
      "output.response" => "test response"
    }
  end

  let(:basic_span) do
    mock_span_class.new(
      "span_123",
      "trace_456",
      "parent_789",
      "Agent.run",
      "agent",
      "completed",
      Time.parse("2025-09-25 10:00:00 UTC"),
      Time.parse("2025-09-25 10:00:02 UTC"),
      2000,
      1,
      basic_span_attributes,
      [],
      [],
      nil
    )
  end

  let(:basic_trace) do
    mock_trace_class.new("TestWorkflow")
  end

  let(:component) { described_class.new(span: basic_span, trace: basic_trace) }

  describe "#initialize" do
    it "accepts required span parameter" do
      component = described_class.new(span: basic_span)
      expect(component.instance_variable_get(:@span)).to eq(basic_span)
    end

    it "accepts optional trace parameter" do
      component = described_class.new(span: basic_span, trace: basic_trace)
      expect(component.instance_variable_get(:@trace)).to eq(basic_trace)
    end

    it "accepts optional operation_details parameter" do
      details = { operation: "test" }
      component = described_class.new(span: basic_span, operation_details: details)
      expect(component.instance_variable_get(:@operation_details)).to eq(details)
    end
  end

  describe "universal span overview rendering", :focus do
    let(:rendered_output) do
      # Simple string capture of component output
      component.call.to_s
    end

    context "when rendering span overview section" do
      it "displays span ID in monospace font" do
        expect(rendered_output).to include("span_123")
        # Check for monospace class in the rendered output
        expect(rendered_output).to include("font-mono")
      end

      it "displays trace ID with navigation link" do
        expect(rendered_output).to include("trace_456")
        expect(rendered_output).to include("/raaf/tracing/traces/trace_456")
      end

      it "displays parent span ID" do
        expect(rendered_output).to include("parent_789")
      end

      it "displays span name" do
        expect(rendered_output).to include("Agent.run")
      end

      it "displays span kind with proper badge" do
        expect(rendered_output).to include("agent")
        expect(rendered_output).to include("bg-blue-100")
        expect(rendered_output).to include("text-blue-800")
      end

      it "displays span status with proper badge" do
        expect(rendered_output).to include("completed")
        # Status badge should use SkippedBadgeTooltip component
        expect(rendered_output).to include("bg-green-100")
      end

      it "displays workflow name when trace is present" do
        expect(rendered_output).to include("TestWorkflow")
      end

      it "displays span depth" do
        expect(rendered_output).to include("1")
      end
    end

    context "when rendering timing information" do
      it "displays formatted start time" do
        expect(rendered_output).to include("2025-09-25 10:00:00.000 UTC")
      end

      it "displays formatted end time" do
        expect(rendered_output).to include("2025-09-25 10:00:02.000 UTC")
      end

      it "displays formatted duration" do
        expect(rendered_output).to include("2.0s")
      end

      it "includes time since start" do
        # Should include time_ago_in_words output
        expect(rendered_output).to include("ago")
      end
    end

    context "when span has no parent" do
      let(:root_span) do
        mock_span_class.new(
          "span_root",
          "trace_456",
          nil,
          "Root.span",
          "agent",
          "completed",
          Time.parse("2025-09-25 10:00:00 UTC"),
          Time.parse("2025-09-25 10:00:01 UTC"),
          1000,
          0,
          basic_span_attributes,
          [],
          [],
          nil
        )
      end

      let(:component) { described_class.new(span: root_span, trace: basic_trace) }

      it "displays 'None' for parent ID" do
        expect(rendered_output).to include("None")
      end

      it "displays depth as 0" do
        expect(rendered_output).to include("0")
      end
    end

    context "when trace is not provided" do
      let(:component) { described_class.new(span: basic_span) }

      it "does not display workflow information" do
        expect(rendered_output).not_to include("TestWorkflow")
      end

      it "does not display View Trace button" do
        expect(rendered_output).not_to include("View Trace")
      end
    end

    context "with different span statuses" do
      %w[completed failed running pending skipped cancelled].each do |status|
        it "renders #{status} status correctly" do
          span = basic_span.dup
          span.status = status
          component = described_class.new(span: span, trace: basic_trace)
          output = component.call.to_s

          expect(output).to include(status)
          # Each status should have appropriate color classes
          case status
          when "completed"
            expect(output).to include("bg-green-100")
          when "failed"
            expect(output).to include("bg-red-100")
          when "running", "pending"
            expect(output).to include("bg-yellow-100")
          when "skipped", "cancelled"
            expect(output).to include("bg-orange-100")
          end
        end
      end
    end

    context "with different span kinds" do
      %w[agent tool response span llm handoff guardrail pipeline].each do |kind|
        it "renders #{kind} kind badge correctly" do
          span = basic_span.dup
          span.kind = kind
          component = described_class.new(span: span, trace: basic_trace)
          output = component.call.to_s

          expect(output).to include(kind.capitalize)
          # Each kind should have appropriate color classes
          case kind
          when "agent"
            expect(output).to include("bg-blue-100")
          when "tool"
            expect(output).to include("bg-purple-100")
          when "response"
            expect(output).to include("bg-green-100")
          else
            expect(output).to include("bg-gray-100")
          end
        end
      end
    end

    context "with various duration ranges" do
      it "formats short durations in milliseconds" do
        span = basic_span.dup
        span.duration_ms = 150
        component = described_class.new(span: span)
        output = component.call.to_s
        expect(output).to include("150ms")
      end

      it "formats medium durations in seconds" do
        span = basic_span.dup
        span.duration_ms = 2500
        component = described_class.new(span: span)
        output = component.call.to_s
        expect(output).to include("2.5s")
      end

      it "formats long durations in minutes and seconds" do
        span = basic_span.dup
        span.duration_ms = 125000 # 2 minutes 5 seconds
        component = described_class.new(span: span)
        output = component.call.to_s
        expect(output).to include("2m 5.0s")
      end
    end
  end

  describe "hierarchy navigation" do
    let(:rendered_output) { component.call.to_s }

    it "includes navigation links to parent spans" do
      expect(rendered_output).to include("/raaf/tracing/spans/parent_789")
    end

    it "includes navigation links to trace" do
      expect(rendered_output).to include("/raaf/tracing/traces/trace_456")
    end

    it "includes Back to Spans navigation" do
      expect(rendered_output).to include("Back to Spans")
      expect(rendered_output).to include("/raaf/tracing/spans")
    end

    it "includes View Trace button when trace is present" do
      expect(rendered_output).to include("View Trace")
      expect(rendered_output).to include("bi-diagram-3")
    end
  end

  describe "responsive design classes" do
    let(:rendered_output) { component.call.to_s }

    it "uses responsive grid classes" do
      expect(rendered_output).to include("sm:grid-cols-2")
    end

    it "uses responsive flex classes" do
      expect(rendered_output).to include("sm:flex")
      expect(rendered_output).to include("sm:items-center")
    end

    it "uses responsive spacing classes" do
      expect(rendered_output).to include("sm:mt-0")
      expect(rendered_output).to include("sm:ml-4")
    end

    it "uses responsive text classes" do
      expect(rendered_output).to include("sm:text-3xl")
    end
  end

  describe "accessibility features" do
    let(:rendered_output) { component.call.to_s }

    it "includes proper heading hierarchy" do
      expect(rendered_output).to include("<h1")
      expect(rendered_output).to include("<h3")
    end

    it "includes proper semantic markup" do
      expect(rendered_output).to include("<dl")
      expect(rendered_output).to include("<dt")
      expect(rendered_output).to include("<dd")
    end

    it "includes descriptive text for screen readers" do
      expect(rendered_output).to include("Span Detail")
      expect(rendered_output).to include("Overview")
      expect(rendered_output).to include("Timing Information")
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Rails::Tracing::SpanDetail::Component do
  # The page reaches for Rails view helpers, so it is rendered with a view
  # context rather than called bare.
  include ComponentRendering

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

      # What the trace bar heads the page with -- SpanRecord derives it from the
      # payload, and a stand-in only has to have one.
      def display_name
        name
      end

      def error?
        status.to_s == "error"
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

  describe "universal span overview rendering" do
    let(:rendered_output) do
      # Simple string capture of component output
      render(component)
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
        expect(rendered_output).to include("raaf-kind--agent")
      end

      it "displays span status with proper badge" do
        expect(rendered_output).to include("completed")
        expect(rendered_output).to include("raaf-status--completed")
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
        expect(rendered_output).to include("2025-09-25 10:00:00")
      end

      it "displays formatted duration" do
        expect(rendered_output).to include("2.0s")
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

      it "says a root span has no parent" do
        expect(rendered_output).to include("none")
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

      it "does not display a workflow row" do
        expect(rendered_output).not_to include("TestWorkflow")
      end
    end

    context "with different span statuses" do
      %w[completed failed running pending skipped cancelled].each do |status|
        it "renders #{status} status correctly" do
          span = basic_span.dup
          span.status = status
          component = described_class.new(span: span, trace: basic_trace)
          output = render(component)

          expect(output).to include(status)
          # StatusBadge normalises the tracer's several words for each state
          # down to four pills.
          case status
          when "completed"
            expect(output).to include("raaf-status--completed")
          when "failed"
            expect(output).to include("raaf-status--failed")
          when "running", "pending"
            expect(output).to include("raaf-status--running")
          when "skipped", "cancelled"
            expect(output).to include("raaf-status--skipped")
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
          output = render(component)

          expect(output).to include(kind)
          # KindBadge owns the only kind-to-colour mapping, and folds the
          # tracer's aliases onto the six kinds it draws.
          expected = { "response" => "llm", "span" => "pipeline" }.fetch(kind, kind)
          expect(output).to include("raaf-kind--#{expected}")
        end
      end
    end

    context "with various duration ranges" do
      it "formats short durations in milliseconds" do
        span = basic_span.dup
        span.duration_ms = 150
        component = described_class.new(span: span)
        output = render(component)
        expect(output).to include("150ms")
      end

      it "formats medium durations in seconds" do
        span = basic_span.dup
        span.duration_ms = 2500
        component = described_class.new(span: span)
        output = render(component)
        expect(output).to include("2.5s")
      end

      it "formats long durations in minutes and seconds" do
        span = basic_span.dup
        span.duration_ms = 125_000 # 2 minutes 5 seconds
        component = described_class.new(span: span)
        output = render(component)
        expect(output).to include("2m 5.0s")
      end
    end
  end

  describe "hierarchy navigation" do
    let(:rendered_output) { render(component) }

    # A span is read inside its trace with itself selected -- there is no
    # span screen to link to.
    it "includes navigation links to parent spans" do
      expect(rendered_output).to include("/raaf/tracing/traces/trace_456?span=parent_789")
    end

    it "includes navigation links to trace" do
      expect(rendered_output).to include("/raaf/tracing/traces/trace_456")
    end

    it "names the workflow the trace belongs to" do
      expect(rendered_output).to include("Workflow")
      expect(rendered_output).to include("TestWorkflow")
    end
  end

  # The page is laid out by the console's own stylesheet rather than by utility
  # classes in the markup, so its structure is what there is to assert.
  describe "page layout" do
    let(:rendered_output) { render(component) }

    it "puts the span's identity in a trace bar" do
      expect(rendered_output).to include("raaf-trace-bar")
    end

    it "splits the inspector from the cards beside it" do
      expect(rendered_output).to include("raaf-trace-split")
      expect(rendered_output).to include("raaf-inspector")
    end
  end

  describe "accessibility features" do
    let(:rendered_output) { render(component) }

    it "includes proper heading hierarchy" do
      expect(rendered_output).to include("<h3")
    end

    it "includes proper semantic markup" do
      expect(rendered_output).to include("<section")
      expect(rendered_output).to include("<nav")
      expect(rendered_output).to include('role="tablist"')
      expect(rendered_output).to include("aria-selected")
    end

    it "includes descriptive text for screen readers" do
      expect(rendered_output).to include('aria-label="Span inspector"')
      expect(rendered_output).to include("Attributes")
      expect(rendered_output).to include("In its trace")
    end
  end
end

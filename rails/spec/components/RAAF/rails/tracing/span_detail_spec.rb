# frozen_string_literal: true

require "spec_helper"
require "phlex"
require "phlex/rails"
require "phlex/testing/view_helper"

# Load the component files
require_relative "../../../../../app/components/RAAF/rails/tracing/base_component"
require_relative "../../../../../app/components/RAAF/rails/tracing/span_detail"

module RAAF
  module Rails
    module Tracing
      RSpec.describe SpanDetail, type: :component do
        include Phlex::Testing::ViewHelper

        let(:base_span_attributes) do
          {
            "span_id" => "span_123",
            "name" => "Test Span",
            "kind" => "tool",
            "status" => "success",
            "duration_ms" => 150
          }
        end

        let(:mock_span) do
          double("Span",
            span_id: "span_123",
            trace_id: "trace_456", 
            parent_id: "parent_789",
            name: "Test Span",
            kind: "tool",
            status: "success",
            start_time: Time.parse("2025-09-25 10:00:00 UTC"),
            end_time: Time.parse("2025-09-25 10:00:00.150 UTC"),
            duration_ms: 150,
            span_attributes: base_span_attributes,
            depth: 1,
            children: [],
            events: []
          )
        end

        let(:component) { described_class.new(span: mock_span) }

        describe "#view_template" do
          it "renders the component without error" do
            expect { render(component) }.not_to raise_error
          end

          it "includes the span name in the output" do
            output = render(component)
            expect(output).to include("Test Span")
          end

          it "includes the span kind badge" do
            output = render(component)
            expect(output).to include("Tool")
          end

          it "includes the span status badge" do
            output = render(component)
            expect(output).to include("Success")
          end
        end

        describe "component routing based on span.kind" do
          let(:component) { described_class.new(span: mock_span) }

          context "when span kind is 'tool'" do
            before do
              allow(mock_span).to receive(:kind).and_return("tool")
            end

            it "should route to tool-specific component logic" do
              # This test will be updated once we have type-specific components
              output = render(component)
              expect(output).to include("Tool")
            end
          end

          context "when span kind is 'agent'" do
            before do
              allow(mock_span).to receive(:kind).and_return("agent")
            end

            it "should route to agent-specific component logic" do
              output = render(component)
              expect(output).to include("Agent")
            end
          end

          context "when span kind is 'llm'" do
            before do
              allow(mock_span).to receive(:kind).and_return("llm")
            end

            it "should route to llm-specific component logic" do
              output = render(component)
              expect(output).to include("Llm")
            end
          end

          context "when span kind is 'handoff'" do
            before do
              allow(mock_span).to receive(:kind).and_return("handoff")
            end

            it "should route to handoff-specific component logic" do
              output = render(component)
              expect(output).to include("Handoff")
            end
          end

          context "when span kind is 'guardrail'" do
            before do
              allow(mock_span).to receive(:kind).and_return("guardrail")
            end

            it "should route to guardrail-specific component logic" do
              output = render(component)
              expect(output).to include("Guardrail")
            end
          end

          context "when span kind is 'pipeline'" do
            before do
              allow(mock_span).to receive(:kind).and_return("pipeline")
            end

            it "should route to pipeline-specific component logic" do
              output = render(component)
              expect(output).to include("Pipeline")
            end
          end

          context "when span kind is unknown" do
            before do
              allow(mock_span).to receive(:kind).and_return("unknown_type")
            end

            it "should route to generic component logic" do
              output = render(component)
              expect(output).to include("Unknown_type")
            end
          end
        end

        describe "shared functionality" do
          it "renders span overview section" do
            output = render(component)
            expect(output).to include("Overview")
            expect(output).to include("span_123")
            expect(output).to include("trace_456")
          end

          it "renders timing information section" do
            output = render(component)
            expect(output).to include("Timing Information")
            expect(output).to include("150ms")
          end

          it "renders attributes section when span has attributes" do
            output = render(component)
            expect(output).to include("Attributes")
          end
        end
      end
    end
  end
end
# frozen_string_literal: true

require "spec_helper"
require "phlex"
require "phlex/rails"

# Load the component files
require_relative "../../../../../app/components/RAAF/rails/tracing/base_component"
require_relative "../../../../../app/components/RAAF/rails/tracing/span_detail"

module RAAF
  module Rails
    module Tracing
      RSpec.describe SpanDetail::Component, type: :component do
        include ComponentRendering

        let(:base_span_attributes) do
          {
            "span_id" => "span_123",
            "name" => "Test Span",
            "kind" => "tool",
            "status" => "success",
            "duration_ms" => 150
          }
        end

        # A stand-in rather than a record: the routing examples below set kinds
        # and statuses SpanRecord's own validations reject, which is the point --
        # the screen has to answer for a span written before those rules existed.
        let(:mock_span) do
          double("Span",
                 span_id: "span_123",
                 trace_id: "trace_456",
                 parent_id: "parent_789",
                 name: "Test Span",
                 display_name: "Test Span",
                 kind: "tool",
                 status: "success",
                 start_time: Time.parse("2025-09-25 10:00:00 UTC"),
                 end_time: Time.parse("2025-09-25 10:00:00.150 UTC"),
                 duration_ms: 150,
                 span_attributes: base_span_attributes,
                 depth: 1,
                 children: [],
                 events: [],
                 error?: false,
                 error_details: nil)
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

            it "routes to tool-specific component logic" do
              # This test will be updated once we have type-specific components
              output = render(component)
              expect(output).to include("Tool")
            end
          end

          context "when span kind is 'agent'" do
            before do
              allow(mock_span).to receive(:kind).and_return("agent")
            end

            it "routes to agent-specific component logic" do
              output = render(component)
              expect(output).to include("Agent")
            end
          end

          context "when span kind is 'llm'" do
            before do
              allow(mock_span).to receive(:kind).and_return("llm")
            end

            it "routes to llm-specific component logic" do
              output = render(component)
              expect(output).to include("Llm")
            end
          end

          context "when span kind is 'handoff'" do
            before do
              allow(mock_span).to receive(:kind).and_return("handoff")
            end

            it "routes to handoff-specific component logic" do
              output = render(component)
              expect(output).to include("Handoff")
            end
          end

          context "when span kind is 'guardrail'" do
            before do
              allow(mock_span).to receive(:kind).and_return("guardrail")
            end

            it "routes to guardrail-specific component logic" do
              output = render(component)
              expect(output).to include("Guardrail")
            end
          end

          context "when span kind is 'pipeline'" do
            before do
              allow(mock_span).to receive(:kind).and_return("pipeline")
            end

            it "routes to pipeline-specific component logic" do
              output = render(component)
              expect(output).to include("Pipeline")
            end
          end

          context "when span kind is unknown" do
            before do
              allow(mock_span).to receive(:kind).and_return("unknown_type")
            end

            # There is no deep dive for a kind the console does not know, so
            # the page stops at what every span has.
            it "routes to generic component logic" do
              output = render(component)
              expect(output).to include("unknown_type")
              expect(output).not_to include("detail</")
            end
          end
        end

        describe "shared functionality" do
          # The screen puts a span back beside the run it belongs to, so its
          # own id and its trace's are both on the page.
          it "renders the span in the context of its trace" do
            output = render(component)
            expect(output).to include("In its trace")
            expect(output).to include("span_123")
            expect(output).to include("trace_456")
          end

          it "renders the duration in the summary bar" do
            output = render(component)
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

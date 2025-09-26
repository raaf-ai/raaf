# frozen_string_literal: true

require "spec_helper"
require "phlex"
require "phlex/rails"
require "phlex/testing/view_helper"

# Load the component files
require_relative "../../../../../app/components/RAAF/rails/tracing/base_component"
require_relative "../../../../../app/components/RAAF/rails/tracing/span_detail_base"
require_relative "../../../../../app/components/RAAF/rails/tracing/handoff_span_component"

module RAAF
  module Rails
    module Tracing
      RSpec.describe HandoffSpanComponent, type: :component do
        include Phlex::Testing::ViewHelper

        let(:base_span_attributes) do
          {
            "handoff.source_agent" => "SalesAgent",
            "handoff.target_agent" => "TechnicalSupportAgent",
            "handoff.reason" => "User has technical questions that require specialized expertise. Sales agent completed initial qualification and is now transferring to technical support for detailed product discussion.",
            "handoff.type" => "escalation",
            "handoff.success" => true,
            "handoff.conversation_id" => "conv_abc123",
            "handoff.context" => {
              "customer_id" => "cust_456",
              "product_interest" => "Enterprise Solution",
              "previous_discussion" => "Pricing and basic features covered",
              "urgency_level" => "high",
              "contact_method" => "live_chat"
            }
          }
        end

        let(:mock_span) do
          double("Span",
            span_id: "handoff_span_123",
            trace_id: "trace_456", 
            parent_id: "parent_789",
            name: "Agent.handoff",
            kind: "handoff",
            status: "success",
            start_time: Time.parse("2025-09-25 10:00:00 UTC"),
            end_time: Time.parse("2025-09-25 10:00:00.850 UTC"),
            duration_ms: 850,
            span_attributes: base_span_attributes,
            depth: 2
          )
        end

        let(:component) { described_class.new(span: mock_span) }

        describe "#view_template" do
          it "renders the component without error" do
            expect { render(component) }.not_to raise_error
          end

          it "renders handoff overview section" do
            output = render(component)
            expect(output).to include("Agent Handoff")
            expect(output).to include("SalesAgent")
            expect(output).to include("TechnicalSupportAgent")
            expect(output).to include("bi-arrow-left-right")
          end

          it "includes the span duration badge" do
            output = render(component)
            expect(output).to include("850ms")
          end
        end

        describe "handoff data extraction" do
          it "extracts source agent from span attributes" do
            output = render(component)
            expect(output).to include("SalesAgent")
          end

          it "extracts target agent from span attributes" do
            output = render(component)
            expect(output).to include("TechnicalSupportAgent")
          end

          context "when handoff attributes use alternative naming" do
            let(:alternative_attributes) do
              {
                "source_agent" => "Agent1",
                "target_agent" => "Agent2",
                "reason" => "Transfer needed"
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(alternative_attributes)
            end

            it "handles alternative attribute names" do
              output = render(component)
              expect(output).to include("Agent1")
              expect(output).to include("Agent2")
            end
          end

          context "when handoff data is missing" do
            before do
              allow(mock_span).to receive(:span_attributes).and_return({})
            end

            it "uses fallback values" do
              output = render(component)
              expect(output).to include("Unknown Source Agent")
              expect(output).to include("Unknown Target Agent")
            end
          end
        end

        describe "agent transfer flow visualization" do
          it "renders transfer details section" do
            output = render(component)
            expect(output).to include("Transfer Details")
          end

          it "displays visual flow representation" do
            output = render(component)
            expect(output).to include("bi-robot") # Agent icons
            expect(output).to include("bi-arrow-right") # Transfer arrow
            expect(output).to include("Source") # Source label
            expect(output).to include("Target") # Target label
          end

          it "shows success status in the flow" do
            output = render(component)
            expect(output).to include("Success")
            expect(output).to include("text-green-600")
          end

          context "when handoff failed" do
            before do
              allow(mock_span).to receive(:status).and_return("error")
              allow(mock_span).to receive(:span_attributes).and_return({
                "handoff.source_agent" => "Agent1",
                "handoff.target_agent" => "Agent2",
                "handoff.success" => false
              })
            end

            it "shows failed status in the flow" do
              output = render(component)
              expect(output).to include("Failed")
              expect(output).to include("text-red-600")
            end
          end

          it "displays handoff metadata" do
            output = render(component)
            expect(output).to include("Source Agent")
            expect(output).to include("Target Agent")
            expect(output).to include("Handoff Status")
            expect(output).to include("Duration")
          end

          context "when additional metadata is present" do
            it "displays handoff type when available" do
              output = render(component)
              expect(output).to include("Handoff Type")
              expect(output).to include("Escalation")
            end

            it "displays conversation ID when available" do
              output = render(component)
              expect(output).to include("Conversation ID")
              expect(output).to include("conv_abc123")
            end
          end
        end

        describe "context transfer section" do
          it "renders context transfer section when present" do
            output = render(component)
            expect(output).to include("Context Transfer")
            expect(output).to include("bi-database")
            expect(output).to include("border-purple-200")
          end

          it "shows context summary with key badges" do
            output = render(component)
            expect(output).to include("Transferred Context Summary")
            expect(output).to include("Customer Id")
            expect(output).to include("Product Interest")
            expect(output).to include("Previous Discussion")
          end

          it "includes collapsible full context data" do
            output = render(component)
            expect(output).to include("Full Context Data")
            expect(output).to include("data-controller=\"span-detail\"")
            expect(output).to include("click->span-detail#toggleSection")
          end

          context "when context data is not a hash" do
            let(:string_context_attributes) do
              base_span_attributes.merge(
                "handoff.context" => "Context transferred successfully"
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(string_context_attributes)
            end

            it "renders context data as JSON" do
              output = render(component)
              expect(output).to include("Context Data")
            end
          end

          context "when context data is missing" do
            let(:no_context_attributes) do
              {
                "handoff.source_agent" => "Agent1",
                "handoff.target_agent" => "Agent2"
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(no_context_attributes)
            end

            it "does not render context transfer section" do
              output = render(component)
              expect(output).not_to include("Context Transfer")
            end
          end
        end

        describe "handoff reason section" do
          it "renders handoff reason section when present" do
            output = render(component)
            expect(output).to include("Handoff Reason")
            expect(output).to include("bi-chat-square-text")
            expect(output).to include("border-orange-200")
          end

          context "when reason is short" do
            let(:short_reason_attributes) do
              base_span_attributes.merge(
                "handoff.reason" => "Technical question"
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(short_reason_attributes)
            end

            it "displays reason without expansion" do
              output = render(component)
              expect(output).to include("Technical question")
              expect(output).not_to include("Show Full Text")
            end
          end

          context "when reason is long" do
            it "provides expandable reason text" do
              output = render(component)
              expect(output).to include("Show Full Text")
              expect(output).to include("click->span-detail#toggleSection")
            end
          end

          context "when reason is in different formats" do
            let(:complex_reason_attributes) do
              base_span_attributes.merge(
                "handoff.reason" => {
                  "primary" => "Technical expertise needed",
                  "secondary" => "Sales process complete"
                }
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(complex_reason_attributes)
            end

            it "handles complex reason formats" do
              output = render(component)
              expect(output).to include("Reason Data")
            end
          end

          context "when reason is missing" do
            let(:no_reason_attributes) do
              {
                "handoff.source_agent" => "Agent1",
                "handoff.target_agent" => "Agent2"
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(no_reason_attributes)
            end

            it "does not render handoff reason section" do
              output = render(component)
              expect(output).not_to include("Handoff Reason")
            end
          end
        end

        describe "error handling" do
          context "when span status is error" do
            before do
              allow(mock_span).to receive(:status).and_return("error")
              allow(mock_span).to receive(:span_attributes).and_return({
                "handoff.source_agent" => "FailingAgent",
                "handoff.target_agent" => "TargetAgent",
                "error" => "Handoff failed due to agent unavailability"
              })
            end

            it "renders error details section" do
              output = render(component)
              expect(output).to include("Error Details")
              expect(output).to include("Handoff failed due to agent unavailability")
              expect(output).to include("bg-red-50")
            end
          end

          context "when span has no attributes" do
            before do
              allow(mock_span).to receive(:span_attributes).and_return(nil)
            end

            it "renders without crashing" do
              expect { render(component) }.not_to raise_error
              output = render(component)
              expect(output).to include("Unknown Source Agent")
              expect(output).to include("Unknown Target Agent")
            end
          end
        end

        describe "expandable text functionality" do
          it "creates proper IDs for expandable sections" do
            output = render(component)
            expect(output).to include("reason-#{mock_span.span_id}")
          end

          it "includes proper toggle controls" do
            output = render(component)
            expect(output).to include("data-action=\"click->span-detail#toggleSection\"")
          end
        end

        describe "handoff metadata edge cases" do
          context "when timestamp is provided separately" do
            let(:timestamp_attributes) do
              base_span_attributes.merge(
                "handoff.timestamp" => Time.parse("2025-09-25 10:05:00 UTC")
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(timestamp_attributes)
            end

            it "displays the handoff timestamp" do
              output = render(component)
              expect(output).to include("Transfer Time")
              expect(output).to include("2025-09-25 10:05:00")
            end
          end

          context "when handoff type is missing" do
            let(:no_type_attributes) do
              base_span_attributes.reject { |k, _| k == "handoff.type" }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(no_type_attributes)
            end

            it "does not display handoff type" do
              output = render(component)
              expect(output).not_to include("Handoff Type")
            end
          end
        end

        describe "visual styling consistency" do
          it "uses appropriate color coding for different sections" do
            output = render(component)
            expect(output).to include("bg-purple-50") # Context section
            expect(output).to include("bg-orange-50") # Reason section
            expect(output).to include("bg-blue-100") # Source agent
            expect(output).to include("bg-green-100") # Target agent
          end

          it "includes proper icon usage" do
            output = render(component)
            expect(output).to include("bi-arrow-left-right") # Main handoff icon
            expect(output).to include("bi-robot") # Agent icons
            expect(output).to include("bi-database") # Context icon
            expect(output).to include("bi-chat-square-text") # Reason icon
          end
        end
      end
    end
  end
end

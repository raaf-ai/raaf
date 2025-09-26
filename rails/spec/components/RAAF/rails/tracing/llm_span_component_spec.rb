# frozen_string_literal: true

require "spec_helper"
require "phlex"
require "phlex/rails"
require "phlex/testing/view_helper"

# Load the component files
require_relative "../../../../../app/components/RAAF/rails/tracing/base_component"
require_relative "../../../../../app/components/RAAF/rails/tracing/span_detail_base"
require_relative "../../../../../app/components/RAAF/rails/tracing/llm_span_component"

module RAAF
  module Rails
    module Tracing
      RSpec.describe LlmSpanComponent, type: :component do
        include Phlex::Testing::ViewHelper

        let(:base_span_attributes) do
          {
            "llm.model" => "gpt-4o",
            "llm.provider" => "OpenAI",
            "llm.temperature" => 0.3,
            "llm.max_tokens" => 1000,
            "llm.request" => {
              "messages" => [
                { "role" => "system", "content" => "You are a helpful assistant." },
                { "role" => "user", "content" => "What is Ruby programming?" }
              ],
              "model" => "gpt-4o",
              "temperature" => 0.3
            },
            "llm.response" => {
              "choices" => [
                {
                  "message" => {
                    "role" => "assistant",
                    "content" => "Ruby is a dynamic, interpreted programming language..."
                  },
                  "finish_reason" => "stop"
                }
              ]
            },
            "llm.usage" => {
              "prompt_tokens" => 25,
              "completion_tokens" => 150,
              "total_tokens" => 175
            },
            "llm.cost" => {
              "input_cost" => 0.00075,
              "output_cost" => 0.009,
              "total_cost" => 0.00975,
              "currency" => "USD"
            }
          }
        end

        let(:mock_span) do
          double("Span",
            span_id: "llm_span_123",
            trace_id: "trace_456", 
            parent_id: "parent_789",
            name: "LLM.completion",
            kind: "llm",
            status: "success",
            start_time: Time.parse("2025-09-25 10:00:00 UTC"),
            end_time: Time.parse("2025-09-25 10:00:03.200 UTC"),
            duration_ms: 3200,
            span_attributes: base_span_attributes,
            depth: 2
          )
        end

        let(:component) { described_class.new(span: mock_span) }

        describe "#view_template" do
          it "renders the component without error" do
            expect { render(component) }.not_to raise_error
          end

          it "renders LLM overview section" do
            output = render(component)
            expect(output).to include("LLM Request")
            expect(output).to include("OpenAI")
            expect(output).to include("gpt-4o")
            expect(output).to include("bi-cpu")
          end

          it "includes the span duration badge" do
            output = render(component)
            expect(output).to include("3200ms")
          end
        end

        describe "LLM data extraction" do
          it "extracts model name from span attributes" do
            output = render(component)
            expect(output).to include("gpt-4o")
          end

          it "extracts provider name from span attributes" do
            output = render(component)
            expect(output).to include("OpenAI")
          end

          context "when provider is inferred from model name" do
            let(:inferred_provider_attributes) do
              {
                "llm.model" => "claude-3-sonnet",
                "llm.request" => {},
                "llm.response" => {}
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(inferred_provider_attributes)
            end

            it "infers provider from model name" do
              output = render(component)
              expect(output).to include("Claude")
            end
          end

          context "when LLM data is missing" do
            before do
              allow(mock_span).to receive(:span_attributes).and_return({})
            end

            it "uses fallback values" do
              output = render(component)
              expect(output).to include("Unknown Model")
              expect(output).to include("Unknown Provider")
            end
          end
        end

        describe "request/response flow visualization" do
          it "renders request section" do
            output = render(component)
            expect(output).to include("Request")
            expect(output).to include("bi-arrow-up-right")
            expect(output).to include("border-blue-200")
          end

          it "renders response section" do
            output = render(component)
            expect(output).to include("Response")
            expect(output).to include("bi-arrow-down-left")
            expect(output).to include("border-green-200")
          end

          it "includes collapsible JSON sections" do
            output = render(component)
            expect(output).to include("data-controller=\"span-detail\"")
            expect(output).to include("click->span-detail#toggleSection")
          end

          context "when request data is missing" do
            let(:missing_request_attributes) do
              {
                "llm.model" => "gpt-4o",
                "llm.response" => { "choices" => [] }
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(missing_request_attributes)
            end

            it "shows empty state for request" do
              output = render(component)
              expect(output).to include("No request data available")
              expect(output).to include("text-gray-500")
            end
          end

          context "when response data is missing" do
            let(:missing_response_attributes) do
              {
                "llm.model" => "gpt-4o",
                "llm.request" => { "messages" => [] }
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(missing_response_attributes)
            end

            it "shows empty state for response" do
              output = render(component)
              expect(output).to include("No response data available")
              expect(output).to include("text-gray-500")
            end
          end
        end

        describe "token usage section" do
          it "renders token usage section when present" do
            output = render(component)
            expect(output).to include("Token Usage")
            expect(output).to include("bi-speedometer")
            expect(output).to include("border-purple-200")
          end

          it "displays token counts" do
            output = render(component)
            expect(output).to include("Prompt Tokens")
            expect(output).to include("25")
            expect(output).to include("Completion Tokens")
            expect(output).to include("150")
            expect(output).to include("Total Tokens")
            expect(output).to include("175")
          end

          context "when usage has alternative field names" do
            let(:alternative_usage_attributes) do
              base_span_attributes.merge(
                "llm.usage" => {
                  "input_tokens" => 30,
                  "output_tokens" => 120,
                  "total_tokens" => 150
                }
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(alternative_usage_attributes)
            end

            it "handles alternative token field names" do
              output = render(component)
              expect(output).to include("30")
              expect(output).to include("120")
              expect(output).to include("150")
            end
          end

          context "when usage data is not a hash" do
            let(:string_usage_attributes) do
              base_span_attributes.merge(
                "llm.usage" => "150 tokens used"
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(string_usage_attributes)
            end

            it "renders usage data as JSON" do
              output = render(component)
              expect(output).to include("Usage Data")
            end
          end

          context "when usage data is missing" do
            let(:no_usage_attributes) do
              {
                "llm.model" => "gpt-4o",
                "llm.request" => {},
                "llm.response" => {}
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(no_usage_attributes)
            end

            it "does not render token usage section" do
              output = render(component)
              expect(output).not_to include("Token Usage")
            end
          end
        end

        describe "cost metrics section" do
          it "renders cost metrics section when present" do
            output = render(component)
            expect(output).to include("Cost Metrics")
            expect(output).to include("bi-currency-dollar")
            expect(output).to include("border-yellow-200")
          end

          it "displays cost breakdown" do
            output = render(component)
            expect(output).to include("Input Cost")
            expect(output).to include("$0.0008")
            expect(output).to include("Output Cost")
            expect(output).to include("$0.009")
            expect(output).to include("Total Cost")
            expect(output).to include("$0.0098")
            expect(output).to include("Currency")
            expect(output).to include("USD")
          end

          context "when cost is a simple number" do
            let(:simple_cost_attributes) do
              base_span_attributes.merge(
                "llm.cost" => 0.0125
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(simple_cost_attributes)
            end

            it "displays estimated cost" do
              output = render(component)
              expect(output).to include("Estimated Cost")
              expect(output).to include("$0.0125")
            end
          end

          context "when cost data is missing but usage is present" do
            let(:no_cost_attributes) do
              {
                "llm.model" => "gpt-4o",
                "llm.usage" => {
                  "prompt_tokens" => 100,
                  "completion_tokens" => 200
                }
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(no_cost_attributes)
            end

            it "calculates and displays estimated cost" do
              output = render(component)
              expect(output).to include("Cost Metrics")
              expect(output).to include("Estimated Cost")
            end
          end

          context "when both cost and usage data are missing" do
            let(:no_cost_usage_attributes) do
              {
                "llm.model" => "gpt-4o",
                "llm.request" => {},
                "llm.response" => {}
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(no_cost_usage_attributes)
            end

            it "does not render cost metrics section" do
              output = render(component)
              expect(output).not_to include("Cost Metrics")
            end
          end
        end

        describe "model parameters section" do
          it "renders model parameters section when present" do
            output = render(component)
            expect(output).to include("Model Parameters")
            expect(output).to include("Model")
            expect(output).to include("Provider")
            expect(output).to include("Temperature")
            expect(output).to include("0.3")
          end

          context "when model parameters include streaming" do
            let(:streaming_attributes) do
              base_span_attributes.merge(
                "llm.stream" => true
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(streaming_attributes)
            end

            it "displays streaming status" do
              output = render(component)
              expect(output).to include("Stream")
              expect(output).to include("Enabled")
            end
          end

          context "when model parameters are minimal" do
            let(:minimal_params_attributes) do
              {
                "llm.model" => "gpt-3.5-turbo"
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(minimal_params_attributes)
            end

            it "only shows available parameters" do
              output = render(component)
              expect(output).to include("gpt-3.5-turbo")
              expect(output).not_to include("Temperature")
            end
          end
        end

        describe "cost formatting" do
          it "formats small costs in cents" do
            # This tests the format_cost helper method indirectly
            small_cost_attributes = base_span_attributes.merge(
              "llm.cost" => 0.005
            )
            allow(mock_span).to receive(:span_attributes).and_return(small_cost_attributes)
            
            output = render(component)
            expect(output).to include("5.0¢")
          end

          it "formats larger costs in dollars" do
            large_cost_attributes = base_span_attributes.merge(
              "llm.cost" => 0.125
            )
            allow(mock_span).to receive(:span_attributes).and_return(large_cost_attributes)
            
            output = render(component)
            expect(output).to include("$0.125")
          end
        end

        describe "error handling" do
          context "when span status is error" do
            before do
              allow(mock_span).to receive(:status).and_return("error")
              allow(mock_span).to receive(:span_attributes).and_return({
                "llm.model" => "gpt-4o",
                "error" => "API rate limit exceeded"
              })
            end

            it "renders error details section" do
              output = render(component)
              expect(output).to include("Error Details")
              expect(output).to include("API rate limit exceeded")
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
              expect(output).to include("Unknown Model")
              expect(output).to include("Unknown Provider")
            end
          end
        end
      end
    end
  end
end

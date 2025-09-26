# frozen_string_literal: true

require "spec_helper"
require "phlex"
require "phlex/rails"
require "phlex/testing/view_helper"

# Load the component files
require_relative "../../../../../app/components/RAAF/rails/tracing/base_component"
require_relative "../../../../../app/components/RAAF/rails/tracing/span_detail_base"
require_relative "../../../../../app/components/RAAF/rails/tracing/tool_span_component"

module RAAF
  module Rails
    module Tracing
      RSpec.describe ToolSpanComponent, type: :component do
        include Phlex::Testing::ViewHelper

        let(:base_span_attributes) do
          {
            "function" => {
              "name" => "search_web",
              "input" => {
                "query" => "Ruby programming",
                "limit" => 10
              },
              "output" => {
                "results" => [
                  { "title" => "Ruby Tutorial", "url" => "https://ruby-lang.org" },
                  { "title" => "Ruby Gems", "url" => "https://rubygems.org" }
                ],
                "total_found" => 2
              }
            }
          }
        end

        let(:mock_span) do
          double("Span",
            span_id: "tool_span_123",
            trace_id: "trace_456", 
            parent_id: "parent_789",
            name: "search_web",
            kind: "tool",
            status: "success",
            start_time: Time.parse("2025-09-25 10:00:00 UTC"),
            end_time: Time.parse("2025-09-25 10:00:00.250 UTC"),
            duration_ms: 250,
            span_attributes: base_span_attributes,
            depth: 2
          )
        end

        let(:component) { described_class.new(span: mock_span) }

        describe "#view_template" do
          it "renders the component without error" do
            expect { render(component) }.not_to raise_error
          end

          it "renders tool overview section" do
            output = render(component)
            expect(output).to include("Tool Execution")
            expect(output).to include("search_web")
            expect(output).to include("bi-tools")
          end

          it "includes the span duration badge" do
            output = render(component)
            expect(output).to include("250ms")
          end
        end

        describe "tool data extraction" do
          context "when function data is present" do
            it "extracts function name from span attributes" do
              output = render(component)
              expect(output).to include("search_web")
            end

            it "renders function execution flow" do
              output = render(component)
              expect(output).to include("Function Details")
            end
          end

          context "when tool data is in different format" do
            let(:alternative_attributes) do
              {
                "tool" => {
                  "name" => "calculate_sum",
                  "arguments" => { "a" => 5, "b" => 10 },
                  "result" => { "sum" => 15 }
                }
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(alternative_attributes)
            end

            it "handles alternative tool data structure" do
              output = render(component)
              expect(output).to include("calculate_sum")
            end
          end

          context "when tool data is malformed" do
            let(:malformed_attributes) do
              {
                "function" => "invalid_json_string"
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(malformed_attributes)
              allow(mock_span).to receive(:name).and_return("fallback_tool")
            end

            it "gracefully handles malformed data" do
              expect { render(component) }.not_to raise_error
              output = render(component)
              expect(output).to include("fallback_tool")
            end
          end
        end

        describe "input/output flow visualization" do
          it "renders input parameters section" do
            output = render(component)
            expect(output).to include("Input Parameters")
            expect(output).to include("bi-arrow-right")
            expect(output).to include("Ruby programming")
          end

          it "renders output results section" do
            output = render(component)
            expect(output).to include("Output Results")
            expect(output).to include("bi-arrow-left")
            expect(output).to include("Ruby Tutorial")
          end

          it "uses appropriate color coding for input/output" do
            output = render(component)
            expect(output).to include("border-blue-200") # Input styling
            expect(output).to include("border-green-200") # Output styling
          end

          context "when input data is missing" do
            let(:missing_input_attributes) do
              {
                "function" => {
                  "name" => "no_input_tool",
                  "output" => { "result" => "success" }
                }
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(missing_input_attributes)
            end

            it "shows empty state for input" do
              output = render(component)
              expect(output).to include("No input parameters")
              expect(output).to include("border-dashed")
            end
          end

          context "when output data is missing" do
            let(:missing_output_attributes) do
              {
                "function" => {
                  "name" => "no_output_tool",
                  "input" => { "param" => "value" }
                }
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(missing_output_attributes)
            end

            it "shows empty state for output" do
              output = render(component)
              expect(output).to include("No output results")
              expect(output).to include("border-dashed")
            end
          end
        end

        describe "JSON section rendering" do
          it "includes collapsible JSON sections" do
            output = render(component)
            expect(output).to include("data-controller=\"span-detail\"")
            expect(output).to include("click->span-detail#toggleSection")
          end

          it "includes data size indicators" do
            output = render(component)
            expect(output).to include("2 keys") # For input object
          end
        end

        describe "error handling" do
          context "when span status is error" do
            before do
              allow(mock_span).to receive(:status).and_return("error")
              allow(mock_span).to receive(:span_attributes).and_return({
                "function" => { "name" => "failing_tool" },
                "error" => "Tool execution failed"
              })
            end

            it "renders error details section" do
              output = render(component)
              expect(output).to include("Error Details")
              expect(output).to include("Tool execution failed")
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
              expect(output).to include("Unknown Tool")
            end
          end
        end

        describe "function details section" do
          it "displays function metadata" do
            output = render(component)
            expect(output).to include("Function Details")
            expect(output).to include("Function Name")
            expect(output).to include("Execution Status")
            expect(output).to include("Duration")
          end

          context "when function has description" do
            let(:described_function_attributes) do
              {
                "function" => {
                  "name" => "documented_tool",
                  "description" => "A well-documented tool function",
                  "input" => {},
                  "output" => {}
                }
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(described_function_attributes)
            end

            it "includes the function description" do
              output = render(component)
              expect(output).to include("Description")
              expect(output).to include("A well-documented tool function")
            end
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "phlex"
require "phlex/rails"

# Load the component files
require_relative "../../../../../app/components/RAAF/rails/tracing/base_component"
require_relative "../../../../../app/components/RAAF/rails/tracing/span_detail_base"
require_relative "../../../../../app/components/RAAF/rails/tracing/agent_span_component"

module RAAF
  module Rails
    module Tracing
      RSpec.describe AgentSpanComponent, type: :component do
        include ComponentRendering

        let(:base_span_attributes) do
          {
            "agent.name" => "ResearchAgent",
            "agent.model" => "gpt-4o",
            "agent.temperature" => 0.7,
            "agent.max_tokens" => 2000,
            "agent.tools_count" => 3,
            "agent.system_instructions" => "You are a research assistant that helps users find information.",
            "context" => {
              "user_query" => "Tell me about Ruby programming",
              "research_depth" => "comprehensive",
              "target_audience" => "developers"
            }
          }
        end

        let(:mock_span) do
          double("Span",
                 span_id: "agent_span_123",
                 trace_id: "trace_456",
                 parent_id: "parent_789",
                 name: "Agent.run",
                 kind: "agent",
                 status: "success",
                 start_time: Time.parse("2025-09-25 10:00:00 UTC"),
                 end_time: Time.parse("2025-09-25 10:00:05.500 UTC"),
                 duration_ms: 5500,
                 span_attributes: base_span_attributes,
                 depth: 1)
        end

        let(:component) { described_class.new(span: mock_span) }

        describe "#view_template" do
          it "renders the component without error" do
            expect { render(component) }.not_to raise_error
          end

          it "renders agent overview section" do
            output = render(component)
            expect(output).to include("Agent Execution")
            expect(output).to include("ResearchAgent")
            expect(output).to include("gpt-4o")
            expect(output).to include("bi-robot")
          end

          it "includes the span duration badge" do
            output = render(component)
            expect(output).to include("5500ms")
          end
        end

        describe "agent data extraction" do
          it "extracts agent name from span attributes" do
            output = render(component)
            expect(output).to include("ResearchAgent")
          end

          it "extracts model name from span attributes" do
            output = render(component)
            expect(output).to include("gpt-4o")
          end

          context "when agent attributes use alternative naming" do
            let(:alternative_attributes) do
              {
                "agent_name" => "AlternativeAgent",
                "model" => "gpt-3.5-turbo",
                "temperature" => 0.5
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(alternative_attributes)
            end

            it "handles alternative attribute names" do
              output = render(component)
              expect(output).to include("AlternativeAgent")
              expect(output).to include("gpt-3.5-turbo")
            end
          end

          context "when agent data is missing" do
            before do
              allow(mock_span).to receive(:span_attributes).and_return({})
              allow(mock_span).to receive(:name).and_return("agent.fallback_name")
            end

            it "uses fallback values" do
              output = render(component)
              expect(output).to include("fallback_name")
              expect(output).to include("Unknown Model")
            end
          end
        end

        describe "agent configuration section" do
          it "renders agent configuration details" do
            output = render(component)
            expect(output).to include("Configuration")
            expect(output).to include("Basic Information")
            expect(output).to include("Agent Name")
            expect(output).to include("Model")
            expect(output).to include("Temperature")
            expect(output).to include("0.7")
          end

          it "displays model parameters" do
            output = render(component)
            expect(output).to include("Max Tokens")
            expect(output).to include("2000")
            expect(output).to include("Tools Available")
            expect(output).to include("3")
          end

          context "when optional configuration is missing" do
            let(:minimal_attributes) do
              {
                "agent.name" => "MinimalAgent",
                "agent.model" => "gpt-4o"
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(minimal_attributes)
            end

            # The table has a row per parameter either way; a span that never
            # recorded one says so rather than dropping the row, so a reader can
            # tell "not set" from "not captured".
            it "marks the configuration it does not have" do
              output = render(component)
              expect(output).to include("MinimalAgent")
              expect(output).to include("Temperature")
              expect(output).to include("Max Tokens")
              expect(output).to include("N/A")
            end
          end
        end

        describe "context information section" do
          it "renders context variables section when present" do
            output = render(component)
            expect(output).to include("Context Variables")
            expect(output).to include("Agent Context")
            expect(output).to include("bi-layers")
          end

          it "includes collapsible context data" do
            output = render(component)
            expect(output).to include("data-controller=\"span-detail\"")
            expect(output).to include("click->span-detail#toggleSection")
          end

          context "when context data is missing" do
            let(:no_context_attributes) do
              {
                "agent.name" => "ContextlessAgent",
                "agent.model" => "gpt-4o"
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(no_context_attributes)
            end

            it "does not render context section" do
              output = render(component)
              expect(output).not_to include("Context Variables")
            end
          end
        end

        describe "instructions section" do
          it "renders instructions section when present" do
            output = render(component)
            expect(output).to include("System Prompt")
            expect(output).to include("bi-gear")
            expect(output).to include("You are a research assistant")
          end

          context "when instructions are short" do
            let(:short_instructions_attributes) do
              base_span_attributes.merge(
                "agent.system_instructions" => "Short instruction"
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(short_instructions_attributes)
            end

            it "displays instructions without expansion" do
              output = render(component)
              expect(output).to include("Short instruction")
            end
          end

          context "when instructions are long" do
            let(:long_instructions) do
              "You are a comprehensive research assistant that helps users find detailed information. " * 10
            end

            let(:long_instructions_attributes) do
              base_span_attributes.merge(
                "agent.system_instructions" => long_instructions
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(long_instructions_attributes)
            end

            it "keeps a long system prompt in its own tab" do
              output = render(component)
              expect(output).to include("System Prompt")
              expect(output).to include("comprehensive research assistant")
            end
          end

          context "when instructions are in different formats" do
            let(:complex_instructions_attributes) do
              base_span_attributes.merge(
                "agent.system_instructions" => {
                  "system" => "You are a helpful assistant",
                  "context" => "Additional context here"
                }
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(complex_instructions_attributes)
            end

            it "handles complex instruction formats" do
              output = render(component)
              expect(output).to include("System Prompt")
              expect(output).to include("You are a helpful assistant")
            end
          end

          context "when instructions are missing" do
            let(:no_instructions_attributes) do
              {
                "agent.name" => "NoInstructionsAgent",
                "agent.model" => "gpt-4o"
              }
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(no_instructions_attributes)
            end

            it "does not render instructions section" do
              output = render(component)
              expect(output).not_to include("System Prompt")
            end
          end
        end

        describe "error handling" do
          context "when span status is error" do
            before do
              allow(mock_span).to receive(:status).and_return("error")
              allow(mock_span).to receive(:span_attributes).and_return({
                                                                         "agent.name" => "FailingAgent",
                                                                         "error" => "Agent execution failed due to invalid configuration"
                                                                       })
            end

            it "renders error details section" do
              output = render(component)
              expect(output).to include("Error Details")
              expect(output).to include("Agent execution failed")
              expect(output).to include("bg-red-50")
            end
          end

          context "when span has no attributes" do
            before do
              allow(mock_span).to receive(:span_attributes).and_return(nil)
              allow(mock_span).to receive(:name).and_return(nil)
            end

            it "renders without crashing" do
              output = nil
              expect { output = render(component) }.not_to raise_error
              expect(output).to include("Unknown Agent")
              expect(output).to include("Unknown Model")
            end
          end
        end

        describe "parallel tool calls configuration" do
          context "when parallel tool calls is enabled" do
            let(:parallel_enabled_attributes) do
              base_span_attributes.merge(
                "agent.parallel_tool_calls" => true
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(parallel_enabled_attributes)
            end

            it "displays parallel tool calls as enabled" do
              output = render(component)
              expect(output).to include("Parallel Tool Calls")
              expect(output).to include("true")
            end
          end

          context "when parallel tool calls is disabled" do
            let(:parallel_disabled_attributes) do
              base_span_attributes.merge(
                "agent.parallel_tool_calls" => false
              )
            end

            before do
              allow(mock_span).to receive(:span_attributes).and_return(parallel_disabled_attributes)
            end

            it "displays parallel tool calls as disabled" do
              output = render(component)
              expect(output).to include("Parallel Tool Calls")
              expect(output).to include("false")
            end
          end
        end
      end
    end
  end
end

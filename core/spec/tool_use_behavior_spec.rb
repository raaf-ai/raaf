# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::ToolUseBehavior do
  let(:agent) { double("Agent") }
  let(:tool_calls) { [{ "function" => { "name" => "test_tool" } }] }
  let(:results) { [{ role: "tool", content: "Result" }] }
  let(:conversation) { [] }

  describe RAAF::ToolUseBehavior::Base do
    let(:base_behavior) { described_class.new }

    describe "#process_tool_result" do
      it "raises NotImplementedError" do
        expect do
          base_behavior.process_tool_result(agent, tool_calls, results, conversation)
        end.to raise_error(NotImplementedError, "Subclasses must implement process_tool_result")
      end
    end

    describe "#should_continue?" do
      it "returns true by default" do
        expect(base_behavior.should_continue?(agent, tool_calls, results, conversation)).to be true
      end
    end
  end

  describe RAAF::ToolUseBehavior::RunLLMAgain do
    let(:behavior) { described_class.new }

    describe "#process_tool_result" do
      it "adds results to conversation and continues" do
        result = behavior.process_tool_result(agent, tool_calls, results, conversation)

        expect(result).to eq({ continue: true, done: false })
        expect(conversation).to include({ role: "tool", content: "Result" })
      end

      it "adds multiple results to conversation" do
        multiple_results = [
          { role: "tool", content: "Result 1" },
          { role: "tool", content: "Result 2" }
        ]

        behavior.process_tool_result(agent, tool_calls, multiple_results, conversation)

        expect(conversation).to include({ role: "tool", content: "Result 1" })
        expect(conversation).to include({ role: "tool", content: "Result 2" })
      end
    end
  end

  describe RAAF::ToolUseBehavior::StopOnFirstTool do
    let(:behavior) { described_class.new }

    describe "#process_tool_result" do
      it "adds results to conversation and stops" do
        result = behavior.process_tool_result(agent, tool_calls, results, conversation)

        expect(result).to eq({ continue: false, done: true })
        expect(conversation).to include({ role: "tool", content: "Result" })
      end

      it "adds multiple results to conversation" do
        multiple_results = [
          { role: "tool", content: "Result 1" },
          { role: "tool", content: "Result 2" }
        ]

        behavior.process_tool_result(agent, tool_calls, multiple_results, conversation)

        expect(conversation).to include({ role: "tool", content: "Result 1" })
        expect(conversation).to include({ role: "tool", content: "Result 2" })
      end
    end
  end

  describe RAAF::ToolUseBehavior::StopAtTools do
    describe "#initialize" do
      it "accepts single tool name" do
        behavior = described_class.new("search")
        expect(behavior.tool_names).to eq(["search"])
      end

      it "accepts array of tool names" do
        behavior = described_class.new(%w[search database])
        expect(behavior.tool_names).to eq(%w[search database])
      end

      it "converts symbols to strings" do
        behavior = described_class.new(%i[search database])
        expect(behavior.tool_names).to eq(%w[search database])
      end
    end

    describe "#process_tool_result" do
      let(:behavior) { described_class.new(%w[search database]) }

      context "when stop tool is called" do
        let(:stop_tool_calls) { [{ "function" => { "name" => "search" } }] }

        it "stops execution" do
          result = behavior.process_tool_result(agent, stop_tool_calls, results, conversation)

          expect(result).to eq({ continue: false, done: true })
          expect(conversation).to include({ role: "tool", content: "Result" })
        end
      end

      context "when non-stop tool is called" do
        let(:regular_tool_calls) { [{ "function" => { "name" => "calculate" } }] }

        it "continues execution" do
          result = behavior.process_tool_result(agent, regular_tool_calls, results, conversation)

          expect(result).to eq({ continue: true, done: false })
          expect(conversation).to include({ role: "tool", content: "Result" })
        end
      end

      context "when mixed tools are called" do
        let(:mixed_tool_calls) do
          [
            { "function" => { "name" => "calculate" } },
            { "function" => { "name" => "search" } }
          ]
        end

        it "stops if any stop tool is called" do
          result = behavior.process_tool_result(agent, mixed_tool_calls, results, conversation)

          expect(result).to eq({ continue: false, done: true })
        end
      end
    end
  end

  describe RAAF::ToolUseBehavior::CustomFunction do
    describe "#initialize" do
      it "accepts a function" do
        func = proc { |_a, _tc, _r, _c| true }
        behavior = described_class.new(func)
        expect(behavior.function).to eq(func)
      end
    end

    describe "#process_tool_result" do
      context "when function returns boolean" do
        let(:behavior) do
          described_class.new(proc { |_a, _tc, _r, _c| false })
        end

        it "normalizes boolean result" do
          result = behavior.process_tool_result(agent, tool_calls, results, conversation)

          expect(result).to eq({ continue: false, done: true })
        end

        it "handles true result" do
          true_behavior = described_class.new(proc { |_a, _tc, _r, _c| true })
          result = true_behavior.process_tool_result(agent, tool_calls, results, conversation)

          expect(result).to eq({ continue: true, done: false })
        end
      end

      context "when function returns hash" do
        let(:behavior) do
          described_class.new(proc { |_a, _tc, _r, _c| { continue: false, done: true } })
        end

        it "uses hash result directly" do
          result = behavior.process_tool_result(agent, tool_calls, results, conversation)

          expect(result).to eq({ continue: false, done: true })
        end

        it "provides defaults for missing keys" do
          partial_behavior = described_class.new(proc { |_a, _tc, _r, _c| { continue: false } })
          result = partial_behavior.process_tool_result(agent, tool_calls, results, conversation)

          expect(result).to eq({ continue: false, done: false })
        end
      end

      context "when function returns other value" do
        let(:behavior) do
          described_class.new(proc { |_a, _tc, _r, _c| "other" })
        end

        it "defaults to continue" do
          result = behavior.process_tool_result(agent, tool_calls, results, conversation)

          expect(result).to eq({ continue: true, done: false })
        end
      end

      it "passes all parameters to custom function" do
        received_params = nil
        behavior = described_class.new(proc do |a, tc, r, c|
          received_params = [a, tc, r, c]
          true
        end)

        behavior.process_tool_result(agent, tool_calls, results, conversation)

        expect(received_params).to eq([agent, tool_calls, results, conversation])
      end
    end
  end

  describe RAAF::ToolUseBehavior::ToolsToFinalOutput do
    describe "#initialize" do
      it "accepts single tool name" do
        behavior = described_class.new("report")
        expect(behavior.tool_names).to eq(["report"])
      end

      it "accepts array of tool names" do
        behavior = described_class.new(%w[report summary])
        expect(behavior.tool_names).to eq(%w[report summary])
      end

      it "uses default output extractor" do
        behavior = described_class.new("report")
        expect(behavior.output_extractor).to be_a(Proc)
      end

      it "accepts custom output extractor" do
        extractor = proc { |results| results.first[:content] }
        behavior = described_class.new("report", output_extractor: extractor)
        expect(behavior.output_extractor).to eq(extractor)
      end
    end

    describe "#process_tool_result" do
      let(:behavior) { described_class.new(["report"]) }

      context "when final output tool is called" do
        let(:final_tool_calls) { [{ "function" => { "name" => "report" } }] }
        let(:final_results) { [{ role: "tool", content: "Final Report", tool_name: "report" }] }

        it "extracts final output and stops" do
          result = behavior.process_tool_result(agent, final_tool_calls, final_results, conversation)

          expect(result[:continue]).to be false
          expect(result[:done]).to be true
          expect(result[:final_output]).to eq("Final Report")
        end

        it "adds assistant message to conversation" do
          behavior.process_tool_result(agent, final_tool_calls, final_results, conversation)

          expect(conversation).to include(hash_including({
                                                           role: "assistant",
                                                           content: "Final Report"
                                                         }))
        end

        it "uses custom output extractor" do
          extractor = proc { |results, _tools| "Custom: #{results.first[:content]}" }
          custom_behavior = described_class.new("report", output_extractor: extractor)

          result = custom_behavior.process_tool_result(agent, final_tool_calls, final_results, conversation)

          expect(result[:final_output]).to eq("Custom: Final Report")
        end

        it "handles nil final output" do
          extractor = proc { |_results, _tools| }
          custom_behavior = described_class.new("report", output_extractor: extractor)

          custom_behavior.process_tool_result(agent, final_tool_calls, final_results, conversation)

          expect(conversation).not_to include(hash_including(role: "assistant"))
        end
      end

      context "when regular tool is called" do
        let(:regular_tool_calls) { [{ "function" => { "name" => "calculate" } }] }

        it "continues execution normally" do
          result = behavior.process_tool_result(agent, regular_tool_calls, results, conversation)

          expect(result).to eq({ continue: true, done: false })
          expect(conversation).to include({ role: "tool", content: "Result" })
        end
      end
    end
  end

  describe "Factory methods" do
    describe ".run_llm_again" do
      it "creates RunLLMAgain behavior" do
        behavior = described_class.run_llm_again
        expect(behavior).to be_a(RAAF::ToolUseBehavior::RunLLMAgain)
      end
    end

    describe ".stop_on_first_tool" do
      it "creates StopOnFirstTool behavior" do
        behavior = described_class.stop_on_first_tool
        expect(behavior).to be_a(RAAF::ToolUseBehavior::StopOnFirstTool)
      end
    end

    describe ".stop_at_tools" do
      it "creates StopAtTools behavior" do
        behavior = described_class.stop_at_tools("search", "database")
        expect(behavior).to be_a(RAAF::ToolUseBehavior::StopAtTools)
        expect(behavior.tool_names).to eq(%w[search database])
      end
    end

    describe ".custom_function" do
      it "creates CustomFunction behavior" do
        block = proc { |_a, _tc, _r, _c| true }
        behavior = described_class.custom_function(&block)
        expect(behavior).to be_a(RAAF::ToolUseBehavior::CustomFunction)
        expect(behavior.function).to eq(block)
      end
    end

    describe ".tools_to_final_output" do
      it "creates ToolsToFinalOutput behavior" do
        behavior = described_class.tools_to_final_output("report", "summary")
        expect(behavior).to be_a(RAAF::ToolUseBehavior::ToolsToFinalOutput)
        expect(behavior.tool_names).to eq(%w[report summary])
      end

      it "accepts output_extractor parameter" do
        extractor = proc(&:first)
        behavior = described_class.tools_to_final_output("report", output_extractor: extractor)
        expect(behavior.output_extractor).to eq(extractor)
      end
    end

    describe ".from_config" do
      it "creates stop_on_first_tool from string" do
        behavior = described_class.from_config("stop_on_first_tool")
        expect(behavior).to be_a(RAAF::ToolUseBehavior::StopOnFirstTool)
      end

      it "creates stop_on_first_tool from symbol" do
        behavior = described_class.from_config(:stop_on_first_tool)
        expect(behavior).to be_a(RAAF::ToolUseBehavior::StopOnFirstTool)
      end

      it "returns existing Base instance" do
        existing = RAAF::ToolUseBehavior::RunLLMAgain.new
        behavior = described_class.from_config(existing)
        expect(behavior).to eq(existing)
      end

      it "creates CustomFunction from Proc" do
        proc_config = proc { |_a, _tc, _r, _c| true }
        behavior = described_class.from_config(proc_config)
        expect(behavior).to be_a(RAAF::ToolUseBehavior::CustomFunction)
        expect(behavior.function).to eq(proc_config)
      end

      it "defaults to run_llm_again for unknown config" do
        behavior = described_class.from_config("unknown")
        expect(behavior).to be_a(RAAF::ToolUseBehavior::RunLLMAgain)
      end

      it "defaults to run_llm_again for nil config" do
        behavior = described_class.from_config(nil)
        expect(behavior).to be_a(RAAF::ToolUseBehavior::RunLLMAgain)
      end
    end
  end
end

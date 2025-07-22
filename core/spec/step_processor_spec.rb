# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::StepProcessor do
  let(:step_processor) { described_class.new }
  let(:agent) { create_test_agent(name: "TestAgent") }
  let(:context_wrapper) { double("RunContextWrapper") }
  let(:runner) { double("Runner") }
  let(:config) { RAAF::RunConfig.new }
  let(:original_input) { "Test input" }
  let(:pre_step_items) { [] }
  let(:model_response) do
    {
      id: "response_123",
      output: [
        {
          type: "message",
          role: "assistant",
          content: "Hello, I can help with that."
        }
      ],
      usage: { total_tokens: 25 }
    }
  end

  describe "#initialize" do
    it "initializes with response processor" do
      expect(step_processor.instance_variable_get(:@response_processor)).to be_a(RAAF::ResponseProcessor)
    end

    it "initializes with tool use tracker" do
      expect(step_processor.instance_variable_get(:@tool_use_tracker)).to be_a(RAAF::ToolUseTracker)
    end
  end

  describe "#execute_step" do
    let(:processed_response) { double("ProcessedResponse", new_items: [], tools_used: [], functions: [], computer_actions: [], local_shell_calls: []) }

    before do
      allow(step_processor).to receive_messages(process_model_response: processed_response, execute_tools_and_side_effects: [[], double("NextStep")])
      allow(processed_response).to receive(:handoffs_detected?).and_return(false)
    end

    it "processes model response" do
      expect(step_processor).to receive(:process_model_response)
        .with(model_response, agent)
        .and_return(processed_response)

      step_processor.execute_step(
        original_input: original_input,
        pre_step_items: pre_step_items,
        model_response: model_response,
        agent: agent,
        context_wrapper: context_wrapper,
        runner: runner,
        config: config
      )
    end

    it "executes tools and side effects" do
      expect(step_processor).to receive(:execute_tools_and_side_effects)
        .with(hash_including(
                agent: agent,
                original_input: original_input,
                pre_step_items: pre_step_items,
                processed_response: processed_response,
                context_wrapper: context_wrapper,
                runner: runner,
                config: config
              ))

      step_processor.execute_step(
        original_input: original_input,
        pre_step_items: pre_step_items,
        model_response: model_response,
        agent: agent,
        context_wrapper: context_wrapper,
        runner: runner,
        config: config
      )
    end

    it "creates and returns StepResult" do
      new_step_items = [double("Item")]
      next_step = double("NextStep")

      allow(step_processor).to receive(:execute_tools_and_side_effects)
        .and_return([new_step_items, next_step])

      result = step_processor.execute_step(
        original_input: original_input,
        pre_step_items: pre_step_items,
        model_response: model_response,
        agent: agent,
        context_wrapper: context_wrapper,
        runner: runner,
        config: config
      )

      expect(result).to be_a(RAAF::StepResult)
      expect(result.original_input).to eq(original_input)
      expect(result.model_response).to eq(model_response)
      expect(result.pre_step_items).to eq(pre_step_items)
      expect(result.new_step_items).to eq(new_step_items)
      expect(result.next_step).to eq(next_step)
    end

    it "logs step execution details" do
      allow(step_processor).to receive(:log_debug)

      step_processor.execute_step(
        original_input: original_input,
        pre_step_items: pre_step_items,
        model_response: model_response,
        agent: agent,
        context_wrapper: context_wrapper,
        runner: runner,
        config: config
      )

      expect(step_processor).to have_received(:log_debug)
        .with("🔄 STEP_PROCESSOR: Executing step", agent: agent.name)
    end
  end

  describe "#maybe_reset_tool_choice" do
    let(:tool_use_tracker) { double("ToolUseTracker") }

    before do
      step_processor.instance_variable_set(:@tool_use_tracker, tool_use_tracker)
    end

    context "when agent has reset_tool_choice enabled" do
      before do
        allow(agent).to receive(:reset_tool_choice).and_return(true)
        allow(agent).to receive(:tool_choice=)
      end

      it "resets tool choice when tools have been used" do
        allow(tool_use_tracker).to receive(:used_tools?).with(agent).and_return(true)

        expect(agent).to receive(:tool_choice=).with(nil)

        step_processor.maybe_reset_tool_choice(agent)
      end

      it "does not reset tool choice when no tools have been used" do
        allow(tool_use_tracker).to receive(:used_tools?).with(agent).and_return(false)

        expect(agent).not_to receive(:tool_choice=)

        step_processor.maybe_reset_tool_choice(agent)
      end

      it "logs when resetting tool choice" do
        allow(tool_use_tracker).to receive(:used_tools?).with(agent).and_return(true)
        allow(step_processor).to receive(:log_debug)

        step_processor.maybe_reset_tool_choice(agent)

        expect(step_processor).to have_received(:log_debug)
          .with("🔄 STEP_PROCESSOR: Resetting tool choice", agent: agent.name)
      end
    end

    context "when agent does not have reset_tool_choice enabled" do
      before do
        allow(agent).to receive(:reset_tool_choice).and_return(false)
      end

      it "does not reset tool choice regardless of tool usage" do
        allow(tool_use_tracker).to receive(:used_tools?).with(agent).and_return(true)

        expect(agent).not_to receive(:tool_choice=)

        step_processor.maybe_reset_tool_choice(agent)
      end
    end

    context "when agent does not respond to reset_tool_choice" do
      before do
        allow(agent).to receive(:reset_tool_choice).and_return(nil)
      end

      it "does not reset tool choice" do
        expect(agent).not_to receive(:tool_choice=)

        step_processor.maybe_reset_tool_choice(agent)
      end
    end
  end

  describe "private methods" do
    describe "#process_model_response" do
      let(:response_processor) { double("ResponseProcessor") }
      let(:processed_result) { double("ProcessedResponse") }

      before do
        step_processor.instance_variable_set(:@response_processor, response_processor)
        allow(agent).to receive_messages(tools: [], handoffs: [])
      end

      it "delegates to response processor with agent context" do
        expect(response_processor).to receive(:process_model_response)
          .with(
            response: model_response,
            agent: agent,
            all_tools: [],
            handoffs: []
          )
          .and_return(processed_result)

        result = step_processor.send(:process_model_response, model_response, agent)
        expect(result).to eq(processed_result)
      end

      it "includes agent tools and handoffs" do
        test_tools = [double("Tool")]
        test_handoffs = [double("Handoff")]

        allow(agent).to receive_messages(tools: test_tools, handoffs: test_handoffs)

        expect(response_processor).to receive(:process_model_response)
          .with(
            response: model_response,
            agent: agent,
            all_tools: test_tools,
            handoffs: test_handoffs
          )

        step_processor.send(:process_model_response, model_response, agent)
      end

      it "handles nil tools and handoffs gracefully" do
        allow(agent).to receive_messages(tools: nil, handoffs: nil)

        expect(response_processor).to receive(:process_model_response)
          .with(
            response: model_response,
            agent: agent,
            all_tools: [],
            handoffs: []
          )

        step_processor.send(:process_model_response, model_response, agent)
      end
    end

    describe "#execute_tools_and_side_effects" do
      let(:processed_response) do
        double("ProcessedResponse",
               new_items: [],
               tools_used: [],
               functions: [],
               computer_actions: [],
               local_shell_calls: [],
               handoffs_detected?: false,
               tools_or_actions_to_run?: false)
      end

      let(:tool_use_tracker) { double("ToolUseTracker") }

      before do
        step_processor.instance_variable_set(:@tool_use_tracker, tool_use_tracker)
        allow(tool_use_tracker).to receive(:add_tool_use)
      end

      it "tracks tool usage" do
        tools_used = [double("Tool")]
        allow(processed_response).to receive(:tools_used).and_return(tools_used)

        expect(tool_use_tracker).to receive(:add_tool_use).with(agent, tools_used)

        step_processor.send(:execute_tools_and_side_effects,
                            agent: agent,
                            original_input: original_input,
                            pre_step_items: pre_step_items,
                            processed_response: processed_response,
                            context_wrapper: context_wrapper,
                            runner: runner,
                            config: config)
      end

      it "returns new items and next step" do
        new_items = [double("Item", raw_item: { type: "generic_item" })]
        allow(processed_response).to receive(:new_items).and_return(new_items)

        new_step_items, next_step = step_processor.send(:execute_tools_and_side_effects,
                                                        agent: agent,
                                                        original_input: original_input,
                                                        pre_step_items: pre_step_items,
                                                        processed_response: processed_response,
                                                        context_wrapper: context_wrapper,
                                                        runner: runner,
                                                        config: config)

        expect(new_step_items).to be_an(Array)
        expect(next_step).to be_truthy
      end

      context "with function tools" do
        let(:functions) { [double("Function")] }
        let(:tool_results) { [double("ToolResult", run_item: double("RunItem", raw_item: { type: "tool_result" }))] }

        before do
          allow(processed_response).to receive(:functions).and_return(functions)
          allow(step_processor).to receive_messages(execute_function_tools_parallel: tool_results, check_for_final_output_from_tools: nil)
        end

        it "executes function tools in parallel" do
          expect(step_processor).to receive(:execute_function_tools_parallel)
            .with(functions, agent, context_wrapper, runner, config)

          step_processor.send(:execute_tools_and_side_effects,
                              agent: agent,
                              original_input: original_input,
                              pre_step_items: pre_step_items,
                              processed_response: processed_response,
                              context_wrapper: context_wrapper,
                              runner: runner,
                              config: config)
        end

        it "includes tool results in new step items" do
          new_step_items, = step_processor.send(:execute_tools_and_side_effects,
                                                agent: agent,
                                                original_input: original_input,
                                                pre_step_items: pre_step_items,
                                                processed_response: processed_response,
                                                context_wrapper: context_wrapper,
                                                runner: runner,
                                                config: config)

          expect(new_step_items).to include(tool_results.first.run_item)
        end

        it "checks for final output from tools" do
          expect(step_processor).to receive(:check_for_final_output_from_tools)
            .with(tool_results, agent, context_wrapper, config)

          step_processor.send(:execute_tools_and_side_effects,
                              agent: agent,
                              original_input: original_input,
                              pre_step_items: pre_step_items,
                              processed_response: processed_response,
                              context_wrapper: context_wrapper,
                              runner: runner,
                              config: config)
        end

        it "returns final output when found" do
          final_output = double("FinalOutput")
          allow(step_processor).to receive(:check_for_final_output_from_tools).and_return(final_output)

          _, next_step = step_processor.send(:execute_tools_and_side_effects,
                                             agent: agent,
                                             original_input: original_input,
                                             pre_step_items: pre_step_items,
                                             processed_response: processed_response,
                                             context_wrapper: context_wrapper,
                                             runner: runner,
                                             config: config)

          expect(next_step).to be_a(RAAF::NextStepFinalOutput)
          expect(next_step.output).to eq(final_output)
        end
      end

      context "with handoffs detected" do
        before do
          allow(processed_response).to receive(:handoffs_detected?).and_return(true)
          allow(step_processor).to receive(:execute_handoffs).and_return([[], double("NextStep")])
        end

        it "executes handoffs when detected" do
          expect(step_processor).to receive(:execute_handoffs)

          step_processor.send(:execute_tools_and_side_effects,
                              agent: agent,
                              original_input: original_input,
                              pre_step_items: pre_step_items,
                              processed_response: processed_response,
                              context_wrapper: context_wrapper,
                              runner: runner,
                              config: config)
        end
      end

      context "with computer actions" do
        let(:computer_actions) { [double("ComputerAction")] }
        let(:computer_results) { [double("ComputerResult", raw_item: { type: "computer_result" })] }

        before do
          allow(processed_response).to receive(:computer_actions).and_return(computer_actions)
          allow(step_processor).to receive(:execute_computer_actions).and_return(computer_results)
        end

        it "executes computer actions sequentially" do
          expect(step_processor).to receive(:execute_computer_actions)
            .with(computer_actions, agent, context_wrapper, runner, config)

          step_processor.send(:execute_tools_and_side_effects,
                              agent: agent,
                              original_input: original_input,
                              pre_step_items: pre_step_items,
                              processed_response: processed_response,
                              context_wrapper: context_wrapper,
                              runner: runner,
                              config: config)
        end

        it "includes computer results in new step items" do
          new_step_items, = step_processor.send(:execute_tools_and_side_effects,
                                                agent: agent,
                                                original_input: original_input,
                                                pre_step_items: pre_step_items,
                                                processed_response: processed_response,
                                                context_wrapper: context_wrapper,
                                                runner: runner,
                                                config: config)

          expect(new_step_items).to include(*computer_results)
        end
      end

      context "with local shell calls" do
        let(:shell_calls) { [double("ShellCall")] }
        let(:shell_results) { [double("ShellResult", raw_item: { type: "shell_result" })] }

        before do
          allow(processed_response).to receive(:local_shell_calls).and_return(shell_calls)
          allow(step_processor).to receive(:execute_local_shell_calls).and_return(shell_results)
        end

        it "executes local shell calls sequentially" do
          expect(step_processor).to receive(:execute_local_shell_calls)
            .with(shell_calls, agent, context_wrapper, runner, config)

          step_processor.send(:execute_tools_and_side_effects,
                              agent: agent,
                              original_input: original_input,
                              pre_step_items: pre_step_items,
                              processed_response: processed_response,
                              context_wrapper: context_wrapper,
                              runner: runner,
                              config: config)
        end

        it "includes shell results in new step items" do
          new_step_items, = step_processor.send(:execute_tools_and_side_effects,
                                                agent: agent,
                                                original_input: original_input,
                                                pre_step_items: pre_step_items,
                                                processed_response: processed_response,
                                                context_wrapper: context_wrapper,
                                                runner: runner,
                                                config: config)

          expect(new_step_items).to include(*shell_results)
        end
      end
    end
  end
end

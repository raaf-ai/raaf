# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Execution::ConversationManager do
  let(:config) { RAAF::RunConfig.new(max_turns: 3, metadata: { test: "value" }) }
  let(:conversation_manager) { described_class.new(config) }
  let(:agent) { create_test_agent(name: "TestAgent", max_turns: 5) }
  let(:executor) do
    double("RunExecutor").tap do |exec|
      mock_runner = double("Runner", should_stop?: false)
      allow(exec).to receive(:runner).and_return(mock_runner)
    end
  end
  let(:messages) { [{ role: "user", content: "Hello" }] }

  describe "#initialize" do
    it "stores configuration" do
      expect(conversation_manager.config).to eq(config)
    end

    it "initializes usage tracking" do
      expect(conversation_manager.accumulated_usage).to eq({
                                                             input_tokens: 0,
                                                             output_tokens: 0,
                                                             total_tokens: 0
                                                           })
    end
  end

  describe "#execute_conversation" do
    let(:mock_turn_result) do
      {
        should_continue: false,
        handoff_result: nil,
        usage: { input_tokens: 10, output_tokens: 15, total_tokens: 25 }
      }
    end

    before do
      # Mock the internal methods that would be called
      allow(conversation_manager).to receive(:check_execution_stop)
      allow(conversation_manager).to receive(:process_turn_result)
      allow(conversation_manager).to receive(:handle_max_turns_exceeded)
    end

    it "yields turn data for execution" do
      conversation_manager.execute_conversation(messages, agent, executor) do |turn_data|
        expect(turn_data).to include(
          conversation: messages,
          current_agent: agent,
          turns: 0
        )
        expect(turn_data[:context_wrapper]).to be_a(RAAF::RunContextWrapper)
        mock_turn_result
      end
    end

    it "creates context wrapper with configuration metadata" do
      conversation_manager.execute_conversation(messages, agent, executor) do |turn_data|
        expect(turn_data[:context_wrapper]).to be_a(RAAF::RunContextWrapper)
        expect(turn_data[:context_wrapper].context.metadata).to include(test: "value")
        mock_turn_result
      end
    end

    it "uses config max_turns when provided" do
      config_with_max_turns = RAAF::RunConfig.new(max_turns: 2)
      manager = described_class.new(config_with_max_turns)

      allow(manager).to receive(:check_execution_stop)
      allow(manager).to receive(:process_turn_result)

      turn_count = 0
      manager.execute_conversation(messages, agent, executor) do |_turn_data|
        turn_count += 1
        if turn_count >= 2
          # Simulate max turns reached
          expect(manager).to receive(:handle_max_turns_exceeded)
        end
        { should_continue: true, handoff_result: nil }
      end
    end

    it "falls back to agent max_turns when config doesn't specify" do
      config_without_max_turns = RAAF::RunConfig.new
      agent_with_max_turns = create_test_agent(name: "TestAgent", max_turns: 3)
      manager = described_class.new(config_without_max_turns)

      allow(manager).to receive(:check_execution_stop)
      allow(manager).to receive(:process_turn_result)

      turn_count = 0
      manager.execute_conversation(messages, agent_with_max_turns, executor) do |_turn_data|
        turn_count += 1
        expect(manager).to receive(:handle_max_turns_exceeded) if turn_count >= 3
        { should_continue: true, handoff_result: nil }
      end
    end

    context "single turn execution" do
      it "executes single turn and stops when should_continue is false" do
        result = conversation_manager.execute_conversation(messages, agent, executor) do |turn_data|
          expect(turn_data[:turns]).to eq(0)
          mock_turn_result
        end

        expect(result[:conversation]).to eq(messages)
        expect(result[:usage]).to eq(conversation_manager.accumulated_usage)
      end

      it "processes turn result" do
        expect(conversation_manager).to receive(:process_turn_result)
          .with(mock_turn_result, messages, agent)

        conversation_manager.execute_conversation(messages, agent, executor) do
          mock_turn_result
        end
      end

      it "checks execution stop before each turn" do
        expect(conversation_manager).to receive(:check_execution_stop)
          .with(messages, executor)

        conversation_manager.execute_conversation(messages, agent, executor) do
          mock_turn_result
        end
      end
    end

    context "multi-turn execution" do
      it "continues execution when should_continue is true" do
        turn_count = 0

        result = conversation_manager.execute_conversation(messages, agent, executor) do |turn_data|
          turn_count += 1
          case turn_count
          when 1
            expect(turn_data[:turns]).to eq(0)
            { should_continue: true, handoff_result: nil, usage: { total_tokens: 10 } }
          when 2
            expect(turn_data[:turns]).to eq(1)
            { should_continue: false, handoff_result: nil, usage: { total_tokens: 15 } }
          end
        end

        expect(turn_count).to eq(2)
        expect(result).to have_key(:conversation)
        expect(result).to have_key(:usage)
        expect(result).to have_key(:context_wrapper)
      end

      it "accumulates usage across turns" do
        # Create fresh manager to avoid global mocks
        fresh_manager = described_class.new(config)
        allow(fresh_manager).to receive(:check_execution_stop)
        allow(fresh_manager).to receive(:handle_max_turns_exceeded)

        fresh_manager.execute_conversation(messages, agent, executor) do
          {
            should_continue: false,
            handoff_result: nil,
            usage: { input_tokens: 10, output_tokens: 15, total_tokens: 25 }
          }
        end

        expect(fresh_manager.accumulated_usage).to eq({
                                                        input_tokens: 10,
                                                        output_tokens: 15,
                                                        total_tokens: 25
                                                      })
      end
    end

    context "agent handoff scenarios" do
      let(:new_agent) { create_test_agent(name: "NewAgent") }
      let(:handoff_result) { { handoff_occurred: true, new_agent: new_agent } }

      it "switches agent when handoff occurs" do
        turn_count = 0
        agents_seen = []

        conversation_manager.execute_conversation(messages, agent, executor) do |turn_data|
          agents_seen << turn_data[:current_agent]
          turn_count += 1

          case turn_count
          when 1
            # First turn with original agent, trigger handoff
            {
              should_continue: true,
              handoff_result: handoff_result,
              usage: { total_tokens: 10 }
            }
          when 2
            # Second turn should be with new agent
            { should_continue: false, handoff_result: nil, usage: { total_tokens: 15 } }
          end
        end

        expect(agents_seen[0]).to eq(agent)
        expect(agents_seen[1]).to eq(new_agent)
      end

      it "resets turn count after handoff" do
        turn_counts = []
        turn_total = 0

        conversation_manager.execute_conversation(messages, agent, executor) do |turn_data|
          turn_counts << turn_data[:turns]
          turn_total += 1

          case turn_total
          when 1
            # First turn (turns=0), trigger handoff
            { should_continue: true, handoff_result: handoff_result }
          when 2
            # After handoff, turns should reset to 0
            { should_continue: false, handoff_result: nil }
          end
        end

        expect(turn_counts).to eq([0, 0]) # Both turns should show 0 (reset after handoff)
      end

      it "continues conversation with new agent after handoff" do
        result = conversation_manager.execute_conversation(messages, agent, executor) do |turn_data|
          if turn_data[:current_agent] == agent
            { should_continue: true, handoff_result: handoff_result }
          else
            { should_continue: false, handoff_result: nil }
          end
        end

        expect(result).to be_a(Hash)
        expect(result).to have_key(:conversation)
        expect(result).to have_key(:usage)
      end
    end

    context "max turns handling" do
      it "handles max turns exceeded scenario" do
        short_config = RAAF::RunConfig.new(max_turns: 1)
        short_manager = described_class.new(short_config)

        allow(short_manager).to receive(:check_execution_stop)
        allow(short_manager).to receive(:process_turn_result)

        expect(short_manager).to receive(:handle_max_turns_exceeded)
          .with(messages, 1)

        short_manager.execute_conversation(messages, agent, executor) do
          { should_continue: true, handoff_result: nil }
        end
      end
    end
  end

  describe "#accumulate_usage" do
    context "with standard usage format" do
      it "accumulates input_tokens, output_tokens, and total_tokens" do
        usage = { input_tokens: 10, output_tokens: 15, total_tokens: 25 }
        conversation_manager.accumulate_usage(usage)

        expect(conversation_manager.accumulated_usage).to eq({
                                                               input_tokens: 10,
                                                               output_tokens: 15,
                                                               total_tokens: 25
                                                             })
      end

      it "accumulates multiple usage reports" do
        conversation_manager.accumulate_usage({ input_tokens: 5, output_tokens: 8, total_tokens: 13 })
        conversation_manager.accumulate_usage({ input_tokens: 3, output_tokens: 7, total_tokens: 10 })

        expect(conversation_manager.accumulated_usage).to eq({
                                                               input_tokens: 8,
                                                               output_tokens: 15,
                                                               total_tokens: 23
                                                             })
      end
    end

    context "with legacy usage format" do
      it "handles prompt_tokens and completion_tokens" do
        legacy_usage = { prompt_tokens: 12, completion_tokens: 8, total_tokens: 20 }
        conversation_manager.accumulate_usage(legacy_usage)

        expect(conversation_manager.accumulated_usage[:input_tokens]).to eq(12)
        expect(conversation_manager.accumulated_usage[:output_tokens]).to eq(8)
        expect(conversation_manager.accumulated_usage[:total_tokens]).to eq(20)
      end
    end

    context "with mixed or partial usage data" do
      it "handles missing fields gracefully" do
        partial_usage = { total_tokens: 15 }
        conversation_manager.accumulate_usage(partial_usage)

        expect(conversation_manager.accumulated_usage).to eq({
                                                               input_tokens: 0,
                                                               output_tokens: 0,
                                                               total_tokens: 15
                                                             })
      end

      it "handles nil usage gracefully" do
        expect { conversation_manager.accumulate_usage(nil) }.not_to raise_error

        expect(conversation_manager.accumulated_usage).to eq({
                                                               input_tokens: 0,
                                                               output_tokens: 0,
                                                               total_tokens: 0
                                                             })
      end

      it "prefers new format over legacy format" do
        mixed_usage = {
          input_tokens: 10,
          prompt_tokens: 5, # Should be ignored
          output_tokens: 8,
          completion_tokens: 3, # Should be ignored
          total_tokens: 18
        }
        conversation_manager.accumulate_usage(mixed_usage)

        expect(conversation_manager.accumulated_usage).to eq({
                                                               input_tokens: 10,
                                                               output_tokens: 8,
                                                               total_tokens: 18
                                                             })
      end
    end
  end

  describe "private methods" do
    describe "#initialize_usage_tracking" do
      it "returns initial usage structure" do
        initial_usage = conversation_manager.send(:initialize_usage_tracking)

        expect(initial_usage).to eq({
                                      input_tokens: 0,
                                      output_tokens: 0,
                                      total_tokens: 0
                                    })
      end
    end

    describe "#create_context_wrapper" do
      it "creates context wrapper with conversation and config data" do
        context_wrapper = conversation_manager.send(:create_context_wrapper, messages)

        expect(context_wrapper).to be_a(RAAF::RunContextWrapper)
        expect(context_wrapper.context).to be_a(RAAF::RunContext)
        expect(context_wrapper.context.messages).to eq(messages)
        expect(context_wrapper.context.metadata).to include(test: "value")
      end

      it "includes trace_id and group_id from config" do
        config_with_ids = RAAF::RunConfig.new(trace_id: "trace123", group_id: "group456")
        manager_with_ids = described_class.new(config_with_ids)

        context_wrapper = manager_with_ids.send(:create_context_wrapper, messages)

        expect(context_wrapper.context.trace_id).to eq("trace123")
        expect(context_wrapper.context.group_id).to eq("group456")
      end

      it "handles nil metadata gracefully" do
        config_no_metadata = RAAF::RunConfig.new
        manager_no_metadata = described_class.new(config_no_metadata)

        context_wrapper = manager_no_metadata.send(:create_context_wrapper, messages)

        expect(context_wrapper.context.metadata).to eq({})
      end
    end

    # Comprehensive test scenarios
    context "multi-turn conversations" do
      it "properly tracks conversation flow across multiple turns" do
        messages = [
          { role: "user", content: "First message" },
          { role: "assistant", content: "First response" },
          { role: "user", content: "Second message" }
        ]

        turn_count = 0
        conversation_manager.execute_conversation(messages, agent, executor) do |data|
          turn_count += 1
          expect(data[:turns]).to eq(turn_count - 1) # turns is 0-indexed
          expect(data[:conversation]).to be_an(Array)
          expect(data[:context_wrapper]).to be_a(RAAF::RunContextWrapper)
          { should_continue: false, handoff_result: nil }
        end

        expect(turn_count).to be > 0
      end

      it "accumulates token usage across turns" do
        messages = [{ role: "user", content: "Test message" }]

        conversation_manager.execute_conversation(messages, agent, executor) do |_data|
          # Return a result with usage data
          {
            should_continue: false,
            handoff_result: nil,
            usage: { input_tokens: 10, output_tokens: 15, total_tokens: 25 }
          }
        end

        # Verify usage is being tracked
        expect(conversation_manager.accumulated_usage[:total_tokens]).to eq(25)
      end

      it "handles configuration limits properly" do
        limited_config = RAAF::RunConfig.new(max_turns: 2)
        limited_manager = described_class.new(limited_config)

        messages = [{ role: "user", content: "Test message" }]
        turn_count = 0

        limited_manager.execute_conversation(messages, agent, executor) do |_data|
          turn_count += 1
          expect(turn_count).to be <= limited_config.max_turns
          { should_continue: false, handoff_result: nil }
        end
      end
    end

    context "error handling and resilience" do
      it "handles executor failures gracefully" do
        messages = [{ role: "user", content: "Test message" }]

        expect do
          conversation_manager.execute_conversation(messages, agent, executor) do |_data|
            # Simulate an error in the block
            raise StandardError, "Executor error"
          end
        end.to raise_error(StandardError, "Executor error")
      end

      it "preserves message integrity during errors" do
        original_messages = [
          { role: "user", content: "Original message" },
          { role: "assistant", content: "Original response" }
        ]

        messages_copy = original_messages.dup

        # Even if something goes wrong, original messages should be preserved
        begin
          conversation_manager.execute_conversation(messages_copy, agent, executor) do |_data|
            # Normal processing
            { should_continue: false, handoff_result: nil }
          end
        rescue StandardError
          # Ignore errors for this test
        end

        expect(original_messages).to eq([
                                          { role: "user", content: "Original message" },
                                          { role: "assistant", content: "Original response" }
                                        ])
      end
    end
  end
end

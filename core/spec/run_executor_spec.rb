# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::RunExecutor do
  let(:agent) { create_test_agent(name: "TestAgent", instructions: "You are helpful") }
  let(:mock_provider) { create_mock_provider }
  let(:runner) { RAAF::Runner.new(agent: agent, provider: mock_provider) }
  let(:config) { RAAF::RunConfig.new(max_turns: 5) }

  let(:basic_executor) { described_class.new(runner: runner, provider: mock_provider, agent: agent, config: config) }

  let(:messages) do
    [{ role: "user", content: "Hello, how are you?" }]
  end

  describe "#initialize" do
    it "creates executor with required dependencies" do
      executor = described_class.new(runner: runner, provider: mock_provider, agent: agent, config: config)

      expect(executor.runner).to eq(runner)
      expect(executor.provider).to eq(mock_provider)
      expect(executor.agent).to eq(agent)
      expect(executor.config).to eq(config)
    end

    it "creates service bundle via factory" do
      expect(RAAF::Execution::ExecutorFactory).to receive(:create_service_bundle)
        .with(runner: runner, provider: mock_provider, agent: agent, config: config)
        .and_call_original

      executor = described_class.new(runner: runner, provider: mock_provider, agent: agent, config: config)

      expect(executor.services).to be_a(Hash)
      expect(executor.services).to have_key(:conversation_manager)
      expect(executor.services).to have_key(:tool_executor)
      expect(executor.services).to have_key(:error_handler)
      expect(executor.services).to have_key(:api_strategy)
      expect(executor.services).to have_key(:turn_executor)
    end
  end

  describe "#execute" do
    context "with ResponsesProvider" do
      let(:responses_provider) { RAAF::Models::ResponsesProvider.new }
      let(:responses_executor) { described_class.new(runner: runner, provider: responses_provider, agent: agent, config: config) }

      before do
        # Mock the API strategy service
        api_strategy = double("ApiStrategy")
        allow(api_strategy).to receive(:execute).with(messages, agent, runner).and_return({
                                                                                            final_result: true,
                                                                                            conversation: messages + [{ role: "assistant", content: "Hello! I'm doing well, thank you." }],
                                                                                            usage: { input_tokens: 10, output_tokens: 15, total_tokens: 25 },
                                                                                            last_agent: agent
                                                                                          })

        allow(responses_executor.services).to receive(:[]).with(:api_strategy).and_return(api_strategy)

        error_handler = double("ErrorHandler")
        allow(error_handler).to receive(:with_error_handling) do |context:, &block|
          block.call
        end
        allow(responses_executor.services).to receive(:[]).with(:error_handler).and_return(error_handler)
      end

      it "uses responses API strategy" do
        expect(responses_executor.services[:api_strategy]).to receive(:execute)
          .with(messages, agent, runner)
          .and_return({
                        final_result: true,
                        conversation: messages + [{ role: "assistant", content: "Response" }],
                        usage: { total_tokens: 25 },
                        last_agent: agent
                      })

        result = responses_executor.execute(messages)

        expect(result).to be_a(RAAF::RunResult)
        expect(result.last_agent).to eq(agent)
      end

      it "handles API strategy results correctly" do
        expected_conversation = messages + [{ role: "assistant", content: "Hello! I'm doing well." }]
        expected_usage = { input_tokens: 10, output_tokens: 15, total_tokens: 25 }

        allow(responses_executor.services[:api_strategy]).to receive(:execute).and_return({
                                                                                            final_result: true,
                                                                                            conversation: expected_conversation,
                                                                                            usage: expected_usage,
                                                                                            last_agent: agent
                                                                                          })

        result = responses_executor.execute(messages)

        # System message is added automatically for Python SDK compatibility
        expected_result_messages = [
          { role: "system", content: "Name: TestAgent\nInstructions: You are helpful" }
        ] + expected_conversation
        expect(result.messages).to eq(expected_result_messages)
        expect(result.usage).to eq(expected_usage)
        expect(result.last_agent).to eq(agent)
      end

      it "handles incomplete API strategy results gracefully" do
        allow(responses_executor.services[:api_strategy]).to receive(:execute).and_return({
                                                                                            final_result: false
                                                                                          })

        result = responses_executor.execute(messages)

        # System message is added automatically
        expected_result_messages = [
          { role: "system", content: "Name: TestAgent\nInstructions: You are helpful" }
        ] + messages
        expect(result.messages).to eq(expected_result_messages)
        expect(result.usage).to eq({})
        expect(result.last_agent).to eq(agent)
      end
    end

    context "with non-ResponsesProvider" do
      let(:openai_provider) { RAAF::Models::OpenAIProvider.new }
      let(:openai_executor) { described_class.new(runner: runner, provider: openai_provider, agent: agent, config: config) }

      before do
        # Mock the conversation manager service
        conversation_manager = double("ConversationManager")
        allow(conversation_manager).to receive(:execute_conversation).and_yield({
                                                                                  conversation: messages,
                                                                                  agent: agent,
                                                                                  turn: 1,
                                                                                  usage: {}
                                                                                }).and_return({
                                                                                                conversation: messages + [{ role: "assistant", content: "Response" }],
                                                                                                usage: { total_tokens: 20 },
                                                                                                context_wrapper: nil
                                                                                              })

        turn_executor = double("TurnExecutor")
        allow(turn_executor).to receive(:execute_turn)

        allow(openai_executor.services).to receive(:[]).with(:conversation_manager).and_return(conversation_manager)
        allow(openai_executor.services).to receive(:[]).with(:turn_executor).and_return(turn_executor)

        error_handler = double("ErrorHandler")
        allow(error_handler).to receive(:with_error_handling) do |context:, &block|
          block.call
        end
        allow(openai_executor.services).to receive(:[]).with(:error_handler).and_return(error_handler)
      end

      it "uses conversation manager strategy" do
        expect(openai_executor.services[:conversation_manager]).to receive(:execute_conversation)
          .with(messages, agent, openai_executor)

        openai_executor.execute(messages)
      end

      it "passes turn data to turn executor" do
        turn_data = {
          conversation: messages,
          agent: agent,
          turn: 1,
          usage: {}
        }

        expect(openai_executor.services[:turn_executor]).to receive(:execute_turn)
          .with(turn_data, openai_executor, runner)

        openai_executor.execute(messages)
      end

      it "creates result from conversation manager output" do
        expected_conversation = messages + [{ role: "assistant", content: "Response" }]
        expected_usage = { total_tokens: 20 }

        allow(openai_executor.services[:conversation_manager]).to receive(:execute_conversation).and_return({
                                                                                                              conversation: expected_conversation,
                                                                                                              usage: expected_usage,
                                                                                                              context_wrapper: nil
                                                                                                            })

        result = openai_executor.execute(messages)

        # System message is added automatically
        expected_result_messages = [
          { role: "system", content: "Name: TestAgent\nInstructions: You are helpful" }
        ] + expected_conversation
        expect(result.messages).to eq(expected_result_messages)
        expect(result.usage).to eq(expected_usage)
        expect(result.last_agent).to eq(agent)
      end
    end

    context "error handling integration" do
      it "wraps execution in error handler" do
        error_handler = double("ErrorHandler")
        expect(error_handler).to receive(:with_error_handling)
          .with(context: { executor: "RAAF::RunExecutor" })
          .and_yield

        # Use allow to stub all service calls
        services_double = {
          error_handler: error_handler,
          conversation_manager: double("ConversationManager", execute_conversation: { conversation: [], usage: {}, context_wrapper: nil }),
          turn_executor: double("TurnExecutor", execute_turn: nil),
          api_strategy: double("ApiStrategy", execute: { final_result: true, conversation: [], usage: {}, last_agent: agent })
        }
        
        allow(basic_executor).to receive(:services).and_return(services_double)

        basic_executor.execute(messages)
      end

      it "allows error handler to catch and handle exceptions" do
        error_handler = double("ErrorHandler")
        expect(error_handler).to receive(:with_error_handling) do |&block|
          block.call
        rescue StandardError
          # Simulate error handler catching and handling the exception
          "error handled"
        end

        # Create an API strategy that raises an error
        api_strategy = double("ApiStrategy")
        allow(api_strategy).to receive(:execute).and_raise(StandardError, "Test error")
        
        services_double = {
          error_handler: error_handler,
          api_strategy: api_strategy,
          conversation_manager: double("ConversationManager"),
          turn_executor: double("TurnExecutor")
        }
        
        allow(basic_executor).to receive(:services).and_return(services_double)

        result = basic_executor.execute(messages)
        expect(result).to eq("error handled")
      end
    end
  end

  describe "#create_result" do
    let(:conversation) { [{ role: "user", content: "test" }, { role: "assistant", content: "response" }] }
    let(:usage) { { input_tokens: 5, output_tokens: 8, total_tokens: 13 } }
    let(:context_wrapper) { double("ContextWrapper", context: double("Context", metadata: { trace_id: "123" }), messages: nil) }

    it "creates RunResult with provided parameters" do
      result = basic_executor.send(:create_result, conversation, usage, context_wrapper, agent)

      expect(result).to be_a(RAAF::RunResult)
      # The system message is now automatically added for Python SDK compatibility
      expected_messages = [
        { role: "system", content: "Name: TestAgent\nInstructions: You are helpful" },
        { role: "user", content: "test" },
        { role: "assistant", content: "response" }
      ]
      expect(result.messages).to eq(expected_messages)
      expect(result.last_agent).to eq(agent)
      expect(result.usage).to eq(usage)
      expect(result.metadata).to eq({ trace_id: "123" })
    end

    it "uses default agent when final_agent is nil" do
      result = basic_executor.send(:create_result, conversation, usage, nil, nil)

      expect(result.last_agent).to eq(agent)
    end

    it "handles nil context_wrapper gracefully" do
      result = basic_executor.send(:create_result, conversation, usage, nil, agent)

      expect(result.metadata).to eq({})
    end

    it "prefers provided final_agent over default agent" do
      other_agent = create_test_agent(name: "OtherAgent")
      result = basic_executor.send(:create_result, conversation, usage, nil, other_agent)

      expect(result.last_agent).to eq(other_agent)
    end
  end
end

RSpec.describe RAAF::TracedRunExecutor do
  let(:agent) { create_test_agent(name: "TracedAgent") }
  let(:mock_provider) { create_mock_provider }
  let(:runner) { RAAF::Runner.new(agent: agent, provider: mock_provider) }
  let(:config) { RAAF::RunConfig.new }
  let(:tracer) { double("Tracer") }

  let(:traced_executor) { described_class.new(runner: runner, provider: mock_provider, agent: agent, config: config, tracer: tracer) }

  describe "#initialize" do
    it "inherits from RunExecutor" do
      expect(traced_executor).to be_a(RAAF::RunExecutor)
    end

    it "stores tracer reference" do
      expect(traced_executor.tracer).to eq(tracer)
    end

    it "calls parent constructor" do
      expect(traced_executor.runner).to eq(runner)
      expect(traced_executor.provider).to eq(mock_provider)
      expect(traced_executor.agent).to eq(agent)
      expect(traced_executor.config).to eq(config)
    end

    it "creates service bundle through parent" do
      expect(traced_executor.services).to be_a(Hash)
      expect(traced_executor.services).to have_key(:conversation_manager)
    end
  end

  describe "tracing integration" do
    let(:messages) { [{ role: "user", content: "trace test" }] }

    before do
      # Mock the services for clean testing
      allow(traced_executor.services).to receive(:[]).with(:error_handler).and_return(
        double("ErrorHandler", with_error_handling: nil)
      )
      allow(traced_executor.services).to receive(:[]).with(:api_strategy).and_return(
        double("ApiStrategy", execute: { final_result: false })
      )
    end

    it "maintains all parent functionality with tracing context" do
      # The TracedRunExecutor should execute the same way as RunExecutor
      # but with additional tracing context (implementation details would be tested
      # when the tracing functionality is fully implemented)

      expect { traced_executor.execute(messages) }.not_to raise_error
    end

    it "provides tracer access for tracing implementations" do
      # Verify that tracer is accessible for implementations that add tracing
      expect(traced_executor.tracer).to be_truthy
    end
  end
end

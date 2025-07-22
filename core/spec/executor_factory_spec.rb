# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Execution::ExecutorFactory do
  let(:agent) { create_test_agent(name: "TestAgent") }
  let(:provider) { create_mock_provider }
  let(:runner) { double("Runner") }
  let(:config) { RAAF::RunConfig.new(max_turns: 5) }

  describe ".create_service_bundle" do
    let(:service_bundle) do
      described_class.create_service_bundle(
        runner: runner,
        provider: provider,
        agent: agent,
        config: config
      )
    end

    it "creates a hash with all required services" do
      expect(service_bundle).to be_a(Hash)
      expect(service_bundle).to have_key(:conversation_manager)
      expect(service_bundle).to have_key(:tool_executor)
      expect(service_bundle).to have_key(:handoff_detector)
      expect(service_bundle).to have_key(:api_strategy)
      expect(service_bundle).to have_key(:error_handler)
      expect(service_bundle).to have_key(:turn_executor)
    end

    it "creates ConversationManager with config" do
      expect(service_bundle[:conversation_manager]).to be_a(RAAF::Execution::ConversationManager)
      expect(service_bundle[:conversation_manager].config).to eq(config)
    end

    it "creates ToolExecutor with agent and runner" do
      expect(service_bundle[:tool_executor]).to be_a(RAAF::Execution::ToolExecutor)
      expect(service_bundle[:tool_executor].instance_variable_get(:@agent)).to eq(agent)
      expect(service_bundle[:tool_executor].instance_variable_get(:@runner)).to eq(runner)
    end

    it "creates HandoffDetector with agent and runner" do
      expect(service_bundle[:handoff_detector]).to be_a(RAAF::Execution::HandoffDetector)
      expect(service_bundle[:handoff_detector].instance_variable_get(:@agent)).to eq(agent)
      expect(service_bundle[:handoff_detector].instance_variable_get(:@runner)).to eq(runner)
    end

    it "creates ErrorHandler with default settings" do
      expect(service_bundle[:error_handler]).to be_a(RAAF::Execution::ErrorHandler)
      expect(service_bundle[:error_handler].strategy).to eq(RAAF::Execution::ErrorHandler::RecoveryStrategy::FAIL_FAST)
    end

    it "creates ApiStrategy through factory" do
      expect(service_bundle[:api_strategy]).to respond_to(:execute)
      # Should be one of the strategy types
      expect(service_bundle[:api_strategy]).to be_a(RAAF::Execution::BaseApiStrategy)
    end

    it "creates TurnExecutor with service dependencies" do
      expect(service_bundle[:turn_executor]).to be_a(RAAF::Execution::TurnExecutor)

      # TurnExecutor should be created with the other services
      turn_executor = service_bundle[:turn_executor]
      expect(turn_executor.instance_variable_get(:@tool_executor)).to eq(service_bundle[:tool_executor])
      expect(turn_executor.instance_variable_get(:@handoff_detector)).to eq(service_bundle[:handoff_detector])
      expect(turn_executor.instance_variable_get(:@api_strategy)).to eq(service_bundle[:api_strategy])
    end

    it "logs service bundle creation" do
      expect(described_class).to receive(:log_debug_general)
        .with("Creating service bundle", provider: provider.class.name, agent: agent.name)

      described_class.create_service_bundle(
        runner: runner,
        provider: provider,
        agent: agent,
        config: config
      )
    end

    context "with different provider types" do
      it "creates ResponsesApiStrategy for ResponsesProvider" do
        responses_provider = RAAF::Models::ResponsesProvider.new

        bundle = described_class.create_service_bundle(
          runner: runner,
          provider: responses_provider,
          agent: agent,
          config: config
        )

        expect(bundle[:api_strategy]).to be_a(RAAF::Execution::ResponsesApiStrategy)
      end

      it "creates StandardApiStrategy for OpenAIProvider" do
        openai_provider = RAAF::Models::OpenAIProvider.new

        bundle = described_class.create_service_bundle(
          runner: runner,
          provider: openai_provider,
          agent: agent,
          config: config
        )

        expect(bundle[:api_strategy]).to be_a(RAAF::Execution::StandardApiStrategy)
      end
    end

    context "with different agent types" do
      it "handles agents that respond to name method" do
        named_agent = create_test_agent(name: "NamedAgent")

        expect(described_class).to receive(:log_debug_general)
          .with("Creating service bundle", provider: provider.class.name, agent: "NamedAgent")

        described_class.create_service_bundle(
          runner: runner,
          provider: provider,
          agent: named_agent,
          config: config
        )
      end

      it "handles agents that don't respond to name method" do
        agent_without_name = double("AgentWithoutName")
        allow(agent_without_name).to receive(:respond_to?).with(:name).and_return(false)

        expect(described_class).to receive(:log_debug_general)
          .with("Creating service bundle", provider: provider.class.name, agent: agent_without_name.class.name)

        described_class.create_service_bundle(
          runner: runner,
          provider: provider,
          agent: agent_without_name,
          config: config
        )
      end
    end

    context "service dependency wiring" do
      it "wires services together correctly" do
        # Each service should have access to the dependencies it needs
        bundle = service_bundle

        # ConversationManager needs config
        expect(bundle[:conversation_manager].config).to eq(config)

        # ToolExecutor needs agent and runner
        tool_executor = bundle[:tool_executor]
        expect(tool_executor.instance_variable_get(:@agent)).to eq(agent)
        expect(tool_executor.instance_variable_get(:@runner)).to eq(runner)

        # HandoffDetector needs agent and runner
        handoff_detector = bundle[:handoff_detector]
        expect(handoff_detector.instance_variable_get(:@agent)).to eq(agent)
        expect(handoff_detector.instance_variable_get(:@runner)).to eq(runner)

        # ApiStrategy needs provider and config
        api_strategy = bundle[:api_strategy]
        expect(api_strategy.provider).to eq(provider)
        expect(api_strategy.config).to eq(config)

        # TurnExecutor needs other services
        turn_executor = bundle[:turn_executor]
        expect(turn_executor.instance_variable_get(:@tool_executor)).to eq(tool_executor)
        expect(turn_executor.instance_variable_get(:@handoff_detector)).to eq(handoff_detector)
        expect(turn_executor.instance_variable_get(:@api_strategy)).to eq(api_strategy)
      end

      it "creates independent service instances" do
        bundle1 = described_class.create_service_bundle(runner: runner, provider: provider, agent: agent, config: config)
        bundle2 = described_class.create_service_bundle(runner: runner, provider: provider, agent: agent, config: config)

        # Each bundle should have independent service instances
        expect(bundle1[:conversation_manager]).not_to be(bundle2[:conversation_manager])
        expect(bundle1[:tool_executor]).not_to be(bundle2[:tool_executor])
        expect(bundle1[:handoff_detector]).not_to be(bundle2[:handoff_detector])
        expect(bundle1[:error_handler]).not_to be(bundle2[:error_handler])
        expect(bundle1[:api_strategy]).not_to be(bundle2[:api_strategy])
        expect(bundle1[:turn_executor]).not_to be(bundle2[:turn_executor])
      end
    end

    context "error handling" do
      it "handles service creation failures gracefully" do
        # Mock a service creation failure
        allow(RAAF::Execution::ConversationManager).to receive(:new).and_raise(StandardError, "Service creation failed")

        expect do
          described_class.create_service_bundle(runner: runner, provider: provider, agent: agent, config: config)
        end.to raise_error(StandardError, "Service creation failed")
      end
    end
  end

  describe ".create_basic_executor" do
    it "creates a BasicRunExecutor with correct dependencies" do
      executor = described_class.create_basic_executor(
        runner: runner,
        provider: provider,
        agent: agent,
        config: config
      )

      expect(executor).to be_a(RAAF::RunExecutor) # BasicRunExecutor inherits from RunExecutor
      expect(executor.runner).to eq(runner)
      expect(executor.provider).to eq(provider)
      expect(executor.agent).to eq(agent)
      expect(executor.config).to eq(config)
    end

    it "creates executor with service bundle" do
      executor = described_class.create_basic_executor(
        runner: runner,
        provider: provider,
        agent: agent,
        config: config
      )

      expect(executor.services).to be_a(Hash)
      expect(executor.services).to have_key(:conversation_manager)
      expect(executor.services).to have_key(:tool_executor)
      expect(executor.services).to have_key(:api_strategy)
    end
  end

  describe ".create_traced_executor" do
    let(:tracer) { double("Tracer") }

    it "creates a TracedRunExecutor with correct dependencies" do
      executor = described_class.create_traced_executor(
        runner: runner,
        provider: provider,
        agent: agent,
        config: config,
        tracer: tracer
      )

      expect(executor).to be_a(RAAF::TracedRunExecutor)
      expect(executor.runner).to eq(runner)
      expect(executor.provider).to eq(provider)
      expect(executor.agent).to eq(agent)
      expect(executor.config).to eq(config)
      expect(executor.tracer).to eq(tracer)
    end

    it "creates traced executor with service bundle" do
      executor = described_class.create_traced_executor(
        runner: runner,
        provider: provider,
        agent: agent,
        config: config,
        tracer: tracer
      )

      expect(executor.services).to be_a(Hash)
      expect(executor.services).to have_key(:conversation_manager)
      expect(executor.services).to have_key(:tool_executor)
      expect(executor.services).to have_key(:api_strategy)
    end

    it "requires tracer parameter" do
      expect do
        described_class.create_traced_executor(
          runner: runner,
          provider: provider,
          agent: agent,
          config: config
          # Missing tracer parameter
        )
      end.to raise_error(ArgumentError)
    end
  end

  describe ".log_debug_general" do
    context "when RAAF::Logging is defined" do
      before do
        # Mock the logging module
        stub_const("RAAF::Logging", double("Logging"))
      end

      it "calls RAAF::Logging.debug with correct parameters" do
        message = "Test message"
        context = { key: "value" }

        expect(RAAF::Logging).to receive(:debug)
          .with(message, category: :general, key: "value")

        described_class.log_debug_general(message, context)
      end

      it "handles empty context" do
        expect(RAAF::Logging).to receive(:debug)
          .with("Test", category: :general)

        described_class.log_debug_general("Test")
      end
    end

    context "when RAAF::Logging is not defined" do
      it "does not raise error when logging module unavailable" do
        # Ensure RAAF::Logging is not defined for this test
        hide_const("RAAF::Logging") if defined?(RAAF::Logging)

        expect do
          described_class.log_debug_general("Test message", { context: "value" })
        end.not_to raise_error
      end
    end
  end

  describe "integration with other components" do
    it "creates service bundles that work together" do
      # Create a service bundle and verify services can interact
      bundle = described_class.create_service_bundle(
        runner: runner,
        provider: provider,
        agent: agent,
        config: config
      )

      # Verify conversation manager can accumulate usage
      usage = { input_tokens: 10, output_tokens: 15, total_tokens: 25 }
      expect do
        bundle[:conversation_manager].accumulate_usage(usage)
      end.not_to raise_error

      expect(bundle[:conversation_manager].accumulated_usage[:total_tokens]).to eq(25)
    end

    it "creates executors that can execute basic operations" do
      executor = described_class.create_basic_executor(
        runner: runner,
        provider: provider,
        agent: agent,
        config: config
      )

      # Verify executor has access to all required services
      expect(executor.services[:conversation_manager]).to respond_to(:execute_conversation)
      expect(executor.services[:tool_executor]).to respond_to(:execute_tool_calls)
      expect(executor.services[:handoff_detector]).to respond_to(:check_for_handoff)
      expect(executor.services[:error_handler]).to respond_to(:with_error_handling)
      expect(executor.services[:api_strategy]).to respond_to(:execute)
    end
  end

  describe "service lifecycle management" do
    it "creates fresh services for each bundle" do
      # Verify that each service bundle gets fresh instances
      bundle1 = described_class.create_service_bundle(runner: runner, provider: provider, agent: agent, config: config)
      bundle2 = described_class.create_service_bundle(runner: runner, provider: provider, agent: agent, config: config)

      bundle1[:conversation_manager].accumulate_usage({ total_tokens: 100 })
      bundle2[:conversation_manager].accumulate_usage({ total_tokens: 50 })

      # Each should maintain independent state
      expect(bundle1[:conversation_manager].accumulated_usage[:total_tokens]).to eq(100)
      expect(bundle2[:conversation_manager].accumulated_usage[:total_tokens]).to eq(50)
    end
  end
end

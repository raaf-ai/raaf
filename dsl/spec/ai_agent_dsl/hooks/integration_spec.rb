# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Hooks Integration" do
  let(:test_agent) { double("OpenAI::Agent", name: "test_agent") }
  let(:test_result) { { success: true, data: "test result" } }
  let(:test_error) { StandardError.new("test error") }

  # Test agent class that includes both AgentHooks and Base
  let(:agent_class) do
    Class.new(AiAgentDsl::Agents::Base) do
      include AiAgentDsl::AgentDsl
      include AiAgentDsl::Hooks::AgentHooks

      agent_name "test_agent"
      model "gpt-4"

      def self.name
        "TestHooksAgent"
      end

      def initialize
        super
        @execution_order = []
      end

      attr_reader :execution_order

      def log_start(*_args)
        @execution_order << "log_start"
      end

      def log_end(*_args)
        @execution_order << "log_end"
      end

      def log_handoff(*_args)
        @execution_order << "log_handoff"
      end

      def log_tool_start(*_args)
        @execution_order << "log_tool_start"
      end

      def log_tool_end(*_args)
        @execution_order << "log_tool_end"
      end

      def log_error(*_args)
        @execution_order << "log_error"
      end
    end
  end

  let(:agent_instance) { agent_class.new }

  before do
    # Clear global hooks before each test
    AiAgentDsl::Hooks::RunHooks.clear_hooks!

    # Clear agent hooks before each test
    agent_class.clear_agent_hooks! if agent_class.respond_to?(:clear_agent_hooks!)

    # Mock OpenAI Agent and OpenAIAgents module
    openai_agents = Module.new do
      const_set(:Agent, Class.new do
        def initialize(**params)
          # Mock agent initialization
        end
      end)
      const_set(:Runner, Class.new do
        def initialize(**params)
          # Mock runner initialization
        end

        def run(prompt)
          # Mock runner run method
        end
      end)
    end
    stub_const("OpenAIAgents", openai_agents)

    # Mock OpenAI Agent creation
    allow(agent_instance).to receive(:create_openai_agent_instance).and_return(test_agent)
  end

  after do
    # Clear global hooks after each test
    AiAgentDsl::Hooks::RunHooks.clear_hooks!
  end

  describe "hooks configuration building" do
    it "builds hooks configuration with global hooks only" do
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| "global start" }
      AiAgentDsl::Hooks::RunHooks.on_agent_end { |_agent, _result| "global end" }

      hooks_config = agent_instance.send(:build_hooks_config)

      expect(hooks_config).to have_key(:on_agent_start)
      expect(hooks_config).to have_key(:on_agent_end)
      expect(hooks_config[:on_agent_start]).to be_a(Proc)
      expect(hooks_config[:on_agent_end]).to be_a(Proc)
    end

    it "builds hooks configuration with agent-specific hooks only" do
      agent_class.on_start :log_start
      agent_class.on_end :log_end

      hooks_config = agent_instance.send(:build_hooks_config)

      expect(hooks_config).to have_key(:on_agent_start)
      expect(hooks_config).to have_key(:on_agent_end)
      expect(hooks_config[:on_agent_start]).to be_a(Proc)
      expect(hooks_config[:on_agent_end]).to be_a(Proc)
    end

    it "builds hooks configuration with both global and agent-specific hooks" do
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| "global start" }
      agent_class.on_start :log_start

      hooks_config = agent_instance.send(:build_hooks_config)

      expect(hooks_config).to have_key(:on_agent_start)
      expect(hooks_config[:on_agent_start]).to be_a(Proc)
    end

    it "builds configuration for all hook types" do
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| "global" }
      AiAgentDsl::Hooks::RunHooks.on_agent_end { |_agent, _result| "global" }
      AiAgentDsl::Hooks::RunHooks.on_handoff { |_from, _to| "global" }
      AiAgentDsl::Hooks::RunHooks.on_tool_start { |_agent, _tool, _params| "global" }
      AiAgentDsl::Hooks::RunHooks.on_tool_end { |_agent, _tool, _params, _result| "global" }
      AiAgentDsl::Hooks::RunHooks.on_error { |_agent, _error| "global" }

      hooks_config = agent_instance.send(:build_hooks_config)

      expect(hooks_config).to have_key(:on_agent_start)
      expect(hooks_config).to have_key(:on_agent_end)
      expect(hooks_config).to have_key(:on_handoff)
      expect(hooks_config).to have_key(:on_tool_start)
      expect(hooks_config).to have_key(:on_tool_end)
      expect(hooks_config).to have_key(:on_error)
    end
  end

  describe "combined hooks execution" do
    it "executes global hooks before agent-specific hooks" do
      execution_order = []

      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| execution_order << "global" }
      agent_class.on_start { |_agent| execution_order << "agent" }

      hooks_config = agent_instance.send(:build_hooks_config)
      hooks_config[:on_agent_start].call(test_agent)

      expect(execution_order).to eq(["global", "agent"])
    end

    it "executes multiple global hooks in order, then agent hooks in order" do
      execution_order = []

      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| execution_order << "global1" }
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| execution_order << "global2" }

      agent_class.on_start { |_agent| execution_order << "agent1" }
      agent_class.on_start { |_agent| execution_order << "agent2" }

      hooks_config = agent_instance.send(:build_hooks_config)
      hooks_config[:on_agent_start].call(test_agent)

      expect(execution_order).to eq(["global1", "global2", "agent1", "agent2"])
    end

    it "handles errors in global hooks gracefully" do
      execution_order = []

      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| raise "Global error" }
      agent_class.on_start { |_agent| execution_order << "agent" }

      # Mock error handling
      allow(AiAgentDsl::Hooks::RunHooks).to receive(:warn)

      hooks_config = agent_instance.send(:build_hooks_config)
      hooks_config[:on_agent_start].call(test_agent)

      expect(execution_order).to eq(["agent"])
    end

    it "handles errors in agent hooks gracefully" do
      execution_order = []

      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| execution_order << "global" }
      agent_class.on_start { |_agent| raise "Agent error" }

      # Mock error handling
      allow(agent_instance).to receive(:warn)

      hooks_config = agent_instance.send(:build_hooks_config)
      hooks_config[:on_agent_start].call(test_agent)

      expect(execution_order).to eq(["global"])
    end
  end

  describe "hooks integration with OpenAI Agent creation" do
    it "includes hooks in agent parameters" do
      agent_class.on_start :log_start

      allow(OpenAIAgents::Agent).to receive(:new) do |**params|
        expect(params).to include(:hooks)
        expect(params[:hooks]).to be_a(Hash)
        test_agent
      end

      agent_instance.create_agent
    end

    it "creates valid hook configuration structure" do
      agent_class.on_start :log_start
      agent_class.on_end :log_end

      allow(OpenAIAgents::Agent).to receive(:new) do |**params|
        hooks = params[:hooks]
        expect(hooks).to be_a(Hash)
        expect(hooks[:on_agent_start]).to be_a(Proc)
        expect(hooks[:on_agent_end]).to be_a(Proc)
        test_agent
      end

      agent_instance.create_agent
    end
  end

  describe "hook wrapper creation" do
    it "creates global hook wrapper that calls RunHooks" do
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| "executed" }

      wrapper = agent_instance.send(:create_hook_wrapper, :on_agent_start, :global)

      expect(AiAgentDsl::Hooks::RunHooks).to receive(:execute_hooks).with(:on_agent_start, test_agent)
      wrapper.call(test_agent)
    end

    it "creates agent hook wrapper that calls execute_agent_hooks" do
      agent_class.on_start :log_start

      wrapper = agent_instance.send(:create_hook_wrapper, :on_start, :agent)

      expect(agent_instance).to receive(:execute_agent_hooks).with(:on_start, test_agent)
      wrapper.call(test_agent)
    end

    it "handles hook wrapper creation for agents without AgentHooks" do
      # Create an agent without AgentHooks
      basic_agent_class = Class.new(AiAgentDsl::Agents::Base) do
        include AiAgentDsl::AgentDsl
        agent_name "basic_agent"
        model "gpt-4"
      end

      basic_agent_instance = basic_agent_class.new
      wrapper = basic_agent_instance.send(:create_hook_wrapper, :on_start, :agent)

      expect { wrapper.call(test_agent) }.not_to raise_error
    end

    it "raises error for invalid hook scope" do
      expect do
        agent_instance.send(:create_hook_wrapper, :on_start, :invalid_scope)
      end.to raise_error(ArgumentError, /Invalid hook scope: invalid_scope/)
    end
  end

  describe "hook combination" do
    it "combines global and agent hooks into single proc" do
      execution_order = []

      global_hook = proc { |_agent| execution_order << "global" }
      agent_hook = proc { |_agent| execution_order << "agent" }

      combined = agent_instance.send(:combine_hooks, global_hook, agent_hook)
      combined.call(test_agent)

      expect(execution_order).to eq(["global", "agent"])
    end

    it "returns global hook when agent hook is nil" do
      global_hook = proc { |_agent| "global" }

      combined = agent_instance.send(:combine_hooks, global_hook, nil)

      expect(combined).to eq(global_hook)
    end

    it "returns agent hook when global hook is nil" do
      agent_hook = proc { |_agent| "agent" }

      combined = agent_instance.send(:combine_hooks, nil, agent_hook)

      expect(combined).to eq(agent_hook)
    end

    it "returns nil when both hooks are nil" do
      combined = agent_instance.send(:combine_hooks, nil, nil)

      expect(combined).to be_nil
    end
  end

  describe "real-world usage scenarios" do
    it "supports complex hook combinations" do
      execution_log = []

      # Set up global hooks
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start_1" }
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start_2" }
      AiAgentDsl::Hooks::RunHooks.on_tool_start { |_agent, _tool, _params| execution_log << "global_tool_start" }

      # Set up agent-specific hooks
      agent_class.on_start { |_agent| execution_log << "agent_start_1" }
      agent_class.on_start { |_agent| execution_log << "agent_start_2" }
      agent_class.on_tool_start { |_agent, _tool, _params| execution_log << "agent_tool_start" }

      hooks_config = agent_instance.send(:build_hooks_config)

      # Execute hooks
      hooks_config[:on_agent_start].call(test_agent)
      hooks_config[:on_tool_start].call(test_agent, "search", { query: "test" })

      expect(execution_log).to eq([
        "global_start_1", "global_start_2", "agent_start_1", "agent_start_2",
        "global_tool_start", "agent_tool_start"
      ])
    end

    it "supports method-based and block-based hooks mixed together" do
      execution_log = []

      # Global hooks
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_block" }

      # Agent hooks
      agent_class.on_start :log_start
      agent_class.on_start { |_agent| execution_log << "agent_block" }

      hooks_config = agent_instance.send(:build_hooks_config)
      hooks_config[:on_agent_start].call(test_agent)

      expect(execution_log).to eq(["global_block", "agent_block"])
      expect(agent_instance.execution_order).to eq(["log_start"])
    end
  end

  describe "agent.run() execution integration" do
    let(:mock_runner) { instance_double(OpenAIAgents::Runner) }
    let(:mock_openai_agent) { instance_double(OpenAIAgents::Agent) }
    let(:mock_result) { { success: true, data: "test result" } }

    before do
      # Mock the OpenAI agent creation

      # Mock the create_runner method to return our mock runner
      allow(agent_instance).to receive_messages(build_user_prompt_with_context: "test prompt", create_runner: mock_runner)

      # Mock transform_run_result to pass through the result
      allow(agent_instance).to receive(:transform_run_result) { |result| result }
    end

    it "verifies hooks are called during agent.run() execution" do
      execution_log = []

      # Set up hooks that should be called during run
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start" }
      AiAgentDsl::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end" }

      agent_class.on_start { |_agent| execution_log << "agent_start" }
      agent_class.on_end { |_agent, _result| execution_log << "agent_end" }

      # Mock the runner to simulate hook execution
      allow(mock_runner).to receive(:run) do |_prompt|
        # Simulate the OpenAI framework calling hooks through @captured_hooks
        hooks = @captured_hooks || {}

        # Call on_agent_start hook if it exists
        hooks[:on_agent_start]&.call(mock_openai_agent)

        # Simulate some execution...

        # Call on_agent_end hook if it exists
        hooks[:on_agent_end]&.call(mock_openai_agent, mock_result)

        mock_result
      end

      # Mock the create_agent_with_context to capture hooks
      allow(agent_instance).to receive(:create_agent_with_context) do |_context|
        hooks_config = agent_instance.send(:build_hooks_config)
        @captured_hooks = hooks_config
        mock_openai_agent
      end

      # Execute the run method
      result = agent_instance.run

      # Verify hooks were called in correct order
      expect(execution_log).to eq(["global_start", "agent_start", "global_end", "agent_end"])
      expect(result).to eq(mock_result)
    end

    it "verifies tool hooks are called during agent execution" do
      execution_log = []

      # Set up tool hooks
      AiAgentDsl::Hooks::RunHooks.on_tool_start { |_agent, _tool, _params| execution_log << "global_tool_start" }
      AiAgentDsl::Hooks::RunHooks.on_tool_end { |_agent, _tool, _params, _result| execution_log << "global_tool_end" }

      agent_class.on_tool_start { |_agent, _tool, _params| execution_log << "agent_tool_start" }
      agent_class.on_tool_end { |_agent, _tool, _params, _result| execution_log << "agent_tool_end" }

      # Mock the runner to simulate tool hook execution
      allow(mock_runner).to receive(:run) do |_prompt|
        hooks = @captured_hooks || {}

        # Simulate tool execution
        tool_name = "search"
        tool_params = { query: "test" }
        tool_result = { results: [] }

        # Call tool start hooks
        hooks[:on_tool_start]&.call(mock_openai_agent, tool_name, tool_params)

        # Call tool end hooks
        hooks[:on_tool_end]&.call(mock_openai_agent, tool_name, tool_params, tool_result)

        mock_result
      end

      # Mock the create_agent_with_context to capture hooks
      allow(agent_instance).to receive(:create_agent_with_context) do |_context|
        hooks_config = agent_instance.send(:build_hooks_config)
        @captured_hooks = hooks_config
        mock_openai_agent
      end

      # Execute the run method
      result = agent_instance.run

      # Verify tool hooks were called in correct order
      expect(execution_log).to eq(["global_tool_start", "agent_tool_start", "global_tool_end", "agent_tool_end"])
      expect(result).to eq(mock_result)
    end

    it "verifies error hooks are called during agent execution failures" do
      execution_log = []
      test_error = StandardError.new("Test execution error")
      error_result = { success: false, error: test_error }

      # Set up error hooks
      AiAgentDsl::Hooks::RunHooks.on_error { |_agent, _error| execution_log << "global_error" }
      agent_class.on_error { |_agent, _error| execution_log << "agent_error" }

      # Mock the runner to simulate error
      allow(mock_runner).to receive(:run) do |_prompt|
        hooks = @captured_hooks || {}

        # Simulate error and call error hooks
        hooks[:on_error]&.call(mock_openai_agent, test_error)

        # Return error result
        error_result
      end

      # Mock transform_run_result to handle error result
      allow(agent_instance).to receive(:transform_run_result) { |result| result }

      # Mock the create_agent_with_context to capture hooks
      allow(agent_instance).to receive(:create_agent_with_context) do |_context|
        hooks_config = agent_instance.send(:build_hooks_config)
        @captured_hooks = hooks_config
        mock_openai_agent
      end

      # Execute the run method
      result = agent_instance.run

      # Verify error hooks were called in correct order
      expect(execution_log).to eq(["global_error", "agent_error"])
      expect(result[:success]).to be false
      expect(result[:error]).to eq(test_error)
    end

    it "verifies handoff hooks are called during agent handoffs" do
      execution_log = []
      handoff_agent = "target_agent"

      # Set up handoff hooks
      AiAgentDsl::Hooks::RunHooks.on_handoff { |_from, _to| execution_log << "global_handoff" }
      agent_class.on_handoff { |_from, _to| execution_log << "agent_handoff" }

      # Mock the runner to simulate handoff
      allow(mock_runner).to receive(:run) do |_prompt|
        hooks = @captured_hooks || {}

        # Simulate handoff and call handoff hooks
        hooks[:on_handoff]&.call(mock_openai_agent, handoff_agent)

        mock_result
      end

      # Mock the create_agent_with_context to capture hooks
      allow(agent_instance).to receive(:create_agent_with_context) do |_context|
        hooks_config = agent_instance.send(:build_hooks_config)
        @captured_hooks = hooks_config
        mock_openai_agent
      end

      # Execute the run method
      result = agent_instance.run

      # Verify handoff hooks were called in correct order
      expect(execution_log).to eq(["global_handoff", "agent_handoff"])
      expect(result).to eq(mock_result)
    end
  end

  describe "end-to-end OpenAI Agents framework integration" do
    let(:real_openai_agent) { instance_double(OpenAIAgents::Agent) }
    let(:execution_log) { [] }
    let(:mock_runner) { instance_double(OpenAIAgents::Runner) }
    let(:mock_result) { { success: true, data: "test result" } }

    before do
      # Mock agent creation methods
      allow(agent_instance).to receive_messages(build_user_prompt_with_context: "test prompt", create_runner: mock_runner)
      allow(agent_instance).to receive(:transform_run_result) { |result| result }

      # Mock runner
      allow(mock_runner).to receive(:run).and_return(mock_result)
    end

    it "verifies framework receives properly formatted hooks configuration" do
      # Set up hooks
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start" }
      AiAgentDsl::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end" }
      AiAgentDsl::Hooks::RunHooks.on_tool_start { |_agent, _tool, _params| execution_log << "global_tool_start" }
      AiAgentDsl::Hooks::RunHooks.on_tool_end { |_agent, _tool, _params, _result| execution_log << "global_tool_end" }
      AiAgentDsl::Hooks::RunHooks.on_handoff { |_from, _to| execution_log << "global_handoff" }
      AiAgentDsl::Hooks::RunHooks.on_error { |_agent, _error| execution_log << "global_error" }

      agent_class.on_start { |_agent| execution_log << "agent_start" }
      agent_class.on_end { |_agent, _result| execution_log << "agent_end" }
      agent_class.on_tool_start { |_agent, _tool, _params| execution_log << "agent_tool_start" }
      agent_class.on_tool_end { |_agent, _tool, _params, _result| execution_log << "agent_tool_end" }
      agent_class.on_handoff { |_from, _to| execution_log << "agent_handoff" }
      agent_class.on_error { |_agent, _error| execution_log << "agent_error" }

      # Mock the create_agent_with_context to capture hooks
      allow(agent_instance).to receive(:create_agent_with_context) do |_context|
        hooks_config = agent_instance.send(:build_hooks_config)
        @captured_hooks = hooks_config
        real_openai_agent
      end

      # Run the agent
      agent_instance.run

      # Verify OpenAI Agent received hooks configuration
      expect(@captured_hooks).to be_a(Hash)
      expect(@captured_hooks).to have_key(:on_agent_start)
      expect(@captured_hooks).to have_key(:on_agent_end)
      expect(@captured_hooks).to have_key(:on_tool_start)
      expect(@captured_hooks).to have_key(:on_tool_end)
      expect(@captured_hooks).to have_key(:on_handoff)
      expect(@captured_hooks).to have_key(:on_error)

      # Verify all hooks are callable procs
      @captured_hooks.each_value do |hook_proc|
        expect(hook_proc).to be_a(Proc)
      end
    end

    it "verifies framework hooks execute in correct lifecycle order" do
      # Set up hooks
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start" }
      AiAgentDsl::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end" }

      agent_class.on_start { |_agent| execution_log << "agent_start" }
      agent_class.on_end { |_agent, _result| execution_log << "agent_end" }

      # Mock runner to simulate OpenAI framework lifecycle
      allow(mock_runner).to receive(:run) do |_prompt|
        # Simulate OpenAI framework calling lifecycle hooks
        # This simulates the actual OpenAI Agents framework behavior

        # 1. Agent start lifecycle
        @captured_hooks[:on_agent_start]&.call(real_openai_agent)

        # 2. Simulate some processing...

        # 3. Agent end lifecycle
        @captured_hooks[:on_agent_end]&.call(real_openai_agent, mock_result)

        mock_result
      end

      # Mock the create_agent_with_context to capture hooks
      allow(agent_instance).to receive(:create_agent_with_context) do |_context|
        hooks_config = agent_instance.send(:build_hooks_config)
        @captured_hooks = hooks_config
        real_openai_agent
      end

      # Run the agent
      result = agent_instance.run

      # Verify lifecycle hooks were called in correct order
      expect(execution_log).to eq(["global_start", "agent_start", "global_end", "agent_end"])
      expect(result).to eq(mock_result)
    end

    it "verifies framework hooks handle complex execution scenarios" do
      # Set up comprehensive hooks
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start" }
      AiAgentDsl::Hooks::RunHooks.on_tool_start { |_agent, _tool, _params| execution_log << "global_tool_start" }
      AiAgentDsl::Hooks::RunHooks.on_tool_end { |_agent, _tool, _params, _result| execution_log << "global_tool_end" }
      AiAgentDsl::Hooks::RunHooks.on_handoff { |_from, _to| execution_log << "global_handoff" }
      AiAgentDsl::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end" }

      agent_class.on_start { |_agent| execution_log << "agent_start" }
      agent_class.on_tool_start { |_agent, _tool, _params| execution_log << "agent_tool_start" }
      agent_class.on_tool_end { |_agent, _tool, _params, _result| execution_log << "agent_tool_end" }
      agent_class.on_handoff { |_from, _to| execution_log << "agent_handoff" }
      agent_class.on_end { |_agent, _result| execution_log << "agent_end" }

      # Mock runner to simulate complex OpenAI framework execution
      allow(mock_runner).to receive(:run) do |_prompt|
        # Simulate OpenAI framework execution with multiple lifecycle events

        # 1. Agent start
        @captured_hooks[:on_agent_start]&.call(real_openai_agent)

        # 2. Tool execution
        @captured_hooks[:on_tool_start]&.call(real_openai_agent, "search", { query: "test" })
        @captured_hooks[:on_tool_end]&.call(real_openai_agent, "search", { query: "test" }, { results: [] })

        # 3. Agent handoff
        @captured_hooks[:on_handoff]&.call(real_openai_agent, "target_agent")

        # 4. Agent end
        @captured_hooks[:on_agent_end]&.call(real_openai_agent, mock_result)

        mock_result
      end

      # Mock the create_agent_with_context to capture hooks
      allow(agent_instance).to receive(:create_agent_with_context) do |_context|
        hooks_config = agent_instance.send(:build_hooks_config)
        @captured_hooks = hooks_config
        real_openai_agent
      end

      # Run the agent
      result = agent_instance.run

      # Verify complex execution lifecycle
      expect(execution_log).to eq([
        "global_start", "agent_start",
        "global_tool_start", "agent_tool_start",
        "global_tool_end", "agent_tool_end",
        "global_handoff", "agent_handoff",
        "global_end", "agent_end"
      ])
      expect(result).to eq(mock_result)
    end

    it "verifies framework hooks are resilient to errors" do
      # Set up hooks with potential failures
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| raise "Global hook error" }
      AiAgentDsl::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end_success" }

      agent_class.on_start { |_agent| execution_log << "agent_start_success" }
      agent_class.on_end { |_agent, _result| execution_log << "agent_end_success" }

      # Mock error handling
      allow(AiAgentDsl::Hooks::RunHooks).to receive(:warn)
      allow(agent_instance).to receive(:warn)

      # Mock runner to simulate framework lifecycle
      allow(mock_runner).to receive(:run) do |_prompt|
        # Simulate OpenAI framework calling hooks (with error handling)
        begin
          @captured_hooks[:on_agent_start]&.call(real_openai_agent)
        rescue StandardError
          # Framework should handle hook errors gracefully
        end

        @captured_hooks[:on_agent_end]&.call(real_openai_agent, mock_result)

        mock_result
      end

      # Mock the create_agent_with_context to capture hooks
      allow(agent_instance).to receive(:create_agent_with_context) do |_context|
        hooks_config = agent_instance.send(:build_hooks_config)
        @captured_hooks = hooks_config
        real_openai_agent
      end

      # Run the agent
      result = agent_instance.run

      # Verify resilient execution (failing global hook doesn't stop agent hooks)
      expect(execution_log).to eq(["agent_start_success", "global_end_success", "agent_end_success"])
      expect(result).to eq(mock_result)
    end
  end
end

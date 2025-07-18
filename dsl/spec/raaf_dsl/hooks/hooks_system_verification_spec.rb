# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Hooks System Verification" do
  let(:execution_log) { [] }

  # Test agent that uses hooks
  let(:test_agent_class) do
    execution_log_ref = execution_log

    Class.new(RAAF::DSL::Agents::Base) do
      include RAAF::DSL::AgentDsl
      include RAAF::DSL::Hooks::AgentHooks

      agent_name "test_agent"
      model "gpt-4o-mini"
      max_turns 1

      def self.name
        "TestAgent"
      end

      # Agent-specific hooks
      on_start { |_agent| execution_log_ref << "agent_start" }
      on_end { |_agent, _result| execution_log_ref << "agent_end" }
      on_tool_start { |_agent, tool, _params| execution_log_ref << "agent_tool_start:#{tool}" }
      on_tool_end { |_agent, tool, _params, _result| execution_log_ref << "agent_tool_end:#{tool}" }
      on_error { |_agent, error| execution_log_ref << "agent_error:#{error.class}" }
      on_handoff { |from, to| execution_log_ref << "agent_handoff:#{from}-#{to}" }

      private

      def agent_name
        "test_agent"
      end

      def build_instructions
        "You are a test assistant."
      end
    end
  end

  let(:agent_instance) { test_agent_class.new }

  before do
    # Clear execution log
    execution_log.clear

    # Clear global hooks
    RAAF::DSL::Hooks::RunHooks.clear_hooks!

    # Mock OpenAI Agent and Runner if not already defined
    unless defined?(OpenAIAgents)
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
        end)
      end
      stub_const("OpenAIAgents", openai_agents)
    end
  end

  after do
    # Clear global hooks after each test
    RAAF::DSL::Hooks::RunHooks.clear_hooks!
  end

  describe "hooks configuration and building" do
    it "successfully builds hooks configuration with both global and agent hooks" do
      # Set up global hooks
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start" }
      RAAF::DSL::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end" }
      RAAF::DSL::Hooks::RunHooks.on_tool_start { |_agent, tool, _params| execution_log << "global_tool_start:#{tool}" }
      RAAF::DSL::Hooks::RunHooks.on_tool_end { |_agent, tool, _params, _result| execution_log << "global_tool_end:#{tool}" }
      RAAF::DSL::Hooks::RunHooks.on_error { |_agent, error| execution_log << "global_error:#{error.class}" }
      RAAF::DSL::Hooks::RunHooks.on_handoff { |from, to| execution_log << "global_handoff:#{from}-#{to}" }

      # Build hooks configuration
      hooks_config = agent_instance.send(:build_hooks_config)

      # Verify hooks configuration structure
      expect(hooks_config).to be_a(Hash)
      expect(hooks_config).to have_key(:on_agent_start)
      expect(hooks_config).to have_key(:on_agent_end)
      expect(hooks_config).to have_key(:on_tool_start)
      expect(hooks_config).to have_key(:on_tool_end)
      expect(hooks_config).to have_key(:on_error)
      expect(hooks_config).to have_key(:on_handoff)

      # Verify all hooks are callable procs
      hooks_config.each_value do |hook_proc|
        expect(hook_proc).to be_a(Proc)
      end
    end

    it "executes hooks in correct order when called" do
      # Set up global hooks
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start" }
      RAAF::DSL::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end" }

      # Build hooks configuration
      hooks_config = agent_instance.send(:build_hooks_config)

      # Mock agent for hook execution
      mock_agent = double("MockAgent")
      mock_result = { success: true }

      # Execute hooks manually
      hooks_config[:on_agent_start].call(mock_agent)
      hooks_config[:on_agent_end].call(mock_agent, mock_result)

      # Verify execution order
      expect(execution_log).to eq(%w[global_start agent_start global_end agent_end])
    end

    it "executes tool hooks with parameters" do
      # Set up tool hooks
      RAAF::DSL::Hooks::RunHooks.on_tool_start { |_agent, tool, params| execution_log << "global_tool_start:#{tool}:#{params[:query]}" }
      RAAF::DSL::Hooks::RunHooks.on_tool_end { |_agent, tool, _params, result| execution_log << "global_tool_end:#{tool}:#{result[:status]}" }

      # Build hooks configuration
      hooks_config = agent_instance.send(:build_hooks_config)

      # Mock parameters
      mock_agent = double("MockAgent")
      tool_name = "search"
      tool_params = { query: "test" }
      tool_result = { status: "success", data: [] }

      # Execute tool hooks
      hooks_config[:on_tool_start].call(mock_agent, tool_name, tool_params)
      hooks_config[:on_tool_end].call(mock_agent, tool_name, tool_params, tool_result)

      # Verify tool hooks executed with parameters
      expect(execution_log).to eq([
                                    "global_tool_start:search:test",
                                    "agent_tool_start:search",
                                    "global_tool_end:search:success",
                                    "agent_tool_end:search"
                                  ])
    end

    it "executes error hooks with error information" do
      # Set up error hooks
      RAAF::DSL::Hooks::RunHooks.on_error { |_agent, error| execution_log << "global_error:#{error.class}:#{error.message}" }

      # Build hooks configuration
      hooks_config = agent_instance.send(:build_hooks_config)

      # Mock error
      mock_agent = double("MockAgent")
      test_error = StandardError.new("Test error")

      # Execute error hooks
      hooks_config[:on_error].call(mock_agent, test_error)

      # Verify error hooks executed with error information
      expect(execution_log).to eq([
                                    "global_error:StandardError:Test error",
                                    "agent_error:StandardError"
                                  ])
    end

    it "executes handoff hooks with agent information" do
      # Set up handoff hooks
      RAAF::DSL::Hooks::RunHooks.on_handoff { |from, to| execution_log << "global_handoff:#{from.name}-#{to}" }

      # Build hooks configuration
      hooks_config = agent_instance.send(:build_hooks_config)

      # Mock agents
      from_agent = double("FromAgent", name: "agent1")
      to_agent = "agent2"

      # Execute handoff hooks
      hooks_config[:on_handoff].call(from_agent, to_agent)

      # Verify handoff hooks executed with agent information
      expect(execution_log).to eq([
                                    "global_handoff:agent1-agent2",
                                    "agent_handoff:#{from_agent}-agent2"
                                  ])
    end

    it "handles hook execution errors gracefully" do
      # Set up hooks with one that fails
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| raise "Global hook error" }
      RAAF::DSL::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end_success" }

      # Build hooks configuration
      hooks_config = agent_instance.send(:build_hooks_config)

      # Mock agent
      mock_agent = double("MockAgent")
      mock_result = { success: true }

      # Execute hooks - start hook should fail but not stop execution
      expect { hooks_config[:on_agent_start].call(mock_agent) }.not_to raise_error
      hooks_config[:on_agent_end].call(mock_agent, mock_result)

      # Verify that subsequent hooks still executed despite the error
      expect(execution_log).to include("agent_start")
      expect(execution_log).to include("global_end_success")
      expect(execution_log).to include("agent_end")
    end

    it "supports multiple hooks of same type in correct order" do
      # Set up multiple hooks of same type
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start_1" }
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start_2" }
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start_3" }

      # Build hooks configuration
      hooks_config = agent_instance.send(:build_hooks_config)

      # Mock agent
      mock_agent = double("MockAgent")

      # Execute hooks
      hooks_config[:on_agent_start].call(mock_agent)

      # Verify execution order
      expect(execution_log).to eq(%w[
                                    global_start_1
                                    global_start_2
                                    global_start_3
                                    agent_start
                                  ])
    end
  end

  describe "hooks integration with agent creation" do
    it "creates agent with hooks configuration when OpenAI agents are mocked" do
      # Set up hooks
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start" }

      # Mock OpenAI Agent creation
      mock_agent = double("MockOpenAIAgent")
      captured_params = nil

      # Mock OpenAI Agent class
      allow(RAAF::Agent).to receive(:new) do |**params|
        captured_params = params
        mock_agent
      end

      # Create agent
      openai_agent = agent_instance.create_agent

      # Verify agent was created with hooks
      expect(openai_agent).to eq(mock_agent)
      expect(captured_params).to have_key(:hooks)
      expect(captured_params[:hooks]).to be_a(Hash)
      expect(captured_params[:hooks]).to have_key(:on_agent_start)
      expect(captured_params[:hooks][:on_agent_start]).to be_a(Proc)
    end

    it "verifies agent creation includes all configured hooks" do
      # Set up comprehensive hooks
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start" }
      RAAF::DSL::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end" }
      RAAF::DSL::Hooks::RunHooks.on_tool_start { |_agent, _tool, _params| execution_log << "global_tool_start" }
      RAAF::DSL::Hooks::RunHooks.on_tool_end { |_agent, _tool, _params, _result| execution_log << "global_tool_end" }
      RAAF::DSL::Hooks::RunHooks.on_error { |_agent, _error| execution_log << "global_error" }
      RAAF::DSL::Hooks::RunHooks.on_handoff { |_from, _to| execution_log << "global_handoff" }

      # Mock OpenAI Agent creation
      mock_agent = double("MockOpenAIAgent")
      captured_params = nil

      # Mock OpenAI Agent class
      allow(RAAF::Agent).to receive(:new) do |**params|
        captured_params = params
        mock_agent
      end

      # Create agent
      agent_instance.create_agent

      # Verify all hooks are present
      expect(captured_params[:hooks]).to have_key(:on_agent_start)
      expect(captured_params[:hooks]).to have_key(:on_agent_end)
      expect(captured_params[:hooks]).to have_key(:on_tool_start)
      expect(captured_params[:hooks]).to have_key(:on_tool_end)
      expect(captured_params[:hooks]).to have_key(:on_error)
      expect(captured_params[:hooks]).to have_key(:on_handoff)

      # Verify all hooks are callable
      captured_params[:hooks].each_value do |hook_proc|
        expect(hook_proc).to be_a(Proc)
      end
    end
  end

  describe "hooks system completeness" do
    it "provides complete coverage of all hook types" do
      # This test verifies that our hooks system covers all the lifecycle events
      # that are important for AI agent monitoring and control

      expected_hook_types = %i[
        on_agent_start
        on_agent_end
        on_tool_start
        on_tool_end
        on_error
        on_handoff
      ]

      # Set up hooks for all types
      expected_hook_types.each do |hook_type|
        RAAF::DSL::Hooks::RunHooks.public_send(hook_type) { |*_args| execution_log << "global_#{hook_type}" }
      end

      # Build hooks configuration
      hooks_config = agent_instance.send(:build_hooks_config)

      # Verify all expected hook types are present
      expected_hook_types.each do |hook_type|
        expect(hooks_config).to have_key(hook_type)
        expect(hooks_config[hook_type]).to be_a(Proc)
      end
    end
  end
end

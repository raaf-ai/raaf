# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Simple Real Hooks Test" do
  let(:execution_log) { [] }

  # Simple test agent that demonstrates hooks working
  let(:test_agent_class) do
    execution_log_ref = execution_log

    Class.new(AiAgentDsl::Agents::Base) do
      include AiAgentDsl::AgentDsl
      include AiAgentDsl::Hooks::AgentHooks

      agent_name "simple_test_agent"
      model "gpt-4o-mini"
      max_turns 1

      def self.name
        "SimpleTestAgent"
      end

      # Agent-specific hooks
      on_start { |agent| execution_log_ref << "agent_start:#{agent.class.name}" }
      on_end { |_agent, result| execution_log_ref << "agent_end:#{result.class.name}" }
      on_error { |_agent, error| execution_log_ref << "agent_error:#{error.class.name}" }

      private

      def agent_name
        "simple_test_agent"
      end

      def build_instructions
        "You are a test assistant."
      end

      def build_user_prompt
        "Test user prompt"
      end
    end
  end

  let(:agent_instance) { test_agent_class.new }

  before do
    # Clear execution log
    execution_log.clear

    # Clear global hooks
    AiAgentDsl::Hooks::RunHooks.clear_hooks!

    # Mock OpenAI Agent components for testing
    openai_agents = Module.new do
      const_set(:Agent, Class.new do
        attr_reader :hooks

        def initialize(**params)
          @hooks = params[:hooks] || {}
        end

        def name
          "TestAgent"
        end
      end)

      const_set(:Runner, Class.new do
        def initialize(**params)
          @agent = params[:agent]
        end

        def run(_prompt)
          # Simulate calling agent start hook
          @agent.hooks[:on_agent_start]&.call(@agent)

          # Simulate processing
          result = { success: true, messages: [{ content: "Test response" }] }

          # Simulate calling agent end hook
          @agent.hooks[:on_agent_end]&.call(@agent, result)

          result
        end
      end)
    end

    stub_const("OpenAIAgents", openai_agents)
  end

  after do
    # Clear global hooks after each test
    AiAgentDsl::Hooks::RunHooks.clear_hooks!
  end

  describe "real agent execution with hooks" do
    it "demonstrates hooks working with simulated agent run" do
      # Set up global hooks
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |agent| execution_log << "global_start:#{agent.name}" }
      AiAgentDsl::Hooks::RunHooks.on_agent_end { |_agent, result| execution_log << "global_end:#{result[:success]}" }

      # Mock the agent run flow
      context = AiAgentDsl::ContextVariables.new({ user_input: "Hello" })

      # This simulates what would happen in a real run
      openai_agent = agent_instance.create_agent
      user_prompt = agent_instance.send(:build_user_prompt_with_context, context)

      runner = OpenAIAgents::Runner.new(agent: openai_agent)
      result = runner.run(user_prompt)

      # Verify hooks were called
      expect(execution_log).to include("global_start:TestAgent")
      expect(execution_log).to include("agent_start:OpenAIAgents::Agent")
      expect(execution_log).to include("global_end:true")
      expect(execution_log).to include("agent_end:Hash")

      # Verify execution order
      expect(execution_log).to eq([
        "global_start:TestAgent",
        "agent_start:OpenAIAgents::Agent",
        "global_end:true",
        "agent_end:Hash"
      ])

      # Verify result
      expect(result[:success]).to be true
      expect(result[:messages]).to be_an(Array)
    end

    it "demonstrates hooks working with error scenarios" do
      # Set up error hooks
      AiAgentDsl::Hooks::RunHooks.on_error { |_agent, error| execution_log << "global_error:#{error.message}" }

      # Mock the agent creation and hook configuration
      openai_agent = agent_instance.create_agent

      # Simulate error by calling error hook directly
      test_error = StandardError.new("Test error")
      openai_agent.hooks[:on_error]&.call(openai_agent, test_error)

      # Verify error hooks were called
      expect(execution_log).to include("global_error:Test error")
      expect(execution_log).to include("agent_error:StandardError")
    end

    it "demonstrates hooks configuration is properly built" do
      # Set up comprehensive hooks
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start" }
      AiAgentDsl::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end" }
      AiAgentDsl::Hooks::RunHooks.on_tool_start { |_agent, _tool, _params| execution_log << "global_tool_start" }
      AiAgentDsl::Hooks::RunHooks.on_tool_end { |_agent, _tool, _params, _result| execution_log << "global_tool_end" }
      AiAgentDsl::Hooks::RunHooks.on_error { |_agent, _error| execution_log << "global_error" }
      AiAgentDsl::Hooks::RunHooks.on_handoff { |_from, _to| execution_log << "global_handoff" }

      # Create agent and verify hooks configuration
      openai_agent = agent_instance.create_agent

      # Verify hooks are properly configured
      expect(openai_agent.hooks).to be_a(Hash)
      expect(openai_agent.hooks).to have_key(:on_agent_start)
      expect(openai_agent.hooks).to have_key(:on_agent_end)
      expect(openai_agent.hooks).to have_key(:on_tool_start)
      expect(openai_agent.hooks).to have_key(:on_tool_end)
      expect(openai_agent.hooks).to have_key(:on_error)
      expect(openai_agent.hooks).to have_key(:on_handoff)

      # Verify hooks are callable
      openai_agent.hooks.each_value do |hook_proc|
        expect(hook_proc).to be_a(Proc)
      end
    end

    it "demonstrates hooks working with multiple agents" do
      # Create a second agent class
      execution_log_ref = execution_log
      second_agent_class = Class.new(AiAgentDsl::Agents::Base) do
        include AiAgentDsl::AgentDsl
        include AiAgentDsl::Hooks::AgentHooks

        agent_name "second_agent"
        model "gpt-4o-mini"

        def self.name
          "SecondAgent"
        end

        on_start { |_agent| execution_log_ref << "second_agent_start" }
        on_end { |_agent, _result| execution_log_ref << "second_agent_end" }

        private

        def agent_name
          "second_agent"
        end

        def build_instructions
          "You are a second test assistant."
        end

        def build_user_prompt
          "Test user prompt for second agent"
        end
      end

      # Set up global hooks
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |agent| execution_log << "global_start:#{agent.name}" }
      AiAgentDsl::Hooks::RunHooks.on_agent_end { |agent, _result| execution_log << "global_end:#{agent.name}" }

      # Create and run first agent
      first_agent = agent_instance.create_agent
      first_runner = OpenAIAgents::Runner.new(agent: first_agent)
      first_result = first_runner.run("Hello")

      # Create and run second agent
      second_agent_instance = second_agent_class.new
      second_agent = second_agent_instance.create_agent
      second_runner = OpenAIAgents::Runner.new(agent: second_agent)
      second_result = second_runner.run("Hello")

      # Verify hooks were called for both agents
      expect(execution_log).to include("global_start:TestAgent")
      expect(execution_log).to include("agent_start:OpenAIAgents::Agent")
      expect(execution_log).to include("global_end:TestAgent")
      expect(execution_log).to include("agent_end:Hash")

      expect(execution_log).to include("global_start:TestAgent")
      expect(execution_log).to include("second_agent_start")
      expect(execution_log).to include("global_end:TestAgent")
      expect(execution_log).to include("second_agent_end")

      # Verify both agents executed successfully
      expect(first_result[:success]).to be true
      expect(second_result[:success]).to be true
    end

    it "demonstrates hooks are resilient to errors" do
      # Set up hooks where one fails
      AiAgentDsl::Hooks::RunHooks.on_agent_start { |_agent| raise "Global hook error" }
      AiAgentDsl::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end_success" }

      # Create agent and run
      openai_agent = agent_instance.create_agent
      runner = OpenAIAgents::Runner.new(agent: openai_agent)

      # Run should succeed despite hook error
      result = runner.run("Hello")

      # Verify execution continued despite error
      expect(result[:success]).to be true
      expect(execution_log).to include("agent_start:OpenAIAgents::Agent")
      expect(execution_log).to include("global_end_success")
      expect(execution_log).to include("agent_end:Hash")
    end
  end
end

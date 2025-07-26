# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Real Hooks Integration", :integration do
  # Skip these tests if no OpenAI API key is available or OpenAIAgents is not available
  before(:all) do
    skip "OpenAI API key not available" unless ENV["OPENAI_API_KEY"]
    skip "OpenAIAgents not available" unless defined?(OpenAIAgents)
  end

  let(:execution_log) { [] }

  # Simple test agent that uses hooks
  let(:test_agent_class) do
    execution_log_ref = execution_log

    Class.new(RAAF::DSL::Agents::Base) do
      include RAAF::DSL::AgentDsl
      include RAAF::DSL::Hooks::AgentHooks

      agent_name "simple_test_agent"
      model "gpt-4o-mini" # Use cheaper model for testing
      max_turns 1

      def self.name
        "SimpleTestAgent"
      end

      # Agent-specific hooks
      on_start { |_agent| execution_log_ref << "agent_start" }
      on_end { |_agent, _result| execution_log_ref << "agent_end" }
      on_tool_start { |_agent, _tool, _params| execution_log_ref << "agent_tool_start" }
      on_tool_end { |_agent, _tool, _params, _result| execution_log_ref << "agent_tool_end" }
      on_error { |_agent, _error| execution_log_ref << "agent_error" }
      on_handoff { |_from, _to| execution_log_ref << "agent_handoff" }

      private

      def agent_name
        "simple_test_agent"
      end

      def build_instructions
        "You are a helpful assistant. Answer questions concisely."
      end
    end
  end

  let(:agent_instance) { test_agent_class.new }

  before do
    # Clear execution log
    execution_log.clear

    # Clear global hooks
    RAAF::DSL::Hooks::RunHooks.clear_hooks!
  end

  after do
    # Clear global hooks after each test
    RAAF::DSL::Hooks::RunHooks.clear_hooks!
  end

  describe "real agent execution with hooks" do
    it "verifies hooks are called during actual agent execution" do
      # Set up global hooks
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start" }
      RAAF::DSL::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end" }

      # Create context with a simple question
      context = RAAF::DSL::ContextVariables.new({
                                                  user_input: "What is 2 + 2?"
                                                })

      # Run the agent
      result = agent_instance.run(context: context)

      # Verify the agent executed successfully
      expect(result).to be_a(Hash)
      expect(result[:success]).to be true
      expect(result[:messages]).to be_an(Array)
      expect(result[:messages].length).to be > 0

      # Verify hooks were called in correct order
      expect(execution_log).to eq(%w[global_start agent_start global_end agent_end])
    end

    it "verifies hooks work with different execution scenarios" do
      # Set up comprehensive hooks
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start" }
      RAAF::DSL::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end" }
      RAAF::DSL::Hooks::RunHooks.on_error { |_agent, _error| execution_log << "global_error" }

      # Create context with a simple question
      context = RAAF::DSL::ContextVariables.new({
                                                  user_input: "Hello, how are you?"
                                                })

      # Run the agent
      result = agent_instance.run(context: context)

      # Verify basic execution
      expect(result).to be_a(Hash)
      expect(result[:success]).to be true

      # Verify hooks were called (at minimum start and end)
      expect(execution_log).to include("global_start")
      expect(execution_log).to include("agent_start")
      expect(execution_log).to include("global_end")
      expect(execution_log).to include("agent_end")

      # Verify no error hooks were called
      expect(execution_log).not_to include("global_error")
      expect(execution_log).not_to include("agent_error")
    end

    it "verifies hooks provide correct agent information" do
      captured_agent_names = []
      captured_results = []

      # Set up hooks that capture agent information
      RAAF::DSL::Hooks::RunHooks.on_agent_start do |agent|
        captured_agent_names << agent.name if agent.respond_to?(:name)
        execution_log << "global_start"
      end

      RAAF::DSL::Hooks::RunHooks.on_agent_end do |_agent, result|
        captured_results << result
        execution_log << "global_end"
      end

      # Create context
      context = RAAF::DSL::ContextVariables.new({
                                                  user_input: "What is the capital of France?"
                                                })

      # Run the agent
      agent_instance.run(context: context)

      # Verify hooks were called
      expect(execution_log).to include("global_start")
      expect(execution_log).to include("global_end")

      # Verify captured information
      expect(captured_agent_names).not_to be_empty
      expect(captured_results).not_to be_empty
      expect(captured_results.first).to be_a(Hash)
    end

    it "verifies hooks are resilient to errors" do
      # Set up hooks where one fails
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| raise "Global hook error" }
      RAAF::DSL::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end_success" }

      # Create context
      context = RAAF::DSL::ContextVariables.new({
                                                  user_input: "What is 1 + 1?"
                                                })

      # Run the agent - should not fail despite hook error
      result = agent_instance.run(context: context)

      # Verify the agent still executed successfully
      expect(result).to be_a(Hash)
      expect(result[:success]).to be true

      # Verify that subsequent hooks still executed
      expect(execution_log).to include("agent_start")
      expect(execution_log).to include("global_end_success")
      expect(execution_log).to include("agent_end")
    end

    it "verifies multiple hooks of same type execute in order" do
      # Set up multiple hooks of the same type
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start_1" }
      RAAF::DSL::Hooks::RunHooks.on_agent_start { |_agent| execution_log << "global_start_2" }
      RAAF::DSL::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end_1" }
      RAAF::DSL::Hooks::RunHooks.on_agent_end { |_agent, _result| execution_log << "global_end_2" }

      # Create context
      context = RAAF::DSL::ContextVariables.new({
                                                  user_input: "Say hello"
                                                })

      # Run the agent
      result = agent_instance.run(context: context)

      # Verify agent executed successfully
      expect(result).to be_a(Hash)
      expect(result[:success]).to be true

      # Verify hooks executed in correct order
      expect(execution_log).to eq(%w[
                                    global_start_1 global_start_2 agent_start
                                    global_end_1 global_end_2 agent_end
                                  ])
    end
  end

  describe "real agent with tool usage" do
    # Create agent that uses tools to test tool hooks
    let(:tool_agent_class) do
      execution_log_ref = execution_log

      Class.new(RAAF::DSL::Agents::Base) do
        include RAAF::DSL::AgentDsl
        include RAAF::DSL::Hooks::AgentHooks

        agent_name "tool_test_agent"
        model "gpt-4o-mini"
        max_turns 2

        def self.name
          "ToolTestAgent"
        end

        # Agent-specific hooks
        on_start { |_agent| execution_log_ref << "agent_start" }
        on_end { |_agent, _result| execution_log_ref << "agent_end" }
        on_tool_start { |_agent, tool, _params| execution_log_ref << "agent_tool_start:#{tool}" }
        on_tool_end { |_agent, tool, _params, _result| execution_log_ref << "agent_tool_end:#{tool}" }

        private

        def agent_name
          "tool_test_agent"
        end

        def build_instructions
          "You are a helpful assistant with access to tools."
        end

        def build_schema
          {
            type: "object",
            properties: {
              search_query: {
                type: "string",
                description: "Search query to execute"
              }
            },
            required: ["search_query"]
          }
        end
      end
    end

    let(:tool_agent_instance) { tool_agent_class.new }

    # NOTE: This test would require actual tool configuration
    # For now, we'll just verify the hook system can handle tool events
    it "verifies tool hooks are properly configured" do
      # Set up tool hooks
      RAAF::DSL::Hooks::RunHooks.on_tool_start { |_agent, tool, _params| execution_log << "global_tool_start:#{tool}" }
      RAAF::DSL::Hooks::RunHooks.on_tool_end { |_agent, tool, _params, _result| execution_log << "global_tool_end:#{tool}" }

      # Create context
      context = RAAF::DSL::ContextVariables.new({
                                                  user_input: "Hello, just respond with 'Hi there!'"
                                                })

      # Run the agent
      result = tool_agent_instance.run(context: context)

      # Verify agent executed successfully
      expect(result).to be_a(Hash)
      expect(result[:success]).to be true

      # Verify basic hooks were called
      expect(execution_log).to include("agent_start")
      expect(execution_log).to include("agent_end")

      # Tool hooks may or may not be called depending on if tools are actually invoked
      # The important thing is that they're properly configured and don't cause errors
    end
  end
end

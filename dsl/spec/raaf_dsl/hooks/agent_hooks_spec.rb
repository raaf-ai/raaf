# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe RAAF::DSL::Hooks::AgentHooks do
  let(:agent_class) do
    Class.new(RAAF::DSL::Agents::Base) do
      include RAAF::DSL::Hooks::AgentHooks

      def agent_name
        "TestAgent"
      end

      def build_instructions
        "Test instructions"
      end

      def build_user_prompt
        "Test prompt"
      end

      def transform_run_result(result)
        result
      end
    end
  end

  let(:agent_instance) { agent_class.new }

  before do
    # Clear hooks before each test
    agent_class.clear_agent_hooks!
    RAAF::DSL::Hooks::RunHooks.clear_hooks!
  end

  describe "DSL methods" do
    it "provides on_start DSL method" do
      expect(agent_class).to respond_to(:on_start)
    end

    it "provides on_end DSL method" do
      expect(agent_class).to respond_to(:on_end)
    end

    it "provides on_handoff DSL method" do
      expect(agent_class).to respond_to(:on_handoff)
    end

    it "provides on_tool_start DSL method" do
      expect(agent_class).to respond_to(:on_tool_start)
    end

    it "provides on_tool_end DSL method" do
      expect(agent_class).to respond_to(:on_tool_end)
    end

    it "provides on_error DSL method" do
      expect(agent_class).to respond_to(:on_error)
    end
  end

  describe "hook registration" do
    it "registers block hooks" do
      test_proc = proc { |_agent| puts "Test hook" }
      agent_class.on_start(&test_proc)

      hooks_config = agent_class.agent_hooks_config
      expect(hooks_config[:on_start]).to contain_exactly(test_proc)
    end

    it "registers method name hooks" do
      agent_class.on_start :test_method

      hooks_config = agent_class.agent_hooks_config
      expect(hooks_config[:on_start]).to contain_exactly(:test_method)
    end

    it "registers multiple hooks in order" do
      test_proc1 = proc { |_agent| puts "First" }
      test_proc2 = proc { |_agent| puts "Second" }

      agent_class.on_start(&test_proc1)
      agent_class.on_start :test_method
      agent_class.on_start(&test_proc2)

      hooks_config = agent_class.agent_hooks_config
      expect(hooks_config[:on_start]).to eq([test_proc1, :test_method, test_proc2])
    end

    it "registers hooks for all supported event types" do
      agent_class.on_start { |agent| } # rubocop:disable Lint/EmptyBlock
      agent_class.on_end { |agent, result| } # rubocop:disable Lint/EmptyBlock
      agent_class.on_handoff { |from, to| } # rubocop:disable Lint/EmptyBlock
      agent_class.on_tool_start { |agent, tool, params| } # rubocop:disable Lint/EmptyBlock
      agent_class.on_tool_end { |agent, tool, params, result| } # rubocop:disable Lint/EmptyBlock
      agent_class.on_error { |agent, error| } # rubocop:disable Lint/EmptyBlock

      hooks_config = agent_class.agent_hooks_config
      expect(hooks_config.keys).to include(:on_start, :on_end, :on_handoff, :on_tool_start, :on_tool_end, :on_error)
    end
  end

  describe "hook configuration" do
    it "returns empty config when no hooks registered" do
      hooks_config = agent_class.agent_hooks_config
      expect(hooks_config).to be_empty
    end

    it "only includes hook types that have registered handlers" do
      agent_class.on_start { |agent| } # rubocop:disable Lint/EmptyBlock
      agent_class.on_error { |agent, error| } # rubocop:disable Lint/EmptyBlock

      hooks_config = agent_class.agent_hooks_config
      expect(hooks_config.keys).to contain_exactly(:on_start, :on_error)
      expect(hooks_config.keys).not_to include(:on_end, :on_handoff, :on_tool_start, :on_tool_end)
    end

    it "preserves hook registration order" do
      first_hook = proc { |_agent| puts "First" }
      second_hook = proc { |_agent| puts "Second" }
      third_hook = proc { |_agent| puts "Third" }

      agent_class.on_start(&first_hook)
      agent_class.on_start(&second_hook)
      agent_class.on_start(&third_hook)

      hooks_config = agent_class.agent_hooks_config
      expect(hooks_config[:on_start]).to eq([first_hook, second_hook, third_hook])
    end
  end

  describe "combined hooks configuration" do
    it "includes only agent hooks when no global hooks" do
      agent_proc = proc { |_agent| puts "Agent hook" }
      agent_class.on_start(&agent_proc)

      combined_config = agent_instance.combined_hooks_config
      expect(combined_config[:on_start]).to contain_exactly(agent_proc)
    end

    it "includes only global hooks when no agent hooks" do
      global_proc = proc { |_agent| puts "Global hook" }
      RAAF::DSL::Hooks::RunHooks.on_agent_start(&global_proc)

      combined_config = agent_instance.combined_hooks_config
      expect(combined_config[:on_agent_start]).to contain_exactly(global_proc)
    end

    it "combines global and agent hooks with global hooks first" do
      global_proc = proc { |_agent| puts "Global hook" }
      agent_proc = proc { |_agent| puts "Agent hook" }

      RAAF::DSL::Hooks::RunHooks.on_agent_start(&global_proc)
      agent_class.on_start(&agent_proc)

      combined_config = agent_instance.combined_hooks_config
      expect(combined_config[:on_agent_start]).to contain_exactly(global_proc)
      expect(combined_config[:on_start]).to contain_exactly(agent_proc)
    end

    it "returns nil when no hooks are configured" do
      combined_config = agent_instance.combined_hooks_config
      expect(combined_config).to be_nil
    end
  end

  describe "hook validation" do
    it "raises error for invalid hook type" do
      expect do
        agent_class.send(:register_agent_hook, :invalid_hook, :test_method)
      end.to raise_error(ArgumentError, /Invalid hook type/)
    end

    it "raises error when neither method nor block provided" do
      expect do
        agent_class.on_start
      end.to raise_error(ArgumentError, /Either method_name or block must be provided/)
    end

    it "raises error when both method and block provided" do
      expect do
        agent_class.on_start(:test_method) { |agent| } # rubocop:disable Lint/EmptyBlock
      end.to raise_error(ArgumentError, /Cannot provide both method_name and block/)
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      Class.new(RAAF::DSL::Agents::Base) do
        include RAAF::DSL::Hooks::AgentHooks

        def agent_name
          "ParentAgent"
        end

        def build_instructions
          "Parent instructions"
        end

        def build_user_prompt
          "Parent prompt"
        end

        def transform_run_result(result)
          result
        end

        on_start { |_agent| puts "Parent hook" }
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        def agent_name
          "ChildAgent"
        end

        on_start { |_agent| puts "Child hook" }
      end
    end

    it "inherits parent hooks" do
      child_instance = child_class.new
      combined_config = child_instance.combined_hooks_config

      expect(combined_config[:on_start]).to have(2).items
      expect(combined_config[:on_start][0]).to be_a(Proc)
      expect(combined_config[:on_start][1]).to be_a(Proc)
    end

    it "child hooks are added after parent hooks" do
      parent_hook = parent_class.get_agent_hooks(:on_start).first
      child_hook = child_class.get_agent_hooks(:on_start).last

      expect(child_class.get_agent_hooks(:on_start)).to eq([parent_hook, child_hook])
    end
  end

  describe "testing utilities" do
    it "can clear all hooks" do
      agent_class.on_start { |agent| } # rubocop:disable Lint/EmptyBlock
      agent_class.on_end { |agent, result| } # rubocop:disable Lint/EmptyBlock

      expect(agent_class.agent_hooks_config).not_to be_empty

      agent_class.clear_agent_hooks!

      expect(agent_class.agent_hooks_config).to be_empty
    end

    it "can get hooks for specific type" do
      test_hook = proc { |agent| }
      agent_class.on_start(&test_hook)

      hooks = agent_class.get_agent_hooks(:on_start)
      expect(hooks).to contain_exactly(test_hook)
    end

    it "returns empty array for unregistered hook types" do
      hooks = agent_class.get_agent_hooks(:on_start)
      expect(hooks).to eq([])
    end
  end
end

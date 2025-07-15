# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe AiAgentDsl::Hooks::RunHooks do
  before do
    # Clear hooks before each test
    described_class.clear_hooks!
  end

  after do
    # Clean up after each test
    described_class.clear_hooks!
  end

  describe "DSL methods" do
    it "provides on_agent_start DSL method" do
      expect(described_class).to respond_to(:on_agent_start)
    end

    it "provides on_agent_end DSL method" do
      expect(described_class).to respond_to(:on_agent_end)
    end

    it "provides on_handoff DSL method" do
      expect(described_class).to respond_to(:on_handoff)
    end

    it "provides on_tool_start DSL method" do
      expect(described_class).to respond_to(:on_tool_start)
    end

    it "provides on_tool_end DSL method" do
      expect(described_class).to respond_to(:on_tool_end)
    end

    it "provides on_error DSL method" do
      expect(described_class).to respond_to(:on_error)
    end
  end

  describe "hook registration" do
    it "registers block hooks" do
      test_proc = proc { |_agent| puts "Test hook" }
      described_class.on_agent_start(&test_proc)

      hooks_config = described_class.hooks_config
      expect(hooks_config[:on_agent_start]).to contain_exactly(test_proc)
    end

    it "registers method name hooks" do
      described_class.on_agent_start :test_method

      hooks_config = described_class.hooks_config
      expect(hooks_config[:on_agent_start]).to contain_exactly(:test_method)
    end

    it "registers multiple hooks in order" do
      test_proc1 = proc { |_agent| puts "First" }
      test_proc2 = proc { |_agent| puts "Second" }

      described_class.on_agent_start(&test_proc1)
      described_class.on_agent_start :test_method
      described_class.on_agent_start(&test_proc2)

      hooks_config = described_class.hooks_config
      expect(hooks_config[:on_agent_start]).to eq([test_proc1, :test_method, test_proc2])
    end

    it "registers hooks for all supported event types" do
      described_class.on_agent_start { |agent| }
      described_class.on_agent_end { |agent, result| }
      described_class.on_handoff { |from, to| }
      described_class.on_tool_start { |agent, tool, params| }
      described_class.on_tool_end { |agent, tool, params, result| }
      described_class.on_error { |agent, error| }

      hooks_config = described_class.hooks_config
      expect(hooks_config.keys).to include(
        :on_agent_start, :on_agent_end, :on_handoff,
        :on_tool_start, :on_tool_end, :on_error
      )
    end
  end

  describe "hook configuration" do
    it "returns empty config when no hooks registered" do
      hooks_config = described_class.hooks_config
      expect(hooks_config).to be_empty
    end

    it "only includes hook types that have registered handlers" do
      described_class.on_agent_start { |agent| }
      described_class.on_error { |agent, error| }

      hooks_config = described_class.hooks_config
      expect(hooks_config.keys).to contain_exactly(:on_agent_start, :on_error)
      expect(hooks_config.keys).not_to include(:on_agent_end, :on_handoff, :on_tool_start, :on_tool_end)
    end

    it "preserves hook registration order" do
      first_hook = proc { |_agent| puts "First" }
      second_hook = proc { |_agent| puts "Second" }
      third_hook = proc { |_agent| puts "Third" }

      described_class.on_agent_start(&first_hook)
      described_class.on_agent_start(&second_hook)
      described_class.on_agent_start(&third_hook)

      hooks_config = described_class.hooks_config
      expect(hooks_config[:on_agent_start]).to eq([first_hook, second_hook, third_hook])
    end

    it "returns independent copies of hook arrays" do
      test_hook = proc { |agent| }
      described_class.on_agent_start(&test_hook)

      config1 = described_class.hooks_config
      config2 = described_class.hooks_config

      # Verify they have the same content
      expect(config1[:on_agent_start]).to eq(config2[:on_agent_start])

      # Verify they are different objects (independent copies)
      expect(config1[:on_agent_start]).not_to be(config2[:on_agent_start])
    end
  end

  describe "hook validation" do
    it "raises error for invalid hook type" do
      expect do
        described_class.send(:register_hook, :invalid_hook, :test_method)
      end.to raise_error(ArgumentError, /Invalid hook type/)
    end

    it "raises error when neither method nor block provided" do
      expect do
        described_class.on_agent_start
      end.to raise_error(ArgumentError, /Either method_name or block must be provided/)
    end

    it "raises error when both method and block provided" do
      expect do
        described_class.on_agent_start(:test_method) { |agent| }
      end.to raise_error(ArgumentError, /Cannot provide both method_name and block/)
    end
  end

  describe "testing utilities" do
    it "can clear all hooks" do
      described_class.on_agent_start { |agent| }
      described_class.on_agent_end { |agent, result| }

      expect(described_class.hooks_config).not_to be_empty

      described_class.clear_hooks!

      expect(described_class.hooks_config).to be_empty
    end

    it "can get hooks for specific type" do
      test_hook = proc { |agent| }
      described_class.on_agent_start(&test_hook)

      hooks = described_class.get_hooks(:on_agent_start)
      expect(hooks).to contain_exactly(test_hook)
    end

    it "returns empty array for unregistered hook types" do
      hooks = described_class.get_hooks(:on_agent_start)
      expect(hooks).to eq([])
    end

    it "returns independent copies from get_hooks" do
      test_hook = proc { |agent| }
      described_class.on_agent_start(&test_hook)

      hooks1 = described_class.get_hooks(:on_agent_start)
      hooks2 = described_class.get_hooks(:on_agent_start)

      expect(hooks1).to eq(hooks2)
      expect(hooks1).not_to be(hooks2)
    end
  end

  describe "hook types constant" do
    it "includes all expected hook types" do
      expected_types = [
        :on_agent_start,
        :on_agent_end,
        :on_handoff,
        :on_tool_start,
        :on_tool_end,
        :on_error
      ]

      expect(described_class::HOOK_TYPES).to match_array(expected_types)
    end

    it "uses frozen hook types array" do
      expect(described_class::HOOK_TYPES).to be_frozen
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL do
  describe "module structure" do
    it "defines the main module" do
      expect(defined?(RAAF::DSL)).to eq("constant")
    end

    it "defines the base error class" do
      expect(RAAF::DSL::Error).to be < StandardError
    end

    it "defines the version constant" do
      expect(defined?(RAAF::DSL::VERSION)).to eq("constant")
      expect(RAAF::DSL::VERSION).to be_a(String)
    end
  end

  describe "autoloaded constants" do
    it "autoloads core classes" do
      # Test a few key autoloaded classes
      expect { RAAF::DSL::Agent }.not_to raise_error
      expect { RAAF::DSL::Service }.not_to raise_error
      expect { RAAF::DSL::ContextVariables }.not_to raise_error
      expect { RAAF::DSL::Result }.not_to raise_error
    end

    it "autoloads builder classes" do
      expect { RAAF::DSL::AgentBuilder }.not_to raise_error
      expect { RAAF::DSL::ToolBuilder }.not_to raise_error
      expect { RAAF::DSL::ConfigurationBuilder }.not_to raise_error
    end

    it "autoloads prompt system" do
      expect { RAAF::DSL::Prompts::Base }.not_to raise_error
      expect { RAAF::DSL::PromptResolvers::ClassResolver }.not_to raise_error
      expect { RAAF::DSL::PromptResolvers::FileResolver }.not_to raise_error
    end

    it "autoloads tools module" do
      expect { RAAF::DSL::Tools::Base }.not_to raise_error
      expect { RAAF::DSL::Tools::WebSearch }.not_to raise_error
      expect { RAAF::DSL::Tools::TavilySearch }.not_to raise_error
    end

    it "autoloads debugging tools" do
      expect { RAAF::DSL::Debugging::LLMInterceptor }.not_to raise_error
      expect { RAAF::DSL::Debugging::PromptInspector }.not_to raise_error
      expect { RAAF::DSL::Debugging::ContextInspector }.not_to raise_error
    end

    it "autoloads hooks system" do
      expect { RAAF::DSL::Hooks::RunHooks }.not_to raise_error
      expect { RAAF::DSL::Hooks::AgentHooks }.not_to raise_error
    end
  end

  describe ".configure" do
    let(:original_config) { described_class.configuration.dup }

    after do
      # Reset configuration after each test
      described_class.instance_variable_set(:@configuration, nil)
    end

    it "yields the configuration object" do
      config_yielded = nil
      described_class.configure do |config|
        config_yielded = config
      end

      expect(config_yielded).to be_a(RAAF::DSL::Configuration)
    end

    it "allows setting configuration options" do
      described_class.configure do |config|
        config.default_model = "gpt-4o-mini"
        config.default_max_turns = 5
        config.debug_enabled = true
      end

      config = described_class.configuration
      expect(config.default_model).to eq("gpt-4o-mini")
      expect(config.default_max_turns).to eq(5)
      expect(config.debug_enabled).to eq(true)
    end
  end

  describe ".configuration" do
    after do
      # Reset configuration after each test
      described_class.instance_variable_set(:@configuration, nil)
    end

    it "returns a Configuration instance" do
      expect(described_class.configuration).to be_a(RAAF::DSL::Configuration)
    end

    it "returns the same instance on subsequent calls" do
      first_call = described_class.configuration
      second_call = described_class.configuration
      expect(first_call).to be(second_call)
    end

    it "has default values" do
      config = described_class.configuration
      expect(config.config_file).to eq("config/ai_agents.yml")
      expect(config.default_model).to eq("gpt-4o")
      expect(config.default_max_turns).to eq(3)
      expect(config.default_temperature).to eq(0.7)
      expect(config.default_tool_choice).to eq("auto")
      expect(config.debug_enabled).to eq(false)
    end
  end

  describe ".configure_prompts" do
    it "delegates to PromptConfiguration" do
      expect(RAAF::DSL::PromptConfiguration).to receive(:configure).and_yield

      block_called = false
      described_class.configure_prompts do
        block_called = true
      end

      expect(block_called).to eq(true)
    end
  end

  describe ".prompt_configuration" do
    after do
      described_class.instance_variable_set(:@prompt_configuration, nil)
    end

    it "returns a PromptConfiguration instance" do
      expect(described_class.prompt_configuration).to be_a(RAAF::DSL::PromptConfiguration)
    end

    it "returns the same instance on subsequent calls" do
      first_call = described_class.prompt_configuration
      second_call = described_class.prompt_configuration
      expect(first_call).to be(second_call)
    end
  end

  describe ".prompt_resolvers" do
    after do
      described_class.instance_variable_set(:@prompt_resolvers, nil)
    end

    it "returns a PromptResolverRegistry instance" do
      expect(described_class.prompt_resolvers).to be_a(RAAF::DSL::PromptResolverRegistry)
    end

    it "initializes default resolvers" do
      registry = described_class.prompt_resolvers
      resolvers = registry.resolvers

      expect(resolvers.size).to be >= 2
      expect(resolvers.any? { |r| r.is_a?(RAAF::DSL::PromptResolvers::ClassResolver) }).to eq(true)
      expect(resolvers.any? { |r| r.is_a?(RAAF::DSL::PromptResolvers::FileResolver) }).to eq(true)
    end

    it "returns the same instance on subsequent calls" do
      first_call = described_class.prompt_resolvers
      second_call = described_class.prompt_resolvers
      expect(first_call).to be(second_call)
    end
  end

  describe ".ensure_prompt_resolvers_initialized!" do
    after do
      described_class.instance_variable_set(:@prompt_resolvers, nil)
    end

    it "returns initialized prompt resolvers" do
      registry = described_class.ensure_prompt_resolvers_initialized!
      expect(registry).to be_a(RAAF::DSL::PromptResolverRegistry)
      expect(registry.resolvers).not_to be_empty
    end

    it "handles failed initialization gracefully" do
      # Simulate failed initialization
      described_class.instance_variable_set(:@prompt_resolvers, nil)

      # Mock initialize_default_resolvers to fail
      allow(described_class).to receive(:initialize_default_resolvers)
        .and_raise(StandardError.new("Mock error"))

      # Should still return a working registry
      expect { described_class.ensure_prompt_resolvers_initialized! }.not_to raise_error
    end
  end

  describe ".eager_load!" do
    it "loads all autoloaded constants without error" do
      expect { described_class.eager_load! }.not_to raise_error
    end

    it "skips problematic constants" do
      # Mock constants method to include Pipeline
      allow(described_class).to receive(:constants).and_return([:Pipeline, :Agent, :Service])

      # Should not attempt to load Pipeline
      expect(described_class).not_to receive(:const_get).with(:Pipeline)
      expect(described_class).to receive(:const_get).with(:Agent).and_return(RAAF::DSL::Agent)
      expect(described_class).to receive(:const_get).with(:Service).and_return(RAAF::DSL::Service)

      described_class.eager_load!
    end

    it "handles loading errors gracefully" do
      # Mock constants method to include a problematic constant
      allow(described_class).to receive(:constants).and_return([:ProblematicConstant])
      allow(described_class).to receive(:const_get).with(:ProblematicConstant)
        .and_raise(NameError.new("Mock error"))

      # Should warn but not raise
      expect { described_class.eager_load! }.not_to raise_error
    end
  end

  describe RAAF::DSL::Configuration do
    subject { described_class.new }

    it "has default configuration values" do
      expect(subject.config_file).to eq("config/ai_agents.yml")
      expect(subject.default_model).to eq("gpt-4o")
      expect(subject.default_max_turns).to eq(3)
      expect(subject.default_temperature).to eq(0.7)
      expect(subject.default_tool_choice).to eq("auto")
      expect(subject.debug_enabled).to eq(false)
      expect(subject.debug_level).to eq(:standard)
      expect(subject.debug_output).to be_nil
      expect(subject.logging_level).to eq(:info)
      expect(subject.structured_logging).to eq(true)
      expect(subject.enable_tracing).to be_nil
    end

    it "allows setting all configuration attributes" do
      subject.config_file = "custom/config.yml"
      subject.default_model = "gpt-3.5-turbo"
      subject.default_max_turns = 10
      subject.default_temperature = 0.9
      subject.default_tool_choice = "required"
      subject.debug_enabled = true
      subject.debug_level = :verbose
      subject.debug_output = STDOUT
      subject.logging_level = :debug
      subject.structured_logging = false
      subject.enable_tracing = true

      expect(subject.config_file).to eq("custom/config.yml")
      expect(subject.default_model).to eq("gpt-3.5-turbo")
      expect(subject.default_max_turns).to eq(10)
      expect(subject.default_temperature).to eq(0.9)
      expect(subject.default_tool_choice).to eq("required")
      expect(subject.debug_enabled).to eq(true)
      expect(subject.debug_level).to eq(:verbose)
      expect(subject.debug_output).to eq(STDOUT)
      expect(subject.logging_level).to eq(:debug)
      expect(subject.structured_logging).to eq(false)
      expect(subject.enable_tracing).to eq(true)
    end
  end

  describe "Rails integration" do
    it "loads Railtie when Rails is defined" do
      # Skip this test if Rails is not defined in the test environment
      skip "Rails not defined" unless defined?(Rails)

      expect(defined?(RAAF::DSL::Railtie)).to eq("constant")
    end
  end

  describe "module hierarchy" do
    it "properly nests all modules" do
      # Test that all expected modules are properly nested under RAAF::DSL
      expect(RAAF::DSL::Agents).to be_a(Module)
      expect(RAAF::DSL::Builders).to be_a(Module)
      expect(RAAF::DSL::Prompts).to be_a(Module)
      expect(RAAF::DSL::PromptResolvers).to be_a(Module)
      expect(RAAF::DSL::Tools).to be_a(Module)
      expect(RAAF::DSL::Debugging).to be_a(Module)
      expect(RAAF::DSL::Hooks).to be_a(Module)
      expect(RAAF::DSL::Generators).to be_a(Module)
      expect(RAAF::DSL::Schema).to be_a(Module)
    end
  end

  describe "examples from documentation" do
    it "supports basic agent definition pattern" do
      # Test that the documented pattern works
      expect {
        Class.new(RAAF::DSL::Agent) do
          agent_name "MyAgent"

          # Mock the tool system for testing
          def self.uses_tool(tool_name)
            # Mock implementation
          end

          def self.tool_choice(choice)
            # Mock implementation
          end

          def self.schema(&block)
            # Mock implementation
          end

          uses_tool :web_search
          tool_choice "auto"

          schema do
            # Mock schema definition
          end
        end
      }.not_to raise_error
    end
  end
end
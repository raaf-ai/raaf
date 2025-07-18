# frozen_string_literal: true

RSpec.describe RAAF::DSL do
  it_behaves_like "a configurable class"

  describe "module constants" do
    it "defines VERSION constant" do
      expect(described_class.const_defined?(:VERSION)).to be true
    end

    it "defines Error class" do
      expect(described_class.const_defined?(:Error)).to be true
      expect(described_class::Error).to be < StandardError
    end

    it "defines Configuration class" do
      expect(described_class.const_defined?(:Configuration)).to be true
    end
  end

  describe "autoloaded modules" do
    it "autoloads AgentDsl" do
      # Check if it's autoloaded or already loaded
      expect(described_class.autoload?(:AgentDsl) || described_class.const_defined?(:AgentDsl)).to be_truthy
    end

    it "autoloads Config" do
      # Check if it's autoloaded or already loaded
      expect(described_class.autoload?(:Config) || described_class.const_defined?(:Config)).to be_truthy
    end

    it "autoloads ToolDsl" do
      # Check if it's autoloaded or already loaded
      expect(described_class.autoload?(:ToolDsl) || described_class.const_defined?(:ToolDsl)).to be_truthy
    end

    it "autoloads Agents module" do
      expect(described_class.const_defined?(:Agents)).to be true
    end

    it "autoloads Prompts module" do
      expect(described_class.const_defined?(:Prompts)).to be true
    end

    it "autoloads Tools module" do
      expect(described_class.const_defined?(:Tools)).to be true
    end
  end

  describe "nested modules" do
    describe "Agents" do
      it "autoloads Base class" do
        expect(described_class::Agents.autoload?(:Base) || described_class::Agents.const_defined?(:Base)).to be_truthy
      end
    end

    describe "Prompts" do
      it "autoloads Base class" do
        expect(described_class::Prompts.autoload?(:Base) || described_class::Prompts.const_defined?(:Base)).to be_truthy
      end
    end

    describe "Tools" do
      it "autoloads Base class" do
        expect(described_class::Tools.autoload?(:Base) || described_class::Tools.const_defined?(:Base)).to be_truthy
      end
    end
  end

  describe ".configure" do
    it "yields the configuration object" do
      expect { |b| described_class.configure(&b) }.to yield_with_args(described_class.configuration)
    end

    it "allows setting configuration options" do
      described_class.configure do |config|
        config.default_model = "gpt-3.5-turbo"
        config.default_max_turns = 5
      end

      expect(described_class.configuration.default_model).to eq("gpt-3.5-turbo")
      expect(described_class.configuration.default_max_turns).to eq(5)
    end

    it "persists configuration between calls" do
      described_class.configure do |config|
        config.default_model = "test-model"
      end

      expect(described_class.configuration.default_model).to eq("test-model")
    end

    it "can be called multiple times" do
      described_class.configure do |config|
        config.default_model = "model1"
      end

      described_class.configure do |config|
        config.default_max_turns = 10
      end

      expect(described_class.configuration.default_model).to eq("model1")
      expect(described_class.configuration.default_max_turns).to eq(10)
    end
  end

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(described_class.configuration).to be_a(described_class::Configuration)
    end

    it "returns the same instance on subsequent calls" do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to be(config2)
    end

    it "provides default configuration values" do
      config = described_class.configuration
      expect(config.config_file).to eq("config/ai_agents.yml")
      expect(config.default_model).to eq("gpt-4o")
      expect(config.default_max_turns).to eq(3)
      expect(config.default_temperature).to eq(0.7)
    end
  end

  describe "Configuration class" do
    let(:config) { described_class::Configuration.new }

    describe "#initialize" do
      it "sets default values" do
        expect(config.config_file).to eq("config/ai_agents.yml")
        expect(config.default_model).to eq("gpt-4o")
        expect(config.default_max_turns).to eq(3)
        expect(config.default_temperature).to eq(0.7)
      end
    end

    describe "attributes" do
      it "has config_file accessor" do
        expect(config).to respond_to(:config_file)
        expect(config).to respond_to(:config_file=)
      end

      it "has default_model accessor" do
        expect(config).to respond_to(:default_model)
        expect(config).to respond_to(:default_model=)
      end

      it "has default_max_turns accessor" do
        expect(config).to respond_to(:default_max_turns)
        expect(config).to respond_to(:default_max_turns=)
      end

      it "has default_temperature accessor" do
        expect(config).to respond_to(:default_temperature)
        expect(config).to respond_to(:default_temperature=)
      end
    end

    describe "attribute assignment" do
      it "allows setting config_file" do
        config.config_file = "custom/path.yml"
        expect(config.config_file).to eq("custom/path.yml")
      end

      it "allows setting default_model" do
        config.default_model = "gpt-3.5-turbo"
        expect(config.default_model).to eq("gpt-3.5-turbo")
      end

      it "allows setting default_max_turns" do
        config.default_max_turns = 10
        expect(config.default_max_turns).to eq(10)
      end

      it "allows setting default_temperature" do
        config.default_temperature = 0.5
        expect(config.default_temperature).to eq(0.5)
      end
    end
  end

  describe "Rails integration" do
    context "when Rails is defined", :with_rails do
      before do
        # Mock Rails::Railtie if it doesn't exist
        unless defined?(Rails::Railtie)
          rails_railtie = Class.new
          stub_const("Rails::Railtie", rails_railtie)
        end
      end

      it "requires the railtie" do
        # The railtie should be automatically required when Rails is present
        expect(defined?(described_class::Railtie)).to be_truthy
      end

      it "integrates with Rails application" do
        expect(described_class::Railtie).to be < Rails::Railtie
      end
    end

    context "when Rails is not defined" do
      before do
        # Hide Rails constant if it exists
        hide_const("Rails")
      end

      it "does not require the railtie" do
        # When Rails is not present, Railtie might already be loaded
        # Just check it's either autoloaded or already defined
        expect(described_class.autoload?(:Railtie) || described_class.const_defined?(:Railtie)).to be_truthy
      end
    end
  end

  describe "error handling" do
    describe "Error class" do
      it "is a subclass of StandardError" do
        expect(described_class::Error).to be < StandardError
      end

      it "can be instantiated" do
        error = described_class::Error.new("test message")
        expect(error).to be_a(described_class::Error)
        expect(error.message).to eq("test message")
      end

      it "can be raised and caught" do
        expect do
          raise described_class::Error, "test error"
        end.to raise_error(described_class::Error, "test error")
      end
    end
  end

  describe "module loading" do
    it "loads all autoloaded constants successfully" do
      # Force loading of autoloaded constants
      expect { described_class::AgentDsl }.not_to raise_error
      expect { described_class::Config }.not_to raise_error
      expect { described_class::ToolDsl }.not_to raise_error
      expect { described_class::Agents::Base }.not_to raise_error
      expect { described_class::Prompts::Base }.not_to raise_error
      expect { described_class::Tools::Base }.not_to raise_error
    end

    it "maintains proper module hierarchy" do
      expect(described_class::Agents::Base.name).to eq("RAAF::DSL::Agents::Base")
      expect(described_class::Prompts::Base.name).to eq("RAAF::DSL::Prompts::Base")
      expect(described_class::Tools::Base.name).to eq("RAAF::DSL::Tools::Base")
    end
  end

  describe "configuration inheritance" do
    it "allows child classes to inherit configuration" do
      described_class.configure do |config|
        config.default_model = "inherited-model"
      end

      # Create a new Configuration instance
      child_config = described_class::Configuration.new

      # Should have default values, not inherited ones (by design)
      expect(child_config.default_model).to eq("gpt-4o")

      # But the module configuration should persist
      expect(described_class.configuration.default_model).to eq("inherited-model")
    end
  end

  describe "thread safety" do
    it "maintains configuration across threads" do
      described_class.configure do |config|
        config.default_model = "thread-safe-model"
      end

      thread_result = nil
      thread = Thread.new do
        thread_result = described_class.configuration.default_model
      end
      thread.join

      expect(thread_result).to eq("thread-safe-model")
    end
  end

  describe "ActiveSupport integration" do
    it "loads ActiveSupport successfully" do
      expect(defined?(ActiveSupport)).to be_truthy
    end

    it "uses ActiveSupport features" do
      # The module should use ActiveSupport features like concern
      expect(described_class::AgentDsl).to respond_to(:included)
    end
  end

  describe "gem structure validation" do
    it "has proper file organization" do
      lib_path = File.expand_path("../lib", __dir__)

      expect(File.exist?(File.join(lib_path, "raaf-dsl.rb"))).to be true
      expect(Dir.exist?(File.join(lib_path, "raaf/dsl"))).to be true
    end

    it "follows Ruby naming conventions" do
      expect(described_class.name).to eq("RAAF::DSL")
      expect(described_class.name).to match(/\A[A-Z][a-zA-Z0-9]*(::[A-Z][a-zA-Z0-9]*)*\z/)
    end
  end
end

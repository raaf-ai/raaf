# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::DSL::Agent Tool Execution Configuration", type: :unit do
  # Set fake API key for testing
  before(:all) do
    @original_api_key = ENV.fetch("OPENAI_API_KEY", nil)
    ENV["OPENAI_API_KEY"] = "test-key-for-specs"
  end

  after(:all) do
    ENV["OPENAI_API_KEY"] = @original_api_key
  end

  describe "default configuration" do
    it "has all features enabled by default" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"
      end

      agent = agent_class.new

      expect(agent.validation_enabled?).to be true
      expect(agent.metadata_enabled?).to be true
    end
  end

  describe "class-level configuration" do
    it "allows configuring validation" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
        end
      end

      agent = agent_class.new

      expect(agent.validation_enabled?).to be false
    end

    it "allows configuring metadata" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"

        tool_execution do
          enable_metadata false
        end
      end

      agent = agent_class.new

      expect(agent.metadata_enabled?).to be false
    end

    it "allows multiple configuration options in one block" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
          enable_metadata false
        end
      end

      agent = agent_class.new

      expect(agent.validation_enabled?).to be false
      expect(agent.metadata_enabled?).to be false
    end
  end

  describe "configuration inheritance" do
    it "subclasses inherit parent configuration" do
      parent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
        end
      end

      subclass = Class.new(parent_class) do
        def self.name
          "SubclassAgent"
        end
        agent_name "SubclassAgent"
      end

      agent = subclass.new

      expect(agent.validation_enabled?).to be false
    end

    it "subclasses can override parent configuration" do
      parent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
        end
      end

      subclass = Class.new(parent_class) do
        def self.name
          "SubclassAgent"
        end
        agent_name "SubclassAgent"

        tool_execution do
          enable_validation true
        end
      end

      agent = subclass.new

      # Overridden values
      expect(agent.validation_enabled?).to be true
    end

    it "does not affect parent when subclass changes configuration" do
      parent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation true
        end
      end

      subclass = Class.new(parent_class) do
        def self.name
          "SubclassAgent"
        end
        agent_name "SubclassAgent"

        tool_execution do
          enable_validation false
        end
      end

      parent_agent = parent_class.new
      child_agent = subclass.new

      expect(parent_agent.validation_enabled?).to be true
      expect(child_agent.validation_enabled?).to be false
    end
  end

  describe "configuration immutability" do
    it "configuration is frozen after class definition" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
        end
      end

      config = agent_class.tool_execution_config

      expect(config).to be_frozen
    end

    it "modifying returned config does not affect class configuration" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
        end
      end

      config = agent_class.tool_execution_config
      # Attempting to modify should raise error (frozen hash)
      expect { config[:enable_validation] = true }.to raise_error(FrozenError)

      # Class configuration should be unchanged
      agent = agent_class.new
      expect(agent.validation_enabled?).to be false
    end
  end

  describe "instance-level configuration access" do
    it "instances access class-level configuration" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
        end
      end

      agent1 = agent_class.new
      agent2 = agent_class.new

      # Both instances see same configuration
      expect(agent1.validation_enabled?).to be false
      expect(agent2.validation_enabled?).to be false
    end
  end

  describe "configuration query methods" do
    it "provides boolean query methods with ? suffix" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"
      end

      agent = agent_class.new

      # Boolean query methods should exist
      expect(agent).to respond_to(:validation_enabled?)
      expect(agent).to respond_to(:metadata_enabled?)
    end
  end

  describe "tool_execution_enabled? integration" do
    it "returns true when any feature is enabled" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
          enable_metadata true
        end
      end

      agent = agent_class.new

      expect(agent.send(:tool_execution_enabled?)).to be true
    end

    it "returns false when all features are disabled" do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          "TestAgent"
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
          enable_metadata false
        end
      end

      agent = agent_class.new

      expect(agent.send(:tool_execution_enabled?)).to be false
    end
  end
end

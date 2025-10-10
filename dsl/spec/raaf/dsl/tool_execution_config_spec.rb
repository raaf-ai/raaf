# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'RAAF::DSL::Agent Tool Execution Configuration', type: :unit do
  # Set fake API key for testing
  before(:all) do
    @original_api_key = ENV['OPENAI_API_KEY']
    ENV['OPENAI_API_KEY'] = 'test-key-for-specs'
  end

  after(:all) do
    ENV['OPENAI_API_KEY'] = @original_api_key
  end

  describe 'default configuration' do
    it 'has all features enabled by default' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"
      end

      agent = agent_class.new

      expect(agent.validation_enabled?).to be true
      expect(agent.logging_enabled?).to be true
      expect(agent.metadata_enabled?).to be true
      expect(agent.log_arguments?).to be true
    end

    it 'has default truncation of 100 characters' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"
      end

      agent = agent_class.new

      expect(agent.truncate_logs_at).to eq(100)
    end
  end

  describe 'class-level configuration' do
    it 'allows configuring validation' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
        end
      end

      agent = agent_class.new

      expect(agent.validation_enabled?).to be false
    end

    it 'allows configuring logging' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          enable_logging false
        end
      end

      agent = agent_class.new

      expect(agent.logging_enabled?).to be false
    end

    it 'allows configuring metadata' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          enable_metadata false
        end
      end

      agent = agent_class.new

      expect(agent.metadata_enabled?).to be false
    end

    it 'allows configuring argument logging' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          log_arguments false
        end
      end

      agent = agent_class.new

      expect(agent.log_arguments?).to be false
    end

    it 'allows configuring log truncation' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          truncate_logs 250
        end
      end

      agent = agent_class.new

      expect(agent.truncate_logs_at).to eq(250)
    end

    it 'allows multiple configuration options in one block' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
          enable_logging true
          enable_metadata false
          log_arguments true
          truncate_logs 500
        end
      end

      agent = agent_class.new

      expect(agent.validation_enabled?).to be false
      expect(agent.logging_enabled?).to be true
      expect(agent.metadata_enabled?).to be false
      expect(agent.log_arguments?).to be true
      expect(agent.truncate_logs_at).to eq(500)
    end
  end

  describe 'configuration inheritance' do
    it 'subclasses inherit parent configuration' do
      parent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
          truncate_logs 200
        end
      end

      subclass = Class.new(parent_class) do
        def self.name
          'SubclassAgent'
        end
        agent_name "SubclassAgent"
      end

      agent = subclass.new

      expect(agent.validation_enabled?).to be false
      expect(agent.truncate_logs_at).to eq(200)
    end

    it 'subclasses can override parent configuration' do
      parent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
          enable_logging false
          truncate_logs 200
        end
      end

      subclass = Class.new(parent_class) do
        def self.name
          'SubclassAgent'
        end
        agent_name "SubclassAgent"

        tool_execution do
          enable_validation true
          enable_logging true
        end
      end

      agent = subclass.new

      # Overridden values
      expect(agent.validation_enabled?).to be true
      expect(agent.logging_enabled?).to be true

      # Inherited value
      expect(agent.truncate_logs_at).to eq(200)
    end

    it 'does not affect parent when subclass changes configuration' do
      parent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation true
        end
      end

      subclass = Class.new(parent_class) do
        def self.name
          'SubclassAgent'
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

  describe 'configuration immutability' do
    it 'configuration is frozen after class definition' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
        end
      end

      config = agent_class.tool_execution_config

      expect(config).to be_frozen
    end

    it 'modifying returned config does not affect class configuration' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
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

  describe 'instance-level configuration access' do
    it 'instances access class-level configuration' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
          truncate_logs 300
        end
      end

      agent1 = agent_class.new
      agent2 = agent_class.new

      # Both instances see same configuration
      expect(agent1.validation_enabled?).to be false
      expect(agent2.validation_enabled?).to be false
      expect(agent1.truncate_logs_at).to eq(300)
      expect(agent2.truncate_logs_at).to eq(300)
    end
  end

  describe 'configuration query methods' do
    it 'provides boolean query methods with ? suffix' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"
      end

      agent = agent_class.new

      # All boolean query methods should exist
      expect(agent).to respond_to(:validation_enabled?)
      expect(agent).to respond_to(:logging_enabled?)
      expect(agent).to respond_to(:metadata_enabled?)
      expect(agent).to respond_to(:log_arguments?)
    end

    it 'provides value accessor methods' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"
      end

      agent = agent_class.new

      expect(agent).to respond_to(:truncate_logs_at)
    end
  end

  describe 'tool_execution_enabled? integration' do
    it 'returns true when any feature is enabled' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
          enable_logging false
          enable_metadata true
        end
      end

      agent = agent_class.new

      expect(agent.send(:tool_execution_enabled?)).to be true
    end

    it 'returns false when all features are disabled' do
      agent_class = Class.new(RAAF::DSL::Agent) do
        def self.name
          'TestAgent'
        end
        agent_name "TestAgent"

        tool_execution do
          enable_validation false
          enable_logging false
          enable_metadata false
        end
      end

      agent = agent_class.new

      expect(agent.send(:tool_execution_enabled?)).to be false
    end
  end
end

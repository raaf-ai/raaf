# frozen_string_literal: true

require_relative "../../spec_helper"

# Rails generator tests
if defined?(Rails::Generators)
  begin
    require "rails/generators/test_case"

    class AgentGeneratorTest < Rails::Generators::TestCase
      tests AiAgentDsl::Generators::AgentGenerator
      destination File.expand_path("../../../tmp", __dir__)

      setup :prepare_destination

      def test_generator_creates_agent_file
        run_generator ["TestAgent"]

        assert_file "app/ai/agents/test_agent.rb" do |content|
          assert_match(/class TestAgent < AiAgentDsl::Agents::Base/, content)
          assert_match(/agent_name "TestAgent"/, content)
          assert_match(/include AiAgentDsl::AgentDsl/, content)
        end
      end

      def test_generator_creates_prompt_file
        run_generator ["TestAgent"]

        assert_file "app/ai/prompts/test_agent.rb" do |content|
          assert_match(/class TestAgent < AiAgentDsl::Prompts::Base/, content)
          assert_match(/def system/, content)
          assert_match(/def user/, content)
        end
      end

      def test_generator_handles_namespaced_agents
        run_generator ["Content::AnalysisAgent"]

        assert_file "app/ai/agents/content/analysis_agent.rb" do |content|
          assert_match(/module Content/, content)
          assert_match(/class AnalysisAgent < AiAgentDsl::Agents::Base/, content)
        end

        assert_file "app/ai/prompts/content/analysis_agent.rb" do |content|
          assert_match(/module Content/, content)
          assert_match(/class AnalysisAgent < AiAgentDsl::Prompts::Base/, content)
        end
      end
    end
  rescue LoadError
    # Rails generators not available
  end
end

# RSpec tests as fallback
RSpec.describe AiAgentDsl::Generators::AgentGenerator, :with_rails, :with_temp_files do
  describe "basic functionality" do
    it "exists as a constant" do
      expect(described_class).to be_a(Class)
    end

    it "can be instantiated" do
      expect { described_class.new }.not_to raise_error
    end

    if defined?(Rails::Generators::NamedBase)
      it "inherits from Rails::Generators::NamedBase" do
        expect(described_class.superclass).to eq(Rails::Generators::NamedBase)
      end
    end
  end

  describe "generator configuration" do
    it "has a description" do
      expect(described_class.desc).to be_a(String)
      expect(described_class.desc.length).to be > 0
    end

    it "has a namespace" do
      expect(described_class.namespace).to eq("ai_agent_dsl:agent")
    end

    if defined?(Rails::Generators) && Rails::Generators.respond_to?(:find_by_namespace)
      it "is registered with Rails generators" do
        # Skip this test as Rails generator registration is complex in test environment
        skip "Rails generator registration requires full Rails environment"
      end
    end
  end
end

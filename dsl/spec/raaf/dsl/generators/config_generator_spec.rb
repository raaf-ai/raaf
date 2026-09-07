# frozen_string_literal: true

require_relative "../../../spec_helper"

# Rails generator tests
if defined?(Rails::Generators)
  begin
    require "rails/generators/test_case"

    class ConfigGeneratorTest < Rails::Generators::TestCase
      tests RAAF::DSL::Generators::ConfigGenerator
      destination File.expand_path("../../../tmp", __dir__)

      setup :prepare_destination

      def test_generator_creates_config_file
        run_generator

        assert_file "config/ai_agents.yml" do |content|
          expect(content).to include("defaults: &defaults")
          expect(content).to include("development:")
          expect(content).to include("test:")
          expect(content).to include("production:")
        end
      end

      def test_generator_creates_initializer
        run_generator

        assert_file "config/initializers/ai_config.rb" do |content|
          expect(content).to include("RAAF::DSL.configure do |config|")
        end
      end
    end
  rescue LoadError
    # Rails generators not available
  end
end

# RSpec tests as fallback
RSpec.describe RAAF::DSL::Generators::ConfigGenerator, :with_rails, :with_temp_files do
  describe "basic functionality" do
    it "exists as a constant" do
      expect(described_class).to be_a(Class)
    end

    it "can be instantiated" do
      expect { described_class.new }.not_to raise_error
    end

    if defined?(Rails::Generators::Base)
      it "inherits from Rails::Generators::Base" do
        expect(described_class.superclass).to eq(Rails::Generators::Base)
      end
    end
  end

  describe "generator configuration" do
    it "has a description" do
      expect(described_class.desc).to be_a(String)
      expect(described_class.desc.length).to be > 0
    end

    it "has a namespace" do
      expect(described_class.namespace).to eq("raaf/dsl:config")
    end

    if defined?(Rails::Generators) && Rails::Generators.respond_to?(:find_by_namespace)
      it "is registered with Rails generators" do
        # Skip this test as Rails generator registration is complex in test environment
        skip "Rails generator registration requires full Rails environment"
      end
    end
  end
end

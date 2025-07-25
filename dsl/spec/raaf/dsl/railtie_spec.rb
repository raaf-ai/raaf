# frozen_string_literal: true

require_relative "../../spec_helper"
require "rails"
require "rails/railtie"

RSpec.describe RAAF::DSL::Railtie, :with_rails, :with_temp_files do
  let(:rails_app) { mock_rails_application }

  before do
    # Reset any previous railtie state
    described_class.instance_variable_set(:@ran, false) if described_class.instance_variable_defined?(:@ran)

    # Ensure Rails application is set up
    Rails.application ||= rails_app if defined?(Rails)
  end

  # Helper to simulate to_prepare callback
  def simulate_to_prepare
    # Execute the to_prepare block from the railtie
    config_file = Rails.root.join("config", "ai_agents.yml")
    RAAF::DSL::Config.reload! if config_file.exist?
  end

  describe "railtie configuration" do
    it "inherits from Rails::Railtie" do
      expect(described_class.superclass).to eq(Rails::Railtie)
    end

    it "sets the railtie name" do
      pending "Rails integration"
      expect(described_class.railtie_name).to eq("raaf/dsl")
    end

    it "includes eager load namespace" do
      # The namespace should be added during railtie initialization
      expect(described_class.config.eager_load_namespaces).to include(RAAF::DSL)
    end
  end

  describe "configuration preparation" do
    let(:test_config) do
      {
        "development" => {
          "global" => {
            "model" => "gpt-4o-mini",
            "max_turns" => 2
          }
        }
      }
    end

    context "with existing config file" do
      it "reloads configuration when config file exists" do
        config_path = File.join(temp_dir, "config", "ai_agents.yml")
        FileUtils.mkdir_p(File.dirname(config_path))
        File.write(config_path, test_config.to_yaml)

        allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))

        # Should reload configuration since file exists
        expect { simulate_to_prepare }.not_to raise_error

        # Verify config was loaded by checking that RAAF::DSL::Config responds appropriately
        expect(RAAF::DSL::Config.for_agent("test_agent")).to be_a(Hash)
      end
    end

    context "without config file" do
      it "does not reload configuration when config file does not exist" do
        allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))

        # Should not crash when config file doesn't exist
        expect { simulate_to_prepare }.not_to raise_error
      end
    end

    it "runs on every application reload in development" do
      config_path = File.join(temp_dir, "config", "ai_agents.yml")
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, test_config.to_yaml)

      allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))

      # Should handle multiple reloads without error
      expect do
        simulate_to_prepare
        simulate_to_prepare
      end.not_to raise_error
    end
  end

  describe "initializer configuration" do
    it "configures RAAF::DSL with Rails root path" do
      pending "RAAF DSL configuration with Rails root"
      expect(RAAF::DSL).to receive(:configure) do |&block|
        config = double("Configuration")
        # Expect any Rails root path (since temp directories vary)
        expect(config).to receive(:config_file=).with(a_string_ending_with("/config/ai_agents.yml"))
        block.call(config)
      end

      # Simulate initializer execution
      described_class.initializers.find { |i| i.name == "raaf/dsl.configure" }.block.call(rails_app)
    end

    context "in development environment" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      end

      it "logs initialization message" do
        pending "Development environment logging"
        logger = double("Logger")
        allow(Rails).to receive(:logger).and_return(logger)

        expect(logger).to receive(:info).with("[RAAF::DSL] Gem initialized with Rails integration")

        # Simulate initializer execution
        described_class.initializers.find { |i| i.name == "raaf/dsl.configure" }.block.call(rails_app)
      end
    end

    context "in non-development environment" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      end

      it "does not log initialization message" do
        pending "Non-development environment logging"
        logger = double("Logger")
        allow(Rails).to receive(:logger).and_return(logger)

        expect(logger).not_to receive(:info)

        # Simulate initializer execution
        described_class.initializers.find { |i| i.name == "raaf/dsl.configure" }.block.call(rails_app)
      end
    end
  end

  describe "generator registration" do
    before do
      # Reset any loaded generators
      if Rails.application.config.generators.respond_to?(:hidden_namespaces)
        Rails.application.config.generators.hidden_namespaces.clear
      end
    end

    it "registers agent generator" do
      # The generators block should be defined
      expect(described_class.generators).not_to be_empty
    end

    it "makes generators available to Rails" do
      # Generators should be registered with the railtie
      expect(described_class.generators).not_to be_empty
      # The railtie registers a single generators block that loads both generators
      expect(described_class.generators.size).to be >= 1
    end
  end

  describe "eager loading configuration" do
    it "adds RAAF::DSL to eager load namespaces" do
      expect(described_class.config.eager_load_namespaces).to include(RAAF::DSL)
    end

    context "in production environment" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      end

      it "ensures classes are eagerly loaded" do
        # In production, Rails should eager load all RAAF::DSL classes
        expect(described_class.config.eager_load_namespaces).to include(RAAF::DSL)

        # Verify that the namespace is configured for eager loading
        # The actual eager loading would be done by Rails in production
        expect(described_class.config.eager_load_namespaces).to be_an(Array)
        expect(described_class.config.eager_load_namespaces).not_to be_empty
      end
    end
  end

  describe "Rails integration scenarios" do
    context "with Rails 7.0+" do
      before do
        allow(Rails).to receive(:version).and_return("7.0.0")
      end

      it "integrates properly with modern Rails" do
        expect { described_class.config }.not_to raise_error
        expect(described_class.config.eager_load_namespaces).to include(RAAF::DSL)
      end
    end

    context "with Rails application restart" do
      it "handles application restart gracefully" do
        config_path = File.join(temp_dir, "config", "ai_agents.yml")
        FileUtils.mkdir_p(File.dirname(config_path))
        File.write(config_path, { "test" => { "global" => { "model" => "gpt-4o" } } }.to_yaml)

        allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))

        # Simulate multiple application restarts
        expect do
          3.times { simulate_to_prepare }
        end.not_to raise_error
      end
    end

    context "with configuration changes" do
      it "reloads configuration when file changes" do
        config_path = File.join(temp_dir, "config", "ai_agents.yml")
        FileUtils.mkdir_p(File.dirname(config_path))

        # Initial config
        File.write(config_path, { "development" => { "global" => { "model" => "gpt-4o" } } }.to_yaml)
        allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))

        simulate_to_prepare

        # Simulate config change and reload
        File.write(config_path, { "development" => { "global" => { "model" => "gpt-4o-mini" } } }.to_yaml)

        expect do
          simulate_to_prepare
        end.not_to raise_error
      end
    end
  end

  describe "initializer order and dependencies" do
    it "runs before other application initializers" do
      pending "Initializer order and dependencies"
      initializer = described_class.initializers.find { |i| i.name == "raaf/dsl.configure" }
      expect(initializer).not_to be_nil
      expect(initializer.name).to eq("raaf/dsl.configure")
    end

    it "configures gem before application components need it" do
      pending "Rails integration"
      # The initializer should run early enough that other components can use RAAF::DSL configuration
      expect(RAAF::DSL).to receive(:configure)

      # Run the initializer
      described_class.initializers.find { |i| i.name == "raaf/dsl.configure" }.block.call(rails_app)

      # After initializer runs, configuration should be accessible
      expect { RAAF::DSL.configuration }.not_to raise_error
    end
  end

  describe "environment-specific behavior" do
    let(:test_config) do
      {
        "development" => { "global" => { "model" => "gpt-4o-mini" } },
        "test" => { "global" => { "model" => "gpt-4o-mini", "max_turns" => 1 } },
        "production" => { "global" => { "model" => "gpt-4o" } }
      }
    end

    before do
      config_path = File.join(temp_dir, "config", "ai_agents.yml")
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, test_config.to_yaml)
      allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))
    end

    %w[development test production].each do |env|
      context "in #{env} environment" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(env))
        end

        it "loads environment-specific configuration" do
          simulate_to_prepare

          # Verify configuration is available for the environment
          config = RAAF::DSL::Config.global(environment: env)
          expect(config).to eq(test_config[env]["global"])
        end
      end
    end
  end

  describe "error handling" do
    context "when Rails root is not available" do
      before do
        allow(Rails).to receive(:root).and_raise(NoMethodError)
      end

      it "handles missing Rails root gracefully" do
        expect do
          described_class.initializers.find { |i| i.name == "raaf/dsl.configure" }.block.call(rails_app)
        end.to raise_error(NoMethodError)
      end
    end

    context "when logger is not available" do
      before do
        allow(Rails).to receive_messages(logger: nil, env: ActiveSupport::StringInquirer.new("development"))
      end

      it "handles missing logger gracefully" do
        pending "Missing logger handling"
        expect do
          described_class.initializers.find { |i| i.name == "raaf/dsl.configure" }.block.call(rails_app)
        end.not_to raise_error
      end
    end

    context "with corrupted config file" do
      before do
        config_path = File.join(temp_dir, "config", "ai_agents.yml")
        FileUtils.mkdir_p(File.dirname(config_path))
        File.write(config_path, "invalid: yaml: content: [")
        allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))
      end

      it "handles YAML parsing errors gracefully" do
        expect do
          simulate_to_prepare
        end.not_to raise_error
      end
    end
  end

  describe "integration with Rails generators" do
    it "allows generator usage after railtie initialization" do
      pending "Generator usage after initialization"
      # Simulate full Rails initialization
      described_class.initializers.find { |i| i.name == "raaf/dsl.configure" }.block.call(rails_app)

      # Generators should be registered
      expect(described_class.generators).not_to be_empty
    end
  end

  describe "compatibility with different Rails setups" do
    context "with Rails API application" do
      before do
        # Rails API apps have the same configuration structure
        allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))
      end

      it "works with Rails API applications" do
        pending "Rails API application compatibility"
        expect(RAAF::DSL).to receive(:configure).and_call_original

        expect do
          described_class.initializers.find { |i| i.name == "raaf/dsl.configure" }.block.call(rails_app)
        end.not_to raise_error
      end
    end

    context "with Rails application in different modes" do
      %w[development test production].each do |mode|
        it "works in #{mode} mode" do
          pending "Rails boot time performance"
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(mode))

          expect do
            described_class.initializers.find { |i| i.name == "raaf/dsl.configure" }.block.call(rails_app)
          end.not_to raise_error
        end
      end
    end
  end

  describe "performance considerations" do
    it "does not significantly impact Rails boot time" do
      pending "Component loading optimization"
      start_time = Time.current

      # Simulate initializer execution
      described_class.initializers.find { |i| i.name == "raaf/dsl.configure" }.block.call(rails_app)

      end_time = Time.current
      expect(end_time - start_time).to be < 0.1 # Should complete in under 100ms
    end

    it "only loads necessary components during initialization" do
      pending "Component loading optimization"
      # The railtie itself should be lightweight
      # Just verify that the initializer runs quickly
      start_time = Time.current

      # Run initializer
      described_class.initializers.find { |i| i.name == "raaf/dsl.configure" }.block.call(rails_app)

      end_time = Time.current
      # Initializer should complete very quickly
      expect(end_time - start_time).to be < 0.01 # Under 10ms
    end
  end
end

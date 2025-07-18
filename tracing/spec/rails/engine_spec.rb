# frozen_string_literal: true

require "spec_helper"

# Skip Rails-specific tests if Rails is not available
begin
  require "rails"
  require "active_record"
  require_relative "../../../../lib/raaf/tracing/engine"
  
  # Check if database connection is available
  ActiveRecord::Base.connection.migration_context.current_version
rescue LoadError, ActiveRecord::ConnectionNotDefined, ActiveRecord::NoDatabaseError => e
  puts "Skipping Rails tests: #{e.message}"
  return
end

RSpec.describe RAAF::Tracing::Engine do
  describe "engine configuration" do
    subject { described_class }

    it "isolates namespace correctly" do
      expect(subject.isolated?).to be true
    end

    it "has correct engine name" do
      expect(subject.engine_name).to eq("openai_agents_tracing")
    end

    it "configures generators correctly" do
      generators = subject.config.generators
      expect(generators.options[:test_framework]).to eq(:rspec)
      expect(generators.options[:assets]).to be true
      expect(generators.options[:helper]).to be true
    end
  end

  describe "configuration options" do
    let(:config) { RAAF::Tracing.configuration }

    it "has default configuration values" do
      expect(config.auto_configure).to be_falsy
      expect(config.mount_path).to eq("/tracing")
      expect(config.retention_days).to eq(30)
      expect(config.sampling_rate).to eq(1.0)
    end

    it "allows configuration changes" do
      RAAF::Tracing.configure do |c|
        c.auto_configure = true
        c.mount_path = "/custom-tracing"
        c.retention_days = 7
        c.sampling_rate = 0.5
      end

      expect(config.auto_configure).to be true
      expect(config.mount_path).to eq("/custom-tracing")
      expect(config.retention_days).to eq(7)
      expect(config.sampling_rate).to eq(0.5)
    end
  end

  describe "routes" do
    before(:all) do
      skip "Rails not available" unless defined?(Rails)
      begin
        require "rack/test"
      rescue LoadError
        skip "Rack::Test not available"
      end
    end

    include Rack::Test::Methods if defined?(Rack::Test)

    def app
      @app ||= Class.new(Rails::Application) do
        config.eager_load = false
        config.logger = Logger.new(File::NULL)
        
        routes.draw do
          mount RAAF::Tracing::Engine => "/tracing"
        end
      end.initialize!
    end

    it "mounts engine routes correctly" do
      # Test that basic routes are accessible
      expect { get "/tracing" }.not_to raise_error
    end

    it "includes dashboard routes" do
      routes = RAAF::Tracing::Engine.routes.routes
      route_names = routes.map(&:name).compact
      
      expect(route_names).to include("openai_agents_tracing.dashboard")
      expect(route_names).to include("openai_agents_tracing.dashboard_performance")
      expect(route_names).to include("openai_agents_tracing.dashboard_costs")
      expect(route_names).to include("openai_agents_tracing.dashboard_errors")
    end

    it "includes trace and span routes" do
      routes = RAAF::Tracing::Engine.routes.routes
      route_names = routes.map(&:name).compact
      
      expect(route_names).to include("openai_agents_tracing.traces")
      expect(route_names).to include("openai_agents_tracing.spans")
      expect(route_names).to include("openai_agents_tracing.search")
    end
  end

  describe "auto-configuration" do
    before do
      allow(Rails.application.config).to receive(:after_initialize).and_yield
      allow(OpenAIAgents).to receive(:tracer).and_return(double("tracer", add_processor: true))
    end

    context "when auto_configure is enabled" do
      before do
        allow(Rails.application.config.openai_agents_tracing).to receive(:auto_configure).and_return(true)
      end

      it "automatically adds ActiveRecord processor" do
        expect(RAAF::tracer).to receive(:add_processor).with(
          an_instance_of(RAAF::Tracing::ActiveRecordProcessor)
        )
        
        # Trigger the initializer
        described_class.initializers.find { |i| i.name == "openai_agents.tracing.configure" }.run
      end
    end

    context "when auto_configure is disabled" do
      before do
        allow(Rails.application.config.openai_agents_tracing).to receive(:auto_configure).and_return(false)
      end

      it "does not add processor automatically" do
        expect(RAAF::tracer).not_to receive(:add_processor)
        
        # Trigger the initializer
        described_class.initializers.find { |i| i.name == "openai_agents.tracing.configure" }.run
      end
    end
  end

  describe "asset precompilation" do
    it "includes tracing assets in precompile list" do
      assets_initializer = described_class.initializers.find { |i| i.name == "openai_agents.tracing.assets" }
      expect(assets_initializer).to be_present
      
      # Mock Rails app config
      app_config = double("app_config")
      assets_config = double("assets_config", precompile: [])
      allow(app_config).to receive(:assets).and_return(assets_config)
      allow(app_config).to receive(:respond_to?).with(:assets).and_return(true)
      
      expect(assets_config.precompile).to receive(:concat).with(
        %w[openai_agents/tracing/application.css openai_agents/tracing/application.js]
      )
      
      assets_initializer.run(app_config)
    end
  end

  describe "autoload paths" do
    it "includes engine-specific paths" do
      expect(described_class.config.autoload_paths).to include(
        a_string_ending_with("app/models/concerns"),
        a_string_ending_with("app/controllers/concerns"),
        a_string_ending_with("lib")
      )
    end
  end
end
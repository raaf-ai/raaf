# frozen_string_literal: true

RSpec.describe RAAF::Rails do
  describe "version" do
    it "has a version number" do
      expect(RAAF::Rails::VERSION).not_to be_nil
    end

    it "follows semantic versioning" do
      expect(RAAF::Rails::VERSION).to match(/^\d+\.\d+\.\d+/)
    end
  end

  describe "Rails engine" do
    it "defines the Rails engine" do
      expect(RAAF::Rails::Engine).to be_a(Class)
      expect(RAAF::Rails::Engine.superclass).to eq(Rails::Engine)
    end

    it "is defined within RAAF::Rails module" do
      expect(described_class.constants).to include(:Engine)
    end
  end

  describe "module structure" do
    it "is defined under RAAF namespace" do
      # Check that the module is defined as a constant
      expect(RAAF.const_defined?(:Rails)).to be true
    end

    it "defines helper modules" do
      expect(defined?(RAAF::Rails::Helpers)).to eq("constant")
      expect(defined?(RAAF::Rails::Helpers::AgentHelper)).to eq("constant")
    end

    it "has a modular structure for controllers" do
      # Controllers are loaded on demand, not by default
      expect(File.exist?(File.join(File.dirname(__FILE__), "../lib/raaf/rails/controllers"))).to be true
    end

    # The gem does not load the websocket handler: its require in raaf-rails.rb
    # is commented out because the class needs websocket-rails, which is not a
    # dependency. So the constant is absent, and the example that asserted it
    # was defined passed only when a spec that required the file by path
    # happened to run first — on its own it failed. That spec is gone, and this
    # says what is true instead. It fails if anything starts loading the file,
    # which is the change worth being told about.
    it "does not define the websocket handler, which it never loads" do
      expect(defined?(RAAF::Rails::WebsocketHandler)).to be_nil
    end
  end

  describe "constants" do
    it "defines DEFAULT_CONFIG" do
      expect(RAAF::Rails::DEFAULT_CONFIG).to be_a(Hash)
      expect(RAAF::Rails::DEFAULT_CONFIG).to be_frozen
    end

    it "has all required configuration keys" do
      required_keys = %i[
        authentication_method
        enable_dashboard
        enable_api
        enable_websockets
        enable_background_jobs
        dashboard_path
        api_path
        websocket_path
        allowed_origins
        rate_limit
        monitoring
      ]

      required_keys.each do |key|
        expect(RAAF::Rails::DEFAULT_CONFIG).to have_key(key)
      end
    end
  end

  describe "module methods" do
    it "responds to configuration methods" do
      expect(described_class).to respond_to(:configure)
      expect(described_class).to respond_to(:config)
    end

    it "responds to installation methods" do
      expect(described_class).to respond_to(:install!)
    end

    it "responds to agent management methods" do
      expect(described_class).to respond_to(:create_agent)
      expect(described_class).to respond_to(:find_agent)
      expect(described_class).to respond_to(:agents_for_user)
      expect(described_class).to respond_to(:start_conversation)
    end
  end

  describe "gem integration" do
    it "requires raaf-core" do
      expect(defined?(RAAF::Agent)).to eq("constant")
      expect(defined?(RAAF::Runner)).to eq("constant")
    end

    it "requires raaf-memory" do
      expect(defined?(RAAF::Memory)).to eq("constant")
    end

    it "requires raaf-tracing" do
      expect(defined?(RAAF::Tracing)).to eq("constant")
    end
  end
end

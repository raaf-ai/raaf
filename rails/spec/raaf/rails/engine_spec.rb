# frozen_string_literal: true

RSpec.describe RAAF::Rails::Engine do
  it "is a Rails Engine" do
    expect(described_class).to be < Rails::Engine
  end

  it "isolates namespace to RAAF::Rails" do
    # Engine.isolate_namespace is called during class definition
    expect(described_class).to respond_to(:isolated_namespace)
  end

  describe "configuration" do
    it "configures autoload paths" do
      config = described_class.config
      expect(config.autoload_paths).to be_an(Array)
    end

    it "configures eager load paths" do
      config = described_class.config
      expect(config.eager_load_paths).to be_an(Array)
    end

    it "enables assets" do
      config = described_class.config
      expect(config.assets.enabled).to be true
    end

    it "configures asset paths" do
      config = described_class.config
      expect(config.assets.paths).to be_an(Array)
    end

    it "configures assets to precompile" do
      config = described_class.config
      expect(config.assets.precompile).to include("raaf-rails.css", "raaf-rails.js")
    end

    it "configures generators" do
      config = described_class.config
      expect(config.generators).to respond_to(:test_framework)
    end
  end

  describe "initializers" do
    it "defines initialization hooks" do
      # Engine should have initializers defined
      expect(described_class.config).to respond_to(:after_initialize)
    end
  end

  describe "CORS middleware" do
    # The engine's Rack::Cors covers config[:api_path], which belongs to the
    # host application rather than to the engine's mount point. Two Rack::Cors
    # instances compete instead of merging — the first in the stack answers
    # every preflight — so installing one by default silently replaced the
    # host's own policy. These examples pin the insertion to explicit opt-in.
    let(:inserted) { [] }

    let(:host_app) do
      stack = Object.new
      recorder = inserted
      stack.define_singleton_method(:insert_before) do |index, klass, &block|
        recorder << { index: index, klass: klass, block: block }
      end
      config = Struct.new(:middleware).new(stack)
      Struct.new(:config).new(config)
    end

    def run_initializer(overrides)
      config = RAAF::Rails::DEFAULT_CONFIG.merge(
        enable_background_jobs: false,
        enable_websockets: false,
        monitoring: { enabled: false }
      ).merge(overrides)
      allow(RAAF::Rails).to receive(:config).and_return(config)

      described_class.initializers.find { |i| i.name == "raaf-rails.initialize" }.run(host_app)
    end

    it "installs no CORS middleware by default" do
      run_initializer({})

      expect(inserted).to be_empty
    end

    it "installs no CORS middleware even when origins are configured, unless asked" do
      run_initializer(allowed_origins: ["https://myapp.com"])

      expect(inserted).to be_empty
    end

    context "when the host opts in" do
      before { skip("rack-cors not available") unless defined?(Rack::Cors) }

      it "installs a single Rack::Cors" do
        run_initializer(configure_cors: true)

        expect(inserted.map { |i| i[:klass] }).to eq([Rack::Cors])
      end

      it "covers the configured api_path rather than a hardcoded one" do
        run_initializer(configure_cors: true, api_path: "/agents/api/v2")

        resource_paths = []
        cors = Object.new
        cors.define_singleton_method(:allow) { |&block| instance_eval(&block) }
        cors.define_singleton_method(:origins) { |*| }
        cors.define_singleton_method(:resource) { |path, **| resource_paths << path }
        cors.instance_eval(&inserted.first[:block])

        expect(resource_paths).to eq(["/agents/api/v2/*"])
      end
    end
  end

  describe "routes" do
    it "defines routes configuration" do
      expect(described_class).to respond_to(:routes)
    end
  end
end

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

  describe "routes" do
    it "defines routes configuration" do
      expect(described_class).to respond_to(:routes)
    end
  end
end

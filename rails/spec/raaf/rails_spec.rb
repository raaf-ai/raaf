# frozen_string_literal: true

RSpec.describe RAAF::Rails do
  # Reset configuration before each test
  before do
    described_class.instance_variable_set(:@config, nil)
  end

  describe ".configure" do
    it "yields configuration block" do
      expect do |block|
        described_class.configure(&block)
      end.to yield_with_args(Hash)
    end

    it "returns configuration hash" do
      result = described_class.configure do |config|
        config[:test_option] = true
      end
      expect(result).to be_a(Hash)
      expect(result[:test_option]).to be true
    end

    it "preserves default configuration" do
      config = described_class.configure
      expect(config[:authentication_method]).to eq(:none)
      expect(config[:enable_dashboard]).to be true
      expect(config[:enable_api]).to be true
      expect(config[:enable_websockets]).to be true
      expect(config[:enable_background_jobs]).to be true
    end

    it "allows overriding default configuration" do
      config = described_class.configure do |c|
        c[:authentication_method] = :devise
        c[:enable_dashboard] = false
      end
      expect(config[:authentication_method]).to eq(:devise)
      expect(config[:enable_dashboard]).to be false
    end
  end

  describe ".config" do
    it "returns current configuration" do
      config = described_class.config
      expect(config).to be_a(Hash)
      expect(config).to have_key(:authentication_method)
      expect(config).to have_key(:enable_dashboard)
    end

    it "returns default configuration if not configured" do
      # Reset config
      described_class.instance_variable_set(:@config, nil)
      config = described_class.config

      expect(config[:authentication_method]).to eq(:none)
      expect(config[:dashboard_path]).to eq("/dashboard")
      expect(config[:api_path]).to eq("/api/v1")
      expect(config[:websocket_path]).to eq("/chat")
    end
  end

  describe ".install!" do
    it "responds to install!" do
      expect(described_class).to respond_to(:install!)
    end
  end

  describe "agent management methods" do
    describe ".create_agent" do
      it "responds to create_agent" do
        expect(described_class).to respond_to(:create_agent)
      end
    end

    describe ".find_agent" do
      it "responds to find_agent" do
        expect(described_class).to respond_to(:find_agent)
      end
    end

    describe ".agents_for_user" do
      it "responds to agents_for_user" do
        expect(described_class).to respond_to(:agents_for_user)
      end
    end

    describe ".start_conversation" do
      it "responds to start_conversation" do
        expect(described_class).to respond_to(:start_conversation)
      end

      it "returns nil if agent not found" do
        allow(described_class).to receive(:find_agent).and_return(nil)
        result = described_class.start_conversation("invalid_id", "Hello")
        expect(result).to be_nil
      end
    end
  end

  describe "DEFAULT_CONFIG" do
    it "contains all expected configuration keys" do
      config = RAAF::Rails::DEFAULT_CONFIG

      expect(config).to have_key(:authentication_method)
      expect(config).to have_key(:enable_dashboard)
      expect(config).to have_key(:enable_api)
      expect(config).to have_key(:enable_websockets)
      expect(config).to have_key(:enable_background_jobs)
      expect(config).to have_key(:dashboard_path)
      expect(config).to have_key(:api_path)
      expect(config).to have_key(:websocket_path)
      expect(config).to have_key(:allowed_origins)
      expect(config).to have_key(:rate_limit)
      expect(config).to have_key(:monitoring)
    end

    it "has correct default values" do
      config = RAAF::Rails::DEFAULT_CONFIG

      expect(config[:authentication_method]).to eq(:none)
      expect(config[:enable_dashboard]).to be true
      expect(config[:enable_api]).to be true
      expect(config[:allowed_origins]).to eq(["*"])
      expect(config[:rate_limit][:enabled]).to be true
      expect(config[:rate_limit][:requests_per_minute]).to eq(60)
      expect(config[:monitoring][:metrics]).to eq(%i[usage performance errors])
    end

    it "is frozen to prevent modification" do
      expect(RAAF::Rails::DEFAULT_CONFIG).to be_frozen
    end
  end
end

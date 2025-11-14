# frozen_string_literal: true

require "spec_helper"
require "raaf/usage/pricing_data_manager"
require "webmock/rspec"

RSpec.describe RAAF::Usage::PricingDataManager do
  subject(:manager) { described_class.instance }

  let(:helicone_url) { "https://www.helicone.ai/api/llm-costs" }
  let(:mock_helicone_response) do
    {
      "data" => [
        {
          "model" => "gpt-4o",
          "provider" => "OPENAI",
          "input_cost_per_1m" => 2.50,
          "output_cost_per_1m" => 10.00,
          "prompt_cache_read_per_1m" => 0.25,
          "prompt_cache_write_per_1m" => 1.25
        },
        {
          "model" => "claude-3-5-sonnet-20241022",
          "provider" => "ANTHROPIC",
          "input_cost_per_1m" => 3.00,
          "output_cost_per_1m" => 15.00
        },
        {
          "model" => "gemini-2.5-flash",
          "provider" => "GOOGLE",
          "input_cost_per_1m" => 0.15,
          "output_cost_per_1m" => 0.60
        }
      ]
    }
  end

  before do
    # Reset singleton state before each test
    manager.instance_variable_set(:@data, nil)
    manager.instance_variable_set(:@last_fetch, nil)

    # Stub HTTP request by default
    stub_request(:get, helicone_url)
      .to_return(status: 200, body: mock_helicone_response.to_json, headers: { "Content-Type" => "application/json" })
  end

  after do
    WebMock.reset!
  end

  describe "#get_pricing" do
    context "when data has not been loaded" do
      it "fetches data from Helicone on first access" do
        result = manager.get_pricing("gpt-4o")

        expect(result).to eq({
                               input: 2.50,
                               output: 10.00,
                               domain: "openai.com",
                               prompt_cache_read: 0.25,
                               prompt_cache_write: 1.25
                             })

        expect(WebMock).to have_requested(:get, helicone_url).once
      end

      it "returns nil for unknown models" do
        expect(manager.get_pricing("unknown-model")).to be_nil
      end

      it "caches data after first fetch" do
        manager.get_pricing("gpt-4o")
        manager.get_pricing("claude-3-5-sonnet-20241022")

        # Should only fetch once
        expect(WebMock).to have_requested(:get, helicone_url).once
      end
    end

    context "when data is already loaded" do
      before do
        manager.get_pricing("gpt-4o") # Load data
      end

      it "returns cached pricing without fetching" do
        result = manager.get_pricing("claude-3-5-sonnet-20241022")

        expect(result).to eq({
                               input: 3.00,
                               output: 15.00,
                               domain: "anthropic.com"
                             })

        # Should still only have one request from before block
        expect(WebMock).to have_requested(:get, helicone_url).once
      end
    end

    context "when API request fails" do
      before do
        stub_request(:get, helicone_url).to_return(status: 500, body: "Internal Server Error")
      end

      it "returns nil gracefully" do
        expect(manager.get_pricing("gpt-4o")).to be_nil
      end

      it "logs error message" do
        expect(RAAF.logger).to receive(:warn).with(/Helicone API returned 500/)
        manager.get_pricing("gpt-4o")
      end
    end

    context "when API returns invalid JSON" do
      before do
        stub_request(:get, helicone_url).to_return(status: 200, body: "not json")
      end

      it "returns nil gracefully" do
        expect(manager.get_pricing("gpt-4o")).to be_nil
      end

      it "logs error message" do
        expect(RAAF.logger).to receive(:error).with(/Failed to fetch from Helicone/)
        manager.get_pricing("gpt-4o")
      end
    end
  end

  describe "#refresh!" do
    it "forces a fresh fetch from Helicone" do
      manager.get_pricing("gpt-4o") # First fetch
      expect(WebMock).to have_requested(:get, helicone_url).once

      manager.refresh! # Force refresh
      expect(WebMock).to have_requested(:get, helicone_url).twice
    end

    it "returns true on successful fetch" do
      expect(manager.refresh!).to be true
    end

    it "returns false on failed fetch" do
      stub_request(:get, helicone_url).to_return(status: 500)
      expect(manager.refresh!).to be false
    end

    it "updates last_fetch timestamp" do
      freeze_time = Time.new(2025, 1, 15, 12, 0, 0)
      allow(Time).to receive(:now).and_return(freeze_time)

      manager.refresh!

      expect(manager.instance_variable_get(:@last_fetch)).to eq(freeze_time)
    end
  end

  describe "#stale?" do
    context "when data has never been loaded" do
      it "returns true" do
        expect(manager.stale?).to be true
      end
    end

    context "when data was recently fetched" do
      before do
        manager.refresh!
      end

      it "returns false" do
        expect(manager.stale?).to be false
      end
    end

    context "when data is older than TTL" do
      before do
        manager.refresh!

        # Simulate 8 days passing (TTL is 7 days)
        future_time = Time.now + (8 * 24 * 60 * 60)
        allow(Time).to receive(:now).and_return(future_time)
      end

      it "returns true" do
        expect(manager.stale?).to be true
      end

      it "triggers refresh on next get_pricing call" do
        manager.get_pricing("gpt-4o")

        # Should have fetched twice: initial + stale refresh
        expect(WebMock).to have_requested(:get, helicone_url).twice
      end
    end
  end

  describe "#status" do
    context "before any data is loaded" do
      it "returns unloaded status" do
        status = manager.status

        expect(status[:loaded]).to be false
        expect(status[:last_fetch]).to be_nil
        expect(status[:stale]).to be true
        expect(status[:model_count]).to eq(0)
      end
    end

    context "after data is loaded" do
      before do
        manager.refresh!
      end

      it "returns loaded status" do
        status = manager.status

        expect(status[:loaded]).to be true
        expect(status[:last_fetch]).to be_a(Time)
        expect(status[:stale]).to be false
        expect(status[:model_count]).to eq(3) # 3 models in mock data
        expect(status[:ttl]).to eq(604_800) # 7 days
      end
    end
  end

  describe "domain extraction" do
    it "extracts openai.com from OPENAI provider" do
      pricing = manager.get_pricing("gpt-4o")
      expect(pricing[:domain]).to eq("openai.com")
    end

    it "extracts anthropic.com from ANTHROPIC provider" do
      pricing = manager.get_pricing("claude-3-5-sonnet-20241022")
      expect(pricing[:domain]).to eq("anthropic.com")
    end

    it "extracts google.com from GOOGLE provider" do
      pricing = manager.get_pricing("gemini-2.5-flash")
      expect(pricing[:domain]).to eq("google.com")
    end

    it "handles unknown providers gracefully" do
      stub_request(:get, helicone_url).to_return(
        status: 200,
        body: {
          "data" => [{ "model" => "test", "provider" => "UNKNOWN", "input_cost_per_1m" => 1.0, "output_cost_per_1m" => 2.0 }]
        }.to_json
      )

      manager.refresh!
      pricing = manager.get_pricing("test")
      expect(pricing[:domain]).to eq("unknown.com")
    end
  end

  describe "cache costs inclusion" do
    it "includes cache costs when present" do
      pricing = manager.get_pricing("gpt-4o")

      expect(pricing[:prompt_cache_read]).to eq(0.25)
      expect(pricing[:prompt_cache_write]).to eq(1.25)
    end

    it "excludes cache costs when absent" do
      pricing = manager.get_pricing("claude-3-5-sonnet-20241022")

      expect(pricing).not_to have_key(:prompt_cache_read)
      expect(pricing).not_to have_key(:prompt_cache_write)
    end
  end

  describe "thread safety" do
    it "handles concurrent get_pricing calls" do
      threads = 10.times.map do
        Thread.new do
          manager.get_pricing("gpt-4o")
        end
      end

      threads.each(&:join)

      # Should only fetch once despite concurrent calls
      expect(WebMock).to have_requested(:get, helicone_url).once
    end
  end

  describe "configuration" do
    let(:custom_config) { RAAF::Configuration.new }

    before do
      custom_config.set("usage.pricing_data.url", "https://custom.api/costs")
      custom_config.set("usage.pricing_data.ttl", 3600) # 1 hour

      # Inject custom config into manager
      manager.instance_variable_set(:@config, custom_config)
    end

    it "uses custom API URL from configuration" do
      stub_request(:get, "https://custom.api/costs")
        .to_return(status: 200, body: mock_helicone_response.to_json)

      manager.refresh!

      expect(WebMock).to have_requested(:get, "https://custom.api/costs")
    end

    it "uses custom TTL from configuration" do
      manager.refresh!

      # Simulate 1.5 hours passing
      future_time = Time.now + 5400 # 1.5 hours
      allow(Time).to receive(:now).and_return(future_time)

      expect(manager.stale?).to be true
    end
  end
end

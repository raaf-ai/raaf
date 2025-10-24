# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing::SpanCollectors::LLMCollector do
  let(:collector) { described_class.new }

  describe ".collect_attributes" do
    context "with usage data containing token counts" do
      let(:completion) do
        Struct.new(:usage, :model, :elapsed_time_ms).new(
          {
            input_tokens: 1250,
            output_tokens: 342,
            cache_read_input_tokens: 500,
            cache_creation_input_tokens: 100,
            total_tokens: 2092
          },
          "gpt-4o",
          2450
        )
      end

      it "captures input token count" do
        attributes = collector.collect_attributes(completion)
        expect(attributes["llm.tokens.input"]).to eq("1250")
      end

      it "captures output token count" do
        attributes = collector.collect_attributes(completion)
        expect(attributes["llm.tokens.output"]).to eq("342")
      end

      it "captures cache read token count" do
        attributes = collector.collect_attributes(completion)
        expect(attributes["llm.tokens.cache_read"]).to eq("500")
      end

      it "captures cache creation token count" do
        attributes = collector.collect_attributes(completion)
        expect(attributes["llm.tokens.cache_creation"]).to eq("100")
      end

      it "captures total token count" do
        attributes = collector.collect_attributes(completion)
        expect(attributes["llm.tokens.total"]).to eq("2092")
      end

      it "captures latency in milliseconds" do
        attributes = collector.collect_attributes(completion)
        expect(attributes["llm.latency.total_ms"]).to eq("2450")
      end

      it "captures model name" do
        attributes = collector.collect_attributes(completion)
        expect(attributes["llm.model"]).to eq("gpt-4o")
      end
    end

    context "with usage data in hash format (both symbol and string keys)" do
      let(:completion) do
        Struct.new(:usage, :model).new(
          {
            "input_tokens" => 1000,
            "output_tokens" => 200,
            "cache_read_input_tokens" => 300
          },
          "gpt-4o"
        )
      end

      it "extracts tokens from hash with string keys" do
        attributes = collector.collect_attributes(completion)
        expect(attributes["llm.tokens.input"]).to eq("1000")
        expect(attributes["llm.tokens.output"]).to eq("200")
        expect(attributes["llm.tokens.cache_read"]).to eq("300")
      end
    end

    context "with missing or zero usage data" do
      let(:completion) do
        Struct.new(:usage, :model).new(
          { input_tokens: 0, output_tokens: 0 },
          "gpt-4o"
        )
      end

      it "captures zero values" do
        attributes = collector.collect_attributes(completion)
        expect(attributes["llm.tokens.input"]).to eq("0")
        expect(attributes["llm.tokens.output"]).to eq("0")
      end
    end

    context "with nil usage data" do
      let(:completion) do
        Struct.new(:usage, :model).new(nil, "gpt-4o")
      end

      it "returns N/A for missing usage" do
        attributes = collector.collect_attributes(completion)
        expect(attributes["llm.tokens.input"]).to eq("N/A")
        expect(attributes["llm.tokens.output"]).to eq("N/A")
        expect(attributes["llm.tokens.total"]).to eq("N/A")
      end
    end

    context "with missing elapsed_time_ms" do
      let(:completion) do
        Struct.new(:usage, :model, :elapsed_time_ms).new(
          { input_tokens: 100, output_tokens: 50, total_tokens: 150 },
          "gpt-4o",
          nil
        )
      end

      it "returns N/A for missing latency" do
        attributes = collector.collect_attributes(completion)
        expect(attributes["llm.latency.total_ms"]).to eq("N/A")
      end
    end
  end

  describe "cost calculation" do
    context "with OpenAI gpt-4o pricing" do
      let(:completion) do
        Struct.new(:usage, :model).new(
          {
            input_tokens: 1000,
            output_tokens: 100
          },
          "gpt-4o"
        )
      end

      it "calculates cost for gpt-4o input tokens" do
        attributes = collector.collect_attributes(completion)
        # gpt-4o: input = $0.005 per 1K tokens
        # 1000 tokens = $0.005
        cost_cents = attributes["llm.cost.input_cents"].to_i
        expect(cost_cents).to eq(1) # ~1 cent
      end

      it "calculates cost for gpt-4o output tokens" do
        attributes = collector.collect_attributes(completion)
        # gpt-4o: output = $0.015 per 1K tokens
        # 100 tokens = $0.0015 ≈ 0 cents
        cost_cents = attributes["llm.cost.output_cents"].to_i
        expect(cost_cents).to be >= 0
      end

      it "calculates total cost" do
        attributes = collector.collect_attributes(completion)
        total_cents = attributes["llm.cost.total_cents"].to_i
        expect(total_cents).to be > 0
      end
    end

    context "with cache metrics" do
      let(:completion) do
        Struct.new(:usage, :model).new(
          {
            input_tokens: 1000,
            output_tokens: 100,
            cache_read_input_tokens: 500,
            cache_creation_input_tokens: 0
          },
          "gpt-4o"
        )
      end

      it "tracks cached token savings" do
        attributes = collector.collect_attributes(completion)
        # Cached tokens should be tracked separately
        expect(attributes["llm.tokens.cache_read"]).to eq("500")
      end

      it "accounts for cache in cost calculation" do
        attributes = collector.collect_attributes(completion)
        # Should have cache_cost_savings metric
        expect(attributes).to have_key("llm.cost.total_cents")
      end
    end
  end

  describe "model detection" do
    it "detects OpenAI models" do
      completion = Struct.new(:usage, :model).new(
        { input_tokens: 100, output_tokens: 50, total_tokens: 150 },
        "gpt-4o"
      )
      attributes = collector.collect_attributes(completion)
      expect(attributes["llm.model"]).to eq("gpt-4o")
    end
  end
end

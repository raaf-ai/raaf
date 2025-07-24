# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::ContextConfig do
  describe "#initialize" do
    let(:config) { described_class.new }

    it "sets default values" do
      expect(config.enabled).to be true
      expect(config.strategy).to eq(:token_sliding_window)
      expect(config.max_tokens).to be_nil
      expect(config.max_messages).to eq(50)
      expect(config.preserve_system).to be true
      expect(config.preserve_recent).to eq(5)
      expect(config.summarization_enabled).to be false
      expect(config.summarization_threshold).to eq(0.8)
      expect(config.summarization_model).to eq("gpt-3.5-turbo")
    end

    it "allows attribute modification" do
      config.max_tokens = 10_000
      config.preserve_recent = 3

      expect(config.max_tokens).to eq(10_000)
      expect(config.preserve_recent).to eq(3)
    end
  end

  describe ".conservative" do
    it "creates conservative configuration for gpt-4o" do
      config = described_class.conservative(model: "gpt-4o")

      expect(config.strategy).to eq(:token_sliding_window)
      expect(config.max_tokens).to eq(50_000)
      expect(config.preserve_recent).to eq(3)
    end

    it "creates conservative configuration for gpt-4-turbo" do
      config = described_class.conservative(model: "gpt-4-turbo")

      expect(config.max_tokens).to eq(50_000)
    end

    it "creates conservative configuration for gpt-3.5" do
      config = described_class.conservative(model: "gpt-3.5-turbo")

      expect(config.max_tokens).to eq(2_000)
    end

    it "creates conservative configuration for unknown model" do
      config = described_class.conservative(model: "unknown-model")

      expect(config.max_tokens).to eq(4_000)
    end

    it "uses default model when none provided" do
      config = described_class.conservative

      expect(config.max_tokens).to eq(50_000)
    end
  end

  describe ".balanced" do
    it "creates balanced configuration" do
      config = described_class.balanced(model: "gpt-4o")

      expect(config.strategy).to eq(:token_sliding_window)
      expect(config.max_tokens).to be_nil # Uses model defaults
      expect(config.preserve_recent).to eq(5)
    end

    it "uses default model when none provided" do
      config = described_class.balanced

      expect(config.strategy).to eq(:token_sliding_window)
      expect(config.preserve_recent).to eq(5)
    end
  end

  describe ".aggressive" do
    it "creates aggressive configuration for gpt-4o" do
      config = described_class.aggressive(model: "gpt-4o")

      expect(config.strategy).to eq(:token_sliding_window)
      expect(config.max_tokens).to eq(120_000)
      expect(config.preserve_recent).to eq(10)
    end

    it "creates aggressive configuration for gpt-4-turbo" do
      config = described_class.aggressive(model: "gpt-4-turbo")

      expect(config.max_tokens).to eq(120_000)
    end

    it "creates aggressive configuration for gpt-3.5-turbo-16k" do
      config = described_class.aggressive(model: "gpt-3.5-turbo-16k")

      expect(config.max_tokens).to eq(15_000)
    end

    it "creates aggressive configuration for gpt-3.5" do
      config = described_class.aggressive(model: "gpt-3.5-turbo")

      expect(config.max_tokens).to eq(3_500)
    end

    it "creates aggressive configuration for unknown model" do
      config = described_class.aggressive(model: "unknown-model")

      expect(config.max_tokens).to eq(7_500)
    end

    it "uses default model when none provided" do
      config = described_class.aggressive

      expect(config.max_tokens).to eq(120_000)
    end
  end

  describe ".message_based" do
    it "creates message-based configuration with default max_messages" do
      config = described_class.message_based

      expect(config.strategy).to eq(:message_count)
      expect(config.max_messages).to eq(30)
      expect(config.preserve_recent).to eq(5)
    end

    it "creates message-based configuration with custom max_messages" do
      config = described_class.message_based(max_messages: 20)

      expect(config.strategy).to eq(:message_count)
      expect(config.max_messages).to eq(20)
      expect(config.preserve_recent).to eq(5)
    end
  end

  describe ".with_summarization" do
    it "creates summarization-enabled configuration" do
      config = described_class.with_summarization(model: "gpt-4o")

      expect(config.strategy).to eq(:summarization)
      expect(config.summarization_enabled).to be true
      expect(config.summarization_threshold).to eq(0.7)
      expect(config.preserve_recent).to eq(5)
    end

    it "uses default model when none provided" do
      config = described_class.with_summarization

      expect(config.strategy).to eq(:summarization)
      expect(config.summarization_enabled).to be true
    end
  end

  describe ".disabled" do
    it "creates disabled configuration" do
      config = described_class.disabled

      expect(config.enabled).to be false
    end
  end

  describe "#build_context_manager" do
    context "when enabled" do
      it "builds context manager for token_sliding_window strategy" do
        config = described_class.new
        config.strategy = :token_sliding_window

        manager = config.build_context_manager(model: "gpt-4o")

        expect(manager).to be_a(RAAF::ContextManager)
      end

      it "builds context manager for message_count strategy" do
        config = described_class.new
        config.strategy = :message_count

        manager = config.build_context_manager(model: "gpt-4o")

        expect(manager).to be_a(RAAF::ContextManager)
      end

      it "builds context manager for summarization strategy" do
        config = described_class.new
        config.strategy = :summarization

        manager = config.build_context_manager(model: "gpt-4o")

        expect(manager).to be_a(RAAF::ContextManager)
      end

      it "passes configuration to context manager" do
        config = described_class.new
        config.max_tokens = 10_000
        config.preserve_system = false
        config.preserve_recent = 8

        expect(RAAF::ContextManager).to receive(:new).with(
          model: "gpt-4o",
          max_tokens: 10_000,
          preserve_system: false,
          preserve_recent: 8
        )

        config.build_context_manager(model: "gpt-4o")
      end

      it "uses default max_tokens for summarization strategy" do
        config = described_class.new
        config.strategy = :summarization
        config.max_tokens = nil

        expect(RAAF::ContextManager).to receive(:new).with(
          model: "gpt-4o",
          max_tokens: 10_000,
          preserve_system: true,
          preserve_recent: 5
        )

        config.build_context_manager(model: "gpt-4o")
      end

      it "raises error for unknown strategy" do
        config = described_class.new
        config.strategy = :unknown_strategy

        expect do
          config.build_context_manager(model: "gpt-4o")
        end.to raise_error(ArgumentError, "Unknown context strategy: unknown_strategy")
      end
    end

    context "when disabled" do
      it "returns nil" do
        config = described_class.disabled

        manager = config.build_context_manager(model: "gpt-4o")

        expect(manager).to be_nil
      end
    end

    it "works without model parameter" do
      config = described_class.new

      manager = config.build_context_manager

      expect(manager).to be_a(RAAF::ContextManager)
    end
  end

  describe "attribute accessors" do
    let(:config) { described_class.new }

    it "allows setting and getting enabled" do
      config.enabled = false
      expect(config.enabled).to be false
    end

    it "allows setting and getting strategy" do
      config.strategy = :message_count
      expect(config.strategy).to eq(:message_count)
    end

    it "allows setting and getting max_tokens" do
      config.max_tokens = 50_000
      expect(config.max_tokens).to eq(50_000)
    end

    it "allows setting and getting max_messages" do
      config.max_messages = 100
      expect(config.max_messages).to eq(100)
    end

    it "allows setting and getting preserve_system" do
      config.preserve_system = false
      expect(config.preserve_system).to be false
    end

    it "allows setting and getting preserve_recent" do
      config.preserve_recent = 10
      expect(config.preserve_recent).to eq(10)
    end

    it "allows setting and getting summarization_enabled" do
      config.summarization_enabled = true
      expect(config.summarization_enabled).to be true
    end

    it "allows setting and getting summarization_threshold" do
      config.summarization_threshold = 0.9
      expect(config.summarization_threshold).to eq(0.9)
    end

    it "allows setting and getting summarization_model" do
      config.summarization_model = "gpt-4o-mini"
      expect(config.summarization_model).to eq("gpt-4o-mini")
    end
  end
end

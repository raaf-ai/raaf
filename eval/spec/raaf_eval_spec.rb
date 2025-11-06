# frozen_string_literal: true

RSpec.describe RAAF::Eval do
  describe "module structure" do
    it "has a version number" do
      expect(RAAF::Eval::VERSION).not_to be_nil
      expect(RAAF::Eval::VERSION).to match(/\d+\.\d+\.\d+/)
    end

    it "has EVAL_VERSION constant" do
      expect(RAAF::Eval::EVAL_VERSION).to eq(RAAF::Eval::VERSION)
    end
  end

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(RAAF::Eval.configuration).to be_a(RAAF::Eval::Configuration)
    end

    it "returns the same instance on multiple calls" do
      expect(RAAF::Eval.configuration).to eq(RAAF::Eval.configuration)
    end
  end

  describe ".configure" do
    it "yields the configuration instance" do
      expect { |b| RAAF::Eval.configure(&b) }.to yield_with_args(RAAF::Eval.configuration)
    end

    it "allows setting configuration options" do
      RAAF::Eval.configure do |config|
        config.ai_comparator_model = "test-model"
      end

      expect(RAAF::Eval.configuration.ai_comparator_model).to eq("test-model")
    end
  end

  describe ".logger" do
    it "returns the configured logger" do
      expect(RAAF::Eval.logger).to be_a(Logger)
    end
  end
end

# frozen_string_literal: true

RSpec.describe RAAF::Eval::Continuous::EvaluatorDiscovery do
  # Mock evaluator class for testing
  let(:test_evaluator_class) do
    Class.new do
      include RAAF::Eval::DSL::Evaluator

      def self.evaluator_type
        "rule_based"
      end

      def self.description
        "A test evaluator for testing"
      end

      def self.configurable_options
        [
          { name: :threshold, type: :float, default: 0.8, description: "Score threshold" },
          { name: :max_tokens, type: :integer, default: 4000, description: "Maximum tokens" }
        ]
      end

      def initialize(options = {})
        @options = options
      end

      def evaluate(field_context, **options)
        { label: "good", score: 0.9, message: "Test passed" }
      end
    end
  end

  before do
    # Clear registry and register test evaluator
    allow(RAAF::Eval::DSL::EvaluatorRegistry.instance).to receive(:all_names).and_return([:test_evaluator, :token_limit])
    allow(RAAF::Eval::DSL::EvaluatorRegistry.instance).to receive(:get).with(:test_evaluator).and_return(test_evaluator_class)
    allow(RAAF::Eval::DSL::EvaluatorRegistry.instance).to receive(:get).with(:token_limit).and_return(test_evaluator_class)
  end

  describe ".available_evaluators" do
    it "returns all registered evaluator names from the DSL registry" do
      names = described_class.available_evaluators
      expect(names).to include(:test_evaluator)
      expect(names).to include(:token_limit)
    end
  end

  describe ".evaluator_details" do
    it "returns detailed information about each evaluator" do
      details = described_class.evaluator_details
      expect(details).to be_an(Array)
      expect(details.first).to include(:name, :type, :description, :configurable_options)
    end

    it "includes evaluator name as string" do
      details = described_class.evaluator_details
      names = details.map { |d| d[:name] }
      expect(names).to include("test_evaluator")
    end

    it "determines evaluator type correctly" do
      details = described_class.evaluator_details
      test_detail = details.find { |d| d[:name] == "test_evaluator" }
      expect(test_detail[:type]).to eq("rule_based")
    end

    it "includes description when available" do
      details = described_class.evaluator_details
      test_detail = details.find { |d| d[:name] == "test_evaluator" }
      expect(test_detail[:description]).to eq("A test evaluator for testing")
    end

    it "includes configurable options when available" do
      details = described_class.evaluator_details
      test_detail = details.find { |d| d[:name] == "test_evaluator" }
      expect(test_detail[:configurable_options]).to be_an(Array)
      expect(test_detail[:configurable_options].first[:name]).to eq(:threshold)
    end
  end

  describe ".build" do
    let(:config) { { "name" => "test_evaluator", "config" => { "threshold" => 0.9 } } }

    it "builds an evaluator instance from policy configuration" do
      evaluator = described_class.build(config)
      expect(evaluator).to be_a(test_evaluator_class)
    end

    it "passes config options to the evaluator" do
      evaluator = described_class.build(config)
      expect(evaluator.instance_variable_get(:@options)).to eq({ "threshold" => 0.9 })
    end

    it "works with symbol keys" do
      symbol_config = { name: :test_evaluator, config: { threshold: 0.9 } }
      evaluator = described_class.build(symbol_config)
      expect(evaluator).to be_a(test_evaluator_class)
    end

    it "handles missing config gracefully" do
      minimal_config = { "name" => "test_evaluator" }
      evaluator = described_class.build(minimal_config)
      expect(evaluator).to be_a(test_evaluator_class)
    end

    it "raises error for unknown evaluator" do
      allow(RAAF::Eval::DSL::EvaluatorRegistry.instance).to receive(:get).with(:unknown).and_raise(
        RAAF::Eval::DSL::EvaluatorRegistry::UnregisteredEvaluatorError, "unknown"
      )

      unknown_config = { "name" => "unknown" }
      expect { described_class.build(unknown_config) }
        .to raise_error(RAAF::Eval::Continuous::UnknownEvaluatorError)
    end
  end

  describe ".determine_evaluator_type" do
    context "when evaluator responds to evaluator_type" do
      it "uses the evaluator_type method" do
        type = described_class.send(:determine_evaluator_type, test_evaluator_class)
        expect(type).to eq("rule_based")
      end
    end

    context "when evaluator has LlmJudge in name" do
      let(:llm_class) do
        Class.new do
          def self.name
            "RAAF::Eval::Evaluators::LlmJudge::QualityScore"
          end
        end
      end

      it "returns llm_judge type" do
        allow(llm_class).to receive(:respond_to?).with(:evaluator_type).and_return(false)
        type = described_class.send(:determine_evaluator_type, llm_class)
        expect(type).to eq("llm_judge")
      end
    end

    context "when evaluator has Statistical in name" do
      let(:statistical_class) do
        Class.new do
          def self.name
            "RAAF::Eval::Evaluators::Statistical::Consistency"
          end
        end
      end

      it "returns statistical type" do
        allow(statistical_class).to receive(:respond_to?).with(:evaluator_type).and_return(false)
        type = described_class.send(:determine_evaluator_type, statistical_class)
        expect(type).to eq("statistical")
      end
    end

    context "when cannot determine type" do
      let(:unknown_class) do
        Class.new do
          def self.name
            "SomeCustomEvaluator"
          end
        end
      end

      it "defaults to rule_based" do
        allow(unknown_class).to receive(:respond_to?).with(:evaluator_type).and_return(false)
        type = described_class.send(:determine_evaluator_type, unknown_class)
        expect(type).to eq("rule_based")
      end
    end
  end

  describe ".grouped_by_type" do
    it "groups evaluators by their type" do
      grouped = described_class.grouped_by_type
      expect(grouped).to be_a(Hash)
      expect(grouped.keys).to include("rule_based")
    end

    it "returns arrays of evaluator details under each type" do
      grouped = described_class.grouped_by_type
      expect(grouped["rule_based"]).to be_an(Array)
      expect(grouped["rule_based"].first).to include(:name)
    end
  end

  describe ".search" do
    it "finds evaluators matching search term" do
      results = described_class.search("test")
      expect(results.map { |r| r[:name] }).to include("test_evaluator")
    end

    it "is case insensitive" do
      results = described_class.search("TEST")
      expect(results.map { |r| r[:name] }).to include("test_evaluator")
    end

    it "searches in description" do
      results = described_class.search("testing")
      expect(results.map { |r| r[:name] }).to include("test_evaluator")
    end

    it "returns empty array for no matches" do
      results = described_class.search("nonexistent")
      expect(results).to eq([])
    end
  end
end

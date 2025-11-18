# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/eval/red_team"

RSpec.describe "Red-Team Infrastructure" do
  describe "Module Structure" do
    it "defines the RedTeam module" do
      expect(RAAF::Eval::RedTeam).to be_a(Module)
    end

    it "defines the RedTeamer class" do
      expect(RAAF::Eval::RedTeam::RedTeamer).to be_a(Class)
    end

    it "defines the Vulnerability class" do
      expect(RAAF::Eval::RedTeam::Vulnerability).to be_a(Class)
    end

    it "defines the Attack class" do
      expect(RAAF::Eval::RedTeam::Attack).to be_a(Class)
    end

    it "defines the RTTestCase class" do
      expect(RAAF::Eval::RedTeam::RTTestCase).to be_a(Class)
    end

    it "defines the RiskAssessment class" do
      expect(RAAF::Eval::RedTeam::RiskAssessment).to be_a(Class)
    end
  end

  describe RAAF::Eval::RedTeam::Vulnerability do
    let(:vulnerability_class) do
      Class.new(RAAF::Eval::RedTeam::Vulnerability) do
        def vulnerability_type
          "test_vulnerability"
        end

        def category
          "responsible_ai"
        end

        def assess(input, output, context = {})
          {
            score: 1.0,
            reasoning: "Test assessment",
            vulnerable: false
          }
        end
      end
    end

    let(:vulnerability) { vulnerability_class.new }

    it "can be instantiated" do
      expect(vulnerability).to be_a(RAAF::Eval::RedTeam::Vulnerability)
    end

    it "has vulnerability_type method" do
      expect(vulnerability).to respond_to(:vulnerability_type)
      expect(vulnerability.vulnerability_type).to eq("test_vulnerability")
    end

    it "has category method" do
      expect(vulnerability).to respond_to(:category)
      expect(vulnerability.category).to eq("responsible_ai")
    end

    it "has assess method" do
      expect(vulnerability).to respond_to(:assess)
      result = vulnerability.assess("input", "output")
      expect(result).to include(:score, :reasoning, :vulnerable)
    end

    it "has default_sub_types method" do
      expect(vulnerability).to respond_to(:default_sub_types)
      expect(vulnerability.default_sub_types).to be_an(Array)
    end

    it "has description method" do
      expect(vulnerability).to respond_to(:description)
      expect(vulnerability.description).to be_a(String)
    end

    it "has severity method" do
      expect(vulnerability).to respond_to(:severity)
      expect(vulnerability.severity).to be_a(Symbol)
    end

    it "accepts sub_types and weight parameters" do
      vuln = vulnerability_class.new(sub_types: ["type1"], weight: 0.5)
      expect(vuln.sub_types).to eq(["type1"])
      expect(vuln.weight).to eq(0.5)
    end
  end

  describe RAAF::Eval::RedTeam::Attack do
    let(:attack_class) do
      Class.new(RAAF::Eval::RedTeam::Attack) do
        def attack_type
          :single_turn
        end

        def attack_name
          "test_attack"
        end

        def execute(baseline_input, context = {})
          "attacked: #{baseline_input}"
        end
      end
    end

    let(:attack) { attack_class.new }

    it "can be instantiated" do
      expect(attack).to be_a(RAAF::Eval::RedTeam::Attack)
    end

    it "has attack_type method" do
      expect(attack).to respond_to(:attack_type)
      expect(attack.attack_type).to eq(:single_turn)
    end

    it "has attack_name method" do
      expect(attack).to respond_to(:attack_name)
      expect(attack.attack_name).to eq("test_attack")
    end

    it "has execute method for single-turn attacks" do
      expect(attack).to respond_to(:execute)
      result = attack.execute("test input")
      expect(result).to eq("attacked: test input")
    end

    it "has single_turn? predicate" do
      expect(attack.single_turn?).to be true
    end

    it "has multi_turn? predicate" do
      expect(attack.multi_turn?).to be false
    end

    it "accepts weight and config parameters" do
      attack_instance = attack_class.new(weight: 0.8, custom_option: true)
      expect(attack_instance.weight).to eq(0.8)
      expect(attack_instance.config).to include(custom_option: true)
    end
  end

  describe RAAF::Eval::RedTeam::RTTestCase do
    let(:vulnerability) do
      instance_double(
        RAAF::Eval::RedTeam::Vulnerability,
        vulnerability_type: "bias",
        category: "responsible_ai"
      )
    end

    let(:attack) do
      instance_double(
        RAAF::Eval::RedTeam::Attack,
        attack_name: "prompt_injection"
      )
    end

    let(:test_case) do
      RAAF::Eval::RedTeam::RTTestCase.new(
        vulnerability: vulnerability,
        attack: attack,
        input: "test input",
        output: "test output",
        score: 1.0,
        reasoning: "Test passed",
        status: "passed",
        vulnerable: false
      )
    end

    it "can be instantiated" do
      expect(test_case).to be_a(RAAF::Eval::RedTeam::RTTestCase)
    end

    it "stores vulnerability and attack" do
      expect(test_case.vulnerability).to eq(vulnerability)
      expect(test_case.attack).to eq(attack)
    end

    it "stores input, output, and assessment" do
      expect(test_case.input).to eq("test input")
      expect(test_case.output).to eq("test output")
      expect(test_case.score).to eq(1.0)
      expect(test_case.reasoning).to eq("Test passed")
      expect(test_case.status).to eq("passed")
      expect(test_case.vulnerable).to be false
    end

    it "has passed? predicate" do
      expect(test_case.passed?).to be true
    end

    it "has failed? predicate" do
      expect(test_case.failed?).to be false
    end

    it "has vulnerability_type accessor" do
      expect(test_case.vulnerability_type).to eq("bias")
    end

    it "has attack_name accessor" do
      expect(test_case.attack_name).to eq("prompt_injection")
    end

    it "has to_h method" do
      hash = test_case.to_h
      expect(hash).to include(
        vulnerability_type: "bias",
        attack_name: "prompt_injection",
        score: 1.0
      )
    end

    it "has to_row method for DataFrame export" do
      row = test_case.to_row
      expect(row).to include(
        vulnerability_type: "bias",
        attack_name: "prompt_injection",
        score: 1.0,
        status: "passed"
      )
    end
  end

  describe RAAF::Eval::RedTeam::RiskAssessment do
    let(:vulnerability) do
      instance_double(
        RAAF::Eval::RedTeam::Vulnerability,
        vulnerability_type: "bias",
        category: "responsible_ai"
      )
    end

    let(:attack) do
      instance_double(
        RAAF::Eval::RedTeam::Attack,
        attack_name: "prompt_injection"
      )
    end

    let(:test_cases) do
      [
        RAAF::Eval::RedTeam::RTTestCase.new(
          vulnerability: vulnerability,
          attack: attack,
          input: "test1",
          output: "output1",
          score: 1.0,
          reasoning: "Passed",
          status: "passed",
          vulnerable: false
        ),
        RAAF::Eval::RedTeam::RTTestCase.new(
          vulnerability: vulnerability,
          attack: attack,
          input: "test2",
          output: "output2",
          score: 0.0,
          reasoning: "Failed",
          status: "failed",
          vulnerable: true
        )
      ]
    end

    let(:assessment) { RAAF::Eval::RedTeam::RiskAssessment.new(test_cases: test_cases) }

    it "can be instantiated" do
      expect(assessment).to be_a(RAAF::Eval::RedTeam::RiskAssessment)
    end

    it "has overview with aggregate statistics" do
      expect(assessment.overview).to be_a(RAAF::Eval::RedTeam::RedTeamingOverview)
      expect(assessment.overview.total_tests).to eq(2)
      expect(assessment.overview.passed_count).to eq(1)
      expect(assessment.overview.failed_count).to eq(1)
      expect(assessment.overview.pass_rate).to eq(0.5)
    end

    it "has vulnerability_results grouped by type" do
      results = assessment.vulnerability_results
      expect(results).to have_key("bias")
      expect(results["bias"][:total]).to eq(2)
      expect(results["bias"][:passed]).to eq(1)
      expect(results["bias"][:failed]).to eq(1)
    end

    it "has attack_results grouped by method" do
      results = assessment.attack_results
      expect(results).to have_key("prompt_injection")
      expect(results["prompt_injection"][:total]).to eq(2)
    end

    it "calculates risk_score" do
      expect(assessment.risk_score).to eq(0.5)
    end

    it "determines risk_level" do
      expect(assessment.risk_level).to be_a(Symbol)
      expect(%i[critical high medium low]).to include(assessment.risk_level)
    end

    it "has to_df method" do
      df = assessment.to_df
      expect(df).to be_an(Array)
      expect(df.length).to eq(2)
    end

    it "has summary method" do
      summary = assessment.summary
      expect(summary).to include(
        total_tests: 2,
        passed: 1,
        failed: 1,
        risk_score: 0.5
      )
    end
  end

  describe RAAF::Eval::RedTeam::RedTeamer do
    let(:model_callback) { ->(input) { "response to: #{input}" } }
    let(:red_teamer) { RAAF::Eval::RedTeam::RedTeamer.new(model_callback: model_callback) }

    it "can be instantiated with model_callback" do
      expect(red_teamer).to be_a(RAAF::Eval::RedTeam::RedTeamer)
    end

    it "stores model_callback" do
      expect(red_teamer.model_callback).to eq(model_callback)
    end

    it "has attack_cache" do
      expect(red_teamer.attack_cache).to be_a(Hash)
    end

    it "raises error for invalid callback" do
      expect {
        RAAF::Eval::RedTeam::RedTeamer.new(model_callback: "not a proc")
      }.to raise_error(ArgumentError, /must be callable/)
    end

    it "accepts configuration options" do
      teamer = RAAF::Eval::RedTeam::RedTeamer.new(
        model_callback: model_callback,
        async_mode: false,
        max_concurrent: 5,
        target_purpose: "Test system"
      )
      expect(teamer).to be_a(RAAF::Eval::RedTeam::RedTeamer)
    end

    it "has clear_cache! method" do
      expect(red_teamer).to respond_to(:clear_cache!)
      red_teamer.clear_cache!
      expect(red_teamer.attack_cache).to be_empty
    end
  end
end

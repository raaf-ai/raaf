# frozen_string_literal: true

require_relative 'matchers/vulnerability_matchers'
require_relative 'matchers/attack_matchers'
require_relative 'matchers/assessment_matchers'

module RAAF
  module Eval
    module RedTeam
      # RSpec matchers for red-teaming tests
      #
      # This module provides comprehensive RSpec matchers for testing
      # vulnerabilities, attacks, and red-team assessments.
      #
      # ## Usage
      #
      # Include these matchers in your RSpec configuration:
      #
      # ```ruby
      # # spec/spec_helper.rb or spec/rails_helper.rb
      # require 'raaf/eval/red_team/matchers'
      #
      # RSpec.configure do |config|
      #   config.include RAAF::Eval::RedTeam::Matchers
      # end
      # ```
      #
      # Or include them in specific test files:
      #
      # ```ruby
      # require 'raaf/eval/red_team/matchers'
      #
      # RSpec.describe MyAgent do
      #   include RAAF::Eval::RedTeam::Matchers
      #
      #   it "produces safe output" do
      #     output = agent.generate("test input")
      #     expect(output).not_to be_vulnerable_to(:bias)
      #     expect(output).not_to be_vulnerable_to(:toxicity)
      #   end
      # end
      # ```
      #
      # ## Available Matchers
      #
      # ### Vulnerability Matchers
      #
      # Test for specific vulnerabilities in LLM outputs:
      #
      # - `be_vulnerable_to(type, threshold: nil)` - Test if output contains vulnerability
      # - `be_vulnerable_to_any(types)` - Test if output contains any vulnerability
      # - `be_vulnerable_to_all(types)` - Test if output contains all vulnerabilities
      # - `have_vulnerability_score(type).of(score)` - Test exact vulnerability score
      # - `have_vulnerability_score(type).above(min)` - Test score above threshold
      # - `have_vulnerability_score(type).below(max)` - Test score below threshold
      #
      # @example Vulnerability testing
      #   expect(output).to be_vulnerable_to(:bias)
      #   expect(output).not_to be_vulnerable_to(:toxicity, threshold: 0.7)
      #   expect(output).to be_vulnerable_to_any([:bias, :toxicity])
      #   expect(output).to have_vulnerability_score(:pii_leakage).above(0.5)
      #
      # ### Attack Matchers
      #
      # Test attack effectiveness and behavior:
      #
      # - `have_breach_rate_above(threshold)` - Test attack breach rate
      # - `have_breach_rate_below(threshold)` - Test attack breach rate upper limit
      # - `successfully_breach_model` - Test if attack succeeded
      # - `escalate_monotonically` - Test multi-turn escalation pattern
      # - `have_escalation_range(range)` - Test escalation coverage
      # - `increase_emotional_intensity` - Test crescendo emotional progression
      # - `use_manipulation_types(types)` - Test crescendo manipulation tactics
      # - `be_deterministic` - Test if attack is deterministic
      # - `require_llm` - Test if attack requires LLM
      #
      # @example Attack testing
      #   attack = CrescendoAttack.new
      #   expect(attack).to have_breach_rate_above(0.4)
      #   expect(attack).to require_llm
      #
      #   result = attack.execute_conversation(input, model_callback)
      #   expect(result).to escalate_monotonically
      #   expect(result).to increase_emotional_intensity
      #
      # ### Assessment Matchers
      #
      # Test overall red-team scan results:
      #
      # - `have_acceptable_risk_level` - Test if risk is acceptable
      # - `have_risk_level(level)` - Test specific risk level
      # - `have_vulnerabilities_below(count)` - Test vulnerability count
      # - `have_no_critical_vulnerabilities` - Test for critical issues
      # - `pass_category(category)` - Test category has no vulnerabilities
      # - `fail_category(category)` - Test category has vulnerabilities
      # - `pass_all_categories` - Test all categories pass
      # - `have_scan_coverage_above(threshold)` - Test scan completeness
      # - `complete_successfully` - Test scan completed without errors
      # - `have_mitigation_recommendations` - Test recommendations present
      #
      # @example Assessment testing
      #   assessment = run_red_team_scan(model)
      #   expect(assessment).to have_acceptable_risk_level
      #   expect(assessment).to have_no_critical_vulnerabilities
      #   expect(assessment).to pass_category(:responsible_ai)
      #   expect(assessment).to have_scan_coverage_above(0.8)
      #
      # ## Supported Vulnerability Types
      #
      # - `:bias` - Bias and fairness issues (Responsible AI)
      # - `:toxicity` - Toxic or harmful content (Responsible AI)
      # - `:pii_leakage` - PII disclosure (Data Privacy)
      #
      # ## Complete Testing Example
      #
      # ```ruby
      # require 'raaf/eval/red_team/matchers'
      #
      # RSpec.describe "MyModel Red Team Testing" do
      #   include RAAF::Eval::RedTeam::Matchers
      #
      #   let(:model) { MyModel.new }
      #
      #   describe "vulnerability testing" do
      #     it "produces unbiased output" do
      #       output = model.generate("Describe engineers")
      #       expect(output).not_to be_vulnerable_to(:bias)
      #     end
      #
      #     it "avoids toxic content" do
      #       output = model.generate("offensive topic")
      #       expect(output).not_to be_vulnerable_to(:toxicity, threshold: 0.7)
      #     end
      #
      #     it "protects PII" do
      #       output = model.generate("user data request")
      #       expect(output).not_to be_vulnerable_to(:pii_leakage)
      #     end
      #   end
      #
      #   describe "attack resistance" do
      #     it "resists prompt injection" do
      #       attack = PromptInjectionAttack.new
      #       adversarial = attack.execute("harmful request")
      #       output = model.generate(adversarial)
      #
      #       expect(output).not_to be_vulnerable_to_any([:bias, :toxicity])
      #     end
      #
      #     it "resists crescendo manipulation" do
      #       attack = CrescendoAttack.new
      #       model_callback = ->(input) { model.generate(input) }
      #
      #       result = attack.execute_conversation("harmful request", model_callback)
      #       expect(result).not_to successfully_breach_model
      #     end
      #   end
      #
      #   describe "comprehensive assessment" do
      #     it "passes red-team scan" do
      #       assessment = run_red_team_scan(model)
      #
      #       expect(assessment).to complete_successfully
      #       expect(assessment).to have_acceptable_risk_level
      #       expect(assessment).to have_no_critical_vulnerabilities
      #       expect(assessment).to pass_all_categories
      #     end
      #   end
      # end
      # ```
      module Matchers
        # Helper method to run red-team scan
        #
        # @param model [Object] Model to test
        # @param options [Hash] Scan options
        # @return [Hash] Assessment results
        def run_red_team_scan(model, options = {})
          # Placeholder for actual red-team scan implementation
          # This would coordinate running vulnerabilities and attacks
          {
            success: true,
            risk_level: :low,
            vulnerabilities: [],
            coverage: 1.0,
            recommendations: []
          }
        end
      end
    end
  end
end

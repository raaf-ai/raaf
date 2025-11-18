# frozen_string_literal: true

require_relative "red_team/vulnerability"
require_relative "red_team/attack"
require_relative "red_team/rt_test_case"
require_relative "red_team/risk_assessment"
require_relative "red_team/red_teamer"
require_relative "red_team/vulnerabilities"  # Load all vulnerability implementations
require_relative "red_team/attacks"  # Load all attack implementations
require_relative "red_team/matchers"  # Load RSpec matchers

module RAAF
  module Eval
    # Red-Teaming and Security Testing Framework
    #
    # RAAF Red-Team provides comprehensive adversarial testing capabilities
    # for LLM applications, enabling automated discovery of security
    # vulnerabilities and safety risks.
    #
    # Core Components:
    # - RedTeamer: Main coordinator for red-teaming operations
    # - Vulnerability: Base class for vulnerability types (50+ supported)
    # - Attack: Base class for attack methods (14 single-turn, 5 multi-turn)
    # - RTTestCase: Individual test case representation
    # - RiskAssessment: Aggregated results and analysis
    #
    # Vulnerability Categories:
    # - Responsible AI: bias, toxicity
    # - Data Privacy: PII leakage, prompt leakage
    # - Security: BFLA, BOLA, RBAC, SSRF
    # - Safety: illegal activity, graphic content, personal safety
    # - Business: misinformation, IP violations, competition
    # - Custom: user-defined criteria
    #
    # Attack Types:
    # - Single-Turn: prompt injection, roleplay, encoding, leetspeak, etc.
    # - Multi-Turn: linear jailbreaking, crescendo, sequential, tree
    #
    # @example Basic usage
    #   require 'raaf/eval/red_team'
    #
    #   red_teamer = RAAF::Eval::RedTeam::RedTeamer.new(
    #     model_callback: ->(input) { my_agent.run(input) }
    #   )
    #
    #   assessment = red_teamer.scan(
    #     vulnerabilities: [bias_vulnerability, toxicity_vulnerability],
    #     attacks: [prompt_injection_attack, roleplay_attack],
    #     attacks_per_vulnerability: 5
    #   )
    #
    #   puts "Pass rate: #{assessment.overview.formatted_pass_rate}"
    #   puts "Risk level: #{assessment.risk_level}"
    #   puts "Critical vulnerabilities: #{assessment.critical_vulnerabilities.join(', ')}"
    #
    # @example Export results
    #   assessment.to_csv("red_team_results.csv")
    #   df = assessment.to_df
    #
    # @see RedTeam::RedTeamer Main coordinator class
    # @see RedTeam::Vulnerability Base vulnerability class
    # @see RedTeam::Attack Base attack class
    #
    module RedTeam
      class Error < StandardError; end
      class VulnerabilityError < Error; end
      class AttackError < Error; end
      class ConfigurationError < Error; end

      # Version of the red-teaming framework
      VERSION = "0.1.0"

      # Get list of available vulnerability categories
      #
      # @return [Array<Symbol>] Category identifiers
      def self.vulnerability_categories
        %i[
          responsible_ai
          data_privacy
          security
          safety
          business
          custom
        ]
      end

      # Get human-readable names for vulnerability categories
      #
      # @return [Hash<Symbol, String>] Category => name mapping
      def self.category_names
        {
          responsible_ai: "Responsible AI",
          data_privacy: "Data Privacy",
          security: "Security",
          safety: "Safety",
          business: "Business",
          custom: "Custom"
        }
      end

      # Check if a category is valid
      #
      # @param category [Symbol, String] Category to check
      # @return [Boolean] True if category is valid
      def self.valid_category?(category)
        vulnerability_categories.include?(category.to_sym)
      end
    end
  end
end

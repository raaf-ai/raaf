# frozen_string_literal: true

# Load all vulnerability classes
require_relative "vulnerabilities/bias"
require_relative "vulnerabilities/toxicity"
require_relative "vulnerabilities/pii_leakage"

module RAAF
  module Eval
    module RedTeam
      # Namespace for all vulnerability types
      #
      # This module provides access to all implemented vulnerability classes
      # for red-teaming and security testing of LLM applications.
      #
      # Available vulnerabilities:
      # - BiasVulnerability (responsible_ai)
      # - ToxicityVulnerability (responsible_ai)
      # - PIILeakageVulnerability (data_privacy)
      #
      # @example Using a vulnerability
      #   bias = RAAF::Eval::RedTeam::Vulnerabilities::BiasVulnerability.new
      #   result = bias.assess(input, output)
      #
      module Vulnerabilities
        # Get all available vulnerability classes
        #
        # @return [Array<Class>] All vulnerability class constants
        def self.all
          constants.map { |const| const_get(const) }.select { |c| c.is_a?(Class) }
        end

        # Get vulnerabilities by category
        #
        # @param category [String, Symbol] Category name (e.g., "responsible_ai", "data_privacy")
        # @return [Array<Class>] Vulnerability classes in the specified category
        def self.by_category(category)
          all.select do |vuln_class|
            vuln_class.new.category.to_s == category.to_s
          rescue StandardError
            false
          end
        end

        # Get all vulnerability types (string identifiers)
        #
        # @return [Array<String>] All vulnerability type identifiers
        def self.types
          all.map do |vuln_class|
            vuln_class.new.vulnerability_type
          rescue StandardError
            nil
          end.compact
        end
      end
    end
  end
end

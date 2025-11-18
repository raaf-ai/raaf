# frozen_string_literal: true

require 'rspec/expectations'

# RSpec matchers for red-team assessment validation
#
# These matchers help test overall red-team scan results and
# assess model safety and security posture.

# Matcher: have_acceptable_risk_level
#
# Tests if assessment has an acceptable overall risk level
#
# @return [Boolean] True if risk level is acceptable (low or medium)
RSpec::Matchers.define :have_acceptable_risk_level do
  match do |assessment|
    return false unless assessment.is_a?(Hash)
    return false unless assessment[:risk_level]

    [:low, :medium].include?(assessment[:risk_level])
  end

  failure_message do |assessment|
    actual_risk = assessment[:risk_level] || "unknown"

    "expected assessment to have acceptable risk level (low or medium), " \
    "but risk level was: #{actual_risk}"
  end

  failure_message_when_negated do |assessment|
    "expected assessment not to have acceptable risk level, " \
    "but risk level was: #{assessment[:risk_level]}"
  end

  description do
    "have acceptable risk level"
  end
end

# Matcher: have_risk_level
#
# Tests if assessment has a specific risk level
#
# @param expected_level [Symbol] Expected risk level (:low, :medium, :high, :critical)
# @return [Boolean] True if risk level matches
RSpec::Matchers.define :have_risk_level do |expected_level|
  match do |assessment|
    return false unless assessment.is_a?(Hash)

    assessment[:risk_level] == expected_level
  end

  failure_message do |assessment|
    actual_level = assessment[:risk_level] || "unknown"

    "expected assessment to have risk level #{expected_level}, " \
    "but actual risk level was: #{actual_level}"
  end

  failure_message_when_negated do |assessment|
    "expected assessment not to have risk level #{expected_level}, but it did"
  end

  description do
    "have risk level #{expected_level}"
  end
end

# Matcher: have_vulnerabilities_below
#
# Tests if total vulnerability count is below threshold
#
# @param threshold [Integer] Maximum acceptable vulnerability count
# @return [Boolean] True if vulnerability count below threshold
RSpec::Matchers.define :have_vulnerabilities_below do |threshold|
  match do |assessment|
    return false unless assessment.is_a?(Hash)
    return false unless assessment[:vulnerabilities]

    actual_count = assessment[:vulnerabilities].length
    actual_count < threshold
  end

  failure_message do |assessment|
    actual_count = assessment[:vulnerabilities]&.length || 0

    "expected assessment to have vulnerabilities below #{threshold}, " \
    "but actual count was: #{actual_count}"
  end

  failure_message_when_negated do |assessment|
    actual_count = assessment[:vulnerabilities]&.length || 0

    "expected assessment not to have vulnerabilities below #{threshold}, " \
    "but actual count was: #{actual_count}"
  end

  description do
    "have vulnerabilities below #{threshold}"
  end
end

# Matcher: have_no_critical_vulnerabilities
#
# Tests if assessment has zero critical severity vulnerabilities
#
# @return [Boolean] True if no critical vulnerabilities found
RSpec::Matchers.define :have_no_critical_vulnerabilities do
  match do |assessment|
    return false unless assessment.is_a?(Hash)
    return false unless assessment[:vulnerabilities]

    critical_vulns = assessment[:vulnerabilities].select do |vuln|
      vuln[:severity] == :critical
    end

    critical_vulns.empty?
  end

  failure_message do |assessment|
    critical_vulns = assessment[:vulnerabilities]&.select do |vuln|
      vuln[:severity] == :critical
    end || []

    "expected assessment to have no critical vulnerabilities, " \
    "but found #{critical_vulns.length}: #{critical_vulns.map { |v| v[:type] }}"
  end

  failure_message_when_negated do |assessment|
    "expected assessment to have critical vulnerabilities, but none were found"
  end

  description do
    "have no critical vulnerabilities"
  end
end

# Matcher: pass_category
#
# Tests if assessment passes a specific vulnerability category
#
# @param category [Symbol] Vulnerability category to check
# @return [Boolean] True if category has no detected vulnerabilities
RSpec::Matchers.define :pass_category do |category|
  match do |assessment|
    return false unless assessment.is_a?(Hash)
    return false unless assessment[:vulnerabilities]

    category_vulns = assessment[:vulnerabilities].select do |vuln|
      vuln[:category] == category
    end

    category_vulns.empty?
  end

  failure_message do |assessment|
    category_vulns = assessment[:vulnerabilities]&.select do |vuln|
      vuln[:category] == category
    end || []

    "expected assessment to pass category #{category}, " \
    "but found #{category_vulns.length} vulnerabilities"
  end

  failure_message_when_negated do |assessment|
    "expected assessment not to pass category #{category}, but it did"
  end

  description do
    "pass category #{category}"
  end
end

# Matcher: fail_category
#
# Tests if assessment fails a specific vulnerability category
#
# @param category [Symbol] Vulnerability category to check
# @return [Boolean] True if category has detected vulnerabilities
RSpec::Matchers.define :fail_category do |category|
  match do |assessment|
    return false unless assessment.is_a?(Hash)
    return false unless assessment[:vulnerabilities]

    category_vulns = assessment[:vulnerabilities].select do |vuln|
      vuln[:category] == category
    end

    !category_vulns.empty?
  end

  failure_message do |assessment|
    "expected assessment to fail category #{category}, " \
    "but no vulnerabilities were found"
  end

  failure_message_when_negated do |assessment|
    category_vulns = assessment[:vulnerabilities]&.select do |vuln|
      vuln[:category] == category
    end || []

    "expected assessment not to fail category #{category}, " \
    "but found #{category_vulns.length} vulnerabilities"
  end

  description do
    "fail category #{category}"
  end
end

# Matcher: pass_all_categories
#
# Tests if assessment passes all vulnerability categories
#
# @return [Boolean] True if no vulnerabilities detected in any category
RSpec::Matchers.define :pass_all_categories do
  match do |assessment|
    return false unless assessment.is_a?(Hash)
    return false unless assessment[:vulnerabilities]

    assessment[:vulnerabilities].empty?
  end

  failure_message do |assessment|
    vulns = assessment[:vulnerabilities] || []
    failed_categories = vulns.map { |v| v[:category] }.uniq

    "expected assessment to pass all categories, " \
    "but found vulnerabilities in: #{failed_categories}"
  end

  failure_message_when_negated do |assessment|
    "expected assessment not to pass all categories, but it did"
  end

  description do
    "pass all categories"
  end
end

# Matcher: have_scan_coverage_above
#
# Tests if scan coverage is above threshold
#
# @param threshold [Float] Minimum coverage percentage (0.0-1.0)
# @return [Boolean] True if coverage exceeds threshold
RSpec::Matchers.define :have_scan_coverage_above do |threshold|
  match do |assessment|
    return false unless assessment.is_a?(Hash)
    return false unless assessment[:coverage]

    assessment[:coverage] > threshold
  end

  failure_message do |assessment|
    actual_coverage = assessment[:coverage] || 0.0

    "expected assessment to have scan coverage above #{threshold}, " \
    "but actual coverage was: #{actual_coverage}"
  end

  failure_message_when_negated do |assessment|
    actual_coverage = assessment[:coverage] || 0.0

    "expected assessment not to have scan coverage above #{threshold}, " \
    "but actual coverage was: #{actual_coverage}"
  end

  description do
    "have scan coverage above #{threshold}"
  end
end

# Matcher: complete_successfully
#
# Tests if assessment completed without errors
#
# @return [Boolean] True if assessment completed successfully
RSpec::Matchers.define :complete_successfully do
  match do |assessment|
    return false unless assessment.is_a?(Hash)

    assessment[:success] == true && assessment[:error].nil?
  end

  failure_message do |assessment|
    if assessment[:success] == false
      "expected assessment to complete successfully, " \
      "but it failed with error: #{assessment[:error]}"
    else
      "expected assessment to complete successfully, " \
      "but success status was not set"
    end
  end

  failure_message_when_negated do |assessment|
    "expected assessment not to complete successfully, but it did"
  end

  description do
    "complete successfully"
  end
end

# Matcher: have_mitigation_recommendations
#
# Tests if assessment includes mitigation recommendations
#
# @return [Boolean] True if recommendations present
RSpec::Matchers.define :have_mitigation_recommendations do
  match do |assessment|
    return false unless assessment.is_a?(Hash)
    return false unless assessment[:recommendations]

    !assessment[:recommendations].empty?
  end

  failure_message do |assessment|
    "expected assessment to have mitigation recommendations, but none were found"
  end

  failure_message_when_negated do |assessment|
    count = assessment[:recommendations]&.length || 0

    "expected assessment not to have mitigation recommendations, but found #{count}"
  end

  description do
    "have mitigation recommendations"
  end
end

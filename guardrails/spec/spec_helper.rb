# frozen_string_literal: true

# Suppress Ruby warnings during test runs
$VERBOSE = nil

require "bundler/setup"

# Silence logging during tests to prevent console noise
ENV["RAAF_LOG_LEVEL"] = "fatal"

# Set a dummy API key so provider initialization does not abort
ENV["OPENAI_API_KEY"] = "test-api-key" if ENV["OPENAI_API_KEY"].to_s.empty?

require "raaf-guardrails"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

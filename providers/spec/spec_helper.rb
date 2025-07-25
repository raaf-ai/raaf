# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"
  minimum_coverage 0
end

require "bundler/setup"
require "rspec"
require "vcr"
require "webmock/rspec"
require "pry"

# Require the main library
require "raaf-providers"

# Configure VCR for HTTP mocking
VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.default_cassette_options = {
    record: :new_episodes,
    match_requests_on: %i[method uri body]
  }

  # Filter sensitive data
  config.filter_sensitive_data("<OPENAI_API_KEY>") { ENV.fetch("OPENAI_API_KEY", nil) }
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV.fetch("ANTHROPIC_API_KEY", nil) }
  config.filter_sensitive_data("<COHERE_API_KEY>") { ENV.fetch("COHERE_API_KEY", nil) }
  config.filter_sensitive_data("<GROQ_API_KEY>") { ENV.fetch("GROQ_API_KEY", nil) }
  config.filter_sensitive_data("<TOGETHER_API_KEY>") { ENV.fetch("TOGETHER_API_KEY", nil) }
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Mock external HTTP calls by default
  config.before do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  # Shared examples and helpers
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed
end

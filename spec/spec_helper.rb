# frozen_string_literal: true

require "bundler/setup"

# Disable tracing during tests to prevent API calls and console noise
ENV["OPENAI_AGENTS_DISABLE_TRACING"] = "true"

# Set dummy API key for tests to allow provider initialization
ENV["OPENAI_API_KEY"] = "test-api-key" unless ENV["OPENAI_API_KEY"]

require "openai_agents"
require "rspec/collection_matchers"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

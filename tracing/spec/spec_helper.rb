# frozen_string_literal: true

# Suppress Ruby warnings during test runs
$VERBOSE = nil

require "bundler/setup"

# Disable tracing during tests to prevent API calls and console noise
ENV["RAAF_DISABLE_TRACING"] = "true"

# Silence logging during tests to prevent console noise
ENV["RAAF_LOG_LEVEL"] = "fatal"

# Set dummy API key for tests to allow provider initialization
ENV["OPENAI_API_KEY"] = "test-api-key" if ENV["OPENAI_API_KEY"].to_s.empty?

require "raaf-tracing"
require "rspec/collection_matchers"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include SpanTimeHelpers

  # TracingRegistry keeps a process-level tracer, so an example that sets one
  # leaks it into every later example - including doubles, which expire and then
  # blow up wherever a span is sent.
  config.after do
    RAAF::Tracing::TracingRegistry.clear_all_contexts!
  end
end

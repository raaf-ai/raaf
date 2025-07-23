# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"
  track_files "lib/**/*.rb"
  
  add_group "Core", "lib/raaf"
  add_group "Models", "lib/raaf/models"
  add_group "Execution", "lib/raaf/execution"
  add_group "Tracing", "lib/raaf/tracing"
  add_group "Tools", "lib/raaf/tools"
end

require "bundler/setup"

# Load Rails if available for testing Rails integrations
begin
  require "rails"
  require "active_record"
  require "action_controller"
rescue LoadError
  # Rails not available, skip Rails-specific tests
end

# Load VCR for record-replay testing
begin
  require "vcr"
  require "webmock/rspec"
rescue LoadError
  # VCR not available, integration tests will be skipped
end

# Load benchmark and performance testing gems
begin
  require "rspec-benchmark"
rescue LoadError
  # Benchmarking not available
end

# Disable tracing during tests to prevent API calls and console noise
ENV["RAAF_DISABLE_TRACING"] = "true"

# Set dummy API key for tests to allow provider initialization
ENV["OPENAI_API_KEY"] = "test-api-key" unless ENV["OPENAI_API_KEY"]

require "raaf-core"
require "rspec/collection_matchers"

# Configure VCR if available
if defined?(VCR)
  VCR.configure do |config|
    config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
    config.hook_into :webmock
    config.default_cassette_options = {
      record: :once,
      match_requests_on: %i[method uri headers body]
    }

    # Filter sensitive data
    config.filter_sensitive_data("<OPENAI_API_KEY>") { ENV.fetch("OPENAI_API_KEY", nil) }
    config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV.fetch("ANTHROPIC_API_KEY", nil) }

    # Allow real HTTP connections for integration tests when explicitly enabled
    config.allow_http_connections_when_no_cassette = !ENV["VCR_ALLOW_HTTP"].nil? && !ENV["VCR_ALLOW_HTTP"].empty?
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Include benchmark matchers if available
  config.include RSpec::Benchmark::Matchers if defined?(RSpec::Benchmark)

  # Test categorization and configuration
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:type] = :integration
    metadata[:integration] = true
  end

  config.define_derived_metadata(file_path: %r{/spec/performance/}) do |metadata|
    metadata[:type] = :performance
    metadata[:performance] = true
  end

  config.define_derived_metadata(file_path: %r{/spec/cost/}) do |metadata|
    metadata[:type] = :cost
    metadata[:cost] = true
  end

  config.define_derived_metadata(file_path: %r{/spec/property_based/}) do |metadata|
    metadata[:type] = :property
    metadata[:property] = true
  end

  # Skip integration tests by default unless explicitly requested
  config.filter_run_excluding :integration unless ENV["RUN_INTEGRATION_TESTS"]

  # Skip performance tests by default unless explicitly requested
  config.filter_run_excluding :performance unless ENV["RUN_PERFORMANCE_TESTS"]

  # Skip cost tests by default unless explicitly requested
  config.filter_run_excluding :cost unless ENV["RUN_COST_TESTS"]

  # Skip acceptance tests by default unless explicitly requested
  config.filter_run_excluding :acceptance unless ENV["RUN_ACCEPTANCE_TESTS"]

  # Configuration for integration tests
  config.before(:each, :integration) do
    # Skip if VCR not available
    skip "VCR not available" unless defined?(VCR)
  end

  # Configuration for performance tests
  config.before(:each, :performance) do
    # Skip if benchmark matchers not available
    skip "rspec-benchmark not available" unless defined?(RSpec::Benchmark)
  end

  # Configuration for cost tests
  config.before(:each, :cost) do
    # Reset cost tracking before each test
    RAAF::Testing::CostTracker.reset! if defined?(RAAF::Testing::CostTracker)
  end

  # Configuration for acceptance tests
  config.before(:each, :acceptance) do
    # Skip if VCR not available
    skip "VCR not available" unless defined?(VCR)
    # Allow real HTTP connections for acceptance tests if VCR_ALLOW_HTTP is set
    WebMock.allow_net_connect! if defined?(WebMock) && ENV["VCR_ALLOW_HTTP"]
  end

  # Configuration for property-based tests
  config.before(:each, :property) do
    # Disable WebMock for property tests as they generate random data
    WebMock.disable! if defined?(WebMock)
  end

  config.after(:each, :property) do
    # Re-enable WebMock after property tests
    WebMock.enable! if defined?(WebMock)
  end
end

# Test helpers and utilities
module RAAF

  module Testing

    class MockProvider

      def initialize
        @responses = []
        @errors = []
        @call_count = 0
      end

      def add_response(content, tool_calls: nil, usage: nil)
        default_usage = { 
          prompt_tokens: 10, 
          completion_tokens: 15, 
          total_tokens: 25,
          input_tokens: 10,
          output_tokens: 15
        }
        
        # Merge custom usage with defaults, converting string keys to symbols
        final_usage = if usage
          normalized_usage = {}
          usage.each do |key, value|
            symbol_key = key.to_sym
            normalized_usage[symbol_key] = value
          end
          default_usage.merge(normalized_usage)
        else
          default_usage
        end
        
        response = {
          id: "mock_#{SecureRandom.hex(6)}",
          output: build_output(content, tool_calls),
          usage: final_usage
        }
        @responses << response
      end

      def add_error(error)
        @errors << error
      end

      def responses_completion(messages:, model:, **_kwargs)
        @call_count += 1

        raise @errors.shift if @errors.any?

        if @responses.any?
          @responses.shift
        else
          default_response
        end
      end

      alias complete responses_completion

      private

      def build_output(content, tool_calls)
        output = []

        if content
          output << {
            type: "message",
            role: "assistant",
            content: content
          }
        end

        tool_calls&.each do |call|
          output << {
            type: "function_call",
            name: call.dig(:function, :name) || call[:name],
            arguments: call.dig(:function, :arguments) || call[:arguments] || "{}",
            call_id: call[:id] || "call_#{SecureRandom.hex(4)}"
          }
        end

        output
      end

      def default_response
        {
          id: "mock_default",
          output: [{
            type: "message",
            role: "assistant",
            content: "Default mock response"
          }],
          usage: { prompt_tokens: 10, completion_tokens: 15, total_tokens: 25 }
        }
      end

    end

    class CostTracker

      @total_tokens = 0
      @total_cost = 0.0
      @calls = []

      class << self

        attr_reader :total_tokens, :total_cost, :calls

        def reset!
          @total_tokens = 0
          @total_cost = 0.0
          @calls = []
        end

        def track_usage(usage, model: "gpt-4o")
          tokens = usage[:total_tokens] || usage["total_tokens"] || 0
          cost = estimate_cost(tokens, model)

          @total_tokens += tokens
          @total_cost += cost
          @calls << { tokens: tokens, cost: cost, model: model, timestamp: Time.now }
        end

        def estimate_cost(tokens, model)
          # Simplified cost estimation - adjust based on actual pricing
          case model
          when /gpt-4o/
            tokens * 0.00001  # $0.01 per 1K tokens (average of input/output)
          when /gpt-4/
            tokens * 0.00003  # $0.03 per 1K tokens
          when /gpt-3.5/
            tokens * 0.000002 # $0.002 per 1K tokens
          else
            tokens * 0.00001  # Default rate
          end
        end

      end

    end

    module Helpers

      def create_test_agent(name: "TestAgent", **)
        RAAF::Agent.new(name: name, **)
      end

      def create_mock_provider
        MockProvider.new
      end

      def with_cost_tracking
        CostTracker.reset!
        yield
        CostTracker
      end

    end

    module Matchers

      extend RSpec::Matchers::DSL

      matcher :be_within_token_budget do |expected_tokens|
        match do |result|
          usage = result.usage || {}
          actual_tokens = usage[:total_tokens] || usage["total_tokens"] || 0
          actual_tokens <= expected_tokens
        end

        failure_message do |result|
          usage = result.usage || {}
          actual_tokens = usage[:total_tokens] || usage["total_tokens"] || 0
          "expected #{actual_tokens} tokens to be within budget of #{expected_tokens}"
        end
      end

      matcher :be_within_cost_budget do |expected_cost|
        match do |result|
          usage = result.usage || {}
          tokens = usage[:total_tokens] || usage["total_tokens"] || 0
          # Use default model for cost calculation since result doesn't have model info
          actual_cost = CostTracker.estimate_cost(tokens, "gpt-4o")
          actual_cost <= expected_cost
        end

        failure_message do |result|
          usage = result.usage || {}
          tokens = usage[:total_tokens] || usage["total_tokens"] || 0
          actual_cost = CostTracker.estimate_cost(tokens, "gpt-4o")
          "expected cost of $#{actual_cost.round(4)} to be within budget of $#{expected_cost}"
        end
      end

      matcher :include_handoff_to do |expected_agent|
        match do |result|
          result.messages.any? do |message|
            message[:tool_calls]&.any? do |call|
              call.dig("function", "name")&.include?("transfer_to_") &&
                call.dig("function", "name").include?(expected_agent.downcase)
            end
          end
        end

        failure_message do |_result|
          "expected result to include handoff to #{expected_agent}"
        end
      end

    end

  end

end

# Include test helpers in RSpec
RSpec.configure do |config|
  config.include RAAF::Testing::Helpers
  config.include RAAF::Testing::Matchers
end

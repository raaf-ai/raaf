#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates RetryableProvider integration with RAAF Core.
# The RetryableProvider adds robust retry logic to any provider,
# implementing exponential backoff and failure recovery.
# This is essential for production systems that need resilience against transient failures,
# network issues, rate limits, and temporary service outages.

require_relative "../lib/raaf-core"

# For this example, we'll use the core providers
unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY environment variable is required"
  puts "Please set it with: export OPENAI_API_KEY='your-api-key'"
  exit 1
end

puts "=== RAAF Core RetryableProvider Example ==="
puts

# ============================================================================
# EXAMPLE 1: BASIC RETRY WITH CORE PROVIDERS
# ============================================================================

puts "1. Basic retry with core providers:"

# Create base provider from core
base_provider = RAAF::Models::OpenAIProvider.new

# Create a retryable wrapper
retryable_provider = RAAF::Models::RetryableProviderWrapper.new(
  base_provider,
  max_attempts: 3,          # Retry up to 3 times
  base_delay: 1.0,          # Start with 1 second delay
  max_delay: 30.0,          # Maximum delay between retries
  multiplier: 2.0,          # Double the delay each time
  jitter: 0.1               # Add 10% jitter to prevent thundering herd
)

# Test basic retry functionality
puts "Testing basic retry functionality..."
begin
  response = retryable_provider.chat_completion(
    messages: [{ role: "user", content: "Hello! Test the retry mechanism with RAAF Core." }],
    model: "gpt-4o"
  )
  puts "Success: #{response.dig("choices", 0, "message", "content")}"
rescue StandardError => e
  puts "Failed after retries: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 2: RETRY WITH RESPONSES PROVIDER
# ============================================================================

puts "2. Retry with ResponsesProvider (Core default):"

# Use the default ResponsesProvider from core
responses_provider = RAAF::Models::ResponsesProvider.new

# Wrap with retry logic
retryable_responses = RAAF::Models::RetryableProviderWrapper.new(
  responses_provider,
  max_attempts: 3,
  base_delay: 0.5,
  logger: Logger.new($stdout)
)

puts "Testing with ResponsesProvider and retry..."
begin
  response = retryable_responses.chat_completion(
    messages: [{ role: "user", content: "Test ResponsesProvider with retry logic." }],
    model: "gpt-4o"
  )
  puts "ResponsesProvider success: #{response.dig("choices", 0, "message", "content")}"
rescue StandardError => e
  puts "ResponsesProvider with retry failed: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 3: AGENT WITH RETRYABLE PROVIDER
# ============================================================================

puts "3. Agent with retryable provider:"

# Create agent
resilient_agent = RAAF::Agent.new(
  name: "ResilientAgent",
  instructions: "You are a resilient agent that handles API failures gracefully.",
  model: "gpt-4o"
)

# Create runner with retryable provider
resilient_runner = RAAF::Runner.new(
  agent: resilient_agent,
  provider: retryable_provider
)

# Test resilient agent
puts "Testing resilient agent..."
begin
  result = resilient_runner.run("Tell me about the benefits of retry logic in AI applications.")
  puts "Resilient agent response: #{result.messages.last[:content]}"
rescue StandardError => e
  puts "Resilient agent error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 4: TESTING RETRY BEHAVIOR
# ============================================================================

puts "4. Testing retry behavior with simulated failures:"

# Create a mock provider that fails predictably
class FailingProvider < RAAF::Models::ModelInterface

  def initialize(fail_count = 2)
    super()
    @fail_count = fail_count
    @attempt = 0
  end

  def chat_completion(messages:, model:, **_options)
    @attempt += 1

    if @attempt <= @fail_count
      # Simulate different types of failures
      case @attempt
      when 1
        raise Errno::ECONNRESET, "Connection reset by peer"
      when 2
        raise Net::ReadTimeout, "Read timeout"
      else
        raise Net::HTTPServiceUnavailable, "Service unavailable"
      end
    end

    # Success after failures
    {
      "choices" => [
        {
          "message" => {
            "content" => "Success after #{@fail_count} failures! (Attempt #{@attempt})"
          }
        }
      ],
      "usage" => {
        "prompt_tokens" => 10,
        "completion_tokens" => 15,
        "total_tokens" => 25
      }
    }
  end

end

# Test with failing provider
failing_provider = FailingProvider.new(2) # Fail 2 times, then succeed
retryable_failing = RAAF::Models::RetryableProviderWrapper.new(
  failing_provider,
  max_attempts: 5,
  base_delay: 0.1, # Fast for demo
  logger: Logger.new($stdout)
)

puts "Testing with provider that fails 2 times..."
begin
  response = retryable_failing.chat_completion(
    messages: [{ role: "user", content: "Test failure recovery" }],
    model: "test-model"
  )
  puts "Recovery success: #{response.dig("choices", 0, "message", "content")}"
rescue StandardError => e
  puts "Recovery failed: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 5: RETRY CONFIGURATION
# ============================================================================

puts "5. Different retry configurations:"

configurations = [
  {
    name: "Fast retry",
    config: { max_attempts: 2, base_delay: 0.1, max_delay: 1.0 }
  },
  {
    name: "Standard retry",
    config: { max_attempts: 3, base_delay: 1.0, max_delay: 30.0 }
  },
  {
    name: "Persistent retry",
    config: { max_attempts: 5, base_delay: 2.0, max_delay: 60.0 }
  }
]

configurations.each do |config_info|
  puts "Testing #{config_info[:name]}:"

  test_provider = RAAF::Models::RetryableProviderWrapper.new(
    base_provider,
    **config_info[:config]
  )

  begin
    response = test_provider.chat_completion(
      messages: [{ role: "user", content: "Test #{config_info[:name]} configuration." }],
      model: "gpt-4o"
    )
    puts "  Success: Configuration working properly"
  rescue StandardError => e
    puts "  Error: #{e.message}"
  end

  puts
end

# ============================================================================
# SUMMARY
# ============================================================================

puts "=== RetryableProvider Core Features ==="
puts
puts "Available in RAAF Core:"
puts "1. ✅ RetryableProvider module - Add retry logic to any provider"
puts "2. ✅ RetryableProviderWrapper - Wrap existing providers with retry"
puts "3. ✅ Exponential backoff with jitter"
puts "4. ✅ Configurable retry attempts and delays"
puts "5. ✅ Built-in logging and error handling"
puts "6. ✅ Support for common network errors"
puts "7. ✅ Integration with core ModelInterface"
puts
puts "Best Practices:"
puts "- Start with 3-5 retry attempts for most use cases"
puts "- Use exponential backoff to avoid overwhelming failing services"
puts "- Add jitter to prevent synchronized retry storms"
puts "- Configure appropriate max delays for your application"
puts "- Monitor retry patterns in production"
puts "- Log retry attempts for debugging and analysis"
puts
puts "Example Complete! RetryableProvider is now available in RAAF Core."

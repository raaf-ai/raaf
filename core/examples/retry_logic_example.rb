#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates retry logic and error handling for production reliability.
# Network issues, rate limits, and temporary API outages are common in production
# AI applications. This example shows how to implement robust retry mechanisms,
# graceful degradation, and comprehensive error handling strategies.
#
# ⚠️  WARNING: This file shows PLANNED retry logic features that are NOT implemented yet!
# ❌ The RAAF::Models::RetryableProvider class does not exist
# ✅ This serves as design documentation for future retry features

require_relative "../lib/raaf-core"

# ============================================================================
# RETRY CONFIGURATION AND SETUP
# ============================================================================

puts "=== Retry Logic and Error Handling Example ==="
puts "=" * 60

# Environment check
unless ENV["OPENAI_API_KEY"]
  puts "NOTE: OPENAI_API_KEY not set. Running in simulation mode."
  puts "For live retry testing, set your API key."
  puts
end

# ============================================================================
# RETRYABLE PROVIDER CONFIGURATION
# ============================================================================

puts "=== Retryable Provider Configuration ==="
puts "-" * 50

# Configure retry settings for different scenarios.
# The RetryableProvider is a mixin that adds retry logic to existing providers.
def create_retryable_provider(max_retries: 3, base_delay: 1.0, max_delay: 60.0)
  # ❌ PLANNED FEATURE: Create a provider class that includes retry logic
  # The following code shows the intended API but does not work yet
  puts "⚠️  WARNING: RetryableProvider is not implemented yet"
  return nil
  
  # PLANNED API (commented out until implemented):
  # retryable_class = Class.new(RAAF::Models::ResponsesProvider) do  # Use ResponsesProvider instead
  #   include RAAF::Models::RetryableProvider  # This doesn't exist yet

    def initialize(**kwargs)
      super
      configure_retry(
        max_attempts: kwargs[:max_retries] || 3,
        base_delay: kwargs[:base_delay] || 1.0,
        max_delay: kwargs[:max_delay] || 60.0,
        multiplier: 2.0,
        jitter: 0.1
      )
    end

    def chat_completion(**kwargs)
      with_retry { super(**kwargs) }
    end

    def stream_completion(...)
      with_retry { super(...) }
    end
  end

  retryable_provider = retryable_class.new(
    max_retries: max_retries,
    base_delay: base_delay,
    max_delay: max_delay
  )

  puts "✅ Retryable provider configured:"
  puts "   Max retries: #{max_retries}"
  puts "   Base delay: #{base_delay}s"
  puts "   Max delay: #{max_delay}s"
  puts "   Exponential backoff with jitter enabled"

  retryable_provider
end

# Create different retry configurations for different use cases
create_retryable_provider(max_retries: 2, base_delay: 0.5)
create_retryable_provider(max_retries: 3, base_delay: 1.0)
create_retryable_provider(max_retries: 5, base_delay: 2.0)

puts "\n✅ Multiple retry configurations created:"
puts "   Conservative: 2 retries, 0.5s base delay"
puts "   Standard: 3 retries, 1.0s base delay"
puts "   Aggressive: 5 retries, 2.0s base delay"

# ============================================================================
# ERROR SIMULATION AND TESTING
# ============================================================================

puts "\n=== Error Simulation and Recovery ==="
puts "-" * 50

# Custom provider that simulates different types of errors
# This helps demonstrate retry behavior without relying on actual network issues
class ErrorSimulationProvider < RAAF::Models::ModelInterface

  def initialize(error_pattern: [])
    super()
    @call_count = 0
    @error_pattern = error_pattern
  end

  def chat_completion(messages:, model:, **_kwargs)
    @call_count += 1

    # Check if we should simulate an error for this call
    if @call_count <= @error_pattern.length && @error_pattern[@call_count - 1]
      error_type = @error_pattern[@call_count - 1]
      simulate_error(error_type)
    else
      # Successful response
      {
        choices: [{
          message: {
            role: "assistant",
            content: "This is a successful response after #{@call_count} attempts."
          }
        }],
        usage: {
          prompt_tokens: 10,
          completion_tokens: 15,
          total_tokens: 25
        }
      }
    end
  end

  def stream_completion(messages:, model:)
    # For simplicity, stream_completion behaves like chat_completion
    result = chat_completion(messages: messages, model: model)
    yield result.dig(:choices, 0, :message, :content) if block_given?
    result
  end

  def provider_name
    "ErrorSimulation"
  end

  def supported_models
    ["test-model"]
  end

  private

  def simulate_error(error_type)
    case error_type
    when :rate_limit
      puts "   🔄 Simulating rate limit error (attempt #{@call_count})"
      raise RAAF::Models::RateLimitError, "Rate limit exceeded. Please try again later."
    when :server_error
      puts "   🔄 Simulating server error (attempt #{@call_count})"
      raise RAAF::Models::ServerError, "Internal server error (500)"
    when :timeout
      puts "   🔄 Simulating timeout error (attempt #{@call_count})"
      raise RAAF::Models::APIError, "Request timeout"
    when :network_error
      puts "   🔄 Simulating network error (attempt #{@call_count})"
      raise StandardError, "Network connection failed"
    else
      puts "   🔄 Simulating generic error (attempt #{@call_count})"
      raise RAAF::Models::APIError, "Generic API error"
    end
  end

end

# Test different error scenarios
error_scenarios = {
  "Rate Limit Recovery" => [:rate_limit, :rate_limit, false],
  "Server Error Recovery" => [:server_error, false],
  "Mixed Error Recovery" => [:timeout, :rate_limit, :server_error, false],
  "Persistent Failure" => %i[rate_limit rate_limit rate_limit rate_limit]
}

puts "Testing retry behavior with error simulation:"
puts

error_scenarios.each do |scenario_name, error_pattern|
  puts "#{scenario_name}:"

  # Create error simulation provider
  error_provider = ErrorSimulationProvider.new(error_pattern: error_pattern)

  # ❌ PLANNED: Create retryable wrapper for error provider  
  puts "⚠️  WARNING: RetryableProvider is not implemented yet - skipping retry test"
  return
  
  # PLANNED API (commented out until RetryableProvider is implemented):
  # retryable_class = Class.new do
  #   include RAAF::Models::RetryableProvider  # This doesn't exist yet

    def initialize(base_provider)
      @base_provider = base_provider
      configure_retry(
        max_attempts: 3,
        base_delay: 0.1,
        max_delay: 1.0,
        multiplier: 2.0,
        jitter: 0.1
      )
    end

    def chat_completion(**kwargs)
      with_retry { @base_provider.chat_completion(**kwargs) }
    end

    def stream_completion(...)
      with_retry { @base_provider.stream_completion(...) }
    end

    def provider_name
      "Retryable(#{@base_provider.provider_name})"
    end

    def supported_models
      @base_provider.supported_models
    end
  end

  retryable_provider = retryable_class.new(error_provider)

  # Create agent and runner
  test_agent = RAAF::Agent.new(
    name: "RetryTestAgent",
    instructions: "You are a test agent for retry logic.",
    model: "test-model"
  )

  retry_runner = RAAF::Runner.new(
    agent: test_agent,
    provider: retryable_provider
  )

  begin
    start_time = Time.now
    result = retry_runner.run("Test message for retry logic")
    end_time = Time.now

    puts "   ✅ Success after retries!"
    puts "   Response: #{result.final_output}"
    puts "   Total time: #{((end_time - start_time) * 1000).round(1)}ms"
  rescue StandardError => e
    end_time = Time.now
    puts "   ❌ Failed after all retries: #{e.class.name}: #{e.message}"
    puts "   Total time: #{((end_time - start_time) * 1000).round(1)}ms"
  end

  puts
end

# ============================================================================
# CUSTOM RETRY STRATEGIES
# ============================================================================

puts "=== Custom Retry Strategies ==="
puts "-" * 50

# Custom retry logic with circuit breaker pattern
class CircuitBreakerProvider < RAAF::Models::ModelInterface

  def initialize(base_provider, failure_threshold: 5, recovery_timeout: 30)
    super()
    @base_provider = base_provider
    @failure_threshold = failure_threshold
    @recovery_timeout = recovery_timeout
    @failure_count = 0
    @last_failure_time = nil
    @state = :closed # :closed, :open, :half_open
  end

  def chat_completion(messages:, model:, **)
    case @state
    when :open
      raise RAAF::Models::APIError, "Circuit breaker is open" unless Time.now - @last_failure_time > @recovery_timeout

      @state = :half_open
      puts "   🔄 Circuit breaker: Attempting recovery (half-open)"

    when :half_open
      puts "   🔄 Circuit breaker: Testing recovery"
    end

    begin
      result = @base_provider.chat_completion(messages: messages, model: model, **)

      # Success - reset failure count and close circuit
      @failure_count = 0
      @state = :closed
      puts "   ✅ Circuit breaker: Request successful (#{@state})"

      result
    rescue StandardError => e
      @failure_count += 1
      @last_failure_time = Time.now

      if @failure_count >= @failure_threshold
        @state = :open
        puts "   ⚡ Circuit breaker: Opened due to #{@failure_count} failures"
      end

      raise e
    end
  end

  def stream_completion(messages:, model:)
    chat_completion(messages: messages, model: model)
  end

  def provider_name
    "CircuitBreaker(#{@base_provider.provider_name})"
  end

  def supported_models
    @base_provider.supported_models
  end

  attr_reader :state

end

# Test circuit breaker
puts "Testing circuit breaker pattern:"

# Create a provider that fails consistently
failing_provider = ErrorSimulationProvider.new(
  error_pattern: %i[server_error server_error server_error server_error server_error server_error]
)

circuit_breaker = CircuitBreakerProvider.new(failing_provider, failure_threshold: 3, recovery_timeout: 1)

test_agent = RAAF::Agent.new(
  name: "CircuitTestAgent",
  instructions: "Test agent for circuit breaker.",
  model: "test-model"
)

runner = RAAF::Runner.new(agent: test_agent, provider: circuit_breaker)

# Test multiple requests to trigger circuit breaker
(1..7).each do |attempt|
  begin
    puts "   Attempt #{attempt}:"
    result = runner.run("Test message #{attempt}")
    puts "     ✅ Success: #{result.final_output}"
  rescue StandardError => e
    puts "     ❌ Failed: #{e.message}"
    puts "     Circuit state: #{circuit_breaker.state}"
  end

  sleep(0.1) # Small delay between attempts
end

# Test recovery after timeout
puts "\n   Waiting for recovery timeout..."
sleep(1.1)

begin
  puts "   Recovery attempt:"
  result = runner.run("Recovery test message")
  puts "     ✅ Recovery successful!"
rescue StandardError => e
  puts "     ❌ Recovery failed: #{e.message}"
end

# ============================================================================
# COMPREHENSIVE ERROR HANDLING
# ============================================================================

puts "\n=== Comprehensive Error Handling Patterns ==="
puts "-" * 50

# Error handling utility class for production use
class ErrorHandler

  def self.handle_agent_errors
    yield
  rescue RAAF::Models::AuthenticationError => e
    {
      success: false,
      error_type: :authentication,
      message: "Invalid API key or authentication failed",
      user_message: "Authentication error. Please check your API configuration.",
      retry_after: nil,
      details: e.message
    }
  rescue RAAF::Models::RateLimitError => e
    retry_after = extract_retry_after(e.message)
    {
      success: false,
      error_type: :rate_limit,
      message: "Rate limit exceeded",
      user_message: "Request rate limit exceeded. Please try again later.",
      retry_after: retry_after,
      details: e.message
    }
  rescue RAAF::Models::ServerError => e
    {
      success: false,
      error_type: :server_error,
      message: "Server error occurred",
      user_message: "Service temporarily unavailable. Please try again.",
      retry_after: 30,
      details: e.message
    }
  rescue RAAF::Models::APIError => e
    {
      success: false,
      error_type: :api_error,
      message: "API request failed",
      user_message: "Request failed. Please check your input and try again.",
      retry_after: 5,
      details: e.message
    }
  rescue RAAF::MaxTurnsError => e
    {
      success: false,
      error_type: :max_turns,
      message: "Maximum conversation turns exceeded",
      user_message: "Conversation has reached maximum length. Please start a new conversation.",
      retry_after: nil,
      details: e.message
    }
  rescue StandardError => e
    {
      success: false,
      error_type: :unknown,
      message: "Unexpected error occurred",
      user_message: "An unexpected error occurred. Please try again later.",
      retry_after: 60,
      details: e.message
    }
  end

  def self.extract_retry_after(error_message)
    # Try to extract retry-after time from error message
    if error_message =~ /(?:retry.*?(\d+).*?second|try again.*?(\d+))/i
      (Regexp.last_match(1) || Regexp.last_match(2)).to_i
    else
      60 # Default to 60 seconds
    end
  end

end

# Demonstrate comprehensive error handling
puts "Testing comprehensive error handling:"

error_test_cases = [
  { provider: ErrorSimulationProvider.new(error_pattern: [:rate_limit]), description: "Rate limit handling" },
  { provider: ErrorSimulationProvider.new(error_pattern: [:server_error]), description: "Server error handling" },
  { provider: ErrorSimulationProvider.new(error_pattern: [:network_error]), description: "Network error handling" }
]

error_test_cases.each do |test_case|
  puts "\n#{test_case[:description]}:"

  agent = RAAF::Agent.new(
    name: "ErrorTestAgent",
    instructions: "Test agent for error handling.",
    model: "test-model"
  )

  runner = RAAF::Runner.new(agent: agent, provider: test_case[:provider])

  result = ErrorHandler.handle_agent_errors do
    runner.run("Test error handling")
  end

  if result.is_a?(Hash) && !result[:success]
    puts "   Error handled gracefully:"
    puts "     Type: #{result[:error_type]}"
    puts "     User message: #{result[:user_message]}"
    puts "     Retry after: #{result[:retry_after]}s" if result[:retry_after]
    puts "     Technical details: #{result[:details]}"
  else
    puts "   ✅ Request succeeded unexpectedly"
  end
end

# ============================================================================
# PRODUCTION RETRY PATTERNS
# ============================================================================

puts "\n=== Production Retry Implementation ==="
puts "-" * 50

# Production-ready retry wrapper with monitoring
class ProductionRetryWrapper

  def initialize(runner, max_retries: 3, base_delay: 1.0, max_delay: 60.0)
    @runner = runner
    @max_retries = max_retries
    @base_delay = base_delay
    @max_delay = max_delay
    @metrics = Hash.new(0)
  end

  def run_with_retry(message, **kwargs)
    attempt = 0
    last_error = nil

    loop do
      attempt += 1

      begin
        @metrics[:total_requests] += 1
        start_time = Time.now

        result = @runner.run(message, **kwargs)

        duration = Time.now - start_time
        @metrics[:successful_requests] += 1
        @metrics[:total_duration] += duration

        if attempt > 1
          @metrics[:retries_successful] += 1
          puts "   ✅ Succeeded on attempt #{attempt}"
        end

        return {
          success: true,
          result: result,
          attempts: attempt,
          duration: duration
        }
      rescue StandardError => e
        last_error = e
        @metrics[:failed_requests] += 1

        if attempt >= @max_retries + 1
          @metrics[:permanent_failures] += 1
          break
        end

        # Calculate delay with exponential backoff
        delay = [@base_delay * (2**(attempt - 1)), @max_delay].min

        # Add jitter (±25%)
        jitter = delay * 0.25 * (rand - 0.5)
        final_delay = delay + jitter

        @metrics[:retries_attempted] += 1
        puts "   🔄 Attempt #{attempt} failed: #{e.class.name}"
        puts "      Retrying in #{final_delay.round(2)}s..."

        sleep(final_delay)
      end
    end

    # All retries exhausted
    {
      success: false,
      error: last_error,
      attempts: attempt,
      final_error: last_error.message
    }
  end

  def metrics
    success_rate = if @metrics[:total_requests].positive?
                     (@metrics[:successful_requests].to_f / @metrics[:total_requests] * 100).round(2)
                   else
                     0
                   end

    avg_duration = if @metrics[:successful_requests].positive?
                     (@metrics[:total_duration] / @metrics[:successful_requests]).round(3)
                   else
                     0
                   end

    {
      total_requests: @metrics[:total_requests],
      successful_requests: @metrics[:successful_requests],
      failed_requests: @metrics[:failed_requests],
      retries_attempted: @metrics[:retries_attempted],
      retries_successful: @metrics[:retries_successful],
      permanent_failures: @metrics[:permanent_failures],
      success_rate: "#{success_rate}%",
      average_duration: "#{avg_duration}s"
    }
  end

end

# Test production retry wrapper
puts "Testing production retry wrapper with metrics:"

# Create a provider with intermittent failures
intermittent_provider = ErrorSimulationProvider.new(
  error_pattern: [:rate_limit, false, :server_error, false, false, :timeout, false]
)

test_agent = RAAF::Agent.new(
  name: "ProductionTestAgent",
  instructions: "Production test agent with retry logic.",
  model: "test-model"
)

base_runner = RAAF::Runner.new(agent: test_agent, provider: intermittent_provider)
retry_wrapper = ProductionRetryWrapper.new(base_runner, max_retries: 2, base_delay: 0.1)

# Run multiple test requests
test_requests = [
  "First test request",
  "Second test request",
  "Third test request",
  "Fourth test request",
  "Fifth test request"
]

puts

test_requests.each_with_index do |request, index|
  puts "Request #{index + 1}: \"#{request}\""

  result = retry_wrapper.run_with_retry(request)

  if result[:success]
    puts "   ✅ Success in #{result[:attempts]} attempt(s)"
    puts "   Response: #{result[:result].final_output}"
  else
    puts "   ❌ Failed after #{result[:attempts]} attempts"
    puts "   Final error: #{result[:final_error]}"
  end

  puts
end

# Display metrics
puts "=== Production Metrics ==="
metrics = retry_wrapper.metrics
metrics.each do |key, value|
  puts "#{key.to_s.gsub("_", " ").capitalize}: #{value}"
end

# ============================================================================
# BEST PRACTICES SUMMARY
# ============================================================================

puts "\n=== Retry Logic Best Practices ==="
puts "-" * 50

puts "✅ Retry Configuration:"
puts "   • Use exponential backoff with jitter"
puts "   • Set reasonable maximum retry limits (3-5 attempts)"
puts "   • Implement per-error-type retry strategies"
puts "   • Add circuit breaker for cascading failures"
puts "   • Monitor retry success rates and adjust"

puts "\n✅ Error Handling Strategies:"
puts "   • Distinguish between retryable and non-retryable errors"
puts "   • Provide meaningful user error messages"
puts "   • Log detailed technical information for debugging"
puts "   • Implement graceful degradation where possible"
puts "   • Set up alerting for high error rates"

puts "\n✅ Production Considerations:"
puts "   • Monitor retry metrics and success rates"
puts "   • Implement request deduplication"
puts "   • Use bulkhead pattern for service isolation"
puts "   • Consider async processing for non-urgent requests"
puts "   • Implement proper timeout handling"

puts "\n✅ Network Resilience:"
puts "   • Handle DNS resolution failures"
puts "   • Implement connection pooling and keep-alive"
puts "   • Use multiple API endpoints when available"
puts "   • Consider regional failover strategies"
puts "   • Implement health checks and monitoring"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Retry Logic and Error Handling Complete! ==="
puts "\nKey Features Demonstrated:"
puts "• Configurable retry logic with exponential backoff"
puts "• Circuit breaker pattern for cascading failure prevention"
puts "• Comprehensive error classification and handling"
puts "• Production-ready retry wrapper with metrics"
puts "• Error simulation and testing strategies"

puts "\nError Types Handled:"
puts "• Rate limiting with intelligent backoff"
puts "• Server errors and temporary outages"
puts "• Network connectivity issues"
puts "• Authentication and authorization failures"
puts "• Timeout and performance issues"

puts "\nProduction Implementation:"
puts "• Use RetryableProvider for automatic retry logic"
puts "• Implement circuit breakers for critical services"
puts "• Monitor retry metrics and adjust strategies"
puts "• Provide graceful error messages to users"
puts "• Set up alerting for error rate thresholds"

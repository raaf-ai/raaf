#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates RetryableProviderWrapper integration with RAAF (Ruby AI Agents Factory).
# The RetryableProviderWrapper wraps any other provider with robust retry logic,
# implementing exponential backoff, circuit breaker patterns, and failure recovery.
# This is essential for production systems that need resilience against transient failures,
# network issues, rate limits, and temporary service outages.

require_relative "../lib/raaf"

# For this example, we'll use OpenAI by default, but you can use any provider
unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY environment variable is required"
  puts "Please set it with: export OPENAI_API_KEY='your-api-key'"
  puts "You can also set GROQ_API_KEY, ANTHROPIC_API_KEY, etc. to test with other providers"
  exit 1
end

puts "=== Retryable Provider Example ==="
puts

# ============================================================================
# PROVIDER SETUP
# ============================================================================

# Create base providers to wrap with retry logic
base_providers = {}

# OpenAI provider (primary)
base_providers[:openai] = RAAF::Models::OpenAIProvider.new

# Add other providers if API keys are available
if ENV["GROQ_API_KEY"]
  base_providers[:groq] = RAAF::Models::GroqProvider.new
end

if ENV["ANTHROPIC_API_KEY"]
  base_providers[:anthropic] = RAAF::Models::AnthropicProvider.new
end

puts "Available providers for retry testing: #{base_providers.keys.join(", ")}"
puts

# ============================================================================
# EXAMPLE 1: BASIC RETRY WRAPPER
# ============================================================================

puts "1. Basic retry wrapper setup:"

# Create a basic retryable provider with default settings
retryable_provider = RAAF::Models::RetryableProviderWrapper.new(
  base_providers[:openai],
  max_attempts: 3,          # Retry up to 3 times
  base_delay: 1.0,          # Start with 1 second delay
  max_delay: 30.0,          # Maximum delay between retries
  exponential_base: 2.0,    # Double the delay each time
  jitter: true              # Add random jitter to prevent thundering herd
)

# Test basic retry functionality
puts "Testing basic retry functionality..."
begin
  response = retryable_provider.chat_completion(
    messages: [{ role: "user", content: "Hello! Test the retry mechanism." }],
    model: "gpt-4o"
  )
  puts "Success: #{response.dig("choices", 0, "message", "content")}"
rescue StandardError => e
  puts "Failed after retries: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 2: RETRY WITH LOGGING
# ============================================================================

puts "2. Retry with detailed logging:"

# Create a logger to track retry attempts
require 'logger'
retry_logger = Logger.new($stdout)
retry_logger.level = Logger::INFO

# Create retryable provider with logging
logged_provider = RAAF::Models::RetryableProviderWrapper.new(
  base_providers[:openai],
  max_attempts: 5,
  base_delay: 0.5,
  exponential_base: 2.0,
  jitter: true,
  logger: retry_logger,
  log_level: Logger::INFO
)

puts "Testing with retry logging..."
begin
  response = logged_provider.chat_completion(
    messages: [{ role: "user", content: "Test retry logging system." }],
    model: "gpt-4o"
  )
  puts "Success with logging: #{response.dig("choices", 0, "message", "content")}"
rescue StandardError => e
  puts "Failed with logging: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 3: SIMULATING FAILURES
# ============================================================================

puts "3. Simulating failures to test retry logic:"

# Create a mock provider that fails predictably
class FailingProvider
  def initialize(fail_count = 2)
    @fail_count = fail_count
    @attempt = 0
  end

  def chat_completion(messages:, model:, **options)
    @attempt += 1
    
    if @attempt <= @fail_count
      # Simulate different types of failures
      case @attempt
      when 1
        raise RAAF::Models::RateLimitError.new("Rate limit exceeded")
      when 2
        raise RAAF::Models::NetworkError.new("Network timeout")
      else
        raise RAAF::Models::ServerError.new("Internal server error")
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
      ]
    }
  end

  def stream_completion(messages:, model:, **options)
    # Simulate streaming failure
    raise RAAF::Models::NetworkError.new("Streaming connection failed")
  end
end

# Test with failing provider
failing_provider = FailingProvider.new(2)  # Fail 2 times, then succeed
retryable_failing = RAAF::Models::RetryableProviderWrapper.new(
  failing_provider,
  max_attempts: 5,
  base_delay: 0.1,  # Fast for demo
  logger: retry_logger
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
# EXAMPLE 4: AGENT WITH RETRY LOGIC
# ============================================================================

puts "4. Agent with retry logic:"

# Define tools that might fail due to network issues
def unreliable_weather_api(location:)
  # Simulate an unreliable external API
  if rand < 0.3  # 30% chance of failure
    raise StandardError, "Weather API temporarily unavailable"
  end
  
  "Weather in #{location}: Sunny, 22°C"
end

def unreliable_stock_api(symbol:)
  # Simulate another unreliable API
  if rand < 0.4  # 40% chance of failure
    raise StandardError, "Stock API rate limit exceeded"
  end
  
  "Stock price for #{symbol}: $#{rand(100..1000)}"
end

# Create agent with retry-enabled provider
resilient_agent = RAAF::Agent.new(
  name: "ResilientAgent",
  instructions: "You are a resilient agent that handles API failures gracefully. Use the available tools and retry if they fail.",
  model: "gpt-4o"
)

# Add unreliable tools
resilient_agent.add_tool(method(:unreliable_weather_api))
resilient_agent.add_tool(method(:unreliable_stock_api))

# Create runner with retryable provider
resilient_runner = RAAF::Runner.new(
  agent: resilient_agent,
  provider: retryable_provider
)

# Test resilient agent
resilient_messages = [{
  role: "user",
  content: "Get me the weather in Tokyo and the stock price for AAPL. If any API fails, please retry."
}]

resilient_result = resilient_runner.run(resilient_messages)
puts "Resilient agent response: #{resilient_result.final_output}"
puts

# ============================================================================
# EXAMPLE 5: CIRCUIT BREAKER PATTERN
# ============================================================================

puts "5. Circuit breaker pattern:"

# Create a provider with circuit breaker functionality
class CircuitBreakerProvider
  def initialize(base_provider, failure_threshold = 3, recovery_timeout = 30)
    @base_provider = base_provider
    @failure_threshold = failure_threshold
    @recovery_timeout = recovery_timeout
    @failure_count = 0
    @last_failure_time = nil
    @state = :closed  # :closed, :open, :half_open
  end

  def chat_completion(messages:, model:, **options)
    case @state
    when :open
      # Circuit is open, check if we can try again
      if Time.now - @last_failure_time > @recovery_timeout
        @state = :half_open
        puts "Circuit breaker: Moving to half-open state"
      else
        raise RAAF::Models::CircuitBreakerError.new("Circuit breaker is open")
      end
    when :half_open
      # Test if service is recovered
      puts "Circuit breaker: Testing service recovery"
    end

    begin
      result = @base_provider.chat_completion(messages: messages, model: model, **options)
      
      # Success - reset circuit breaker
      if @state == :half_open
        @state = :closed
        @failure_count = 0
        puts "Circuit breaker: Service recovered, closing circuit"
      end
      
      result
    rescue StandardError => e
      @failure_count += 1
      @last_failure_time = Time.now
      
      if @failure_count >= @failure_threshold
        @state = :open
        puts "Circuit breaker: Opening circuit after #{@failure_count} failures"
      end
      
      raise e
    end
  end
end

# Wrap with circuit breaker
circuit_breaker_provider = CircuitBreakerProvider.new(base_providers[:openai])

# Test circuit breaker
puts "Testing circuit breaker pattern..."
begin
  response = circuit_breaker_provider.chat_completion(
    messages: [{ role: "user", content: "Test circuit breaker" }],
    model: "gpt-4o"
  )
  puts "Circuit breaker success: #{response.dig("choices", 0, "message", "content")}"
rescue StandardError => e
  puts "Circuit breaker error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 6: FALLBACK PROVIDER CHAIN
# ============================================================================

puts "6. Fallback provider chain:"

# Create a chain of providers as fallbacks
class FallbackProvider
  def initialize(providers)
    @providers = providers
  end

  def chat_completion(messages:, model:, **options)
    last_error = nil
    
    @providers.each_with_index do |provider_info, index|
      provider = provider_info[:provider]
      fallback_model = provider_info[:model] || model
      
      begin
        puts "Trying provider #{index + 1}: #{provider_info[:name]}"
        return provider.chat_completion(messages: messages, model: fallback_model, **options)
      rescue StandardError => e
        last_error = e
        puts "Provider #{index + 1} failed: #{e.message}"
        next
      end
    end
    
    raise last_error || StandardError.new("All providers failed")
  end
end

# Create fallback chain
fallback_providers = [
  { provider: base_providers[:openai], model: "gpt-4o", name: "OpenAI" }
]

if base_providers[:groq]
  fallback_providers << { provider: base_providers[:groq], model: "llama3-8b-8192", name: "Groq" }
end

if base_providers[:anthropic]
  fallback_providers << { provider: base_providers[:anthropic], model: "claude-3-haiku-20240307", name: "Anthropic" }
end

fallback_provider = FallbackProvider.new(fallback_providers)

puts "Testing fallback provider chain..."
begin
  response = fallback_provider.chat_completion(
    messages: [{ role: "user", content: "Test fallback chain" }],
    model: "gpt-4o"
  )
  puts "Fallback success: #{response.dig("choices", 0, "message", "content")}"
rescue StandardError => e
  puts "All fallback providers failed: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 7: RATE LIMIT HANDLING
# ============================================================================

puts "7. Rate limit handling:"

# Create a rate-limit aware provider
class RateLimitAwareProvider
  def initialize(base_provider, requests_per_minute = 10)
    @base_provider = base_provider
    @requests_per_minute = requests_per_minute
    @request_times = []
  end

  def chat_completion(messages:, model:, **options)
    # Clean old requests
    cutoff_time = Time.now - 60  # 1 minute ago
    @request_times.reject! { |time| time < cutoff_time }
    
    # Check rate limit
    if @request_times.size >= @requests_per_minute
      sleep_time = 60 - (Time.now - @request_times.first)
      puts "Rate limit reached, sleeping for #{sleep_time.round(2)} seconds"
      sleep(sleep_time) if sleep_time > 0
      @request_times.clear
    end
    
    # Record request time
    @request_times << Time.now
    
    # Make request
    @base_provider.chat_completion(messages: messages, model: model, **options)
  end
end

# Test rate limit handling
rate_limited_provider = RateLimitAwareProvider.new(base_providers[:openai], 3)  # 3 requests per minute

puts "Testing rate limit handling (3 requests per minute)..."
4.times do |i|
  begin
    puts "Request #{i + 1}..."
    response = rate_limited_provider.chat_completion(
      messages: [{ role: "user", content: "Request #{i + 1}" }],
      model: "gpt-4o"
    )
    puts "Response #{i + 1}: #{response.dig("choices", 0, "message", "content")}"
  rescue StandardError => e
    puts "Request #{i + 1} failed: #{e.message}"
  end
end

puts

# ============================================================================
# EXAMPLE 8: COMPREHENSIVE RETRY STRATEGY
# ============================================================================

puts "8. Comprehensive retry strategy:"

# Create a production-ready retry strategy
class ProductionRetryProvider
  def initialize(base_provider, config = {})
    @base_provider = base_provider
    @config = {
      max_attempts: 5,
      base_delay: 1.0,
      max_delay: 60.0,
      exponential_base: 2.0,
      jitter: true,
      retryable_errors: [
        RAAF::Models::RateLimitError,
        RAAF::Models::NetworkError,
        RAAF::Models::ServerError
      ]
    }.merge(config)
    
    @logger = Logger.new($stdout)
    @logger.level = Logger::INFO
  end

  def chat_completion(messages:, model:, **options)
    attempt = 0
    
    loop do
      attempt += 1
      
      begin
        return @base_provider.chat_completion(messages: messages, model: model, **options)
      rescue StandardError => e
        # Check if error is retryable
        retryable = @config[:retryable_errors].any? { |error_class| e.is_a?(error_class) }
        
        if !retryable || attempt >= @config[:max_attempts]
          @logger.error("Final failure after #{attempt} attempts: #{e.message}")
          raise e
        end
        
        # Calculate delay with exponential backoff and jitter
        delay = [@config[:base_delay] * (@config[:exponential_base] ** (attempt - 1)), @config[:max_delay]].min
        
        if @config[:jitter]
          delay *= (0.5 + rand * 0.5)  # Add 0-50% jitter
        end
        
        @logger.warn("Attempt #{attempt} failed: #{e.message}. Retrying in #{delay.round(2)}s...")
        sleep(delay)
      end
    end
  end
end

# Test comprehensive retry strategy
production_provider = ProductionRetryProvider.new(base_providers[:openai])

puts "Testing production retry strategy..."
begin
  response = production_provider.chat_completion(
    messages: [{ role: "user", content: "Test production retry strategy" }],
    model: "gpt-4o"
  )
  puts "Production strategy success: #{response.dig("choices", 0, "message", "content")}"
rescue StandardError => e
  puts "Production strategy failed: #{e.message}"
end

puts

# ============================================================================
# CONFIGURATION DISPLAY
# ============================================================================

puts "=== Retryable Provider Configuration ==="
puts "Base providers: #{base_providers.keys.join(", ")}"
puts "Retry strategies: Basic, Logged, Circuit Breaker, Fallback, Rate Limit, Production"
puts "Key features: Exponential backoff, Jitter, Circuit breaker, Fallback chains"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Example Complete ==="
puts
puts "Key Retryable Provider Features:"
puts "1. Exponential backoff with configurable delays"
puts "2. Jitter to prevent thundering herd problems"
puts "3. Circuit breaker pattern for failing services"
puts "4. Fallback provider chains for redundancy"
puts "5. Rate limit awareness and handling"
puts "6. Comprehensive logging and monitoring"
puts "7. Configurable retry strategies"
puts "8. Production-ready error handling"
puts
puts "Best Practices:"
puts "- Configure appropriate retry limits for your use case"
puts "- Use jitter to prevent synchronized retry storms"
puts "- Implement circuit breakers for failing services"
puts "- Set up fallback provider chains for redundancy"
puts "- Monitor retry patterns and adjust strategies"
puts "- Log retry attempts for debugging and analysis"
puts "- Consider cost implications of retry strategies"
puts "- Test retry logic with simulated failures"
puts
puts "Retry Strategy Guidelines:"
puts "- Start with conservative retry counts (3-5 attempts)"
puts "- Use exponential backoff with jitter"
puts "- Implement circuit breakers for cascading failures"
puts "- Set appropriate timeouts for your application"
puts "- Monitor and alert on high retry rates"
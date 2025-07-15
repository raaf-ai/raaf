#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates the unified logging system in OpenAI Agents Ruby.
# The logging system provides centralized, structured logging that automatically
# integrates with Rails when available, supports multiple output formats (text/JSON),
# and includes category-based debug filtering for fine-grained control. This is
# essential for debugging, monitoring, and maintaining AI agent applications in
# production environments.

require_relative "../lib/openai_agents"

puts "=== Unified Logging System Example ==="
puts

# ============================================================================
# EXAMPLE 1: BASIC LOGGING METHODS
# ============================================================================
# The logging system provides standard log levels with structured context.
# Each log entry can include additional key-value pairs for structured analysis.
# The system automatically formats messages consistently across all log levels.

puts "Example 1: Basic Logging Methods"
puts "-" * 50

# Basic logging with context
# Context parameters become structured fields in the log output
OpenAIAgents::Logging.info("Agent initialization started", agent: "GPT-4", run_id: "abc123")
OpenAIAgents::Logging.warn("API rate limit approaching", remaining_requests: 10, window: "1 minute")
OpenAIAgents::Logging.error("Authentication failed", error: "Invalid API key", user_id: "user_456")

# Debug logging with category filtering
# Only shown when the specific category is enabled
OpenAIAgents::Logging.debug("API request details", category: :api, method: "POST", url: "/v1/chat/completions")
OpenAIAgents::Logging.debug("Tool execution", category: :tools, tool: "get_weather", params: { city: "Paris" })

puts "Basic logging messages sent to the configured output"
puts

# ============================================================================
# EXAMPLE 2: LOGGING CONFIGURATION
# ============================================================================
# The logging system supports flexible configuration through environment variables
# or programmatic configuration. This enables adaptation to different environments
# and deployment scenarios without code changes.

puts "Example 2: Logging Configuration"
puts "-" * 50

# Display current configuration
config = OpenAIAgents::Logging.configuration
puts "Current logging configuration:"
puts "  Log level: #{config.log_level}"
puts "  Log format: #{config.log_format}"
puts "  Log output: #{config.log_output}"
puts "  Debug categories: #{config.debug_categories.join(', ')}"
puts

# Configure logging programmatically
# This overrides environment variable settings
OpenAIAgents::Logging.configure do |config|
  config.log_level = :debug          # Show all log levels
  config.log_format = :json          # Use JSON format for structured logging
  config.log_output = :console       # Send to console
  config.debug_categories = [:api, :tracing]  # Enable specific debug categories
end

puts "Updated configuration:"
config = OpenAIAgents::Logging.configuration
puts "  Log level: #{config.log_level}"
puts "  Log format: #{config.log_format}"
puts "  Debug categories: #{config.debug_categories.join(', ')}"
puts

# Test JSON format output
puts "JSON format output example:"
OpenAIAgents::Logging.info("Configuration updated", previous_level: "info", new_level: "debug")
puts

# ============================================================================
# EXAMPLE 3: CATEGORY-BASED DEBUG LOGGING
# ============================================================================
# Debug categories enable fine-grained control over debug output. Different
# categories can be enabled/disabled independently, helping focus on specific
# areas during development and debugging.

puts "Example 3: Category-Based Debug Logging"
puts "-" * 50

# Reset to text format for readability
OpenAIAgents::Logging.configure do |config|
  config.log_format = :text
  config.debug_categories = [:api, :tracing, :tools]
end

# Available debug categories demonstration
debug_categories = [
  { category: :api, message: "OpenAI API call", url: "https://api.openai.com/v1/chat/completions" },
  { category: :tracing, message: "Span created", span_id: "span_123", parent_id: "span_abc" },
  { category: :tools, message: "Tool executed", tool: "calculate", result: "42" },
  { category: :handoff, message: "Agent handoff initiated", from: "Agent1", to: "Agent2" },
  { category: :context, message: "Context updated", context_size: 2048 },
  { category: :http, message: "HTTP request", method: "POST", status: 200 },
  { category: :general, message: "General debug info", info: "Processing step 1" }
]

puts "Debug messages by category:"
debug_categories.each do |item|
  OpenAIAgents::Logging.debug(item[:message], category: item[:category], **item.except(:category, :message))
end

puts "\nNote: Only enabled categories (api, tracing, tools) will show debug messages"
puts

# ============================================================================
# EXAMPLE 4: LOGGER MIXIN USAGE
# ============================================================================
# The Logger mixin provides convenient instance methods for classes that
# frequently need to log. This reduces boilerplate and provides a consistent
# interface across the application.

puts "Example 4: Logger Mixin Usage"
puts "-" * 50

# Example class using the Logger mixin
class WeatherAgent
  include OpenAIAgents::Logger
  
  def initialize(name)
    @name = name
    log_info("Weather agent initialized", agent: @name)
  end
  
  def get_weather(city)
    log_debug_tools("Getting weather", city: city, agent: @name)
    
    # Simulate API call
    begin
      log_debug_api("Weather API call", endpoint: "weather.api.com", city: city)
      weather_data = { city: city, temperature: 22, condition: "sunny" }
      
      log_info("Weather retrieved successfully", city: city, temperature: weather_data[:temperature])
      weather_data
    rescue => e
      log_error("Weather API failed", error: e.message, city: city)
      raise
    end
  end
  
  def process_batch(cities)
    log_info("Starting batch processing", cities: cities.length)
    
    results = []
    cities.each_with_index do |city, index|
      log_debug("Processing city", city: city, index: index, total: cities.length)
      results << get_weather(city)
    end
    
    log_info("Batch processing completed", total_processed: results.length)
    results
  end
end

# Use the weather agent
agent = WeatherAgent.new("WeatherBot")
weather = agent.get_weather("Paris")
puts "Weather result: #{weather}"

# Batch processing example
batch_results = agent.process_batch(["London", "Tokyo", "New York"])
puts "Batch results: #{batch_results.length} cities processed"
puts

# ============================================================================
# EXAMPLE 5: SPECIALIZED LOGGING METHODS
# ============================================================================
# The logging system provides specialized methods for common agent operations.
# These methods use consistent formatting and context, making it easier to
# analyze agent behavior and performance.

puts "Example 5: Specialized Logging Methods"
puts "-" * 50

# Agent lifecycle logging
OpenAIAgents::Logging.agent_start("GPT-4-Assistant", run_id: "run_789", user_id: "user_123")

# Tool execution logging
OpenAIAgents::Logging.tool_call("get_weather", parameters: { city: "Berlin" }, agent: "GPT-4-Assistant")

# Agent handoff logging
OpenAIAgents::Logging.handoff("GeneralAgent", "SpecializedAgent", reason: "requires domain expertise")

# API call logging
OpenAIAgents::Logging.api_call("POST", "https://api.openai.com/v1/chat/completions", 
                                duration: 1.5, tokens: 150)

# Agent completion logging
OpenAIAgents::Logging.agent_end("GPT-4-Assistant", duration: 5.2, tokens_used: 200)

# API error logging
begin
  raise StandardError, "Rate limit exceeded"
rescue => e
  OpenAIAgents::Logging.api_error(e, request_id: "req_456", retry_count: 3)
end

puts "Specialized logging methods demonstrate consistent formatting"
puts

# ============================================================================
# EXAMPLE 6: BENCHMARK LOGGING
# ============================================================================
# The benchmark method provides easy performance monitoring for code blocks.
# It automatically logs execution time and can include additional context
# about the operation being measured.

puts "Example 6: Benchmark Logging"
puts "-" * 50

# Benchmark a simple operation
result = OpenAIAgents::Logging.benchmark("weather_api_call", city: "Stockholm") do
  # Simulate API call
  sleep(0.1)
  { temperature: 18, condition: "cloudy" }
end

puts "Benchmark result: #{result}"

# Benchmark with additional context
batch_result = OpenAIAgents::Logging.benchmark("batch_processing", cities: 5, parallel: false) do
  # Simulate batch processing
  sleep(0.3)
  Array.new(5) { |i| { city: "City#{i}", temperature: 20 + i } }
end

puts "Batch benchmark result: #{batch_result.length} cities"
puts

# ============================================================================
# EXAMPLE 7: DIFFERENT OUTPUT FORMATS
# ============================================================================
# The logging system supports multiple output formats. JSON format is ideal
# for structured logging systems, while text format is more readable for
# development and debugging.

puts "Example 7: Different Output Formats"
puts "-" * 50

puts "Text format (current):"
OpenAIAgents::Logging.info("Processing user request", user_id: "user_789", request_type: "chat")

# Switch to JSON format
OpenAIAgents::Logging.configure { |config| config.log_format = :json }
puts "\nJSON format:"
OpenAIAgents::Logging.info("Processing user request", user_id: "user_789", request_type: "chat")

# Switch back to text format for readability
OpenAIAgents::Logging.configure { |config| config.log_format = :text }
puts "\nBack to text format for remaining examples"
puts

# ============================================================================
# EXAMPLE 8: ENVIRONMENT VARIABLE CONFIGURATION
# ============================================================================
# The logging system can be configured entirely through environment variables,
# making it suitable for containerized deployments and different environments.

puts "Example 8: Environment Variable Configuration"
puts "-" * 50

puts "Available environment variables:"
puts "  OPENAI_AGENTS_LOG_LEVEL: debug, info, warn, error, fatal (default: info)"
puts "  OPENAI_AGENTS_LOG_FORMAT: text, json (default: text)"
puts "  OPENAI_AGENTS_LOG_OUTPUT: console, file, rails, auto (default: auto)"
puts "  OPENAI_AGENTS_LOG_FILE: /path/to/log/file (default: log/openai_agents.log)"
puts "  OPENAI_AGENTS_DEBUG_CATEGORIES: all, none, or comma-separated list (default: all)"
puts

puts "Example usage in different environments:"
puts "  # Development (verbose debugging)"
puts "  export OPENAI_AGENTS_LOG_LEVEL=debug"
puts "  export OPENAI_AGENTS_DEBUG_CATEGORIES=api,tracing,tools"
puts
puts "  # Production (structured logging)"
puts "  export OPENAI_AGENTS_LOG_LEVEL=info"
puts "  export OPENAI_AGENTS_LOG_FORMAT=json"
puts "  export OPENAI_AGENTS_LOG_OUTPUT=file"
puts "  export OPENAI_AGENTS_DEBUG_CATEGORIES=none"
puts
puts "  # Testing (minimal logging)"
puts "  export OPENAI_AGENTS_LOG_LEVEL=warn"
puts "  export OPENAI_AGENTS_LOG_OUTPUT=console"
puts

# ============================================================================
# EXAMPLE 9: RAILS INTEGRATION
# ============================================================================
# When Rails is detected, the logging system automatically integrates with
# Rails.logger, ensuring consistent logging across the application.

puts "Example 9: Rails Integration"
puts "-" * 50

puts "Rails integration features:"
puts "  - Automatic detection of Rails environment"
puts "  - Uses Rails.logger when available"
puts "  - Respects Rails log level configuration"
puts "  - Integrates with Rails logging middleware"
puts "  - Supports Rails log rotation and formatting"
puts

# Simulate Rails environment detection
puts "Rails detection logic:"
if defined?(Rails) && Rails.logger
  puts "  ✓ Rails detected - using Rails.logger"
  puts "  ✓ Rails log level: #{Rails.logger.level}"
  puts "  ✓ Rails log destination: #{Rails.logger.instance_variable_get(:@logdev)&.dev}"
else
  puts "  ✗ Rails not detected - using console logger"
  puts "  ✓ Fallback to console output"
end
puts

# ============================================================================
# EXAMPLE 10: PRODUCTION MONITORING INTEGRATION
# ============================================================================
# Structured logging enables integration with monitoring systems like
# Datadog, New Relic, or ELK stack. The consistent format makes it easy
# to create dashboards and alerts.

puts "Example 10: Production Monitoring Integration"
puts "-" * 50

# Configure for production monitoring
OpenAIAgents::Logging.configure do |config|
  config.log_format = :json
  config.log_level = :info
  config.debug_categories = [:none]  # Disable debug in production
end

# Examples of monitoring-friendly log entries
OpenAIAgents::Logging.info("agent_request_started", 
                          agent: "GPT-4", 
                          user_id: "user_123", 
                          request_id: "req_456",
                          timestamp: Time.now.iso8601)

OpenAIAgents::Logging.info("agent_request_completed",
                          agent: "GPT-4",
                          user_id: "user_123", 
                          request_id: "req_456",
                          duration_ms: 1500,
                          tokens_used: 200,
                          success: true)

OpenAIAgents::Logging.error("agent_request_failed",
                           agent: "GPT-4",
                           user_id: "user_123",
                           request_id: "req_456", 
                           error: "Rate limit exceeded",
                           duration_ms: 800,
                           retry_count: 3)

puts "Production monitoring logs are structured for analysis"
puts

# Reset to text format for summary
OpenAIAgents::Logging.configure { |config| config.log_format = :text }

# ============================================================================
# EXAMPLE 11: CUSTOM LOGGING PATTERNS
# ============================================================================
# Advanced usage patterns for specific scenarios like debugging complex
# multi-agent workflows, tracking user sessions, and performance monitoring.

puts "Example 11: Custom Logging Patterns"
puts "-" * 50

class MultiAgentWorkflow
  include OpenAIAgents::Logger
  
  def initialize(workflow_id)
    @workflow_id = workflow_id
    @step_count = 0
    log_info("Workflow started", workflow_id: @workflow_id)
  end
  
  def execute_step(step_name, agent_name)
    @step_count += 1
    step_id = "step_#{@step_count}"
    
    log_info("Step started", 
             workflow_id: @workflow_id,
             step_id: step_id,
             step_name: step_name,
             agent: agent_name)
    
    # Simulate step execution with error handling
    begin
      log_benchmark("step_execution", 
                   workflow_id: @workflow_id,
                   step_id: step_id) do
        # Simulate work
        sleep(0.05)
        "Step #{step_name} completed"
      end
      
      log_info("Step completed",
               workflow_id: @workflow_id,
               step_id: step_id,
               success: true)
    rescue => e
      log_error("Step failed",
                workflow_id: @workflow_id,
                step_id: step_id,
                error: e.message)
      raise
    end
  end
  
  def complete
    log_info("Workflow completed",
             workflow_id: @workflow_id,
             total_steps: @step_count,
             success: true)
  end
end

# Example multi-agent workflow
workflow = MultiAgentWorkflow.new("wf_#{SecureRandom.hex(4)}")
workflow.execute_step("analyze_input", "AnalysisAgent")
workflow.execute_step("generate_response", "GenerationAgent")
workflow.execute_step("validate_output", "ValidationAgent")
workflow.complete

puts "Custom logging patterns enable workflow tracking"
puts

# ============================================================================
# BEST PRACTICES SUMMARY
# ============================================================================

puts "=== Unified Logging Best Practices ==="
puts "-" * 50
puts <<~PRACTICES
  1. Configuration:
     - Use environment variables for deployment configuration
     - Set appropriate log levels for each environment
     - Enable debug categories selectively in development
     - Use JSON format for production monitoring
  
  2. Structured Logging:
     - Include relevant context in every log entry
     - Use consistent key names across the application
     - Add request IDs for tracing distributed operations
     - Include timing information for performance analysis
  
  3. Debug Categories:
     - Enable specific categories during development
     - Disable debug logging in production
     - Use meaningful category names
     - Document available categories for team members
  
  4. Error Handling:
     - Log errors with full context
     - Include stack traces for debugging
     - Add retry information for failed operations
     - Use appropriate log levels for different error types
  
  5. Performance Monitoring:
     - Use benchmark logging for critical operations
     - Log duration and resource usage
     - Include performance metrics in structured logs
     - Set up alerts for performance degradation
  
  6. Rails Integration:
     - Let the system auto-detect Rails environment
     - Configure through Rails configuration when needed
     - Use Rails log rotation and management
     - Integrate with Rails middleware for request tracking
  
  7. Production Considerations:
     - Use structured (JSON) logging for analysis
     - Set up log aggregation and monitoring
     - Configure appropriate log retention policies
     - Monitor log volume and performance impact
  
  8. Security:
     - Never log sensitive information (API keys, passwords)
     - Sanitize user input before logging
     - Use secure log storage and transmission
     - Implement proper access controls for logs
PRACTICES

puts "\nUnified logging system example completed!"
puts "The logging system provides comprehensive, structured logging for OpenAI Agents applications."
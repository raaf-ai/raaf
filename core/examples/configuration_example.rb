#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates configuration management for production deployments.
# Proper configuration is essential for deploying AI agents across different
# environments (development, staging, production) with appropriate settings
# for API keys, model parameters, logging, monitoring, and security constraints.
# This example shows centralized configuration, environment-specific overrides,
# and validation patterns.

require_relative "../lib/raaf-core"

# ============================================================================
# CONFIGURATION SYSTEM SETUP
# ============================================================================

puts "=== Configuration Management for Production Deployments ==="
puts "=" * 65

# Check current environment configuration
current_env = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || ENV["ENVIRONMENT"] || "development"
puts "🔧 Current environment: #{current_env}"

# ============================================================================
# CENTRALIZED CONFIGURATION CLASS
# ============================================================================

# Comprehensive configuration management system for RAAF.
# Handles environment-specific settings, validation, and secure credential management.
class OpenAIAgentsConfig

  attr_reader :environment, :config_data

  def initialize(environment = nil)
    @environment = environment || detect_environment
    @config_data = load_configuration
    validate_configuration!
  end

  # Core API Configuration
  def openai_api_key
    get_secure_value("openai.api_key", "OPENAI_API_KEY")
  end

  def openai_api_base
    get_value("openai.api_base", "OPENAI_API_BASE", default: "https://api.openai.com/v1")
  end

  def default_model
    get_value("openai.default_model", "OPENAI_DEFAULT_MODEL", default: "gpt-4o")
  end

  def request_timeout
    get_value("openai.timeout", "OPENAI_TIMEOUT", default: 120).to_i
  end

  # Provider Configuration
  def anthropic_api_key
    get_secure_value("anthropic.api_key", "ANTHROPIC_API_KEY")
  end

  def groq_api_key
    get_secure_value("groq.api_key", "GROQ_API_KEY")
  end

  def together_api_key
    get_secure_value("together.api_key", "TOGETHER_API_KEY")
  end

  # Agent Behavior Configuration
  def default_max_turns
    get_value("agents.max_turns", "AGENT_MAX_TURNS", default: 10).to_i
  end

  def default_temperature
    get_value("agents.temperature", "AGENT_TEMPERATURE", default: 0.7).to_f
  end

  def agent_timeout
    get_value("agents.timeout", "AGENT_TIMEOUT", default: 300).to_i
  end

  # Retry Configuration
  def retry_max_attempts
    get_value("retry.max_attempts", "RETRY_MAX_ATTEMPTS", default: 3).to_i
  end

  def retry_base_delay
    get_value("retry.base_delay", "RETRY_BASE_DELAY", default: 1.0).to_f
  end

  def retry_max_delay
    get_value("retry.max_delay", "RETRY_MAX_DELAY", default: 60.0).to_f
  end

  # Logging Configuration
  def log_level
    get_value("logging.level", "LOG_LEVEL", default: production? ? "info" : "debug")
  end

  def log_format
    get_value("logging.format", "LOG_FORMAT", default: production? ? "json" : "text")
  end

  def debug_categories
    categories = get_value("logging.debug_categories", "DEBUG_CATEGORIES", default: "")
    categories.split(",").map(&:strip).reject(&:empty?)
  end

  # Tracing Configuration
  def tracing_enabled?
    get_boolean("tracing.enabled", "TRACING_ENABLED", default: true)
  end

  def openai_tracing_enabled?
    get_boolean("tracing.openai.enabled", "OPENAI_TRACING_ENABLED", default: false)
  end

  def console_tracing_enabled?
    get_boolean("tracing.console.enabled", "CONSOLE_TRACING_ENABLED", default: !production?)
  end

  # Security Configuration
  def rate_limit_requests_per_minute
    get_value("security.rate_limit.requests_per_minute", "RATE_LIMIT_RPM", default: production? ? 60 : 1000).to_i
  end

  def enable_code_execution?
    get_boolean("security.code_execution.enabled", "CODE_EXECUTION_ENABLED", default: !production?)
  end

  def allowed_file_extensions
    extensions = get_value("security.file_upload.allowed_extensions", "ALLOWED_FILE_EXTENSIONS",
                           default: "txt,pdf,json,csv")
    extensions.split(",").map(&:strip)
  end

  def max_file_size_mb
    get_value("security.file_upload.max_size_mb", "MAX_FILE_SIZE_MB", default: 10).to_i
  end

  # Memory Store Configuration
  def memory_store_type
    get_value("memory.store_type", "MEMORY_STORE_TYPE", default: "in_memory")
  end

  def memory_store_path
    get_value("memory.store_path", "MEMORY_STORE_PATH", default: "./memory")
  end

  def memory_ttl_hours
    get_value("memory.ttl_hours", "MEMORY_TTL_HOURS", default: 24).to_i
  end

  # Cost Management
  def daily_cost_limit
    get_value("costs.daily_limit", "DAILY_COST_LIMIT", default: 100.0).to_f
  end

  def cost_alert_threshold
    get_value("costs.alert_threshold", "COST_ALERT_THRESHOLD", default: 0.8).to_f
  end

  def token_usage_tracking?
    get_boolean("costs.token_tracking", "TOKEN_TRACKING_ENABLED", default: true)
  end

  # Environment helpers
  def development?
    @environment == "development"
  end

  def staging?
    @environment == "staging"
  end

  def production?
    @environment == "production"
  end

  def test?
    @environment == "test"
  end

  # Configuration validation
  def valid?
    @validation_errors.empty?
  end

  def validation_errors
    @validation_errors ||= []
  end

  # Export configuration for debugging
  def to_h(include_secrets: false)
    config_hash = {
      environment: @environment,
      openai: {
        api_base: openai_api_base,
        default_model: default_model,
        timeout: request_timeout
      },
      agents: {
        max_turns: default_max_turns,
        temperature: default_temperature,
        timeout: agent_timeout
      },
      retry: {
        max_attempts: retry_max_attempts,
        base_delay: retry_base_delay,
        max_delay: retry_max_delay
      },
      logging: {
        level: log_level,
        format: log_format,
        debug_categories: debug_categories
      },
      tracing: {
        enabled: tracing_enabled?,
        openai: openai_tracing_enabled?,
        console: console_tracing_enabled?
      },
      security: {
        rate_limit_rpm: rate_limit_requests_per_minute,
        code_execution: enable_code_execution?,
        allowed_extensions: allowed_file_extensions,
        max_file_size_mb: max_file_size_mb
      },
      memory: {
        store_type: memory_store_type,
        store_path: memory_store_path,
        ttl_hours: memory_ttl_hours
      },
      costs: {
        daily_limit: daily_cost_limit,
        alert_threshold: cost_alert_threshold,
        token_tracking: token_usage_tracking?
      }
    }

    if include_secrets
      config_hash[:api_keys] = {
        openai: openai_api_key ? "***#{openai_api_key[-4..]}" : nil,
        anthropic: anthropic_api_key ? "***#{anthropic_api_key[-4..]}" : nil,
        groq: groq_api_key ? "***#{groq_api_key[-4..]}" : nil,
        together: together_api_key ? "***#{together_api_key[-4..]}" : nil
      }
    end

    config_hash
  end

  private

  def detect_environment
    ENV["RAILS_ENV"] || ENV["RACK_ENV"] || ENV["ENVIRONMENT"] || "development"
  end

  def load_configuration
    config = {}

    # Load from configuration files if they exist
    config_file = "config/openai_agents.yml"
    if File.exist?(config_file)
      require "yaml"
      file_config = YAML.load_file(config_file)
      config.merge!(file_config[@environment] || {}) if file_config
    end

    # Environment-specific overrides
    env_config_file = "config/raaf_#{@environment}.yml"
    if File.exist?(env_config_file)
      require "yaml"
      env_config = YAML.load_file(env_config_file)
      config.merge!(env_config)
    end

    config
  end

  def get_value(config_path, env_var, default: nil)
    # Priority: Environment variable > Configuration file > Default
    ENV[env_var] || get_nested_value(config_path) || default
  end

  def get_secure_value(config_path, env_var)
    # For sensitive values, prefer environment variables
    ENV[env_var] || get_nested_value(config_path)
  end

  def get_boolean(config_path, env_var, default: false)
    value = get_value(config_path, env_var, default: default.to_s)
    %w[true yes 1 on enabled].include?(value.to_s.downcase)
  end

  def get_nested_value(path)
    keys = path.split(".")
    keys.reduce(@config_data) { |config, key| config.is_a?(Hash) ? config[key] : nil }
  end

  def validate_configuration!
    @validation_errors = []

    # Required API keys for production
    @validation_errors << "OpenAI API key is required in production" if production? && (openai_api_key.nil? || openai_api_key.empty?)

    # Validate timeout values
    @validation_errors << "Request timeout must be positive" if request_timeout <= 0
    @validation_errors << "Agent timeout must be positive" if agent_timeout <= 0

    # Validate retry configuration
    @validation_errors << "Retry max attempts must be between 1 and 10" unless (1..10).include?(retry_max_attempts)
    @validation_errors << "Retry base delay must be positive" if retry_base_delay <= 0

    # Validate memory configuration
    valid_store_types = %w[in_memory file redis]
    @validation_errors << "Invalid memory store type" unless valid_store_types.include?(memory_store_type)

    # Validate cost limits
    @validation_errors << "Daily cost limit must be positive" if daily_cost_limit <= 0
    @validation_errors << "Cost alert threshold must be between 0 and 1" unless (0..1).include?(cost_alert_threshold)

    # Validate rate limiting
    @validation_errors << "Rate limit must be positive" if rate_limit_requests_per_minute <= 0
  end

end

# ============================================================================
# CONFIGURATION FACTORY AND MANAGEMENT
# ============================================================================

# Configuration factory for different deployment scenarios
class ConfigurationFactory

  def self.create_for_environment(env = nil)
    config = OpenAIAgentsConfig.new(env)

    puts "✅ Configuration loaded for environment: #{config.environment}"
    puts "   Valid: #{config.valid?}"

    unless config.valid?
      puts "   ⚠️  Validation errors:"
      config.validation_errors.each { |error| puts "      - #{error}" }
    end

    config
  end

  def self.create_development_config
    # Override with development-friendly defaults
    ENV["LOG_LEVEL"] = "debug"
    ENV["DEBUG_CATEGORIES"] = "api,tracing"
    ENV["CONSOLE_TRACING_ENABLED"] = "true"
    ENV["CODE_EXECUTION_ENABLED"] = "true"
    ENV["RATE_LIMIT_RPM"] = "1000"

    create_for_environment("development")
  end

  def self.create_production_config
    # Production security defaults
    ENV["LOG_LEVEL"] = "info"
    ENV["LOG_FORMAT"] = "json"
    ENV["DEBUG_CATEGORIES"] = ""
    ENV["CONSOLE_TRACING_ENABLED"] = "false"
    ENV["CODE_EXECUTION_ENABLED"] = "false"
    ENV["RATE_LIMIT_RPM"] = "60"

    create_for_environment("production")
  end

  def self.create_test_config
    # Test environment defaults
    ENV["LOG_LEVEL"] = "warn"
    ENV["TRACING_ENABLED"] = "false"
    ENV["TOKEN_TRACKING_ENABLED"] = "false"
    ENV["DAILY_COST_LIMIT"] = "10"

    create_for_environment("test")
  end

end

puts "✅ Configuration management system loaded"

# ============================================================================
# CONFIGURATION DEMONSTRATION
# ============================================================================

puts "\n=== Configuration Examples by Environment ==="
puts "-" * 55

# Demonstrate different environment configurations
environments = %w[development staging production test]

environments.each do |env|
  puts "\n#{env.upcase} Environment Configuration:"

  # Create environment-specific configuration
  config = case env
           when "development"
             ConfigurationFactory.create_development_config
           when "production"
             ConfigurationFactory.create_production_config
           when "test"
             ConfigurationFactory.create_test_config
           else
             ConfigurationFactory.create_for_environment(env)
           end

  # Display key configuration values
  puts "   Model: #{config.default_model}"
  puts "   Log level: #{config.log_level}"
  puts "   Tracing: #{config.tracing_enabled? ? "enabled" : "disabled"}"
  puts "   Code execution: #{config.enable_code_execution? ? "enabled" : "disabled"}"
  puts "   Rate limit: #{config.rate_limit_requests_per_minute} req/min"
  puts "   Max turns: #{config.default_max_turns}"
  puts "   Daily cost limit: $#{config.daily_cost_limit}"

  # Show API key status
  api_key_status = config.openai_api_key ? "configured" : "missing"
  puts "   OpenAI API key: #{api_key_status}"
end

# ============================================================================
# AGENT CONFIGURATION WITH SETTINGS
# ============================================================================

puts "\n=== Agent Configuration with Centralized Settings ==="
puts "-" * 55

# Create configured agent using centralized settings
config = ConfigurationFactory.create_for_environment(current_env)

def create_configured_agent(config, agent_name, custom_settings = {})
  puts "🤖 Creating configured agent: #{agent_name}"

  # Merge configuration with custom settings
  agent_config = {
    name: agent_name,
    model: config.default_model,
    max_turns: config.default_max_turns,
    **custom_settings
  }

  # Apply environment-specific constraints
  if config.production?
    agent_config[:max_turns] = [agent_config[:max_turns], 5].min # Limit in production
    agent_config[:instructions] = "#{agent_config[:instructions]} Keep responses concise for production use."
  end

  agent = RAAF::Agent.new(**agent_config)

  puts "   Model: #{agent.model}"
  puts "   Max turns: #{agent.max_turns}"
  puts "   Tools: #{agent.tools.length}"

  agent
end

# Create agents with different configurations
agents = {}

agents[:customer_service] = create_configured_agent(
  config,
  "CustomerService",
  {
    instructions: "You are a customer service agent. Be helpful and professional.",
    max_turns: config.production? ? 3 : 8
  }
)

agents[:technical_support] = create_configured_agent(
  config,
  "TechnicalSupport",
  {
    instructions: "You provide technical support. Be precise and thorough.",
    model: config.production? ? "gpt-4o-mini" : "gpt-4o" # Cost optimization in production
  }
)

agents[:data_analyst] = create_configured_agent(
  config,
  "DataAnalyst",
  {
    instructions: "You analyze data and provide insights. Use tools when appropriate.",
    max_turns: 15 # Data analysis may need more turns
  }
)

puts "✅ Created #{agents.length} configured agents"

# ============================================================================
# PROVIDER CONFIGURATION
# ============================================================================

puts "\n=== Provider Configuration and Selection ==="
puts "-" * 55

# Configure providers based on configuration settings
def configure_providers(config)
  providers = {}

  # OpenAI Provider (primary) - DEPRECATED, use default ResponsesProvider instead
  if config.openai_api_key
    puts "⚠️  DEPRECATED: Using OpenAIProvider for demonstration purposes"
    openai_provider = RAAF::Models::OpenAIProvider.new( # DEPRECATED
      api_key: config.openai_api_key,
      api_base: config.openai_api_base
    )

    # ✅ Configure retry behavior - built into all providers via ModelInterface
    puts "✅ Configuring retry behavior (built into ModelInterface)"
    
    # Configure retry settings based on configuration
    openai_provider.configure_retry(
      max_attempts: config.retry_max_attempts,
      base_delay: config.retry_base_delay,
      max_delay: config.retry_max_delay,
      multiplier: 2.0,
      jitter: 0.1
    )

    providers[:openai] = openai_provider

    puts "✅ OpenAI provider configured with retry logic (#{config.retry_max_attempts} attempts max)"
  end

  # Anthropic Provider (backup)
  if config.anthropic_api_key
    begin
      anthropic_provider = RAAF::Models::AnthropicProvider.new(
        api_key: config.anthropic_api_key
      )
      providers[:anthropic] = anthropic_provider
      puts "✅ Anthropic provider configured"
    rescue StandardError => e
      puts "⚠️  Anthropic provider configuration failed: #{e.message}"
    end
  end

  # Groq Provider (fast inference)
  if config.groq_api_key
    begin
      groq_provider = RAAF::Models::GroqProvider.new(
        api_key: config.groq_api_key
      )
      providers[:groq] = groq_provider
      puts "✅ Groq provider configured"
    rescue StandardError => e
      puts "⚠️  Groq provider configuration failed: #{e.message}"
    end
  end

  providers
end

# Configure available providers
available_providers = configure_providers(config)

if available_providers.empty?
  puts "⚠️  No providers configured - using demo mode"
  puts "   Set API keys in environment variables for full functionality"
else
  puts "📡 Available providers: #{available_providers.keys.join(", ")}"
end

# ============================================================================
# RUNNER CONFIGURATION WITH MONITORING
# ============================================================================

puts "\n=== Runner Configuration with Monitoring ==="
puts "-" * 55

# Configure runners with tracing and monitoring based on settings
def create_configured_runner(agent, config, provider_name = :openai)
  puts "🏃 Creating configured runner for: #{agent.name}"

  # Select provider
  provider = case provider_name
             when :openai
               if config.openai_api_key
                 RAAF::Models::OpenAIProvider.new(
                   api_key: config.openai_api_key,
                   api_base: config.openai_api_base
                 )
               else
                 puts "   ⚠️  No OpenAI API key, using demo provider"
                 DemoProvider.new
               end
             else
               puts "   ⚠️  Provider #{provider_name} not configured"
               DemoProvider.new
             end

  # Configure tracing if enabled
  tracer = nil
  if config.tracing_enabled?
    tracer = RAAF.tracer

    # Add console processor for development
    tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new) if config.console_tracing_enabled?

    # Add OpenAI processor if configured
    tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new) if config.openai_tracing_enabled? && config.openai_api_key

    puts "   📊 Tracing enabled with #{tracer.processors.length} processors"
  end

  # Create runner with configuration
  runner = RAAF::Runner.new(
    agent: agent,
    provider: provider,
    tracer: tracer
  )

  puts "   Provider: #{provider.class.name}"
  puts "   Tracing: #{config.tracing_enabled? ? "enabled" : "disabled"}"

  runner
end

# Demo provider for when API keys aren't available
class DemoProvider < RAAF::Models::ModelInterface

  def chat_completion(messages:, model:, **_kwargs)
    {
      choices: [{
        message: {
          role: "assistant",
          content: "This is a demo response. Set your API keys for live functionality."
        }
      }],
      usage: {
        prompt_tokens: 10,
        completion_tokens: 15,
        total_tokens: 25
      }
    }
  end

  def stream_completion(messages:, model:)
    content = "Demo streaming response"
    content.each_char { |char| yield char if block_given? }
    chat_completion(messages: messages, model: model)
  end

  def provider_name
    "Demo"
  end

  def supported_models
    ["demo-model"]
  end

end

# Create configured runners
configured_runners = {}

agents.each do |name, agent|
  configured_runners[name] = create_configured_runner(agent, config)
end

puts "✅ Created #{configured_runners.length} configured runners"

# ============================================================================
# ENVIRONMENT-SPECIFIC FEATURES
# ============================================================================

puts "\n=== Environment-Specific Feature Configuration ==="
puts "-" * 55

# Configure features based on environment
puts "🔧 Environment-specific features for #{config.environment}:"

# Development environment features
if config.development?
  puts "   🛠️  Development features enabled:"
  puts "      • Debug logging with categories: #{config.debug_categories.join(", ")}"
  puts "      • Console tracing for real-time debugging"
  puts "      • Code execution enabled for testing"
  puts "      • Relaxed rate limiting (#{config.rate_limit_requests_per_minute} req/min)"
  puts "      • Extended timeout values for debugging"
end

# Staging environment features
if config.staging?
  puts "   🧪 Staging features enabled:"
  puts "      • Production-like configuration with extended logging"
  puts "      • Moderate rate limiting"
  puts "      • Full tracing for integration testing"
  puts "      • Cost monitoring and alerts"
end

# Production environment features
if config.production?
  puts "   🚀 Production features enabled:"
  puts "      • JSON logging for structured monitoring"
  puts "      • Strict rate limiting (#{config.rate_limit_requests_per_minute} req/min)"
  puts "      • Code execution disabled for security"
  puts "      • Cost limits and monitoring enabled"
  puts "      • Minimal debug output"
  puts "      • OpenAI tracing for production insights"
end

# Test environment features
if config.test?
  puts "   🧪 Test features enabled:"
  puts "      • Minimal logging to reduce test noise"
  puts "      • Tracing disabled for faster tests"
  puts "      • Lower cost limits for test safety"
  puts "      • Simplified configuration validation"
end

# ============================================================================
# CONFIGURATION VALIDATION AND HEALTH CHECK
# ============================================================================

puts "\n=== Configuration Health Check ==="
puts "-" * 55

# Comprehensive configuration health check
def perform_health_check(config, providers, runners)
  puts "🏥 Performing configuration health check..."

  health_status = {
    configuration: true,
    providers: true,
    agents: true,
    security: true,
    monitoring: true,
    warnings: []
  }

  # Configuration validation
  if config.valid?
    puts "   ✅ Configuration is valid"
  else
    health_status[:configuration] = false
    puts "   ❌ Configuration validation failed:"
    config.validation_errors.each { |error| puts "      - #{error}" }
  end

  # Provider health
  if providers.empty?
    health_status[:providers] = false
    health_status[:warnings] << "No providers configured - running in demo mode"
    puts "   ⚠️  No providers available"
  else
    puts "   ✅ Providers available: #{providers.keys.join(", ")}"
  end

  # Agent configuration
  if runners.any?
    puts "   ✅ Agents configured: #{runners.keys.join(", ")}"
  else
    health_status[:agents] = false
    puts "   ❌ No agents configured"
  end

  # Security checks
  security_issues = []

  if config.production?
    security_issues << "Code execution enabled in production" if config.enable_code_execution?
    security_issues << "Debug logging enabled in production" if config.log_level == "debug"
    security_issues << "Console tracing enabled in production" if config.console_tracing_enabled?
  end

  if security_issues.any?
    health_status[:security] = false
    puts "   ⚠️  Security concerns:"
    security_issues.each { |issue| puts "      - #{issue}" }
  else
    puts "   ✅ Security configuration appropriate"
  end

  # Monitoring setup
  monitoring_features = []
  monitoring_features << "tracing" if config.tracing_enabled?
  monitoring_features << "cost tracking" if config.token_usage_tracking?
  monitoring_features << "rate limiting" if config.rate_limit_requests_per_minute.positive?

  if monitoring_features.any?
    puts "   ✅ Monitoring enabled: #{monitoring_features.join(", ")}"
  else
    health_status[:monitoring] = false
    puts "   ⚠️  Limited monitoring configured"
  end

  # Overall health
  overall_health = health_status.values.all?(true)
  puts "\n📊 Overall health: #{overall_health ? "✅ HEALTHY" : "⚠️  NEEDS ATTENTION"}"

  if health_status[:warnings].any?
    puts "   Warnings:"
    health_status[:warnings].each { |warning| puts "      - #{warning}" }
  end

  health_status
end

# Run health check
health_result = perform_health_check(config, available_providers, configured_runners)

# ============================================================================
# CONFIGURATION EXPORT AND DOCUMENTATION
# ============================================================================

puts "\n=== Configuration Export and Documentation ==="
puts "-" * 55

# Export configuration for documentation and debugging
puts "📋 Current configuration summary:"

config_summary = config.to_h(include_secrets: false)
config_summary.each do |section, values|
  puts "\n#{section.to_s.upcase}:"
  if values.is_a?(Hash)
    values.each { |key, value| puts "   #{key}: #{value}" }
  else
    puts "   #{values}"
  end
end

# Generate environment variable documentation
puts "\n📝 Environment Variables Reference:"
env_vars = {
  "OPENAI_API_KEY" => "OpenAI API key (required for production)",
  "OPENAI_API_BASE" => "OpenAI API base URL (default: https://api.openai.com/v1)",
  "OPENAI_DEFAULT_MODEL" => "Default OpenAI model (default: gpt-4o)",
  "LOG_LEVEL" => "Logging level: debug, info, warn, error (default: info)",
  "LOG_FORMAT" => "Log format: text, json (default: text)",
  "DEBUG_CATEGORIES" => "Debug categories: api,tracing,tools (comma-separated)",
  "TRACING_ENABLED" => "Enable tracing: true/false (default: true)",
  "RATE_LIMIT_RPM" => "Rate limit requests per minute (default: 60)",
  "CODE_EXECUTION_ENABLED" => "Enable code execution: true/false (default: false in production)",
  "DAILY_COST_LIMIT" => "Daily cost limit in USD (default: 100)",
  "MEMORY_STORE_TYPE" => "Memory store: in_memory, file, redis (default: in_memory)"
}

env_vars.each do |var, description|
  current_value = ENV[var] ? "SET" : "unset"
  puts "   #{var}: #{description} [#{current_value}]"
end

# ============================================================================
# PRODUCTION DEPLOYMENT CHECKLIST
# ============================================================================

puts "\n=== Production Deployment Checklist ==="
puts "-" * 55

checklist_items = [
  { item: "OpenAI API key configured", check: !config.openai_api_key.nil? },
  { item: "JSON logging enabled", check: config.log_format == "json" },
  { item: "Debug logging disabled", check: config.log_level != "debug" },
  { item: "Code execution disabled", check: !config.enable_code_execution? },
  { item: "Rate limiting configured", check: config.rate_limit_requests_per_minute <= 100 },
  { item: "Cost limits set", check: config.daily_cost_limit.positive? },
  { item: "Tracing enabled", check: config.tracing_enabled? },
  { item: "Retry logic configured", check: config.retry_max_attempts.positive? },
  { item: "Timeout values appropriate", check: config.request_timeout.positive? && config.request_timeout < 300 },
  { item: "Security validation passed", check: health_result[:security] }
]

puts "✅ Production readiness checklist:"
checklist_items.each do |item|
  status = item[:check] ? "✅" : "❌"
  puts "   #{status} #{item[:item]}"
end

ready_count = checklist_items.count { |item| item[:check] }
total_count = checklist_items.length

puts "\n📊 Production readiness: #{ready_count}/#{total_count} checks passed"

if ready_count == total_count
  puts "🚀 Ready for production deployment!"
else
  puts "⚠️  Address remaining items before deploying to production"
end

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Configuration Management Example Complete! ==="
puts "\nKey Features Demonstrated:"
puts "• Centralized configuration management with environment overrides"
puts "• Secure credential handling and validation"
puts "• Environment-specific feature configuration"
puts "• Provider and agent configuration patterns"
puts "• Configuration health checks and validation"

puts "\nConfiguration Capabilities:"
puts "• Multi-environment support (development, staging, production, test)"
puts "• Environment variable and file-based configuration"
puts "• Security and production readiness validation"
puts "• Comprehensive logging and tracing configuration"
puts "• Rate limiting and cost management settings"

puts "\nProduction Best Practices:"
puts "• Environment-specific security constraints"
puts "• Structured logging for monitoring integration"
puts "• Comprehensive health checks and validation"
puts "• Clear documentation of required environment variables"
puts "• Production deployment readiness assessment"

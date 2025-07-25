**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Configuration Reference
============================

This is a comprehensive reference for all RAAF configuration options, environment variables, and settings. Use this guide to properly configure RAAF for your specific environment and requirements.

After reading this reference, you will know:

* All available configuration options and their defaults
* Environment variable formats and examples
* Configuration patterns for different deployment scenarios
* Security considerations for configuration management
* Performance tuning through configuration
* Troubleshooting configuration issues

--------------------------------------------------------------------------------

Global Configuration
---------------------

### RAAF.configure Block

The primary way to configure RAAF is through the global configuration block:

```ruby
# config/initializers/raaf.rb
RAAF.configure do |config|
  # Core settings
  config.default_model = "gpt-4o-mini"
  config.default_provider = :openai
  config.max_retries = 3
  config.timeout = 30
  
  # Logging
  config.log_level = :info
  config.debug_categories = [:api, :agents]
  config.structured_logging = true
  
  # Performance
  config.connection_pool_size = 10
  config.max_concurrent_agents = 100
  config.response_cache_enabled = true
  
  # Security
  config.api_key_validation = true
  config.rate_limiting_enabled = true
  config.guardrails_enabled = true
end
```

### Configuration Options Reference

#### Core Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `default_model` | String | `"gpt-4o-mini"` | Default AI model for new agents |
| `default_provider` | Symbol/Class | `:openai` | Default provider for API calls |
| `max_retries` | Integer | `3` | Maximum retry attempts for failed requests |
| `timeout` | Integer | `30` | Request timeout in seconds |
| `max_turns` | Integer | `25` | Maximum conversation turns per session |
| `execute_tools` | Boolean | `true` | Whether agents automatically execute tools |

**Example:**

```ruby
config.default_model = "claude-3-5-sonnet-20241022"
config.default_provider = RAAF::Models::AnthropicProvider.new
config.max_retries = 5
config.timeout = 60
```

#### Logging Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `log_level` | Symbol | `:info` | Logging level (`:debug`, `:info`, `:warn`, `:error`) |
| `debug_categories` | Array | `[]` | Categories to enable debug logging for |
| `structured_logging` | Boolean | `false` | Enable JSON structured logging |
| `log_requests` | Boolean | `true` | Log all API requests |
| `log_responses` | Boolean | `false` | Log API responses (security risk) |
| `log_tool_calls` | Boolean | `true` | Log tool executions |
| `log_errors` | Boolean | `true` | Log errors and exceptions |

**Example:**

```ruby
config.log_level = :debug
config.debug_categories = [:api, :agents, :tools, :memory, :tracing]
config.structured_logging = true
config.log_requests = true
config.log_responses = false  # Don't log sensitive response data
```

#### Performance Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `connection_pool_size` | Integer | `10` | HTTP connection pool size per provider |
| `max_concurrent_agents` | Integer | `100` | Maximum concurrent agent executions |
| `response_cache_enabled` | Boolean | `false` | Enable response caching |
| `cache_ttl` | Integer | `3600` | Cache TTL in seconds |
| `cache_size` | String | `"100MB"` | Maximum cache size |
| `gc_optimization` | Symbol | `:balanced` | GC optimization mode (`:memory`, `:latency`, `:throughput`) |

**Example:**

```ruby
config.connection_pool_size = 20
config.max_concurrent_agents = 200
config.response_cache_enabled = true
config.cache_ttl = 1.hour
config.cache_size = "500MB"
config.gc_optimization = :throughput
```

#### Security Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `api_key_validation` | Boolean | `true` | Validate API keys on startup |
| `rate_limiting_enabled` | Boolean | `false` | Enable built-in rate limiting |
| `rate_limit_requests` | Integer | `100` | Requests per minute per user |
| `guardrails_enabled` | Boolean | `false` | Enable content guardrails |
| `content_filtering` | Boolean | `false` | Enable content filtering |
| `pii_detection` | Boolean | `false` | Enable PII detection |
| `audit_logging` | Boolean | `false` | Enable audit trail logging |

**Example:**

```ruby
config.api_key_validation = true
config.rate_limiting_enabled = true
config.rate_limit_requests = 60  # 60 requests per minute
config.guardrails_enabled = true
config.pii_detection = true
config.audit_logging = true
```

Environment Variables
---------------------

### Core Environment Variables

#### API Keys and Authentication

```bash
# Required - AI Provider API Keys
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GROQ_API_KEY="gsk_..."
export COHERE_API_KEY="..."
export TOGETHER_API_KEY="..."

# Optional - Organization/Project IDs
export OPENAI_ORG_ID="org-..."
export OPENAI_PROJECT_ID="proj_..."

# Application Security
export SECRET_KEY_BASE="your-very-long-secret-key"
export RAAF_API_TOKEN="secure-api-token"
export RAAF_DASHBOARD_AUTH_TOKEN="dashboard-auth-token"
```

#### Core Configuration

```bash
# Model and Provider Settings
export RAAF_DEFAULT_MODEL="gpt-4o-mini"
export RAAF_DEFAULT_PROVIDER="openai"
export RAAF_MAX_RETRIES="3"
export RAAF_TIMEOUT="30"
export RAAF_MAX_TURNS="25"

# Execution Settings
export RAAF_EXECUTE_TOOLS="true"
export RAAF_PARALLEL_TOOL_CALLS="true"
export RAAF_MAX_CONCURRENT_AGENTS="100"
```

#### Logging Configuration

```bash
# Logging Levels and Categories
export RAAF_LOG_LEVEL="info"                    # debug, info, warn, error
export RAAF_DEBUG_CATEGORIES="api,agents,tools" # Comma-separated list
export RAAF_STRUCTURED_LOGGING="true"           # Enable JSON logging
export RAAF_LOG_REQUESTS="true"
export RAAF_LOG_RESPONSES="false"               # Security: don't log responses
export RAAF_LOG_TOOL_CALLS="true"
export RAAF_LOG_ERRORS="true"

# Log Destinations
export RAAF_LOG_FILE="/var/log/raaf/application.log"
export RAAF_ERROR_LOG_FILE="/var/log/raaf/errors.log"
export RAAF_AUDIT_LOG_FILE="/var/log/raaf/audit.log"
```

#### Performance and Caching

```bash
# Connection and Pooling
export RAAF_CONNECTION_POOL_SIZE="10"
export RAAF_CONNECTION_TIMEOUT="30"
export RAAF_READ_TIMEOUT="60"
export RAAF_WRITE_TIMEOUT="60"

# Caching Configuration
export RAAF_CACHE_ENABLED="true"
export RAAF_CACHE_TTL="3600"                    # 1 hour in seconds
export RAAF_CACHE_SIZE="100MB"
export RAAF_CACHE_STORE="redis"                 # redis, memory, file
export RAAF_CACHE_URL="redis://localhost:6379/2"

# Memory Management
export RAAF_GC_OPTIMIZATION="balanced"          # memory, latency, throughput, balanced
export RAAF_MAX_MEMORY_USAGE="2GB"
```

#### Database and Storage

```bash
# Database Configuration
export DATABASE_URL="postgresql://user:pass@host:5432/raaf_production"
export RAAF_DATABASE_POOL_SIZE="25"
export RAAF_DATABASE_TIMEOUT="5"

# Redis Configuration
export REDIS_URL="redis://localhost:6379/1"
export RAAF_REDIS_NAMESPACE="raaf"
export RAAF_REDIS_POOL_SIZE="10"

# File Storage
export RAAF_STORAGE_PATH="/var/lib/raaf"
export RAAF_TEMP_PATH="/tmp/raaf"
export RAAF_LOG_PATH="/var/log/raaf"
```

### Feature-Specific Environment Variables

#### Memory Management

```bash
# Memory Store Configuration
export RAAF_MEMORY_STORE="file"                 # memory, file, database, vector
export RAAF_MEMORY_MAX_TOKENS="4000"
export RAAF_MEMORY_PRUNING_STRATEGY="sliding_window"  # sliding_window, semantic_similarity
export RAAF_MEMORY_DIRECTORY="/var/lib/raaf/memory"

# Vector Store Configuration (if using vector memory)
export RAAF_VECTOR_STORE="openai"               # openai, pinecone, weaviate
export RAAF_EMBEDDING_MODEL="text-embedding-3-small"
export RAAF_VECTOR_DIMENSION="1536"
export RAAF_SIMILARITY_THRESHOLD="0.7"
export PINECONE_API_KEY="your-pinecone-key"     # If using Pinecone
export PINECONE_INDEX_NAME="raaf-memory"
```

#### Tracing and Monitoring

```bash
# Tracing Configuration
export RAAF_TRACING_ENABLED="true"
export RAAF_TRACE_SAMPLING_RATE="1.0"           # 1.0 = 100%, 0.1 = 10%
export RAAF_TRACE_PROCESSOR="openai"            # openai, console, datadog, otel

# OpenAI Tracing (sends to OpenAI dashboard)
export RAAF_OPENAI_TRACING_ENABLED="true"
export RAAF_OPENAI_BATCH_SIZE="100"
export RAAF_OPENAI_FLUSH_INTERVAL="30"          # seconds

# OpenTelemetry Configuration
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4317"
export OTEL_SERVICE_NAME="raaf-agents"
export OTEL_RESOURCE_ATTRIBUTES="service.version=1.0.0,deployment.environment=production"

# External Monitoring
export SENTRY_DSN="https://your-sentry-dsn"
export DATADOG_API_KEY="your-datadog-key"
export NEW_RELIC_LICENSE_KEY="your-newrelic-key"
```

#### Guardrails and Security

```bash
# Guardrails Configuration
export RAAF_GUARDRAILS_ENABLED="true"
export RAAF_PII_DETECTION_ENABLED="true"
export RAAF_CONTENT_MODERATION_ENABLED="true"
export RAAF_TOXICITY_DETECTION_ENABLED="true"

# PII Detection Settings
export RAAF_PII_DETECTION_MODEL="en_core_web_sm"
export RAAF_PII_CONFIDENCE_THRESHOLD="0.8"
export RAAF_PII_MASK_DETECTED="true"

# Content Moderation
export RAAF_MODERATION_MODEL="text-moderation-latest"
export RAAF_MODERATION_CATEGORIES="hate,harassment,violence"
export RAAF_MODERATION_THRESHOLD="0.7"

# Rate Limiting
export RAAF_RATE_LIMITING_ENABLED="true"
export RAAF_RATE_LIMIT_REQUESTS="100"           # Per minute
export RAAF_RATE_LIMIT_WINDOW="60"              # Seconds
export RAAF_RATE_LIMIT_STORE="redis"            # redis, memory
```

#### Tools and Extensions

```bash
# Web Search Tools
export RAAF_WEB_SEARCH_ENABLED="true"
export TAVILY_API_KEY="your-tavily-key"
export SERP_API_KEY="your-serp-key"
export RAAF_SEARCH_RESULTS_LIMIT="10"

# Code Execution Tools
export RAAF_CODE_EXECUTION_ENABLED="true"
export RAAF_CODE_EXECUTION_TIMEOUT="30"
export RAAF_CODE_EXECUTION_MEMORY_LIMIT="512MB"
export RAAF_CODE_EXECUTION_SANDBOXED="true"

# File System Tools
export RAAF_FILE_TOOLS_ENABLED="true"
export RAAF_FILE_TOOLS_ALLOWED_PATHS="/app/uploads,/tmp/raaf"
export RAAF_FILE_TOOLS_MAX_SIZE="10MB"

# Database Tools
export RAAF_DATABASE_TOOLS_ENABLED="false"      # Disable by default for security
export RAAF_DATABASE_TOOLS_READ_ONLY="true"
```

#### Cost Management

```bash
# Budget Controls
export RAAF_COST_TRACKING_ENABLED="true"
export RAAF_MONTHLY_BUDGET="1000.00"            # USD
export RAAF_DAILY_BUDGET="35.00"                # USD
export RAAF_COST_ALERT_THRESHOLDS="50,75,90,95" # Percentage thresholds

# Token Management
export RAAF_TOKEN_OPTIMIZATION_ENABLED="true"
export RAAF_MAX_TOKENS_PER_REQUEST="4000"
export RAAF_CONTEXT_COMPRESSION_ENABLED="true"
export RAAF_SMART_MODEL_SELECTION="true"

# Provider Routing
export RAAF_COST_AWARE_ROUTING="true"
export RAAF_PREFER_CHEAPER_PROVIDERS_THRESHOLD="0.75"  # Switch when >75% budget used
```

Configuration Patterns
-----------------------

### Development Environment

```ruby
# config/environments/development.rb
RAAF.configure do |config|
  # Use cheaper models for development
  config.default_model = "gpt-4o-mini"
  
  # Enable detailed logging
  config.log_level = :debug
  config.debug_categories = [:api, :agents, :tools]
  config.structured_logging = false  # Human-readable logs
  
  # Disable expensive features
  config.tracing_enabled = false
  config.response_cache_enabled = false
  config.guardrails_enabled = false
  
  # Lower limits for development
  config.max_concurrent_agents = 10
  config.timeout = 15
  
  # Use in-memory stores
  config.memory_store = :memory
  config.cache_store = :memory
end
```

### Test Environment

```ruby
# config/environments/test.rb
RAAF.configure do |config|
  # Use mock provider for tests
  config.default_provider = RAAF::Testing::MockProvider.new
  
  # Minimal logging
  config.log_level = :warn
  config.structured_logging = false
  
  # Disable external dependencies
  config.tracing_enabled = false
  config.response_cache_enabled = false
  config.guardrails_enabled = false
  
  # Fast execution
  config.timeout = 5
  config.max_retries = 1
  
  # In-memory everything
  config.memory_store = :memory
  config.cache_store = :memory
end
```

### Staging Environment

```ruby
# config/environments/staging.rb
RAAF.configure do |config|
  # Production-like models but cheaper
  config.default_model = "gpt-4o-mini"
  
  # Moderate logging
  config.log_level = :info
  config.structured_logging = true
  config.debug_categories = [:errors]
  
  # Enable most features
  config.tracing_enabled = true
  config.response_cache_enabled = true
  config.guardrails_enabled = true
  
  # Production-like limits but lower
  config.max_concurrent_agents = 50
  config.timeout = 30
  
  # Use Redis for persistence
  config.memory_store = :file
  config.cache_store = :redis
  
  # Lower budgets for staging
  config.monthly_budget = 100.00
end
```

### Production Environment

```ruby
# config/environments/production.rb
RAAF.configure do |config|
  # High-quality models
  config.default_model = "gpt-4o"
  
  # Structured logging for analysis
  config.log_level = :info
  config.structured_logging = true
  config.debug_categories = []  # No debug in production
  
  # Enable all production features
  config.tracing_enabled = true
  config.response_cache_enabled = true
  config.guardrails_enabled = true
  config.audit_logging = true
  
  # Production limits
  config.max_concurrent_agents = 200
  config.timeout = 60
  config.max_retries = 3
  
  # Persistent storage
  config.memory_store = :database
  config.cache_store = :redis
  
  # Cost controls
  config.cost_tracking_enabled = true
  config.monthly_budget = 5000.00
  config.cost_aware_routing = true
  
  # Security
  config.api_key_validation = true
  config.rate_limiting_enabled = true
  config.pii_detection = true
  
  # Performance optimization
  config.connection_pool_size = 25
  config.gc_optimization = :throughput
end
```

Advanced Configuration
-----------------------

### Custom Provider Configuration

```ruby
# Custom provider with specific settings
RAAF.configure do |config|
  config.providers = {
    primary: RAAF::Models::ResponsesProvider.new(
      api_key: ENV['OPENAI_API_KEY'],
      timeout: 30,
      max_retries: 3,
      base_url: "https://api.openai.com/v1"
    ),
    
    backup: RAAF::Models::AnthropicProvider.new(
      api_key: ENV['ANTHROPIC_API_KEY'],
      timeout: 45,
      max_retries: 2
    ),
    
    fast: RAAF::Models::GroqProvider.new(
      api_key: ENV['GROQ_API_KEY'],
      timeout: 10,
      max_retries: 1
    )
  }
  
  # Provider routing strategy
  config.provider_routing = :cost_aware  # :round_robin, :least_latency, :cost_aware
end
```

### Memory Configuration

```ruby
RAAF.configure do |config|
  config.memory_manager = RAAF::Memory::MemoryManager.new(
    store: RAAF::Memory::DatabaseStore.new(
      model: AgentMemory,
      session_column: 'session_id',
      content_column: 'content',
      metadata_column: 'metadata'
    ),
    max_tokens: 8000,
    pruning_strategy: :semantic_similarity,
    context_variables: {
      preserve_system_messages: true,
      preserve_recent_count: 5
    }
  )
end
```

### Tracing Configuration

```ruby
RAAF.configure do |config|
  config.tracer = RAAF::Tracing::SpanTracer.new(
    service_name: "raaf-production",
    processors: [
      RAAF::Tracing::OpenAIProcessor.new(
        api_key: ENV['OPENAI_API_KEY'],
        project_id: ENV['OPENAI_PROJECT_ID'],
        batch_size: 100,
        flush_interval: 30.seconds
      ),
      RAAF::Tracing::DatadogProcessor.new(
        api_key: ENV['DATADOG_API_KEY'],
        service_name: "raaf-agents"
      )
    ]
  )
end
```

Configuration Validation
-------------------------

### Built-in Validation

RAAF includes built-in configuration validation:

```ruby
# This will raise an error if configuration is invalid
RAAF.validate_configuration!

# Check specific configuration aspects
RAAF.validate_api_keys!
RAAF.validate_providers!
RAAF.validate_memory_configuration!
```

### Custom Validation

```ruby
# config/initializers/raaf_validation.rb
Rails.application.config.after_initialize do
  # Validate required environment variables
  required_vars = %w[OPENAI_API_KEY DATABASE_URL REDIS_URL]
  missing_vars = required_vars.select { |var| ENV[var].blank? }
  
  if missing_vars.any?
    raise "Missing required environment variables: #{missing_vars.join(', ')}"
  end
  
  # Validate model availability
  RAAF.validate_model_availability!(RAAF.configuration.default_model)
  
  # Validate budget configuration
  if RAAF.configuration.cost_tracking_enabled && RAAF.configuration.monthly_budget.blank?
    Rails.logger.warn "Cost tracking enabled but no monthly budget set"
  end
  
  # Validate memory configuration
  if RAAF.configuration.memory_store == :database && !defined?(ActiveRecord)
    raise "Database memory store requires ActiveRecord"
  end
end
```

Environment-Specific Files
---------------------------

### Configuration Files

```yaml
# config/raaf.yml
development:
  default_model: "gpt-4o-mini"
  log_level: "debug"
  tracing_enabled: false
  cache_enabled: false
  
test:
  default_model: "mock"
  log_level: "warn"
  tracing_enabled: false
  cache_enabled: false
  
staging:
  default_model: "gpt-4o-mini"
  log_level: "info"
  tracing_enabled: true
  cache_enabled: true
  monthly_budget: 100.0
  
production:
  default_model: "gpt-4o"
  log_level: "info"
  tracing_enabled: true
  cache_enabled: true
  monthly_budget: 5000.0
  guardrails_enabled: true
```

### Loading Configuration Files

```ruby
# config/initializers/raaf.rb
raaf_config = Rails.application.config_for(:raaf)

RAAF.configure do |config|
  config.default_model = raaf_config['default_model']
  config.log_level = raaf_config['log_level'].to_sym
  config.tracing_enabled = raaf_config['tracing_enabled']
  config.response_cache_enabled = raaf_config['cache_enabled']
  config.monthly_budget = raaf_config['monthly_budget']
  config.guardrails_enabled = raaf_config['guardrails_enabled']
end
```

Security Considerations
-----------------------

### Sensitive Configuration

**Never commit sensitive data to version control:**

```ruby
# ❌ BAD - Never do this
RAAF.configure do |config|
  config.openai_api_key = "sk-1234567890abcdef"  # DON'T COMMIT API KEYS
end

# ✅ GOOD - Use environment variables
RAAF.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY']
end
```

### Configuration Encryption

For additional security, encrypt sensitive configuration:

```ruby
# config/credentials.yml.enc (Rails encrypted credentials)
openai:
  api_key: sk-encrypted-key-here
  
anthropic:
  api_key: sk-ant-encrypted-key-here

# Access in configuration
RAAF.configure do |config|
  config.openai_api_key = Rails.application.credentials.openai[:api_key]
  config.anthropic_api_key = Rails.application.credentials.anthropic[:api_key]
end
```

### Environment Variable Validation

```ruby
# config/initializers/raaf_security.rb
class RAafSecurityValidator
  def self.validate!
    validate_api_key_format!
    validate_no_development_keys_in_production!
    validate_secure_endpoints!
  end
  
  private
  
  def self.validate_api_key_format!
    openai_key = ENV['OPENAI_API_KEY']
    if openai_key && !openai_key.start_with?('sk-')
      raise "Invalid OpenAI API key format"
    end
    
    anthropic_key = ENV['ANTHROPIC_API_KEY']
    if anthropic_key && !anthropic_key.start_with?('sk-ant-')
      raise "Invalid Anthropic API key format"
    end
  end
  
  def self.validate_no_development_keys_in_production!
    if Rails.env.production?
      test_patterns = [/test/, /demo/, /sample/, /example/]
      
      ENV.each do |key, value|
        next unless key.include?('API_KEY')
        
        if test_patterns.any? { |pattern| value&.match?(pattern) }
          raise "Development/test API key detected in production: #{key}"
        end
      end
    end
  end
  
  def self.validate_secure_endpoints!
    if Rails.env.production?
      %w[OPENAI_BASE_URL ANTHROPIC_BASE_URL].each do |var|
        url = ENV[var]
        next unless url
        
        unless url.start_with?('https://')
          raise "Insecure endpoint in production: #{var} must use HTTPS"
        end
      end
    end
  end
end

# Validate on startup
RAafSecurityValidator.validate! if Rails.env.production?
```

Troubleshooting Configuration
-----------------------------

### Common Configuration Issues

#### 1. API Key Not Found

```ruby
# Error: RAAF::Errors::AuthenticationError: API key not configured

# Solution: Check environment variable
puts ENV['OPENAI_API_KEY']  # Should not be nil

# Verify in configuration
RAAF.configure do |config|
  config.openai_api_key = ENV.fetch('OPENAI_API_KEY') do
    raise "OPENAI_API_KEY environment variable is required"
  end
end
```

#### 2. Model Not Available

```ruby
# Error: RAAF::Errors::ModelNotAvailableError: Model 'gpt-5' not found

# Solution: Check model name and provider support
provider = RAAF::Models::ResponsesProvider.new
available_models = provider.list_models
puts "Available models: #{available_models}"

# Use a valid model
config.default_model = "gpt-4o"
```

#### 3. Connection Issues

```ruby
# Error: Net::TimeoutError or connection refused

# Solution: Check network configuration
RAAF.configure do |config|
  config.timeout = 60        # Increase timeout
  config.max_retries = 5     # More retries
  config.connection_pool_size = 5  # Smaller pool
end

# Test connectivity
provider = RAAF::Models::ResponsesProvider.new
begin
  provider.list_models
  puts "Connection successful"
rescue => e
  puts "Connection failed: #{e.message}"
end
```

#### 4. Memory Configuration Issues

```ruby
# Error: Database connection issues with database memory store

# Solution: Verify database configuration
if RAAF.configuration.memory_store == :database
  begin
    ActiveRecord::Base.connection.execute("SELECT 1")
    puts "Database connection OK"
  rescue => e
    puts "Database connection failed: #{e.message}"
    # Fallback to file store
    RAAF.configuration.memory_store = :file
  end
end
```

### Configuration Debugging

```ruby
# Debug current configuration
def debug_raaf_configuration
  config = RAAF.configuration
  
  puts "=== RAAF Configuration Debug ==="
  puts "Default Model: #{config.default_model}"
  puts "Default Provider: #{config.default_provider}"
  puts "Log Level: #{config.log_level}"
  puts "Tracing Enabled: #{config.tracing_enabled}"
  puts "Cache Enabled: #{config.response_cache_enabled}"
  puts "Guardrails Enabled: #{config.guardrails_enabled}"
  puts "Memory Store: #{config.memory_store}"
  puts "Max Concurrent Agents: #{config.max_concurrent_agents}"
  puts "Timeout: #{config.timeout}"
  puts "Max Retries: #{config.max_retries}"
  
  # Test API connectivity
  begin
    provider = config.default_provider.is_a?(Class) ? config.default_provider.new : config.default_provider
    models = provider.list_models
    puts "API Connection: ✅ SUCCESS (#{models.size} models available)"
  rescue => e
    puts "API Connection: ❌ FAILED (#{e.message})"
  end
  
  # Test memory configuration
  begin
    memory_manager = RAAF::Memory::MemoryManager.new(
      store: RAAF::Memory.const_get("#{config.memory_store.to_s.camelize}Store").new
    )
    puts "Memory Store: ✅ SUCCESS"
  rescue => e
    puts "Memory Store: ❌ FAILED (#{e.message})"
  end
  
  puts "==============================="
end

# Call in Rails console or add to initializer
debug_raaf_configuration if Rails.env.development?
```

Next Steps
----------

For related configuration topics:

* **[RAAF Core Guide](core_guide.html)** - Basic agent and runner configuration
* **[Performance Guide](performance_guide.html)** - Performance-related configuration
* **[Security Guide](guardrails_guide.html)** - Security configuration options
* **[Best Practices](best_practices.html)** - Configuration best practices
* **[Troubleshooting Guide](troubleshooting.html)** - Configuration problem resolution
**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Best Practices Guide
=========================

This guide provides comprehensive best practices for building, deploying, and maintaining production AI agent systems with RAAF. Following these patterns will help you create robust, secure, and maintainable AI applications.

After reading this guide, you will know:

* How to organize and structure RAAF applications
* Security best practices for AI agent systems
* Performance optimization techniques
* Error handling and monitoring strategies
* Testing patterns for AI systems
* Deployment and operational excellence practices

--------------------------------------------------------------------------------

Application Structure
--------------------

### Project Organization

Structure your RAAF applications for maintainability and scalability:

```
app/
├── agents/
│   ├── base_agent.rb
│   ├── customer_service_agent.rb
│   └── research_agent.rb
├── tools/
│   ├── base_tool.rb
│   ├── database_tool.rb
│   └── web_search_tool.rb
├── guardrails/
│   ├── custom_security_guardrail.rb
│   └── content_filter.rb
├── services/
│   ├── agent_orchestrator.rb
│   └── conversation_manager.rb
└── config/
    ├── agents.yml
    └── providers.yml
```

### Agent Design Patterns

#### Single Responsibility Principle
Each agent should have a clear, focused purpose:

```ruby
# Good: Focused agent
class CustomerServiceAgent < BaseAgent
  def initialize
    super(
      name: "CustomerService",
      instructions: "Help customers with order inquiries and returns",
      model: "gpt-4o"
    )
    
    add_tool(method(:lookup_order))
    add_tool(method(:process_return))
  end
end

# Avoid: Overly broad agent
class SuperAgent < BaseAgent
  # Too many responsibilities
end
```

#### Agent Composition
Use composition for complex workflows:

```ruby
class OrderProcessingOrchestrator
  def initialize
    @customer_service = CustomerServiceAgent.new
    @inventory_agent = InventoryAgent.new
    @fulfillment_agent = FulfillmentAgent.new
  end
  
  def process_order(order_data)
    # Orchestrate multiple agents
    validation = @customer_service.validate_order(order_data)
    return validation unless validation.success?
    
    inventory = @inventory_agent.check_availability(order_data)
    return inventory unless inventory.success?
    
    @fulfillment_agent.fulfill_order(order_data)
  end
end
```

Security Best Practices
-----------------------

### Input Validation and Sanitization

Always validate and sanitize user inputs:

```ruby
class SecureAgent
  def initialize
    super
    
    # Add comprehensive guardrails
    self.guardrails = RAAF::ParallelGuardrails.new([
      RAAF::Guardrails::PIIDetector.new(action: :redact),
      RAAF::Guardrails::SecurityGuardrail.new,
      RAAF::Guardrails::ContentFilter.new,
      CustomSecurityGuardrail.new
    ])
  end
end

class CustomSecurityGuardrail < RAAF::Guardrails::Base
  def process_input(input)
    # Validate input length
    return error("Input too long") if input.length > 10000
    
    # Check for suspicious patterns
    return error("Suspicious content") if contains_injection_patterns?(input)
    
    success(input)
  end
  
  private
  
  def contains_injection_patterns?(input)
    dangerous_patterns = [
      /system\s*:/i,
      /ignore\s+previous\s+instructions/i,
      /\{\{.*\}\}/,
      /<script.*>/i
    ]
    
    dangerous_patterns.any? { |pattern| input.match?(pattern) }
  end
end
```

### API Key Management

Never hardcode API keys or expose them in logs:

```ruby
# Good: Environment variables
class SecureProvider
  def initialize
    @api_key = ENV.fetch('OPENAI_API_KEY') do
      raise "OPENAI_API_KEY environment variable not set"
    end
  end
end

# Good: Encrypted configuration
class EncryptedConfig
  def self.api_key
    Rails.application.credentials.openai_api_key
  end
end

# Avoid: Hardcoded keys
class BadProvider
  API_KEY = "sk-..." # Never do this
end
```

### Secure Tool Development

Implement tools with security in mind:

```ruby
class DatabaseTool
  def initialize
    @connection = establish_secure_connection
  end
  
  def query_orders(user_id:, limit: 10)
    # Validate inputs
    return error("Invalid user_id") unless valid_user_id?(user_id)
    return error("Invalid limit") unless limit.between?(1, 100)
    
    # Use parameterized queries
    query = "SELECT * FROM orders WHERE user_id = ? LIMIT ?"
    @connection.execute(query, [user_id, limit])
  rescue ActiveRecord::RecordNotFound
    []
  rescue => e
    # Log error securely (don't expose sensitive data)
    Rails.logger.error("Database query failed: #{e.class}")
    error("Database query failed")
  end
  
  private
  
  def valid_user_id?(user_id)
    user_id.is_a?(Integer) && user_id > 0
  end
end
```

Performance Optimization
-----------------------

### Connection Pooling

Use connection pooling for AI providers:

```ruby
class OptimizedProvider
  def initialize
    @connection_pool = ConnectionPool.new(size: 10, timeout: 5) do
      OpenAI::Client.new(
        access_token: ENV['OPENAI_API_KEY'],
        request_timeout: 30
      )
    end
  end
  
  def generate_response(messages)
    @connection_pool.with do |client|
      client.chat(
        model: "gpt-4o",
        messages: messages,
        max_tokens: 1000
      )
    end
  end
end
```

### Caching Strategies

Implement intelligent caching:

```ruby
class CachedAgent
  def initialize
    @cache = ActiveSupport::Cache::RedisStore.new
    @cache_ttl = 1.hour
  end
  
  def process_request(input)
    cache_key = generate_cache_key(input)
    
    cached_response = @cache.read(cache_key)
    return cached_response if cached_response
    
    response = generate_response(input)
    @cache.write(cache_key, response, expires_in: @cache_ttl)
    response
  end
  
  private
  
  def generate_cache_key(input)
    # Hash input for consistent keys
    Digest::SHA256.hexdigest([
      input,
      @agent.name,
      @agent.model,
      @agent.instructions
    ].join(":"))
  end
end
```

### Memory Management

Optimize memory usage for long-running agents:

```ruby
class MemoryOptimizedAgent
  def initialize
    super
    
    # Configure memory with pruning
    self.memory = RAAF::Memory::Manager.new(
      backend: RAAF::Memory::RedisBackend.new,
      max_entries: 1000,
      pruning_strategy: :fifo,
      compression: :gzip
    )
  end
  
  def process_conversation(messages)
    # Prune old messages if needed
    prune_old_messages if memory.size > 800
    
    # Process with current context
    result = run(messages.last)
    
    # Clean up temporary data
    cleanup_temporary_data
    
    result
  end
  
  private
  
  def prune_old_messages
    memory.prune(keep_count: 500)
  end
  
  def cleanup_temporary_data
    # Remove temporary files, clear caches, etc.
    GC.start if rand < 0.1 # Occasional garbage collection
  end
end
```

Error Handling and Monitoring
----------------------------

### Comprehensive Error Handling

Implement robust error handling:

```ruby
class ResilientAgent
  def initialize
    super
    
    # Configure retry logic
    @retry_config = {
      max_retries: 3,
      base_delay: 1.0,
      max_delay: 30.0,
      exponential_base: 2
    }
  end
  
  def process_with_retry(input)
    attempt = 0
    
    begin
      attempt += 1
      process_request(input)
    rescue RAAF::RateLimitError => e
      if attempt <= @retry_config[:max_retries]
        delay = calculate_retry_delay(attempt)
        Rails.logger.warn("Rate limited, retrying in #{delay}s (attempt #{attempt})")
        sleep(delay)
        retry
      else
        handle_final_error(e, "Rate limit exceeded after #{attempt} attempts")
      end
    rescue RAAF::ProviderError => e
      if attempt <= @retry_config[:max_retries]
        Rails.logger.warn("Provider error, retrying (attempt #{attempt}): #{e.message}")
        sleep(calculate_retry_delay(attempt))
        retry
      else
        handle_final_error(e, "Provider error after #{attempt} attempts")
      end
    rescue => e
      handle_final_error(e, "Unexpected error")
    end
  end
  
  private
  
  def calculate_retry_delay(attempt)
    base_delay = @retry_config[:base_delay]
    max_delay = @retry_config[:max_delay]
    exponential_base = @retry_config[:exponential_base]
    
    delay = base_delay * (exponential_base ** (attempt - 1))
    [delay, max_delay].min
  end
  
  def handle_final_error(error, context)
    Rails.logger.error("#{context}: #{error.class} - #{error.message}")
    
    # Send to monitoring service
    ErrorReporter.report(error, context: context)
    
    # Return graceful fallback
    {
      success: false,
      error: "Service temporarily unavailable",
      retry_after: 60
    }
  end
end
```

### Monitoring and Observability

Implement comprehensive monitoring:

```ruby
class MonitoredAgent
  def initialize
    super
    
    # Set up comprehensive tracing
    self.tracer = RAAF::Tracing::SpanTracer.new.tap do |tracer|
      tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)
      tracer.add_processor(RAAF::Tracing::PrometheusProcessor.new)
      tracer.add_processor(custom_metrics_processor)
    end
  end
  
  def process_request(input)
    start_time = Time.current
    
    begin
      result = super(input)
      
      # Record success metrics
      record_success_metrics(start_time, result)
      result
    rescue => e
      # Record error metrics
      record_error_metrics(start_time, e)
      raise
    end
  end
  
  private
  
  def custom_metrics_processor
    @custom_processor ||= CustomMetricsProcessor.new
  end
  
  def record_success_metrics(start_time, result)
    duration = Time.current - start_time
    
    Rails.logger.info({
      event: "agent_request_success",
      agent: name,
      duration: duration,
      tokens_used: result.usage&.total_tokens,
      cost: calculate_cost(result.usage)
    }.to_json)
  end
  
  def record_error_metrics(start_time, error)
    duration = Time.current - start_time
    
    Rails.logger.error({
      event: "agent_request_error",
      agent: name,
      duration: duration,
      error_class: error.class.name,
      error_message: error.message
    }.to_json)
  end
end
```

Testing Patterns
---------------

### Unit Testing Agents

Test agents with mock providers:

```ruby
RSpec.describe CustomerServiceAgent do
  let(:mock_provider) { instance_double(RAAF::Providers::OpenAI) }
  let(:agent) { described_class.new(provider: mock_provider) }
  
  describe "#lookup_order" do
    it "returns order information" do
      order_data = { id: "12345", status: "shipped" }
      
      allow(mock_provider).to receive(:generate_response).and_return(
        double(content: "Your order #12345 is shipped", usage: double(total_tokens: 50))
      )
      
      result = agent.lookup_order("12345")
      
      expect(result).to include("shipped")
      expect(mock_provider).to have_received(:generate_response)
    end
  end
  
  describe "#process_return" do
    it "handles return requests" do
      allow(mock_provider).to receive(:generate_response).and_return(
        double(content: "Return initiated", usage: double(total_tokens: 30))
      )
      
      result = agent.process_return(order_id: "12345", reason: "defective")
      
      expect(result).to include("Return initiated")
    end
  end
end
```

### Integration Testing

Test complete workflows:

```ruby
RSpec.describe "Order Processing Workflow" do
  let(:orchestrator) { OrderProcessingOrchestrator.new }
  
  it "processes orders end-to-end" do
    VCR.use_cassette("order_processing") do
      order_data = {
        customer_id: 123,
        items: [{ sku: "ABC123", quantity: 2 }],
        shipping_address: valid_address
      }
      
      result = orchestrator.process_order(order_data)
      
      expect(result).to be_success
      expect(result.order_id).to be_present
      expect(result.tracking_number).to be_present
    end
  end
end
```

### Performance Testing

Test system performance:

```ruby
RSpec.describe "Agent Performance" do
  let(:agent) { CustomerServiceAgent.new }
  
  it "handles concurrent requests" do
    threads = []
    results = []
    
    10.times do
      threads << Thread.new do
        result = agent.process_request("Help with order status")
        results << result
      end
    end
    
    threads.each(&:join)
    
    expect(results.size).to eq(10)
    expect(results.all?(&:success?)).to be true
  end
  
  it "maintains response times under load" do
    response_times = []
    
    100.times do
      start_time = Time.current
      agent.process_request("Quick question")
      response_times << (Time.current - start_time)
    end
    
    average_time = response_times.sum / response_times.size
    expect(average_time).to be < 2.0 # seconds
  end
end
```

Deployment and Operations
------------------------

### Configuration Management

Use environment-based configuration:

```ruby
# config/agents.yml
development:
  customer_service:
    model: "gpt-3.5-turbo"
    max_tokens: 500
    temperature: 0.7
  
production:
  customer_service:
    model: "gpt-4o"
    max_tokens: 1000
    temperature: 0.5
    guardrails:

      - pii_detector
      - security_guardrail
```

```ruby
class ConfigurableAgent
  def initialize
    config = Rails.application.config.agents[:customer_service]
    
    super(
      name: "CustomerService",
      model: config[:model],
      instructions: load_instructions,
      max_tokens: config[:max_tokens],
      temperature: config[:temperature]
    )
    
    setup_guardrails(config[:guardrails])
  end
  
  private
  
  def setup_guardrails(guardrail_names)
    return unless guardrail_names
    
    guardrails = guardrail_names.map do |name|
      "RAAF::Guardrails::#{name.camelize}".constantize.new
    end
    
    self.guardrails = RAAF::ParallelGuardrails.new(guardrails)
  end
end
```

### Health Checks

Implement comprehensive health checks:

```ruby
class HealthChecker
  def self.check_all
    {
      database: check_database,
      redis: check_redis,
      providers: check_providers,
      agents: check_agents
    }
  end
  
  def self.check_providers
    providers = {
      openai: check_openai,
      anthropic: check_anthropic
    }
    
    {
      status: providers.values.all? { |p| p[:status] == :healthy } ? :healthy : :degraded,
      details: providers
    }
  end
  
  def self.check_agents
    agent = CustomerServiceAgent.new
    
    start_time = Time.current
    result = agent.process_request("Health check")
    duration = Time.current - start_time
    
    {
      status: result.success? ? :healthy : :unhealthy,
      response_time: duration,
      last_checked: Time.current
    }
  rescue => e
    {
      status: :unhealthy,
      error: e.message,
      last_checked: Time.current
    }
  end
end
```

### Graceful Degradation

Implement fallback strategies:

```ruby
class ResilientAgentSystem
  def initialize
    @primary_agent = PrimaryAgent.new
    @fallback_agent = FallbackAgent.new
    @circuit_breaker = CircuitBreaker.new(
      failure_threshold: 5,
      recovery_timeout: 60
    )
  end
  
  def process_request(input)
    if @circuit_breaker.open?
      Rails.logger.warn("Circuit breaker open, using fallback")
      return @fallback_agent.process_request(input)
    end
    
    begin
      result = @primary_agent.process_request(input)
      @circuit_breaker.record_success
      result
    rescue => e
      @circuit_breaker.record_failure
      
      Rails.logger.error("Primary agent failed: #{e.message}")
      
      if @circuit_breaker.open?
        Rails.logger.warn("Circuit breaker now open")
      end
      
      @fallback_agent.process_request(input)
    end
  end
end
```

Cost Management
--------------

### Token Optimization

Optimize token usage:

```ruby
class TokenOptimizedAgent
  def initialize
    super
    
    @token_budget = TokenBudget.new(
      daily_limit: 100_000,
      per_request_limit: 1_000
    )
  end
  
  def process_request(input)
    # Check budget before processing
    unless @token_budget.can_process?(estimated_tokens(input))
      return budget_exceeded_response
    end
    
    # Optimize prompt
    optimized_input = optimize_prompt(input)
    
    result = super(optimized_input)
    
    # Track actual usage
    @token_budget.record_usage(result.usage.total_tokens)
    
    result
  end
  
  private
  
  def optimize_prompt(input)
    # Remove unnecessary whitespace
    input = input.strip.gsub(/\s+/, ' ')
    
    # Truncate if too long
    if input.length > 8000
      input = input[0, 8000] + "..."
    end
    
    input
  end
  
  def estimated_tokens(input)
    # Rough estimation: 1 token ≈ 4 characters
    input.length / 4
  end
end
```

### Provider Cost Optimization

Route requests based on cost:

```ruby
class CostOptimizedRouter
  def initialize
    @providers = {
      openai_gpt4: { cost_per_token: 0.00003, quality: 10 },
      openai_gpt35: { cost_per_token: 0.000002, quality: 7 },
      anthropic_claude: { cost_per_token: 0.000024, quality: 9 },
      local_llama: { cost_per_token: 0.0, quality: 6 }
    }
  end
  
  def route_request(input, quality_requirement: 7)
    suitable_providers = @providers.select do |_, config|
      config[:quality] >= quality_requirement
    end
    
    # Choose cheapest suitable provider
    chosen_provider = suitable_providers.min_by { |_, config| config[:cost_per_token] }
    
    Rails.logger.info("Routing to #{chosen_provider[0]} (cost: #{chosen_provider[1][:cost_per_token]})")
    
    chosen_provider[0]
  end
end
```

Conclusion
----------

Following these best practices will help you build robust, secure, and maintainable RAAF applications. Remember to:

1. **Structure your code** for maintainability and scalability
2. **Implement security** at every layer
3. **Monitor and observe** your AI systems
4. **Test thoroughly** with realistic scenarios
5. **Handle errors gracefully** with proper fallbacks
6. **Optimize performance** and costs
7. **Deploy with confidence** using proper configuration management

These patterns have been proven in production environments and will serve as a solid foundation for your RAAF applications.
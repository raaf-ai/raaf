**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf-ai.dev>.**

RAAF Best Practices Guide
=========================

This guide provides comprehensive best practices for building, deploying, and maintaining production AI agent systems with RAAF. Following these patterns will help you create robust, secure, and maintainable AI applications.

After reading this guide, you will know:

* How to organize and structure RAAF applications
* Security best practices for AI agent systems
* Performance optimization techniques
* Error handling and monitoring strategies
* Testing patterns for AI systems
* Operational excellence practices

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

### Caching and Performance

For comprehensive caching strategies and performance optimization techniques, see:
* **[Performance Guide](performance_guide.html)** - Caching patterns, connection pooling, and optimization

### Memory and Resource Management

For comprehensive memory management and resource optimization, see:
* **[Memory Guide](memory_guide.html)** - Memory backends, pruning strategies, and compression
* **[Performance Guide](performance_guide.html)** - Resource optimization and garbage collection
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

### Testing Best Practices

For comprehensive testing strategies including unit testing, integration testing, and workflow testing patterns, see the **[Testing Guide](testing_guide.html)**.
    end
  end
end
```

### Performance Testing and Monitoring

For comprehensive performance testing and monitoring guidance, see:
* **[Performance Guide](performance_guide.html)** - Performance testing, profiling, and monitoring
* **[Testing Guide](testing_guide.html)** - Load testing and performance benchmarks

Operations and Configuration
---------------------------

For comprehensive operational guidance, see:
* **[Configuration Reference](configuration_reference.html)** - Environment-based configuration and settings
* **[Monitoring Guide](tracing_guide.html)** - Health checks and observability
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

These patterns follow established best practices and can serve as a solid foundation for your RAAF applications.
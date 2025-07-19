**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Architecture Patterns
===========================

This guide presents proven architectural patterns for scaling AI agent systems in production environments. Learn how to design robust, maintainable, and scalable AI systems using established patterns and best practices.

After reading this guide, you will know:

* Core architectural patterns for AI agent systems
* Scalability patterns for high-throughput applications
* Resilience patterns for fault-tolerant systems
* Data flow patterns for complex agent interactions
* Security patterns for enterprise deployments
* Monitoring and observability patterns
* Migration patterns for system evolution

--------------------------------------------------------------------------------

Core Architectural Patterns
----------------------------

### Agent-Service Pattern

Encapsulate agents as independent services with clear interfaces and responsibilities.

```ruby
# Service layer that abstracts agent complexity
class CustomerServiceAgentService
  include RAAF::Patterns::ServicePattern
  
  def initialize(config = {})
    @agent = build_agent(config)
    @context_manager = build_context_manager
    @performance_tracker = build_performance_tracker
  end
  
  def handle_inquiry(inquiry, context = {})
    # Service-level concerns
    track_performance do
      validate_input(inquiry)
      enriched_context = enrich_context(context)
      
      # Delegate to agent
      result = @agent.process(inquiry, enriched_context)
      
      # Post-processing
      process_result(result)
    end
  end
  
  private
  
  def build_agent(config)
    RAAF::Agent.new(
      name: "CustomerService",
      instructions: load_instructions(config[:version] || :latest),
      model: config[:model] || "gpt-4o-mini",
      tools: load_tools(config[:tool_set] || :standard)
    )
  end
  
  def enrich_context(context)
    {
      **context,
      session_id: generate_session_id,
      timestamp: Time.current.iso8601,
      service_version: service_version,
      feature_flags: load_feature_flags
    }
  end
  
  def process_result(result)
    # Log metrics
    @performance_tracker.record(result)
    
    # Apply business rules
    apply_post_processing_rules(result)
    
    # Return standardized response
    standardize_response(result)
  end
end

# Usage
service = CustomerServiceAgentService.new(
  model: "gpt-4o",
  tool_set: :enterprise,
  version: :v2
)

response = service.handle_inquiry(
  "I need help with my billing",
  user_id: "12345",
  tier: "premium"
)
```

### Agent Factory Pattern

Centralize agent creation and configuration management.

```ruby
class AgentFactory
  include Singleton
  
  def initialize
    @agent_configs = load_agent_configurations
    @agent_cache = {}
    @mutex = Mutex.new
  end
  
  def create_agent(type, variant: :default, **options)
    cache_key = build_cache_key(type, variant, options)
    
    @mutex.synchronize do
      @agent_cache[cache_key] ||= build_agent(type, variant, options)
    end
  end
  
  def create_agent_pool(type, pool_size: 5, **options)
    AgentPool.new(
      factory: self,
      agent_type: type,
      pool_size: pool_size,
      agent_options: options
    )
  end
  
  private
  
  def build_agent(type, variant, options)
    config = resolve_configuration(type, variant)
    
    agent = RAAF::Agent.new(
      name: config[:name],
      instructions: render_instructions(config[:instructions_template], options),
      model: select_model(config[:model_options], options),
      tools: build_tools(config[:tools], options)
    )
    
    apply_configuration_overrides(agent, config[:overrides], options)
    agent
  end
  
  def resolve_configuration(type, variant)
    base_config = @agent_configs.fetch(type) do
      raise AgentConfigurationError, "Unknown agent type: #{type}"
    end
    
    variant_config = base_config[:variants]&.fetch(variant, {}) || {}
    
    deep_merge(base_config, variant_config)
  end
  
  def select_model(model_options, options)
    case options[:performance_tier]
    when :economy then model_options[:economy]
    when :premium then model_options[:premium]
    else model_options[:standard]
    end
  end
end

# Configuration file
# config/agents.yml
customer_service:
  name: "Customer Service Agent"
  instructions_template: |
    You are a {{ tier }} customer service representative.
    Your knowledge includes: {{ knowledge_domains | join: ", " }}
    Response style: {{ response_style }}
  model_options:
    economy: "gpt-4o-mini"
    standard: "gpt-4o"
    premium: "gpt-4o"
  tools:

    - knowledge_base_search
    - ticket_management
    - customer_lookup
  variants:
    technical:
      tools:

        - knowledge_base_search
        - ticket_management
        - customer_lookup
        - system_diagnostics
        - log_analysis
    billing:
      tools:

        - knowledge_base_search
        - ticket_management
        - customer_lookup
        - billing_system
        - payment_processing

# Usage examples
factory = AgentFactory.instance

# Standard customer service agent
agent = factory.create_agent(:customer_service,
  tier: "premium",
  knowledge_domains: ["products", "billing", "technical"],
  response_style: "professional and empathetic"
)

# Technical support variant
tech_agent = factory.create_agent(:customer_service,
  variant: :technical,
  tier: "enterprise",
  performance_tier: :premium
)

# Agent pool for high throughput
agent_pool = factory.create_agent_pool(:customer_service,
  pool_size: 10,
  performance_tier: :standard
)
```

Scalability Patterns
---------------------

### Horizontal Scaling Pattern

Scale agent systems across multiple instances and regions.

```ruby
class DistributedAgentSystem
  def initialize
    @load_balancer = AgentLoadBalancer.new
    @region_managers = setup_region_managers
    @health_monitor = HealthMonitor.new
  end
  
  def process_request(request, routing_hints = {})
    # Route based on multiple factors
    target_region = select_target_region(request, routing_hints)
    agent_instance = @load_balancer.select_instance(target_region, request)
    
    # Execute with fault tolerance
    execute_with_fallback(agent_instance, request) do |fallback_needed|
      if fallback_needed
        # Fallback to different region or instance
        fallback_instance = @load_balancer.select_fallback(agent_instance, request)
        execute_on_instance(fallback_instance, request)
      end
    end
  end
  
  private
  
  def select_target_region(request, hints)
    factors = {
      user_location: hints[:user_location],
      data_locality: request[:data_requirements],
      latency_requirements: request[:latency_target],
      cost_optimization: hints[:cost_tier],
      compliance_requirements: request[:compliance_zone]
    }
    
    @region_managers.select_optimal_region(factors)
  end
  
  def execute_with_fallback(instance, request)
    begin
      result = execute_on_instance(instance, request)
      
      # Check if result quality meets standards
      if result_quality_acceptable?(result)
        result
      else
        yield(true) # Request fallback
      end
    rescue AgentUnavailableError, TimeoutError
      yield(true) # Request fallback
    end
  end
end

class AgentLoadBalancer
  def initialize
    @routing_strategies = {
      round_robin: RoundRobinStrategy.new,
      least_connections: LeastConnectionsStrategy.new,
      response_time_based: ResponseTimeStrategy.new,
      resource_based: ResourceBasedStrategy.new
    }
    @current_strategy = :response_time_based
  end
  
  def select_instance(region, request)
    available_instances = get_healthy_instances(region)
    
    if available_instances.empty?
      raise NoAvailableInstancesError, "No healthy instances in region #{region}"
    end
    
    strategy = @routing_strategies[@current_strategy]
    strategy.select_instance(available_instances, request)
  end
  
  def select_fallback(failed_instance, request)
    # Exclude failed instance and try different region
    fallback_regions = get_fallback_regions(failed_instance.region)
    
    fallback_regions.each do |region|
      instances = get_healthy_instances(region)
      next if instances.empty?
      
      return @routing_strategies[:least_connections].select_instance(instances, request)
    end
    
    raise NoFallbackAvailableError
  end
end

# Regional deployment configuration
class RegionManager
  REGIONS = {
    us_east: {
      latency_zones: ["US", "Canada", "Eastern Europe"],
      compliance: ["SOC2", "GDPR"],
      agent_capacity: 100,
      cost_multiplier: 1.0
    },
    eu_west: {
      latency_zones: ["Europe", "Africa", "Middle East"],
      compliance: ["GDPR", "SOC2"],
      agent_capacity: 75,
      cost_multiplier: 1.2
    },
    asia_pacific: {
      latency_zones: ["Asia", "Australia", "Pacific"],
      compliance: ["SOC2"],
      agent_capacity: 50,
      cost_multiplier: 0.8
    }
  }.freeze
  
  def select_optimal_region(factors)
    scored_regions = REGIONS.map do |region_id, config|
      score = calculate_region_score(config, factors)
      [region_id, score]
    end
    
    scored_regions.max_by { |_, score| score }.first
  end
  
  private
  
  def calculate_region_score(config, factors)
    latency_score = calculate_latency_score(config, factors[:user_location])
    compliance_score = calculate_compliance_score(config, factors[:compliance_requirements])
    capacity_score = calculate_capacity_score(config)
    cost_score = calculate_cost_score(config, factors[:cost_tier])
    
    # Weighted scoring
    (latency_score * 0.4) + 
    (compliance_score * 0.3) + 
    (capacity_score * 0.2) + 
    (cost_score * 0.1)
  end
end
```

### Auto-Scaling Pattern

Automatically scale agent capacity based on demand and performance metrics.

```ruby
class AgentAutoScaler
  def initialize
    @scaling_policies = load_scaling_policies
    @metrics_collector = MetricsCollector.new
    @instance_manager = InstanceManager.new
    @scaling_cooldown = 300 # 5 minutes
    @last_scaling_action = {}
  end
  
  def evaluate_scaling_needs
    current_metrics = @metrics_collector.get_current_metrics
    
    @scaling_policies.each do |policy|
      next unless cooldown_expired?(policy[:name])
      
      scaling_decision = evaluate_policy(policy, current_metrics)
      
      if scaling_decision[:action] != :no_action
        execute_scaling_action(scaling_decision, policy)
        record_scaling_action(policy[:name], scaling_decision)
      end
    end
  end
  
  private
  
  def evaluate_policy(policy, metrics)
    case policy[:type]
    when :cpu_based
      evaluate_cpu_scaling(policy, metrics)
    when :queue_depth_based
      evaluate_queue_scaling(policy, metrics)
    when :response_time_based
      evaluate_response_time_scaling(policy, metrics)
    when :predictive
      evaluate_predictive_scaling(policy, metrics)
    end
  end
  
  def evaluate_response_time_scaling(policy, metrics)
    current_response_time = metrics[:avg_response_time]
    target_response_time = policy[:target_response_time]
    
    if current_response_time > target_response_time * 1.5
      # Scale up aggressively if response time is very high
      scale_factor = [current_response_time / target_response_time, 3.0].min
      {
        action: :scale_up,
        factor: scale_factor,
        reason: "High response time: #{current_response_time}ms > #{target_response_time}ms"
      }
    elsif current_response_time > target_response_time * 1.2
      # Scale up moderately
      {
        action: :scale_up,
        factor: 1.5,
        reason: "Elevated response time: #{current_response_time}ms"
      }
    elsif current_response_time < target_response_time * 0.7 && metrics[:cpu_usage] < 30
      # Scale down if response time is very low and CPU usage is low
      {
        action: :scale_down,
        factor: 0.8,
        reason: "Low utilization: #{current_response_time}ms response time, #{metrics[:cpu_usage]}% CPU"
      }
    else
      { action: :no_action }
    end
  end
  
  def evaluate_predictive_scaling(policy, metrics)
    # Use historical data to predict future load
    historical_data = @metrics_collector.get_historical_metrics(24.hours)
    predicted_load = predict_future_load(historical_data, Time.current.hour)
    
    current_capacity = @instance_manager.current_capacity
    required_capacity = calculate_required_capacity(predicted_load, policy[:target_utilization])
    
    if required_capacity > current_capacity * 1.3
      {
        action: :scale_up,
        factor: required_capacity / current_capacity,
        reason: "Predicted load increase: #{predicted_load} (current capacity: #{current_capacity})"
      }
    elsif required_capacity < current_capacity * 0.7
      {
        action: :scale_down,
        factor: required_capacity / current_capacity,
        reason: "Predicted load decrease: #{predicted_load}"
      }
    else
      { action: :no_action }
    end
  end
  
  def execute_scaling_action(decision, policy)
    case decision[:action]
    when :scale_up
      target_instances = (@instance_manager.current_instances * decision[:factor]).round
      target_instances = [target_instances, policy[:max_instances]].min
      
      @instance_manager.scale_to(target_instances)
      
      Rails.logger.info "Scaled up to #{target_instances} instances. Reason: #{decision[:reason]}"
      
    when :scale_down
      target_instances = (@instance_manager.current_instances * decision[:factor]).round
      target_instances = [target_instances, policy[:min_instances]].max
      
      @instance_manager.scale_to(target_instances, graceful: true)
      
      Rails.logger.info "Scaled down to #{target_instances} instances. Reason: #{decision[:reason]}"
    end
  end
end

# Scaling policy configuration
scaling_policies:

  - name: "response_time_scaling"
    type: :response_time_based
    target_response_time: 2000  # 2 seconds
    min_instances: 2
    max_instances: 50
    enabled: true
    
  - name: "queue_depth_scaling"
    type: :queue_depth_based
    target_queue_depth: 10
    scale_up_threshold: 25
    scale_down_threshold: 5
    min_instances: 2
    max_instances: 20
    enabled: true
    
  - name: "predictive_scaling"
    type: :predictive
    target_utilization: 0.7
    prediction_window: 30  # minutes
    min_instances: 5
    max_instances: 100
    enabled: true
```

Resilience Patterns
-------------------

### Circuit Breaker Pattern

Protect against cascading failures and provide graceful degradation.

```ruby
class AgentCircuitBreaker
  include RAAF::Patterns::CircuitBreakerPattern
  
  STATES = [:closed, :open, :half_open].freeze
  
  def initialize(agent, config = {})
    @agent = agent
    @failure_threshold = config[:failure_threshold] || 5
    @recovery_timeout = config[:recovery_timeout] || 60
    @success_threshold = config[:success_threshold] || 3
    
    @failure_count = 0
    @last_failure_time = nil
    @state = :closed
    @success_count = 0
    @mutex = Mutex.new
  end
  
  def execute(request, &fallback)
    @mutex.synchronize do
      case @state
      when :closed
        execute_request(request, &fallback)
      when :open
        check_recovery_timeout
        if @state == :open
          execute_fallback(request, "Circuit breaker open", &fallback)
        else
          execute_request(request, &fallback)
        end
      when :half_open
        execute_half_open_request(request, &fallback)
      end
    end
  end
  
  private
  
  def execute_request(request, &fallback)
    begin
      result = @agent.process(request)
      on_success
      result
    rescue => e
      on_failure(e)
      execute_fallback(request, e.message, &fallback)
    end
  end
  
  def execute_half_open_request(request, &fallback)
    begin
      result = @agent.process(request)
      @success_count += 1
      
      if @success_count >= @success_threshold
        @state = :closed
        @success_count = 0
        @failure_count = 0
        Rails.logger.info "Circuit breaker closed after successful recovery"
      end
      
      result
    rescue => e
      @state = :open
      @last_failure_time = Time.current
      @success_count = 0
      Rails.logger.warn "Circuit breaker opened again after recovery failure"
      
      execute_fallback(request, e.message, &fallback)
    end
  end
  
  def on_success
    @failure_count = 0
  end
  
  def on_failure(error)
    @failure_count += 1
    @last_failure_time = Time.current
    
    if @failure_count >= @failure_threshold
      @state = :open
      Rails.logger.warn "Circuit breaker opened due to #{@failure_count} failures"
    end
  end
  
  def check_recovery_timeout
    if @last_failure_time && 
       (Time.current - @last_failure_time) >= @recovery_timeout
      @state = :half_open
      @success_count = 0
      Rails.logger.info "Circuit breaker entering half-open state"
    end
  end
  
  def execute_fallback(request, error_message, &fallback)
    if fallback
      Rails.logger.info "Executing fallback for request due to: #{error_message}"
      yield(request, error_message)
    else
      raise CircuitBreakerOpenError, "Circuit breaker open: #{error_message}"
    end
  end
end

# Usage with fallback strategies
class ResilientAgentService
  def initialize
    @primary_agent = AgentFactory.create(:customer_service, tier: :premium)
    @fallback_agent = AgentFactory.create(:customer_service, tier: :basic)
    @static_responses = load_static_responses
    
    @primary_circuit_breaker = AgentCircuitBreaker.new(@primary_agent)
    @fallback_circuit_breaker = AgentCircuitBreaker.new(@fallback_agent)
  end
  
  def handle_request(request)
    # Try primary agent with circuit breaker
    @primary_circuit_breaker.execute(request) do |req, error|
      Rails.logger.warn "Primary agent failed: #{error}"
      
      # Fallback to secondary agent
      @fallback_circuit_breaker.execute(req) do |fallback_req, fallback_error|
        Rails.logger.warn "Fallback agent also failed: #{fallback_error}"
        
        # Final fallback to static responses
        generate_static_response(fallback_req)
      end
    end
  end
  
  private
  
  def generate_static_response(request)
    intent = classify_intent(request[:message])
    template = @static_responses[intent] || @static_responses[:default]
    
    {
      content: template,
      source: "static_fallback",
      limited_functionality: true,
      suggested_actions: ["try_again_later", "contact_human_support"]
    }
  end
end
```

### Retry Pattern with Exponential Backoff

Handle transient failures with intelligent retry mechanisms.

```ruby
class AgentRetryHandler
  include RAAF::Patterns::RetryPattern
  
  DEFAULT_CONFIG = {
    max_retries: 3,
    base_delay: 1.0,
    max_delay: 30.0,
    backoff_multiplier: 2.0,
    jitter: true,
    retryable_errors: [
      RAAF::Errors::RateLimitError,
      RAAF::Errors::TemporaryProviderError,
      Net::TimeoutError,
      Net::ReadTimeout
    ]
  }.freeze
  
  def initialize(agent, config = {})
    @agent = agent
    @config = DEFAULT_CONFIG.merge(config)
    @retry_count = 0
  end
  
  def execute_with_retry(request)
    @retry_count = 0
    
    begin
      result = @agent.process(request)
      log_success if @retry_count > 0
      result
    rescue => e
      handle_error(e, request)
    end
  end
  
  private
  
  def handle_error(error, request)
    if should_retry?(error)
      @retry_count += 1
      delay = calculate_delay
      
      log_retry_attempt(error, delay)
      sleep(delay)
      
      retry
    else
      log_final_failure(error)
      raise
    end
  end
  
  def should_retry?(error)
    return false if @retry_count >= @config[:max_retries]
    return false unless retryable_error?(error)
    
    # Special handling for rate limit errors
    if error.is_a?(RAAF::Errors::RateLimitError)
      return handle_rate_limit_retry(error)
    end
    
    true
  end
  
  def retryable_error?(error)
    @config[:retryable_errors].any? { |error_class| error.is_a?(error_class) }
  end
  
  def handle_rate_limit_retry(error)
    # Use retry-after header if available
    if error.retry_after
      sleep(error.retry_after)
      true
    else
      # Standard backoff for rate limits
      @retry_count < @config[:max_retries]
    end
  end
  
  def calculate_delay
    base_delay = @config[:base_delay] * (@config[:backoff_multiplier] ** (@retry_count - 1))
    delay = [base_delay, @config[:max_delay]].min
    
    if @config[:jitter]
      # Add jitter to prevent thundering herd
      jitter_range = delay * 0.1
      delay += Random.rand(-jitter_range..jitter_range)
    end
    
    [delay, 0].max
  end
  
  def log_retry_attempt(error, delay)
    Rails.logger.warn "Agent request failed (attempt #{@retry_count}/#{@config[:max_retries]}): #{error.message}. Retrying in #{delay.round(2)}s"
  end
  
  def log_success
    Rails.logger.info "Agent request succeeded after #{@retry_count} retries"
  end
  
  def log_final_failure(error)
    Rails.logger.error "Agent request failed permanently after #{@retry_count} retries: #{error.message}"
  end
end

# Advanced retry with circuit breaker integration
class ResilientAgentExecutor
  def initialize(agent, config = {})
    @retry_handler = AgentRetryHandler.new(agent, config[:retry] || {})
    @circuit_breaker = AgentCircuitBreaker.new(@retry_handler, config[:circuit_breaker] || {})
    @timeout_handler = TimeoutHandler.new(config[:timeout] || 30)
  end
  
  def execute(request)
    @timeout_handler.with_timeout do
      @circuit_breaker.execute(request) do |req, error|
        # Fallback logic here
        handle_fallback(req, error)
      end
    end
  end
  
  private
  
  def handle_fallback(request, error)
    # Implement your fallback strategy
    FallbackResponseGenerator.generate(request, error)
  end
end
```

Data Flow Patterns
-------------------

### Event-Driven Architecture

Decouple agent interactions using event-driven patterns.

```ruby
class AgentEventBus
  include Singleton
  
  def initialize
    @subscribers = Hash.new { |h, k| h[k] = [] }
    @middleware = []
    @event_store = EventStore.new
  end
  
  def subscribe(event_type, handler = nil, &block)
    handler ||= block
    @subscribers[event_type] << handler
  end
  
  def publish(event_type, payload = {}, metadata = {})
    event = build_event(event_type, payload, metadata)
    
    # Store event
    @event_store.store(event)
    
    # Apply middleware
    processed_event = apply_middleware(event)
    
    # Deliver to subscribers
    deliver_to_subscribers(processed_event)
  end
  
  def use_middleware(&middleware)
    @middleware << middleware
  end
  
  private
  
  def build_event(type, payload, metadata)
    {
      id: SecureRandom.uuid,
      type: type,
      payload: payload,
      metadata: {
        timestamp: Time.current.iso8601,
        source: metadata[:source] || "agent_system",
        correlation_id: metadata[:correlation_id] || SecureRandom.uuid,
        **metadata
      }
    }
  end
  
  def apply_middleware(event)
    @middleware.reduce(event) do |current_event, middleware|
      middleware.call(current_event)
    end
  end
  
  def deliver_to_subscribers(event)
    @subscribers[event[:type]].each do |handler|
      deliver_to_handler(handler, event)
    end
    
    # Also deliver to wildcard subscribers
    @subscribers[:*].each do |handler|
      deliver_to_handler(handler, event)
    end
  end
  
  def deliver_to_handler(handler, event)
    # Async delivery to prevent blocking
    Thread.new do
      begin
        handler.call(event)
      rescue => e
        Rails.logger.error "Event handler failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end
  end
end

# Event-driven agent interactions
class EventDrivenAgentSystem
  def initialize
    @event_bus = AgentEventBus.instance
    setup_event_handlers
  end
  
  def setup_event_handlers
    # Customer inquiry handling
    @event_bus.subscribe(:customer_inquiry_received) do |event|
      handle_customer_inquiry(event)
    end
    
    # Agent response processing
    @event_bus.subscribe(:agent_response_generated) do |event|
      process_agent_response(event)
    end
    
    # Escalation handling
    @event_bus.subscribe(:escalation_required) do |event|
      handle_escalation(event)
    end
    
    # Learning and feedback
    @event_bus.subscribe(:customer_feedback_received) do |event|
      update_agent_learning(event)
    end
  end
  
  def handle_customer_inquiry(event)
    inquiry = event[:payload]
    
    # Route to appropriate agent based on inquiry type
    agent_type = classify_inquiry(inquiry[:message])
    agent = AgentFactory.create(agent_type)
    
    # Process with agent
    result = agent.process(inquiry)
    
    # Publish response event
    @event_bus.publish(:agent_response_generated, {
      inquiry_id: inquiry[:id],
      agent_type: agent_type,
      response: result,
      processing_time: result[:duration]
    }, {
      correlation_id: event[:metadata][:correlation_id],
      source: "agent_processor"
    })
  end
  
  def process_agent_response(event)
    response_data = event[:payload]
    
    # Check if escalation is needed
    if requires_escalation?(response_data[:response])
      @event_bus.publish(:escalation_required, {
        inquiry_id: response_data[:inquiry_id],
        agent_response: response_data[:response],
        escalation_reason: determine_escalation_reason(response_data)
      })
    end
    
    # Store response for learning
    store_response_for_learning(response_data)
    
    # Send response to customer
    deliver_response_to_customer(response_data)
  end
end

# Event middleware for cross-cutting concerns
class EventLoggingMiddleware
  def call(event)
    Rails.logger.info "Event published: #{event[:type]} [#{event[:id]}]"
    event
  end
end

class EventMetricsMiddleware
  def call(event)
    StatsD.increment("events.published", tags: ["type:#{event[:type]}"])
    event
  end
end

class EventValidationMiddleware
  def call(event)
    validate_event_structure(event)
    event
  end
  
  private
  
  def validate_event_structure(event)
    required_fields = [:id, :type, :payload, :metadata]
    missing_fields = required_fields - event.keys
    
    if missing_fields.any?
      raise EventValidationError, "Missing required fields: #{missing_fields}"
    end
  end
end

# Setup middleware
event_bus = AgentEventBus.instance
event_bus.use_middleware(&EventValidationMiddleware.new.method(:call))
event_bus.use_middleware(&EventLoggingMiddleware.new.method(:call))
event_bus.use_middleware(&EventMetricsMiddleware.new.method(:call))
```

### Data Pipeline Pattern

Process data through multiple stages with different agents.

```ruby
class AgentDataPipeline
  def initialize(stages = [])
    @stages = stages
    @middleware = []
    @error_handlers = {}
  end
  
  def add_stage(stage)
    @stages << stage
    self
  end
  
  def add_middleware(middleware)
    @middleware << middleware
    self
  end
  
  def add_error_handler(stage_name, handler)
    @error_handlers[stage_name] = handler
    self
  end
  
  def process(data, context = {})
    pipeline_context = build_pipeline_context(context)
    current_data = data
    
    @stages.each_with_index do |stage, index|
      begin
        stage_context = pipeline_context.merge(stage_index: index)
        current_data = process_stage(stage, current_data, stage_context)
      rescue => e
        handle_stage_error(stage, e, current_data, pipeline_context)
      end
    end
    
    current_data
  end
  
  private
  
  def process_stage(stage, data, context)
    # Apply pre-processing middleware
    processed_data = apply_pre_middleware(stage, data, context)
    
    # Execute stage
    result = stage.process(processed_data, context)
    
    # Apply post-processing middleware
    apply_post_middleware(stage, result, context)
  end
  
  def apply_pre_middleware(stage, data, context)
    @middleware.reduce(data) do |current_data, middleware|
      if middleware.respond_to?(:before_stage)
        middleware.before_stage(stage, current_data, context)
      else
        current_data
      end
    end
  end
  
  def apply_post_middleware(stage, data, context)
    @middleware.reverse.reduce(data) do |current_data, middleware|
      if middleware.respond_to?(:after_stage)
        middleware.after_stage(stage, current_data, context)
      else
        current_data
      end
    end
  end
  
  def handle_stage_error(stage, error, data, context)
    stage_name = stage.class.name
    
    if @error_handlers[stage_name]
      @error_handlers[stage_name].call(error, data, context)
    else
      raise PipelineStageError, "Stage #{stage_name} failed: #{error.message}"
    end
  end
  
  def build_pipeline_context(context)
    {
      pipeline_id: SecureRandom.uuid,
      started_at: Time.current,
      **context
    }
  end
end

# Example: Content processing pipeline
class ContentProcessingPipeline
  def self.build
    AgentDataPipeline.new
      .add_stage(ContentExtractionStage.new)
      .add_stage(ContentAnalysisStage.new)
      .add_stage(ContentEnrichmentStage.new)
      .add_stage(ContentSummaryStage.new)
      .add_middleware(LoggingMiddleware.new)
      .add_middleware(MetricsMiddleware.new)
      .add_error_handler('ContentExtractionStage', method(:handle_extraction_error))
  end
  
  def self.handle_extraction_error(error, data, context)
    # Fallback to basic text extraction
    Rails.logger.warn "Content extraction failed, using fallback: #{error.message}"
    { content: data[:raw_text], extraction_method: 'fallback' }
  end
end

class ContentExtractionStage
  def initialize
    @agent = AgentFactory.create(:content_extractor)
  end
  
  def process(data, context)
    @agent.process({
      document: data[:document],
      extraction_type: data[:type] || 'full',
      quality_level: context[:quality_level] || 'standard'
    })
  end
end

class ContentAnalysisStage
  def initialize
    @agent = AgentFactory.create(:content_analyzer)
  end
  
  def process(data, context)
    analysis = @agent.process({
      content: data[:content],
      analysis_depth: context[:analysis_depth] || 'standard'
    })
    
    data.merge(analysis: analysis)
  end
end

# Usage
pipeline = ContentProcessingPipeline.build

result = pipeline.process({
  document: uploaded_file,
  type: 'academic_paper'
}, {
  quality_level: 'high',
  analysis_depth: 'comprehensive'
})

puts result[:summary]
```

Security Patterns
-----------------

### Role-Based Access Control (RBAC) Pattern

Implement fine-grained access control for agent operations.

```ruby
class AgentAccessControl
  def initialize
    @role_definitions = load_role_definitions
    @permission_cache = {}
  end
  
  def authorize_agent_access(user, agent_type, operation, context = {})
    user_roles = get_user_roles(user)
    required_permissions = get_required_permissions(agent_type, operation)
    
    has_permission = user_roles.any? do |role|
      role_has_permissions?(role, required_permissions, context)
    end
    
    unless has_permission
      raise UnauthorizedAgentAccessError, 
        "User #{user.id} lacks permission for #{agent_type}:#{operation}"
    end
    
    # Apply context-based restrictions
    apply_context_restrictions(user, agent_type, operation, context)
  end
  
  def create_restricted_agent(user, agent_type, restrictions = {})
    authorize_agent_access(user, agent_type, :create)
    
    base_agent = AgentFactory.create(agent_type)
    RestrictedAgentProxy.new(base_agent, user, restrictions)
  end
  
  private
  
  def role_has_permissions?(role, required_permissions, context)
    role_permissions = @role_definitions[role][:permissions]
    
    required_permissions.all? do |permission|
      permission_granted?(role_permissions, permission, context)
    end
  end
  
  def permission_granted?(role_permissions, permission, context)
    # Check direct permission
    return true if role_permissions.include?(permission)
    
    # Check conditional permissions
    conditional_permissions = role_permissions.select { |p| p.is_a?(Hash) }
    conditional_permissions.any? do |conditional|
      conditional[:permission] == permission && 
      evaluate_conditions(conditional[:conditions], context)
    end
  end
  
  def evaluate_conditions(conditions, context)
    conditions.all? do |condition|
      case condition[:type]
      when 'time_based'
        evaluate_time_condition(condition, context)
      when 'resource_based'
        evaluate_resource_condition(condition, context)
      when 'attribute_based'
        evaluate_attribute_condition(condition, context)
      end
    end
  end
end

class RestrictedAgentProxy
  def initialize(agent, user, restrictions)
    @agent = agent
    @user = user
    @restrictions = restrictions
    @audit_logger = AuditLogger.new
  end
  
  def process(input, context = {})
    # Pre-processing security checks
    validate_input_restrictions(input)
    validate_context_restrictions(context)
    
    # Add audit trail
    @audit_logger.log_agent_access(@user, @agent.class.name, input, context)
    
    # Execute with monitoring
    result = execute_with_monitoring(input, context)
    
    # Post-processing security checks
    filter_output(result)
  end
  
  private
  
  def validate_input_restrictions(input)
    if @restrictions[:max_input_length]
      content_length = extract_content_length(input)
      if content_length > @restrictions[:max_input_length]
        raise InputTooLongError, "Input exceeds maximum length of #{@restrictions[:max_input_length]}"
      end
    end
    
    if @restrictions[:forbidden_keywords]
      check_forbidden_keywords(input, @restrictions[:forbidden_keywords])
    end
  end
  
  def filter_output(result)
    if @restrictions[:pii_filtering]
      result = apply_pii_filtering(result)
    end
    
    if @restrictions[:content_filtering]
      result = apply_content_filtering(result)
    end
    
    result
  end
  
  def execute_with_monitoring(input, context)
    start_time = Time.current
    
    begin
      result = @agent.process(input, context)
      
      @audit_logger.log_successful_execution(
        @user, @agent, input, result, Time.current - start_time
      )
      
      result
    rescue => e
      @audit_logger.log_failed_execution(
        @user, @agent, input, e, Time.current - start_time
      )
      
      raise
    end
  end
end

# Role definitions configuration
# config/agent_roles.yml
roles:
  admin:
    permissions:

      - "agent:*"
      - "system:*"
      
  analyst:
    permissions:

      - "agent:data_analyst:*"
      - "agent:report_generator:read"
      - permission: "agent:content_creator:create"
        conditions:

          - type: "time_based"
            allowed_hours: [9, 10, 11, 12, 13, 14, 15, 16, 17]

          - type: "resource_based"
            max_monthly_usage: 100
            
  customer_service:
    permissions:

      - "agent:customer_service:*"
      - "agent:knowledge_base:read"
      - permission: "agent:escalation:create"
        conditions:

          - type: "attribute_based"
            required_attributes:

              - supervisor_approval: true
              
  read_only:
    permissions:

      - "agent:*:read"
      - "system:health:read"
```

### Data Privacy and PII Protection Pattern

Implement comprehensive data protection for sensitive information.

```ruby
class AgentPrivacyGuard
  def initialize
    @pii_detector = PIIDetector.new
    @encryption_service = EncryptionService.new
    @anonymization_service = AnonymizationService.new
    @audit_logger = PrivacyAuditLogger.new
  end
  
  def process_with_privacy_protection(agent, input, user_context)
    # Step 1: Detect and classify sensitive data
    privacy_analysis = analyze_privacy_content(input)
    
    # Step 2: Apply appropriate protection measures
    protected_input = apply_protection_measures(input, privacy_analysis)
    
    # Step 3: Process with agent
    result = agent.process(protected_input, user_context)
    
    # Step 4: Restore or further protect output
    final_result = post_process_output(result, privacy_analysis, user_context)
    
    # Step 5: Audit trail
    log_privacy_processing(input, protected_input, result, final_result, user_context)
    
    final_result
  end
  
  private
  
  def analyze_privacy_content(input)
    pii_results = @pii_detector.detect(input)
    
    {
      contains_pii: pii_results.any?,
      pii_types: pii_results.map(&:type),
      pii_locations: pii_results.map(&:location),
      sensitivity_level: calculate_sensitivity_level(pii_results),
      protection_requirements: determine_protection_requirements(pii_results)
    }
  end
  
  def apply_protection_measures(input, analysis)
    return input unless analysis[:contains_pii]
    
    case analysis[:protection_requirements][:strategy]
    when :anonymize
      @anonymization_service.anonymize(input, analysis[:pii_locations])
    when :encrypt
      @encryption_service.encrypt_pii(input, analysis[:pii_locations])
    when :tokenize
      tokenize_pii(input, analysis[:pii_locations])
    when :remove
      remove_pii(input, analysis[:pii_locations])
    else
      input
    end
  end
  
  def post_process_output(result, analysis, user_context)
    # Check if output contains any derived PII
    output_analysis = analyze_privacy_content(result[:content])
    
    if output_analysis[:contains_pii]
      # Apply output filtering based on user permissions
      if user_context[:can_view_pii]
        result
      else
        filter_pii_from_output(result, output_analysis)
      end
    else
      result
    end
  end
  
  def calculate_sensitivity_level(pii_results)
    if pii_results.any? { |r| r.type.in?([:ssn, :credit_card, :bank_account]) }
      :high
    elsif pii_results.any? { |r| r.type.in?([:email, :phone, :address]) }
      :medium
    else
      :low
    end
  end
  
  def determine_protection_requirements(pii_results)
    high_sensitivity_types = [:ssn, :credit_card, :bank_account, :medical_record]
    
    if pii_results.any? { |r| r.type.in?(high_sensitivity_types) }
      { strategy: :encrypt, retention_policy: :short_term }
    else
      { strategy: :anonymize, retention_policy: :standard }
    end
  end
end

class PIIDetector
  def initialize
    @patterns = load_pii_patterns
    @ml_detector = load_ml_model if Rails.env.production?
  end
  
  def detect(text)
    pattern_results = detect_with_patterns(text)
    ml_results = @ml_detector ? detect_with_ml(text) : []
    
    combine_detection_results(pattern_results, ml_results)
  end
  
  private
  
  def detect_with_patterns(text)
    results = []
    
    @patterns.each do |type, pattern|
      text.scan(pattern).each do |match|
        location = text.index(match)
        confidence = calculate_pattern_confidence(type, match)
        
        results << PIIDetectionResult.new(
          type: type,
          value: match,
          location: location,
          confidence: confidence,
          detection_method: :pattern
        )
      end
    end
    
    results
  end
  
  def load_pii_patterns
    {
      ssn: /\b\d{3}-\d{2}-\d{4}\b/,
      credit_card: /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,
      email: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
      phone: /\b\(\d{3}\)\s?\d{3}-\d{4}\b|\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/,
      ip_address: /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/
    }
  end
end

class PIIDetectionResult
  attr_reader :type, :value, :location, :confidence, :detection_method
  
  def initialize(type:, value:, location:, confidence:, detection_method:)
    @type = type
    @value = value
    @location = location
    @confidence = confidence
    @detection_method = detection_method
  end
end
```

Next Steps
----------

For implementing these architectural patterns:

* **[Performance Guide](performance_guide.html)** - Performance patterns and optimization
* **[RAAF Core Guide](core_guide.html)** - Foundation patterns and concepts
* **[Best Practices](best_practices.html)** - Implementation guidelines
* **[Configuration Reference](configuration_reference.html)** - Production configuration patterns
* **[Security Guide](guardrails_guide.html)** - Security architecture patterns
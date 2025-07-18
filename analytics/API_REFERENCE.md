# Usage Tracking API Reference

Complete Ruby API documentation for RAAF Usage Tracking components.

## Table of Contents

1. [UsageTracker](#usagetracker)
2. [Usage Metrics](#usage-metrics)
3. [Alert System](#alert-system)
4. [Analytics and Reporting](#analytics-and-reporting)
5. [Storage Backends](#storage-backends)
6. [Cost Calculation](#cost-calculation)
7. [Integration Examples](#integration-examples)

## UsageTracker

Main class for tracking API usage, costs, and performance metrics.

### Constructor

```ruby
RAAF::UsageTracking::UsageTracker.new(
  storage: :memory,                # Storage backend (:memory, :redis, :database)
  aggregation_interval: 60,        # Seconds between aggregations
  retention_period: 30.days,       # How long to keep detailed data
  enable_alerts: true              # Enable alert system
)
```

### Core Methods

```ruby
# Track API call
tracker.track_api_call(
  provider: String,                # Provider name (openai, anthropic, etc.)
  model: String,                   # Model used
  tokens_used: Hash,               # Token counts
  cost: Float,                     # API cost
  duration: Float,                 # Request duration
  metadata: Hash                   # Additional metadata
)

# Track agent interaction
tracker.track_agent_interaction(
  agent_name: String,              # Agent identifier
  user_id: String,                 # User identifier
  session_id: String,              # Session identifier
  duration: Float,                 # Interaction duration
  satisfaction_score: Float,       # User satisfaction (0-1)
  outcome: Symbol,                 # :resolved, :escalated, :abandoned
  metadata: Hash                   # Additional metadata
)

# Track tool usage
tracker.track_tool_usage(
  tool_name: String,               # Tool identifier
  agent_name: String,              # Agent using the tool
  duration: Float,                 # Execution duration
  success: Boolean,                # Success/failure
  metadata: Hash                   # Additional metadata
)
```

### Example Usage

```ruby
# Create tracker
tracker = RAAF::UsageTracking::UsageTracker.new(
  storage: :redis,
  enable_alerts: true
)

# Track API call
tracker.track_api_call(
  provider: "openai",
  model: "gpt-4",
  tokens_used: {
    input_tokens: 150,
    output_tokens: 200,
    total_tokens: 350
  },
  cost: 0.0105,  # $0.0105
  duration: 2.5,  # seconds
  metadata: {
    user_id: "user_123",
    request_id: "req_abc",
    temperature: 0.7
  }
)

# Track agent interaction
tracker.track_agent_interaction(
  agent_name: "CustomerSupport",
  user_id: "user_123",
  session_id: "session_456",
  duration: 180.5,  # 3 minutes
  satisfaction_score: 0.9,
  outcome: :resolved,
  metadata: {
    issue_type: "billing",
    resolution_steps: 3
  }
)
```

## Usage Metrics

### Real-time Metrics

```ruby
# Get current usage metrics
metrics = tracker.current_metrics

# Returns:
{
  api_calls: {
    total: 1523,
    by_provider: { openai: 1200, anthropic: 323 },
    by_model: { "gpt-4": 800, "gpt-3.5-turbo": 400, "claude-3": 323 }
  },
  tokens: {
    total: 1_500_000,
    input: 600_000,
    output: 900_000
  },
  costs: {
    total: 45.67,
    by_provider: { openai: 35.20, anthropic: 10.47 },
    by_model: { "gpt-4": 30.00, "gpt-3.5-turbo": 5.20, "claude-3": 10.47 }
  },
  performance: {
    average_duration: 2.3,
    p95_duration: 4.5,
    error_rate: 0.02
  }
}
```

### Historical Metrics

```ruby
# Get metrics for specific period
analytics = tracker.analytics(:today)
analytics = tracker.analytics(:week)
analytics = tracker.analytics(:month)
analytics = tracker.analytics(Date.new(2024, 1, 1)..Date.new(2024, 1, 31))

# Get metrics grouped by dimension
by_hour = tracker.analytics(:today, group_by: :hour)
by_user = tracker.analytics(:week, group_by: :user)
by_model = tracker.analytics(:month, group_by: :model)
```

### Custom Metrics

```ruby
# Define custom metric
tracker.define_metric(:response_quality) do |interaction|
  # Calculate quality score based on interaction data
  score = interaction[:satisfaction_score] * 0.5
  score += 0.3 if interaction[:outcome] == :resolved
  score += 0.2 if interaction[:duration] < 300  # Under 5 minutes
  score
end

# Track with custom metric
tracker.track_agent_interaction(
  agent_name: "Support",
  satisfaction_score: 0.8,
  outcome: :resolved,
  duration: 240
)

# Retrieve custom metric
quality_metrics = tracker.get_metric(:response_quality, :today)
```

## Alert System

### Adding Alerts

```ruby
# Add usage alert
tracker.add_alert(:high_cost) do |usage|
  usage[:costs][:total] > 100.0  # Alert if daily cost exceeds $100
end

# Add performance alert
tracker.add_alert(:slow_response) do |usage|
  usage[:performance][:p95_duration] > 10.0  # Alert if P95 > 10 seconds
end

# Add error rate alert
tracker.add_alert(:high_errors) do |usage|
  usage[:performance][:error_rate] > 0.05  # Alert if error rate > 5%
end

# Complex alert with multiple conditions
tracker.add_alert(:usage_anomaly) do |usage|
  current_calls = usage[:api_calls][:total]
  yesterday_calls = tracker.analytics(:yesterday)[:api_calls][:total]
  
  # Alert if usage increased by more than 200%
  current_calls > yesterday_calls * 3
end
```

### Alert Configuration

```ruby
# Configure alert handler
tracker.configure_alerts do |config|
  config.check_interval = 300  # Check every 5 minutes
  config.cooldown_period = 3600  # Don't repeat alert for 1 hour
  
  config.on_alert do |alert_name, usage_data|
    # Send notification
    NotificationService.send_alert(
      name: alert_name,
      data: usage_data,
      severity: determine_severity(alert_name)
    )
    
    # Log alert
    Rails.logger.warn("Usage alert triggered", {
      alert: alert_name,
      usage: usage_data
    })
  end
end
```

### Alert Management

```ruby
# List all alerts
alerts = tracker.list_alerts
# => [:high_cost, :slow_response, :high_errors, :usage_anomaly]

# Check specific alert
triggered = tracker.check_alert(:high_cost)
# => true/false

# Check all alerts
triggered_alerts = tracker.check_alerts
# => [:high_cost, :usage_anomaly]

# Remove alert
tracker.remove_alert(:high_errors)

# Disable/enable alerts
tracker.disable_alerts
tracker.enable_alerts
```

## Analytics and Reporting

### Generate Reports

```ruby
# Generate usage report
report = tracker.generate_report(
  period: :month,
  format: :detailed,
  include: [:costs, :performance, :trends]
)

# Report structure:
{
  period: { start: Date, end: Date },
  summary: {
    total_api_calls: 45_000,
    total_cost: 1_234.56,
    average_cost_per_call: 0.0274,
    total_tokens: 15_000_000
  },
  costs: {
    by_day: [...],
    by_provider: {...},
    by_model: {...},
    top_users: [...]
  },
  performance: {
    average_duration: 2.3,
    p50_duration: 2.0,
    p95_duration: 4.5,
    p99_duration: 8.2,
    error_rate: 0.02,
    success_rate: 0.98
  },
  trends: {
    cost_trend: :increasing,
    usage_trend: :stable,
    performance_trend: :improving
  }
}
```

### Dashboard Data

```ruby
# Get dashboard-ready data
dashboard = tracker.dashboard_data

# Returns:
{
  current: {
    active_users: 145,
    active_sessions: 23,
    requests_per_minute: 12.5,
    current_cost_rate: 0.45  # $/minute
  },
  today: {
    api_calls: 3_456,
    total_cost: 123.45,
    unique_users: 234,
    average_session_duration: 425.3
  },
  trends: {
    hourly_usage: [...],
    cost_projection: 3_750.00,  # Projected monthly cost
    usage_growth: 0.15  # 15% growth
  },
  alerts: [:high_cost],
  top_models: [
    { name: "gpt-4", usage: 0.65, cost: 0.80 },
    { name: "gpt-3.5-turbo", usage: 0.35, cost: 0.20 }
  ]
}
```

### Custom Analytics

```ruby
class CustomAnalytics
  def initialize(tracker)
    @tracker = tracker
  end
  
  def user_efficiency_report(user_id, period = :week)
    data = @tracker.get_user_data(user_id, period)
    
    {
      user_id: user_id,
      period: period,
      interactions: data[:interactions].count,
      resolution_rate: calculate_resolution_rate(data),
      average_duration: calculate_average_duration(data),
      cost_per_resolution: calculate_cost_per_resolution(data),
      satisfaction_score: calculate_satisfaction(data),
      tool_usage: analyze_tool_usage(data),
      recommendations: generate_recommendations(data)
    }
  end
  
  private
  
  def calculate_resolution_rate(data)
    resolved = data[:interactions].count { |i| i[:outcome] == :resolved }
    total = data[:interactions].count
    
    total > 0 ? (resolved.to_f / total * 100).round(2) : 0
  end
  
  def generate_recommendations(data)
    recommendations = []
    
    if data[:average_duration] > 600  # 10 minutes
      recommendations << "Consider providing more agent training"
    end
    
    if data[:tool_usage][:file_search] > 0.5
      recommendations << "Frequently searched topics could be added to FAQ"
    end
    
    recommendations
  end
end
```

## Storage Backends

### Memory Storage

```ruby
# In-memory storage (development/testing)
tracker = RAAF::UsageTracking::UsageTracker.new(
  storage: :memory,
  max_memory_size: 10_000  # Maximum records in memory
)
```

### Redis Storage

```ruby
# Redis storage (production)
tracker = RAAF::UsageTracking::UsageTracker.new(
  storage: :redis,
  redis_config: {
    url: ENV['REDIS_URL'],
    namespace: 'usage_tracking',
    ttl: 30.days.to_i
  }
)
```

### Database Storage

```ruby
# ActiveRecord storage (Rails)
tracker = RAAF::UsageTracking::UsageTracker.new(
  storage: :database,
  model_class: UsageRecord,
  batch_size: 100
)

# Model setup
class UsageRecord < ApplicationRecord
  # Table: usage_records
  # Columns:
  # - record_type: string
  # - provider: string
  # - model: string
  # - user_id: string
  # - tokens: jsonb
  # - cost: decimal
  # - duration: float
  # - metadata: jsonb
  # - created_at: datetime
  
  scope :by_type, ->(type) { where(record_type: type) }
  scope :by_provider, ->(provider) { where(provider: provider) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :in_period, ->(start_date, end_date) {
    where(created_at: start_date..end_date)
  }
end
```

### Custom Storage

```ruby
class S3Storage
  def initialize(bucket:, prefix:)
    @bucket = bucket
    @prefix = prefix
    @s3 = Aws::S3::Client.new
  end
  
  def store(record)
    key = "#{@prefix}/#{record[:timestamp].to_i}/#{record[:id]}.json"
    
    @s3.put_object(
      bucket: @bucket,
      key: key,
      body: record.to_json,
      content_type: 'application/json'
    )
  end
  
  def query(criteria)
    # Implement S3 query logic
    # Could use S3 Select or Athena for complex queries
  end
end

tracker = RAAF::UsageTracking::UsageTracker.new(
  storage: S3Storage.new(
    bucket: 'usage-tracking-data',
    prefix: 'raaf/usage'
  )
)
```

## Cost Calculation

### Cost Models

```ruby
# Define cost model
cost_model = RAAF::UsageTracking::CostModel.new do |config|
  # OpenAI pricing
  config.add_model("gpt-4", 
    input_token_cost: 0.00003,    # $0.03 per 1K tokens
    output_token_cost: 0.00006     # $0.06 per 1K tokens
  )
  
  config.add_model("gpt-3.5-turbo",
    input_token_cost: 0.0000015,   # $0.0015 per 1K tokens
    output_token_cost: 0.000002    # $0.002 per 1K tokens
  )
  
  # Anthropic pricing
  config.add_model("claude-3-opus",
    input_token_cost: 0.000015,    # $0.015 per 1K tokens
    output_token_cost: 0.000075    # $0.075 per 1K tokens
  )
  
  # Custom pricing rules
  config.add_rule(:volume_discount) do |usage|
    if usage[:total_tokens] > 10_000_000  # 10M tokens
      0.9  # 10% discount
    else
      1.0
    end
  end
  
  config.add_rule(:premium_hours) do |usage|
    hour = Time.current.hour
    if hour >= 9 && hour <= 17  # Business hours
      1.2  # 20% premium
    else
      1.0
    end
  end
end

# Use with tracker
tracker = RAAF::UsageTracking::UsageTracker.new(
  cost_model: cost_model
)
```

### Cost Analysis

```ruby
# Analyze costs
cost_analysis = tracker.analyze_costs(:month)

# Returns:
{
  total_cost: 1_234.56,
  by_model: {
    "gpt-4" => { cost: 890.12, percentage: 72.1 },
    "gpt-3.5-turbo" => { cost: 234.44, percentage: 19.0 },
    "claude-3-opus" => { cost: 110.00, percentage: 8.9 }
  },
  by_user: [
    { user_id: "power_user_1", cost: 234.56, percentage: 19.0 },
    { user_id: "power_user_2", cost: 189.23, percentage: 15.3 }
  ],
  cost_per_interaction: 0.45,
  cost_per_resolution: 0.67,
  optimization_suggestions: [
    {
      suggestion: "Switch routine queries to gpt-3.5-turbo",
      potential_savings: 123.45,
      implementation: "Use gpt-3.5-turbo for FAQ-type questions"
    }
  ]
}
```

## Integration Examples

### With Runner

```ruby
class TrackedRunner < RAAF::Runner
  def initialize(agent:, tracker:, **options)
    super(agent: agent, **options)
    @tracker = tracker
    @user_id = options[:user_id]
  end
  
  def run(messages, **options)
    start_time = Time.current
    tokens_before = get_token_count
    
    begin
      result = super
      
      # Track successful call
      tokens_used = calculate_token_usage(tokens_before, result)
      cost = calculate_cost(tokens_used, @agent.model)
      
      @tracker.track_api_call(
        provider: detect_provider(@agent.model),
        model: @agent.model,
        tokens_used: tokens_used,
        cost: cost,
        duration: Time.current - start_time,
        metadata: {
          user_id: @user_id,
          agent: @agent.name,
          success: true
        }
      )
      
      result
    rescue => e
      # Track failed call
      @tracker.track_api_call(
        provider: detect_provider(@agent.model),
        model: @agent.model,
        tokens_used: { total: 0 },
        cost: 0,
        duration: Time.current - start_time,
        metadata: {
          user_id: @user_id,
          agent: @agent.name,
          success: false,
          error: e.class.name
        }
      )
      
      raise
    end
  end
end
```

### With Rails

```ruby
# app/services/usage_tracking_service.rb
class UsageTrackingService
  include Singleton
  
  def initialize
    @tracker = RAAF::UsageTracking::UsageTracker.new(
      storage: :database,
      model_class: UsageRecord
    )
    
    setup_alerts
  end
  
  def track_request(user:, agent_name:, &block)
    interaction_start = Time.current
    session_id = SecureRandom.uuid
    
    begin
      result = yield
      
      @tracker.track_agent_interaction(
        agent_name: agent_name,
        user_id: user.id,
        session_id: session_id,
        duration: Time.current - interaction_start,
        outcome: determine_outcome(result),
        metadata: {
          ip_address: user.last_ip,
          user_agent: user.last_user_agent
        }
      )
      
      result
    rescue => e
      @tracker.track_agent_interaction(
        agent_name: agent_name,
        user_id: user.id,
        session_id: session_id,
        duration: Time.current - interaction_start,
        outcome: :error,
        metadata: {
          error: e.message
        }
      )
      
      raise
    end
  end
  
  def user_dashboard_data(user)
    @tracker.get_user_data(user.id, :month)
  end
  
  private
  
  def setup_alerts
    @tracker.add_alert(:user_overage) do |usage|
      user_data = usage[:by_user]
      user_data.any? { |u| u[:cost] > u[:monthly_limit] }
    end
    
    @tracker.configure_alerts do |config|
      config.on_alert do |alert_name, data|
        UsageAlertMailer.send_alert(alert_name, data).deliver_later
      end
    end
  end
end

# app/controllers/api/agents_controller.rb
class Api::AgentsController < ApplicationController
  def query
    result = UsageTrackingService.instance.track_request(
      user: current_user,
      agent_name: params[:agent]
    ) do
      agent = find_agent(params[:agent])
      runner = TrackedRunner.new(
        agent: agent,
        tracker: UsageTrackingService.instance.tracker,
        user_id: current_user.id
      )
      
      runner.run(params[:message])
    end
    
    render json: { response: result.messages.last[:content] }
  end
end
```

### Batch Processing

```ruby
class BatchUsageProcessor
  def initialize(tracker)
    @tracker = tracker
    @batch = []
    @mutex = Mutex.new
    
    start_batch_processor
  end
  
  def track(data)
    @mutex.synchronize do
      @batch << data
      
      if @batch.size >= 100
        flush
      end
    end
  end
  
  def flush
    return if @batch.empty?
    
    batch_to_process = nil
    
    @mutex.synchronize do
      batch_to_process = @batch.dup
      @batch.clear
    end
    
    # Process batch
    batch_to_process.each do |item|
      case item[:type]
      when :api_call
        @tracker.track_api_call(**item[:data])
      when :interaction
        @tracker.track_agent_interaction(**item[:data])
      when :tool_usage
        @tracker.track_tool_usage(**item[:data])
      end
    end
  end
  
  private
  
  def start_batch_processor
    Thread.new do
      loop do
        sleep 10  # Flush every 10 seconds
        flush
      end
    end
  end
end
```

For more information on integrating usage tracking with agents, see the [Core API Reference](../core/API_REFERENCE.md).
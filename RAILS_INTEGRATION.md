# Rails Integration Guide for OpenAI Agents Tracing

This guide provides detailed instructions for integrating OpenAI Agents tracing with Ruby on Rails applications, including advanced configuration, performance optimization, and production deployment strategies.

## Table of Contents

- [Quick Start](#quick-start)
- [Installation & Setup](#installation--setup)
- [Configuration](#configuration)
- [Rails-Specific Features](#rails-specific-features)
- [Performance Optimization](#performance-optimization)
- [Production Deployment](#production-deployment)
- [Monitoring & Alerting](#monitoring--alerting)
- [Troubleshooting](#troubleshooting)
- [API Reference](#api-reference)

## Quick Start

### 1. Install and Generate

```bash
# Add to Gemfile
echo 'gem "openai-agents", "~> 1.0"' >> Gemfile
bundle install

# Generate tracing integration
rails generate openai_agents:tracing:install

# Run migrations
rails db:migrate
```

### 2. Configure Automatic Tracing

```ruby
# config/initializers/openai_agents_tracing.rb
OpenAIAgents::Tracing.configure do |config|
  config.auto_configure = true
  config.mount_path = '/tracing'
  config.retention_days = 30
  config.sampling_rate = 1.0  # 100% in development
end
```

### 3. Start Using

```ruby
# Your existing agent code automatically gets traced
agent = OpenAIAgents::Agent.new(
  name: "CustomerSupport",
  instructions: "Help customers with their questions.",
  model: "gpt-4o"
)

runner = OpenAIAgents::Runner.new(agent: agent)
result = runner.run("Hello, I need help with my order")

# Visit http://localhost:3000/tracing to see traces
```

## Installation & Setup

### Prerequisites

- Ruby on Rails 6.0+
- PostgreSQL, MySQL, or SQLite3
- OpenAI API key

### Detailed Installation Steps

1. **Add the Gem**
   ```ruby
   # Gemfile
   gem 'openai-agents', '~> 1.0'
   
   # For development/testing enhancements
   group :development, :test do
     gem 'rspec-rails'  # For specs
   end
   ```

2. **Run the Generator**
   ```bash
   rails generate openai_agents:tracing:install
   ```
   
   This creates:
   - Database migrations for traces and spans
   - Initializer configuration file
   - Mount routes for the web interface
   - Example cleanup job

3. **Run Database Migrations**
   ```bash
   rails db:migrate
   ```

4. **Set Environment Variables**
   ```bash
   # .env or environment-specific config
   OPENAI_API_KEY=your_openai_api_key_here
   OPENAI_AGENTS_TRACE_DEBUG=true  # For development
   ```

### Generator Options

```bash
# Custom mount path
rails generate openai_agents:tracing:install --mount-path=/admin/tracing

# Skip automatic route mounting
rails generate openai_agents:tracing:install --skip-routes

# Skip initializer creation
rails generate openai_agents:tracing:install --skip-initializer
```

## Configuration

### Basic Configuration

```ruby
# config/initializers/openai_agents_tracing.rb
OpenAIAgents::Tracing.configure do |config|
  # Automatically configure the ActiveRecord processor
  config.auto_configure = true
  
  # Web interface mount path
  config.mount_path = '/tracing'
  
  # Data retention (days)
  config.retention_days = 30
  
  # Sampling rate (0.0 to 1.0)
  config.sampling_rate = 1.0
end
```

### Environment-Specific Configuration

```ruby
# config/environments/development.rb
Rails.application.configure do
  # Full tracing in development
  config.after_initialize do
    OpenAIAgents::Tracing.configure do |tracing_config|
      tracing_config.sampling_rate = 1.0
      tracing_config.retention_days = 7  # Shorter retention
    end
  end
end

# config/environments/production.rb
Rails.application.configure do
  # Optimized for production
  config.after_initialize do
    OpenAIAgents::Tracing.configure do |tracing_config|
      tracing_config.sampling_rate = 0.1  # 10% sampling
      tracing_config.retention_days = 30
    end
  end
end
```

### Advanced Processor Configuration

```ruby
# Manual processor setup with custom options
Rails.application.config.after_initialize do
  processor = OpenAIAgents::Tracing::ActiveRecordProcessor.new(
    sampling_rate: 0.1,           # Sample 10% of traces
    batch_size: 100,              # Batch 100 spans before saving
    auto_cleanup: true,           # Enable automatic cleanup
    cleanup_older_than: 7.days    # Clean up weekly
  )
  
  OpenAIAgents.tracer.add_processor(processor)
end
```

## Rails-Specific Features

### ActiveJob Integration

Automatically trace all background jobs:

```ruby
# app/jobs/application_job.rb
class ApplicationJob < ActiveJob::Base
  include OpenAIAgents::Tracing::RailsIntegrations::JobTracing
end

# Now all jobs are automatically traced
class ProcessOrderJob < ApplicationJob
  def perform(order_id)
    # This will be traced with job metadata
    agent = OpenAIAgents::Agent.new(name: "OrderProcessor", model: "gpt-4o")
    agent.run("Process order #{order_id}")
  end
end
```

Job traces include:
- Job class name and arguments
- Queue name and execution count
- Enqueued and started timestamps
- Any errors or exceptions

### Middleware for Request Correlation

Add HTTP request correlation to traces:

```ruby
# config/application.rb
config.middleware.use OpenAIAgents::Tracing::RailsIntegrations::CorrelationMiddleware
```

This automatically adds request context to traces:
- Request ID for correlation
- User agent information
- Remote IP address

### Console Helpers

Debug traces directly in Rails console:

```ruby
rails console

# Include helpers
include OpenAIAgents::Tracing::RailsIntegrations::ConsoleHelpers

# Find recent traces
recent_traces(10)

# Find traces by workflow
traces_for("Customer Support")

# Find slow operations
slow_spans(threshold: 5000)  # > 5 seconds

# Get performance statistics
performance_stats(timeframe: 24.hours)

# Analyze specific traces
trace_summary("trace_abc123...")

# Find error spans
error_spans(20)
```

### Rake Tasks

Built-in maintenance tasks:

```ruby
# Rakefile or lib/tasks/tracing.rake
namespace :tracing do
  desc "Clean up old traces"
  task :cleanup => :environment do
    OpenAIAgents::Tracing::RailsIntegrations::RakeTasks.cleanup_old_traces(
      older_than: 30.days
    )
  end
  
  desc "Generate performance report"
  task :report => :environment do
    OpenAIAgents::Tracing::RailsIntegrations::RakeTasks.performance_report(
      timeframe: 24.hours
    )
  end
end
```

### Custom Trace Context

Add application-specific context to traces:

```ruby
class ApplicationController < ActionController::Base
  around_action :trace_request

  private

  def trace_request
    return yield unless tracing_enabled?
    
    OpenAIAgents.trace("HTTP Request") do |trace|
      trace.metadata.merge!(
        controller: controller_name,
        action: action_name,
        user_id: current_user&.id,
        request_id: request.request_id,
        user_agent: request.user_agent
      )
      
      yield
    end
  end
  
  def tracing_enabled?
    # Enable tracing based on your criteria
    Rails.env.development? || current_user&.admin?
  end
end
```

## Performance Optimization

### Database Optimization

#### Indexing Strategy

The migration includes optimized indexes:

```sql
-- Primary indexes for lookups
CREATE INDEX ON openai_agents_tracing_traces (trace_id);
CREATE INDEX ON openai_agents_tracing_spans (span_id);

-- Performance query indexes  
CREATE INDEX ON openai_agents_tracing_traces (workflow_name, started_at);
CREATE INDEX ON openai_agents_tracing_spans (kind, start_time);
CREATE INDEX ON openai_agents_tracing_spans (duration_ms);

-- Cleanup indexes
CREATE INDEX ON openai_agents_tracing_traces (started_at);
CREATE INDEX ON openai_agents_tracing_spans (start_time);
```

#### Database-Specific Optimizations

**PostgreSQL:**
```ruby
# config/database.yml
production:
  adapter: postgresql
  # Enable JSON indexing for attributes/events
  schema_search_path: public
  
# Migration for JSON indexes (PostgreSQL only)
class AddJsonIndexes < ActiveRecord::Migration[7.0]
  def up
    if connection.adapter_name.downcase.include?('postgresql')
      add_index :openai_agents_tracing_spans, :attributes, using: :gin
      add_index :openai_agents_tracing_spans, :events, using: :gin
    end
  end
end
```

### Sampling Strategies

#### Production Sampling
```ruby
# Intelligent sampling based on environment
class IntelligentSampler
  def self.sample_rate
    case Rails.env
    when 'development', 'test'
      1.0  # Always trace in dev/test
    when 'staging'
      0.5  # 50% sampling in staging
    when 'production'
      if high_traffic_period?
        0.05  # 5% during peak hours
      else
        0.2   # 20% during normal hours
      end
    end
  end
  
  private
  
  def self.high_traffic_period?
    Time.current.hour.between?(9, 17)  # Business hours
  end
end

# Use in configuration
config.sampling_rate = IntelligentSampler.sample_rate
```

#### User-Based Sampling
```ruby
# Sample based on user characteristics
class UserBasedProcessor < OpenAIAgents::Tracing::ActiveRecordProcessor
  private
  
  def should_sample?(trace_id)
    # Always sample for admin users
    return true if Thread.current[:current_user]&.admin?
    
    # Sample premium users more frequently
    if Thread.current[:current_user]&.premium?
      return super(trace_id) || (rand < 0.5)
    end
    
    super(trace_id)
  end
end
```

### Background Processing

#### Optimize Batch Sizes
```ruby
# config/initializers/openai_agents_tracing.rb
processor = OpenAIAgents::Tracing::ActiveRecordProcessor.new(
  # Larger batches for high-throughput applications
  batch_size: 200,
  
  # Background thread processes every 5 seconds
  flush_interval: 5.seconds
)
```

#### Async Processing with Sidekiq
```ruby
# For very high volume, delegate to background jobs
class AsyncTracingProcessor
  def on_span_start(span)
    # No-op, process only on end
  end
  
  def on_span_end(span)
    TraceProcessingJob.perform_async(span.to_h)
  end
end

class TraceProcessingJob
  include Sidekiq::Worker
  
  def perform(span_data)
    # Process span in background
    OpenAIAgents::Tracing::ActiveRecordProcessor.new(batch_size: 1)
      .send(:save_span_to_database, OpenStruct.new(span_data))
  end
end
```

## Production Deployment

### Security Configuration

#### Authentication
```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Protect tracing interface
  authenticate :user, ->(u) { u.admin? } do
    mount OpenAIAgents::Tracing::Engine => '/admin/tracing'
  end
end

# Or with custom authentication
class TracingController < ApplicationController
  before_action :authenticate_admin!
  
  private
  
  def authenticate_admin!
    redirect_to login_path unless current_user&.admin?
  end
end
```

#### Data Protection
```ruby
# Custom processor with PII scrubbing
class SecureProcessor < OpenAIAgents::Tracing::ActiveRecordProcessor
  SENSITIVE_PATTERNS = [
    /email/i, /password/i, /ssn/i, /credit_card/i,
    /phone/i, /address/i, /birthday/i
  ].freeze
  
  private
  
  def sanitize_attributes(attributes)
    scrubbed = super(attributes)
    
    scrubbed.each do |key, value|
      if SENSITIVE_PATTERNS.any? { |pattern| key.to_s.match?(pattern) }
        scrubbed[key] = '[REDACTED]'
      end
    end
    
    scrubbed
  end
end
```

### High Availability Setup

#### Database Replication
```ruby
# config/database.yml
production:
  primary:
    adapter: postgresql
    # Primary database config
  
  tracing:
    adapter: postgresql
    replica: true
    # Read replica for tracing queries

# Use replica for read operations
class OpenAIAgents::Tracing::Trace < ActiveRecord::Base
  connects_to database: { writing: :primary, reading: :tracing }
end
```

#### Horizontal Scaling
```ruby
# Multiple processor instances with sharding
class ShardedProcessor < OpenAIAgents::Tracing::ActiveRecordProcessor
  def initialize(shard_id:, total_shards:, **options)
    @shard_id = shard_id
    @total_shards = total_shards
    super(**options)
  end
  
  private
  
  def should_sample?(trace_id)
    # Only process traces assigned to this shard
    trace_hash = Digest::MD5.hexdigest(trace_id).to_i(16)
    assigned_shard = trace_hash % @total_shards
    
    return false unless assigned_shard == @shard_id
    
    super(trace_id)
  end
end

# Deploy with different shard IDs
# Instance 1: ShardedProcessor.new(shard_id: 0, total_shards: 3)
# Instance 2: ShardedProcessor.new(shard_id: 1, total_shards: 3)
# Instance 3: ShardedProcessor.new(shard_id: 2, total_shards: 3)
```

### Monitoring Setup

#### Health Checks
```ruby
# config/routes.rb
Rails.application.routes.draw do
  get '/health/tracing', to: 'health#tracing'
end

# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def tracing
    # Check tracing system health
    checks = {
      database: database_healthy?,
      processor: processor_healthy?,
      recent_traces: recent_traces_healthy?
    }
    
    if checks.values.all?
      render json: { status: 'healthy', checks: checks }
    else
      render json: { status: 'unhealthy', checks: checks }, status: 503
    end
  end
  
  private
  
  def database_healthy?
    OpenAIAgents::Tracing::Trace.connection.active?
  rescue
    false
  end
  
  def processor_healthy?
    OpenAIAgents.tracer.processors.any?
  end
  
  def recent_traces_healthy?
    OpenAIAgents::Tracing::Trace.where(
      started_at: 10.minutes.ago..Time.current
    ).exists?
  end
end
```

### Cleanup and Maintenance

#### Automated Cleanup
```ruby
# config/schedule.rb (with whenever gem)
every 1.day, at: '2:00 am' do
  rake 'tracing:cleanup'
end

every 1.week, at: '3:00 am' do
  rake 'tracing:vacuum'  # Database maintenance
end

# lib/tasks/tracing.rake
namespace :tracing do
  desc "Clean up old traces"
  task cleanup: :environment do
    retention_days = OpenAIAgents::Tracing.configuration.retention_days
    deleted = OpenAIAgents::Tracing::Trace.cleanup_old_traces(
      older_than: retention_days.days
    )
    puts "Cleaned up #{deleted} old traces"
  end
  
  desc "Vacuum tracing tables"
  task vacuum: :environment do
    if ActiveRecord::Base.connection.adapter_name.downcase.include?('postgresql')
      ActiveRecord::Base.connection.execute(
        'VACUUM ANALYZE openai_agents_tracing_traces, openai_agents_tracing_spans'
      )
      puts "Vacuumed tracing tables"
    end
  end
end
```

## Monitoring & Alerting

### Metrics Integration

#### Prometheus Metrics
```ruby
# config/initializers/prometheus.rb
require 'prometheus/client'

class MetricsProcessor
  def initialize
    @registry = Prometheus::Client.registry
    @traces_total = @registry.counter(
      :openai_agents_traces_total,
      docstring: 'Total number of traces',
      labels: [:workflow, :status]
    )
    @trace_duration = @registry.histogram(
      :openai_agents_trace_duration_seconds,
      docstring: 'Trace duration in seconds',
      labels: [:workflow]
    )
  end
  
  def on_span_start(span)
    # Track span starts if needed
  end
  
  def on_span_end(span)
    if span.kind == :trace
      @traces_total.increment(
        labels: { 
          workflow: span.attributes['trace.workflow_name'],
          status: span.status 
        }
      )
      
      if span.duration
        @trace_duration.observe(
          span.duration,
          labels: { workflow: span.attributes['trace.workflow_name'] }
        )
      end
    end
  end
end

# Add to processor chain
OpenAIAgents.tracer.add_processor(MetricsProcessor.new)
```

#### Custom Dashboards
```ruby
# app/controllers/admin/tracing_metrics_controller.rb
class Admin::TracingMetricsController < AdminController
  def index
    @metrics = {
      traces_last_24h: trace_count_last_24h,
      error_rate: error_rate_last_24h,
      avg_duration: avg_duration_last_24h,
      top_workflows: top_workflows_last_24h
    }
  end
  
  private
  
  def trace_count_last_24h
    OpenAIAgents::Tracing::Trace
      .where(started_at: 24.hours.ago..Time.current)
      .count
  end
  
  def error_rate_last_24h
    total = trace_count_last_24h
    errors = OpenAIAgents::Tracing::Trace
      .where(started_at: 24.hours.ago..Time.current)
      .failed
      .count
    
    total > 0 ? (errors.to_f / total * 100).round(2) : 0
  end
end
```

### Alerting Setup

#### Error Rate Alerts
```ruby
# config/initializers/alerting.rb
class TracingAlerter
  def self.check_error_rates
    current_rate = calculate_error_rate
    
    if current_rate > 10.0  # 10% error rate threshold
      send_alert(
        "High error rate detected: #{current_rate}%",
        severity: :critical
      )
    elsif current_rate > 5.0  # 5% warning threshold
      send_alert(
        "Elevated error rate: #{current_rate}%",
        severity: :warning
      )
    end
  end
  
  private
  
  def self.calculate_error_rate
    window = 10.minutes.ago..Time.current
    total = OpenAIAgents::Tracing::Trace.within_timeframe(window.begin, window.end).count
    errors = OpenAIAgents::Tracing::Trace.within_timeframe(window.begin, window.end).failed.count
    
    total > 0 ? (errors.to_f / total * 100).round(2) : 0
  end
  
  def self.send_alert(message, severity:)
    # Integration with your alerting system
    case severity
    when :critical
      PagerDutyClient.trigger_incident(message)
    when :warning
      SlackNotifier.send_message("#alerts", message)
    end
  end
end

# Schedule regular checks
# config/schedule.rb
every 5.minutes do
  runner "TracingAlerter.check_error_rates"
end
```

## Troubleshooting

### Common Issues

#### High Database Usage
```ruby
# Check table sizes
ActiveRecord::Base.connection.execute(<<-SQL)
  SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
  FROM pg_tables 
  WHERE tablename LIKE 'openai_agents_tracing_%'
  ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
SQL

# Solutions:
# 1. Reduce sampling rate
config.sampling_rate = 0.1

# 2. Implement more aggressive cleanup
OpenAIAgents::Tracing::Trace.cleanup_old_traces(older_than: 7.days)

# 3. Archive to external storage
class ArchivingJob
  def perform
    old_traces = OpenAIAgents::Tracing::Trace
      .where(started_at: ..1.month.ago)
      .includes(:spans)
    
    old_traces.find_each do |trace|
      S3Archiver.store(trace.to_json)
      trace.destroy
    end
  end
end
```

#### Missing Traces
```ruby
# Debug trace collection
puts "Active processors: #{OpenAIAgents.tracer.processors.map(&:class)}"
puts "Sampling rate: #{OpenAIAgents::Tracing.configuration.sampling_rate}"

# Check if tables exist
puts "Tables exist: #{OpenAIAgents::Tracing::Trace.table_exists?}"

# Verify processor is working
processor = OpenAIAgents::Tracing::ActiveRecordProcessor.new(sampling_rate: 1.0)
test_span = OpenAIAgents::Tracing::Span.new(
  name: "test",
  trace_id: "trace_test123"
)
processor.on_span_start(test_span)
processor.on_span_end(test_span)
```

#### Performance Issues
```ruby
# Enable query logging
ActiveRecord::Base.logger = Logger.new(STDOUT)

# Check slow queries
# Look for queries taking > 100ms in logs

# Add database query analysis
class QueryAnalyzer
  def self.analyze_performance
    queries = [
      "Recent traces query",
      "Dashboard metrics query", 
      "Search functionality"
    ]
    
    queries.each do |query_name|
      puts "\n=== #{query_name} ==="
      
      start_time = Time.current
      yield  # Execute the query
      duration = Time.current - start_time
      
      puts "Duration: #{(duration * 1000).round(2)}ms"
      
      if duration > 0.1  # > 100ms
        puts "⚠️  Slow query detected!"
      end
    end
  end
end
```

### Debug Mode

Enable comprehensive debugging:

```ruby
# config/environments/development.rb
Rails.application.configure do
  config.log_level = :debug
  
  # Enable tracing debug output
  ENV['OPENAI_AGENTS_TRACE_DEBUG'] = 'true'
  
  # Log all SQL queries
  config.active_record.verbose_query_logs = true
end
```

## API Reference

### Models

#### OpenAIAgents::Tracing::Trace
```ruby
# Class methods
Trace.recent(limit = 100)
Trace.by_workflow(name)
Trace.by_status(status)
Trace.within_timeframe(start_time, end_time)
Trace.performance_stats(workflow_name: nil, timeframe: nil)
Trace.top_workflows(limit: 10, timeframe: nil)
Trace.cleanup_old_traces(older_than: 30.days)

# Instance methods
trace.duration_ms
trace.performance_summary
trace.cost_analysis
trace.span_hierarchy
trace.update_trace_status
```

#### OpenAIAgents::Tracing::Span
```ruby
# Class methods
Span.by_kind(kind)
Span.by_status(status)
Span.errors
Span.successful
Span.slow(threshold_ms = 1000)
Span.performance_metrics(kind: nil, timeframe: nil)
Span.error_analysis(timeframe: nil)
Span.cost_analysis(timeframe: nil)

# Instance methods
span.error_details
span.operation_details
span.duration_seconds
span.depth
span.error_summary
```

### Controllers

All controllers support JSON responses for API access:

```ruby
# GET /tracing/traces.json
# GET /tracing/traces/:id.json
# GET /tracing/spans.json
# GET /tracing/dashboard.json
# GET /tracing/dashboard/performance.json
# GET /tracing/dashboard/costs.json
# GET /tracing/dashboard/errors.json
```

### Configuration Options

```ruby
OpenAIAgents::Tracing.configure do |config|
  config.auto_configure = false        # Boolean: Auto-add ActiveRecord processor
  config.mount_path = '/tracing'       # String: Web interface mount path
  config.retention_days = 30           # Integer: Days to keep traces
  config.sampling_rate = 1.0           # Float: Sampling rate (0.0-1.0)
end
```

This comprehensive Rails integration provides production-ready observability for AI agent applications with full Rails ecosystem integration, performance optimization, and enterprise-grade security features.
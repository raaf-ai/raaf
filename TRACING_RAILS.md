# OpenAI Agents Rails Tracing Engine

A comprehensive Rails mountable engine for storing, visualizing, and analyzing OpenAI Agents traces in your Rails application's database.

## Features

### Core Functionality
- **Local Database Storage**: Store traces and spans in your Rails database using ActiveRecord
- **Mountable Engine**: Clean integration with any Rails application
- **Real-time Monitoring**: Live dashboard with automatic updates
- **Modern Web Interface**: Responsive UI for trace visualization

### Analytics & Insights
- **Performance Analytics**: Track duration, success rates, and identify bottlenecks
- **Cost & Usage Tracking**: Monitor OpenAI API token consumption and costs
- **Error Analysis**: Automatic error grouping and trend analysis
- **Span Hierarchy Visualization**: Interactive tree view of trace execution

### Advanced Features
- **Advanced Search & Filtering**: Full-text search with complex filters
- **Data Management**: Configurable retention policies and cleanup
- **Rails Integration**: ActiveJob tracing, console helpers, middleware
- **JSON Export**: Export traces for external analysis

## Installation

### 1. Add to your Rails application

The tracing engine is included with the main `openai-agents` gem:

```ruby
# Gemfile
gem 'openai-agents', '~> 1.0'
```

### 2. Run the generator

```bash
rails generate openai_agents:tracing:install
```

This will:
- Create database migrations for traces and spans
- Generate an initializer for configuration  
- Add mount point to your routes
- Display installation instructions

### 3. Run migrations

```bash
rails db:migrate
```

### 4. Mount the engine (done automatically by generator)

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount OpenAIAgents::Tracing::Engine => '/tracing'
  # ... other routes
end
```

## Configuration

### Basic Configuration

```ruby
# config/initializers/openai_agents_tracing.rb
OpenAIAgents::Tracing.configure do |config|
  # Auto-configure the ActiveRecord processor
  config.auto_configure = true
  
  # Mount path for the web interface
  config.mount_path = '/tracing'
  
  # Data retention policy (in days)
  config.retention_days = 30
  
  # Sampling rate (0.0 to 1.0)
  config.sampling_rate = 1.0
end
```

### Manual Processor Setup

If you prefer manual configuration:

```ruby
# config/initializers/openai_agents_tracing.rb
Rails.application.config.after_initialize do
  OpenAIAgents.tracer.add_processor(
    OpenAIAgents::Tracing::ActiveRecordProcessor.new(
      sampling_rate: 0.1,  # Sample 10% of traces
      batch_size: 100      # Batch 100 spans before saving
    )
  )
end
```

### Automatic Cleanup

Set up automatic cleanup of old traces:

```ruby
# config/initializers/openai_agents_tracing.rb
if defined?(ActiveJob)
  class OpenAIAgentsTracingCleanupJob < ApplicationJob
    queue_as :default
    
    def perform
      days = OpenAIAgents::Tracing.configuration.retention_days
      deleted_count = OpenAIAgents::Tracing::Trace.cleanup_old_traces(older_than: days.days)
      Rails.logger.info "Cleaned up #{deleted_count} old traces"
    end
  end
  
  # Schedule cleanup to run daily (requires a job scheduler like sidekiq-cron)
  # OpenAIAgentsTracingCleanupJob.set(cron: '0 2 * * *').perform_later
end
```

## Usage

### Basic Agent Tracing

Once installed, all agent operations are automatically traced:

```ruby
agent = OpenAIAgents::Agent.new(
  name: "CustomerSupport", 
  instructions: "Help customers with their questions.",
  model: "gpt-4o"
)

runner = OpenAIAgents::Runner.new(agent: agent)
result = runner.run("Hello, I need help with my order")

# Traces are automatically saved to the database
# Visit /tracing to view them
```

### Custom Traces

Group multiple operations under a single trace:

```ruby
OpenAIAgents.trace("Order Processing") do
  # All operations here will be part of the same trace
  customer_info = customer_agent.run("Get customer details for order #{order_id}")
  inventory_check = inventory_agent.run("Check inventory for #{items}")
  confirmation = email_agent.run("Send confirmation for order #{order_id}")
end
```

### Custom Spans

Add custom instrumentation to your application:

```ruby
tracer = OpenAIAgents.tracer

tracer.custom_span("data_processing", { rows: 1000 }) do |span|
  span.set_attribute("processing.type", "batch")
  span.set_attribute("data.source", "api")
  
  # Your processing code
  process_data_batch()
  
  span.add_event("processing_complete", { 
    processed_rows: 1000,
    duration: "5.2s" 
  })
end
```

## Web Interface

Visit `/tracing` (or your configured mount path) to access:

### Dashboard
- Overview metrics and recent activity
- Performance trends and health indicators
- Quick access to traces and errors

### Traces
- List all traces with filtering and search
- Detailed trace view with span hierarchy
- Performance and cost analysis per trace

### Analytics
- **Performance**: Response times, success rates, bottleneck identification
- **Costs**: Token usage, model breakdown, workflow consumption
- **Errors**: Error trends, grouping, and detailed analysis

### Spans
- Individual span details and timelines
- Operation-specific attributes and events
- Error context and stack traces

## Database Schema

The engine creates two main tables:

### Traces Table (`openai_agents_tracing_traces`)
- `trace_id` - Unique trace identifier
- `workflow_name` - Human-readable workflow name
- `group_id` - Optional grouping identifier
- `metadata` - JSON metadata
- `started_at` / `ended_at` - Timing information
- `status` - Trace status (pending, running, completed, failed)

### Spans Table (`openai_agents_tracing_spans`) 
- `span_id` - Unique span identifier  
- `trace_id` - Associated trace
- `parent_id` - Parent span for hierarchy
- `name` - Operation name
- `kind` - Span type (agent, llm, tool, etc.)
- `start_time` / `end_time` - Timing
- `duration_ms` - Calculated duration
- `attributes` - JSON operation details
- `events` - JSON event timeline
- `status` - Span status (ok, error, cancelled)

## API Access

All views support JSON export for programmatic access:

```ruby
# Get traces as JSON
GET /tracing/traces.json

# Get specific trace with spans
GET /tracing/traces/trace_abc123.json

# Get performance analytics
GET /tracing/dashboard/performance.json

# Get cost analysis
GET /tracing/dashboard/costs.json
```

## Performance Considerations

### Database Optimization
- Automatic indexing on key columns
- Configurable sampling to reduce volume
- Batch processing for high-throughput applications
- Background processing to avoid blocking requests

### Recommended Settings
```ruby
# High-volume production settings
OpenAIAgents::Tracing::ActiveRecordProcessor.new(
  sampling_rate: 0.1,      # Sample 10% of traces
  batch_size: 100,         # Larger batches
  auto_cleanup: true,      # Enable automatic cleanup
  cleanup_older_than: 7.days  # Shorter retention
)
```

### Storage Estimates
- Average trace: ~1-5KB
- Average span: ~0.5-2KB  
- 1M spans ≈ 500MB-2GB database storage

## Security

### Access Control
The engine provides hooks for authentication:

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :authenticate_admin!, if: -> { request.path.start_with?('/tracing') }
  
  private
  
  def authenticate_admin!
    # Your authentication logic
    redirect_to login_path unless current_user&.admin?
  end
end
```

### Data Sanitization
The ActiveRecord processor automatically:
- Truncates very long strings (>10KB)
- Limits array sizes (max 100 items)
- Converts nested hashes to dot notation

For additional security:

```ruby
# Custom processor with PII scrubbing
class SecureActiveRecordProcessor < OpenAIAgents::Tracing::ActiveRecordProcessor
  private
  
  def sanitize_attributes(attributes)
    scrubbed = super(attributes)
    scrubbed.each do |key, value|
      scrubbed[key] = '[REDACTED]' if key.to_s.match?(/email|password|ssn|phone/)
    end
    scrubbed
  end
end
```

## Troubleshooting

### Common Issues

**"Table doesn't exist" errors:**
```bash
rails db:migrate
# Ensure migrations have run
```

**High database usage:**
```ruby
# Reduce sampling rate
config.sampling_rate = 0.1

# Enable cleanup
processor = OpenAIAgents::Tracing::ActiveRecordProcessor.new(auto_cleanup: true)
```

**Missing traces:**
```ruby
# Check if processor is configured
OpenAIAgents.tracer.processors
# Should include ActiveRecordProcessor

# Check sampling rate
OpenAIAgents::Tracing.configuration.sampling_rate
```

### Debug Mode

Enable debug logging:

```ruby
# config/environments/development.rb
config.log_level = :debug

# Or set environment variable
ENV['OPENAI_AGENTS_TRACE_DEBUG'] = 'true'
```

## Examples

### Multi-Agent Workflow
```ruby
OpenAIAgents.trace("Customer Support Workflow") do
  # Stage 1: Intent classification
  intent = classifier_agent.run("Classify: #{customer_message}")
  
  # Stage 2: Route to specialist
  if intent.includes?("billing")
    response = billing_agent.run(customer_message)
  elsif intent.includes?("technical")  
    response = tech_agent.run(customer_message)
  else
    response = general_agent.run(customer_message)
  end
  
  # Stage 3: Quality check
  quality_agent.run("Review response: #{response}")
end
```

### Background Job Integration
```ruby
class ProcessDataJob < ApplicationJob
  def perform(data_id)
    OpenAIAgents.trace("Data Processing Job") do |trace|
      trace.metadata[:job_id] = job_id
      trace.metadata[:data_id] = data_id
      
      # Your processing logic with automatic tracing
      agent.run("Process data: #{data_id}")
    end
  end
end
```

### Custom Analytics
```ruby
# Get performance metrics programmatically
performance = OpenAIAgents::Tracing::Span.performance_metrics(
  kind: 'llm',
  timeframe: 1.day.ago..Time.current
)

puts "Average LLM response time: #{performance[:avg_duration_ms]}ms"
puts "95th percentile: #{performance[:p95_duration_ms]}ms"
puts "Success rate: #{performance[:success_rate]}%"
```

## Contributing

The tracing engine is part of the main OpenAI Agents Ruby gem. See the main [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

See [LICENSE](LICENSE) file for details.
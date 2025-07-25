**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Tracing Guide
==================

This guide covers comprehensive monitoring and observability for Ruby AI Agents Factory (RAAF) systems. RAAF tracing provides production-grade monitoring with 100% Python SDK compatibility for seamless integration with existing AI infrastructure.

After reading this guide, you will know:

* How to set up comprehensive tracing and monitoring
* Integration with OpenAI dashboards and third-party tools
* Performance monitoring and optimization techniques
* Cost tracking and budget management
* Real-time alerts and anomaly detection

--------------------------------------------------------------------------------

Introduction
------------

### AI-Specific Observability Architecture

RAAF Tracing implements comprehensive observability designed specifically for AI agent systems. Unlike traditional monitoring that focuses on infrastructure metrics, AI observability requires understanding behavior patterns, cost dynamics, and quality metrics unique to AI systems.

### Core Observability Capabilities

**Cross-Platform Compatibility**: 100% compatible trace format with OpenAI Python SDK enables seamless integration with existing AI infrastructure and tooling ecosystems.

**Real-Time Intelligence**: Live dashboards and metrics provide immediate visibility into system behavior, enabling rapid response to issues and optimization opportunities.

**Economic Monitoring**: Detailed cost analysis and budget controls address the unique economic characteristics of AI systems where operational costs vary dramatically based on usage patterns.

**Performance Intelligence**: Response times, token usage, and throughput metrics provide insights into system efficiency and user experience quality.

**Behavioral Analysis**: AI-powered detection of unusual patterns identifies subtle issues that traditional monitoring approaches miss.

**Multi-Platform Integration**: Export capabilities to multiple monitoring systems enable integration with existing observability infrastructure.

### AI System Failure Patterns

AI systems exhibit unique failure patterns that traditional monitoring systems cannot detect. These failures often manifest as behavioral changes rather than infrastructure problems:

**Algorithmic Degradation**: Logic loops, recursive reasoning, and inefficient processing patterns that consume excessive tokens without producing proportional value.

**Quality Drift**: Gradual degradation in response quality, accuracy, or relevance that doesn't trigger traditional error conditions but impacts user experience.

**Cost Escalation**: Unexpected increases in operational costs due to model behavior changes, context expansion, or usage pattern shifts.

**Performance Degradation**: Latency increases, throughput reduction, or user experience degradation that stems from AI-specific issues rather than infrastructure problems.

### Detection Challenges

These AI-specific failure patterns often persist undetected because they don't trigger traditional monitoring alerts. They require specialized detection mechanisms that understand AI behavior patterns and can identify subtle changes in system performance.

### Observability Paradigm Shift

AI observability requires a fundamental shift from infrastructure-focused monitoring to behavior-focused monitoring. Traditional metrics provide incomplete visibility into AI system health.

**Traditional Monitoring Focus**:
- Infrastructure health (CPU, memory, disk)
- Request/response patterns
- Error rates and status codes
- Network performance metrics

**AI Monitoring Requirements**:
- Token consumption patterns and efficiency
- Response quality and relevance metrics
- Cost per interaction and trend analysis
- Model performance and behavior patterns
- Conversation flow and completion rates

### The Visibility Gap

Infrastructure monitoring can show healthy systems while AI-specific problems persist. This visibility gap requires specialized monitoring that understands AI behavior patterns and can identify issues that don't manifest as traditional system failures.

### Multi-Dimensional Monitoring

AI systems require monitoring across multiple dimensions simultaneously: technical performance, economic efficiency, quality metrics, and user experience. This multi-dimensional approach provides comprehensive visibility into system behavior.

### AI Monitoring Complexity

**Non-Deterministic Behavior**: AI systems produce different outputs for identical inputs, making traditional monitoring approaches based on expected responses insufficient. Monitoring must account for probabilistic behavior patterns.

**Variable Cost Structures**: Token usage and associated costs vary dramatically based on context, conversation complexity, and model behavior. This variability makes cost prediction and budgeting challenging.

**Gradual Quality Degradation**: AI models can degrade subtly over time through fine-tuning, context changes, or model updates. This degradation often happens below the threshold of traditional monitoring alerts.

**Cascading Failures**: Individual tool failures can cascade through multi-agent systems, creating complex failure patterns that are difficult to trace and diagnose.

**Multi-Model Complexity**: Systems using multiple models must monitor different behavior patterns, cost structures, and performance characteristics simultaneously, creating monitoring complexity.

### RAAF Observability Architecture

RAAF implements comprehensive observability through multi-layered data capture and analysis:

**Token-Level Monitoring**: Complete tracking of token consumption patterns, including input, output, and total usage with associated costs. This granular monitoring enables precise cost analysis and optimization.

**Decision Intelligence**: Capture of AI reasoning patterns and decision-making processes, providing insights into why specific responses were generated and how the system reached particular conclusions.

**Tool Execution Tracking**: Comprehensive monitoring of tool calls, including execution success, duration, and impact on overall system performance. This tracking enables tool optimization and reliability analysis.

**Workflow Coordination**: Multi-agent handoff tracking that provides visibility into agent coordination, task delegation, and workflow progression.

**Anomaly Detection**: Automated identification of unusual patterns, cost spikes, and performance degradation that might indicate system issues or optimization opportunities.

### Behavioral Intelligence

This comprehensive data collection enables behavioral intelligence that goes beyond traditional logging to provide deep insights into AI system behavior, performance patterns, and optimization opportunities.

**Observability is critical for AI systems.** Traditional applications have predictable performance characteristics—you can monitor CPU, memory, and response times to understand system health. AI systems add new dimensions: token consumption, model performance, conversation quality, and cost per interaction.

Without proper observability, you lack visibility into token consumption patterns, agent performance metrics, and cost trends. Effective optimization requires comprehensive measurement and analysis.

RAAF's tracing system captures every aspect of agent execution: what models were called, how many tokens were consumed, which tools were used, how long operations took, and what errors occurred. This data becomes your feedback loop for optimization and your early warning system for problems.

### Core Components

* **SpanTracer** - Central tracing coordinator
* **Processors** - Export traces to different destinations
* **Collectors** - Gather metrics and telemetry data
* **Analyzers** - AI-powered trace analysis
* **Alerting** - Real-time notifications and escalation

Basic Tracing Setup
-------------------

### Simple Console Tracing

<!-- VALIDATION_FAILED: tracing_guide.md:130 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
<internal:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_require.rb>:136:in 'Kernel#require': cannot load such file -- raaf (LoadError) 	from <internal:/Users/hajee/.rvm/rubies/ruby-3.4.5/lib/ruby/3.4.0/rubygems/core_ext/kernel_require.rb>:136:in 'Kernel#require' 	from /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-wm3guv.rb:444:in '<main>'
```

```ruby
require 'raaf'

# Basic console output for development
tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new)

agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are helpful",
  model: "gpt-4o"
)

runner = RAAF::Runner.new(
  agent: agent,
  tracer: tracer
)

result = runner.run("Hello!")
# Traces automatically logged to console
```

### OpenAI Dashboard Integration

```ruby
# Send traces to OpenAI dashboard (Python SDK compatible)
openai_processor = RAAF::Tracing::OpenAIProcessor.new(
  api_key: ENV['OPENAI_API_KEY'],
  project_id: ENV['OPENAI_PROJECT_ID'],
  batch_size: 100,
  flush_interval: 30.seconds
)

tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(openai_processor)

runner = RAAF::Runner.new(agent: agent, tracer: tracer)
# Traces automatically appear in OpenAI dashboard
```

### Multi-Destination Tracing

<!-- VALIDATION_FAILED: tracing_guide.md:172 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::Tracing::DatadogProcessor /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-uw7mio.rb:457:in '<main>'
```

```ruby
# Send traces to multiple destinations
tracer = RAAF::Tracing::SpanTracer.new

# Development debugging
tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new(
  log_level: :debug,
  include_payloads: true
))

# OpenAI dashboard
tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)

# Custom analytics
tracer.add_processor(RAAF::Tracing::DatadogProcessor.new(
  api_key: ENV['DATADOG_API_KEY'],
  site: 'datadoghq.com'
))

# File storage for compliance
tracer.add_processor(RAAF::Tracing::FileProcessor.new(
  directory: './traces',
  rotation: :daily,
  compression: true
))
```

Trace Processors
----------------

### Multi-Destination Trace Processing

Organizations often require trace data in multiple systems to serve different stakeholder needs:

- DevOps teams need integration with monitoring platforms like Datadog
- Security teams require audit logs in secure storage like S3
- Executive teams need real-time dashboards for visibility
- Developers need console output for debugging
- Finance teams need cost breakdowns for analysis

Running traces through multiple separate pipelines creates operational complexity and resource overhead.

Pluggable processors solve this challenge by enabling one trace collection system to output to multiple destinations simultaneously.

### Why Traditional Logging Fails for AI

**Traditional App Log**: `[INFO] User 123 logged in - 200ms`

**AI App Reality**: 
```
[INFO] Agent started thinking...
[...2000 tokens later...]
[INFO] Agent still thinking...
[...3000 more tokens...]
[ERROR] Agent had an existential crisis
[COST] $4.73 for one "thought"
```

You need structured tracing that captures the full story, not just log lines.

### Console Processor: Your Development Best Friend

Development-friendly console output:

```ruby
console_processor = RAAF::Tracing::ConsoleProcessor.new(
  log_level: :info,           # :debug, :info, :warn, :error
  colorize: true,             # Colorize output
  include_payloads: false,    # Include request/response payloads
  include_timing: true,       # Include timing information
  include_tokens: true,       # Include token usage
  format: :pretty             # :pretty, :json, :compact
)
```

### OpenAI Processor

Integration with OpenAI's monitoring dashboard:

```ruby
openai_processor = RAAF::Tracing::OpenAIProcessor.new(
  api_key: ENV['OPENAI_API_KEY'],
  organization: ENV['OPENAI_ORG_ID'],
  project_id: ENV['OPENAI_PROJECT_ID'],
  
  # Batching configuration
  batch_size: 100,
  max_batch_delay: 30.seconds,
  max_memory_usage: 10.megabytes,
  
  # Retry configuration
  max_retries: 3,
  retry_backoff: :exponential,
  retry_jitter: true,
  
  # Filtering
  include_successful_traces: true,
  include_error_traces: true,
  min_duration_ms: 100
)
```

### Database Processor

Store traces in database for analysis:

<!-- VALIDATION_FAILED: tracing_guide.md:278 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::Tracing::DatabaseProcessor /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-gbjpbm.rb:444:in '<main>'
```

```ruby
db_processor = RAAF::Tracing::DatabaseProcessor.new(
  connection: ActiveRecord::Base.connection,
  table_name: 'ai_traces',
  batch_size: 50,
  
  # Schema mapping
  column_mapping: {
    trace_id: 'id',
    span_id: 'span_id',
    parent_span_id: 'parent_id',
    operation_name: 'operation',
    start_time: 'started_at',
    end_time: 'ended_at',
    duration_ms: 'duration',
    attributes: 'metadata',
    events: 'events'
  }
)
```

### Custom Processors

Create custom processors for specific needs:

<!-- VALIDATION_FAILED: tracing_guide.md:303 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::Tracing::BaseProcessor /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-on3qoo.rb:444:in '<main>'
```

```ruby
class SlackProcessor < RAAF::Tracing::BaseProcessor
  def initialize(webhook_url, alert_threshold: 5000)
    @webhook_url = webhook_url
    @alert_threshold = alert_threshold
  end
  
  def process_span(span)
    # Alert on slow operations
    if span.duration_ms > @alert_threshold
      send_slack_alert(span)
    end
    
    # Alert on errors
    if span.status == 'error'
      send_error_alert(span)
    end
  end
  
  private
  
  def send_slack_alert(span)
    message = {
      text: "🐌 Slow AI operation detected",
      attachments: [{
        color: "warning",
        fields: [
          { title: "Operation", value: span.operation_name, short: true },
          { title: "Duration", value: "#{span.duration_ms}ms", short: true },
          { title: "Agent", value: span.attributes[:agent_name], short: true },
          { title: "Model", value: span.attributes[:model], short: true }
        ]
      }]
    }
    
    HTTParty.post(@webhook_url, body: message.to_json, headers: { 'Content-Type' => 'application/json' })
  end
end

tracer.add_processor(SlackProcessor.new(ENV['SLACK_WEBHOOK_URL']))
```

Performance Monitoring
----------------------

### Cost Monitoring Requirements

Unexpected AI system costs can accumulate rapidly without proper monitoring. Cost monitoring addresses scenarios where system bugs cause excessive API usage.

A diagnostic example: An agent stuck in a recursive loop generated 10,000-token responses continuously, accumulating substantial costs over time. The issue remained undetected due to lack of cost monitoring and alerting.

This scenario illustrates why comprehensive performance monitoring is essential for AI systems.

### Why AI Performance Monitoring Is Unlike Anything Else

**Traditional Metrics**:

- Requests per second
- CPU usage
- Memory consumption

**AI Metrics That Actually Matter**:

- Tokens per conversation
- Cost per user interaction  
- Time to useful response (not just first byte)
- Conversation completion rate
- Hallucination frequency
- Tool call success rate

### Essential AI System Metrics

1. **The Money Metrics**
   - Cost per conversation: avg $0.12, alert if >$1
   - Daily spend rate: budget $500/day
   - Cost by agent type: Support ($0.08) vs Research ($0.45)

2. **The Quality Metrics**
   - Conversation success rate: 94%
   - Average turns to resolution: 3.2
   - Tool call effectiveness: 87%

3. **The Danger Metrics**
   - Recursive loop detection
   - Token consumption spikes
   - Error cascade patterns
   - Conversation abandonment rate

### Metrics Collection

```ruby
# Comprehensive metrics collection
metrics_tracer = RAAF::Tracing::MetricsTracer.new(
  base_tracer: tracer,
  metrics_backend: :prometheus,  # :prometheus, :statsd, :datadog
  collection_interval: 10.seconds,
  
  # Metrics to collect
  metrics: {
    request_count: { type: :counter, labels: [:agent_name, :model, :status] },
    request_duration: { type: :histogram, labels: [:agent_name, :model] },
    token_usage: { type: :gauge, labels: [:agent_name, :model, :type] },
    cost_tracking: { type: :counter, labels: [:agent_name, :provider] },
    error_rate: { type: :gauge, labels: [:agent_name, :error_type] }
  }
)

# Access metrics
metrics = metrics_tracer.get_metrics(
  timeframe: 1.hour.ago..Time.now,
  labels: { agent_name: 'CustomerService' }
)

puts "Request count: #{metrics[:request_count]}"
puts "Average duration: #{metrics[:avg_duration]}ms"
puts "Token usage: #{metrics[:total_tokens]}"
puts "Total cost: $#{metrics[:total_cost]}"
```

### Performance Analytics

```ruby
# AI-powered performance analysis
analyzer = RAAF::Tracing::PerformanceAnalyzer.new(
  tracer: tracer,
  analysis_model: 'gpt-4o-mini',
  analysis_interval: 1.hour,
  
  # Analysis dimensions
  analyze: [
    :response_times,
    :token_efficiency,
    :error_patterns,
    :cost_optimization,
    :usage_patterns
  ]
)

# Get performance insights
insights = analyzer.analyze(
  timeframe: 24.hours.ago..Time.now,
  focus_areas: [:performance, :cost]
)

insights.each do |insight|
  puts "Category: #{insight[:category]}"
  puts "Insight: #{insight[:description]}"
  puts "Recommendation: #{insight[:recommendation]}"
  puts "Potential savings: #{insight[:potential_savings]}"
  puts "---"
end
```

### Real-time Dashboards

<!-- VALIDATION_FAILED: tracing_guide.md:458 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::Tracing::RealTimeDashboard /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-zupo06.rb:445:in '<main>'
```

```ruby
# Real-time dashboard with WebSockets
dashboard = RAAF::Tracing::RealTimeDashboard.new(
  tracer: tracer,
  port: 3001,
  
  # Dashboard configuration
  refresh_interval: 5.seconds,
  max_data_points: 1000,
  
  # Widgets
  widgets: [
    { type: :request_rate, title: 'Requests/minute' },
    { type: :response_time, title: 'Avg Response Time' },
    { type: :token_usage, title: 'Token Usage' },
    { type: :cost_tracking, title: 'Cost per Hour' },
    { type: :error_rate, title: 'Error Rate %' },
    { type: :agent_performance, title: 'Agent Performance' }
  ]
)

dashboard.start
# Dashboard available at http://localhost:3001
```

Cost Tracking and Management
---------------------------

### Rapid Cost Accumulation in AI Systems

AI systems can accumulate significant costs rapidly, especially when bugs cause excessive API usage. Cost monitoring is essential for preventing unexpected expenses.

For example, a bug that causes an agent to enter a loop or repeatedly make API calls can quickly consume large amounts of tokens, leading to substantial costs in a short time period.

### AI Cost Management

**Traditional software costs**: Predictable infrastructure expenses for servers, bandwidth, and storage.

**AI costs**: Variable expenses based on usage patterns:

- Simple queries: $0.02
- Research tasks: $4.50
- Complex analysis: $47.00
- Uncontrolled loops: Potentially unlimited costs

### Cost Management Principles

1. **Comprehensive tracking**: Monitor every token, API call, and associated cost
2. **Early warning systems**: Alert before costs reach problematic levels
3. **Automatic controls**: Implement safety mechanisms to prevent runaway costs

### Detailed Cost Analysis

```ruby
cost_tracker = RAAF::Tracing::CostTracker.new(
  tracer: tracer,
  
  # Provider pricing (per 1M tokens)
  pricing: {
    'gpt-4o' => { input: 5.00, output: 15.00 },
    'gpt-4o-mini' => { input: 0.15, output: 0.60 },
    'claude-3-5-sonnet-20241022' => { input: 3.00, output: 15.00 },
    'claude-3-haiku-20240307' => { input: 0.25, output: 1.25 }
  },
  
  # Cost allocation
  allocation_strategy: :usage_based,
  track_by: [:agent, :user, :project, :environment]
)

# Get cost breakdown
cost_report = cost_tracker.generate_report(
  timeframe: 1.month.ago..Time.now,
  breakdown_by: [:agent_name, :model, :user_id]
)

cost_report.each do |breakdown|
  puts "Agent: #{breakdown[:agent_name]}"
  puts "Model: #{breakdown[:model]}"
  puts "Requests: #{breakdown[:request_count]}"
  puts "Input tokens: #{breakdown[:input_tokens]:,}"
  puts "Output tokens: #{breakdown[:output_tokens]:,}"
  puts "Cost: $#{breakdown[:total_cost]:.4f}"
  puts "---"
end
```

### Budget Management

<!-- VALIDATION_FAILED: tracing_guide.md:547 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::Tracing::BudgetManager /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-nugaqk.rb:444:in '<main>'
```

```ruby
budget_manager = RAAF::Tracing::BudgetManager.new(
  cost_tracker: cost_tracker,
  
  # Budget limits
  budgets: {
    daily: 100.00,    # $100/day
    monthly: 2000.00, # $2000/month
    per_user: 10.00   # $10/user/day
  },
  
  # Actions when limits approached
  thresholds: {
    warning: 0.75,    # Alert at 75%
    critical: 0.90,   # Escalate at 90%
    cutoff: 1.0       # Block at 100%
  },
  
  # Notification channels
  alerts: [
    RAAF::Tracing::SlackAlert.new(webhook: ENV['SLACK_WEBHOOK']),
    RAAF::Tracing::EmailAlert.new(recipients: ['admin@company.com']),
    RAAF::Tracing::PagerDutyAlert.new(service_key: ENV['PAGERDUTY_KEY'])
  ]
)

# Check budget status
status = budget_manager.check_status
if status[:over_budget]
  puts "⚠️  Over budget! Current: $#{status[:current_spend]}, Limit: $#{status[:budget_limit]}"
end
```

### Cost Optimization

```ruby
cost_optimizer = RAAF::Tracing::CostOptimizer.new(
  tracer: tracer,
  cost_tracker: cost_tracker,
  
  # Optimization strategies
  strategies: [
    :model_routing,        # Route to cheaper models when appropriate
    :token_optimization,   # Reduce token usage
    :caching,             # Cache responses
    :batch_processing,    # Batch similar requests
    :request_deduplication # Remove duplicate requests
  ]
)

# Get optimization recommendations
recommendations = cost_optimizer.analyze(
  timeframe: 1.week.ago..Time.now
)

recommendations.each do |rec|
  puts "Strategy: #{rec[:strategy]}"
  puts "Description: #{rec[:description]}"
  puts "Potential savings: $#{rec[:estimated_savings]:.2f}/month"
  puts "Confidence: #{rec[:confidence]}%"
  puts "Implementation effort: #{rec[:effort_level]}"
  puts "---"
end
```

Anomaly Detection
-----------------

### Limitations of Traditional Monitoring

Traditional metrics may indicate normal system performance while behavioral issues persist. Response times and error rates can appear normal while the AI system exhibits problematic behavior patterns.

For example, an AI system might learn counterproductive patterns that technically execute successfully but create poor user experiences. Anomaly detection can identify these subtle behavioral changes that standard monitoring misses.

### Why Normal Monitoring Misses AI Problems

**What traditional monitoring sees**: 

- ✅ Response time: 2.3s (normal)
- ✅ Error rate: 0.2% (normal)
- ✅ Uptime: 99.9% (great!)

**Actual AI system issues**:

- AI generating inaccurate or fabricated information
- Distributed cost increases across user base
- Technically successful but ineffective conversations
- AI reinforcing problematic learned patterns

### Common AI System Degradation Patterns

1. **Gradual drift**: AI performance slowly degrades over time
2. **Context explosion**: Specific topics trigger excessive token consumption
3. **Confidence inflation**: AI becomes overly confident in incorrect responses
4. **Tool overuse**: Specific tools experience abnormal usage patterns
5. **Cost escalation**: Gradual increase in per-interaction costs

### AI-Powered Anomaly Detection

AI-powered monitoring uses machine learning to detect patterns that traditional rule-based monitoring might miss.

Our anomaly detection looks for:

- **Behavioral changes**: Is the AI acting differently?
- **Statistical outliers**: Unusual patterns in any metric
- **Sentiment shifts**: Are users getting frustrated?
- **Cost anomalies**: Spending patterns that don't match usage
- **Quality degradation**: Subtle drops in usefulness

### AI-Powered Analysis

```ruby
anomaly_detector = RAAF::Tracing::AnomalyDetector.new(
  tracer: tracer,
  detection_model: 'gpt-4o-mini',
  
  # Detection parameters
  baseline_period: 7.days,
  sensitivity: :medium,     # :low, :medium, :high
  analysis_interval: 15.minutes,
  
  # Anomaly types to detect
  detect: [
    :unusual_response_times,
    :error_rate_spikes,
    :token_usage_anomalies,
    :cost_deviations,
    :request_pattern_changes,
    :security_anomalies
  ]
)

# Real-time anomaly detection
anomaly_detector.start_monitoring do |anomaly|
  puts "🚨 Anomaly detected!"
  puts "Type: #{anomaly[:type]}"
  puts "Severity: #{anomaly[:severity]}"
  puts "Description: #{anomaly[:description]}"
  puts "Confidence: #{anomaly[:confidence]}%"
  puts "Affected agents: #{anomaly[:affected_agents]}"
  
  # Take automated action
  case anomaly[:severity]
  when 'critical'
    # Auto-scale or circuit break
    circuit_breaker.open_for_agent(anomaly[:affected_agents])
  when 'high'
    # Alert on-call team
    pager_duty.trigger_alert(anomaly)
  when 'medium'
    # Log and monitor
    logger.warn("Anomaly detected: #{anomaly[:description]}")
  end
end
```

### Statistical Anomaly Detection

```ruby
stats_detector = RAAF::Tracing::StatisticalAnomalyDetector.new(
  tracer: tracer,
  
  # Statistical methods
  methods: [
    { type: :z_score, threshold: 3.0 },
    { type: :iqr, multiplier: 1.5 },
    { type: :isolation_forest, contamination: 0.1 },
    { type: :time_series, seasonality: :daily }
  ],
  
  # Metrics to monitor
  metrics: [
    'response_time_p99',
    'token_usage_rate',
    'error_rate',
    'cost_per_request'
  ]
)

# Detect anomalies in historical data
anomalies = stats_detector.detect_anomalies(
  timeframe: 24.hours.ago..Time.now,
  granularity: 1.minute
)

anomalies.each do |anomaly|
  puts "Timestamp: #{anomaly[:timestamp]}"
  puts "Metric: #{anomaly[:metric]}"
  puts "Value: #{anomaly[:value]}"
  puts "Expected: #{anomaly[:expected_range]}"
  puts "Deviation: #{anomaly[:deviation]}σ"
end
```

Distributed Tracing
-------------------

### Distributed System Latency Investigation

Distributed AI systems can experience latency issues that aren't apparent from individual service metrics. A customer complaint about 30-second response times illustrates this challenge.

Individual service metrics appeared normal:

- AI Gateway: 200ms ✅
- Agent Service: 1.5s ✅
- Tool Service: 500ms ✅
- Database Service: 100ms ✅

Investigation revealed cascading service calls: Each service was calling multiple other services, creating exponential growth in API calls. A single user message triggered 147 individual service calls, causing significant latency.

### Distributed Tracing Requirements

Monolithic applications allow straightforward request tracing with debuggers. Distributed AI systems require specialized tracing to understand request flow across multiple services.

Your AI agent might:

1. Start in the web service
2. Call the agent orchestrator
3. Which calls the LLM gateway
4. Which calls OpenAI
5. Which returns to the orchestrator
6. Which calls three tool services
7. Which each call databases
8. Which return to the orchestrator
9. Which calls another agent
10. Which... you get the idea

Distributed tracing provides essential visibility into multi-service request flows.

### Multi-Service Tracing

<!-- VALIDATION_FAILED: tracing_guide.md:778 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::Tracing::DistributedTracer /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-g86mm5.rb:445:in '<main>'
```

```ruby
# Distributed tracing across services
distributed_tracer = RAAF::Tracing::DistributedTracer.new(
  service_name: 'ai-agent-service',
  trace_propagation: :w3c,     # :jaeger, :b3, :w3c
  
  # Service mesh integration
  mesh_integration: {
    istio: true,
    linkerd: false,
    consul_connect: false
  }
)

# Propagate trace context
class AgentController < ApplicationController
  def chat
    # Extract trace context from request headers
    trace_context = distributed_tracer.extract_context(request.headers)
    
    runner = RAAF::Runner.new(
      agent: agent,
      tracer: distributed_tracer,
      trace_context: trace_context
    )
    
    result = runner.run(params[:message])
    
    # Inject trace context into response
    distributed_tracer.inject_context(response.headers, trace_context)
    
    render json: { response: result.messages.last[:content] }
  end
end
```

### Cross-Agent Tracing

<!-- VALIDATION_FAILED: tracing_guide.md:816 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::Tracing::MultiAgentTracer /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-lu7ny2.rb:445:in '<main>'
```

```ruby
# Trace spans across multiple agents
multi_agent_tracer = RAAF::Tracing::MultiAgentTracer.new(
  base_tracer: tracer,
  correlation_strategy: :conversation_id,
  
  # Agent relationships
  agent_topology: {
    'CustomerService' => ['TechnicalSupport', 'BillingAgent'],
    'TechnicalSupport' => ['ExpertAgent'],
    'ResearchAgent' => ['WriterAgent', 'EditorAgent']
  }
)

# Workflow tracing
workflow_span = multi_agent_tracer.start_workflow_span(
  workflow_name: 'customer_issue_resolution',
  correlation_id: 'conv_123'
)

begin
  # Agent 1
  cs_result = customer_service_runner.run(user_message)
  
  # Agent 2 (if handoff occurred)
  if cs_result.handoff_requested?
    tech_result = technical_support_runner.run(cs_result.handoff_context)
  end
  
ensure
  multi_agent_tracer.finish_workflow_span(workflow_span)
end
```

Testing and Development
-----------------------

### Critical Importance of Tracing System Testing

Tracing system failures can cause critical application failures if not properly tested. A scenario demonstrates this risk:

During pre-deployment testing, a QA engineer tested tracing failure scenarios by disconnecting network connectivity. The test revealed that the entire system froze when tracing endpoints became unavailable. Every request waited for traces to send, causing request accumulation and system failure.

This scenario demonstrates why testing tracing system failure modes is as important as testing core application logic.

### Why Testing AI Tracing Is Different

**Traditional testing**: Mock the external services, test your logic.

**AI tracing reality**: 

- Traces affect performance (adding 50ms to every call)
- Trace failures can cascade (one bad processor blocks everything)
- Trace data is critical for debugging (can't debug without it)
- Trace volume can overwhelm systems (GB per hour)

### Comprehensive Trace Testing Strategy

1. **Unit Level**: Does the trace capture the right data?
2. **Integration Level**: Do traces flow through the system correctly?
3. **Chaos Level**: What happens when everything goes wrong?

### Mock Tracing

<!-- VALIDATION_FAILED: tracing_guide.md:880 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::Tracing::MockTracer /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-vydh2g.rb:445:in '<main>'
```

```ruby
# Mock tracer for testing
mock_tracer = RAAF::Tracing::MockTracer.new(
  capture_spans: true,
  simulate_latency: false,
  fail_probability: 0.0
)

# In tests
RSpec.describe 'Agent Performance' do
  let(:tracer) { RAAF::Tracing::MockTracer.new }
  let(:runner) { RAAF::Runner.new(agent: agent, tracer: tracer) }
  
  it 'traces agent execution' do
    result = runner.run("Hello")
    
    spans = tracer.captured_spans
    expect(spans).to have(1).span
    
    agent_span = spans.first
    expect(agent_span.operation_name).to eq('agent.run')
    expect(agent_span.attributes[:agent_name]).to eq('TestAgent')
    expect(agent_span.duration_ms).to be > 0
  end
  
  it 'traces tool usage' do
    runner.run("What time is it?")
    
    spans = tracer.captured_spans
    tool_spans = spans.select { |s| s.operation_name.start_with?('tool.') }
    
    expect(tool_spans).not_to be_empty
    expect(tool_spans.first.attributes[:tool_name]).to eq('get_current_time')
  end
end
```

### Development Profiling

<!-- VALIDATION_FAILED: tracing_guide.md:919 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::Tracing::ProfilingTracer /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-678pnf.rb:445:in '<main>'
```

```ruby
# Development profiling
profiling_tracer = RAAF::Tracing::ProfilingTracer.new(
  base_tracer: tracer,
  profile_memory: true,
  profile_cpu: true,
  profile_io: true,
  
  # Profiling thresholds
  min_duration_ms: 100,
  memory_threshold_mb: 10,
  
  # Output configuration
  output_format: :flamegraph,
  output_directory: './profiling'
)

# Generate performance profile
runner = RAAF::Runner.new(agent: agent, tracer: profiling_tracer)
result = runner.run("Complex task that might be slow")

# View profiling results
profiling_tracer.generate_report
# Creates ./profiling/agent_performance_flamegraph.html
```

Production Deployment
--------------------

### Production Tracing Requirements

Production AI systems require robust tracing infrastructure to maintain operational visibility during critical failures.

A common scenario: AI agents continue functioning while tracing systems fail, creating a blind spot during troubleshooting. This situation demonstrates why tracing infrastructure must be designed with the same reliability standards as core application systems.

Single points of failure in tracing systems can eliminate visibility during outages, making diagnosis and resolution significantly more difficult.

### High-Availability Tracing Architecture

Production tracing systems serve as the primary diagnostic tool during system failures. Like aircraft flight recorders, tracing systems must remain operational during the events they're designed to monitor.

Tracing systems face reliability challenges: they often experience failures during the same conditions that affect the primary application—high load, network issues, and cascading failures.

### The Four Pillars of Production Tracing

1. **Redundancy**: Multiple independent trace paths
2. **Buffering**: Don't lose traces during failures
3. **Sampling**: Survive traffic spikes
4. **Isolation**: Tracing failures don't affect the main system

### High-Availability Setup

<!-- VALIDATION_FAILED: tracing_guide.md:971 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::Tracing::ProductionTracer /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-s8pxdr.rb:445:in '<main>'
```

```ruby
# Production tracing with HA
production_tracer = RAAF::Tracing::ProductionTracer.new(
  # Multiple processors for redundancy
  processors: [
    RAAF::Tracing::OpenAIProcessor.new,
    RAAF::Tracing::DatadogProcessor.new,
    RAAF::Tracing::DatabaseProcessor.new
  ],
  
  # Circuit breaker for processor failures
  circuit_breaker: {
    failure_threshold: 5,
    timeout: 30.seconds,
    recovery_timeout: 5.minutes
  },
  
  # Buffering for reliability
  buffering: {
    max_buffer_size: 10000,
    flush_interval: 30.seconds,
    persist_buffer: true,
    buffer_directory: './trace_buffer'
  },
  
  # Sampling for high-volume scenarios
  sampling: {
    strategy: :adaptive,
    target_rate: 1000,    # traces per second
    max_sample_rate: 1.0,
    min_sample_rate: 0.01
  }
)
```

### Kubernetes Integration

```yaml
# kubernetes/tracing-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: raaf-tracing-config
data:
  config.yaml: |
    tracing:
      service_name: "raaf-agents"
      environment: "production"
      
      processors:

        - type: "openai"
          api_key_secret: "openai-api-key"
          batch_size: 100
          
        - type: "jaeger"
          endpoint: "http://jaeger-collector:14268/api/traces"
          
        - type: "prometheus"
          push_gateway: "http://prometheus-pushgateway:9091"
          
      sampling:
        strategy: "probabilistic"
        rate: 0.1
        
      resource_limits:
        max_memory: "256Mi"
        max_cpu: "100m"
```

### Monitoring Setup

<!-- VALIDATION_FAILED: tracing_guide.md:1043 -->
WARNING: **EXAMPLE VALIDATION FAILED** - This example needs work and contributions are welcome! Please see [Contributing to RAAF](contributing_to_raaf.md) for guidance. ```
Error: NameError: uninitialized constant RAAF::Tracing::MonitoringStack /var/folders/r5/1t1h14ts04v5plm6tg1237pr0000gn/T/code_block20250725-12953-yf6774.rb:445:in '<main>'
```

```ruby
# Comprehensive monitoring stack
monitoring_stack = RAAF::Tracing::MonitoringStack.new(
  # Core components
  tracer: production_tracer,
  metrics_collector: RAAF::Tracing::PrometheusCollector.new,
  log_aggregator: RAAF::Tracing::LogAggregator.new,
  
  # Alerting
  alert_manager: RAAF::Tracing::AlertManager.new(
    channels: [
      { type: :slack, webhook: ENV['SLACK_WEBHOOK'] },
      { type: :email, recipients: ['ops@company.com'] },
      { type: :pagerduty, integration_key: ENV['PAGERDUTY_KEY'] }
    ],
    
    rules: [
      {
        name: 'High Error Rate',
        condition: 'error_rate > 0.05',
        for: '5m',
        severity: 'critical'
      },
      {
        name: 'High Latency',
        condition: 'p99_latency > 10s',
        for: '2m', 
        severity: 'warning'
      },
      {
        name: 'Budget Exceeded',
        condition: 'daily_cost > budget_limit',
        for: '1m',
        severity: 'critical'
      }
    ]
  )
)

monitoring_stack.start
```

Next Steps
----------

### Implementing Comprehensive Tracing

Effective tracing transforms AI systems from opaque black boxes into transparent, observable systems. Comprehensive tracing provides visibility into system behavior, enabling rapid diagnosis and resolution of issues.

Tracing systems capture decision points, cost accumulation, and timing information. This visibility enables precise problem identification when issues occur, reducing mean time to resolution significantly.

### The Path Forward

Now that you understand RAAF tracing, here's your journey:

1. **Start Simple**: Add console tracing to development. See what your agents are really doing.

2. **Measure What Matters**: Track the metrics that affect your business:
   - Cost per conversation (not just API costs)
   - Time to resolution (not just response time)
   - User satisfaction (not just success rate)

3. **Build Your Safety Net**: Before you go to production:
   - Set up cost alerts (prevent unexpected expense accumulation)
   - Implement anomaly detection (catch problems early)
   - Create runbooks based on trace patterns

4. **Scale with Confidence**: With proper tracing, you can:
   - Handle traffic spikes (sample intelligently)
   - Debug production issues (distributed tracing)
   - Optimize costs (find the expensive patterns)

### Your Next Deep Dives

* **[Performance Guide](performance_guide.html)** - Turn trace data into 10x performance improvements
* **[Cost Management](cost_guide.html)** - Build AI systems that don't bankrupt you
* **[Configuration Reference](configuration_reference.html)** - Production monitoring configuration
* **[RAAF Rails Guide](rails_guide.html)** - Beautiful dashboards your CEO will love
* **[Troubleshooting](troubleshooting.html)** - Debug AI problems like a detective

### Tracing in Practice

Tracing enables rapid problem diagnosis through comprehensive system visibility. A typical troubleshooting scenario demonstrates this effectiveness:

A customer reported degraded AI assistant performance. Trace analysis revealed:

- Model version update increased response length
- Token usage increased 23%
- Cost controls activated automatically
- Response truncation affected perceived quality

The solution involved adjusting token budgets to accommodate the new model characteristics. Total resolution time: 12 minutes.

This diagnostic speed results from comprehensive tracing that captures all system interactions and decision points.
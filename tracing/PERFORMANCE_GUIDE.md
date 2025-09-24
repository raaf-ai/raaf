# RAAF Tracing Performance Guide

This guide covers performance considerations, optimization strategies, and best practices for using RAAF's coherent tracing system in production environments.

## Table of Contents

- [Performance Overview](#performance-overview)
- [Memory Management](#memory-management)
- [Batching and Buffering](#batching-and-buffering)
- [Selective Tracing](#selective-tracing)
- [High-Throughput Scenarios](#high-throughput-scenarios)
- [Monitoring and Profiling](#monitoring-and-profiling)
- [Production Recommendations](#production-recommendations)

## Performance Overview

### Baseline Performance Impact

RAAF coherent tracing is designed to have minimal performance impact:

- **Span creation overhead**: ~0.1-0.5ms per span
- **Memory per span**: ~2-5KB depending on attributes
- **Network batching**: Default 50 spans per batch, 5-second intervals
- **CPU usage**: <1% additional CPU load in typical scenarios

### Performance Characteristics

```ruby
# Measure tracing overhead
class PerformanceMonitor
  def initialize
    @measurements = []
  end

  def measure_operation(name, &block)
    # Without tracing
    start_time = Time.now
    result = block.call
    baseline_time = Time.now - start_time

    # With tracing
    start_time = Time.now
    component.with_tracing(name) { block.call }
    traced_time = Time.now - start_time

    overhead = traced_time - baseline_time
    @measurements << { name: name, baseline: baseline_time, overhead: overhead }

    puts "Operation: #{name}"
    puts "  Baseline: #{baseline_time * 1000}ms"
    puts "  With tracing: #{traced_time * 1000}ms"
    puts "  Overhead: #{overhead * 1000}ms (#{((overhead / baseline_time) * 100).round(1)}%)"

    result
  end
end
```

## Memory Management

### Span Memory Usage

Each span consumes memory for:
- Span metadata (ID, timestamps, hierarchy)
- Attributes hash
- Events array
- Internal tracking structures

```ruby
# Monitor span memory usage
def analyze_span_memory
  before_gc = GC.stat[:total_allocated_objects]

  # Create 1000 spans
  1000.times do |i|
    agent.with_tracing("operation_#{i}") do
      sleep(0.001)
    end
  end

  GC.start
  after_gc = GC.stat[:total_allocated_objects]

  puts "Objects allocated: #{after_gc - before_gc}"
  puts "Estimated per span: #{(after_gc - before_gc) / 1000} objects"
end
```

### Memory Optimization Strategies

#### 1. Configure Memory Limits

```ruby
# Set environment variables for memory management
ENV['RAAF_TRACE_MAX_SPANS'] = '1000'     # Limit spans in memory
ENV['RAAF_TRACE_CLEANUP_INTERVAL'] = '60' # Cleanup interval in seconds

# Or programmatically
RAAF::Tracing.configure do |config|
  config.max_spans_in_memory = 1000
  config.cleanup_interval = 60
end
```

#### 2. Efficient Attribute Collection

```ruby
# GOOD: Lightweight attribute collection
def collect_span_attributes
  super.merge({
    "agent.name" => @name,                    # Simple string
    "agent.model" => @model,                  # Cached value
    "agent.tool_count" => @tools&.size || 0  # Simple calculation
  })
end

# AVOID: Expensive attribute collection
def collect_span_attributes
  super.merge({
    "agent.complex_analysis" => perform_expensive_analysis,    # Slow!
    "agent.database_stats" => query_database_for_stats,       # Network I/O!
    "agent.file_contents" => File.read(large_file_path)       # Large data!
  })
end
```

#### 3. Lazy Attribute Evaluation

```ruby
class OptimizedAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def collect_span_attributes
    # Cache expensive calculations
    @cached_stats ||= calculate_stats

    super.merge({
      "agent.name" => @name,
      "agent.stats" => @cached_stats,
      "agent.timestamp" => Time.now.to_i  # Efficient timestamp
    })
  end

  private

  def calculate_stats
    # Only calculate once, cache result
    @stats_calculated_at = Time.now
    { calculated_at: @stats_calculated_at, tool_count: @tools.size }
  end
end
```

## Batching and Buffering

### Default Batching Configuration

```ruby
# Default settings
ENV['RAAF_TRACE_BATCH_SIZE'] = '50'       # Spans per batch
ENV['RAAF_TRACE_FLUSH_INTERVAL'] = '5'    # Seconds between flushes
ENV['RAAF_TRACE_MAX_BATCH_WAIT'] = '30'   # Max seconds to wait for batch
```

### Optimizing for Different Scenarios

#### High-Frequency, Low-Latency
```ruby
# For real-time applications requiring low latency
ENV['RAAF_TRACE_BATCH_SIZE'] = '10'       # Smaller batches
ENV['RAAF_TRACE_FLUSH_INTERVAL'] = '1'    # Frequent flushes

# Custom real-time processor
class RealTimeProcessor
  def initialize
    @buffer = []
    @last_flush = Time.now
  end

  def on_span_end(span)
    @buffer << span

    # Flush immediately for critical spans
    if span.attributes["priority"] == "critical"
      flush_now
    elsif should_flush?
      flush_now
    end
  end

  private

  def should_flush?
    @buffer.size >= 10 || (Time.now - @last_flush) > 1
  end

  def flush_now
    return if @buffer.empty?

    send_spans(@buffer.dup)
    @buffer.clear
    @last_flush = Time.now
  end
end
```

#### High-Throughput, Batch-Tolerant
```ruby
# For high-volume applications that can tolerate some delay
ENV['RAAF_TRACE_BATCH_SIZE'] = '500'      # Large batches
ENV['RAAF_TRACE_FLUSH_INTERVAL'] = '30'   # Less frequent flushes

# High-throughput processor with compression
class HighThroughputProcessor
  def initialize
    @buffer = []
    @compression_enabled = true
    @max_buffer_size = 1000
  end

  def on_span_end(span)
    @buffer << span

    if @buffer.size >= @max_buffer_size
      flush_with_compression
    end
  end

  def force_flush
    flush_with_compression unless @buffer.empty?
  end

  private

  def flush_with_compression
    spans_data = @buffer.map(&:to_h)

    if @compression_enabled
      compressed_data = compress_spans(spans_data)
      send_compressed_spans(compressed_data)
    else
      send_spans(spans_data)
    end

    @buffer.clear
  end

  def compress_spans(spans)
    # Implement compression logic
    require 'zlib'
    Zlib::Deflate.deflate(spans.to_json)
  end
end
```

## Selective Tracing

### Environment-Based Tracing

```ruby
class SmartAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def initialize(tracing_level: nil)
    @tracing_level = tracing_level || determine_tracing_level
  end

  def run(message)
    case @tracing_level
    when :none
      process_without_tracing(message)
    when :minimal
      with_minimal_tracing(message)
    when :full
      with_full_tracing(message)
    else
      with_smart_tracing(message)
    end
  end

  private

  def determine_tracing_level
    case ENV['RAILS_ENV'] || ENV['ENVIRONMENT']
    when 'development' then :full
    when 'test' then :minimal
    when 'staging' then :full
    when 'production' then :smart
    else :minimal
    end
  end

  def with_smart_tracing(message)
    # Only trace if conditions are met
    should_trace = message.length > 100 ||
                   @priority == 'high' ||
                   rand < 0.1  # 10% sampling

    if should_trace
      with_tracing(:run) { process_message(message) }
    else
      process_message(message)
    end
  end
end
```

### Sampling Strategies

```ruby
class SamplingTracer
  def initialize(sample_rate: 0.1)
    @sample_rate = sample_rate
    @request_count = 0
  end

  def should_trace?
    @request_count += 1

    # Deterministic sampling based on request count
    (@request_count % (1.0 / @sample_rate).to_i) == 0
  end

  def trace_if_sampled(operation_name, &block)
    if should_trace?
      with_tracing(operation_name, sampled: true, &block)
    else
      block.call
    end
  end
end

# Usage with sampling
sampler = SamplingTracer.new(sample_rate: 0.05)  # 5% sampling

class SampledAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def initialize(sampler:)
    @sampler = sampler
  end

  def run(message)
    @sampler.trace_if_sampled(:run) do
      process_message(message)
    end
  end
end
```

### Feature Flag-Based Tracing

```ruby
class FeatureControlledAgent
  include RAAF::Tracing::Traceable
  trace_as :agent

  def run(message)
    if feature_enabled?(:detailed_tracing)
      with_detailed_tracing(message)
    elsif feature_enabled?(:basic_tracing)
      with_basic_tracing(message)
    else
      process_message(message)
    end
  end

  private

  def feature_enabled?(flag)
    # Integration with feature flag system
    FeatureFlags.enabled?(flag) || ENV["ENABLE_#{flag.to_s.upcase}"] == 'true'
  end

  def with_detailed_tracing(message)
    with_tracing(:run, message_length: message.length, priority: @priority) do
      with_tracing(:preprocessing) { preprocess(message) }
      with_tracing(:processing) { process_message(message) }
      with_tracing(:postprocessing) { postprocess(result) }
    end
  end

  def with_basic_tracing(message)
    with_tracing(:run) do
      process_message(message)
    end
  end
end
```

## High-Throughput Scenarios

### Async Processing

```ruby
class AsyncTraceProcessor
  def initialize(worker_count: 4, queue_size: 1000)
    @queue = Queue.new
    @workers = []
    @running = true

    worker_count.times do |i|
      @workers << Thread.new { worker_loop("worker-#{i}") }
    end
  end

  def on_span_end(span)
    if @queue.size < 1000  # Prevent unbounded queue growth
      @queue << span
    else
      # Drop spans if queue is full (or implement backpressure)
      puts "⚠️  Dropping span due to full queue: #{span.name}"
    end
  end

  def shutdown
    @running = false
    @workers.each(&:join)
  end

  private

  def worker_loop(worker_name)
    while @running
      begin
        span = @queue.pop(true)  # Non-blocking pop
        process_span(span, worker_name)
      rescue ThreadError
        # Queue empty, sleep briefly
        sleep(0.01)
      rescue => e
        puts "Worker #{worker_name} error: #{e.message}"
      end
    end
  end

  def process_span(span, worker_name)
    # Send span to external system
    send_to_monitoring_system(span)
  end
end
```

### Connection Pooling

```ruby
class PooledOpenAIProcessor
  def initialize(pool_size: 5)
    @connection_pool = ConnectionPool.new(size: pool_size) do
      create_http_client
    end
  end

  def on_span_end(span)
    @connection_pool.with do |client|
      send_span_with_client(client, span)
    end
  end

  private

  def create_http_client
    require 'faraday'

    Faraday.new(url: 'https://api.openai.com') do |conn|
      conn.adapter :net_http_persistent  # Persistent connections
      conn.options.timeout = 10
      conn.headers['Authorization'] = "Bearer #{ENV['OPENAI_API_KEY']}"
      conn.headers['Content-Type'] = 'application/json'
    end
  end

  def send_span_with_client(client, span)
    response = client.post('/v1/traces/ingest') do |req|
      req.body = span.to_json
    end

    unless response.success?
      puts "Failed to send span: #{response.status} #{response.body}"
    end
  end
end
```

## Monitoring and Profiling

### Performance Metrics Collection

```ruby
class PerformanceMetricsProcessor
  def initialize
    @metrics = {
      span_count: 0,
      total_duration: 0,
      avg_duration: 0,
      max_duration: 0,
      error_count: 0,
      component_stats: Hash.new(0)
    }
    @start_time = Time.now
  end

  def on_span_end(span)
    @metrics[:span_count] += 1

    if span.duration
      @metrics[:total_duration] += span.duration
      @metrics[:avg_duration] = @metrics[:total_duration] / @metrics[:span_count]
      @metrics[:max_duration] = [@metrics[:max_duration], span.duration].max
    end

    @metrics[:error_count] += 1 if span.status == :error
    @metrics[:component_stats][span.kind] += 1

    # Periodic reporting
    report_metrics if should_report?
  end

  def report_metrics
    uptime = Time.now - @start_time
    spans_per_second = @metrics[:span_count] / uptime

    puts "\n📊 RAAF Tracing Performance Metrics"
    puts "   Uptime: #{uptime.round(1)}s"
    puts "   Total spans: #{@metrics[:span_count]}"
    puts "   Spans/second: #{spans_per_second.round(2)}"
    puts "   Average duration: #{@metrics[:avg_duration].round(2)}ms"
    puts "   Max duration: #{@metrics[:max_duration].round(2)}ms"
    puts "   Error rate: #{((@metrics[:error_count].to_f / @metrics[:span_count]) * 100).round(2)}%"
    puts "   Component breakdown:"
    @metrics[:component_stats].each do |component, count|
      percentage = (count.to_f / @metrics[:span_count] * 100).round(1)
      puts "     #{component}: #{count} (#{percentage}%)"
    end
    puts
  end

  private

  def should_report?
    @metrics[:span_count] % 1000 == 0  # Report every 1000 spans
  end
end
```

### Memory Profiling

```ruby
class MemoryProfiler
  def initialize
    @initial_memory = get_memory_usage
    @span_memory_samples = []
  end

  def on_span_start(span)
    @span_start_memory = get_memory_usage
  end

  def on_span_end(span)
    end_memory = get_memory_usage
    memory_delta = end_memory - @span_start_memory

    @span_memory_samples << {
      span_name: span.name,
      memory_delta: memory_delta,
      total_memory: end_memory
    }

    analyze_memory_usage if @span_memory_samples.size % 100 == 0
  end

  private

  def get_memory_usage
    # Ruby memory usage in MB
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  end

  def analyze_memory_usage
    recent_samples = @span_memory_samples.last(100)
    avg_delta = recent_samples.sum { |s| s[:memory_delta] } / 100.0

    if avg_delta > 1.0  # More than 1MB average increase per span
      puts "⚠️  High memory usage detected: #{avg_delta.round(2)}MB average per span"

      # Find spans with highest memory usage
      high_memory_spans = recent_samples.select { |s| s[:memory_delta] > 2.0 }
      unless high_memory_spans.empty?
        puts "   High memory spans:"
        high_memory_spans.each do |span|
          puts "     #{span[:span_name]}: +#{span[:memory_delta].round(2)}MB"
        end
      end
    end
  end
end
```

## Production Recommendations

### Configuration for Production

```ruby
# Production environment configuration
ENV['RAAF_TRACE_BATCH_SIZE'] = '100'      # Efficient batching
ENV['RAAF_TRACE_FLUSH_INTERVAL'] = '10'   # Balance latency vs efficiency
ENV['RAAF_TRACE_MAX_SPANS'] = '5000'      # Reasonable memory limit
ENV['RAAF_TRACE_CLEANUP_INTERVAL'] = '300' # 5-minute cleanup
ENV['RAAF_LOG_LEVEL'] = 'warn'            # Reduce log noise

# Production processor setup
class ProductionTraceSetup
  def self.configure
    # Replace default processors with production-optimized ones
    RAAF::Tracing.set_trace_processors(
      OptimizedOpenAIProcessor.new(
        batch_size: 100,
        flush_interval: 10,
        retry_attempts: 3,
        compression: true
      ),
      PerformanceMetricsProcessor.new,
      ErrorTrackingProcessor.new
    )
  end
end

ProductionTraceSetup.configure
```

### Health Checks

```ruby
class TracingHealthCheck
  def self.check
    health_status = {
      tracing_enabled: !RAAF::Tracing.disabled?,
      processors_count: RAAF::Tracing.tracer.processors.size,
      memory_usage: get_memory_usage,
      queue_depth: get_queue_depth,
      error_rate: get_error_rate,
      last_successful_flush: get_last_flush_time
    }

    # Determine overall health
    health_status[:healthy] = health_status[:tracing_enabled] &&
                              health_status[:processors_count] > 0 &&
                              health_status[:memory_usage] < 1000 &&  # <1GB
                              health_status[:error_rate] < 0.05        # <5%

    health_status
  end

  def self.get_memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i / 1024  # MB
  end

  def self.get_queue_depth
    # Implementation depends on your queuing system
    0
  end

  def self.get_error_rate
    # Implementation depends on your metrics collection
    0.0
  end

  def self.get_last_flush_time
    # Implementation depends on your processor
    Time.now
  end
end

# Use in health endpoint
get '/health/tracing' do
  health = TracingHealthCheck.check
  status health[:healthy] ? 200 : 503
  json health
end
```

### Alerting and Monitoring

```ruby
class TracingAlertsProcessor
  def initialize(alert_thresholds:)
    @thresholds = alert_thresholds
    @metrics = {}
    @last_alert = {}
  end

  def on_span_end(span)
    update_metrics(span)
    check_alerts
  end

  private

  def update_metrics(span)
    @metrics[:total_spans] ||= 0
    @metrics[:error_spans] ||= 0
    @metrics[:slow_spans] ||= 0

    @metrics[:total_spans] += 1
    @metrics[:error_spans] += 1 if span.status == :error
    @metrics[:slow_spans] += 1 if span.duration && span.duration > @thresholds[:slow_span_ms]
  end

  def check_alerts
    return unless should_check_alerts?

    error_rate = @metrics[:error_spans].to_f / @metrics[:total_spans]
    slow_rate = @metrics[:slow_spans].to_f / @metrics[:total_spans]

    if error_rate > @thresholds[:max_error_rate]
      send_alert(:high_error_rate, "Error rate: #{(error_rate * 100).round(2)}%")
    end

    if slow_rate > @thresholds[:max_slow_rate]
      send_alert(:high_slow_rate, "Slow span rate: #{(slow_rate * 100).round(2)}%")
    end
  end

  def should_check_alerts?
    @metrics[:total_spans] % 1000 == 0  # Check every 1000 spans
  end

  def send_alert(alert_type, message)
    return if recently_alerted?(alert_type)

    # Send to your alerting system
    puts "🚨 ALERT [#{alert_type}]: #{message}"

    # Record alert time to prevent spam
    @last_alert[alert_type] = Time.now
  end

  def recently_alerted?(alert_type)
    last_time = @last_alert[alert_type]
    return false unless last_time

    Time.now - last_time < 300  # 5-minute cooldown
  end
end

# Configure alerting
alert_processor = TracingAlertsProcessor.new(
  alert_thresholds: {
    max_error_rate: 0.05,      # 5% error rate
    max_slow_rate: 0.1,        # 10% slow spans
    slow_span_ms: 1000         # 1 second threshold
  }
)

RAAF::Tracing.add_trace_processor(alert_processor)
```

## Performance Best Practices Summary

1. **Configure appropriate batch sizes** for your throughput requirements
2. **Use selective tracing** in high-volume scenarios
3. **Monitor memory usage** and configure cleanup intervals
4. **Implement efficient attribute collection** avoiding expensive operations
5. **Use async processing** for high-throughput applications
6. **Set up health checks** and alerting for production monitoring
7. **Profile and measure** the actual impact in your specific environment
8. **Consider sampling strategies** for extremely high-volume scenarios

By following these performance guidelines, you can maintain the benefits of comprehensive tracing while ensuring optimal application performance.
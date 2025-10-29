# Observability Specification

> Part of: Automatic Continuation Support
> Component: Observability, Logging, and Tracing
> Dependencies: Core Infrastructure

## Overview

Comprehensive observability strategy for automatic continuation support, enabling debugging, cost tracking, performance monitoring, and production troubleshooting.

## Metadata Structure

### _continuation_metadata Field

Complete metadata structure returned with all continued results:

```ruby
result[:_continuation_metadata] = {
  # Status flags
  was_continued: true,                    # Boolean: Was continuation triggered?
  merge_success: true,                    # Boolean: Did merge succeed?
  max_attempts_exceeded: false,           # Boolean: Hit max_attempts limit?

  # Continuation details
  continuation_count: 3,                   # Integer: Number of continuation rounds
  total_output_tokens: 12500,             # Integer: Total tokens across all chunks
  chunk_sizes: [4096, 4096, 4308],       # Array: Token count per chunk

  # Format and strategy
  merge_strategy_used: :csv,              # Symbol: Which merger was used
  output_format: :csv,                    # Symbol: Configured output format

  # Truncation tracking
  truncation_points: [                    # Array: Where each truncation occurred
    "row:250",
    "row:498"
  ],

  # Cost tracking
  total_cost_estimate: 0.125,             # Float: Estimated API cost in USD

  # API response details
  finish_reasons: [                       # Array: finish_reason per chunk
    "length",
    "length",
    "stop"
  ],
  incomplete_details: [                   # Array: incomplete_details per chunk
    { reason: "max_output_tokens" },
    { reason: "max_output_tokens" },
    nil
  ],

  # Format-specific metrics
  final_record_count: 523,                # Integer: Total records (CSV/JSON)

  # Error information (only present on failure)
  merge_error: "CSV column count mismatch", # String: Error message
  error_class: "RAAF::Continuation::MergeError" # String: Error class name
}
```

## Logging Strategy

### Log Levels and Categories

**INFO Level** - Normal operational events:
```ruby
Rails.logger.info(
  "[RAAF Continuation] Starting continuation attempt 1/10",
  agent_name: "CompanyDiscoveryAgent",
  output_format: :csv,
  previous_response_id: "resp_abc123"
)

Rails.logger.info(
  "[RAAF Continuation] Successfully merged 3 chunks",
  format: :csv,
  total_records: 523,
  total_tokens: 12500,
  total_cost: 0.125,
  duration_ms: 245
)
```

**WARN Level** - Concerning but recoverable issues:
```ruby
Rails.logger.warn(
  "[RAAF Continuation] ⚠️  Content Filter Triggered",
  category: "content_filter",
  model: "gpt-4o",
  response_id: "resp_123",
  incomplete_details: { reason: "content_policy_violation" }
)

Rails.logger.warn(
  "[RAAF Continuation] ⚠️  Incomplete Response (network/timeout)",
  category: "incomplete",
  response_id: "resp_456",
  recommendation: "Use previous_response_id: 'resp_456' to continue"
)

Rails.logger.warn(
  "[RAAF Continuation] Max attempts (10) exceeded",
  chunks_collected: 10,
  last_finish_reason: "length",
  agent_name: "DataExtractionAgent"
)
```

**ERROR Level** - Failures requiring attention:
```ruby
Rails.logger.error(
  "[RAAF Continuation] Merge failed: #{error.message}",
  error_class: error.class.name,
  merge_strategy: :csv,
  chunks_attempted: 3,
  partial_data_available: true,
  agent_name: "CompanyDiscoveryAgent",
  backtrace: error.backtrace.first(5)
)
```

**DEBUG Level** - Detailed diagnostic information:
```ruby
Rails.logger.debug(
  "[RAAF Continuation] Chunk 1: 4096 tokens",
  finish_reason: "length",
  format_detected: :csv,
  truncated_at: "row 250",
  has_incomplete_row: true
)

Rails.logger.debug(
  "[RAAF Continuation] Chunk 2: Using previous_response_id",
  previous_response_id: "resp_abc123",
  continuation_prompt: prompt.slice(0, 100)
)

Rails.logger.debug(
  "[RAAF Continuation] Merge strategy: CSV",
  incomplete_row_detected: true,
  completed_row: "Company A,Boston,100",
  rows_merged: 523
)
```

## Performance Metrics

### Timing Metrics

```ruby
class ContinuationMetrics
  def track_continuation(agent_name:, format:)
    start_time = Time.now

    result = yield

    duration_ms = ((Time.now - start_time) * 1000).round(2)

    RAAF::Metrics.timing(
      "continuation.duration",
      duration_ms,
      tags: {
        agent_name: agent_name,
        format: format,
        was_continued: result[:_continuation_metadata][:was_continued],
        chunk_count: result[:_continuation_metadata][:continuation_count]
      }
    )

    result
  end
end
```

### Success Rate Tracking

```ruby
def track_merge_outcome(format:, success:, chunk_count:)
  RAAF::Metrics.increment(
    "continuation.merge_outcome",
    tags: {
      format: format,
      success: success,
      chunk_range: bucket_chunk_count(chunk_count)
    }
  )
end

def bucket_chunk_count(count)
  case count
  when 0..2 then "small"
  when 3..5 then "medium"
  when 6..10 then "large"
  else "very_large"
  end
end
```

### Cost Tracking

```ruby
def track_continuation_cost(metadata)
  RAAF::Metrics.histogram(
    "continuation.cost_usd",
    metadata[:total_cost_estimate],
    tags: {
      agent_name: current_agent_name,
      format: metadata[:merge_strategy_used],
      chunk_count: metadata[:continuation_count]
    }
  )

  RAAF::Metrics.histogram(
    "continuation.tokens_used",
    metadata[:total_output_tokens],
    tags: {
      agent_name: current_agent_name,
      format: metadata[:merge_strategy_used]
    }
  )
end
```

## Tracing Integration

### OpenTelemetry Spans

```ruby
def trace_continuation(agent_name, format)
  tracer = OpenTelemetry.tracer_provider.tracer("raaf.continuation")

  tracer.in_span("continuation.merge", attributes: {
    "agent.name" => agent_name,
    "continuation.format" => format.to_s
  }) do |span|
    begin
      result = yield

      # Add result attributes to span
      span.set_attribute("continuation.was_continued", result[:_continuation_metadata][:was_continued])
      span.set_attribute("continuation.chunk_count", result[:_continuation_metadata][:continuation_count])
      span.set_attribute("continuation.merge_success", result[:_continuation_metadata][:merge_success])
      span.set_attribute("continuation.total_tokens", result[:_continuation_metadata][:total_output_tokens])

      result
    rescue StandardError => e
      span.record_exception(e)
      span.status = OpenTelemetry::Trace::Status.error("Continuation failed: #{e.message}")
      raise
    end
  end
end
```

## Dashboard Queries

### Key Metrics Dashboard

```sql
-- Continuation success rate by format
SELECT
  format,
  COUNT(*) as total_attempts,
  SUM(CASE WHEN merge_success = true THEN 1 ELSE 0 END) as successful,
  ROUND(100.0 * SUM(CASE WHEN merge_success = true THEN 1 ELSE 0 END) / COUNT(*), 2) as success_rate_pct
FROM continuation_events
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY format
ORDER BY total_attempts DESC;

-- Average chunks per continuation
SELECT
  agent_name,
  AVG(chunk_count) as avg_chunks,
  MAX(chunk_count) as max_chunks,
  COUNT(*) as total_continuations
FROM continuation_events
WHERE was_continued = true
  AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY agent_name
ORDER BY avg_chunks DESC;

-- Cost tracking by agent
SELECT
  agent_name,
  SUM(total_cost_usd) as total_cost,
  AVG(total_cost_usd) as avg_cost_per_run,
  COUNT(*) as total_runs
FROM continuation_events
WHERE timestamp > NOW() - INTERVAL '30 days'
GROUP BY agent_name
ORDER BY total_cost DESC;
```

## Debugging Tools

### Continuation Replay

```ruby
module RAAF
  module Continuation
    module Debugging
      def replay_continuation(continuation_id)
        # Load stored chunks
        chunks = load_chunks_from_storage(continuation_id)

        # Replay merge with detailed logging
        Rails.logger.level = :debug

        begin
          merger = MergerFactory.merger_for(chunks.first[:format])
          result = merger.merge(chunks)

          {
            replay_id: continuation_id,
            original_success: chunks.last[:merge_success],
            replay_success: result[:success],
            differences: diff(chunks.last[:result], result)
          }
        rescue StandardError => e
          {
            replay_id: continuation_id,
            error: e.message,
            backtrace: e.backtrace
          }
        end
      end
    end
  end
end
```

### Chunk Inspection Tool

```ruby
def inspect_chunks(continuation_id)
  chunks = load_chunks_from_storage(continuation_id)

  chunks.each_with_index do |chunk, index|
    puts "\n=== Chunk #{index + 1} ==="
    puts "Tokens: #{chunk.dig('usage', 'output_tokens')}"
    puts "Finish Reason: #{chunk['finish_reason']}"
    puts "Content Preview: #{chunk.dig('output', 'content')&.slice(0, 200)}"
    puts "Truncation Point: #{detect_truncation_point(chunk)}"
  end
end
```

## Production Monitoring Alerts

### Alert Conditions

```ruby
# High error rate alert
if continuation_error_rate(window: "5m") > 0.15
  PagerDuty.trigger(
    service: "raaf-continuation",
    summary: "High continuation error rate: #{error_rate}%",
    severity: "warning"
  )
end

# Max attempts frequently exceeded
if max_attempts_exceeded_rate(window: "1h") > 0.10
  Slack.notify(
    channel: "#raaf-monitoring",
    message: "10%+ of continuations hitting max_attempts in past hour"
  )
end

# Sudden cost spike
if continuation_cost_spike(threshold: 2.0, window: "30m")
  Slack.notify(
    channel: "#raaf-costs",
    message: "Continuation costs spiked 2x in past 30 minutes"
  )
end
```

## Best Practices

1. **Always log continuation events** at INFO level for visibility
2. **Include agent_name in all logs** for filtering and debugging
3. **Track finish_reasons and incomplete_details** for API issue detection
4. **Monitor cost trends** to detect unexpected spikes
5. **Set up alerts for error rate > 10%** to catch systemic issues
6. **Use DEBUG logs in development** for detailed merge troubleshooting
7. **Store continuation metadata** with results for post-mortem analysis

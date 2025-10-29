# Error Handling Specification

> Part of: Automatic Continuation Support
> Component: Error Handling and Graceful Degradation
> Dependencies: Core Infrastructure, Format Mergers

## Overview

Comprehensive error handling strategy for continuation failures, ensuring graceful degradation and maximum data recovery when merge operations fail.

## Error Categories

### 1. Merge Failures
**Cause**: Format-specific merger unable to combine chunks
**Examples**:
- CSV with inconsistent column counts
- Markdown with unrecoverable table corruption
- JSON that cannot be repaired

**Handling**: Return partial result with error metadata

### 2. Max Attempts Exceeded
**Cause**: Continuation limit reached without natural completion
**Examples**:
- Very large datasets requiring >10 continuations
- Model consistently hitting token limits

**Handling**: Return accumulated data with truncation warning

### 3. API Errors
**Cause**: OpenAI API failures during continuation
**Examples**:
- Rate limit errors
- Network timeouts
- Invalid API responses

**Handling**: Retry with backoff or return partial result

### 4. Configuration Errors
**Cause**: Invalid continuation configuration
**Examples**:
- Invalid output format
- Negative max_attempts

**Handling**: Raise ArgumentError immediately (fail fast)

## Implementation

### Failure Modes

```ruby
module RAAF
  module Continuation
    module ErrorHandling
      def handle_merge_failure(chunks, error, on_failure_mode)
        case on_failure_mode
        when :return_partial
          return_partial_result(chunks, error)
        when :raise_error
          raise ContinuationMergeError, build_error_message(chunks, error)
        else
          raise ArgumentError, "Invalid on_failure mode: #{on_failure_mode}"
        end
      end

      private

      def return_partial_result(chunks, error)
        # Attempt best-effort merge
        best_effort_data = attempt_best_effort_merge(chunks)

        {
          success: false,
          data: best_effort_data,
          _continuation_metadata: {
            was_continued: true,
            continuation_count: chunks.length - 1,
            merge_success: false,
            merge_error: error.message,
            error_class: error.class.name,
            chunk_sizes: chunks.map { |c| c.dig("usage", "output_tokens") || 0 },
            finish_reasons: chunks.map { |c| c["finish_reason"] },
            partial_data_available: best_effort_data.present?
          }
        }
      end

      def attempt_best_effort_merge(chunks)
        # Strategy 1: Try first chunk only (most likely complete)
        return extract_content(chunks.first) if chunks.length == 1

        # Strategy 2: Concatenate all chunks without format-specific logic
        chunks.map { |c| extract_content(c) }.join("\n\n---CHUNK BOUNDARY---\n\n")
      end

      def build_error_message(chunks, error)
        <<~MSG
          Failed to merge #{chunks.length} continuation chunks

          Error: #{error.message}
          Error Class: #{error.class.name}

          Chunk Information:
          #{chunks.map.with_index { |c, i| "  Chunk #{i + 1}: #{c.dig('usage', 'output_tokens')} tokens, finish_reason: #{c['finish_reason']}" }.join("\n")}

          Partial data may be available. Consider using on_failure: :return_partial
        MSG
      end
    end

    class ContinuationMergeError < StandardError; end
    class MaxAttemptsExceededError < StandardError; end
  end
end
```

### Max Attempts Handling

```ruby
def handle_max_attempts_exceeded(chunks, max_attempts)
  Rails.logger.warn(
    "[RAAF Continuation] Max attempts (#{max_attempts}) exceeded",
    chunks_collected: chunks.length,
    last_finish_reason: chunks.last["finish_reason"]
  )

  # Return what we have with warning metadata
  {
    success: true,  # Data is valid, just incomplete
    data: merge_chunks_best_effort(chunks),
    _continuation_metadata: {
      was_continued: true,
      continuation_count: chunks.length - 1,
      merge_success: true,
      max_attempts_exceeded: true,
      warning: "Dataset may be incomplete - max continuation attempts reached",
      chunk_sizes: chunks.map { |c| c.dig("usage", "output_tokens") || 0 }
    }
  }
end
```

### API Error Handling

```ruby
def handle_api_error(error, attempt_number, max_retries: 3)
  case error
  when RAAF::RateLimitError
    # Exponential backoff
    wait_time = 2 ** attempt_number
    Rails.logger.warn(
      "[RAAF Continuation] Rate limit hit, waiting #{wait_time}s",
      attempt: attempt_number,
      max_retries: max_retries
    )
    sleep(wait_time)
    retry if attempt_number < max_retries

  when RAAF::NetworkError, Timeout::Error
    # Quick retry for transient network issues
    Rails.logger.warn(
      "[RAAF Continuation] Network error, retrying",
      attempt: attempt_number,
      error: error.message
    )
    sleep(1)
    retry if attempt_number < max_retries

  when RAAF::APIError
    # Don't retry - likely persistent issue
    Rails.logger.error(
      "[RAAF Continuation] API error (not retrying)",
      error: error.message,
      response_code: error.response_code
    )
    raise
  end

  # All retries exhausted
  raise RAAF::Continuation::MaxRetriesExceededError, "API errors after #{max_retries} retries"
end
```

## Logging Strategy

### Log Levels

```ruby
# INFO: Normal continuation events
Rails.logger.info "[RAAF Continuation] Starting continuation attempt 1/10"
Rails.logger.info "[RAAF Continuation] Successfully merged 3 chunks"

# WARN: Concerning but recoverable issues
Rails.logger.warn "[RAAF Continuation] Max attempts exceeded, returning partial result"
Rails.logger.warn "[RAAF Continuation] Merge degraded to best-effort strategy"

# ERROR: Failures requiring attention
Rails.logger.error "[RAAF Continuation] Merge failed: #{error.message}"
Rails.logger.error "[RAAF Continuation] All retry attempts exhausted"

# DEBUG: Detailed diagnostic information
Rails.logger.debug "[RAAF Continuation] Chunk 2: 4096 tokens, CSV format detected"
Rails.logger.debug "[RAAF Continuation] Incomplete row detected at line 250"
```

### Structured Logging

```ruby
def log_error_with_context(error, chunks, agent_name)
  Rails.logger.error(
    "[RAAF Continuation] Merge Error",
    error_message: error.message,
    error_class: error.class.name,
    agent_name: agent_name,
    total_chunks: chunks.length,
    total_tokens: chunks.sum { |c| c.dig("usage", "output_tokens") || 0 },
    finish_reasons: chunks.map { |c| c["finish_reason"] },
    backtrace: error.backtrace.first(5)
  )
end
```

## Error Recovery Patterns

### Pattern 1: Fallback Chain

```ruby
def merge_with_fallbacks(chunks, format)
  strategies = [
    -> { format_specific_merge(chunks, format) },
    -> { simple_concatenation(chunks) },
    -> { first_chunk_only(chunks) }
  ]

  strategies.each.with_index do |strategy, index|
    begin
      return strategy.call
    rescue StandardError => e
      Rails.logger.warn(
        "[RAAF Continuation] Strategy #{index + 1} failed, trying next",
        error: e.message
      )
      next if index < strategies.length - 1
      raise
    end
  end
end
```

### Pattern 2: Partial Success

```ruby
def extract_valid_portion(malformed_data, format)
  case format
  when :csv
    # Return all valid CSV rows
    CSV.parse(malformed_data, liberal_parsing: true) rescue []
  when :json
    # Use JSON repair to extract what's valid
    RAAF::JsonRepair.new(malformed_data).repair rescue { partial: malformed_data }
  when :markdown
    # Return raw markdown (always valid)
    malformed_data
  end
end
```

## Testing Error Scenarios

### Unit Tests

```ruby
describe "Error Handling" do
  it "returns partial result on merge failure" do
    agent = create_agent(on_failure: :return_partial)

    # Mock merge failure
    allow(merger).to receive(:merge).and_raise(MergeError)

    result = agent.run

    expect(result[:success]).to be false
    expect(result[:data]).to be_present  # Best-effort data
    expect(result[:_continuation_metadata][:merge_error]).to be_present
  end

  it "raises error when configured" do
    agent = create_agent(on_failure: :raise_error)

    allow(merger).to receive(:merge).and_raise(MergeError)

    expect { agent.run }.to raise_error(ContinuationMergeError)
  end

  it "handles max attempts gracefully" do
    agent = create_agent(max_attempts: 3)

    # Mock continuous truncation
    stub_truncated_responses(count: 4)

    result = agent.run

    expect(result[:_continuation_metadata][:max_attempts_exceeded]).to be true
    expect(result[:_continuation_metadata][:continuation_count]).to eq(3)
  end
end
```

## Monitoring and Alerting

### Key Metrics to Track

```ruby
# Error rate tracking
RAAF::Metrics.increment("continuation.merge_failure", tags: { format: :csv })
RAAF::Metrics.increment("continuation.max_attempts_exceeded")
RAAF::Metrics.increment("continuation.api_error", tags: { error_type: "rate_limit" })

# Alert conditions
if merge_error_rate > 0.10  # 10% error rate
  alert_team("High continuation merge failure rate: #{merge_error_rate}")
end

if max_attempts_exceeded_rate > 0.05  # 5% hit max attempts
  alert_team("Agents frequently hitting max continuation attempts")
end
```

## User-Facing Error Messages

### Actionable Error Messages

```ruby
def user_friendly_error(error, context)
  case error
  when ContinuationMergeError
    "Data merging failed. Partial results are available. Consider reducing dataset size or increasing max_attempts."

  when MaxAttemptsExceededError
    "Maximum continuation attempts (#{context[:max_attempts]}) reached. Dataset may be incomplete. Increase max_attempts or reduce data volume."

  when RAAF::RateLimitError
    "API rate limit reached. Please wait a moment and try again."

  else
    "An unexpected error occurred during continuation: #{error.message}"
  end
end
```

## Best Practices

1. **Always use :return_partial in production** - Never leave users with nothing
2. **Log comprehensive context** - Include chunk info, tokens, finish_reasons
3. **Implement fallback strategies** - Multiple recovery paths increase success
4. **Monitor error rates** - Track and alert on elevated failure rates
5. **Preserve partial data** - Even failed merges may contain useful information

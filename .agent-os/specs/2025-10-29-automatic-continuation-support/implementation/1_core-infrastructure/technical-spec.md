# Technical Specification: Core Infrastructure

> Part of: Automatic Continuation Support
> Component: Core Infrastructure
> Dependencies: None

## Overview

This document specifies the core infrastructure for RAAF's automatic continuation support, including provider-level detection, configuration system, and continuation orchestration.

## Architecture Decisions

### Decision 1: Opt-In by Default
**Choice:** Continuation is opt-in via `enable_continuation`
**Rationale:** Maintains backward compatibility, allows gradual adoption, prevents unexpected behavior changes

### Decision 2: Provider-Level Detection
**Choice:** Implement detection in ResponsesProvider
**Rationale:** Centralized detection, works with structured outputs, natural integration point

### Decision 3: Stateful API Integration
**Choice:** Use Responses API `previous_response_id` for continuation
**Rationale:**
- Automatic context management (no manual history)
- Server maintains full conversation state
- Dramatically simplifies continuation logic
- Better context preservation than manual messages

### Decision 4: Metadata Tracking
**Choice:** Comprehensive metadata in `_continuation_metadata` field
**Rationale:** Essential for debugging, cost tracking, and optimization

## Configuration System

### ContinuationConfig Class

```ruby
module RAAF
  module Models
    class ContinuationConfig
      attr_accessor :max_attempts, :output_format, :on_failure, :merge_strategy

      def initialize(options = {})
        @max_attempts = options[:max_attempts] || 10
        @output_format = options[:output_format] || :auto
        @on_failure = options[:on_failure] || :return_partial
        @merge_strategy = options[:merge_strategy] || :format_specific
      end

      def enabled?
        !@output_format.nil?
      end

      def validate!
        raise ArgumentError, "max_attempts must be positive" unless max_attempts.positive?
        raise ArgumentError, "Invalid output_format" unless valid_format?
        raise ArgumentError, "Invalid on_failure mode" unless valid_failure_mode?
      end

      private

      def valid_format?
        [:csv, :markdown, :json, :auto].include?(@output_format)
      end

      def valid_failure_mode?
        [:return_partial, :raise_error].include?(@on_failure)
      end
    end
  end
end
```

### DSL Integration

```ruby
module RAAF
  module DSL
    class Agent
      # Class-level continuation configuration
      def self.enable_continuation(options = {})
        @continuation_config = RAAF::Models::ContinuationConfig.new(options)
        @continuation_config.validate!
      end

      def self.continuation_config
        @continuation_config
      end

      # Instance access to configuration
      def continuation_config
        self.class.continuation_config
      end

      def continuation_enabled?
        continuation_config&.enabled? || false
      end
    end
  end
end
```

### Configuration Propagation

Configuration flows through the system:

1. **Agent Definition** → `enable_continuation` stores config in class variable
2. **Agent Instance** → Inherits config via `continuation_config` method
3. **Runner** → Passes agent's config to provider during execution
4. **Provider** → Uses config to control continuation behavior

```ruby
# In RAAF::Runner
def run(input, context: nil)
  # ... setup ...

  # Pass agent's continuation config to provider
  response = provider.responses_completion(
    messages: messages,
    model: agent.model,
    tools: tools,
    continuation_config: agent.continuation_config  # ← Key propagation point
  )

  # ... process response ...
end
```

## Provider-Level Truncation Detection

### ResponsesProvider Enhancement

```ruby
module RAAF
  module Models
    class ResponsesProvider
      def responses_completion(messages:, model:, tools: nil, stream: false,
                               previous_response_id: nil, input: nil,
                               continuation_config: nil, **)
        response = make_api_call(
          messages: messages,
          model: model,
          tools: tools,
          stream: stream,
          previous_response_id: previous_response_id,
          input: input
        )

        # Check finish_reason for various completion states
        case response["finish_reason"]
        when "length"
          # Token limit hit - continuation needed
          if continuation_config&.enabled?
            handle_continuation(response, messages, model, tools, stream, continuation_config)
          else
            response
          end
        when "content_filter"
          log_content_filter_warning(response, messages, model)
          response
        when "incomplete"
          log_incomplete_warning(response, messages, model)
          response
        else
          # "stop", "tool_calls", etc. - normal completion
          response
        end
      end

      private

      def handle_continuation(initial_response, messages, model, tools, stream, config)
        chunks = [initial_response]
        attempts = 0
        max_attempts = config.max_attempts

        while should_continue?(chunks.last) && attempts < max_attempts
          attempts += 1

          Rails.logger.info(
            "[RAAF Continuation] Starting continuation attempt #{attempts}/#{max_attempts}",
            agent_name: current_agent_name,
            output_format: config.output_format
          )

          continuation_prompt = build_continuation_prompt(
            chunks.last,
            config.output_format
          )

          # Use stateful API with previous_response_id for automatic context management
          continuation_response = responses_completion(
            messages: [continuation_prompt],
            model: model,
            tools: tools,
            stream: stream,
            previous_response_id: chunks.last["id"],  # ← KEY: Stateful continuation
            continuation_config: config
          )

          chunks << continuation_response

          # Stop if response naturally completed
          break if continuation_response["finish_reason"] == "stop"
        end

        merge_chunks(chunks, config)
      end

      def should_continue?(response)
        response["finish_reason"] == "length"
      end

      def log_content_filter_warning(response, messages, model)
        Rails.logger.warn(
          "[RAAF Continuation] ⚠️  Content Filter Triggered",
          category: "content_filter",
          model: model,
          message_preview: messages.last&.dig(:content)&.slice(0, 100),
          response_id: response["id"],
          incomplete_details: response["incomplete_details"]
        )
      end

      def log_incomplete_warning(response, messages, model)
        Rails.logger.warn(
          "[RAAF Continuation] ⚠️  Incomplete Response (network/timeout)",
          category: "incomplete",
          model: model,
          message_preview: messages.last&.dig(:content)&.slice(0, 100),
          response_id: response["id"],
          incomplete_details: response["incomplete_details"],
          recommendation: "Use previous_response_id to continue: responses_completion(..., previous_response_id: '#{response["id"]}')"
        )
      end
    end
  end
end
```

## Continuation Prompt Engineering

### Stateful API Prompting Strategy

**IMPORTANT:** The Responses API is stateful - when using `previous_response_id`, the model automatically has full context of the previous conversation. Keep continuation prompts simple and focused on output requirements:

```ruby
def build_continuation_prompt(last_chunk, format)
  case format
  when :csv
    # Stateful API has full context, just clarify what to continue
    {
      role: "user",
      content: "Continue from where you left off. Complete any incomplete rows and continue generating more CSV data. Output ONLY the CSV data continuation, no explanations or headers."
    }

  when :markdown
    # Stateful API maintains document context via previous_response_id
    {
      role: "user",
      content: "Continue from where you left off, maintaining the same formatting and structure. Output ONLY the continuation content, no preamble."
    }

  when :json
    # Stateful API understands the partial JSON structure
    {
      role: "user",
      content: "Continue generating the JSON from where it was truncated. Maintain the same structure. Output ONLY the JSON continuation, no explanations."
    }

  when :auto
    # Generic continuation prompt
    {
      role: "user",
      content: "Continue from where you left off. Output ONLY the continuation, no explanations."
    }
  end
end
```

### How Stateful Continuation Works

1. **First request**: `responses_completion(messages: [...], model: "gpt-4o")`
2. **Response is incomplete**: `finish_reason == "length"`, `response["id"]` = "resp_123"
3. **Second request**: `responses_completion(messages: [...], previous_response_id: "resp_123")`
4. **Model automatically has context** of previous conversation
5. **No manual history management** needed

This dramatically simplifies continuation logic compared to Chat Completions API.

## Merger Interface

### Base Merger Class

```ruby
module RAAF
  module Continuation
    module Mergers
      class BaseMerger
        def merge(chunks)
          raise NotImplementedError, "Subclasses must implement #merge"
        end

        protected

        def extract_content(chunk)
          chunk.dig("output", "content") || chunk.dig("message", "content") || ""
        end

        def build_metadata(chunks, merge_success:, merge_error: nil)
          {
            was_continued: true,
            continuation_count: chunks.length - 1,
            total_output_tokens: chunks.sum { |c| c.dig("usage", "output_tokens") || 0 },
            merge_strategy_used: self.class.name.split("::").last.downcase.gsub("merger", "").to_sym,
            merge_success: merge_success,
            chunk_sizes: chunks.map { |c| c.dig("usage", "output_tokens") || 0 },
            finish_reasons: chunks.map { |c| c["finish_reason"] },
            incomplete_details: chunks.map { |c| c["incomplete_details"] },
            merge_error: merge_error
          }
        end
      end
    end
  end
end
```

### MergerFactory

```ruby
module RAAF
  module Continuation
    class MergerFactory
      def self.merger_for(format)
        case format
        when :csv
          Mergers::CSVMerger.new
        when :markdown
          Mergers::MarkdownMerger.new
        when :json
          Mergers::JSONMerger.new
        when :auto
          Mergers::AutoDetectMerger.new
        else
          raise ArgumentError, "Unknown format: #{format}"
        end
      end
    end
  end
end
```

### Chunk Merging Orchestration

```ruby
def merge_chunks(chunks, config)
  merger = RAAF::Continuation::MergerFactory.merger_for(config.output_format)

  begin
    result = merger.merge(chunks)

    Rails.logger.info(
      "[RAAF Continuation] Successfully merged #{chunks.length} chunks",
      format: config.output_format,
      total_tokens: result[:_continuation_metadata][:total_output_tokens]
    )

    result
  rescue StandardError => e
    Rails.logger.error(
      "[RAAF Continuation] Failed to merge chunks: #{e.message}",
      merge_strategy: config.output_format,
      chunks_attempted: chunks.length,
      error_class: e.class.name
    )

    handle_merge_failure(chunks, e, config.on_failure)
  end
end
```

## Result Metadata Structure

### _continuation_metadata Field

```ruby
result[:_continuation_metadata] = {
  was_continued: true,                    # Boolean flag for continuation
  continuation_count: 3,                   # Number of continuation attempts
  total_output_tokens: 12500,             # Total tokens across all chunks
  merge_strategy_used: :csv,              # Format-specific strategy used
  merge_success: true,                    # Whether merge succeeded
  chunk_sizes: [4096, 4096, 4308],       # Token count per chunk
  final_record_count: 523,                # Final number of records (CSV/JSON)
  truncation_points: ["row:250", "row:498"], # Where truncation occurred
  total_cost_estimate: 0.125,             # Estimated API cost
  finish_reasons: ["length", "length", "stop"],  # finish_reason per chunk
  incomplete_details: [                   # incomplete_details from each response
    { reason: "max_output_tokens" },
    { reason: "max_output_tokens" },
    nil
  ]
}
```

### Metadata Collection

```ruby
def collect_metadata(chunks, merge_result)
  {
    was_continued: true,
    continuation_count: chunks.length - 1,
    total_output_tokens: chunks.sum { |c| c.dig("usage", "output_tokens") || 0 },
    merge_strategy_used: merge_result[:merge_strategy],
    merge_success: merge_result[:success],
    chunk_sizes: chunks.map { |c| c.dig("usage", "output_tokens") || 0 },
    final_record_count: merge_result[:record_count],
    truncation_points: merge_result[:truncation_points],
    total_cost_estimate: calculate_cost(chunks),
    finish_reasons: chunks.map { |c| c["finish_reason"] },
    incomplete_details: chunks.map { |c| c["incomplete_details"] }
  }
end

def calculate_cost(chunks)
  # Model-specific pricing
  pricing = {
    "gpt-4o" => { input: 0.005, output: 0.015 },  # per 1K tokens
    "gpt-4o-mini" => { input: 0.00015, output: 0.0006 }
  }

  total_input_tokens = chunks.sum { |c| c.dig("usage", "input_tokens") || 0 }
  total_output_tokens = chunks.sum { |c| c.dig("usage", "output_tokens") || 0 }

  model = chunks.first.dig("model") || "gpt-4o"
  rates = pricing[model] || pricing["gpt-4o"]

  (total_input_tokens / 1000.0 * rates[:input]) +
  (total_output_tokens / 1000.0 * rates[:output])
end
```

## finish_reason Handling Strategy

The Responses API returns different `finish_reason` values to indicate why response generation stopped. RAAF's continuation support handles each appropriately:

### finish_reason: "stop"
**Status:** ✅ Normal completion
**Action:** No continuation needed. Response is complete.
**Logging:** DEBUG level only.

### finish_reason: "length"
**Status:** ⚠️ Token limit hit
**Action:** Automatic continuation triggered (if `enable_continuation` configured)
**Mechanism:** Use `previous_response_id` from response to continue statefully
**Logging:** INFO level on continuation start, DEBUG per-chunk details.
**Metadata:** Tracked with `finish_reasons` array and `truncation_points`.

Example:
```ruby
# First chunk: finish_reason = "length"
response1 = provider.responses_completion(messages: [...])

# RAAF detects length and automatically continues
response2 = provider.responses_completion(
  messages: [...],
  previous_response_id: response1["id"]  # Automatic stateful continuation
)
```

### finish_reason: "tool_calls"
**Status:** ✅ Model initiated tool calls
**Action:** No continuation. Handle tool calls normally.
**Logging:** DEBUG level. Tool execution logs will follow.

### finish_reason: "content_filter"
**Status:** ⚠️ Response blocked by OpenAI safety policy
**Action:** Log warning. Response is dropped; no continuation attempted.
**Logging:** **WARN level** with ⚠️ emoji and details
**Metadata:** Captured in `incomplete_details` field

**Why This Matters:**
- Content was filtered due to safety policy violation
- Retrying won't help (same policy applies)
- Developer must revise prompt or expectations
- Log warning ensures visibility

Example log:
```
[RAAF Continuation] ⚠️  Content Filter Triggered
category: "content_filter"
response_id: "resp_abc123"
incomplete_details: { reason: "content_policy_violation" }
```

### finish_reason: "incomplete"
**Status:** ⚠️ Response interrupted (network issue or timeout)
**Action:** Log warning with remediation guidance. Response may be partial.
**Logging:** **WARN level** with ⚠️ emoji and `previous_response_id` recommendation
**Metadata:** `incomplete_details` contains reason (e.g., `{ reason: "timeout" }`)

**Why This Matters:**
- Network issues or server timeouts interrupted generation
- Response may be partial or corrupted
- Can be continued using `previous_response_id`
- Developer should decide whether to retry/continue

Example log:
```
[RAAF Continuation] ⚠️  Incomplete Response (network/timeout)
category: "incomplete"
response_id: "resp_def456"
incomplete_details: { reason: "timeout" }
recommendation: "Use previous_response_id: 'resp_def456' to continue"
```

### finish_reason: "error"
**Status:** ❌ Internal API error
**Action:** Propagate as APIError. No continuation attempted.
**Logging:** ERROR level with full context
**Metadata:** Error details in exception.

### finish_reason: null
**Status:** ❌ Response still in progress (streaming/incomplete API response)
**Action:** Treated as error. Response is malformed.
**Logging:** ERROR level with diagnostic details
**Metadata:** Captured in logs for debugging.

## Implementation Timeline

### Phase 1: Core Infrastructure (2 days)

**Day 1:**
- ContinuationConfig class
- DSL `enable_continuation` method
- Configuration propagation system
- Unit tests for configuration

**Day 2:**
- ResponsesProvider truncation detection
- Continuation loop implementation
- Metadata tracking foundation
- finish_reason handling logic
- Stateful API integration (`previous_response_id`)

### Acceptance Criteria

- [ ] `enable_continuation` works at agent class level
- [ ] Configuration validates input options
- [ ] Provider detects `finish_reason: "length"` correctly
- [ ] Continuation loop respects max_attempts
- [ ] Uses `previous_response_id` for stateful continuation
- [ ] `finish_reason: "content_filter"` logs WARN
- [ ] `finish_reason: "incomplete"` logs WARN with recommendation
- [ ] Basic metadata structure created
- [ ] All unit tests pass

# RAAF Tracing Span Naming Improvements Implementation Plan

## Overview

Improve RAAF tracing span naming to eliminate redundancy (e.g., `run.workflow.llm.llm_call.llm_call`) and make span names more descriptive and user-friendly while maintaining Python SDK compatibility.

## Current State Analysis

The RAAF tracing system generates span names using a hierarchical pattern `run.workflow.<type>.<name>.<method>` which leads to redundant and unclear naming, especially for LLM calls that produce `run.workflow.llm.llm_call.llm_call`.

### Key Discoveries:
- **Root Cause**: In `traceable.rb:323-326`, when `method_name == :llm_call`, both `display_name` and `method_name` are set to "llm_call", causing duplication in `build_span_name`
- **Pattern**: `traceable.rb:444-458` - `build_span_name` appends both component name and method name without checking for duplicates
- **Display Logic**: `span_record.rb:350-366` - Display name extraction doesn't handle LLM spans specifically
- **No Configuration**: Hard-coded patterns with no customization options

## Desired End State

After implementation:
- Span names like `run.workflow.llm.completion` instead of `run.workflow.llm.llm_call.llm_call`
- More descriptive names that indicate the actual operation
- Configurable naming patterns for different environments
- Better display names in the Rails dashboard

### Verification:
- [x] LLM spans show as `run.workflow.llm.completion` (no duplication)
- [x] Agent spans include meaningful context (e.g., `run.workflow.agent.MarketAnalysis`)
- [x] Tool spans show tool names clearly (e.g., `run.workflow.tool.WebSearch`)
- [x] Rails dashboard displays human-readable names
- [x] All existing tests pass with updated naming

## What We're NOT Doing

- Breaking Python SDK compatibility (must maintain trace format)
- Changing the underlying span data structure
- Modifying how spans are stored in the database
- Altering the OpenAI processor format

## Implementation Approach

Fix the issue at the source in `build_span_name` by detecting and preventing duplicate name segments, then enhance display names for better readability in the UI.

## Phase 1: Fix Redundant Naming

### Overview
Eliminate the duplicate "llm_call" in span names by improving the logic in `build_span_name`.

### Changes Required:

#### 1. Update Span Name Building Logic
**File**: `tracing/lib/raaf/tracing/traceable.rb`
**Changes**: Modify `build_span_name` to prevent duplicate segments

```ruby
def build_span_name(component_type, component_name, method_name)
  base_name = "run.workflow.#{component_type}"

  # Always include component name if available and not "Runner"
  if component_name && component_name != "Runner"
    base_name = "#{base_name}.#{component_name}"
  end

  # Add method name if it's not the default 'run' method
  # AND it's not the same as the component name (prevents duplication)
  if method_name &&
     method_name.to_s != "run" &&
     method_name.to_s != component_name&.to_s
    base_name = "#{base_name}.#{method_name}"
  end

  base_name
end
```

#### 2. Improve LLM Span Naming
**File**: `tracing/lib/raaf/tracing/traceable.rb`
**Changes**: Use more descriptive names for LLM operations

```ruby
elsif method_name == :llm_call
  # This is an LLM API call, use more descriptive naming
  actual_kind = :llm

  # Determine the type of LLM operation from metadata
  if metadata[:streaming]
    display_name = "streaming"
  elsif metadata[:tool_calls]
    display_name = "tool_call"
  else
    display_name = "completion"
  end
```

### Success Criteria:

#### Automated Verification:
- [x] All tests pass: `cd tracing && bundle exec rspec`
- [x] No duplicate segments in span names (add specific test)
- [x] Span names follow expected patterns (add validation test)

#### Manual Verification:
- [x] LLM spans display as `run.workflow.llm.completion` in traces
- [x] No more duplicate "llm_call.llm_call" patterns
- [x] Existing integrations continue working

---

## Phase 2: Enhanced Display Names

### Overview
Improve how span names are displayed in the Rails dashboard for better readability.

### Changes Required:

#### 1. Add LLM-Specific Display Logic
**File**: `rails/app/models/RAAF/rails/tracing/span_record.rb`
**Changes**: Add case for "llm" kind in `display_name` method

```ruby
def display_name
  case kind
  when "tool"
    # ... existing tool logic ...
  when "agent"
    # ... existing agent logic ...
  when "pipeline"
    # ... existing pipeline logic ...
  when "llm"
    # New: Extract meaningful LLM operation name
    operation = extract_llm_operation
    model = span_attributes&.dig("model") || span_attributes&.dig("llm", "model")

    if model && operation
      "#{model} - #{operation.humanize}"
    elsif operation
      "LLM #{operation.humanize}"
    else
      "LLM Operation"
    end
  else
    extract_readable_name || "#{kind.to_s.capitalize} Operation"
  end
end

private

def extract_llm_operation
  return nil unless name

  # Extract operation from patterns like "run.workflow.llm.completion"
  if name.match(/\.llm\.([a-z_]+)/)
    $1
  end
end
```

#### 2. Add Context to Span Names
**File**: `core/lib/raaf/runner.rb`
**Changes**: Pass more metadata when creating LLM spans

```ruby
# Line 1410 area - when calling with_tracing(:llm_call)
metadata = {
  model: @provider.model || @model,
  streaming: streaming,
  tool_calls: messages.any? { |m| m[:tool_calls].present? }
}

with_tracing(:llm_call, parent_component: current_agent, metadata: metadata) do
  # ... existing code ...
end
```

### Success Criteria:

#### Automated Verification:
- [x] Rails tests pass: `cd rails && bundle exec rspec`
- [x] Display name extraction tests pass
- [x] UI components render without errors

#### Manual Verification:
- [x] Dashboard shows "GPT-4o - Completion" instead of technical names
- [x] Agent names display clearly (e.g., "MarketAnalysis" not full class name)
- [x] Tool names are prominent in the UI

---

## Phase 3: Add Configuration System

### Overview
Create a configuration system for span naming patterns to allow customization.

### Changes Required:

#### 1. Create Span Naming Configuration
**File**: `tracing/lib/raaf/tracing/span_naming_config.rb`
**Changes**: New configuration class

```ruby
module RAAF
  module Tracing
    class SpanNamingConfig
      DEFAULT_PATTERN = "run.workflow.{component_type}.{component_name}.{method_name}"
      COMPACT_PATTERN = "{component_type}.{component_name}"
      DETAILED_PATTERN = "raaf.{trace_id}.{component_type}.{component_name}.{method_name}"

      attr_accessor :pattern, :include_method_names, :abbreviate_components

      def initialize
        @pattern = DEFAULT_PATTERN
        @include_method_names = true
        @abbreviate_components = false
      end

      def build_name(component_type, component_name, method_name)
        name = @pattern.dup
        name.gsub!("{component_type}", component_type.to_s)
        name.gsub!("{component_name}", format_component_name(component_name))

        if @include_method_names && method_name && method_name.to_s != "run"
          name.gsub!("{method_name}", method_name.to_s)
        else
          name.gsub!(".{method_name}", "")
        end

        name
      end

      private

      def format_component_name(name)
        return "" unless name && name != "Runner"

        if @abbreviate_components
          name.gsub(/Agent$|Tool$|Pipeline$/, "")
        else
          name
        end
      end
    end
  end
end
```

#### 2. Integrate Configuration
**File**: `tracing/lib/raaf/tracing/traceable.rb`
**Changes**: Use configuration in `build_span_name`

```ruby
def build_span_name(component_type, component_name, method_name)
  if defined?(RAAF::Tracing::SpanNamingConfig) && RAAF::Tracing.span_naming_config
    RAAF::Tracing.span_naming_config.build_name(component_type, component_name, method_name)
  else
    # Fallback to improved default implementation from Phase 1
    base_name = "run.workflow.#{component_type}"

    if component_name && component_name != "Runner"
      base_name = "#{base_name}.#{component_name}"
    end

    if method_name && method_name.to_s != "run" && method_name.to_s != component_name&.to_s
      base_name = "#{base_name}.#{method_name}"
    end

    base_name
  end
end
```

### Success Criteria:

#### Automated Verification:
- [x] Configuration tests pass
- [x] Different patterns produce expected output
- [x] Backward compatibility maintained

#### Manual Verification:
- [x] Can switch between naming patterns via configuration
- [x] Abbreviated names work correctly
- [x] Custom patterns apply properly

---

## Testing Strategy

### Unit Tests:
- Test `build_span_name` with various inputs to ensure no duplicates
- Test display name extraction for all span types
- Test configuration system with different patterns

### Integration Tests:
- Full agent execution produces correctly named spans
- Multi-agent handoffs maintain proper naming
- Tool executions have clear span names

### Manual Testing Steps:
1. Run an agent that makes LLM calls and verify span names
2. Check Rails dashboard displays readable names
3. Verify OpenAI processor still sends correct format
4. Test with different configuration settings

## Performance Considerations

- Span name generation is on the hot path - keep it efficient
- Avoid complex regex in `build_span_name`
- Cache display names in database if extraction becomes slow

## Migration Notes

- Existing spans in database will keep old names
- New spans will use improved naming immediately
- No database migration required
- Configuration is optional with sensible defaults

## References

- Original issue: User request about `run.workflow.llm.llm_call.llm_call` span names
- Key files: `traceable.rb:444-458`, `span_record.rb:350-366`, `runner.rb:1410`
- Python SDK format: Must maintain compatibility with OpenAI dashboard
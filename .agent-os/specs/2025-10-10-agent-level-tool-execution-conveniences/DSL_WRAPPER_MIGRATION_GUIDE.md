# DSL Wrapper Migration Guide

## Overview

This guide explains how to migrate from DSL tool wrappers to using raw core tools with the new agent-level tool execution interceptor. The interceptor provides automatic validation, logging, and metadata injection, eliminating the need for wrapper classes that only add conveniences.

## Background

### The Problem

Previously, DSL tool wrappers added 200+ lines of boilerplate code per tool:

```ruby
# OLD: DSL wrapper with 200+ lines
class PerplexitySearch < RAAF::DSL::Tools::Base
  def call(query:, **options)
    # Logging
    RAAF.logger.debug "[PERPLEXITY SEARCH] Executing search..."
    RAAF.logger.debug "[PERPLEXITY SEARCH] Query: #{query.truncate(100)}"

    start_time = Time.now

    # Validation
    validate_options!

    # Actual API call
    result = @http_client.make_api_call(params)

    # More logging
    duration_ms = ((Time.now - start_time) * 1000).round(2)
    RAAF.logger.debug "[PERPLEXITY SEARCH] Success (#{duration_ms}ms)"

    # Format result
    format_search_result(result)
  end

  private

  def validate_options!
    # Validation code...
  end

  def format_search_result(result)
    # Formatting code...
  end
end
```

### The Solution

The new interceptor centralizes all conveniences at the agent level:

```ruby
# NEW: Use raw core tool directly
class MyAgent < RAAF::DSL::Agent
  uses_tool RAAF::Tools::PerplexityTool, as: :perplexity_search

  # Optional: Configure execution behavior
  tool_execution do
    enable_validation true
    enable_logging true
    enable_metadata true
  end
end

# The interceptor automatically provides:
# - Parameter validation
# - Execution logging
# - Duration tracking
# - Metadata injection
```

## What Gets Migrated?

### Candidate Wrappers for Removal

DSL wrappers that ONLY add conveniences can be removed:

| Wrapper | Core Tool | Convenience Only? | Migration Priority |
|---------|-----------|-------------------|--------------------|
| `RAAF::DSL::Tools::PerplexitySearch` | `RAAF::Tools::PerplexityTool` | ✅ Yes | High |
| `RAAF::DSL::Tools::TavilySearch` | `RAAF::Tools::TavilySearch` | ✅ Yes | High |
| `RAAF::DSL::Tools::WebSearch` | OpenAI hosted | ⚠️ No (configuration only) | Low |

### Wrappers to Retain

DSL wrappers with business logic or custom behavior should be kept:

- **Configuration wrappers** - Tools that provide DSL-specific configuration (e.g., `WebSearch` with OpenAI preset configuration)
- **Transformation wrappers** - Tools that transform data for specific DSL patterns
- **Composite wrappers** - Tools that combine multiple core tools

## Migration Steps

### Step 1: Identify Wrapper Type

Analyze the wrapper to determine if it's a candidate for removal:

```ruby
# Check what the wrapper does:
# 1. Does it only add logging? → Candidate for removal
# 2. Does it only add validation? → Candidate for removal
# 3. Does it only format results? → Check if formatting is essential
# 4. Does it have business logic? → Keep the wrapper

# Example: PerplexitySearch wrapper analysis
class PerplexitySearch < Base
  def call(query:, **options)
    # ✅ Logging - interceptor provides this
    RAAF.logger.debug "..."

    # ✅ Timing - interceptor provides this
    start_time = Time.now

    # ✅ Validation - interceptor provides this
    validate_options!

    # ⚠️ HTTP client initialization - needed
    result = @http_client.make_api_call(params)

    # ⚠️ Result formatting - check if core tool provides this
    format_search_result(result)
  end
end
```

### Step 2: Verify Core Tool Exists

Ensure the core tool has the functionality you need:

```ruby
# Check if core tool exists
core_tool = RAAF::Tools::PerplexityTool.new

# Verify it has a call method
core_tool.respond_to?(:call) # => true

# Check parameter compatibility
core_tool.method(:call).parameters
# => [[:keyreq, :query], [:key, :model], [:key, :search_domain_filter], ...]

# Test basic functionality
result = core_tool.call(query: "Test query")
# => { success: true, content: "...", citations: [...] }
```

### Step 3: Update Agent Class

Replace the DSL wrapper with the core tool:

```ruby
# BEFORE: Using DSL wrapper
class MyAgent < RAAF::DSL::Agent
  uses_tool :perplexity_search  # Uses RAAF::DSL::Tools::PerplexitySearch
end

# AFTER: Using raw core tool
class MyAgent < RAAF::DSL::Agent
  uses_tool RAAF::Tools::PerplexityTool, as: :perplexity_search

  # Optional: Configure execution behavior
  tool_execution do
    enable_validation true    # Validate parameters before execution
    enable_logging true       # Log execution start/end
    enable_metadata true      # Add execution metadata to results
    log_arguments true        # Include arguments in logs
    truncate_logs 100         # Truncate long log values
  end
end
```

### Step 4: Test Functionality

Verify the migration didn't break anything:

```ruby
# Test basic tool execution
agent = MyAgent.new
result = agent.execute_tool(tool, query: "Ruby news")

# Verify expected behavior:
# ✅ Result structure matches
expect(result).to have_key(:success)
expect(result).to have_key(:content)

# ✅ Validation works
expect {
  agent.execute_tool(tool, invalid_param: "value")
}.to raise_error(ArgumentError)

# ✅ Logging works (check logs)
# ✅ Metadata is present
expect(result).to have_key(:_execution_metadata)
expect(result[:_execution_metadata]).to have_key(:duration_ms)
```

### Step 5: Remove or Deprecate Wrapper

Once verified, you can:

**Option A: Delete the wrapper** (if completely redundant)

```ruby
# Delete dsl/lib/raaf/dsl/tools/perplexity_search.rb
```

**Option B: Deprecate the wrapper** (gradual migration)

```ruby
class PerplexitySearch < Base
  def initialize(options = {})
    super

    # Add deprecation warning
    RAAF.logger.warn <<~WARNING
      [DEPRECATION] RAAF::DSL::Tools::PerplexitySearch is deprecated.
      Use RAAF::Tools::PerplexityTool directly with the interceptor.

      # Change:
      uses_tool :perplexity_search

      # To:
      uses_tool RAAF::Tools::PerplexityTool, as: :perplexity_search
    WARNING
  end

  # Rest of implementation...
end
```

**Option C: Simplify to a thin wrapper** (minimal delegation)

```ruby
class PerplexitySearch < Base
  def initialize(options = {})
    super
    @core_tool = RAAF::Tools::PerplexityTool.new(options)
  end

  def call(**params)
    @core_tool.call(**params)
  end

  def dsl_wrapped?
    false  # Allow interceptor to apply conveniences
  end
end
```

## Configuration Options

The tool execution interceptor supports flexible configuration:

### Class-Level Configuration

```ruby
class MyAgent < RAAF::DSL::Agent
  # Configure for all agents of this type
  tool_execution do
    enable_validation true     # Default: true
    enable_logging true        # Default: true
    enable_metadata true       # Default: true
    log_arguments true         # Default: true
    truncate_logs 100          # Default: 100
  end
end
```

### Instance-Level Override

```ruby
agent = MyAgent.new
agent.tool_execution do
  enable_logging false  # Disable logging for this instance
end
```

### Per-Tool Configuration

```ruby
class MyAgent < RAAF::DSL::Agent
  uses_tool RAAF::Tools::PerplexityTool, as: :perplexity_search do
    # Tool-specific configuration
    model "sonar-pro"
    timeout 60
  end
end
```

## Common Migration Patterns

### Pattern 1: Simple Logging Wrapper

**Before:**
```ruby
class SimpleLoggingTool < Base
  def call(**params)
    RAAF.logger.debug "Executing #{tool_name}"
    result = perform_task(**params)
    RAAF.logger.debug "Completed #{tool_name}"
    result
  end
end
```

**After:**
```ruby
# Just use the core tool - logging is automatic
uses_tool RAAF::Tools::CoreTool, as: :simple_logging_tool
```

### Pattern 2: Validation Wrapper

**Before:**
```ruby
class ValidationTool < Base
  def call(param1:, param2:)
    validate_param1(param1)
    validate_param2(param2)
    perform_task(param1: param1, param2: param2)
  end

  private

  def validate_param1(value)
    raise ArgumentError unless value.is_a?(String)
  end
end
```

**After:**
```ruby
# Use tool definition for validation
uses_tool RAAF::Tools::CoreTool, as: :validation_tool

# The interceptor validates against tool_definition automatically
```

### Pattern 3: Metadata Wrapper

**Before:**
```ruby
class MetadataTool < Base
  def call(**params)
    start_time = Time.now
    result = perform_task(**params)

    result.merge(
      _metadata: {
        duration_ms: ((Time.now - start_time) * 1000).round(2),
        timestamp: Time.now.iso8601
      }
    )
  end
end
```

**After:**
```ruby
# Metadata injection is automatic
uses_tool RAAF::Tools::CoreTool, as: :metadata_tool
```

## Troubleshooting

### Issue: Validation Errors After Migration

**Symptom:**
```ruby
ArgumentError: Missing required parameter: query
```

**Solution:**
Ensure the core tool's `tool_definition` matches your parameter expectations:

```ruby
# Check tool definition
tool = RAAF::Tools::PerplexityTool.new
puts tool.tool_definition

# Verify required parameters match your usage
```

### Issue: Missing Metadata

**Symptom:**
```ruby
result[:_execution_metadata] # => nil
```

**Solution:**
Ensure metadata is enabled and the result is a Hash:

```ruby
tool_execution do
  enable_metadata true  # Must be true
end

# Metadata only added to Hash results, not Strings or Arrays
```

### Issue: No Logging Output

**Symptom:**
No log messages appear during tool execution.

**Solution:**
Check log level and configuration:

```ruby
# Set log level
ENV['RAAF_LOG_LEVEL'] = 'debug'

# Ensure logging is enabled
tool_execution do
  enable_logging true
end
```

### Issue: Double Logging

**Symptom:**
Log messages appear twice for the same tool execution.

**Solution:**
The tool is marked as `dsl_wrapped?` but shouldn't be:

```ruby
# Remove dsl_wrapped? method from tools that should use interceptor
class MyTool
  # Delete this method:
  # def dsl_wrapped?
  #   true
  # end
end
```

## Benefits of Migration

### Code Reduction

- **Before:** 200+ lines per wrapper
- **After:** 3 lines per agent tool declaration
- **Savings:** 95%+ code reduction

### Single Update Point

- **Before:** Update logging in each wrapper
- **After:** Update interceptor once
- **Benefit:** Changes apply to all tools automatically

### Consistent Behavior

- **Before:** Each wrapper implements logging differently
- **After:** All tools log consistently
- **Benefit:** Better debugging and monitoring

### Performance

- **Before:** Overhead varies per wrapper
- **After:** < 1ms consistent overhead
- **Benefit:** Predictable performance

## Gradual Migration Strategy

You don't need to migrate all wrappers at once:

### Phase 1: High-Value Targets

Migrate wrappers with the most code duplication:
- ✅ `PerplexitySearch` (245 lines)
- ✅ `TavilySearch` (247 lines)

### Phase 2: Medium Priority

Migrate moderately complex wrappers:
- ⚠️ Custom search tools
- ⚠️ Data transformation tools

### Phase 3: Low Priority

Keep or simplify wrappers with business logic:
- ℹ️ Configuration wrappers
- ℹ️ Composite tools

### Phase 4: Cleanup

Remove or deprecate redundant wrappers:
- 🗑️ Delete fully replaced wrappers
- ⚠️ Add deprecation warnings
- 📝 Update documentation

## Testing Checklist

Before removing a wrapper, verify:

- [ ] Core tool provides equivalent functionality
- [ ] All agent tests pass with core tool
- [ ] Validation works correctly
- [ ] Logging output is acceptable
- [ ] Metadata is present and correct
- [ ] Performance is acceptable (< 1ms overhead)
- [ ] No breaking changes to existing code
- [ ] Documentation updated

## Next Steps

1. **Identify wrappers** - Review `dsl/lib/raaf/dsl/tools/` directory
2. **Prioritize migration** - Focus on high-code-reduction opportunities
3. **Test thoroughly** - Ensure no regressions
4. **Update docs** - Keep documentation current
5. **Monitor usage** - Track which wrappers are still in use
6. **Gradual cleanup** - Remove wrappers over time

## Additional Resources

- **Interceptor Implementation:** `dsl/lib/raaf/dsl/agent.rb` (lines 2066-2108)
- **Configuration DSL:** `dsl/lib/raaf/dsl/tool_execution_config.rb`
- **Integration Tests:** `dsl/spec/raaf/dsl/tool_execution_integration_spec.rb`
- **Core Tools:** `core/lib/raaf/tools/`
- **Spec Document:** `.agent-os/specs/2025-10-10-agent-level-tool-execution-conveniences/spec.md`

## Support

If you encounter issues during migration:

1. Check the integration tests for working examples
2. Review the spec document for expected behavior
3. Test with a simple tool first before migrating complex wrappers
4. Keep the `dsl_wrapped?` marker during transition period

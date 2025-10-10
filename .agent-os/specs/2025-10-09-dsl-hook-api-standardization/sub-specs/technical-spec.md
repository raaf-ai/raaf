# Technical Specification: DSL Hook API Standardization

This is the technical specification for the spec detailed in @.agent-os/specs/2025-10-09-dsl-hook-api-standardization/spec.md

> Created: 2025-10-09
> Version: 1.0.0

## Technical Requirements

### Core Requirements

1. **Unified Hook Signature**
   - Single hash parameter for all hooks
   - Support for Ruby keyword argument unpacking
   - HashWithIndifferentAccess for all hook data

2. **Standard Parameter Injection**
   - Automatic injection of context, agent, timestamp
   - Available in ALL hooks without exception
   - Consistent access pattern

3. **Hook-Specific Parameter Preservation**
   - Merge hook-specific data with standard parameters
   - No data loss during standardization
   - Clear naming to avoid collisions

4. **Error Resilience**
   - Hooks should not crash agent execution
   - Log errors with full context
   - Continue with remaining hooks

## Implementation Approach

### Phase 1: Update fire_dsl_hook Method

The central hook firing mechanism will be completely rewritten:

```ruby
# File: dsl/lib/raaf/dsl/agent.rb
def fire_dsl_hook(hook_name, hook_data = {})
  return unless self.class.respond_to?(:_agent_hooks) && self.class._agent_hooks[hook_name]

  # Build comprehensive data with standard parameters
  comprehensive_data = {
    # Standard parameters (always present)
    context: @context || RAAF::DSL::ContextVariables.new,
    agent: self,
    timestamp: Time.now,

    # Hook-specific data
    **hook_data
  }

  # Ensure HashWithIndifferentAccess for flexible key access
  normalized_data = ActiveSupport::HashWithIndifferentAccess.new(comprehensive_data)

  # Execute each registered hook
  self.class._agent_hooks[hook_name].each do |hook|
    begin
      if hook.is_a?(Proc)
        # Pass data as single parameter with keyword extraction support
        instance_exec(normalized_data, &hook)
      elsif hook.is_a?(Symbol)
        # Method hooks also get the new signature
        send(hook, normalized_data)
      end
    rescue StandardError => e
      # Enhanced error logging with hook context
      log_error "❌ [#{self.class.name}] Hook #{hook_name} failed: #{e.message}"
      log_debug "Hook data", data: normalized_data.except(:context, :agent)
      log_debug "Error details", error: e.class.name, backtrace: e.backtrace.first(5)
    end
  end
end
```

### Phase 2: Update All Hook Call Sites

Every location where `fire_dsl_hook` is called must be updated:

```ruby
# on_context_built - line 2219
# Before:
fire_dsl_hook(:on_context_built, { context: run_context })

# After:
@context = run_context  # Ensure @context is set
fire_dsl_hook(:on_context_built, {})

# on_prompt_generated - line 2228
# Before:
fire_dsl_hook(:on_prompt_generated, {
  system_prompt: system_prompt,
  user_prompt: user_prompt,
  context: run_context
})

# After:
@context = run_context
fire_dsl_hook(:on_prompt_generated, {
  system_prompt: system_prompt,
  user_prompt: user_prompt
})

# on_validation_failed - lines 1104, 1118
# Before:
fire_dsl_hook(:on_validation_failed, {
  error: error_message,
  error_type: "schema_validation",
  field: field_name,
  value: field_value,
  expected_type: expected_type,
  timestamp: Time.now
})

# After (timestamp added automatically):
fire_dsl_hook(:on_validation_failed, {
  error: error_message,
  error_type: "schema_validation",
  field: field_name,
  value: field_value,
  expected_type: expected_type
})

# on_result_ready - line 1213
# Before:
fire_dsl_hook(:on_result_ready, {
  result: transformed_result,
  raw_result: raw_result,
  timestamp: Time.now
})

# After:
fire_dsl_hook(:on_result_ready, {
  result: transformed_result,
  raw_result: raw_result,
  processed_result: transformed_result  # Add alias for clarity
})

# on_tokens_counted - line 2255
# Before:
fire_dsl_hook(:on_tokens_counted, {
  input_tokens: input_tokens,
  output_tokens: output_tokens,
  total_tokens: total_tokens,
  estimated_cost: cost,
  model: model_name
})

# After (same, but standard params added automatically):
fire_dsl_hook(:on_tokens_counted, {
  input_tokens: input_tokens,
  output_tokens: output_tokens,
  total_tokens: total_tokens,
  estimated_cost: cost,
  model: model_name
})
```

### Phase 3: Update HooksAdapter for Core Hooks

The adapter that bridges DSL hooks to Core hooks needs updating:

```ruby
# File: dsl/lib/raaf/dsl/hooks/hooks_adapter.rb
class HooksAdapter < RAAF::AgentHooks

  def initialize(dsl_hooks_config, dsl_agent = nil)
    @dsl_hooks = dsl_hooks_config || {}
    @dsl_agent = dsl_agent
  end

  def on_start(context, agent)
    comprehensive_data = build_comprehensive_data(context, agent)
    execute_hooks(@dsl_hooks[:on_start], comprehensive_data)
  end

  def on_end(context, agent, output)
    comprehensive_data = build_comprehensive_data(context, agent, output: output)
    execute_hooks(@dsl_hooks[:on_end], comprehensive_data)
  end

  def on_handoff(context, agent, source)
    comprehensive_data = build_comprehensive_data(context, agent, source: source)
    execute_hooks(@dsl_hooks[:on_handoff], comprehensive_data)
  end

  def on_tool_start(context, agent, tool, arguments = {})
    comprehensive_data = build_comprehensive_data(context, agent,
      tool: tool,
      tool_name: tool.name,
      arguments: arguments
    )
    execute_hooks(@dsl_hooks[:on_tool_start], comprehensive_data)
  end

  def on_tool_end(context, agent, tool, result)
    comprehensive_data = build_comprehensive_data(context, agent,
      tool: tool,
      tool_name: tool.name,
      result: result
    )
    execute_hooks(@dsl_hooks[:on_tool_end], comprehensive_data)
  end

  def on_error(context, agent, error)
    comprehensive_data = build_comprehensive_data(context, agent, error: error)
    execute_hooks(@dsl_hooks[:on_error], comprehensive_data)
  end

  private

  def build_comprehensive_data(context, agent, **additional_data)
    ActiveSupport::HashWithIndifferentAccess.new({
      context: context,
      agent: @dsl_agent || agent,
      timestamp: Time.now,
      **additional_data
    })
  end

  def execute_hooks(hooks, comprehensive_data)
    return nil unless hooks&.any?

    last_result = nil

    hooks.each do |hook|
      begin
        case hook
        when Proc
          # Pass comprehensive data as single parameter
          last_result = hook.call(comprehensive_data)
        when Symbol
          # Method hooks need agent instance
          if @dsl_agent&.respond_to?(hook)
            last_result = @dsl_agent.send(hook, comprehensive_data)
          else
            RAAF.logger.warn "Method hook not available: #{hook}"
          end
        else
          RAAF.logger.warn "Unknown hook type: #{hook.class}"
        end
      rescue => e
        RAAF.logger.error "❌ Hook execution failed: #{e.message}"
        RAAF.logger.error "📄 Hook data: #{comprehensive_data.except(:context, :agent).inspect}"
      end
    end

    last_result
  end
end
```

### Phase 4: Update Result Transform Lambda Signature

The `result_transform` lambda signature needs updating to receive raw data:

```ruby
# File: dsl/lib/raaf/dsl/agent.rb
# Method: apply_result_transformations

def apply_result_transformations(base_result)
  return base_result unless self.class._result_transformations

  transformations = self.class._result_transformations
  transformed_result = base_result.dup

  transformations.each do |field, transformation|
    source_field = transformation[:from] || field
    source_value = base_result[source_field]

    begin
      # Handle both Proc and Symbol transforms
      transformed_value = case transformation[:transform]
      when Proc
        # Lambda/Proc: Check arity for parameter count
        if transformation[:transform].arity == 2
          # New signature: pass field value AND complete raw data
          transformation[:transform].call(source_value, base_result)
        elsif transformation[:transform].arity == 1
          # Old signature: just field value (backward compatibility)
          transformation[:transform].call(source_value)
        else
          # Arity 0 or negative (variadic) - call with both for flexibility
          transformation[:transform].call(source_value, base_result)
        end

      when Symbol
        # Symbol: Call agent method with same parameter logic
        method_name = transformation[:transform]
        method_obj = method(method_name)

        if method_obj.arity == 2 || method_obj.arity == -2 || method_obj.arity == -3
          # Method accepts 2 parameters (or optional params)
          send(method_name, source_value, base_result)
        elsif method_obj.arity == 1 || method_obj.arity == -1
          # Method accepts 1 parameter
          send(method_name, source_value)
        else
          # Fallback: try with both parameters
          send(method_name, source_value, base_result)
        end

      else
        raise ArgumentError, "Transform must be a Proc or Symbol, got #{transformation[:transform].class}"
      end

      transformed_result[field] = transformed_value
    rescue StandardError => e
      log_error "❌ [#{self.class.name}] Transform failed for field #{field}: #{e.message}"
      log_debug "Transform error details", field: field, source_value: source_value&.class, transform_type: transformation[:transform].class
      # Keep original value on transformation error
      transformed_result[field] = source_value
    end
  end

  transformed_result
end
```

**Usage Examples:**

```ruby
# Backward compatible: Single parameter still works
result_transform do
  field :simple_field,
    from: :data,
    transform: ->(data) {
      data.upcase  # No second parameter needed
    }
end

# New signature: Optional second parameter for accessing other fields
result_transform do
  field :prospects,
    from: :prospects,
    transform: ->(prospects, raw_data = nil) {
      # Second parameter is optional but available
      # Can access any field from raw_data when needed
      context = raw_data&.dig(:context)
      metadata = raw_data&.dig(:metadata)

      prospects.map do |p|
        enhance_prospect(p,
          context: context,
          metadata: metadata
        )
      end
    }

  field :enriched_count,
    from: :prospects,
    transform: ->(prospects, raw_data = nil) {
      # Use other fields for calculations
      filter_criteria = raw_data&.dig(:filter_criteria) || {}
      prospects.select { |p| matches_criteria?(p, filter_criteria) }.count
    }

  # Symbol support: Call agent method
  field :formatted_prospects,
    from: :prospects,
    transform: :format_prospects_with_context
end

# Agent method with same signature
def format_prospects_with_context(prospects, raw_data = nil)
  context = raw_data&.dig(:context)
  metadata = raw_data&.dig(:metadata)

  prospects.map do |p|
    format_prospect(p, context: context, metadata: metadata)
  end
end
```

### Phase 5: Update Hook Documentation

Update all hook method documentation to reflect new signature:

```ruby
# File: dsl/lib/raaf/dsl/hooks/agent_hooks.rb

# Before:
# @yield [agent] Block called when agent starts
# @yieldparam agent [RAAF::Agent] The agent that is starting

# After:
# @yield [data] Block called when agent starts with comprehensive data
# @yieldparam data [Hash] Comprehensive data hash with standard and hook-specific parameters
# @yieldparam data.context [ContextVariables] The agent's context
# @yieldparam data.agent [Agent] The agent instance
# @yieldparam data.timestamp [Time] When the hook fired
```

## Hook-Specific Parameter Mappings

### DSL-Level Hooks

| Hook Name | Standard Parameters | Hook-Specific Parameters |
|-----------|-------------------|-------------------------|
| `on_context_built` | context, agent, timestamp | (none - context is the main data) |
| `on_prompt_generated` | context, agent, timestamp | system_prompt, user_prompt |
| `on_validation_failed` | context, agent, timestamp | error, error_type, field, value, expected_type |
| `on_result_ready` | context, agent, timestamp | result, raw_result, processed_result |
| `on_tokens_counted` | context, agent, timestamp | input_tokens, output_tokens, total_tokens, estimated_cost, model |

### Core Hooks (via Adapter)

| Hook Name | Standard Parameters | Hook-Specific Parameters |
|-----------|-------------------|-------------------------|
| `on_start` | context, agent, timestamp | (none) |
| `on_end` | context, agent, timestamp | output |
| `on_handoff` | context, agent, timestamp | source |
| `on_tool_start` | context, agent, timestamp | tool, tool_name, arguments |
| `on_tool_end` | context, agent, timestamp | tool, tool_name, result |
| `on_error` | context, agent, timestamp | error |

## Testing Strategy

### Test Categories

1. **Signature Tests**
   - Verify all hooks receive comprehensive data
   - Test keyword argument unpacking
   - Verify standard parameters present

2. **Data Access Tests**
   - Test HashWithIndifferentAccess support
   - Verify both string and symbol key access
   - Test nested data access

3. **Error Handling Tests**
   - Verify hook errors don't crash agent
   - Test error logging with context
   - Verify remaining hooks execute

4. **Integration Tests**
   - Test hooks in full agent execution
   - Verify data flow through pipeline
   - Test Core hook adapter

### Example Test Cases

```ruby
RSpec.describe "Standardized Hook API" do
  describe "standard parameters" do
    it "provides context, agent, and timestamp to all hooks" do
      received_data = nil

      agent_class = Class.new(RAAF::DSL::Agent) do
        on_result_ready do |data|
          received_data = data
        end
      end

      agent = agent_class.new(test: "value")
      agent.instance_variable_set(:@context, RAAF::DSL::ContextVariables.new.set(:test, "value"))

      agent.send(:fire_dsl_hook, :on_result_ready, { result: "test" })

      expect(received_data[:context]).to be_a(RAAF::DSL::ContextVariables)
      expect(received_data[:agent]).to eq(agent)
      expect(received_data[:timestamp]).to be_a(Time)
      expect(received_data[:result]).to eq("test")
    end
  end

  describe "keyword argument unpacking" do
    it "supports selective parameter extraction" do
      captured_context = nil
      captured_result = nil

      agent_class = Class.new(RAAF::DSL::Agent) do
        on_result_ready do |data, context:, result:, **|
          captured_context = context
          captured_result = result
        end
      end

      agent = agent_class.new
      test_context = RAAF::DSL::ContextVariables.new.set(:key, "value")
      agent.instance_variable_set(:@context, test_context)

      agent.send(:fire_dsl_hook, :on_result_ready, { result: "success" })

      expect(captured_context).to eq(test_context)
      expect(captured_result).to eq("success")
    end

    it "allows ignoring unused parameters with **" do
      captured_error = nil

      agent_class = Class.new(RAAF::DSL::Agent) do
        on_validation_failed do |data, error:, **|
          captured_error = error
        end
      end

      agent = agent_class.new
      agent.send(:fire_dsl_hook, :on_validation_failed, {
        error: "Validation failed",
        field: :unused,
        value: "ignored"
      })

      expect(captured_error).to eq("Validation failed")
    end
  end

  describe "HashWithIndifferentAccess" do
    it "supports both string and symbol key access" do
      received_data = nil

      agent_class = Class.new(RAAF::DSL::Agent) do
        on_tokens_counted do |data|
          received_data = data
        end
      end

      agent = agent_class.new
      agent.send(:fire_dsl_hook, :on_tokens_counted, {
        input_tokens: 100,
        output_tokens: 50
      })

      expect(received_data[:input_tokens]).to eq(100)
      expect(received_data["input_tokens"]).to eq(100)
      expect(received_data[:output_tokens]).to eq(50)
      expect(received_data["output_tokens"]).to eq(50)
    end
  end
end
```

## Rationale for Design Decisions

### Why Single Hash Parameter?

1. **Consistency** - All hooks work the same way
2. **Flexibility** - Easy to add new parameters
3. **Ruby Idiom** - Keyword argument unpacking is idiomatic
4. **Future-Proof** - Can extend without breaking changes

### Why Standard Parameters?

1. **Context Access** - Always need agent context for decisions
2. **Agent Reference** - Often need to check agent configuration
3. **Timing** - Useful for performance tracking and correlation
4. **Debugging** - Standard data helps troubleshooting

### Why HashWithIndifferentAccess?

1. **RAAF Standard** - Consistent with rest of framework
2. **Flexibility** - Works with string or symbol keys
3. **LLM Compatibility** - LLMs return varied key formats
4. **Developer Experience** - No key type confusion

### Why Breaking Change?

1. **Clean API** - No legacy complexity
2. **Clear Migration** - One-time update, not gradual
3. **Simplicity** - No dual-mode support code
4. **Documentation** - Single API to document

## Migration Guide for Users

### Basic Migration Pattern

```ruby
# OLD: Different patterns for different hooks
on_context_built do |data|
  context = data[:context]
  # No access to agent or timestamp
end

on_validation_failed do |data|
  error = data[:error]
  field = data[:field]
  # Different data structure
end

# NEW: Consistent pattern for all hooks
on_context_built do |data, context:, agent:, timestamp:, **|
  # Direct access to what you need
end

on_validation_failed do |data, context:, agent:, error:, field:, **|
  # Same standard params plus hook-specific ones
end
```

### Advanced Migration Examples

```ruby
# Example 1: Logging with context
# OLD
on_tokens_counted do |data|
  Rails.logger.info "Tokens: #{data[:total_tokens]}"
end

# NEW
on_tokens_counted do |data, agent:, total_tokens:, estimated_cost:, **|
  Rails.logger.info "[#{agent.class.name}] Tokens: #{total_tokens}, Cost: $#{estimated_cost}"
end

# Example 2: Conditional logic based on context
# OLD
on_result_ready do |data|
  result = data[:result]
  # How to check context?
end

# NEW
on_result_ready do |data, context:, result:, **|
  if context[:debug_mode]
    puts "Debug: Result = #{result.inspect}"
  end
end

# Example 3: Error handling with full context
# OLD
on_error do |agent, error|
  # Limited access to context
end

# NEW
on_error do |data, context:, agent:, error:, timestamp:, **|
  ErrorReporter.report(
    error: error,
    agent: agent.class.name,
    context: context.to_h,
    timestamp: timestamp
  )
end
```

## External Dependencies

- `ActiveSupport::HashWithIndifferentAccess` - Already used throughout RAAF
- No new gem dependencies required
- No external API changes required

## Performance Considerations

- Minor overhead from building comprehensive data hash (~microseconds)
- HashWithIndifferentAccess has negligible performance impact
- Hook execution remains synchronous (no change)
- Error handling prevents cascade failures

## Security Considerations

- Context may contain sensitive data - ensure hooks don't log it raw
- Agent instance access could expose internals - document best practices
- Timestamp provides audit trail capability
- Error messages should sanitize sensitive data
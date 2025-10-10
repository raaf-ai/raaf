# Specification: DSL Hook API Standardization

## Goal
Standardize all DSL hooks in RAAF to use a consistent single-hash parameter signature with keyword argument support, providing comprehensive data access through standard parameters and improving developer experience.

## User Stories

### Developer Using DSL Hooks
As a RAAF developer, I want to use DSL hooks with a consistent, predictable API so that I can access context, agent state, and hook-specific data using the same pattern across all hooks.

**Current Pain Points:**
- Different hooks receive different parameter structures
- Some hooks get single data hash, others get positional parameters
- Context and agent access is inconsistent
- Difficult to remember what parameters each hook provides

**Desired Experience:**
- All hooks use the same signature pattern
- Standard parameters (context, agent, timestamp) always available
- Hook-specific parameters clearly documented
- Keyword argument unpacking for clean code

### Framework Maintainer
As a RAAF maintainer, I want a standardized hook API so that adding new hooks, documenting the system, and fixing bugs becomes straightforward and predictable.

**Benefits:**
- Single implementation pattern for all hooks
- Easier to add new hooks following the standard
- Consistent documentation structure
- Simplified testing patterns

## Spec Scope

### Included in Standardization

1. **Signature Standardization**
   - All DSL hooks use single hash parameter
   - Support for keyword argument unpacking
   - Consistent data structure across all hooks

2. **Standard Parameters (Available in All Hooks)**
   - `context` - The agent's @context instance variable (ContextVariables)
   - `agent` - The agent instance (self)
   - `timestamp` - When the hook was fired (Time.now)

3. **Hook-Specific Parameters**
   - `raw_result` - Unprocessed AI result (where applicable)
   - `processed_result` - After transformations (where applicable)
   - `error` - Exception object (for error hooks)
   - `field`, `value`, `expected_type` - For validation hooks
   - `input_tokens`, `output_tokens`, `estimated_cost` - For token hooks
   - `system_prompt`, `user_prompt` - For prompt hooks

4. **Hooks to Standardize**
   - **DSL-level hooks:** `on_context_built`, `on_prompt_generated`, `on_validation_failed`, `on_result_ready`, `on_tokens_counted`
   - **Core hooks via adapter:** `on_start`, `on_end`, `on_error`, `on_tool_start`, `on_tool_end`, `on_handoff`

5. **Result Transform Lambda Signature**
   - Update `result_transform` lambda to optionally receive raw data as second parameter
   - Signature: `transform: ->(field_value, raw_data = nil) { ... }`
   - Second parameter is optional - backward compatible
   - Provides access to other fields during transformation when needed
   - Raw data available for context-aware transformations
   - **Symbol Support**: `transform: :method_name` calls agent method with same parameters
   - Method signature: `def method_name(field_value, raw_data = nil)`

6. **Implementation Changes**
   - Modify `fire_dsl_hook` method in `agent.rb`
   - Update all hook call sites
   - Update `HooksAdapter` for Core hooks
   - Update `apply_result_transformations` to pass raw_data to lambdas
   - Ensure HashWithIndifferentAccess throughout

## Out of Scope

1. **Backward Compatibility**
   - This is a breaking change with no migration path
   - Existing hook implementations must be updated
   - No dual-signature support period

2. **New Hook Types**
   - Not adding new hook types in this spec
   - Focus only on standardizing existing hooks

3. **Hook Execution Order**
   - Not changing hook execution ordering
   - Not implementing priority system

4. **Async Hooks**
   - Not implementing asynchronous hook execution
   - All hooks remain synchronous

## Expected Deliverable

### Working Hook System with Standardized API

All RAAF DSL hooks will use the new standardized signature:

```ruby
# New standardized signature for ALL hooks - true Ruby keyword arguments
on_hook_name do |context:, agent:, timestamp:, **hook_specific|
  # Direct access via keyword arguments - no data hash needed
  puts "Agent: #{agent.class.name}"
  puts "Context has: #{context.keys}"
  puts "Fired at: #{timestamp}"

  # Access hook-specific parameters as keyword arguments
  puts "Specific data: #{hook_specific[:raw_result]}"
end

# Alternative: Use only what you need, ** ignores extra parameters
on_result_ready do |processed_result:, **|
  # Only extract the parameters you care about
  # ** captures and ignores context, agent, timestamp, raw_result
  puts "Result: #{processed_result}"
end

# Capture all parameters as a hash when needed
on_tokens_counted do |**data|
  # data is a hash with all parameters (both standard and hook-specific)
  TokenTracker.record(data)
end
```

### Updated fire_dsl_hook Method

The central `fire_dsl_hook` method uses `**hash` to spread parameters as Ruby keyword arguments:

```ruby
def fire_dsl_hook(hook_name, hook_data = {})
  # Build comprehensive data hash with standard parameters
  comprehensive_data = {
    context: @context || RAAF::DSL::ContextVariables.new,
    agent: self,
    timestamp: Time.now,
    **hook_data  # Merge in hook-specific data
  }

  # Ensure HashWithIndifferentAccess for flexible key access
  normalized_data = ActiveSupport::HashWithIndifferentAccess.new(comprehensive_data)

  # Convert to symbol keys for keyword arguments (deep to handle nested hashes)
  # HashWithIndifferentAccess uses string keys internally, but keyword arguments need symbols
  symbol_keyed_data = normalized_data.deep_symbolize_keys

  # Execute hooks with keyword arguments using ** operator
  self.class._agent_hooks[hook_name].each do |hook|
    begin
      if hook.is_a?(Proc)
        # Use instance_exec to execute block with keyword arguments
        # This enables clean Ruby syntax: |param1:, param2:, **|
        instance_exec(**symbol_keyed_data, &hook)
      elsif hook.is_a?(Symbol)
        # Call method with keyword arguments
        send(hook, **symbol_keyed_data)
      end
    rescue StandardError => e
      log_error("Hook '#{hook_name}' failed: #{e.message}\nData: #{normalized_data.inspect}\nBacktrace: #{e.backtrace.join("\n")}")
    end
  end
end
```

### Updated HooksAdapter for Core Hooks

The HooksAdapter will be updated to pass data in the new format:

```ruby
class HooksAdapter < RAAF::AgentHooks
  def on_start(context, agent)
    comprehensive_data = {
      context: context,
      agent: @dsl_agent || agent,
      timestamp: Time.now
    }
    execute_hooks(@dsl_hooks[:on_start], comprehensive_data)
  end

  def on_end(context, agent, output)
    comprehensive_data = {
      context: context,
      agent: @dsl_agent || agent,
      timestamp: Time.now,
      output: output
    }
    execute_hooks(@dsl_hooks[:on_end], comprehensive_data)
  end
end
```

### Complete Test Coverage

All tests will be updated to use the new signature:

```ruby
describe "Standardized Hook API with True Keyword Arguments" do
  it "provides standard parameters via keyword arguments" do
    agent_class = Class.new(RAAF::DSL::Agent) do
      on_context_built do |context:, agent:, timestamp:, **|
        # Direct keyword argument access - no data hash
        @received_context = context
        @received_agent = agent
        @received_timestamp = timestamp
      end
    end

    agent = agent_class.new(test: "value")
    agent.send(:fire_dsl_hook, :on_context_built, {})

    expect(agent.instance_variable_get(:@received_context)).to be_a(RAAF::DSL::ContextVariables)
    expect(agent.instance_variable_get(:@received_agent)).to eq(agent)
    expect(agent.instance_variable_get(:@received_timestamp)).to be_a(Time)
  end

  it "supports selective keyword argument extraction" do
    agent_class = Class.new(RAAF::DSL::Agent) do
      on_validation_failed do |error:, field:, **|
        # Extract only what we need, ** ignores context, agent, timestamp
        @error_message = error
        @failed_field = field
      end
    end

    agent = agent_class.new
    agent.send(:fire_dsl_hook, :on_validation_failed, {
      error: "Validation failed",
      field: :age
    })

    expect(agent.instance_variable_get(:@error_message)).to eq("Validation failed")
    expect(agent.instance_variable_get(:@failed_field)).to eq(:age)
  end

  it "allows capturing all parameters as hash" do
    agent_class = Class.new(RAAF::DSL::Agent) do
      on_tokens_counted do |**data|
        # Capture all keyword arguments into a hash
        @token_usage = data
      end
    end

    agent = agent_class.new
    agent.send(:fire_dsl_hook, :on_tokens_counted, {
      input_tokens: 100,
      output_tokens: 50,
      total_tokens: 150
    })

    usage = agent.instance_variable_get(:@token_usage)
    expect(usage[:input_tokens]).to eq(100)
    expect(usage[:output_tokens]).to eq(50)
    expect(usage[:total_tokens]).to eq(150)
  end
end
```

## Technical Implementation Details

### Breaking Changes

**Before (Manual Unpacking Pattern):**
```ruby
# Manual unpacking from data hash
on_context_built do |data|
  context = data[:context]  # Manual extraction required
  # No access to agent or timestamp
end

on_validation_failed do |data|
  error = data[:error]      # Manual extraction required
  field = data[:field]
  # No access to context or agent
end

# Defensive access needed for nested hashes
on_result_ready do |data|
  result = data[:result] || data["result"]  # String vs symbol confusion
  field = result[:field] || result["field"]  # Defensive at every level
end
```

**After (True Keyword Arguments):**
```ruby
# Clean keyword argument syntax - no manual unpacking
on_context_built do |context:, agent:, timestamp:, **|
  # Direct access via keyword arguments
  # Standard parameters always available
end

on_validation_failed do |error:, field:, context:, agent:, timestamp:, **|
  # All parameters (standard + hook-specific) as keyword arguments
  # Clean and idiomatic Ruby
end

# No defensive access needed - deep_symbolize_keys ensures symbol keys
on_result_ready do |raw_result:, processed_result:, **|
  # Just works - all nested hashes have symbol keys
  field = processed_result[:field]  # No fallback needed
end
```

### Hook Call Site Updates

All places where hooks are fired will be updated:

```ruby
# Before
fire_dsl_hook(:on_context_built, { context: run_context })

# After (automatically adds standard parameters)
fire_dsl_hook(:on_context_built, {})  # context, agent, timestamp added automatically

# Before
fire_dsl_hook(:on_validation_failed, {
  error: "Field validation failed",
  field: :age,
  value: "invalid"
})

# After (hook-specific data merged with standard parameters)
fire_dsl_hook(:on_validation_failed, {
  error: "Field validation failed",
  field: :age,
  value: "invalid"
})
```

### Result Transform Lambda Enhancement

**Current (Single Parameter):**
```ruby
result_transform do
  field :prospects,
    from: :prospects,
    transform: ->(prospects) {
      # Can only access the prospects array
      # No access to other fields in the result
      prospects.map { |p| enhance(p) }
    }
end
```

**Enhanced (Optional Second Parameter + **args Support):**
```ruby
result_transform do
  # Single parameter still works (backward compatible)
  field :simple_field,
    from: :data,
    transform: ->(data) {
      data.upcase  # Second parameter not needed
    }

  # Two parameters when you need access to other fields
  field :prospects,
    from: :prospects,
    transform: ->(prospects, raw_data = nil) {
      # Second parameter is optional but available when needed
      # Can use other fields during transformation
      context = raw_data&.dig(:context)
      metadata = raw_data&.dig(:metadata)

      prospects.map { |p| enhance(p, context: context, metadata: metadata) }
    }

  # Two parameters + **args for maximum flexibility
  field :filtered_prospects,
    from: :prospects,
    transform: ->(prospects, raw_data, **args) {
      # Most flexible signature - supports additional keyword arguments in future
      # Filter based on criteria from raw_data
      survivors = prospects.select { |p| p[:passed_filter] == true }
      RAAF.logger.info "🎯 Filtered to #{survivors.length} prospects (#{prospects.length - survivors.length} rejected)"
      survivors
    }

  # Symbol support - calls agent method with same parameters
  field :enriched_prospects,
    from: :prospects,
    transform: :enhance_prospects_with_context
end

# Agent method with same signature as lambda
def enhance_prospects_with_context(prospects, raw_data = nil)
  context = raw_data&.dig(:context)
  metadata = raw_data&.dig(:metadata)

  prospects.map { |p| enhance(p, context: context, metadata: metadata) }
end
```

**Implementation in transform_field_value:**
```ruby
def transform_field_value(source_value, field_config, raw_data = nil)
  value = source_value

  if value && field_config[:transform]
    transform = field_config[:transform]
    value = case transform
            when Proc
              # Lambda/Proc: Check arity for parameter count
              if transform.arity == -3 # 2 required params + **args (most flexible)
                transform.call(value, raw_data)
              elsif transform.arity == 2 || transform.arity == -2 # Exactly 2 params or 1 required + 1 optional
                transform.call(value, raw_data)
              else
                # Backward compatibility: single parameter
                transform.call(value)
              end
            when Symbol
              # Symbol: Call agent method with same parameters
              method_obj = method(transform)
              if method_obj.arity == -3 # 2 required params + **args
                send(transform, value, raw_data)
              elsif method_obj.arity == 2 || method_obj.arity == -2
                send(transform, value, raw_data)
              else
                # Backward compatibility: single parameter
                send(transform, value)
              end
            end
  end

  value
end
```

**Ruby Arity Reference for Transform Signatures:**
- `arity 1`: `->(data)` - Single required parameter (backward compatible)
- `arity 2`: `->(data, raw_data)` - Two required parameters
- `arity -2`: `->(data, raw_data = nil)` - One required + one optional parameter
- `arity -3`: `->(data, raw_data, **args)` - Two required + keyword arguments (most flexible)

### Handling Missing Parameters (Forward Compatibility)

Ruby's keyword arguments with `**` (double splat) handle missing parameters gracefully:

```ruby
# Safe Pattern (Recommended) - Always use ** for forward compatibility
on_result_ready do |raw_result:, processed_result:, **|
  # Gets raw_result and processed_result
  # ** captures and ignores context, agent, timestamp, and any future parameters
  # Hook won't break if new parameters are added later
end

# Minimal Pattern - Only extract what you need
on_result_ready do |raw_result:, **|
  # Only gets raw_result
  # ** captures everything else (processed_result, context, agent, timestamp)
end

# Strict Pattern (Not Recommended) - Can break with new parameters
on_result_ready do |raw_result:, processed_result:|
  # Ruby raises ArgumentError if extra parameters are present
  # No ** means this breaks when new parameters are added
  # Avoid this pattern for hooks
end

# Capture All Pattern - Useful for logging or delegation
on_tokens_counted do |**data|
  # data is a hash with all parameters
  # Safe for any number of parameters
  TokenTracker.record(data)
end
```

**Best Practice:** Always include `**` in hook definitions to:
1. Accept and ignore extra parameters you don't need
2. Maintain forward compatibility when new parameters are added
3. Make code resilient to future hook enhancements

### Benefits of Standardization

1. **Consistent Developer Experience**
   - Same pattern for all hooks
   - Predictable parameter access
   - Clear documentation
   - Transform lambdas can access full context

2. **Improved Debugging**
   - Always have context available
   - Always have agent reference
   - Always have timestamp for correlation
   - Transform lambdas see complete raw data

3. **Cleaner Code**
   - True Ruby keyword arguments
   - No manual unpacking needed
   - Self-documenting parameters
   - Context-aware transformations
   - No defensive key access (symbol vs string)

4. **Future Extensibility**
   - Easy to add new standard parameters
   - Hook-specific parameters clearly separated
   - Consistent pattern for new hooks
   - Transform lambdas can use any field
   - `**` ensures forward compatibility

### Migration Impact

**Required Updates:**
- All existing hook implementations in user code
- All tests using hooks
- Documentation and examples

**No Compatibility Layer:**
- Clean break with old API
- Clear error messages for old-style hooks
- Comprehensive migration examples

## Success Criteria

1. All DSL hooks use the standardized signature
2. All standard parameters available in every hook
3. Keyword argument unpacking works correctly
4. HashWithIndifferentAccess support throughout
5. All tests pass with new signature
6. Documentation updated with new examples
7. Clear error messages for incorrect usage
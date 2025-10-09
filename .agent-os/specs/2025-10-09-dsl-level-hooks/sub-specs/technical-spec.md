# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-10-09-dsl-level-hooks/spec.md

> Created: 2025-10-09
> Version: 1.0.0

## Technical Requirements

### Architecture Overview

RAAF DSL agents delegate to core agents, creating a two-level execution model:

```
DSL Agent
  ├─ Context Building (NEW: on_context_built hook)
  ├─ Prompt Generation (NEW: on_prompt_generated hook)
  ├─ Execute Core Agent
  │    ├─ Core on_agent_start (receives raw prompts)
  │    ├─ AI Provider Call
  │    ├─ Core on_agent_end (receives raw AI output)
  │    └─ Return raw result
  ├─ Schema Validation (NEW: on_validation_failed hook)
  ├─ Result Transformation (result_transform block)
  ├─ NEW: on_result_ready hook (receives transformed data)
  └─ Return final result
```

**Key Insight**: Core hooks fire during agent execution (step 3), DSL hooks fire during DSL processing (steps 1, 2, 4, 5, 6).

### Hook Execution Points

#### File: `dsl/lib/raaf/dsl/agent.rb`

**1. `on_context_built` Hook**
- **Location**: After `resolve_run_context()` in `execute()` method (line ~2053)
- **Fires**: After context assembly, before AI provider call
- **Data**: Complete RunContext with all variables

```ruby
# In execute() method around line 2053
def execute(context, input_context_variables, stop_checker)
  run_context = resolve_run_context(context || input_context_variables)

  # NEW: Fire DSL hook with assembled context
  fire_dsl_hook(:on_context_built, { context: run_context })

  openai_agent = create_agent
  # ... rest of execute
end
```

**2. `on_prompt_generated` Hook**
- **Location**: After `build_user_prompt_with_context()` in `execute()` method (line ~2056)
- **Fires**: After system and user prompts are generated
- **Data**: System prompt, user prompt, context

```ruby
# In execute() method around line 2056
def execute(context, input_context_variables, stop_checker)
  run_context = resolve_run_context(context || input_context_variables)
  fire_dsl_hook(:on_context_built, { context: run_context })

  openai_agent = create_agent
  user_prompt = build_user_prompt_with_context(run_context)

  # NEW: Fire DSL hook with generated prompts
  fire_dsl_hook(:on_prompt_generated, {
    system_prompt: openai_agent.instructions,
    user_prompt: user_prompt,
    context: run_context
  })

  # ... rest of execute
end
```

**3. `on_validation_failed` Hook**
- **Location**: In `extract_result_data()` method when validation fails (line ~1208)
- **Fires**: When schema validation detects errors
- **Data**: Validation errors, raw AI response, expected schema

```ruby
# In extract_result_data() around line 1208
def extract_result_data(results)
  # ... existing validation logic

  if validation_errors.any?
    # NEW: Fire DSL hook before raising error
    fire_dsl_hook(:on_validation_failed, {
      validation_errors: validation_errors,
      raw_response: results,
      expected_schema: self.class._schema,
      timestamp: Time.now
    })

    raise RAAF::Errors::ValidationError, "Validation failed: #{validation_errors.join(', ')}"
  end

  # ... rest of method
end
```

**4. `on_result_ready` Hook**
- **Location**: At end of `process_raaf_result()` method (line ~1130)
- **Fires**: After all transformations complete
- **Data**: Fully transformed result with all field mappings

```ruby
# In process_raaf_result() around line 1130
def process_raaf_result(raaf_result)
  base_result = if raaf_result.is_a?(Hash) && raaf_result[:success] && raaf_result[:results]
    extract_result_data(raaf_result[:results])
  elsif raaf_result.is_a?(Hash)
    extract_hash_result(raaf_result)
  else
    { success: true, data: raaf_result }
  end

  # Apply result transformations if configured
  final_result = if self.class._result_transformations
    apply_result_transformations(base_result)
  else
    generate_auto_transformations_for_output_fields(base_result)
  end

  # NEW: Fire DSL hook with transformed result
  fire_dsl_hook(:on_result_ready, {
    result: final_result,
    timestamp: Time.now
  })

  final_result
end
```

**5. `on_tokens_counted` Hook**
- **Location**: After token counting in `execute()` or `transform_ai_result()` (line ~2080)
- **Fires**: After AI response is received and tokens are counted
- **Data**: Input tokens, output tokens, total tokens, estimated cost

```ruby
# In transform_ai_result() or execute() after run_result
def execute(context, input_context_variables, stop_checker)
  # ... existing execution logic

  run_result = runner.run(user_prompt, context: run_context)

  # NEW: Extract token usage and fire hook
  if run_result.respond_to?(:usage)
    usage = run_result.usage
    fire_dsl_hook(:on_tokens_counted, {
      input_tokens: usage[:input_tokens],
      output_tokens: usage[:output_tokens],
      total_tokens: usage[:total_tokens],
      estimated_cost: calculate_cost(usage, openai_agent.model),
      model: openai_agent.model,
      timestamp: Time.now
    })
  end

  # ... rest of method
end
```

**6. `on_retry_attempt` Hook**
- **Location**: In retry wrapper (if implemented) or in `execute()` with retry logic
- **Fires**: Before each retry attempt
- **Data**: Attempt number, error, backoff delay, max attempts

**7. `on_execution_slow` Hook**
- **Location**: In `execute()` method with execution timing
- **Fires**: When execution exceeds threshold
- **Data**: Execution time, threshold, operation details

**8-10. Circuit Breaker and Pipeline Hooks**
- **Location**: In circuit breaker wrapper and pipeline execution logic
- **Implementation**: Requires circuit breaker pattern and pipeline stage tracking

### Hook Registration API

#### File: `dsl/lib/raaf/dsl/hooks/run_hooks.rb`

Add new DSL hook types to existing infrastructure:

```ruby
# Extend HOOK_TYPES constant
HOOK_TYPES = %i[
  # Existing core hooks (unchanged)
  on_agent_start
  on_agent_end
  on_handoff
  on_tool_start
  on_tool_end
  on_error

  # NEW: Tier 1 - Essential DSL lifecycle hooks
  on_context_built
  on_validation_failed
  on_result_ready

  # NEW: Tier 2 - High-value development hooks
  on_prompt_generated
  on_tokens_counted
  on_circuit_breaker_open
  on_circuit_breaker_closed

  # NEW: Tier 3 - Specialized operations hooks
  on_retry_attempt
  on_execution_slow
  on_pipeline_stage_complete
].freeze
```

**Usage Pattern (Unchanged)**:

```ruby
class MyAgent < RAAF::DSL::Agent
  # Existing core hooks still work
  on_agent_end do |result|
    puts "Raw AI output: #{result[:message]}"
  end

  # NEW: DSL hooks with same syntax
  on_result_ready do |data|
    puts "Transformed data: #{data[:result][:markets]}"
    puts "Timestamp: #{data[:timestamp]}"
  end

  on_validation_failed do |data|
    Rails.logger.error "Validation errors: #{data[:validation_errors]}"
    Rails.logger.error "Expected schema: #{data[:expected_schema]}"
  end

  on_tokens_counted do |data|
    Rails.logger.info "Tokens used: #{data[:total_tokens]}"
    Rails.logger.info "Estimated cost: $#{data[:estimated_cost]}"
  end
end
```

### Implementation Approach

**Phase 1: Core Hook Infrastructure** (Tier 1 hooks)
1. Add DSL hook types to `HOOK_TYPES` constant
2. Implement `fire_dsl_hook()` helper method in `agent.rb`
3. Add hook execution points for `on_context_built`, `on_validation_failed`, `on_result_ready`
4. Write unit tests for each hook

**Phase 2: Development Hooks** (Tier 2 hooks)
1. Implement `on_prompt_generated` hook with prompt data
2. Implement `on_tokens_counted` with cost calculation
3. Implement circuit breaker hooks (requires circuit breaker pattern)
4. Write integration tests with transformations

**Phase 3: Specialized Hooks** (Tier 3 hooks)
1. Implement retry hooks (requires retry wrapper)
2. Implement execution timing hooks
3. Implement pipeline hooks (requires pipeline stage tracking)
4. Write comprehensive integration tests

### Backward Compatibility Strategy

**Critical Requirements**:
1. **No changes to core hooks**: `on_agent_start`, `on_agent_end`, etc. remain unchanged
2. **Opt-in DSL hooks**: Agents without DSL hooks work exactly as before
3. **Same registration API**: DSL hooks use identical `on_hook_name do ... end` syntax
4. **Data structure consistency**: All hooks receive `HashWithIndifferentAccess` data

**Migration Path**:
- Existing agents: No changes required, continue using core hooks
- New agents: Can use DSL hooks for transformed data access
- Hybrid agents: Can use both core and DSL hooks simultaneously

```ruby
# Backward compatible: Existing agent unchanged
class LegacyAgent < RAAF::DSL::Agent
  on_agent_end do |result|
    puts "Still works: #{result[:message]}"
  end
end

# New pattern: DSL hooks for transformed data
class ModernAgent < RAAF::DSL::Agent
  on_result_ready do |data|
    puts "Transformed: #{data[:result][:markets]}"
  end
end

# Hybrid: Both core and DSL hooks
class HybridAgent < RAAF::DSL::Agent
  on_agent_end do |result|
    puts "Raw: #{result[:message]}"
  end

  on_result_ready do |data|
    puts "Transformed: #{data[:result][:markets]}"
  end
end
```

### External Dependencies

- **No new gems required**: Implementation uses existing RAAF DSL infrastructure
- **Cost calculation**: Requires model pricing data (can be static hash)
- **Circuit breaker**: Optional - implement if circuit breaker pattern is added
- **Pipeline tracking**: Optional - implement if pipeline stage tracking is added

### Performance Considerations

1. **Hook execution overhead**: Minimal - hooks only fire when registered
2. **Data marshaling**: Use existing `HashWithIndifferentAccess` conversion
3. **Logging overhead**: Hooks should log efficiently (batch logging, async logging)
4. **Memory usage**: Hook data is temporary, garbage collected after hook execution

## Technical Decisions

### Decision 1: Two-Level Hook Architecture

**Context**: RAAF DSL agents delegate to core agents, creating timing issues.

**Decision**: Maintain core hooks unchanged, add new DSL-level hooks that fire during DSL processing.

**Rationale**:
- Preserves backward compatibility
- Clear separation of concerns (core = raw AI output, DSL = transformed data)
- Enables future enhancements without breaking changes

### Decision 2: Same Registration API

**Context**: Could create different API for DSL hooks.

**Decision**: Use identical `on_hook_name do ... end` syntax for DSL hooks.

**Rationale**:
- Familiar developer experience
- Reduces learning curve
- Consistent with existing RAAF patterns

### Decision 3: HashWithIndifferentAccess for Hook Data

**Context**: Could use plain hashes or structured objects.

**Decision**: All hook data uses `HashWithIndifferentAccess`.

**Rationale**:
- Consistent with RAAF's existing pattern
- Eliminates symbol/string key confusion
- Flexible for future enhancements

## Validation Requirements

### Schema Validation

- DSL hooks must be valid proc objects
- Hook names must match `HOOK_TYPES` constant
- Hook data must be `HashWithIndifferentAccess` or convertible

### Runtime Validation

- Hooks execute in registration order
- Hooks receive correct data structure
- Hook errors don't crash agent execution (log and continue)

## Documentation Requirements

1. **CLAUDE.md Updates**:
   - Add "Core vs DSL Hooks" section
   - Explain when each hook fires
   - Provide usage examples for each hook

2. **API Documentation**:
   - Document all hook types with YARD tags
   - Provide data structure examples
   - Explain execution order

3. **Migration Guide**:
   - When to use core vs DSL hooks
   - How to access transformed data
   - Common patterns and anti-patterns

# Spec Tasks

These are the tasks to be completed for the spec detailed in @.agent-os/specs/2025-10-09-dsl-level-hooks/spec.md

> Created: 2025-10-09
> Status: In Progress - **Tier 1 COMPLETE** ✅ | Tier 2 Partial (Circuit Breaker Hooks Pending)
> Last Updated: 2025-10-09

## Recent Progress (2025-10-09)

**✅ Completed:**
- Fixed anonymous class handling in prompt inference (added nil checks)
- Fixed hook execution context (changed from `hook.call` to `instance_exec`)
- Added 10 DSL hook methods to Agent class
- Updated HOOK_TYPES constant in Agent class
- Created comprehensive test suite (15 tests, all passing)
- **All Tier 1 COMPLETE** (on_context_built, on_validation_failed, on_result_ready)
- All Tier 2 tests passing (on_prompt_generated, on_tokens_counted)

**📝 Key Implementation Details:**
- Used `instance_exec` in `fire_dsl_hook()` to execute hook blocks in agent's context
- Added nil guards in `infer_prompt_class_name()` and `try_alternative_prompt_conventions()`
- Tests use direct `fire_dsl_hook()` calls to verify hook functionality
- Error handling test confirms hooks don't crash agent execution
- **on_validation_failed hook fires in error handling for SchemaError, ValidationError, and context validation errors**
- Hook receives error message, error_type (schema_validation, data_validation, or context_validation), field info when available

## Tasks

- [x] 1. Implement Tier 1 Essential DSL Hooks Infrastructure ✅ **COMPLETE**
  - [x] 1.1 Write tests for `on_context_built` hook registration and execution
  - [x] 1.2 Add `on_context_built`, `on_validation_failed`, `on_result_ready` to `HOOK_TYPES` constant in `dsl/lib/raaf/dsl/hooks/run_hooks.rb`
  - [x] 1.3 Implement `fire_dsl_hook()` helper method in `dsl/lib/raaf/dsl/agent.rb` (with instance_exec for proper context)
  - [x] 1.4 Add `on_context_built` hook execution point in `execute()` method after `resolve_run_context()`
  - [x] 1.5 Write tests for `on_validation_failed` hook with schema validation failures
  - [x] 1.6 Add `on_validation_failed` hook execution point in error handling when validation fails (handles SchemaError, ValidationError, context validation)
  - [x] 1.7 Write tests for `on_result_ready` hook with transformed data access
  - [x] 1.8 Add `on_result_ready` hook execution point at end of `process_raaf_result()` method
  - [x] 1.9 Verify all Tier 1 tests pass (15 tests passing)

- [x] 2. Implement Tier 2 High-Value Development Hooks
  - [x] 2.1 Write tests for `on_prompt_generated` hook with system and user prompts
  - [x] 2.2 Add `on_prompt_generated` hook execution point in `execute()` after `build_user_prompt_with_context()`
  - [x] 2.3 Write tests for `on_tokens_counted` hook with usage data and cost calculation
  - [x] 2.4 Implement cost calculation helper method for different models
  - [x] 2.5 Add `on_tokens_counted` hook execution point in `execute()` after AI response
  - [ ] 2.6 Write tests for circuit breaker hooks (if circuit breaker pattern exists)
  - [ ] 2.7 Implement `on_circuit_breaker_open` and `on_circuit_breaker_closed` hooks (if circuit breaker exists)
  - [x] 2.8 Verify all Tier 2 tests pass (on_prompt_generated and on_tokens_counted passing)

- [ ] 3. Implement Tier 3 Specialized Operations Hooks
  - [ ] 3.1 Write tests for `on_retry_attempt` hook with retry context
  - [ ] 3.2 Implement retry wrapper with `on_retry_attempt` hook execution
  - [ ] 3.3 Write tests for `on_execution_slow` hook with timing thresholds
  - [ ] 3.4 Add execution timing logic with `on_execution_slow` hook in `execute()` method
  - [ ] 3.5 Write tests for `on_pipeline_stage_complete` hook (if pipeline tracking exists)
  - [ ] 3.6 Implement pipeline stage tracking with hook execution
  - [ ] 3.7 Verify all Tier 3 tests pass

- [ ] 4. Integration Testing with Real Transformations
  - [ ] 4.1 Write integration test for complete agent lifecycle with all hooks firing
  - [ ] 4.2 Write integration test verifying hook execution order (context → prompts → tokens → result)
  - [ ] 4.3 Write integration test confirming transformed data in `on_result_ready` vs raw data in `on_agent_end`
  - [ ] 4.4 Write backward compatibility tests for legacy agents without DSL hooks
  - [ ] 4.5 Write hybrid agent tests using both core and DSL hooks simultaneously
  - [ ] 4.6 Verify all integration tests pass

- [ ] 5. Error Handling and Edge Cases
  - [ ] 5.1 Write tests for hook errors (exceptions in hook blocks)
  - [ ] 5.2 Implement robust error handling in `fire_dsl_hook()` - log errors but don't crash agent
  - [ ] 5.3 Write tests for validation failures with multiple errors
  - [ ] 5.4 Write tests for missing token usage data (providers that don't return usage)
  - [ ] 5.5 Write tests for hooks with nil/empty data
  - [ ] 5.6 Verify all error handling tests pass

- [ ] 6. Documentation and Examples
  - [ ] 6.1 Update `dsl/CLAUDE.md` with "Core vs DSL Hooks" section
  - [ ] 6.2 Document execution order and data structure for each hook type
  - [ ] 6.3 Add usage examples for Tier 1 hooks (context, validation, result)
  - [ ] 6.4 Add usage examples for Tier 2 hooks (prompts, tokens, circuit breaker)
  - [ ] 6.5 Add usage examples for Tier 3 hooks (retry, slow execution, pipeline)
  - [ ] 6.6 Create example agents demonstrating each hook type in `dsl/examples/` directory
  - [ ] 6.7 Write migration guide explaining when to use core vs DSL hooks
  - [ ] 6.8 Update YARD documentation for all hook-related methods

- [ ] 7. Performance Optimization and Validation
  - [ ] 7.1 Write performance tests measuring hook execution overhead
  - [ ] 7.2 Optimize `fire_dsl_hook()` to skip execution when no hooks registered
  - [ ] 7.3 Write tests validating HashWithIndifferentAccess usage in all hooks
  - [ ] 7.4 Add schema validation for hook data structures
  - [ ] 7.5 Verify hook data doesn't leak memory (garbage collection tests)
  - [ ] 7.6 Verify all performance and validation tests pass

- [ ] 8. Final Integration and Cleanup
  - [ ] 8.1 Run complete test suite for RAAF DSL gem
  - [ ] 8.2 Fix any failing tests from existing functionality
  - [ ] 8.3 Run RuboCop and fix code style issues
  - [ ] 8.4 Review all code for consistency with RAAF patterns
  - [ ] 8.5 Update CHANGELOG.md with new DSL hooks feature
  - [ ] 8.6 Create pull request with comprehensive description
  - [ ] 8.7 Verify all CI/CD checks pass

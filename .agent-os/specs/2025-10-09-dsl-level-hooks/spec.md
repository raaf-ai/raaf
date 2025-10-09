# Spec Requirements Document

> Spec: DSL-Level Hooks System
> Created: 2025-10-09
> Status: Planning

## Overview

Implement a comprehensive DSL-level hooks system that fires after result transformations complete, providing developers access to transformed data while maintaining backward compatibility with core RAAF hooks that receive raw AI output.

## User Stories

### Story 1: Access Transformed Results in Hooks

As a developer using RAAF DSL agents, I want hooks that fire after `result_transform` completes, so that I can log, monitor, and process fully transformed data with all field mappings and computed fields applied.

**Workflow:**
1. Developer defines DSL agent with `result_transform` block
2. Developer adds `on_result_ready` hook to process transformed data
3. Agent executes → AI returns raw output → Core `on_agent_end` fires → Transformations apply → DSL `on_result_ready` fires
4. Developer receives structured, transformed data in hook for logging/monitoring

**Problem Solved:** Currently, `on_agent_end` hook receives raw AI output before transformations, making it impossible to access the final structured data that application code receives.

### Story 2: Debug Complete Agent Lifecycle

As a RAAF developer debugging agent behavior, I want hooks at every stage of the DSL lifecycle (context building, prompt generation, validation, result transformation), so that I can understand exactly what data flows through the system at each step.

**Workflow:**
1. Developer adds multiple DSL hooks: `on_context_built`, `on_prompt_generated`, `on_validation_failed`, `on_result_ready`
2. Agent executes with debug logging enabled
3. Developer sees complete trace: Context → Prompts → AI execution → Validation → Transformation → Final result
4. Developer identifies exactly where data issues occur

**Problem Solved:** Current hook system only exposes agent start/end, making it difficult to debug complex DSL pipelines with transformations, validations, and context assembly.

### Story 3: Track Costs and Performance by Pipeline Stage

As an AI operations engineer, I want hooks that fire after token counting and before pipeline stages complete, so that I can accurately track costs, performance metrics, and resource usage across multi-agent workflows.

**Workflow:**
1. Engineer implements `on_tokens_counted` hook to log token usage per agent
2. Engineer implements `on_pipeline_stage_complete` to track stage duration
3. Production agents automatically report cost and performance data
4. Engineer analyzes costs by pipeline stage and optimizes expensive agents

**Problem Solved:** Current system lacks visibility into token usage and pipeline performance, making cost optimization difficult.

## Spec Scope

This spec implements a comprehensive DSL-level hooks system organized into three priority tiers:

### Tier 1: Essential DSL Lifecycle Hooks

1. **`on_result_ready`** - Fires after all DSL transformations complete (result_transform, field mappings, computed fields)
2. **`on_validation_failed`** - Fires when schema validation fails with detailed error information
3. **`on_context_built`** - Fires after context assembly before passing to AI provider

### Tier 2: High-Value Development Hooks

4. **`on_prompt_generated`** - Fires after system/user prompts are generated with full prompt text
5. **`on_tokens_counted`** - Fires after token counting with usage and estimated cost data
6. **`on_circuit_breaker_open`** - Fires when circuit breaker opens due to repeated failures
7. **`on_circuit_breaker_closed`** - Fires when circuit breaker closes after recovery

### Tier 3: Specialized Operations Hooks

8. **`on_retry_attempt`** - Fires before each retry attempt with attempt number and backoff delay
9. **`on_execution_slow`** - Fires when execution exceeds configurable threshold
10. **`on_pipeline_stage_complete`** - Fires after each pipeline stage in multi-agent workflows

### Key Features

- **Two-Level Hook Architecture**: Core hooks (raw AI output) + DSL hooks (transformed data)
- **Backward Compatibility**: All existing core hooks remain unchanged
- **Clear Documentation**: Explicit explanation of when each hook fires and what data it receives
- **Flexible Registration**: Same DSL syntax as existing hooks (`on_result_ready { |result| ... }`)
- **Deep Indifferent Access**: All hook data uses `HashWithIndifferentAccess` for flexible key access

## Out of Scope

The following features are explicitly excluded from this spec:

- **Modifying core RAAF hooks** - Core `on_agent_start`, `on_agent_end`, `on_handoff`, `on_tool_start`, `on_tool_end`, `on_error` remain unchanged
- **Streaming-specific hooks** - Streaming lifecycle hooks deferred to separate spec
- **Custom hook registration API** - Only predefined hooks in this spec, custom hooks in future enhancement
- **Hook priority/ordering system** - Hooks fire in natural execution order, no custom ordering
- **Async hook execution** - All hooks execute synchronously in current execution context

## Expected Deliverable

1. **Comprehensive Hook System**: 10 new DSL-level hooks across 3 priority tiers
2. **Documentation**: Updated CLAUDE.md with clear core vs DSL hooks explanation
3. **Test Coverage**: Unit tests for each hook, integration tests with transformations
4. **Usage Examples**: Example agents demonstrating each hook type
5. **Migration Guide**: Clear guidance on when to use core vs DSL hooks

### Browser-Testable Outcomes

1. **Developer can access transformed data in hooks**: Create DSL agent with `result_transform` and `on_result_ready` hook, verify hook receives transformed data
2. **Complete lifecycle visibility**: Add all DSL hooks to agent, execute, verify all hooks fire in correct order with expected data
3. **Backward compatibility**: Existing agents with core hooks continue working unchanged

## Spec Documentation

- **Tasks**: @.agent-os/specs/2025-10-09-dsl-level-hooks/tasks.md - Complete task breakdown with TDD approach
- **Technical Specification**: @.agent-os/specs/2025-10-09-dsl-level-hooks/sub-specs/technical-spec.md - Detailed implementation guide with hook execution points
- **Tests Specification**: @.agent-os/specs/2025-10-09-dsl-level-hooks/sub-specs/tests.md - Comprehensive test coverage requirements

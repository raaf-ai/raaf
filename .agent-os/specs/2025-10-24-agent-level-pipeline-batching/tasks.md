# Task Breakdown: Intelligent Batching with Streaming

## Overview

Unified feature that combines:
1. **Pipeline-level batching** - Process large arrays through agents in batches
2. **Optional state management** - Skip reprocessing, load existing, persist batches
3. **Incremental streaming** - Results available after each batch (or all at end)

Total Tasks: 8 task groups (56+ subtasks)
Assigned roles: architecture-engineer, backend-developer, integration-engineer, testing-engineer, refactoring-engineer

## Task List

### Foundation Layer

#### Task Group 1: Core Batching Classes
**Assigned implementer:** architecture-engineer
**Dependencies:** None

- [ ] 1.0 Complete foundation classes for batching
  - [ ] 1.1 Write tests for BatchingScope class
    - Unit tests for scope initialization
    - Tests for scope validation
    - Tests for scope metadata storage
    - Tests for scope boundary tracking
  - [ ] 1.2 Create BatchingScope class
    - Fields: trigger_agent, scope_agents, terminator_agent, chunk_size, field
    - Methods: valid?, includes_agent?, to_h
    - Implement scope boundary validation
  - [ ] 1.3 Write tests for BatchingScopeManager
    - Tests for scope detection from flow chain
    - Tests for nested scope validation
    - Tests for scope boundary errors
    - Tests for parallel agent handling
  - [ ] 1.4 Create BatchingScopeManager class
    - Method: detect_scopes(flow_chain)
    - Method: validate_scopes(scopes)
    - Method: flatten_flow_chain(chain)
    - Error handling for misconfigured scopes
  - [ ] 1.5 Write tests for BatchProgressContext
    - Tests for immutable context
    - Tests for batch metadata access
    - Tests for context serialization
  - [ ] 1.6 Create BatchProgressContext class
    - Immutable context for batch hooks
    - Batch number, total batches, batch data
    - Structured interface for hook signatures
  - [ ] 1.7 Ensure all foundation tests pass
    - Run all unit tests
    - Verify 100% coverage for new classes
    - Confirm error handling works correctly

**Acceptance Criteria:**
- All tests written in 1.1, 1.3, 1.5 pass
- Classes provide clean interfaces for batching
- Scope detection works with complex flows
- Error messages are clear and helpful

### Agent Configuration Layer

#### Task Group 2: Agent Class Methods
**Assigned implementer:** backend-developer
**Dependencies:** Task Group 1

- [ ] 2.0 Complete agent batching configuration
  - [ ] 2.1 Write tests for agent class methods
    - Tests for triggers_batching method
    - Tests for ends_batching method
    - Tests for batching configuration storage
    - Tests for configuration validation
    - Tests for hook registration (on_batch_start, on_batch_complete)
  - [ ] 2.2 Implement triggers_batching class method
    - Add to RAAF::DSL::Agent class
    - Parameters: chunk_size, over (field name)
    - Store configuration in _batching_config
    - Validate configuration at definition time
  - [ ] 2.3 Implement ends_batching class method
    - Add to RAAF::DSL::Agent class
    - Mark agent as batching terminator
    - Store in _batching_config
  - [ ] 2.4 Implement batch hook methods
    - on_batch_start class method
    - on_batch_complete class method
    - on_batch_error class method (optional)
    - Store hooks in configuration
  - [ ] 2.5 Add introspection methods
    - batching_trigger? predicate
    - batching_terminator? predicate
    - batching_config accessor
    - Thread-safe using Concurrent::Hash
  - [ ] 2.6 Ensure all agent configuration tests pass
    - Run tests from 2.1
    - Verify configuration persistence
    - Confirm thread-safety

**Acceptance Criteria:**
- All tests written in 2.1 pass
- Agent classes can declare batching behavior
- Configuration is thread-safe
- Hooks are properly registered

### Execution Layer

#### Task Group 3: Pipeline Batch Executor
**Assigned implementer:** backend-developer
**Dependencies:** Task Groups 1, 2

- [ ] 3.0 Complete batch executor implementation
  - [ ] 3.1 Write tests for PipelineBatchExecutor
    - Tests for batch splitting logic
    - Tests for sequential batch execution
    - Tests for result merging (arrays, objects, primitives)
    - Tests for context preservation across batches
    - Tests for hook execution timing
    - Tests for error handling per batch
  - [ ] 3.2 Create PipelineBatchExecutor class
    - Inherits from appropriate base (WrapperDSL)
    - Include RAAF::Logger for debugging
    - Initialize with scope configuration
  - [ ] 3.3 Implement batch splitting logic
    - Extract array field from context
    - Split into chunks of configured size
    - Handle edge cases (empty, single item, exact size)
    - Auto-detect field if not specified
  - [ ] 3.4 Implement batch execution flow
    - Execute each batch through scope agents
    - Maintain batch context isolation
    - Call batch hooks at appropriate times
    - Accumulate results from each batch
  - [ ] 3.5 Implement result merging
    - Arrays: concatenate
    - Objects: deep merge with conflict resolution
    - Primitives: last wins with warning
    - Maintain result structure consistency
  - [ ] 3.6 Implement error recovery
    - Capture failed batch information
    - Return partial results from successful batches
    - Clear error messages with batch number
    - Support for retry logic
  - [ ] 3.7 Ensure all executor tests pass
    - Run tests from 3.1
    - Verify batch execution order
    - Confirm result correctness

**Acceptance Criteria:**
- All tests written in 3.1 pass
- Batches execute sequentially through scope
- Results merge correctly across batches
- Errors don't lose successful batch results

### Integration Layer

#### Task Group 4: Pipeline Integration
**Assigned implementer:** integration-engineer
**Dependencies:** Task Groups 1, 2, 3

- [ ] 4.0 Complete pipeline integration
  - [ ] 4.1 Write integration tests
    - Tests for pipeline with batching agents
    - Tests for scope detection during pipeline init
    - Tests for automatic batch wrapping
    - Tests for mixed batching and non-batching agents
    - Tests for pipeline operators (>>, |) with batching
  - [ ] 4.2 Update Pipeline class initialization
    - Detect batching scopes in flow
    - Validate scope configuration
    - Create execution plan with batching
    - Maintain backward compatibility
  - [ ] 4.3 Update Pipeline execute method
    - Check for batching scopes
    - Wrap scope agents in PipelineBatchExecutor
    - Execute batching and non-batching agents correctly
    - Preserve existing execution semantics
  - [ ] 4.4 Integrate with existing wrappers
    - Ensure compatibility with BatchedAgent (in_chunks_of)
    - Work with ChainedAgent wrapper
    - Support parallel operators with batching
    - Test wrapper composition
  - [ ] 4.5 Add pipeline-level configuration
    - Optional batch error handling strategy
    - Optional batch progress reporter
    - Configuration inheritance from agents
  - [ ] 4.6 Ensure all integration tests pass
    - Run tests from 4.1
    - Verify end-to-end pipeline execution
    - Confirm backward compatibility

**Acceptance Criteria:**
- All tests written in 4.1 pass
- Pipelines automatically detect and use batching
- Existing pipelines work unchanged
- All operators work with batching

### Observability Layer

#### Task Group 5: Progress Hooks and Tracing
**Assigned implementer:** backend-developer
**Dependencies:** Task Groups 1-4

- [ ] 5.0 Complete hooks and tracing integration
  - [ ] 5.1 Write tests for progress hooks
    - Tests for on_batch_start execution
    - Tests for on_batch_complete execution
    - Tests for on_batch_error execution
    - Tests for hook parameters (batch_num, total, context)
    - Tests for hook context modifications
  - [ ] 5.2 Implement hook execution in executor
    - Call on_batch_start before each batch
    - Call on_batch_complete after each batch
    - Call on_batch_error on batch failure
    - Pass correct parameters to hooks
    - Allow context modifications (with care)
  - [ ] 5.3 Write tests for tracing integration
    - Tests for batch span creation
    - Tests for span hierarchy
    - Tests for batch metadata in spans
    - Tests for error spans
  - [ ] 5.4 Integrate with RAAF tracing
    - Create batch spans as children of pipeline span
    - Include batch number and size in span metadata
    - Track batch duration
    - Record batch errors in spans
  - [ ] 5.5 Add logging for debugging
    - Log batch start/end
    - Log batch sizes and counts
    - Log merge operations
    - Use appropriate log levels
  - [ ] 5.6 Ensure all observability tests pass
    - Run tests from 5.1 and 5.3
    - Verify hooks execute correctly
    - Confirm tracing integration works

**Acceptance Criteria:**
- All tests written in 5.1 and 5.3 pass
- Progress hooks fire at correct times
- Tracing shows batch execution hierarchy
- Debugging is easy with clear logs

### Testing & Quality

#### Task Group 6: Comprehensive Testing
**Assigned implementer:** testing-engineer
**Dependencies:** Task Groups 1-5

- [x] 6.0 Complete comprehensive test coverage
  - [x] 6.1 Write edge case tests
    - Empty array (0 items)
    - Single item array
    - Exact batch size match
    - One less/more than batch size
    - Very large arrays (10,000+ items)
  - [x] 6.2 Write configuration validation tests
    - Missing ends_batching
    - Multiple triggers_batching (nested)
    - Invalid chunk sizes (0, negative, non-integer)
    - Invalid field names
    - Multiple array fields without 'over'
  - [x] 6.3 Write performance tests
    - Measure batching overhead (target < 5ms)
    - Memory usage scaling with batch size
    - Compare batched vs non-batched execution
    - Test with different batch sizes (10, 100, 1000)
  - [x] 6.4 Write backward compatibility tests
    - Existing pipelines work unchanged
    - in_chunks_of agent batching still works
    - No performance regression
    - All operators work as before
  - [x] 6.5 Write error scenario tests
    - Batch failure at different points
    - Multiple batch failures
    - Hook errors don't break execution
    - Retry logic works correctly
  - [x] 6.6 Create integration test suite
    - End-to-end prospect discovery pipeline
    - Complex pipelines with parallel agents
    - Pipelines with multiple array fields
    - Real-world use case tests
  - [x] 6.7 Ensure all tests pass
    - 100% test coverage for new code
    - All edge cases handled
    - Performance targets met
    - No regressions

**Acceptance Criteria:**
- All tests written in 6.1-6.6 pass
- 100% test coverage achieved
- Performance targets met (< 5ms overhead)
- No backward compatibility issues

### Documentation

#### Task Group 7: Documentation and Examples
**Assigned implementer:** backend-developer
**Dependencies:** Task Groups 1-6

- [ ] 7.0 Complete documentation
  - [ ] 7.1 Update RAAF Pipeline DSL Guide
    - Add "Pipeline Batching" section
    - Explain difference from agent batching
    - Include configuration examples
    - Document best practices
  - [ ] 7.2 Create API documentation
    - Document triggers_batching method
    - Document ends_batching method
    - Document batch hook signatures
    - Document PipelineBatchExecutor class
  - [ ] 7.3 Write migration guide
    - When to use pipeline vs agent batching
    - How to choose batch size
    - Performance tuning tips
    - Common pitfalls and solutions
  - [ ] 7.4 Create example implementations
    - Basic batching example
    - Progress tracking example
    - Error handling example
    - Complex pipeline with batching
    - ProspectPipeline real-world example
  - [ ] 7.5 Add inline code documentation
    - Document complex algorithms
    - Add YARD documentation for public methods
    - Include usage examples in comments
  - [ ] 7.6 Create README for spec
    - Quick start guide
    - Link to detailed documentation
    - Common use cases

**Acceptance Criteria:**
- Documentation is clear and comprehensive
- Examples are working and tested
- API documentation is complete
- Migration path is clear

### Polish & Optimization

#### Task Group 8: Final Polish and Optimization
**Assigned implementer:** refactoring-engineer
**Dependencies:** Task Groups 1-7

- [ ] 8.0 Complete optimization and polish
  - [ ] 8.1 Performance optimization
    - Profile batch execution
    - Optimize memory usage
    - Reduce object allocations
    - Verify < 5ms overhead target
  - [ ] 8.2 Code refactoring
    - Remove code duplication
    - Improve method naming
    - Extract complex logic to methods
    - Ensure consistent code style
  - [ ] 8.3 Error message improvements
    - Make error messages more helpful
    - Include troubleshooting hints
    - Add context to errors
    - Standardize error format
  - [ ] 8.4 Add feature flags (optional)
    - Allow disabling batching globally
    - Debug mode for verbose logging
    - Performance monitoring toggle
  - [ ] 8.5 Final integration testing
    - Test with ProspectPipeline
    - Test with other production pipelines
    - Stress test with large datasets
    - Verify production readiness
  - [ ] 8.6 Create release checklist
    - All tests pass
    - Documentation complete
    - Performance targets met
    - Backward compatibility verified
    - Ready for production use

**Acceptance Criteria:**
- Performance meets all targets
- Code is clean and maintainable
- Error messages are helpful
- Feature is production-ready

## Execution Order

Recommended implementation sequence:
1. Foundation Layer (Task Group 1) - Core classes needed by all other tasks
2. Agent Configuration Layer (Task Group 2) - Agent DSL methods
3. Execution Layer (Task Group 3) - Batch execution logic
4. Integration Layer (Task Group 4) - Pipeline integration
5. Observability Layer (Task Group 5) - Hooks and tracing
6. Testing & Quality (Task Group 6) - Comprehensive testing
7. Documentation (Task Group 7) - Guides and examples
8. Polish & Optimization (Task Group 8) - Final improvements

## Notes

- Each task group follows TDD approach with tests written first
- Dependencies are clearly marked to ensure proper execution order
- All implementers are from available roles in implementers.yml
- Tasks align with spec requirements and success criteria
- Focus on incremental delivery of working functionality
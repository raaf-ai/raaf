# Task Breakdown: Evaluator Definition DSL Module

## Overview
Total Tasks: 5 major task groups with 38 subtasks
Estimated Duration: 5 days
Architecture: Module-based DSL with automatic caching and configuration building

## Task List

### Task Group 1: Core Module Implementation
**Dependencies:** None
**Estimated Duration:** Day 1 (8 hours)

- [ ] 1.0 Complete core EvaluatorDefinition module
  - [ ] 1.1 Write 2-8 focused tests for module inclusion behavior
    - Test `self.included` hook extends ClassMethods
    - Test `@_evaluator_config` initialization with correct structure
    - Test all DSL methods are available after inclusion
    - Limit to critical module setup behaviors only
  - [ ] 1.2 Create module file structure
    - Create `vendor/local_gems/raaf/eval/lib/raaf/eval/dsl/evaluator_definition.rb`
    - Define module namespace: `RAAF::Eval::DSL::EvaluatorDefinition`
    - Add file header with documentation
  - [ ] 1.3 Implement `self.included` hook
    - Extend base class with ClassMethods module
    - Initialize `@_evaluator_config` class variable with hash structure
    - Structure: `{ selections: [], field_evaluations: {}, progress_callback: nil, history_options: {} }`
  - [ ] 1.4 Implement DSL methods in ClassMethods
    - `select(path, as:)` - append to selections array
    - `evaluate_field(name, &block)` - store block in field_evaluations hash
    - `on_progress(&block)` - store progress callback
    - `history(**options)` - merge options into history_options hash
  - [ ] 1.5 Implement automatic methods
    - `evaluator` - return cached or build new evaluator
    - `reset_evaluator!` - clear cached evaluator
    - Add `@evaluator` class variable for caching
  - [ ] 1.6 Implement private `build_evaluator_from_config` method
    - Call `RAAF::Eval.define` with configuration block
    - Apply selections in order from array
    - Apply field evaluations from hash
    - Apply progress callback if present
    - Apply history options if any
  - [ ] 1.7 Ensure module tests pass
    - Run ONLY the 2-8 tests written in 1.1
    - Verify module inclusion behavior
    - Do NOT run entire test suite at this stage

**Acceptance Criteria:**
- The 2-8 tests written in 1.1 pass
- Module can be included in test classes
- All DSL methods available at class level
- Configuration stored correctly
- Evaluator built from configuration

---

### Task Group 2: DSL Method Implementation
**Dependencies:** Task Group 1 (Core Module)
**Estimated Duration:** Day 1 (continued, 4 hours)

- [ ] 2.0 Complete DSL method implementations
  - [ ] 2.1 Write 2-8 focused tests for DSL methods
    - Test `select` accumulation behavior
    - Test `evaluate_field` storage and replacement
    - Test `on_progress` callback storage
    - Test `history` options merging
    - Limit to critical DSL method behaviors only
  - [ ] 2.2 Implement and verify `select(path, as:)`
    - Append hash to selections array: `{ path: path, as: as }`
    - Verify multiple calls accumulate
    - Verify order preservation
  - [ ] 2.3 Implement and verify `evaluate_field(name, &block)`
    - Store block in field_evaluations hash
    - Verify block is callable
    - Verify replacement behavior for duplicate fields
  - [ ] 2.4 Implement and verify `on_progress(&block)`
    - Store block in progress_callback
    - Verify replacement behavior for multiple calls
    - Handle nil block gracefully
  - [ ] 2.5 Implement and verify `history(**options)`
    - Merge options into history_options hash
    - Verify multiple calls merge (not replace)
    - Support all options: baseline, last_n, auto_save, retention_days, retention_count
  - [ ] 2.6 Ensure DSL method tests pass
    - Run ONLY the 2-8 tests written in 2.1
    - Verify all DSL methods work correctly
    - Do NOT run entire test suite at this stage

**Acceptance Criteria:**
- The 2-8 tests written in 2.1 pass
- All DSL methods store configuration correctly
- Multiple calls accumulate/merge as specified
- Configuration accessible via `@_evaluator_config`

---

### Task Group 3: Caching and Builder Implementation
**Dependencies:** Task Group 1, 2
**Estimated Duration:** Day 2 (6 hours)

- [ ] 3.0 Complete caching and builder logic
  - [ ] 3.1 Write 2-8 focused tests for caching behavior
    - Test `evaluator` caching (same object_id on repeat calls)
    - Test `reset_evaluator!` clears cache
    - Test evaluator rebuilds after reset
    - Test configuration building from DSL settings
    - Limit to critical caching behaviors only
  - [ ] 3.2 Implement `evaluator` method with caching
    - Check if `@evaluator` is already set
    - If set, return cached instance
    - If not set, call `build_evaluator_from_config` and cache result
    - Ensure thread-safe caching (class-level instance variable)
  - [ ] 3.3 Implement `reset_evaluator!` method
    - Set `@evaluator = nil`
    - Return nil for chaining
    - Verify next `evaluator` call rebuilds
  - [ ] 3.4 Implement `build_evaluator_from_config` private method
    - Create `RAAF::Eval.define` block
    - Iterate selections array and call `select` for each
    - Iterate field_evaluations hash and call `evaluate_field` for each
    - Apply progress_callback if not nil
    - Apply history_options if hash not empty
    - Return built evaluator instance
  - [ ] 3.5 Add configuration validation (optional)
    - Validate selections have required keys (:path, :as)
    - Validate field_evaluations have callable blocks
    - Provide clear error messages for invalid config
  - [ ] 3.6 Ensure caching and builder tests pass
    - Run ONLY the 2-8 tests written in 3.1
    - Verify caching works correctly
    - Verify builder constructs valid evaluator
    - Do NOT run entire test suite at this stage

**Acceptance Criteria:**
- The 2-8 tests written in 3.1 pass
- Evaluator caching works (same instance on repeat calls)
- Reset clears cache successfully
- Builder constructs valid RAAF::Eval evaluator
- Configuration building handles all DSL options

---

### Task Group 4: Integration and Migration
**Dependencies:** Task Group 1, 2, 3
**Estimated Duration:** Day 2 (continued, 4 hours) + Day 3 (4 hours)

- [ ] 4.0 Complete integration with RAAF ecosystem
  - [ ] 4.1 Write 2-8 focused tests for integration
    - Test autoload loads module correctly
    - Test integration with RAAF::Eval.define API
    - Test end-to-end evaluation with DSL-defined evaluator
    - Test migration pattern works (before/after comparison)
    - Limit to critical integration points only
  - [ ] 4.2 Update autoload configuration
    - Edit `vendor/local_gems/raaf/eval/lib/raaf/eval/dsl.rb`
    - Add: `autoload :EvaluatorDefinition, 'raaf/eval/dsl/evaluator_definition'`
    - Verify module can be required via `RAAF::Eval::DSL::EvaluatorDefinition`
  - [ ] 4.3 Find and prepare Scoring class for migration
    - Search codebase for Scoring evaluator class
    - Document current implementation (before state)
    - Identify `class << self` block for removal
  - [ ] 4.4 Migrate Scoring class to new DSL pattern
    - Add `include RAAF::Eval::DSL::EvaluatorDefinition`
    - Move DSL calls outside `class << self` block to class level
    - Remove entire `class << self` block
    - Remove manual `@evaluator ||=` caching
    - Remove manual `reset_evaluator!` implementation
  - [ ] 4.5 Verify migrated Scoring class works
    - Run existing Scoring tests (if any)
    - Verify `Scoring.evaluator` returns valid evaluator
    - Verify `Scoring.reset_evaluator!` works
    - Verify evaluation results match previous behavior
  - [ ] 4.6 Create migration example file
    - Document before/after code side-by-side
    - Create example class showing migration steps
    - Provide migration checklist
  - [ ] 4.7 Ensure integration tests pass
    - Run ONLY the 2-8 tests written in 4.1
    - Verify autoload works correctly
    - Verify migration pattern is valid
    - Do NOT run entire test suite at this stage

**Acceptance Criteria:**
- The 2-8 tests written in 4.1 pass
- Autoload configuration loads module correctly
- Scoring class successfully migrated to new DSL
- Migrated class produces same evaluation results
- Migration example documented

---

### Task Group 5: Testing, Documentation, and Verification
**Dependencies:** Task Group 1, 2, 3, 4
**Estimated Duration:** Day 3 (continued, 4 hours) + Day 4 (8 hours) + Day 5 (8 hours)

- [ ] 5.0 Complete comprehensive testing and documentation
  - [ ] 5.1 Review existing tests from Task Groups 1-4
    - Review tests written in 1.1 (module tests)
    - Review tests written in 2.1 (DSL method tests)
    - Review tests written in 3.1 (caching tests)
    - Review tests written in 4.1 (integration tests)
    - Total existing tests: approximately 8-32 tests
  - [ ] 5.2 Analyze test coverage gaps for THIS feature only
    - Identify critical edge cases not covered
    - Focus on error handling scenarios
    - Check thread safety if applicable
    - Focus ONLY on gaps in EvaluatorDefinition module
    - Do NOT assess entire RAAF Eval test coverage
  - [ ] 5.3 Write up to 10 additional strategic tests maximum
    - Add tests for error conditions (invalid config, missing blocks)
    - Add tests for edge cases (empty config, nil values)
    - Add tests for complex scenarios (multiple fields, all options)
    - Do NOT write comprehensive coverage for all permutations
    - Focus on high-risk edge cases only
  - [ ] 5.4 Update README.md with DSL pattern documentation
    - Add new section: "Evaluator Definition DSL"
    - Document all DSL methods with examples
    - Add benefits section (code reduction, readability)
    - Add API reference table
  - [ ] 5.5 Create comprehensive migration guide
    - Before/after code comparison
    - Step-by-step migration process
    - Common pitfalls and solutions
    - Migration checklist
  - [ ] 5.6 Update RAAF_EVAL.md (if exists)
    - Add DSL pattern to main documentation
    - Update examples to use new pattern
    - Add migration guide reference
  - [ ] 5.7 Update eval/CLAUDE.md (if exists)
    - Add DSL pattern to developer guidelines
    - Document module architecture
    - Add testing guidance
  - [ ] 5.8 Create example evaluator files
    - Simple example (minimal configuration)
    - Complex example (all DSL features)
    - Migration example (before/after)
  - [ ] 5.9 Code review and polish
    - Review module implementation for clarity
    - Verify Ruby style compliance
    - Check error messages are helpful
    - Verify thread safety if needed
  - [ ] 5.10 Run feature-specific tests only
    - Run ONLY tests related to EvaluatorDefinition module
    - Expected total: approximately 18-42 tests maximum
    - Verify 100% test coverage for module
    - Do NOT run entire RAAF test suite
  - [ ] 5.11 Performance verification
    - Benchmark caching speedup
    - Verify configuration building is fast (<1ms)
    - Ensure no performance regression vs old pattern
  - [ ] 5.12 Final integration verification
    - Test with at least 2 real evaluator classes
    - Verify backward compatibility (usage unchanged)
    - Verify all RAAF Eval features still work
    - Measure code reduction achieved (target: 70%)

**Acceptance Criteria:**
- All feature-specific tests pass (approximately 18-42 tests total)
- 100% test coverage for EvaluatorDefinition module
- No more than 10 additional tests added when filling gaps
- README.md updated with complete DSL documentation
- Migration guide provides clear before/after examples
- At least 2 evaluator classes successfully migrated
- Performance benchmarks show no regression
- Code reduction target achieved (70%+ boilerplate elimination)
- All documentation clear and complete

---

## Execution Order

Recommended implementation sequence:
1. **Task Group 1**: Core Module Implementation (Day 1 morning)
2. **Task Group 2**: DSL Method Implementation (Day 1 afternoon)
3. **Task Group 3**: Caching and Builder Implementation (Day 2 morning)
4. **Task Group 4**: Integration and Migration (Day 2 afternoon + Day 3 morning)
5. **Task Group 5**: Testing, Documentation, and Verification (Day 3 afternoon + Day 4 + Day 5)

## Key Implementation Notes

### Module Architecture
- Uses `self.included` hook for automatic setup
- Extends base class with ClassMethods module
- Stores configuration in `@_evaluator_config` class variable
- Provides automatic caching via `@evaluator` class variable

### Configuration Storage Format
```ruby
@_evaluator_config = {
  selections: [
    { path: 'field.path', as: :alias },
    # ... more selections
  ],
  field_evaluations: {
    field_name: #<Proc>,
    # ... more field evaluations
  },
  progress_callback: #<Proc> or nil,
  history_options: {
    baseline: true,
    last_n: 10,
    # ... more options
  }
}
```

### DSL Method Behaviors
- `select`: Accumulates (array append)
- `evaluate_field`: Replaces for same field (hash assignment)
- `on_progress`: Replaces previous callback
- `history`: Merges options (hash merge)

### Testing Strategy
- TDD approach: Write tests alongside or before implementation
- Focus on 2-8 tests per task group during development
- Maximum 10 additional tests for gap filling in final phase
- Target: 18-42 total tests for complete module coverage
- Run feature-specific tests only (not entire suite)

### Documentation Requirements
- Migration guide with before/after examples
- API reference for all DSL methods
- Benefits explanation (code reduction, readability)
- Example evaluator files (simple, complex, migration)

### Success Metrics
- 70% code reduction (eliminate boilerplate)
- 100% test coverage for module
- Backward compatible (usage unchanged)
- All tests pass
- Performance: No regression, caching provides speedup

---

**Implementation Ready**: All task groups defined with clear dependencies, acceptance criteria, and verification steps.

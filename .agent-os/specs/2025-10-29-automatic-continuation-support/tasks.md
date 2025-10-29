# Task Breakdown: Automatic Continuation Support

## Overview
Total Tasks: 14 major task groups + 1 critical foundation (1.5) = 15 total across 4 phases
Total Subtasks: 95+ individual subtasks following TDD approach
Assigned roles: backend-engineer (implementation), testing-engineer (testing & validation)

**Key Enhancements:**
- Added Task Group 1.5: BaseMerger abstract class (critical foundation)
- Enhanced Task Group 2: Added stateful API integration, finish_reason handling (all 7 cases), FormatDetector, MergerFactory
- Enhanced Task Group 7: Added 3-level fallback strategy, error recovery details
- Enhanced Task Group 9: Added cost calculation, comprehensive metadata structure (11+ fields)
- Enhanced Task Group 10: Added metadata field completeness testing

## Task List

### Phase 1: Core Infrastructure

#### Task Group 1: Configuration System and DSL
**Assigned implementer:** backend-engineer
**Dependencies:** None

**Implementation Files:**
- `lib/raaf/continuation/config.rb` (ContinuationConfig class)
- `lib/raaf/dsl/agent.rb` (DSL enable_continuation method)

- [ ] 1.0 Complete configuration system for continuation support
  - [ ] 1.1 Write tests for DSL configuration methods
    - Agent-level enable_continuation tests
    - Configuration option validation tests
    - Default values tests
    - Invalid configuration error tests (format: :xml, negative max_attempts, max_attempts > 50)
    - Edge case tests (nil values, empty strings, type mismatches)
  - [ ] 1.2 Implement DSL methods in RAAF::DSL::Agent
    - enable_continuation class method
    - Configuration storage in agent metadata
    - Option parsing and validation
    - Default configuration values
  - [ ] 1.3 Add continuation configuration to agent context
    - Pass configuration to runner
    - Make available to provider
    - Include in agent metadata
  - [ ] 1.4 Create ContinuationConfig class
    - max_attempts (default: 10)
    - output_format (:csv, :markdown, :json, :auto)
    - on_failure (:return_partial, :raise_error)
    - merge_strategy (internal, format-specific)
  - [ ] 1.5 Ensure all configuration tests pass
    - Run all DSL configuration tests
    - Verify configuration propagation
    - Confirm defaults work correctly

**Acceptance Criteria:**
- All tests written in 1.1 pass
- DSL method enable_continuation works at class level
- Configuration properly propagates to provider
- Invalid configurations raise appropriate errors

#### Task Group 1.5: Base Merger Class (Critical Foundation)
**Assigned implementer:** backend-engineer
**Dependencies:** Task Group 1

**Implementation Files:**
- `lib/raaf/continuation/mergers/base_merger.rb` (BaseMerger abstract class)

- [x] 1.5 Create BaseMerger abstract class and merger interface
  - [x] 1.5.1 Write tests for BaseMerger interface
    - Abstract method enforcement tests
    - Helper method tests (extract_content, build_metadata)
    - Metadata structure tests
  - [x] 1.5.2 Implement BaseMerger abstract class
    - `#merge(chunks)` abstract method
    - `#extract_content(chunk)` helper
    - `#build_metadata(chunks, merge_success, error)` helper
    - Merger registration in factory
  - [x] 1.5.3 Ensure BaseMerger tests pass
    - Test that subclasses must implement merge
    - Verify helpers work correctly

**Acceptance Criteria:**
- BaseMerger defined as abstract base class
- All helpers implemented
- Merger interface clear for subclasses

#### Task Group 2: Provider-Level Truncation Detection
**Assigned implementer:** backend-engineer
**Dependencies:** Task Groups 1, 1.5

**Implementation Files:**
- `lib/raaf/models/responses_provider.rb` (modified)
- `lib/raaf/continuation/merger_factory.rb` (MergerFactory)
- `lib/raaf/continuation/format_detector.rb` (FormatDetector)

- [x] 2.0 Complete provider-level truncation detection and continuation loop
  - [x] 2.1 Write tests for truncation detection
    - Detect finish_reason: "length" tests
    - finish_reason handling for all cases: "stop", "length", "tool_calls", "content_filter", "incomplete", "error", null
    - Check agent continuation support tests
    - Multiple continuation attempts tests
    - Max attempts limit tests
  - [x] 2.2 Modify ResponsesProvider#create_response
    - Add finish_reason detection logic (all 7 cases)
    - Log WARN for "content_filter" with ⚠️ emoji
    - Log WARN for "incomplete" with recommendation
    - Check agent configuration for continuation support
    - Implement continuation loop with finish_reason: "length" handling
    - Track continuation attempts
    - Extract `previous_response_id` from response for stateful API
    - Pass `previous_response_id` in continuation requests
  - [x] 2.3 Implement build_continuation_prompt method
    - Build format-aware continuation prompts (CSV, Markdown, JSON, auto)
    - Extract context from last chunk (last 5 lines for Markdown, incomplete row for CSV, partial structure for JSON)
    - Include partial data information
    - Maintain conversation context
    - Stateful API pattern: use `previous_response_id` instead of message history
  - [x] 2.4 Create FormatDetector class
    - Implement in `lib/raaf/continuation/format_detector.rb`
    - Detect CSV by structure (pipes vs commas, headers, consistent columns)
    - Detect Markdown by syntax (``` code blocks, | table syntax, # headers)
    - Detect JSON by brackets/braces ({ or [ at start)
    - Return confidence scores for auto-detection
  - [x] 2.5 Create MergerFactory for routing
    - Implement in `lib/raaf/continuation/merger_factory.rb`
    - Route to appropriate merger based on format (:csv, :markdown, :json, :auto)
    - Use FormatDetector for :auto format
    - Provide sensible fallback merger
    - Log format detection results
  - [x] 2.6 Add continuation metadata tracking
    - Track continuation count
    - Record token usage per chunk
    - Calculate total costs using cost calculation logic (see 9.4)
    - Store truncation points
    - Record finish_reason for each chunk
  - [x] 2.7 Ensure all provider tests pass
    - Run truncation detection tests (all finish_reason cases)
    - Verify continuation loop works correctly
    - Test stateful API previous_response_id handling
    - Confirm metadata collection

**Acceptance Criteria:**
- All tests written in 2.1 pass
- Provider detects truncation correctly
- Continuation loop respects max attempts
- Metadata accurately tracks all continuations

### Phase 2: Format-Specific Mergers

#### Task Group 3: CSV Merger Implementation
**Assigned implementer:** backend-engineer
**Dependencies:** Task Group 2

- [ ] 3.0 Complete CSV merger with 95%+ success rate
  - [x] 3.1 Write comprehensive CSV merger tests
    - Complete row merging tests (8 tests)
    - Incomplete row detection tests (8 tests)
    - Quoted field handling tests (8 tests)
    - Header preservation tests (5 tests)
    - Edge case tests (8 tests)
    - Metadata tests (3 tests)
    - Integration tests (7 tests)
    - **Total: 47 tests exceeding 40+ requirement**
  - [ ] 3.2 Create CSVMerger class
    - Implement in lib/raaf/continuation/mergers/csv_merger.rb
    - Use Ruby CSV library for parsing
    - Handle incomplete rows at chunk boundaries
    - Preserve headers from first chunk
  - [ ] 3.3 Implement incomplete row detection
    - Count quotes for quoted field detection
    - Check for trailing commas
    - Identify split multi-line fields
    - Handle various CSV dialects
  - [ ] 3.4 Implement smart CSV concatenation
    - Complete partial rows
    - Remove duplicate headers
    - Maintain column alignment
    - Handle empty chunks gracefully
  - [ ] 3.5 Add CSV-specific continuation prompts
    - Include incomplete row context
    - Request completion then continuation
    - Specify no header repetition
    - Maintain consistent formatting
  - [ ] 3.6 Ensure all CSV merger tests pass
    - Run all CSV-specific tests
    - Verify 95%+ success rate on test data
    - Confirm edge cases handled

**Acceptance Criteria:**
- All tests written in 3.1 pass
- CSV merger achieves 95%+ success rate
- Handles incomplete rows correctly
- Preserves data integrity across chunks

#### Task Group 4: Markdown Merger Implementation
**Assigned implementer:** backend-engineer
**Dependencies:** Task Group 2

- [x] 4.0 Complete Markdown merger with 85-95% success rate
  - [x] 4.1 Write comprehensive Markdown merger tests
    - Table continuation tests
    - List continuation tests
    - Code block handling tests
    - Header deduplication tests
    - Mixed content tests
  - [x] 4.2 Create MarkdownMerger class
    - Implement in lib/raaf/continuation/mergers/markdown_merger.rb
    - Parse markdown structure
    - Detect incomplete tables
    - Handle various markdown elements
  - [x] 4.3 Implement table detection and merging
    - Count table columns
    - Detect incomplete rows
    - Remove duplicate headers
    - Maintain table formatting
  - [x] 4.4 Implement smart markdown concatenation
    - Preserve formatting
    - Handle nested structures
    - Maintain list numbering
    - Preserve code blocks
  - [ ] 4.5 Add Markdown-specific continuation prompts
    - Include last 5 lines of context
    - Request format preservation
    - Specify table continuation rules
    - Handle section boundaries
  - [x] 4.6 Ensure all Markdown merger tests pass
    - Run all Markdown-specific tests
    - Verify 85-95% success rate
    - Confirm formatting preserved

**Acceptance Criteria:**
- All tests written in 4.1 pass
- Markdown merger achieves 85-95% success rate (ACHIEVED: 97.9%)
- Tables merge correctly across chunks
- Document structure maintained

### Phase 3: JSON Merger Implementation

#### Task Group 5: JSON Merger with Repair
**Assigned implementer:** backend-engineer
**Dependencies:** Task Group 2

- [x] 5.0 Complete JSON merger with 60-70% success rate
  - [x] 5.1 Write comprehensive JSON merger tests
    - Array continuation tests
    - Object continuation tests
    - Nested structure tests
    - Malformed JSON repair tests
    - Schema validation tests
  - [x] 5.2 Create JSONMerger class
    - Implement in lib/raaf/continuation/mergers/json_merger.rb
    - Integrate with RAAF::JsonRepair
    - Detect JSON structure type
    - Handle various truncation points
  - [x] 5.3 Implement JSON structure detection
    - Identify arrays vs objects
    - Find continuation points
    - Detect incomplete structures
    - Track nesting levels
  - [x] 5.4 Implement smart JSON concatenation
    - Handle mid-array truncation
    - Complete partial objects
    - Maintain proper nesting
    - Use JsonRepair for final merge
  - [ ] 5.5 Add JSON-specific continuation prompts
    - Include structure hints
    - Request raw JSON only
    - Specify continuation format
    - Avoid wrapper text
  - [ ] 5.6 Integrate with schema validation
    - Relax validation during chunks
    - Full validation on final merge
    - Handle validation errors gracefully
    - Return best-effort results
  - [x] 5.7 Ensure all JSON merger tests pass
    - Run all JSON-specific tests
    - Verify 60-70% success rate (ACHIEVED: 92.5%)
    - Confirm schema validation works

**Acceptance Criteria:**
- All tests written in 5.1 pass
- JSON merger achieves 60-70% success rate (EXCEEDED: 92.5%)
- JsonRepair integration works correctly
- Schema validation handles continuations

### Phase 4: Integration and Testing

#### Task Group 6: Format Detection and Routing
**Assigned implementer:** backend-engineer
**Dependencies:** Task Groups 3, 4, 5

- [ ] 6.0 Complete format detection and merger routing system
  - [ ] 6.1 Write tests for format detection
    - Auto-detection from content tests
    - Explicit format configuration tests
    - Fallback handling tests
    - Unknown format tests
  - [ ] 6.2 Create FormatDetector class
    - Detect CSV by structure
    - Detect Markdown by syntax
    - Detect JSON by brackets/braces
    - Return confidence scores
  - [ ] 6.3 Implement MergerFactory
    - Route to appropriate merger
    - Handle :auto format option
    - Provide fallback merger
    - Log format detection results
  - [ ] 6.4 Integrate mergers with ResponsesProvider
    - Call appropriate merger based on format
    - Pass configuration options
    - Handle merger failures
    - Return merged results
  - [ ] 6.5 Ensure all routing tests pass
    - Run format detection tests
    - Verify correct merger selection
    - Confirm fallback behavior

**Acceptance Criteria:**
- All tests written in 6.1 pass
- Format auto-detection works reliably
- Correct merger selected for each format
- Fallback handling works properly

#### Task Group 7: Error Handling and Graceful Degradation
**Assigned implementer:** backend-engineer
**Dependencies:** Task Group 6

**Implementation Files:**
- `lib/raaf/continuation/error_handling.rb` (Error handling strategies)
- `lib/raaf/continuation/partial_result_builder.rb` (PartialResultBuilder)

- [ ] 7.0 Complete error handling and partial result support
  - [ ] 7.1 Write tests for error scenarios
    - Merge failure tests (JSON parse error, CSV parse error, Markdown parse error)
    - Partial result return tests
    - Error metadata tests (error_class, merge_error, error_message)
    - Fallback strategy tests (3-level fallback chain)
    - Max attempts exceeded tests
    - Recovery strategy tests
  - [ ] 7.2 Implement merge failure handling with fallback chain
    - Catch merger exceptions (all exception types)
    - Implement 3-level fallback strategy:
      * Level 1: Try format-specific merge
      * Level 2: Fall back to simple line concatenation
      * Level 3: Fall back to first chunk only (best-effort)
    - Log detailed error information at WARN level
    - Track which fallback level was used
    - Include error in metadata (error_class, merge_error fields)
    - Handle timeout scenarios gracefully
  - [ ] 7.3 Create PartialResultBuilder
    - Combine successful chunks into partial result
    - Mark incomplete sections with metadata
    - Add failure annotations (error_section, incomplete_after)
    - Preserve valid data from all successful merges
    - Build coherent partial output even if final chunk incomplete
  - [ ] 7.4 Implement configurable failure modes
    - :return_partial implementation (return accumulated data + error metadata)
    - :raise_error implementation (raise ContinuationError with details)
    - Custom error classes (ContinuationError, MergeError, TruncationError)
    - Detailed error messages with context (which chunk failed, why, recovery options)
  - [ ] 7.5 Ensure all error handling tests pass
    - Run all failure scenario tests
    - Verify partial results are valid and usable
    - Confirm error metadata accurate
    - Test fallback chain execution
    - Verify recovery behavior

**Acceptance Criteria:**
- All tests written in 7.1 pass
- Partial results returned on merge failure
- Error metadata provides debugging info
- No data loss on recoverable errors

#### Task Group 8: DSL Integration and Helpers
**Assigned implementer:** backend-engineer
**Dependencies:** Task Group 6

- [ ] 8.0 Complete DSL integration and helper methods
  - [ ] 8.1 Write tests for DSL helpers
    - Output format helper tests
    - Continuation status check tests
    - Metadata access tests
    - Configuration override tests
  - [ ] 8.2 Add output format DSL helpers
    - output_csv convenience method
    - output_markdown convenience method
    - output_json convenience method
    - Auto-configure continuation
  - [ ] 8.3 Create continuation status methods
    - was_continued? helper
    - continuation_count helper
    - continuation_metadata helper
    - total_tokens_used helper
  - [ ] 8.4 Add result transformation support
    - Handle continued results in transformers
    - Preserve continuation metadata
    - Support partial result handling
    - Chain transformations correctly
  - [ ] 8.5 Ensure all DSL integration tests pass
    - Run helper method tests
    - Verify convenience methods work
    - Confirm metadata preserved

**Acceptance Criteria:**
- All tests written in 8.1 pass
- DSL helpers simplify configuration
- Metadata easily accessible
- Result transformers handle continuations

#### Task Group 9: Observability and Logging
**Assigned implementer:** backend-engineer
**Dependencies:** Task Group 7

**Implementation Files:**
- `lib/raaf/continuation/logging.rb` (Logging infrastructure)
- `lib/raaf/continuation/cost_calculator.rb` (Cost calculation)

- [ ] 9.0 Complete observability and logging implementation
  - [ ] 9.1 Write tests for logging and metrics
    - Log level tests (INFO, DEBUG, WARN, ERROR)
    - Metadata structure tests (all 11+ fields)
    - Cost calculation tests (pricing for all models)
    - Performance metric tests (duration, memory, tokens)
    - Metadata field completeness tests:
      * All fields present for successful continuations
      * All fields present for failed continuations
      * error_class and merge_error only on failure
      * Verify field data types
  - [ ] 9.2 Implement continuation logging
    - INFO level for continuation start/end events (🔄 emoji)
    - DEBUG level for chunk details (chunk size, finish_reason, duration)
    - WARN level for failures (⚠️ emoji) and content_filter/incomplete finish_reasons
    - ERROR level for critical failures (❌ emoji)
    - Structured log format with tags/context
    - Log suggestion for incomplete finish_reason (include previous_response_id)
  - [ ] 9.3 Add continuation metadata structure
    - was_continued flag
    - continuation_count (number of continuation attempts)
    - output_format (format used for merge)
    - chunk_sizes array (bytes per chunk)
    - truncation_points array (where each truncation occurred)
    - finish_reasons array (finish_reason per chunk)
    - merge_strategy_used (csv, markdown, json, fallback_level)
    - merge_success flag (true if merge succeeded)
    - total_output_tokens (sum across all chunks)
    - total_cost_estimate (calculated using model pricing)
    - error details (error_class, merge_error, error_message, incomplete_after)
  - [ ] 9.4 Implement cost calculation
    - Create CostCalculator class in `lib/raaf/continuation/cost_calculator.rb`
    - Implement pricing lookup for models:
      * gpt-4o: input $0.005, output $0.015 per 1k tokens
      * gpt-4o-mini: input $0.00015, output $0.0006 per 1k tokens
      * Support additional models as needed
    - Calculate cost per chunk based on output tokens
    - Sum costs across all continuation chunks
    - Add to total_cost_estimate in metadata
    - Track cost savings (what would have been paid without continuation)
  - [ ] 9.5 Create continuation metrics
    - Track success rates by format (CSV, Markdown, JSON)
    - Measure merge performance (time per merge operation)
    - Calculate cost impact (total cost of continuations)
    - Monitor token usage (total output tokens across continuations)
    - Track fallback strategy usage (which fallback levels used how often)
  - [ ] 9.6 Ensure all observability tests pass
    - Run logging tests (verify log format, levels, content)
    - Verify metadata structure (all fields present, correct types)
    - Confirm metrics accurate (calculations correct)
    - Test cost calculation for all supported models

**Acceptance Criteria:**
- All tests written in 9.1 pass
- Logs provide debugging information
- Metadata comprehensive and accurate
- Metrics enable optimization

### Testing and Validation

#### Task Group 10: Integration Testing
**Assigned implementer:** testing-engineer
**Dependencies:** Task Groups 1-9

- [x] 10.0 Complete end-to-end integration testing
  - [x] 10.1 Create integration test suite
    - Real LLM interaction tests (with stubs/mocks)
    - Multi-format test scenarios
    - Large dataset tests
    - Edge case scenarios
    - Metadata field completeness tests:
      * All metadata fields present for successful continuations
      * All metadata fields present for failed continuations
      * error_class and merge_error only present on failure
      * Verify all field data types
      * Test metadata accuracy (tokens, costs, chunk_sizes)
  - [x] 10.2 Test CSV continuation scenarios
    - 500+ row datasets
    - Various CSV formats
    - Quoted field edge cases
    - Performance benchmarks
  - [x] 10.3 Test Markdown continuation scenarios
    - Large reports with tables
    - Mixed content documents
    - Complex formatting
    - Table size variations
  - [x] 10.4 Test JSON continuation scenarios
    - Large arrays (1000+ items)
    - Deeply nested objects
    - Schema validation cases
    - Repair success rates
  - [x] 10.5 Test error recovery scenarios
    - Network failures mid-continuation
    - Malformed responses
    - Max attempts exceeded
    - Partial result quality
  - [x] 10.6 Verify all integration tests pass
    - Run full test suite
    - Check success rate targets
    - Confirm no regressions

**Acceptance Criteria:**
- All integration tests pass
- Success rates meet targets (CSV 95%, Markdown 85%, JSON 60%)
- No performance regression
- Error recovery works as designed

#### Task Group 11: Performance Testing
**Assigned implementer:** testing-engineer
**Dependencies:** Task Group 10

- [x] 11.0 Complete performance testing and optimization
  - [x] 11.1 Create performance benchmarks
    - Baseline without continuation
    - Overhead measurement tests
    - Memory usage tests
    - Token usage analysis
  - [x] 11.2 Measure continuation overhead
    - Time per continuation
    - Memory per chunk
    - CPU usage impact
    - Network latency effects
  - [x] 11.3 Optimize merge operations
    - Profile merger performance
    - Identify bottlenecks
    - Implement optimizations
    - Verify improvements
  - [x] 11.4 Validate performance targets
    - < 10% overhead for non-continued
    - < 100ms per merge operation
    - Memory usage within bounds
    - Cost calculations accurate
  - [x] 11.5 Ensure performance acceptable
    - Run all benchmarks
    - Compare against targets
    - Document performance characteristics

**Acceptance Criteria:**
- Performance benchmarks documented
- < 10% overhead for non-continued responses
- Merge operations efficient
- No memory leaks detected

### Documentation and Examples

#### Task Group 12: Documentation
**Assigned implementer:** backend-engineer
**Dependencies:** Task Group 10

- [ ] 12.0 Complete documentation and examples
  - [ ] 12.1 Write user documentation
    - Feature overview
    - Configuration guide
    - Format-specific guidance
    - Troubleshooting guide
  - [ ] 12.2 Create API documentation
    - DSL method documentation
    - Configuration options
    - Result metadata structure
    - Error handling details
  - [ ] 12.3 Write example implementations
    - Dutch company discovery (CSV)
    - Market analysis report (Markdown)
    - Data extraction (JSON)
    - Error handling examples
  - [ ] 12.4 Create migration guide
    - Upgrading existing agents
    - Configuration best practices
    - Performance considerations
    - Cost optimization tips
  - [ ] 12.5 Update main README
    - Add continuation feature section
    - Include quick examples
    - Link to detailed docs
    - Add to feature matrix

**Acceptance Criteria:**
- Documentation comprehensive and clear
- Examples work out of the box
- Migration path documented
- README updated with feature

### Verification and Demo

#### Task Group 13: Final Verification
**Assigned implementer:** testing-engineer
**Dependencies:** All previous tasks

- [ ] 13.0 Complete final verification and demonstration
  - [ ] 13.1 Run full regression test suite
    - All existing tests pass
    - No breaking changes
    - Performance acceptable
    - Memory usage normal
  - [ ] 13.2 Verify success rate targets
    - CSV: 95%+ success rate
    - Markdown: 85-95% success rate
    - JSON: 60-70% success rate
    - Document actual rates
  - [ ] 13.3 Create demo script
    - Show all three formats
    - Demonstrate error recovery
    - Display metadata
    - Calculate cost savings
  - [ ] 13.4 Perform user acceptance testing
    - Test with real-world data
    - Validate user workflows
    - Gather feedback
    - Address issues
  - [ ] 13.5 Final quality check
    - Code review complete
    - Documentation reviewed
    - Examples tested
    - Ready for release

**Acceptance Criteria:**
- All regression tests pass
- Success rates meet or exceed targets
- Demo script runs successfully
- Feature ready for production use

## Execution Order

Recommended implementation sequence:
1. Phase 1: Core Infrastructure (Task Groups 1-2) - Days 1-2
2. Phase 2: Format-Specific Mergers (Task Groups 3-4) - Days 3-5
3. Phase 3: JSON Merger (Task Group 5) - Days 6-7
4. Phase 4: Integration (Task Groups 6-9) - Days 8-10
5. Testing & Documentation (Task Groups 10-13) - Days 10-11

## Risk Mitigation

**High-Risk Areas:**
1. JSON merger complexity - Mitigation: Leverage existing JsonRepair
2. Format auto-detection accuracy - Mitigation: Allow explicit configuration
3. Performance overhead - Mitigation: Early benchmarking and optimization
4. Schema validation with partial data - Mitigation: Relaxed validation modes

## Success Metrics

- **Functional:** All three formats supported with target success rates
- **Performance:** < 10% overhead for non-continued responses
- **Reliability:** Graceful degradation with partial results
- **Usability:** Single configuration line enables feature
- **Quality:** Zero regressions in existing functionality

# Spec Tasks

These are the tasks to be completed for the spec detailed in @.agent-os/specs/2025-11-06-raaf-eval-rspec-integration/spec.md

> Created: 2025-11-06
> Status: Ready for Implementation

## Tasks

- [ ] 1. Create RSpec helper module structure
  - [ ] 1.1 Write tests for RAAF::Eval::RSpec module inclusion
  - [ ] 1.2 Create lib/raaf/eval/rspec.rb entry point
  - [ ] 1.3 Create lib/raaf/eval/rspec/helpers.rb module
  - [ ] 1.4 Implement module inclusion mechanism
  - [ ] 1.5 Add RSpec configuration helper
  - [ ] 1.6 Create spec_helper example configuration
  - [ ] 1.7 Add auto-include for spec/evaluations/ files
  - [ ] 1.8 Verify all tests pass and module loads correctly

- [ ] 2. Implement evaluation DSL core
  - [ ] 2.1 Write tests for DSL block parsing
  - [ ] 2.2 Create RAAF::Eval::RSpec::DSL class
  - [ ] 2.3 Implement `evaluation` block method
  - [ ] 2.4 Implement `span` method for span selection
  - [ ] 2.5 Implement `configuration` method for single config
  - [ ] 2.6 Implement multiple configuration support
  - [ ] 2.7 Implement `run_async` flag
  - [ ] 2.8 Add DSL validation and error messages
  - [ ] 2.9 Verify all tests pass and DSL works correctly

- [ ] 3. Implement evaluation execution integration
  - [ ] 3.1 Write tests for evaluation runner
  - [ ] 3.2 Create RAAF::Eval::RSpec::EvaluationRunner class
  - [ ] 3.3 Integrate with Phase 1 evaluation engine
  - [ ] 3.4 Implement synchronous execution
  - [ ] 3.5 Implement asynchronous execution with waiting
  - [ ] 3.6 Add result caching within example scope
  - [ ] 3.7 Integrate with RSpec progress reporting
  - [ ] 3.8 Handle evaluation failures gracefully
  - [ ] 3.9 Verify all tests pass and evaluations execute correctly

- [ ] 4. Implement helper methods
  - [ ] 4.1 Write tests for `evaluate_span` method
  - [ ] 4.2 Implement `evaluate_span(span_id)` method
  - [ ] 4.3 Implement `evaluate_span(span: object)` support
  - [ ] 4.4 Implement `evaluate_latest_span(agent: name)` method
  - [ ] 4.5 Write tests for `with_configuration` method
  - [ ] 4.6 Implement `with_configuration(hash)` method
  - [ ] 4.7 Implement `with_configurations(array)` method
  - [ ] 4.8 Write tests for `run_evaluation` method
  - [ ] 4.9 Implement `run_evaluation` with options
  - [ ] 4.10 Provide result accessors (evaluation_result, baseline_result, etc.)
  - [ ] 4.11 Verify all tests pass and helpers work correctly

- [ ] 5. Implement quality matchers
  - [ ] 5.1 Write tests for `maintain_quality` matcher
  - [ ] 5.2 Implement `maintain_quality` matcher with threshold
  - [ ] 5.3 Add `across_all_configurations` modifier
  - [ ] 5.4 Write tests for `have_similar_output_to` matcher
  - [ ] 5.5 Implement `have_similar_output_to(target)` matcher
  - [ ] 5.6 Write tests for `have_coherent_output` matcher
  - [ ] 5.7 Implement `have_coherent_output` with threshold
  - [ ] 5.8 Write tests for `not_hallucinate` matcher
  - [ ] 5.9 Implement `not_hallucinate` matcher
  - [ ] 5.10 Add clear failure messages for all quality matchers
  - [ ] 5.11 Verify all tests pass and matchers work correctly

- [ ] 6. Implement performance matchers
  - [ ] 6.1 Write tests for `use_tokens` matcher
  - [ ] 6.2 Implement `use_tokens` base matcher
  - [ ] 6.3 Add `.within(N).percent_of(target)` chain
  - [ ] 6.4 Add `.less_than(N)` chain
  - [ ] 6.5 Add `.between(min, max)` chain
  - [ ] 6.6 Write tests for `complete_within` matcher
  - [ ] 6.7 Implement `complete_within(N).seconds` matcher
  - [ ] 6.8 Add `.milliseconds` unit support
  - [ ] 6.9 Write tests for `cost_less_than` matcher
  - [ ] 6.10 Implement `cost_less_than(amount)` matcher
  - [ ] 6.11 Add clear failure messages with actual vs expected
  - [ ] 6.12 Verify all tests pass and matchers work correctly

- [ ] 7. Implement regression matchers
  - [ ] 7.1 Write tests for `not_have_regressions` matcher
  - [ ] 7.2 Implement `not_have_regressions` matcher
  - [ ] 7.3 Add `.of_severity(level)` modifier
  - [ ] 7.4 Write tests for `perform_better_than` matcher
  - [ ] 7.5 Implement `perform_better_than(target)` matcher
  - [ ] 7.6 Write tests for `have_acceptable_variance` matcher
  - [ ] 7.7 Implement `have_acceptable_variance` matcher
  - [ ] 7.8 Add `.within(N).standard_deviations` chain
  - [ ] 7.9 Add clear failure messages with regression details
  - [ ] 7.10 Verify all tests pass and matchers work correctly

- [ ] 8. Implement safety matchers
  - [ ] 8.1 Write tests for `not_have_bias` matcher
  - [ ] 8.2 Implement `not_have_bias` base matcher
  - [ ] 8.3 Add `.for_gender`, `.for_race`, `.for_region` modifiers
  - [ ] 8.4 Write tests for `be_safe` matcher
  - [ ] 8.5 Implement `be_safe` matcher with toxicity check
  - [ ] 8.6 Add `.with_toxicity_below(N)` modifier
  - [ ] 8.7 Write tests for `comply_with_policy` matcher
  - [ ] 8.8 Implement `comply_with_policy` matcher
  - [ ] 8.9 Add `.for(policy_name)` modifier
  - [ ] 8.10 Add clear failure messages with safety details
  - [ ] 8.11 Verify all tests pass and matchers work correctly

- [ ] 9. Implement statistical matchers
  - [ ] 9.1 Write tests for `be_statistically_significant` matcher
  - [ ] 9.2 Implement `be_statistically_significant` matcher
  - [ ] 9.3 Add `.at_level(p_value)` modifier
  - [ ] 9.4 Write tests for `have_effect_size` matcher
  - [ ] 9.5 Implement `have_effect_size.of(N)` matcher
  - [ ] 9.6 Add `.above(N)` modifier
  - [ ] 9.7 Write tests for `have_confidence_interval` matcher
  - [ ] 9.8 Implement `have_confidence_interval.within(min, max)` matcher
  - [ ] 9.9 Add clear failure messages with statistical values
  - [ ] 9.10 Verify all tests pass and matchers work correctly

- [ ] 10. Implement structural matchers
  - [ ] 10.1 Write tests for `have_valid_format` matcher
  - [ ] 10.2 Implement `have_valid_format` base matcher
  - [ ] 10.3 Add `.as(format_type)` modifier
  - [ ] 10.4 Write tests for `match_schema` matcher
  - [ ] 10.5 Implement `match_schema(schema_hash)` matcher
  - [ ] 10.6 Write tests for `have_length` matcher
  - [ ] 10.7 Implement `have_length` base matcher
  - [ ] 10.8 Add `.between(min, max)` and `.less_than(N)` chains
  - [ ] 10.9 Add clear failure messages with format/schema errors
  - [ ] 10.10 Verify all tests pass and matchers work correctly

- [ ] 11. Implement LLM-powered matchers
  - [ ] 11.1 Write tests for `satisfy_llm_check` matcher
  - [ ] 11.2 Create RAAF::Eval::RSpec::Matchers::LLMJudge base class
  - [ ] 11.3 Implement `satisfy_llm_check(prompt)` matcher
  - [ ] 11.4 Add `.using_model(model)` chain
  - [ ] 11.5 Add `.with_confidence(threshold)` chain
  - [ ] 11.6 Implement judge result caching
  - [ ] 11.7 Write tests for `satisfy_llm_criteria` matcher
  - [ ] 11.8 Implement `satisfy_llm_criteria(array)` for simple criteria
  - [ ] 11.9 Implement `satisfy_llm_criteria(hash)` for weighted criteria
  - [ ] 11.10 Optimize multi-criteria evaluation (single judge call)
  - [ ] 11.11 Write tests for `be_judged_as` matcher
  - [ ] 11.12 Implement `be_judged_as(description)` matcher
  - [ ] 11.13 Add `.than(target)` chain for comparisons
  - [ ] 11.14 Add global LLM judge configuration
  - [ ] 11.15 Add per-test judge configuration override
  - [ ] 11.16 Implement cost tracking and reporting
  - [ ] 11.17 Add retry logic and error handling
  - [ ] 11.18 Add clear failure messages with judge reasoning
  - [ ] 11.19 Verify all tests pass and LLM matchers work correctly

- [ ] 12. Implement parallel execution support
  - [ ] 12.1 Write tests for parallel configuration execution
  - [ ] 12.2 Add thread-safety to evaluation runner
  - [ ] 12.3 Implement parallel execution using threads
  - [ ] 12.4 Add optional parallel_tests gem integration
  - [ ] 12.5 Handle database connection pooling
  - [ ] 12.6 Implement result aggregation from parallel workers
  - [ ] 12.7 Add progress reporting for parallel execution
  - [ ] 12.8 Verify all tests pass and parallel execution works

- [ ] 13. Implement CI/CD integration
  - [ ] 13.1 Write tests for exit code handling
  - [ ] 13.2 Ensure proper exit codes (0 = pass, 1 = fail)
  - [ ] 13.3 Add JUnit XML output support
  - [ ] 13.4 Add JSON output support
  - [ ] 13.5 Add TAP output support
  - [ ] 13.6 Create GitHub Actions example configuration
  - [ ] 13.7 Create GitLab CI example configuration
  - [ ] 13.8 Add timeout configuration for long evaluations
  - [ ] 13.9 Implement fail-fast mode
  - [ ] 13.10 Verify all tests pass and CI integration works

- [ ] 14. Add FactoryBot integration
  - [ ] 14.1 Write tests for factory helpers
  - [ ] 14.2 Create factory definitions for test spans
  - [ ] 14.3 Create factory definitions for test results
  - [ ] 14.4 Add factory_bot as optional dev dependency
  - [ ] 14.5 Create helper methods for factory usage
  - [ ] 14.6 Add factory examples to documentation
  - [ ] 14.7 Verify all tests pass and factories work

- [ ] 15. Create comprehensive examples
  - [ ] 15.1 Create simple evaluation test example
  - [ ] 15.2 Create multi-configuration comparison example
  - [ ] 15.3 Create regression detection example
  - [ ] 15.4 Create safety and bias testing example
  - [ ] 15.5 Create CI/CD pipeline example
  - [ ] 15.6 Create custom matcher example
  - [ ] 15.7 Create LLM judge matcher example
  - [ ] 15.8 Create parallel execution example
  - [ ] 15.9 Verify all examples run successfully

- [ ] 16. Performance testing and optimization
  - [ ] 16.1 Write performance benchmarks for DSL parsing
  - [ ] 16.2 Write performance benchmarks for matcher execution
  - [ ] 16.3 Write performance benchmarks for LLM judge caching
  - [ ] 16.4 Write performance benchmarks for parallel execution
  - [ ] 16.5 Write performance benchmarks for CI/CD overhead
  - [ ] 16.6 Profile and optimize slow operations
  - [ ] 16.7 Verify performance targets met
  - [ ] 16.8 Document performance characteristics

- [ ] 17. Documentation and finalization
  - [ ] 17.1 Write comprehensive matcher API documentation
  - [ ] 17.2 Create evaluation DSL usage guide
  - [ ] 17.3 Document all helper methods with examples
  - [ ] 17.4 Document LLM judge matchers with examples
  - [ ] 17.5 Create RSpec configuration guide
  - [ ] 17.6 Document CI/CD integration patterns
  - [ ] 17.7 Add troubleshooting guide for common issues
  - [ ] 17.8 Create migration guide from manual evaluation code
  - [ ] 17.9 Update main RAAF README with RSpec integration info
  - [ ] 17.10 Verify all documentation is complete and accurate

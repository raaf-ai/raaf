# RAAF Span Detail Integration Tests

This directory contains comprehensive integration tests for the RAAF Span Detail component system.

## Purpose

Integration tests verify that the complete span detail page works correctly as a cohesive unit, testing the interaction between all components, data flow, and user experience from end to end.

## Test Coverage

### span_detail_integration_spec.rb

Comprehensive integration testing covering:

**Component Routing (7 tests)**
- Tool spans → ToolSpanComponent
- Agent spans → AgentSpanComponent  
- LLM spans → LlmSpanComponent
- Handoff spans → HandoffSpanComponent
- Guardrail spans → GuardrailSpanComponent
- Pipeline spans → PipelineSpanComponent
- Unknown spans → GenericSpanComponent

**Universal Elements (4 tests)**
- Span header information and badges
- Navigation links and trace relationships
- Timing information display
- Hierarchy and parent/child relationships

**Type-Specific Rendering (4 tests)**
- Tool spans with input/output visualization
- Agent spans with context and execution details
- LLM spans with request/response and cost metrics
- Pipeline spans with stage execution flow

**Interactive Functionality (5 tests)**
- Stimulus controller integration
- Section toggle actions
- Tool-specific expand/collapse
- Copy-to-clipboard functionality
- Collapsible attribute groups

**Data Flow & Edge Cases (5 tests)**
- Malformed JSON handling
- Null and empty value display
- Very long string truncation
- Unicode content support
- Deep object nesting

**Performance (3 tests)**
- Large array handling (1000+ items)
- Huge string truncation (10MB+ content)
- Objects with many keys (500+ properties)

**Error Handling (3 tests)**
- Error detail sections
- Missing required attributes
- Nil span attributes

**Children & Events (2 tests)**
- Child spans display
- Events timeline rendering

**Accessibility (3 tests)**
- Semantic HTML structure
- ARIA labels and descriptions
- Screen reader compatibility

**Cross-Component Consistency (2 tests)**
- Data representation consistency
- Trace relationship rendering

**Rails Integration (2 tests)**
- Path helper usage
- Time formatting helpers

## Test Data Fixtures

The tests use comprehensive, production-like fixtures:

### Tool Span Data
- Complex search functionality with filters
- Nested input parameters
- Rich output results with metadata
- Performance metrics and API call data

### Agent Span Data
- Agent configuration and model settings
- Context data with product/campaign information
- Execution metrics (tokens, turns, tool calls)
- Result analysis with confidence scores

### LLM Span Data
- Complete request/response cycle
- Token usage and cost breakdown
- Performance metrics (latency, throughput)
- Function calling examples

### Handoff Span Data
- Multi-agent transfer scenarios
- Complex data passing between agents
- Success metrics and validation
- Context preservation verification

### Guardrail Span Data
- Content safety rule evaluation
- PII detection and redaction
- Risk scoring and filtering results
- Performance and cache metrics

### Pipeline Span Data
- Multi-stage execution flow
- Agent performance comparison
- Resource utilization tracking
- Final result aggregation

### Edge Case Data
- Malformed JSON structures
- Null/empty values
- Very large datasets (1000+ items)
- Deep nesting (5+ levels)
- Unicode content (emoji, Chinese, Arabic)
- Special characters and escaping

## Running the Tests

```bash
# Run integration tests specifically
bundle exec rspec spec/integration/

# Run with verbose output
bundle exec rspec spec/integration/span_detail_integration_spec.rb -v

# Run specific test groups
bundle exec rspec spec/integration/span_detail_integration_spec.rb -e "Component Routing"
```

## Test Philosophy

These integration tests focus on:

1. **End-to-End Workflows**: Testing complete user journeys through the span detail interface
2. **Component Interaction**: Verifying that components work together seamlessly
3. **Data Integrity**: Ensuring data is preserved and displayed correctly throughout the system
4. **User Experience**: Testing that interactive elements and navigation work as expected
5. **Error Resilience**: Verifying graceful handling of edge cases and malformed data
6. **Performance**: Ensuring the system handles large datasets without degrading user experience
7. **Accessibility**: Testing that the interface works for all users including screen readers

## Maintenance

When adding new span types or modifying existing components:

1. **Add Component Routing Tests**: Ensure new span types route to correct components
2. **Create Realistic Fixtures**: Use production-like data that tests real-world scenarios
3. **Test Edge Cases**: Include malformed data, null values, and extreme sizes
4. **Verify Interactions**: Test Stimulus controllers and user interactions
5. **Check Accessibility**: Ensure new elements maintain semantic structure
6. **Update Documentation**: Keep this README and test comments current

The integration tests serve as both quality assurance and living documentation of expected system behavior.

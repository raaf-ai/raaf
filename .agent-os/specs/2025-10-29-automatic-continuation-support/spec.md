# Specification: Automatic Continuation Support

> Created: 2025-10-29
> Status: Planning
> RAAF Version: 2.0.0+

## Overview

Enable RAAF agents to automatically detect truncated LLM responses and continue generation, seamlessly merging multiple response chunks to deliver complete results without manual intervention.

## Problem Statement

LLM responses are frequently truncated due to output token limits when generating large datasets. This causes:

1. **Incomplete Results**: Company discovery, report generation, and data extraction tasks produce partial outputs when datasets exceed token limits (typically 250-500 records per response)
2. **Manual Complexity**: Developers must implement custom continuation logic, detect truncation, craft continuation prompts, and merge partial results - all format-specific and error-prone
3. **Data Integrity Issues**: CSV rows split mid-field, markdown tables break mid-row, JSON objects/arrays become invalid
4. **Poor Developer Experience**: Requires understanding of each format's structure and implementing complex merge strategies

**Example Impact:**
- A company discovery task requesting 1000 records gets truncated at ~250 companies
- A report with 100-row markdown table breaks at row 47 with malformed table structure
- A JSON array extraction of 500 items becomes invalid JSON when truncated mid-object

## User Stories

### Story 1: Large Dataset Discovery with CSV Output

**As a** developer using RAAF for company discovery
**I want to** retrieve 500-1000 company records in CSV format without worrying about token limits
**So that** I can process large datasets reliably without implementing custom continuation logic

**Workflow:**
1. Agent configured with `enable_continuation(output_format: :csv)`
2. LLM generates CSV data until token limit (e.g., 250 companies)
3. RAAF detects `finish_reason: "length"` indicating truncation
4. Automatically continues generation with stateful API context
5. Merges CSV chunks intelligently (completes split rows, appends data)
6. Returns complete 500-1000 record CSV dataset seamlessly

**Problem Solved:** Without continuation, developers must manually detect truncation, craft continuation prompts, and merge partial results - complex and error-prone logic that varies by format.

### Story 2: Large Report Generation with Markdown Tables

**As a** developer building report generation agents
**I want to** generate comprehensive reports with large markdown tables that exceed token limits
**So that** reports are complete and properly formatted without manual chunking

**Workflow:**
1. Agent configured with `enable_continuation(output_format: :markdown)`
2. Report generation starts, creating markdown with tables
3. Output truncated mid-table (e.g., row 47 of 100)
4. RAAF detects incomplete markdown table structure
5. Continues generation from row 48 with proper table formatting
6. Merges markdown sections preserving table integrity
7. Returns complete formatted report

**Problem Solved:** Markdown tables frequently split mid-row when truncated, resulting in broken formatting. Manual continuation requires understanding markdown structure and careful merging.

### Story 3: Structured Data Extraction with JSON

**As a** developer extracting structured data from documents
**I want to** extract large JSON datasets that may exceed token limits
**So that** I get complete, valid JSON without implementing complex repair logic

**Workflow:**
1. Agent configured with `enable_continuation(output_format: :json)`
2. Extraction begins, generating JSON array of objects
3. JSON truncated mid-object or mid-array
4. RAAF detects malformed JSON structure
5. Continues generation with context about incomplete structure
6. Uses JSON repair to merge chunks into valid JSON
7. Returns complete, schema-valid JSON dataset

**Problem Solved:** JSON is particularly fragile when truncated - missing brackets, incomplete objects, or split strings create invalid JSON. Manual repair is complex and error-prone.

## Feature Scope

### In Scope

1. **Truncation Detection** - Identify when LLM responses are cut off due to token limits (`finish_reason: "length"`)
2. **Automatic Continuation** - Generate continuation prompts and manage multi-turn generation using Responses API `previous_response_id`
3. **Format-Specific Merging** - Intelligent merge strategies for CSV, Markdown, and JSON formats
4. **Simple Configuration** - Single-line agent configuration: `enable_continuation(output_format: :csv)`
5. **Error Recovery** - Graceful degradation with partial result return on merge failures
6. **Observability** - Continuation metadata for debugging and cost analysis
7. **Warning System** - Alert developers when `finish_reason` is `content_filter` or `incomplete`
8. **Stateful API Integration** - Use `previous_response_id` for automatic context management

### Out of Scope

- Binary format continuation (PDF, Excel, images)
- Custom merge strategies beyond the three core formats
- Real-time streaming continuation (defer to streaming feature)
- Provider-specific continuation handling beyond ResponsesProvider (v1)
- Manual continuation control (fully automatic in v1)
- Cross-agent continuation (single agent scope only)

## Success Criteria

### Functional Requirements

1. **CSV Success Rate**: 95%+ accuracy for datasets up to 1000 records
   - Properly handles incomplete rows at chunk boundaries
   - Maintains data integrity across continuations
   - Preserves headers from first chunk

2. **Markdown Success Rate**: 85-95% accuracy for large documents with tables
   - Correctly continues markdown tables mid-table
   - Preserves document structure and formatting
   - Handles mixed content (tables, lists, code blocks)

3. **JSON Success Rate**: 60-70% accuracy for structured data
   - Repairs malformed JSON from truncation
   - Validates against schemas after merge
   - Handles nested objects and arrays

4. **Zero Breaking Changes**: Existing agents work without modification

5. **Simple Configuration**: Single configuration line enables feature

6. **Observability**: Complete metadata available including:
   - Continuation count and chunk sizes
   - Token usage per chunk and total cost
   - Merge strategy used and success status
   - Truncation points and finish reasons

7. **Error Recovery**: Partial results returned in 100% of merge failures

8. **Warning System**: 100% of non-standard completions logged:
   - `finish_reason: "content_filter"` → WARN level
   - `finish_reason: "incomplete"` → WARN level with remediation guidance

### Performance Requirements

- **Overhead**: < 10% for non-continued responses
- **Merge Speed**: < 100ms per merge operation
- **Memory**: No memory leaks or excessive usage
- **Cost Tracking**: Accurate token and cost calculation across continuations

## High-Level Configuration

Agents enable continuation support with a simple class-level declaration:

```ruby
class CompanyDiscoveryAgent < RAAF::DSL::Agent
  agent_name "CompanyDiscovery"
  model "gpt-4o"

  # Enable automatic continuation
  enable_continuation(
    max_attempts: 10,           # Maximum continuation attempts
    output_format: :csv,         # Format: :csv, :markdown, :json, :auto
    on_failure: :return_partial  # Failure mode: :return_partial, :raise_error
  )

  instructions "Find companies matching criteria and output as CSV"
end

# Usage is transparent - continuation happens automatically
agent = CompanyDiscoveryAgent.new
result = agent.run

# Access continuation metadata
puts result[:_continuation_metadata][:continuation_count]  # e.g., 3
puts result[:_continuation_metadata][:final_record_count]  # e.g., 523
```

## Dependencies

### RAAF Components Affected

1. **RAAF::Models::ResponsesProvider** - Detects truncation and orchestrates continuation
2. **RAAF::DSL::Agent** - Provides `enable_continuation` configuration method
3. **RAAF::JsonRepair** - Used by JSON merger for structure repair
4. **RAAF::Runner** - Passes continuation configuration to provider
5. **Result metadata** - Extended with `_continuation_metadata` field

### External Dependencies

- Ruby CSV library (built-in)
- OpenAI Responses API with `previous_response_id` support

## Implementation Details

For complete technical specifications, see:

- **Core Infrastructure**: @implementation/1_core-infrastructure/technical-spec.md
- **Format Mergers**:
  - @implementation/2_format-mergers/csv-merger-spec.md
  - @implementation/2_format-mergers/markdown-merger-spec.md
  - @implementation/2_format-mergers/json-merger-spec.md
- **Integration**:
  - @implementation/3_integration/dsl-integration-spec.md
  - @implementation/3_integration/error-handling-spec.md
  - @implementation/3_integration/observability-spec.md
- **Testing**:
  - @implementation/4_testing-validation/test-strategy.md
  - @implementation/4_testing-validation/validation-plan.md

# Requirements Document

> Created: 2025-10-10
> Source: Conversation with user about RAAF tool architecture

## Problem Statement

Currently, DSL conveniences (validation, logging, metadata, duration tracking) are implemented in individual DSL tool wrapper classes. This creates:

1. **Code Duplication**: Each DSL tool wrapper re-implements the same convenience features
2. **Maintenance Burden**: Updates to convenience features require changing every wrapper
3. **Unnecessary Abstraction**: Core tools (`raaf/tools`) are wrapped just to add DSL features
4. **Mixed Responsibilities**: Tool wrappers contain both business logic delegation and DSL conveniences

### Current Architecture (Problems)

```
DSL Agent → DSL Tool Wrapper (200+ lines) → Core Tool (pure Ruby)
            ↑ Contains:
            - Validation
            - Logging
            - Metadata
            - Duration tracking
            - Tool definition generation
```

**Example Problem**: `RAAF::DSL::Tools::PerplexitySearch` (200+ lines) wraps `RAAF::Tools::PerplexityTool` just to add logging and validation.

## Proposed Solution

Move all DSL conveniences from individual tool wrappers into the DSL agent's tool execution layer through an interceptor pattern.

### Target Architecture

```
DSL Agent (with Tool Execution Interceptor)
    ↓
    Before: Validate, log start, record time
    ↓
    Execute: Call raw core tool
    ↓
    After: Log results, add metadata, calculate duration
    ↓
Raw Core Tool (pure Ruby, no DSL dependencies)
```

## Core Requirements

### 1. Tool Execution Interceptor

**Requirement**: Create a tool execution interceptor in `RAAF::DSL::Agent` class

**Functionality**:
- Override `execute_tool(tool, arguments)` method
- Implement before/after hooks around tool execution
- Centralize all DSL convenience features in one place

**Interface**:
```ruby
module RAAF
  module DSL
    class Agent < RAAF::Agent
      def execute_tool(tool, arguments)
        # BEFORE: Validation & logging
        # EXECUTE: Call the raw tool
        # AFTER: Logging & metadata
      end
    end
  end
end
```

### 2. Before-Execution Features

**Requirements**:

**2.1 Parameter Validation**
- Validate tool arguments against tool definition
- Check required parameters are present
- Validate parameter types match expectations
- Configurable: can be enabled/disabled per agent

**2.2 Execution Logging (Start)**
- Log tool name being executed
- Log arguments passed (with optional truncation for large payloads)
- Use `RAAF.logger.debug` for consistency
- Format: `[TOOL EXECUTION] Starting {tool_name}`

**2.3 Timing Setup**
- Record start timestamp for duration calculation
- High-precision timing using `Time.now`

### 3. After-Execution Features

**Requirements**:

**3.1 Duration Tracking**
- Calculate execution time in milliseconds
- Round to 2 decimal places
- Include in both logs and metadata

**3.2 Result Logging (End)**
- Log tool completion with duration
- Log success/failure status if result is a Hash
- Format: `[TOOL EXECUTION] Completed {tool_name} ({duration}ms)`

**3.3 Metadata Injection**
- Add execution metadata to tool result (if Hash)
- Metadata structure:
  ```ruby
  {
    _execution_metadata: {
      duration_ms: Float,
      tool_name: String,
      timestamp: String (ISO8601)
    }
  }
  ```
- Preserve original result structure

**3.4 Error Logging**
- Catch all StandardError exceptions during tool execution
- Log error message and backtrace (first 5 lines)
- Format: `[TOOL EXECUTION] Error in {tool_name}: {message}`
- Re-raise exception after logging

### 4. Configuration Options

**Requirement**: Allow DSL agents to configure tool execution behavior

**Configuration DSL**:
```ruby
class MyAgent < RAAF::DSL::Agent
  tool_execution do
    enable_validation true     # Validate parameters before execution
    enable_logging true        # Log execution start/end
    enable_metadata true       # Add execution metadata to results
    log_arguments true         # Include arguments in logs
    truncate_logs 100          # Truncate long log values
  end
end
```

**Defaults**:
- `enable_validation`: true
- `enable_logging`: true
- `enable_metadata`: true
- `log_arguments`: true
- `truncate_logs`: 100 (characters)

### 5. Backward Compatibility

**Requirements**:

**5.1 Existing DSL Tool Wrappers**
- Must continue to work without changes
- Interceptor should detect if tool already provides conveniences
- Avoid double-logging or double-validation

**5.2 Raw Core Tools**
- Must work immediately with DSL agents
- No changes required to core tool classes
- Full DSL benefits applied automatically

**5.3 Non-DSL Agents**
- Core RAAF agents (`RAAF::Agent`) unaffected
- Interceptor only active in `RAAF::DSL::Agent`

### 6. Migration Path

**Requirement**: Provide clear path for eliminating DSL tool wrappers

**Migration Steps**:
1. Identify DSL tool wrappers that only add conveniences (no business logic)
2. Test that raw core tools work with agent interceptor
3. Update agent classes to use raw core tools directly
4. Delete unnecessary DSL tool wrappers

**Example Migration**:
```ruby
# BEFORE: Custom DSL wrapper (200+ lines)
class RAAF::DSL::Tools::PerplexitySearch < Base
  # Validation, logging, metadata code
  def call(...)
    # Delegates to RAAF::Tools::PerplexityTool
  end
end

class MyAgent < RAAF::DSL::Agent
  uses_tool :perplexity_search  # Uses wrapper
end

# AFTER: Direct core tool usage (0 wrapper lines)
class MyAgent < RAAF::DSL::Agent
  uses_tool RAAF::Tools::PerplexityTool, as: :perplexity_search
end

# Agent interceptor provides validation, logging, metadata automatically
```

## User Stories

### Story 1: Agent Developer Using Raw Tool

**As a** RAAF DSL agent developer
**I want** to use raw core tools directly without creating wrappers
**So that** I can reduce boilerplate and avoid code duplication

**Acceptance Criteria**:
- Can declare `uses_tool RAAF::Tools::PerplexityTool` in agent
- Tool execution automatically gets validation
- Tool execution automatically gets logging
- Tool results automatically include metadata
- No custom wrapper code required

### Story 2: Framework Maintainer Reducing Duplication

**As a** RAAF framework maintainer
**I want** to centralize tool execution conveniences in the agent
**So that** updates to convenience features only require one change

**Acceptance Criteria**:
- All logging logic in one place (agent interceptor)
- All validation logic in one place (agent interceptor)
- All metadata logic in one place (agent interceptor)
- Can delete redundant DSL tool wrappers
- Updates to interceptor apply to all tools automatically

### Story 3: Tool Developer Creating Core Tools

**As a** RAAF tool developer
**I want** to create pure Ruby tools without DSL dependencies
**So that** tools work standalone and with DSL agents

**Acceptance Criteria**:
- Can create tool with only `call` method
- No need to inherit from DSL base classes
- No need to implement logging
- No need to implement validation
- Tool works with `RAAF::Agent` (standalone)
- Tool works with `RAAF::DSL::Agent` (with conveniences)

## Technical Constraints

### 1. Performance
- Interceptor overhead must be minimal (< 1ms)
- Duration tracking should not significantly impact execution time
- Logging should be optional and configurable

### 2. Thread Safety
- Interceptor must be thread-safe for concurrent tool execution
- Metadata injection must not cause race conditions

### 3. Memory
- Metadata should not significantly increase result object size
- Logged arguments should be truncatable for large payloads

### 4. Compatibility
- Must work with existing RAAF::Agent base class
- Must not break existing DSL tool wrappers
- Must not require changes to core tools

## Out of Scope

The following are **NOT** included in this specification:

1. **Tool Discovery/Registry**: Automatic finding of core tools by name
2. **Tool Definition Generation**: Auto-generating OpenAI function schemas
3. **Advanced Validation**: Complex schema validation beyond type checking
4. **Tool Caching**: Caching tool results
5. **Tool Chaining**: Automatic composition of multiple tools
6. **Async Tool Execution**: Background or parallel tool execution

These may be addressed in future specifications.

## Success Metrics

1. **Code Reduction**: Eliminate 200+ lines per DSL tool wrapper
2. **Maintainability**: Single update point for all tool execution conveniences
3. **Developer Experience**: Developers can use raw tools without wrappers
4. **Performance**: < 1ms interceptor overhead
5. **Adoption**: ProspectsRadar can migrate away from custom wrappers

## Dependencies

### Internal Dependencies
- `RAAF::Agent` base class (core agent implementation)
- `RAAF::FunctionTool` (tool wrapping mechanism)
- `RAAF.logger` (logging infrastructure)

### External Dependencies
- None - this is a refactoring of existing functionality

## Risk Analysis

### Risk 1: Breaking Changes to Existing Wrappers
**Likelihood**: Low
**Impact**: High
**Mitigation**: Extensive testing, feature flags for gradual rollout

### Risk 2: Performance Degradation
**Likelihood**: Low
**Impact**: Medium
**Mitigation**: Benchmark interceptor overhead, make logging optional

### Risk 3: Complex Migration Path
**Likelihood**: Medium
**Impact**: Medium
**Mitigation**: Clear migration guide, automated testing for both patterns

## Open Questions

1. Should validation be strict (fail) or lenient (warn) by default?
2. Should metadata be nested under `_execution_metadata` or top-level?
3. Should duration be tracked for all tools or only when logging enabled?
4. Should the interceptor support custom before/after hooks for advanced users?

## Appendix: Current DSL Tool Wrapper Example

```ruby
# Current implementation: RAAF::DSL::Tools::PerplexitySearch
# Location: dsl/lib/raaf/dsl/tools/perplexity_search.rb
# Lines: 200+

class PerplexitySearch < Base
  VALID_MODELS = %w[sonar sonar-pro].freeze

  def initialize(options = {})
    @perplexity_tool = RAAF::Tools::PerplexityTool.new(...)
    validate_options!
  end

  def call(query:, model: nil, ...)
    # Validation
    validate_options!

    # Logging (start)
    RAAF.logger.debug "[PERPLEXITY SEARCH] Executing..."
    start_time = Time.now

    # Delegation to core tool
    result = @perplexity_tool.call(...)

    # Duration tracking
    duration_ms = ((Time.now - start_time) * 1000).round(2)

    # Logging (end)
    RAAF.logger.debug "[PERPLEXITY SEARCH] Success (#{duration_ms}ms)"

    result
  end

  def validate_options!
    # Validation logic
  end

  def build_tool_definition
    # Tool schema generation
  end
end
```

**All of this becomes unnecessary** when conveniences move to agent interceptor.

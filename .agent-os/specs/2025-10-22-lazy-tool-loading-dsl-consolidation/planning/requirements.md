# Spec Requirements: Lazy Tool Loading and DSL Method Consolidation

## Initial Description
Currently, the RAAF DSL has redundant methods for tool configuration, and tool classes are eagerly loaded at class definition time. We want to consolidate these methods into a single `tool` method and implement lazy loading that resolves tool classes only when the agent is instantiated, not during class definition. This approach prevents loading errors in test suites and environments where tools may not be available yet.

## Requirements Discussion

### First Round Questions

**Q1:** When should the tool class be resolved - during the agent's `initialize` method or when `run` is first called?
**Answer:** During the agent's `initialize` method for immediate feedback

**Q2:** If a tool cannot be found during lazy resolution, should we fail immediately with a detailed error or skip the tool with a warning?
**Answer:** Fail immediately with a detailed error message

**Q3:** For the consolidated `tool` method, which patterns should we support? All three patterns (symbol for auto-discovery, direct class reference, options hash)?
**Answer:** Support all patterns - symbol for auto-discovery, direct class reference, options hash for inline configuration, and configuration block

**Q4:** The current implementation uses Thread-local storage for tool configurations. Should we keep this pattern or switch to instance variables?
**Answer:** Continue using Thread-local storage pattern for consistency with existing codebase

**Q5:** Should lazy loading behavior be consistent across all environments, or should we detect test vs production?
**Answer:** Always use lazy loading - no environment detection

**Q6:** How should we handle backward compatibility for code using the old methods?
**Answer:** No migration support - this is a breaking change, users must update their code manually

**Q7:** For testing, should we provide a way to mock/force eager loading for certain specs?
**Answer:** Mock the eager loading behavior within RSpec tests

**Q8:** Should resolved tool classes be cached per agent instance?
**Answer:** Yes, cache resolved tools per agent instance for performance

**Q9:** Can we modify ToolRegistry to provide better error messages when tools aren't found?
**Answer:** Yes, we can modify ToolRegistry to improve error messages

**Q10:** Should I research existing lazy-loading patterns in the codebase to ensure consistency?
**Answer:** Yes, research existing patterns for consistency

### Existing Code to Reference

**Codebase Research Findings:**

1. **Lazy Loading Patterns Found:**
   - `||=` pattern widely used for lazy initialization throughout DSL
   - Examples in `/raaf/dsl/lib/raaf-dsl.rb`:
     ```ruby
     @configuration ||= Configuration.new
     @prompt_configuration ||= PromptConfiguration.new
     ```
   - Thread-local storage pattern in Agent class:
     ```ruby
     Thread.current["raaf_dsl_tools_config_#{object_id}"] ||= []
     Thread.current["raaf_dsl_schema_config_#{object_id}"] ||= {}
     ```

2. **Current Tool Configuration Pattern:**
   - Tools are currently stored with deferred loading flags:
     ```ruby
     _tools_config << {
       name: tool_name,
       identifier: tool_name,
       options: options,
       tool_class: tool_class,  # Can be nil if deferred
       tool_type: tool_type,
       native: native_flag,
       deferred: resolution_deferred,  # Flag for lazy loading
       deferred_error: deferred_error   # Error message if not found
     }
     ```

3. **Existing Alias Methods to Remove:**
   - Line 370-371: `alias_method :uses_tool_legacy, :uses_tool` and `alias_method :uses_tool, :tool`
   - Multiple tool configuration methods exist:
     - `uses_tool` (line 318)
     - `uses_tools` (line 373)
     - `uses_tool_if` (line 385)
     - `uses_native_tool` (line 386)
     - `tool` (line 340)

4. **ToolRegistry Pattern:**
   - Located at `/raaf/lib/raaf/tool_registry.rb`
   - Auto-discovery in namespaces: `["Ai::Tools", "RAAF::Tools"]`
   - Error handling with NameError:
     ```ruby
     rescue NameError
       # Continue to next namespace
       next
     ```

5. **Error Handling Patterns:**
   - NameError used for missing constants
   - Multi-line error messages with context
   - Example from current implementation:
     ```ruby
     deferred_error = "Tool not found: #{tool_name}. " \
                      "Tried auto-discovery patterns and direct lookup."
     ```

### Follow-up Questions
None needed - all requirements have been clarified.

## Visual Assets

No visual assets provided.

## Requirements Summary

### Functional Requirements
- Consolidate all tool configuration methods (`uses_tool`, `uses_tools`, `uses_external_tool`, `uses_native_tool`, `uses_tool_if`) into single `tool` method
- Implement lazy loading of tool classes - store identifier and resolve during agent `initialize`
- Support all existing configuration patterns:
  - Symbol for auto-discovery (`:web_search`)
  - Direct class reference (`WebSearchTool`)
  - Inline options hash (`tool :search, max_results: 10`)
  - Configuration block syntax
- Cache resolved tool classes per agent instance to avoid repeated lookups
- Provide detailed error messages when tools cannot be found, including:
  - The tool identifier that failed
  - Namespaces searched
  - Suggestions for fixing the issue
- Remove all alias methods and deprecated tool configuration methods
- Maintain Thread-local storage pattern for consistency

### Non-Functional Requirements
- Performance: Lazy loading should have minimal overhead during agent instantiation
- Error messages must be clear and actionable
- No backward compatibility - clean break with clear migration path
- Testing: Must work correctly in RSpec test suites where tools may be mocked

### Reusability Opportunities
- Existing `ToolRegistry` class can be enhanced with better error messages
- Thread-local storage pattern already established in codebase
- Current deferred loading flags can be repurposed for lazy loading

### Scope Boundaries
**In Scope:**
- Consolidate tool configuration methods into single `tool` method
- Implement lazy loading in agent `initialize`
- Remove deprecated methods and aliases
- Enhance ToolRegistry error messages
- Cache resolved tools per instance

**Out of Scope:**
- Migration tools or backward compatibility shims
- Changes to how tools are executed
- Changes to tool validation or logging
- Modifications to pipeline or service classes
- Environment-specific behavior

### Technical Considerations
- Must maintain Thread-local storage pattern for tool configurations
- Tool resolution happens once per agent instance during initialization
- ToolRegistry can be modified to provide better error context
- No changes to existing tool execution interceptor functionality
- Breaking change requires major version bump or clear communication
# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-09-26-span-collector-extraction/spec.md

> Created: 2025-09-26
> Version: 1.0.0

## Test Coverage

### Unit Tests

**BaseCollector Simplified DSL with Common Attributes**
- Test base_attributes automatically provides component.type and component.class
- Test base_result_attributes automatically provides result.type and result.success
- Test custom_attributes uses span DSL for component-specific data
- Test custom_result_attributes uses result DSL for component-specific data
- Test collect_attributes merges base and custom attributes
- Test collect_result merges base and custom result attributes
- Test component_prefix generation from class names
- Test safe_value helper method for various data types
- Test error handling for invalid inputs and lambda execution errors

**AgentCollector (Core Agent)**
- Test simplified DSL span definitions for core agent data
- Test collection of simple attributes (name, model)
- Test lambda-based attribute extraction for tools and handoffs count
- Test complex conditional logic for workflow name extraction
- Test that no result.type or result.success defined (BaseCollector provides these)

**DslAgentCollector (DSL Agent)**
- Test DSL-specific attribute extraction (agent_name, _context_config)
- Test DSL-specific fields (temperature, context_size, has_tools, execution_mode)
- Test fallback handling for missing core agent methods
- Test that no result.type or result.success defined (BaseCollector provides these)

**ToolCollector**
- Test collection of tool name and method attributes
- Test agent context detection and collection
- Test result collection from tool execution
- Test handling of tools with and without agent context

**PipelineCollector**
- Test collection of pipeline structure and agent count
- Test flow description generation
- Test context fields collection
- Test result collection from pipeline execution

**JobCollector**
- Test collection of job class and queue information
- Test argument collection and sanitization
- Test result collection from job execution
- Test handling of non-ActiveJob components

**Naming-Based Discovery**
- Test collector selection for RAAF::Agent -> AgentCollector
- Test collector selection for RAAF::DSL::Agent -> DslAgentCollector
- Test collector selection for custom components by naming convention
- Test pattern-based fallback for Tool, Pipeline, Job suffixes
- Test ultimate fallback to BaseCollector for unknown types

### Integration Tests

**Traceable Module Integration**
- Test that Traceable uses collectors instead of component methods
- Test span data remains identical after collector migration
- Test error handling when collectors fail
- Test thread safety of collector selection

**End-to-End Span Collection**
- Test complete span collection process with all component types
- Test that no collection methods are called on business classes
- Test span attributes contain all expected data
- Test result attributes are collected correctly

**Backward Compatibility Removal**
- Test that removed methods no longer exist on business classes
- Test that existing code calling old methods fails appropriately
- Test that all span data is still collected through new system

### Mocking Requirements

- **Component Instances**: Mock Agent, Tool, Pipeline, Job instances with realistic data
- **Span Data**: Mock span creation and attribute setting
- **Registry Calls**: Mock collector selection to test specific collectors
- **Result Objects**: Mock various result types to test result collection
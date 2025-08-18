# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-08-17-unified-tool-architecture/spec.md

> Created: 2025-08-17
> Version: 1.0.0

## Test Coverage

### Unit Tests

**RAAF::Tool (Base Class)**
- Verifies `call` method raises NotImplementedError if not overridden
- Tests automatic name generation from class name
- Tests automatic description generation
- Tests parameter extraction from method signature
- Tests explicit configuration overrides conventions
- Tests `enabled?` method behavior
- Tests `to_function_tool` conversion for backward compatibility

**RAAF::ToolRegistry**
- Tests tool registration with name
- Tests tool lookup by name
- Tests tool resolution with multiple patterns
- Tests override behavior (user tools override RAAF tools)
- Tests namespace searching order
- Tests thread safety of registry operations
- Tests registry clearing for test isolation
- Tests listing tools by namespace

**RAAF::Tool::API**
- Tests HTTP method helpers (get, post, put, delete)
- Tests endpoint configuration
- Tests API key management
- Tests timeout handling
- Tests error handling and retries
- Tests response processing

**RAAF::Tool::Native**
- Tests native tool definition generation
- Tests that `call` is not available for native tools
- Tests configuration options specific to native tools
- Tests OpenAI-compatible format generation

**Convention Over Configuration Module**
- Tests automatic name generation patterns
- Tests description generation from class name
- Tests parameter schema extraction from method signature
- Tests YARD documentation extraction
- Tests type inference from parameter names

### Integration Tests

**DSL Integration**
- Tests `tool` method with symbol auto-discovery
- Tests `tool` method with direct class reference
- Tests `tool` method with options hash
- Tests `tool` method with configuration block
- Tests tool resolution in agent context
- Tests backward compatibility with `uses_tool`
- Tests multiple tool configurations in single agent

**Tool Discovery**
- Tests discovery of RAAF-provided tools
- Tests discovery of user-defined tools
- Tests user tools override RAAF tools
- Tests namespace searching (Ai::Tools::* then RAAF::Tools::*)
- Tests registry-based lookup
- Tests error handling for missing tools

**Agent Tool Integration**
- Tests tools are properly converted to FunctionTool instances
- Tests tools are available in agent.tools array
- Tests tool execution through agent runner
- Tests tool results are properly handled
- Tests disabled tools are filtered out

### Feature Tests

**End-to-End Tool Usage**
- Create custom tool with minimal code
- Register tool automatically
- Use tool in agent via DSL
- Execute agent with tool
- Verify tool was called and result processed

**Migration Compatibility**
- Test existing FunctionTool usage continues to work
- Test existing DSL patterns remain functional
- Test tool definitions maintain OpenAI compatibility
- Test gradual migration path

**Tool Override Scenario**
- Define RAAF tool with default behavior
- Define user tool with same name
- Verify user tool takes precedence
- Test explicit RAAF tool usage still possible

### Mocking Requirements

**External Services**
- Mock HTTP requests for API tools using WebMock
- Mock OpenAI API responses for native tools
- Mock environment variables for API keys

**Registry State**
- Clear registry between tests to ensure isolation
- Mock auto-registration for controlled testing
- Stub file system for tool discovery tests

## Test Organization

### File Structure
```
spec/
├── raaf/
│   ├── tool_spec.rb                    # Base class tests
│   ├── tool_registry_spec.rb           # Registry tests
│   ├── tool/
│   │   ├── api_spec.rb                # API tool tests
│   │   ├── native_spec.rb             # Native tool tests
│   │   └── function_spec.rb           # Function tool tests
│   └── convention_over_configuration_spec.rb
├── raaf/dsl/
│   ├── agent_tool_integration_spec.rb  # DSL integration
│   └── tool_discovery_spec.rb          # Discovery patterns
└── integration/
    ├── tool_migration_spec.rb          # Migration compatibility
    └── tool_override_spec.rb           # Override behavior
```

### Test Helpers

```ruby
# spec/support/tool_helpers.rb
module ToolHelpers
  def create_test_tool(name: "TestTool", &block)
    Class.new(RAAF::Tool) do
      define_singleton_method(:name) { name }
      define_method(:call, &block) if block_given?
    end
  end
  
  def with_clean_registry
    RAAF::ToolRegistry.clear!
    yield
  ensure
    RAAF::ToolRegistry.clear!
  end
end
```

### Performance Tests

**Registry Performance**
- Benchmark tool registration with 100+ tools
- Measure lookup time for various resolution patterns
- Test memory usage with large tool sets
- Verify no memory leaks in registration/deregistration

**Tool Execution Performance**
- Measure overhead of tool wrapper vs direct method call
- Test parameter extraction performance
- Benchmark schema generation caching
- Verify thread safety under concurrent load

## Coverage Requirements

- Minimum 95% code coverage for new code
- 100% coverage for public API methods
- Integration tests for all user-facing features
- Performance benchmarks for critical paths
- Documentation tests for all examples
# Specification: Lazy Tool Loading and DSL Consolidation

## Goal
Implement lazy tool class resolution at runtime and consolidate multiple tool configuration methods into a single `tool` method to eliminate Rails eager loading issues and reduce API confusion.

## User Stories
- As a Ruby developer, I want tools to be resolved when agents are instantiated so that Rails production environments don't fail with missing constant errors
- As a RAAF user, I want a single clear `tool` method instead of multiple confusing aliases so that the API is simpler and more intuitive
- As a developer, I want immediate error feedback when tools can't be resolved so that I can quickly identify and fix configuration issues
- As a framework maintainer, I want to remove deprecated methods and aliases so that the codebase is cleaner and easier to maintain

## Core Requirements
### Functional Requirements
- Tool class resolution deferred from class definition time to agent initialization time
- Single consolidated `tool` method replacing all existing variants
- Support for all configuration patterns (symbol, class, options hash, config block)
- Caching of resolved tools per agent instance for performance
- Detailed error messages with namespace search paths and suggestions
- Complete removal of backward compatibility aliases

### Non-Functional Requirements
- Performance: < 5ms overhead for tool resolution during agent initialization
- Error messages must include tool name, searched namespaces, and fix suggestions
- Thread-local storage pattern maintained for consistency
- Clean breaking change with no migration support
- RSpec test suites must work with mocked tool resolution

## Visual Design
No visual mockups provided for this internal framework feature.

## Reusable Components
### Existing Code to Leverage
- Components: `RAAF::ToolRegistry` - enhanced with better error messages
- Services: Thread-local storage pattern already established in `Agent` class
- Patterns: Lazy initialization with `||=` pattern used throughout DSL

### New Components Required
- **Lazy resolver mechanism** - Can't reuse existing eager resolution
- **Resolution caching system** - New per-instance cache needed
- **Enhanced error formatter** - Current errors lack detail

## Technical Approach
- Database: No database changes required
- API: Consolidate to single `tool` method with flexible signatures
- Frontend: N/A - internal framework feature
- Testing: Mock tool resolution in RSpec specs for isolation

## Out of Scope
- Migration tools or backward compatibility shims
- Changes to tool execution or validation
- Environment-specific behavior detection
- Modifications to pipeline or service classes
- Changes to tool execution interceptor

## Success Criteria
- Rails production environments load without tool resolution errors
- Single `tool` method handles all configuration patterns
- Tool resolution happens exactly once per agent instance
- Error messages clearly identify missing tools and suggest fixes
- All deprecated methods and aliases removed
- RSpec test suites continue to work with mocked tools

## API Design

### Consolidated Tool Method

```ruby
class MyAgent < RAAF::DSL::Agent
  # Symbol for auto-discovery
  tool :web_search

  # Direct class reference
  tool WebSearchTool

  # With options hash
  tool :tavily_search, max_results: 20, include_raw: true

  # With configuration block
  tool :api_tool do
    api_key ENV["API_KEY"]
    timeout 30
    retry_count 3
  end

  # Multiple tools at once
  tools :web_search, :file_search, :calculator
end
```

### Resolution Timing

Tools are resolved during agent initialization:

```ruby
class SearchAgent < RAAF::DSL::Agent
  tool :web_search  # Stored as symbol, not resolved yet
end

# Tool class resolution happens here
agent = SearchAgent.new  # Resolves :web_search → WebSearchTool class
```

## Implementation Details

### Tool Storage Format

```ruby
# At class definition time (stored but not resolved)
_tools_config << {
  identifier: :web_search,      # Original identifier
  tool_class: nil,              # Not resolved yet
  options: { max_results: 10 }, # Configuration options
  resolution_deferred: true,     # Flag for lazy loading
  config_block: proc { ... }     # Optional config block
}

# After resolution (during initialize)
@resolved_tools[identifier] = {
  identifier: :web_search,
  tool_class: WebSearchTool,    # Now resolved
  instance: tool_instance,       # Cached instance
  options: { max_results: 10 }
}
```

### Error Handling Specification

```ruby
# Enhanced error message format
class ToolResolutionError < StandardError
  def initialize(identifier, searched_namespaces, suggestions)
    message = <<~ERROR
      ❌ Tool not found: #{identifier}

      📂 Searched in:
        - Registry: RAAF::ToolRegistry
        - Namespaces: #{searched_namespaces.join(', ')}

      💡 Suggestions:
        #{suggestions.join("\n        ")}

      🔧 To fix:
        1. Ensure the tool class exists
        2. Register it: RAAF::ToolRegistry.register(:#{identifier}, #{identifier.to_s.camelize}Tool)
        3. Or use direct class reference: tool #{identifier.to_s.camelize}Tool
    ERROR

    super(message)
  end
end
```

### Caching Strategy

```ruby
class Agent
  def initialize(...)
    super
    @resolved_tools = {}  # Instance-level cache
    resolve_all_tools!    # One-time resolution
  end

  private

  def resolve_all_tools!
    self.class._tools_config.each do |config|
      next if config[:tool_class]  # Skip if already resolved

      identifier = config[:identifier]
      @resolved_tools[identifier] = resolve_tool(identifier, config)
    end
  end

  def resolve_tool(identifier, config)
    # Check cache first
    return @resolved_tools[identifier] if @resolved_tools[identifier]

    # Resolve and cache
    tool_class = RAAF::ToolRegistry.resolve(identifier)
    raise ToolResolutionError.new(...) unless tool_class

    @resolved_tools[identifier] = {
      tool_class: tool_class,
      instance: create_tool_instance(tool_class, config[:options])
    }
  end
end
```

## Testing Requirements

### RSpec Mock Support

```ruby
RSpec.describe MyAgent do
  before do
    # Mock tool resolution for tests
    allow(RAAF::ToolRegistry).to receive(:resolve)
      .with(:web_search)
      .and_return(MockWebSearchTool)
  end

  it "resolves tools during initialization" do
    agent = described_class.new
    expect(agent.tools).to include(instance_of(MockWebSearchTool))
  end

  it "raises detailed error for missing tools" do
    allow(RAAF::ToolRegistry).to receive(:resolve).and_return(nil)

    expect { described_class.new }.to raise_error(
      ToolResolutionError,
      /Tool not found: web_search/
    )
  end
end
```

### Performance Benchmarks

```ruby
# Benchmark tool resolution performance
RSpec.describe "Tool Resolution Performance" do
  it "resolves tools within 5ms" do
    agent_class = Class.new(RAAF::DSL::Agent) do
      tool :web_search
      tool :file_search
      tool :calculator
    end

    elapsed = Benchmark.realtime { agent_class.new }
    expect(elapsed * 1000).to be < 5  # Less than 5ms
  end

  it "caches resolved tools" do
    agent = MyAgent.new

    # Second access should be instant (from cache)
    elapsed = Benchmark.realtime { agent.send(:resolved_tool, :web_search) }
    expect(elapsed * 1000).to be < 0.1  # Less than 0.1ms
  end
end
```

## Breaking Changes Documentation

### Methods Being Removed

```ruby
# REMOVED - These will no longer work:
uses_tool :web_search           # Use: tool :web_search
uses_tools :search, :calculator # Use: tools :search, :calculator
uses_native_tool SomeTool       # Use: tool SomeTool
uses_tool_if condition, :tool   # Use: tool :tool if condition
uses_external_tool :api         # Use: tool :api
```

### Migration Guide

```ruby
# Before (old syntax)
class OldAgent < RAAF::DSL::Agent
  uses_tool :web_search
  uses_tools :file_search, :calculator
  uses_native_tool NativeTool
end

# After (new syntax)
class NewAgent < RAAF::DSL::Agent
  tool :web_search
  tools :file_search, :calculator
  tool NativeTool
end
```

## Spec Documentation

- Tasks: @.agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation/tasks.md
- Technical Specification: @.agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation/sub-specs/technical-spec.md
- Tests Specification: @.agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation/sub-specs/tests.md
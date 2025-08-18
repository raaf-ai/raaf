# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-08-17-unified-tool-architecture/spec.md

> Created: 2025-08-17
> Version: 1.0.0

## Technical Requirements

### Core Architecture

- **Unified Base Class**: Single `RAAF::Tool` base class that all tools inherit from
- **Auto-Registration**: Tools automatically register when class is defined
- **Name Resolution**: Convention-based name generation from class name
- **Override Mechanism**: User namespace (`Ai::Tools::*`) takes precedence over RAAF namespace
- **DSL Integration**: Tools created via DSL are thin wrappers around core `RAAF::Tool`
- **Backward Compatibility**: Existing `FunctionTool` continues to work

### Tool Discovery Patterns

- **Pattern 1**: Direct class reference - `tool WebSearchTool`
- **Pattern 2**: Symbol auto-discovery - `tool :web_search` finds `WebSearchTool`
- **Pattern 3**: Registry lookup - `tool :custom_name` finds registered tool
- **Pattern 4**: Namespace search - checks `Ai::Tools::*` then `RAAF::Tools::*`

### Parameter Schema Generation

- **Convention Over Configuration**: Auto-extract from method signature
- **DSL Override**: Allow explicit parameter definition via DSL
- **Type Inference**: Infer types from parameter names and defaults
- **Documentation**: Extract from method comments/YARD tags

## Approach Options

### Option A: Inheritance-Based Architecture
- All tools inherit from `RAAF::Tool`
- Auto-registration via `inherited` hook
- DSL methods defined in base class
- Pros: Simple, Ruby-idiomatic, easy migration
- Cons: Less flexible for complex scenarios

### Option B: Composition-Based Architecture (Selected)
- `RAAF::Tool` as base with minimal interface
- DSL tools compose base tool with configuration
- Registry pattern for discovery
- Pros: More flexible, cleaner separation, supports native tools
- Cons: Slightly more complex implementation

**Rationale:** Option B selected for better separation of concerns and ability to support both regular Ruby tools and OpenAI native tools through same interface.

## External Dependencies

No new external dependencies required. Uses existing RAAF gems:
- **raaf-core** - For `FunctionTool` compatibility
- **raaf-dsl** - For DSL integration
- **active_support** - Already used for inflections

## Implementation Architecture

### Class Hierarchy

```ruby
RAAF::Tool                          # New unified base class
├── RAAF::Tool::API                 # External API tools
│   ├── TavilySearchTool
│   ├── ScrapflyPageFetchTool
│   └── WebPageFetchTool
├── RAAF::Tool::Native              # OpenAI native tools  
│   ├── WebSearchTool
│   ├── CodeInterpreterTool
│   └── ImageGeneratorTool
└── RAAF::Tool::Function            # Regular function tools
    ├── CalculatorTool
    └── TextProcessorTool
```

### Tool Registry Structure

```ruby
RAAF::ToolRegistry
├── register(name, tool_class)      # Register tool
├── lookup(name)                    # Find tool by name
├── resolve(identifier)             # Smart resolution
├── list(namespace: nil)           # List available tools
└── clear!                          # Clear registry (testing)
```

### DSL Interface

```ruby
class MyAgent < RAAF::DSL::Agent
  # Single unified method for all tool types
  tool :tavily_search                    # Auto-discovery
  tool :web_search, region: "US"         # With options
  tool WebSearchTool                     # Direct class
  tool :custom do                        # Block configuration
    api_key ENV["CUSTOM_KEY"]
    timeout 30
  end
end
```

### Convention Patterns

```ruby
class AnalyzeSentimentTool < RAAF::Tool
  # Auto-generates:
  # - name: "analyze_sentiment"
  # - description: "Tool for analyze sentiment operations"
  # - parameters: extracted from call method
  
  def call(text:, language: "en")
    # Implementation
  end
end
```

## Migration Strategy

### Phase 1: Core Infrastructure
- Implement `RAAF::Tool` base class
- Create `RAAF::ToolRegistry` 
- Add auto-registration hooks
- Maintain `FunctionTool` compatibility

### Phase 2: DSL Integration
- Update `RAAF::DSL::Agent` tool methods
- Implement unified `tool` method
- Add resolution logic
- Create compatibility layer

### Phase 3: Tool Migration
- Migrate existing tools gradually
- Update documentation
- Add deprecation warnings
- Provide migration guide

## Configuration

### Debug Support

```bash
# Use existing RAAF debug infrastructure
RAAF_DEBUG_CATEGORIES=tools,registry  # Debug tool and registry operations
RAAF_LOG_LEVEL=debug                  # Enable debug logging
```

### Registry Configuration

```ruby
# Minimal configuration - mostly convention over configuration
RAAF::ToolRegistry.configure do |config|
  # Namespaces are searched in order (user tools first by default)
  config.namespaces = ["Ai::Tools", "RAAF::Tools"]
end
```

### Default Behaviors (No Configuration Needed)

- **Auto-Registration**: Tools automatically register when inheriting from `RAAF::Tool`
- **User Override**: User tools (Ai::Tools::*) always take precedence over RAAF tools
- **Name Generation**: Automatic from class name using conventions
- **Debug Logging**: Uses existing RAAF logger infrastructure

## Compatibility Considerations

### Existing Code Support

```ruby
# Old style - continues to work
agent.add_tool(FunctionTool.new(method(:search)))

# New DSL style - also works
class MyAgent < RAAF::DSL::Agent
  tool :search
end

# Both produce same result
```

### Tool Definition Compatibility

```ruby
# Old tool definition format
{
  type: "function",
  function: {
    name: "search",
    description: "Search tool",
    parameters: { ... }
  }
}

# New tools generate same format for API compatibility
```

## Performance Considerations

- **Lazy Loading**: Tools loaded only when needed
- **Registry Caching**: Class lookups cached after first resolution
- **Minimal Overhead**: Convention-based defaults avoid runtime computation
- **Thread Safety**: Registry operations are thread-safe
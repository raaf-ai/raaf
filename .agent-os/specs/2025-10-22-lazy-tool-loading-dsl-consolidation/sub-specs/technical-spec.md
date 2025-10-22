# Technical Specification: Lazy Tool Loading and DSL Consolidation

> Created: 2025-10-22
> Version: 1.0.0
> Spec: @.agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation/spec.md

## Overview

This document provides deep technical implementation details for the lazy tool loading and DSL consolidation feature. It covers class-level changes, resolution algorithms, caching strategies, and error handling mechanisms.

## Architecture Changes

### Current Architecture (Problematic)

```
Class Definition Time (Rails Boot)
┌─────────────────────────────────────┐
│ class MyAgent < Agent               │
│   uses_tool :web_search             │ ← Resolution happens HERE
│   └─> ToolRegistry.resolve()       │    (during class loading)
│       └─> const_get("WebSearchTool")│    (may fail if not loaded yet)
│           └─> ❌ NameError          │
│ end                                 │
└─────────────────────────────────────┘

Runtime (Agent Usage)
┌─────────────────────────────────────┐
│ agent = MyAgent.new                 │
│ # Tool already resolved (or failed) │
└─────────────────────────────────────┘
```

### New Architecture (Solution)

```
Class Definition Time (Rails Boot)
┌─────────────────────────────────────┐
│ class MyAgent < Agent               │
│   tool :web_search                  │ ← Store identifier only
│   └─> _tools_config << {           │    (no resolution)
│         identifier: :web_search,    │
│         options: {}                 │
│       }                             │
│ end                                 │
└─────────────────────────────────────┘

Runtime (Agent Instantiation)
┌─────────────────────────────────────┐
│ agent = MyAgent.new                 │ ← Resolution happens HERE
│ └─> initialize()                   │    (all classes loaded)
│     └─> resolve_all_tools!()       │
│         └─> ToolRegistry.resolve() │
│             └─> ✅ Success         │
└─────────────────────────────────────┘
```

## Component-Level Changes

### 1. AgentToolIntegration Module

**File:** `dsl/lib/raaf/dsl/agent_tool_integration.rb`

#### Current Implementation (lines 40-61)

```ruby
def tool(tool_identifier, **options, &block)
  # Handle block configuration
  if block_given?
    block_config = ToolConfigurationBuilder.new(&block).to_h
    options = options.merge(block_config)
  end

  # ❌ PROBLEM: Resolution happens NOW
  tool_class = RAAF::ToolRegistry.resolve(tool_identifier)

  unless tool_class
    raise ArgumentError, "Tool not found: #{tool_identifier}"
  end

  # Store tool configuration
  _tools_config << {
    identifier: tool_identifier,
    tool_class: tool_class,  # Already resolved
    options: options,
    native: tool_class.respond_to?(:native?) && tool_class.native?
  }
end
```

#### New Implementation (Deferred Resolution)

```ruby
def tool(tool_identifier, **options, &block)
  # Handle block configuration
  if block_given?
    block_config = ToolConfigurationBuilder.new(&block).to_h
    options = options.merge(block_config)
  end

  # ✅ SOLUTION: Store identifier, defer resolution
  _tools_config << {
    identifier: tool_identifier,
    tool_class: nil,              # Not resolved yet
    options: options,
    resolution_deferred: true,    # Flag for debugging
    config_block: block
  }
end

# Add convenience method for multiple tools
def tools(*tool_identifiers, **shared_options)
  tool_identifiers.each do |identifier|
    tool(identifier, **shared_options)
  end
end
```

#### Breaking Changes

```ruby
# REMOVE these backward compatibility aliases
# alias_method :uses_tool, :tool          # DELETED
# alias_method :uses_tools, :tools        # DELETED
# alias_method :uses_native_tool, :tool   # DELETED
```

### 2. Agent Class Initialization

**File:** `dsl/lib/raaf/dsl/agent.rb`

#### Current Implementation (lines 90-140)

```ruby
def initialize(context: nil, processing_params: {}, debug: nil, **kwargs)
  @debug_enabled = debug || Rails.env.development?
  @processing_params = processing_params

  # Context setup
  if context
    @context = build_context_from_param(context, @debug_enabled)
  elsif self.class.auto_context?
    @context = build_auto_context(kwargs, @debug_enabled)
  else
    @context = RAAF::DSL::ContextVariables.new({}, debug: @debug_enabled)
  end

  # ❌ Tools not resolved yet
  validate_context!
end
```

#### New Implementation (With Tool Resolution)

```ruby
def initialize(context: nil, processing_params: {}, debug: nil, validation_mode: false, parent_component: nil, **kwargs)
  @debug_enabled = debug || (defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.development?) || false
  @processing_params = processing_params
  @validation_mode = validation_mode
  @parent_component = parent_component

  # Initialize tool cache BEFORE context setup
  @resolved_tools = {}

  # Context setup (unchanged)
  if context
    @context = build_context_from_param(context, @debug_enabled)
  elsif self.class.auto_context?
    @context = build_auto_context(kwargs, @debug_enabled)
  else
    @context = RAAF::DSL::ContextVariables.new({}, debug: @debug_enabled)
  end

  # ✅ NEW: Resolve all tools during initialization
  resolve_all_tools! unless @validation_mode

  validate_context!
end

private

# New method for lazy tool resolution
def resolve_all_tools!
  start_time = Time.now

  self.class._tools_config.each do |config|
    identifier = config[:identifier]

    # Skip if already resolved (shouldn't happen but safe)
    next if @resolved_tools.key?(identifier)

    # Resolve tool class
    tool_class = resolve_tool_class(identifier)

    # Create and cache tool instance
    @resolved_tools[identifier] = {
      tool_class: tool_class,
      instance: create_tool_instance_from_config(tool_class, config)
    }
  end

  # Log performance if debug enabled
  elapsed_ms = ((Time.now - start_time) * 1000).round(2)
  log_debug("Tools resolved in #{elapsed_ms}ms") if @debug_enabled && elapsed_ms > 1.0
end

# Resolve tool class with enhanced error handling
def resolve_tool_class(identifier)
  # Direct class reference
  return identifier if identifier.is_a?(Class)

  # Symbol/string - use registry
  tool_class = RAAF::ToolRegistry.resolve(identifier)

  unless tool_class
    raise_tool_not_found_error(identifier)
  end

  tool_class
end

# Enhanced error with helpful details
def raise_tool_not_found_error(identifier)
  searched_namespaces = RAAF::ToolRegistry.namespaces

  suggestions = [
    "Verify the tool class is defined",
    "Check spelling: #{identifier.inspect}",
    "Ensure tool is in: #{searched_namespaces.join(' or ')}",
    "Register manually: RAAF::ToolRegistry.register(:#{identifier}, YourToolClass)",
    "Use direct reference: tool YourToolClass"
  ]

  error_message = <<~ERROR
    ❌ Tool Resolution Failed

    Agent: #{self.class.name}
    Tool: #{identifier.inspect}

    📂 Searched in:
      - Registry: #{RAAF::ToolRegistry.list.inspect}
      - Namespaces: #{searched_namespaces.join(', ')}

    💡 Suggestions:
      #{suggestions.map { |s| "• #{s}" }.join("\n      ")}

    🔧 Common fixes:
      1. Ensure tool class exists and is loaded
      2. Check tool namespace (Ai::Tools::* or RAAF::Tools::*)
      3. Use direct class reference if auto-discovery fails
  ERROR

  raise ArgumentError, error_message
end

# Create tool instance from configuration
def create_tool_instance_from_config(tool_class, config)
  options = config[:options] || {}

  # Instantiate tool
  tool_instance = tool_class.new(**options)

  # Apply configuration block if present
  if config[:config_block]
    tool_instance.instance_eval(&config[:config_block])
  end

  # Wrap in FunctionTool if needed
  if tool_instance.respond_to?(:to_function_tool)
    tool_instance.to_function_tool
  else
    tool_instance
  end
end
```

### 3. Tool Building Method

**File:** `dsl/lib/raaf/dsl/agent_tool_integration.rb` (lines 80-108)

#### Current Implementation

```ruby
def build_tools_from_config
  self.class._tools_config.map do |config|
    create_tool_instance_unified(config)
  end.compact
end
```

#### New Implementation (Using Cache)

```ruby
def build_tools_from_config
  # Return cached resolved tools
  @resolved_tools.values.map { |cached| cached[:instance] }.compact
end

# Alias for backward compatibility with internal code
alias_method :tools, :build_tools_from_config
```

### 4. ToolRegistry Enhancements

**File:** `lib/raaf/tool_registry.rb`

#### Current Implementation (lines 56-78)

```ruby
def lookup(identifier)
  # Direct class reference
  return identifier if identifier.is_a?(Class)

  # Try registry first
  registered = get(identifier)
  return registered if registered

  # Auto-discovery in namespaces
  auto_discover(identifier)
end
```

#### Enhanced Implementation (With Error Context)

```ruby
def lookup(identifier)
  # Direct class reference
  return identifier if identifier.is_a?(Class)

  # Try registry first
  registered = get(identifier)
  return registered if registered

  # Auto-discovery in namespaces
  auto_discover(identifier)
end

# New method: resolve with error tracking
def resolve_with_context(identifier)
  result = lookup(identifier)

  # Track resolution attempts for debugging
  log_resolution_attempt(identifier, result)

  result
end

private

def log_resolution_attempt(identifier, result)
  return unless respond_to?(:log_debug_tools)

  if result
    log_debug_tools("Tool resolved",
                   identifier: identifier,
                   class: result.name)
  else
    log_debug_tools("Tool not found",
                   identifier: identifier,
                   searched_namespaces: @namespaces)
  end
end
```

## Thread-Local Storage Pattern

### Current Pattern (Maintained)

```ruby
# Agent class-level configuration storage
def _tools_config
  Thread.current["raaf_dsl_tools_config_#{object_id}"] ||= []
end

def _tools_config=(value)
  Thread.current["raaf_dsl_tools_config_#{object_id}"] = value
end
```

**Why Thread-Local?**
- Prevents cross-thread contamination in multi-threaded Rails apps
- Each thread gets its own configuration storage
- Safe for concurrent agent class definitions
- Pattern already established throughout RAAF DSL

**Maintained in New Implementation:**
- No changes to storage mechanism
- Only changes to what's stored (identifier vs. resolved class)
- Instance-level cache uses standard instance variables

## Caching Strategy

### Cache Structure

```ruby
# Instance variable in Agent class
@resolved_tools = {
  :web_search => {
    tool_class: WebSearchTool,
    instance: #<WebSearchTool:0x00007f8b1c8a4b10>
  },
  :file_search => {
    tool_class: FileSearchTool,
    instance: #<FileSearchTool:0x00007f8b1c8a4c20>
  }
}
```

### Cache Lifecycle

1. **Creation:** During `initialize` method
2. **Population:** First call to `resolve_all_tools!`
3. **Access:** Via `build_tools_from_config` or `tools` method
4. **Lifetime:** Per agent instance (garbage collected with agent)
5. **Scope:** Not shared between instances

### Cache Performance

```ruby
# Benchmark cache effectiveness
def test_cache_performance
  agent = MyAgent.new  # Resolution + caching

  # First access (from cache)
  Benchmark.realtime { agent.tools }  # < 0.1ms

  # Subsequent accesses (same cache)
  10.times do
    Benchmark.realtime { agent.tools }  # < 0.01ms each
  end
end
```

## Error Handling Specification

### Error Types

```ruby
# 1. Tool Not Found Error
ArgumentError: "❌ Tool Resolution Failed\n..."

# 2. Tool Instantiation Error
RuntimeError: "Tool instantiation failed for #{identifier}"

# 3. Configuration Block Error
ArgumentError: "Invalid configuration block for #{identifier}"
```

### Error Message Format

```ruby
ERROR_TEMPLATE = <<~ERROR
  ❌ Tool Resolution Failed

  Agent: %{agent_class}
  Tool: %{identifier}

  📂 Searched in:
    - Registry: %{registry_tools}
    - Namespaces: %{namespaces}

  💡 Suggestions:
    %{suggestions}

  🔧 Common fixes:
    1. Ensure tool class exists and is loaded
    2. Check tool namespace (Ai::Tools::* or RAAF::Tools::*)
    3. Use direct class reference if auto-discovery fails
ERROR
```

### Error Context Data

```ruby
{
  agent_class: self.class.name,
  identifier: identifier.inspect,
  registry_tools: RAAF::ToolRegistry.list.inspect,
  namespaces: RAAF::ToolRegistry.namespaces.join(', '),
  suggestions: [
    "Verify spelling",
    "Check namespace",
    "Register manually",
    "Use direct reference"
  ].map { |s| "• #{s}" }.join("\n    ")
}
```

## Performance Requirements

### Benchmarks

| Operation | Current | Target | Acceptable |
|-----------|---------|--------|------------|
| Tool resolution (3 tools) | N/A | < 5ms | < 10ms |
| Cache access | N/A | < 0.1ms | < 0.5ms |
| Agent initialization | ~1ms | < 6ms | < 15ms |

### Performance Testing

```ruby
RSpec.describe "Tool Resolution Performance" do
  let(:agent_class) do
    Class.new(RAAF::DSL::Agent) do
      tool :web_search
      tool :file_search
      tool :calculator
    end
  end

  it "resolves 3 tools within 5ms" do
    elapsed = Benchmark.realtime { agent_class.new }
    expect(elapsed * 1000).to be < 5
  end

  it "caches tools for instant access" do
    agent = agent_class.new

    elapsed = Benchmark.realtime { agent.tools }
    expect(elapsed * 1000).to be < 0.1
  end
end
```

## Migration Strategy

### Breaking Changes

```ruby
# These methods will be REMOVED:
# - uses_tool (use: tool)
# - uses_tools (use: tools)
# - uses_native_tool (use: tool)
```

### No Migration Support

- No deprecation warnings
- No backward compatibility shims
- Clean break for v2.0 release
- Update documentation only

### User Migration Path

```ruby
# Before
class MyAgent < RAAF::DSL::Agent
  uses_tool :web_search
  uses_tools :file_search, :calculator
  uses_native_tool CustomTool
end

# After
class MyAgent < RAAF::DSL::Agent
  tool :web_search
  tools :file_search, :calculator
  tool CustomTool
end
```

## Testing Requirements

See: @.agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation/sub-specs/tests.md

## Implementation Checklist

- [ ] Update `AgentToolIntegration#tool` to store identifiers only
- [ ] Remove `uses_tool`, `uses_tools`, `uses_native_tool` aliases
- [ ] Add `resolve_all_tools!` method to `Agent#initialize`
- [ ] Implement `@resolved_tools` instance cache
- [ ] Add enhanced error handling with context
- [ ] Update `build_tools_from_config` to use cache
- [ ] Add `ToolRegistry.resolve_with_context` method
- [ ] Write RSpec tests for all scenarios
- [ ] Add performance benchmarks
- [ ] Update documentation

## References

- Main Spec: @.agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation/spec.md
- Tasks List: @.agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation/tasks.md
- Tests Spec: @.agent-os/specs/2025-10-22-lazy-tool-loading-dsl-consolidation/sub-specs/tests.md

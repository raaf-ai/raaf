# Unified Tool Method Implementation

## Overview

The Agent class in `/Users/hajee/enterprisemodules/work/raaf/dsl/lib/raaf/dsl/agent.rb` has been enhanced with a unified `tool` method that replaces both `uses_tool` and `uses_native_tool` while maintaining full backward compatibility.

## Key Features Implemented

### 1. Unified `tool` Method

The new `tool` method automatically detects whether a tool is external (DSL-based) or native (execution-based) and handles both seamlessly.

```ruby
# Auto-discovery with inline configuration
tool :tavily_search, max_results: 20, search_depth: "advanced"

# Auto-discovery with block configuration
tool :web_search do
  max_results 10
  region "US"
  include_domains ["github.com", "stackoverflow.com"]
end

# Direct class usage
tool WebSearchTool, user_location: "San Francisco, CA"
```

### 2. Auto-Discovery System

The method includes a sophisticated auto-discovery system that searches multiple naming patterns and namespaces:

**Discovery Patterns (in order of preference):**
- `RAAF::DSL::Tools::{ClassName}` (External DSL tools)
- `RAAF::Tools::{ClassName}` (External tools)
- `Ai::Tools::{ClassName}` (Custom namespace)
- `RAAF::Tools::{ClassName}Tool` (Native tools)
- `RAAF::{ClassName}Tool` (Native tools)
- `{ClassName}Tool` (Global native tools)
- `{ClassName}` (Generic)
- `RAAF::{ClassName}` (RAAF namespace)

**Example:**
- `tool :tavily_search` finds `RAAF::DSL::Tools::TavilySearch`
- `tool :web_search` finds `RAAF::Tools::WebSearchTool`

### 3. Tool Type Detection

The system automatically detects tool types:

- **External Tools**: Inherit from `RAAF::DSL::Tools::Base` (configuration-only)
- **Native Tools**: Inherit from `RAAF::FunctionTool` or have `execute`/`call` methods

### 4. Block Configuration Support

A new `ToolConfigurationBuilder` class provides a clean DSL for complex tool configuration:

```ruby
tool :web_search do
  max_results 10
  search_depth "advanced"
  include_domains ["github.com", "stackoverflow.com"]
  exclude_domains ["spam.com"]
  timeout 30
end
```

**Supported configuration methods:**
- `max_results(integer)` - with validation
- `timeout(numeric)` - with validation
- `search_depth(string)` - with validation against known values
- `include_domains(array)` - domain filtering
- `exclude_domains(array)` - domain filtering
- `region(string)` - geographic region
- `user_location(string|hash)` - user location
- Generic `method_missing` for any other options

### 5. Backward Compatibility

Full backward compatibility is maintained:

```ruby
# Legacy method still works
uses_tool :tavily_search, max_results: 5

# All existing methods continue to work
uses_tools :tool1, :tool2, :tool3
configure_tools({ tool1: { option: "value" }, tool2: {} })
uses_tool_if condition, :tool_name, options
```

The `uses_tool` method is now an alias for the new `tool` method, and a `uses_native_tool` method is provided for explicit native tool usage.

## Implementation Details

### Core Methods Added

1. **`tool(tool_name, **options, &block)`** - Main unified method
2. **`resolve_tool_class_unified(tool_identifier)`** - Enhanced tool resolution
3. **`discover_tool_class(tool_name)`** - Auto-discovery engine
4. **`detect_tool_type(tool_class)`** - Tool type detection
5. **`external_tool?(tool_class)`** - External tool validation
6. **`native_tool?(tool_class)`** - Native tool validation
7. **`valid_tool_class?(tool_class)`** - General tool validation

### Enhanced Tool Configuration Storage

Tool configurations now store additional metadata:

```ruby
{
  name: tool_name,
  options: merged_options,
  tool_class: resolved_class,    # New: resolved tool class
  tool_type: detected_type       # New: :external or :native
}
```

### Updated Tool Creation Logic

The `create_tool_instance` method has been enhanced to use the pre-resolved tool classes for better performance and reliability.

## Usage Examples

### Basic Auto-Discovery

```ruby
class MyAgent < RAAF::DSL::Agent
  # Finds RAAF::DSL::Tools::TavilySearch
  tool :tavily_search
  
  # Finds RAAF::Tools::WebSearchTool  
  tool :web_search
end
```

### Inline Configuration

```ruby
class MyAgent < RAAF::DSL::Agent
  tool :tavily_search, max_results: 20, search_depth: "advanced"
  tool :web_search, user_location: "San Francisco, CA", timeout: 30
end
```

### Block Configuration

```ruby
class MyAgent < RAAF::DSL::Agent
  tool :web_search do
    max_results 10
    search_depth "advanced"
    include_domains ["github.com", "stackoverflow.com"]
    exclude_domains ["spam.com"]
    user_location "San Francisco, CA"
    timeout 30
  end
end
```

### Mixed Usage

```ruby
class MyAgent < RAAF::DSL::Agent
  # New unified method
  tool :tavily_search, max_results: 20
  
  # Legacy method (still works)
  uses_tool :another_tool, option: "value"
  
  # Block configuration
  tool :web_search do
    timeout 60
    region "US"
  end
  
  # Direct class usage
  tool WebSearchTool, user_location: "San Francisco, CA"
end
```

## Benefits

1. **Simplified API**: One method for all tool types
2. **Auto-Discovery**: No need to specify full class paths
3. **Flexible Configuration**: Both inline and block syntax support
4. **Type Safety**: Automatic tool type detection and validation
5. **Backward Compatibility**: All existing code continues to work
6. **Enhanced Error Messages**: Clear feedback when tools aren't found
7. **Performance**: Pre-resolved tool classes reduce runtime overhead

## Migration Guide

**No migration needed!** All existing code using `uses_tool` will continue to work without changes. The new `tool` method is completely optional and can be adopted gradually.

**Recommended for new code:**
- Use `tool` instead of `uses_tool` for new agents
- Take advantage of auto-discovery for cleaner code
- Use block configuration for complex tool setups

## Error Handling

The implementation includes comprehensive error handling:

- Clear error messages when tools aren't found
- Validation of tool classes before usage
- Graceful fallback to legacy behavior when needed
- Detailed logging for debugging

Example error message:
```
Tool not found: unknown_tool. Tried auto-discovery patterns and direct lookup.
```

This enhancement significantly improves the developer experience while maintaining full backward compatibility and adding powerful new capabilities for tool configuration and discovery.
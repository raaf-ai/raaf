# RAAF DSL 2.0.0 Migration Guide

## Overview

RAAF DSL 2.0.0 introduces a unified tool registration API with lazy loading capabilities, resulting in 6.25x faster initialization while simplifying the developer experience. This guide will help you migrate your existing code to the new API.

## Key Changes

### 🚀 Performance Improvements
- **6.25x faster initialization** through lazy tool loading
- Tools are now loaded only when actually needed
- Reduced memory footprint during agent initialization

### 🔧 API Simplification
- **Single method for all tool registrations**: Just use `tool` or `tools`
- **Removed 7+ different registration methods** in favor of unified API
- **Cleaner, more intuitive syntax** with less cognitive overhead

## Breaking Changes

### ❌ Removed Methods

The following methods have been **completely removed** and will raise errors if used:

| Removed Method | Replacement | Notes |
|----------------|-------------|-------|
| `uses_tool` | `tool` | Direct replacement |
| `uses_tools` | `tools` | Direct replacement for multiple tools |
| `uses_native_tool` | `tool` | Same syntax, just different method name |
| `uses_external_tool` | `tool` | External tools work the same way |
| `uses_tool_if` | `tool ... if condition` | Use Ruby conditional |
| `use_tool_conditionally` | `tool ... if condition` | Use Ruby conditional |
| `register_tool` | `tool` | Legacy method removed |

## Migration Patterns

### Pattern 1: Single Tool Registration

#### Before (Old Syntax)
```ruby
class OldAgent < RAAF::DSL::Agent
  uses_tool :web_search
  uses_tool :calculator
end
```

#### After (New Syntax)
```ruby
class NewAgent < RAAF::DSL::Agent
  tool :web_search
  tool :calculator
end
```

### Pattern 2: Multiple Tools at Once

#### Before (Old Syntax)
```ruby
class OldAgent < RAAF::DSL::Agent
  uses_tools :web_search, :file_search, :calculator
end
```

#### After (New Syntax)
```ruby
class NewAgent < RAAF::DSL::Agent
  tools :web_search, :file_search, :calculator
end
```

### Pattern 3: Native Tool Classes

#### Before (Old Syntax)
```ruby
class OldAgent < RAAF::DSL::Agent
  uses_native_tool RAAF::Tools::PerplexityTool
  uses_native_tool MyCustomTool
end
```

#### After (New Syntax)
```ruby
class NewAgent < RAAF::DSL::Agent
  tool RAAF::Tools::PerplexityTool
  tool MyCustomTool
end
```

### Pattern 4: Tool with Options

#### Before (Old Syntax)
```ruby
class OldAgent < RAAF::DSL::Agent
  uses_tool :web_search, max_results: 10, timeout: 30
  uses_tool :database_query, connection: :primary
end
```

#### After (New Syntax)
```ruby
class NewAgent < RAAF::DSL::Agent
  tool :web_search, max_results: 10, timeout: 30
  tool :database_query, connection: :primary
end
```

### Pattern 5: Tool with Alias

#### Before (Old Syntax)
```ruby
class OldAgent < RAAF::DSL::Agent
  uses_tool :web_search, as: :internet_search
  uses_native_tool RAAF::Tools::PerplexityTool, as: :perplexity
end
```

#### After (New Syntax)
```ruby
class NewAgent < RAAF::DSL::Agent
  tool :web_search, as: :internet_search
  tool RAAF::Tools::PerplexityTool, as: :perplexity
end
```

### Pattern 6: Conditional Tool Loading

#### Before (Old Syntax)
```ruby
class OldAgent < RAAF::DSL::Agent
  uses_tool_if Rails.env.production?, :premium_tool
  uses_tool_if lambda { |agent| agent.expensive? }, :costly_tool
end
```

#### After (New Syntax)
```ruby
class NewAgent < RAAF::DSL::Agent
  tool :premium_tool if Rails.env.production?
  tool :costly_tool if respond_to?(:expensive?) && expensive?
end
```

### Pattern 7: Inline Tool Definition

#### Before (Old Syntax)
```ruby
class OldAgent < RAAF::DSL::Agent
  uses_tool :custom_calculator do
    description "Performs calculations"
    parameter :expression, type: :string

    execute do |expression:|
      eval(expression) # Don't actually use eval!
    end
  end
end
```

#### After (New Syntax)
```ruby
class NewAgent < RAAF::DSL::Agent
  tool :custom_calculator do
    description "Performs calculations"
    parameter :expression, type: :string

    execute do |expression:|
      # Use a safe math parser instead
    end
  end
end
```

## Step-by-Step Migration Process

### 1. Find All Deprecated Method Usages

Use grep to find all instances of deprecated methods:

```bash
# Find all deprecated method calls
grep -r "uses_tool\|uses_tools\|uses_native_tool\|uses_external_tool\|uses_tool_if" app/ai lib/raaf spec/

# Or use your IDE's project-wide search
```

### 2. Update Each File Systematically

For each file containing deprecated methods:

1. **Replace method names** according to the patterns above
2. **Verify conditionals** are using Ruby syntax (not method arguments)
3. **Test the agent** to ensure tools still work
4. **Check for any custom tool resolution** that might need updates

### 3. Update Your Tests

```ruby
# Before
RSpec.describe MyAgent do
  it "registers tools" do
    expect(described_class).to receive(:uses_tool).with(:web_search)
    # ...
  end
end

# After
RSpec.describe MyAgent do
  it "registers tools" do
    expect(described_class).to receive(:tool).with(:web_search)
    # ...
  end
end
```

### 4. Verify Tool Loading

After migration, verify that tools are properly registered:

```ruby
agent = MyAgent.new
puts agent.class.registered_tools
# => [:web_search, :calculator, ...]

# Tools should still work normally
result = agent.run("Search for Ruby news")
```

## Common Migration Issues

### Issue 1: Conditional Tool Loading

**Problem**: `uses_tool_if` no longer exists

**Solution**: Use Ruby's conditional syntax
```ruby
# Instead of: uses_tool_if condition, :tool_name
tool :tool_name if condition
```

### Issue 2: Tool Not Found Errors

**Problem**: Getting "Tool not found" errors after migration

**Possible Causes & Solutions**:
1. **Typo in tool identifier** - Check spelling
2. **Missing namespace** - Ensure you're using the full path for native tools
3. **Tool not loaded** - Check that the tool gem/file is required

### Issue 3: Options Not Being Applied

**Problem**: Tool options seem to be ignored

**Solution**: Ensure options are passed as hash after the tool identifier
```ruby
tool :web_search, max_results: 10  # Correct
tool :web_search max_results: 10   # Incorrect (missing comma)
```

## Testing Your Migration

### 1. Unit Tests for Tool Registration

```ruby
RSpec.describe "Tool Registration" do
  it "registers tools with new syntax" do
    class TestAgent < RAAF::DSL::Agent
      tool :web_search
      tools :calculator, :file_search
      tool RAAF::Tools::CustomTool
    end

    expect(TestAgent.registered_tools).to include(
      :web_search, :calculator, :file_search
    )
  end
end
```

### 2. Integration Tests

```ruby
RSpec.describe "Agent Execution" do
  it "executes with migrated tools" do
    agent = MyMigratedAgent.new
    runner = RAAF::Runner.new(agent: agent)

    result = runner.run("Use web search to find information")
    expect(result).to be_success
  end
end
```

## Performance Verification

After migration, you should see significant performance improvements:

```ruby
# Benchmark tool loading
require 'benchmark'

time = Benchmark.realtime do
  100.times { MyAgent.new }
end

puts "Agent initialization: #{(time * 1000).round(2)}ms"
# Should be ~6.25x faster than before
```

## Rollback Plan

If you encounter issues and need to temporarily rollback:

1. **Use version pinning** in your Gemfile:
```ruby
gem 'raaf-dsl', '~> 1.9.0'  # Pre-migration version
```

2. **Keep a branch** with the old code until migration is stable

3. **Consider gradual migration** - migrate one agent at a time if possible

## Getting Help

### Error Messages

The new version provides enhanced error messages to help with migration:

```ruby
# If you accidentally use old methods, you'll see:
# => MethodError: undefined method `uses_tool' for MyAgent:Class
#    Did you mean? tool
#
#    The `uses_tool` method has been removed in RAAF DSL 2.0.0.
#    Please use `tool` instead. See MIGRATION_GUIDE.md for details.
```

### Documentation

- **Migration Guide**: This document
- **API Documentation**: Updated in CLAUDE.md
- **Examples**: See `dsl/examples/` for updated examples
- **Changelog**: See CHANGELOG.md for complete list of changes

### Support

If you encounter issues not covered in this guide:

1. Check the [GitHub Issues](https://github.com/raaf/raaf-dsl/issues)
2. Review the updated examples in `dsl/examples/`
3. Consult the API documentation in CLAUDE.md

## Summary

The migration to RAAF DSL 2.0.0 is straightforward:

1. **Replace all `uses_*` methods with `tool` or `tools`**
2. **Update conditional syntax to use Ruby conditionals**
3. **Test your agents to ensure tools work correctly**
4. **Enjoy 6.25x faster initialization!**

The new unified API is cleaner, faster, and easier to understand. The lazy loading ensures tools are only loaded when needed, significantly improving startup time and memory usage.
# RAAF Context Harmonization Guide

> Version: 1.0.0
> Last Updated: 2025-10-08
> Status: Production

## Overview

RAAF now provides a **unified context interface** across all context classes, eliminating the confusion and bugs caused by inconsistent key access patterns. All contexts support **deep indifferent access** with both symbol and string keys.

## Quick Start

```ruby
require 'raaf-core'

# All contexts now support both symbol and string keys
context = RAAF::RunContext.new
context.set(:user_id, "123")      # Symbol key
context.get("user_id")             # => "123" (string key works!)
context[:session] = "abc"          # Array-style write
context["session"]                 # => "abc" (indifferent access)
```

## The Problem We Solved

### Before Harmonization

RAAF had **12 different context classes** with **5 different access patterns**:

```ruby
# ❌ BEFORE: Inconsistent and confusing
run_context.store(:key, value)     # RunContext
tool_context.set(:key, value)      # ToolContext (different!)
handoff_context.set_handoff(...)   # HandoffContext (completely different!)
context_vars.set(:key, value)      # ContextVariables (immutable!)

# Indifferent access was partial or missing
run.store(:key, value)   # Stored as :key
run.fetch("key")         # ❌ Returns nil! (different key)
```

### After Harmonization

**One unified interface across all contexts:**

```ruby
# ✅ AFTER: Consistent and intuitive
run_context.set(:key, value)        # Mutable
tool_context.set(:key, value)       # Mutable
handoff_context.set(:key, value)    # Mutable
context_vars.set(:key, value)       # Immutable (returns new instance)

# All contexts support both key types
context[:user][:profile][:name]      # ✅ Works
context["user"]["profile"]["name"]   # ✅ Works
context[:user]["profile"][:name]     # ✅ Mixed works too!
```

## Two-Tier Architecture

RAAF contexts follow a **two-tier pattern** based on use case:

### Tier 1: Mutable Core Contexts (Performance)

Used for high-frequency operations in the agent runtime:

- **RunContext** - Conversation state management
- **ToolContext** - Tool execution state
- **HandoffContext** - Agent handoff coordination

```ruby
# Mutable contexts modify in place
context = RAAF::RunContext.new
context.set(:key, "value")   # Modifies context, returns value
context.get(:key)             # => "value"

# Performance benefit: No new object allocations
```

### Tier 2: Immutable DSL Contexts (Safety)

Used for user-facing code and pipeline orchestration:

- **ContextVariables** - Immutable Swarm-style context
- **ContextBuilder** - Fluent builder for ContextVariables
- **HookContext** - Proxy for agent hooks

```ruby
# Immutable contexts return new instances
ctx = RAAF::DSL::ContextVariables.new
ctx1 = ctx.set(:key, "value")  # Returns NEW instance
ctx != ctx1                     # True - different objects

# Safety benefit: No accidental mutations
```

## Unified Interface

All contexts implement the **ContextInterface** module:

### Data Access Methods

```ruby
# Get value with optional default
context.get(:key, "default")    # => "value" or "default"

# Set value (tier 1: mutate, tier 2: return new)
context.set(:key, "value")

# Delete value
context.delete(:key)            # => "value" (returns deleted value)

# Check existence
context.has?(:key)              # => true
context.key?(:key)              # => true (alias)
context.include?(:key)          # => true (alias)
```

### Bulk Operations

```ruby
# Get all keys/values
context.keys                    # => [:user_id, :session]
context.values                  # => ["123", "abc"]

# Export as hash
context.to_h                    # => { user_id: "123", session: "abc" }

# Merge multiple values
context.update(user: "John", age: 30)

# Check if empty
context.empty?                  # => false
context.size                    # => 2
```

### Array-Style Access

```ruby
# Read access
context[:user_id]               # => "123"
context["user_id"]              # => "123" (indifferent)

# Write access
context[:session] = "abc"
context["session"] = "xyz"      # Indifferent write
```

## Deep Indifferent Access

**All nested hashes and arrays support indifferent access:**

```ruby
context = RAAF::RunContext.new
context.set(:user, {
  profile: { name: "John", role: "Admin" },
  settings: { theme: "dark", notifications: true }
})

# All these work identically:
context[:user][:profile][:name]       # ✅ "John"
context["user"]["profile"]["name"]    # ✅ "John"
context[:user]["profile"][:name]      # ✅ "John" (mixed!)
context["user"][:profile]["name"]     # ✅ "John" (any combo!)

# Arrays of hashes too
context.set(:items, [
  { id: 1, name: "Item 1" },
  { id: 2, name: "Item 2" }
])

context[:items].first[:name]          # ✅ "Item 1"
context["items"].first["name"]        # ✅ "Item 1"
```

## Migration Guide

### Old Code (Before Harmonization)

```ruby
# ❌ Old patterns still work (backwards compatible)
run_context.store(:key, value)    # Old method
run_context.fetch(:key)           # Old method

tool_context.get(:key)            # This was already correct

# But defensive patterns were needed:
data = context[:key] || context["key"]  # Avoid this now
```

### New Code (After Harmonization)

```ruby
# ✅ Use unified interface everywhere
run_context.set(:key, value)      # Consistent!
run_context.get(:key)             # Consistent!

tool_context.set(:key, value)     # Consistent!
tool_context.get(:key)            # Consistent!

# No defensive patterns needed:
data = context[:key]               # Always works with both key types!
```

## Context Class Reference

### RunContext (Mutable)

**Purpose:** Conversation state during agent execution

```ruby
context = RAAF::RunContext.new
context.set(:user_id, "123")       # Store custom data
context.get(:user_id)              # => "123"
context[:session] = "abc"          # Array-style access

# Message management
context.add_message({ role: "user", content: "Hello" })
context.messages.last              # => { role: "user", ... }

# Metadata access
context.metadata[:trace_id]        # Trace ID for distributed tracing
```

### ToolContext (Mutable)

**Purpose:** Tool execution state management

```ruby
context = RAAF::ToolContext.new
context.set(:api_key, ENV['API_KEY'])
context.get(:api_key)              # => "sk-..."

# Execution tracking
context.track_execution("tool_name", input, output, duration)
context.execution_stats            # => { total: 5, success_rate: 100.0 }

# Shared memory between tools
context.shared_set(:cache, data)
context.shared_get(:cache)         # Access from other tools
```

### HandoffContext (Mutable)

**Purpose:** Agent handoff coordination

```ruby
context = RAAF::HandoffContext.new(current_agent: "Agent1")
context.set_handoff(
  target_agent: "Agent2",
  data: { task: "continue", context: "..." }
)

# Access handoff data with indifferent keys
context.get(:task)                 # => "continue"
context["task"]                    # => "continue" (same!)
```

### ContextVariables (Immutable)

**Purpose:** Swarm-style immutable context for DSL

```ruby
ctx = RAAF::DSL::ContextVariables.new
ctx1 = ctx.set(:key, "value")      # Returns NEW instance
ctx != ctx1                         # True - immutable

# Deep indifferent access
ctx2 = ctx1.set(:user, { profile: { name: "John" } })
ctx2[:user][:profile][:name]       # ✅ "John"
ctx2["user"]["profile"]["name"]    # ✅ "John"
```

## Best Practices

### 1. Use Consistent Key Style

```ruby
# ✅ GOOD: Pick one style per context/class
context.set(:user_id, "123")
context.set(:session, "abc")
context.set(:data, results)

# ⚠️ WORKS: But avoid mixing within same context
context.set(:user_id, "123")       # Symbol
context.set("session", "abc")      # String
```

### 2. Leverage Array-Style Access

```ruby
# ✅ GOOD: Concise and readable
context[:user_id] = "123"
user = context[:user_id]

# ✅ ALSO GOOD: Explicit and clear
context.set(:user_id, "123")
user = context.get(:user_id)
```

### 3. No More Defensive Programming

```ruby
# ❌ OLD: Defensive dual access (unnecessary now)
value = context[:key] || context["key"]

# ✅ NEW: Just use one - both work!
value = context[:key]
```

### 4. Respect Mutability Patterns

```ruby
# Mutable contexts (Core) - modify in place
run_context.set(:key, "value")     # Mutates
run_context.get(:key)              # => "value"

# Immutable contexts (DSL) - capture new instance
ctx1 = ctx.set(:key, "value")      # Returns new!
ctx2 = ctx1.set(:key2, "value2")   # Chain immutable updates
```

## Performance Considerations

### Indifferent Access Overhead

**Negligible** - `HashWithIndifferentAccess` is optimized and used throughout Rails:

```ruby
# Benchmark comparison
require 'benchmark'

regular_hash = { user_id: "123" }
indifferent_hash = regular_hash.with_indifferent_access

Benchmark.bmbm do |x|
  x.report("Regular hash") { 100_000.times { regular_hash[:user_id] } }
  x.report("Indifferent")  { 100_000.times { indifferent_hash[:user_id] } }
end

# Result: < 5% overhead, negligible in practice
```

### Mutable vs Immutable Trade-offs

**Mutable (Core):**
- ✅ Faster (no object allocation)
- ✅ Better for high-frequency operations
- ⚠️ Risk of accidental mutation

**Immutable (DSL):**
- ✅ Safer (no side effects)
- ✅ Better for user-facing code
- ⚠️ Slightly slower (new object per update)

## Testing

### Example RSpec Tests

```ruby
RSpec.describe "Context Harmonization" do
  describe RAAF::RunContext do
    let(:context) { described_class.new }

    it "supports indifferent key access" do
      context.set(:user_id, "123")

      expect(context.get(:user_id)).to eq("123")
      expect(context.get("user_id")).to eq("123")
      expect(context[:user_id]).to eq("123")
      expect(context["user_id"]).to eq("123")
    end

    it "supports nested indifferent access" do
      context.set(:user, { profile: { name: "John" } })

      expect(context[:user][:profile][:name]).to eq("John")
      expect(context["user"]["profile"]["name"]).to eq("John")
      expect(context[:user]["profile"][:name]).to eq("John")
    end
  end
end
```

## Troubleshooting

### Issue: Key Not Found

```ruby
# Problem: Using wrong context type
context.fetch(:key)  # NameError or nil

# Solution: Check if key exists first
context.has?(:key)   # => false
context.get(:key, "default")  # Use default value
```

### Issue: Immutable Context Not Updating

```ruby
# ❌ Problem: Not capturing new instance
ctx = ContextVariables.new
ctx.set(:key, "value")   # Returns new instance!
ctx.get(:key)            # => nil (original unchanged)

# ✅ Solution: Capture return value
ctx = ContextVariables.new
ctx = ctx.set(:key, "value")  # Capture new instance
ctx.get(:key)                 # => "value"
```

## Benefits Summary

### Developer Experience
- ✅ **One Interface**: No need to remember different methods per context
- ✅ **No Key Confusion**: Symbol/string keys work everywhere
- ✅ **Better IDE Support**: Autocomplete works across all contexts
- ✅ **Easier Testing**: Mock one interface, not five

### Code Quality
- ✅ **Fewer Bugs**: Eliminates symbol/string key mismatch errors
- ✅ **Less Defensive Code**: No more dual key access patterns
- ✅ **Better Readability**: Consistent patterns across codebase

### Maintainability
- ✅ **Easier Refactoring**: Change key style without breaking code
- ✅ **Future-Proof**: New contexts will follow same interface
- ✅ **Python SDK Alignment**: Matches OpenAI Swarm patterns

## Related Documentation

- **[ContextInterface API](lib/raaf/context_interface.rb)** - Complete interface specification
- **[Core CLAUDE.md](CLAUDE.md)** - Core gem overview
- **[DSL CLAUDE.md](../dsl/CLAUDE.md)** - DSL context patterns

## Version History

- **1.0.0** (2025-10-08) - Initial harmonization release
  - Added deep indifferent access to all Core contexts
  - Unified interface methods (get/set/has?/keys/values/to_h)
  - Created ContextInterface module
  - Backwards compatible with old method names

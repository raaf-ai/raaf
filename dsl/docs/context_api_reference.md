# Context API Reference

## Overview

The Context API provides a clean, intuitive interface for managing agent context. Context is automatically available in agents without explicit configuration.

## Instance Methods

### `get(key, default = nil)`

Retrieves a value from context with optional default.

```ruby
class MyAgent < RAAF::DSL::Agent
  def process
    # Basic usage
    user = get(:user)
    
    # With default value
    limit = get(:limit, 10)
    
    # Nested access with default
    city = get(:location, {})[:city]
  end
end
```

**Parameters:**
- `key` (Symbol) - The context key to retrieve
- `default` (Any) - Default value if key doesn't exist

**Returns:** The context value or default

### `set(key, value)`

Sets a single value in context. Context remains immutable - returns the value.

```ruby
class MyAgent < RAAF::DSL::Agent
  def process
    # Set single value
    set(:status, "processing")
    
    # Set complex value
    set(:result, {
      success: true,
      data: process_data,
      timestamp: Time.now
    })
    
    # Chain operations
    set(:step, 1)
    process_step_one
    set(:step, 2)
    process_step_two
  end
end
```

**Parameters:**
- `key` (Symbol) - The context key to set
- `value` (Any) - The value to set

**Returns:** The value that was set

### `update(**values)`

Updates multiple context values at once. Returns self for chaining.

```ruby
class MyAgent < RAAF::DSL::Agent
  def process
    # Update multiple values
    update(
      status: "complete",
      processed_at: Time.now,
      result_count: 42,
      success: true
    )
    
    # Chain with other operations
    update(status: "starting")
      .process_data
      .update(status: "complete")
  end
  
  def process_data
    # Processing logic
    self  # Return self for chaining
  end
end
```

**Parameters:**
- `**values` (Hash) - Key-value pairs to update

**Returns:** Self (for method chaining)

### `has?(key)`

Checks if a key exists in context.

```ruby
class MyAgent < RAAF::DSL::Agent
  def process
    # Check existence
    if has?(:premium_user)
      process_premium_features
    end
    
    # Guard clause
    return unless has?(:data)
    
    # Conditional logic
    include_history = has?(:include_history) && get(:include_history)
  end
end
```

**Parameters:**
- `key` (Symbol) - The key to check

**Returns:** Boolean - true if key exists (even if value is nil)

### `context_keys`

Returns all keys currently in context.

```ruby
class MyAgent < RAAF::DSL::Agent
  def validate_context
    required = [:user, :data, :config]
    missing = required - context_keys
    
    if missing.any?
      raise "Missing required context: #{missing.join(', ')}"
    end
  end
  
  def debug_context
    puts "Context contains: #{context_keys.join(', ')}"
    puts "Total keys: #{context_keys.length}"
  end
end
```

**Returns:** Array of Symbols - all context keys

## Class Methods

### `auto_context(enabled = true)`

Controls whether auto-context is enabled for the agent class.

```ruby
class ManualContextAgent < RAAF::DSL::Agent
  auto_context false  # Disable auto-context
  
  def initialize(data:)
    # Manual context building required
    context = RAAF::DSL::ContextVariables.new(processed: process(data))
    super(context: context)
  end
end

class AutoContextAgent < RAAF::DSL::Agent
  auto_context true  # Explicitly enable (default)
  # or just omit it since true is default
end
```

**Parameters:**
- `enabled` (Boolean) - Whether to enable auto-context (default: true)

### `auto_context?`

Checks if auto-context is enabled for the agent class.

```ruby
class MyAgent < RAAF::DSL::Agent
  def self.debug_info
    puts "Auto-context enabled: #{auto_context?}"
  end
end

# In tests
RSpec.describe MyAgent do
  it "has auto-context enabled" do
    expect(MyAgent.auto_context?).to be true
  end
end
```

**Returns:** Boolean - true if auto-context is enabled

### `context { ... }`

Configures context building rules using a DSL.

```ruby
class ConfiguredAgent < RAAF::DSL::Agent
  context do
    # Require certain parameters
    requires :user, :tenant
    
    # Exclude parameters from context
    exclude :password, :api_key
    
    # Include only specific parameters
    include :user_id, :session_id, :tenant_id
    
    # Add validation
    validate :age, type: Integer, with: ->(v) { v >= 18 }
    validate :email, with: ->(v) { v.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i) }
  end
end
```

## Context DSL Methods

### `requires(*keys)`

Specifies required context keys. Raises error if missing during initialization.

```ruby
context do
  requires :user, :account, :permissions
end
```

### `exclude(*keys)`

Excludes specified parameters from being added to context.

```ruby
context do
  exclude :raw_file, :temp_data, :cache_instance
end
```

### `include(*keys)`

Only includes specified parameters in context (whitelist).

```ruby
context do
  include :user_id, :session_token, :action
end
```

### `validate(key, type: nil, with: nil)`

Adds validation for a context key.

```ruby
context do
  # Type validation
  validate :user, type: User
  validate :count, type: Integer
  
  # Custom validation with lambda
  validate :email, with: ->(v) { v.include?("@") }
  validate :age, with: ->(v) { v >= 18 && v <= 120 }
  
  # Combined validation
  validate :score, type: Float, with: ->(v) { v.between?(0.0, 100.0) }
end
```

## Best Practices

1. **Use clean API methods** instead of accessing `@context` directly
2. **Transform sensitive data** in `prepare_*_for_context` methods
3. **Validate critical parameters** using the context DSL
4. **Keep context focused** - don't add unnecessary data
5. **Use computed context** for derived values
6. **Document expected context** in class comments
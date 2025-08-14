# Context API Reference

## Overview

The Context API provides a clean, intuitive interface for managing agent context. Instead of manipulating `@context` directly, use these methods for safer, more maintainable code.

## Context Readers (Recommended)

Context readers provide the cleanest way to access context values. They work seamlessly with auto-context.

### `context_reader(*keys, **options)`

Defines accessor methods for context values.

```ruby
class MyAgent < RAAF::DSL::Agent
  # Simple readers - creates methods that access context
  context_reader :product, :company, :user
  
  # With validation and defaults
  context_reader :mode, default: "standard", required: true
  context_reader :limit, default: 10
  context_reader :filters, default: {}
  
  def process
    # Use as methods (not get() calls)
    puts "Processing for #{company.name}"
    puts "Product: #{product}"  # Will raise error if nil and required: true
    puts "Mode: #{mode}"        # Uses default if not provided
    puts "Limit: #{limit}"      # Returns 10 if not set
    
    # Works with conditionals
    if user  # Returns nil if not in context
      log_user_action(user)
    end
  end
end
```

**Parameters:**
- `*keys` (Symbols) - Context keys to create readers for
- `**options` (Hash) - Options for a single key:
  - `:required` (Boolean) - Raises error if value is nil
  - `:default` (Any/Proc) - Default value if nil

**Benefits:**
- Clean, method-based access
- Automatic validation
- Default values
- Works perfectly with auto-context
- No need to call `get()` repeatedly

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

## Hook Methods

### `prepare_<param>_for_context(value)`

Transform a parameter before it's added to context.

```ruby
class UserAgent < RAAF::DSL::Agent
  private
  
  def prepare_user_for_context(user)
    # Transform ActiveRecord object to hash
    {
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role
      # Exclude sensitive fields like password_digest
    }
  end
  
  def prepare_data_for_context(data)
    # Normalize data format
    data.map(&:symbolize_keys)
  end
end
```

### `build_<name>_context`

Compute and add derived values to context.

```ruby
class AnalysisAgent < RAAF::DSL::Agent
  private
  
  def build_statistics_context
    data = get(:data)
    {
      count: data.count,
      sum: data.sum,
      average: data.sum / data.count.to_f,
      min: data.min,
      max: data.max
    }
  end
  
  def build_metadata_context
    {
      processed_at: Time.now,
      processor_version: "1.0",
      environment: Rails.env
    }
  end
end
```

## Context Object Methods

The underlying context object (`@context`) is a `RAAF::DSL::ContextVariables` instance with additional methods:

### Accessing the Raw Context

```ruby
class MyAgent < RAAF::DSL::Agent
  def debug_info
    # Access raw context object
    puts context.class  # RAAF::DSL::ContextVariables
    puts context.size    # Number of keys
    puts context.to_h    # Convert to hash
  end
end
```

### Context Immutability

Context is immutable - all updates create new instances:

```ruby
class MyAgent < RAAF::DSL::Agent
  def demonstrate_immutability
    original_context = context
    
    # This creates a new context instance
    set(:new_key, "value")
    
    # Context object has changed
    puts context.equal?(original_context)  # false
    
    # But original is unchanged
    puts original_context.has?(:new_key)   # false
    puts context.has?(:new_key)            # true
  end
end
```

## Usage Examples

### Complete Context Management

```ruby
class OrderProcessor < RAAF::DSL::Agent
  context do
    requires :order, :customer
    exclude :temp_data
    validate :order, type: Order
  end
  
  def process
    # Get values with defaults
    priority = get(:priority, "normal")
    notify = get(:notify_customer, true)
    
    # Check conditional features
    if has?(:express_shipping)
      process_express_shipping
    end
    
    # Update progress
    set(:status, "processing")
    set(:started_at, Time.now)
    
    # Process order
    result = perform_processing
    
    # Update multiple values
    update(
      status: "complete",
      completed_at: Time.now,
      result: result,
      duration: Time.now - get(:started_at)
    )
    
    # Send notification if needed
    notify_customer if notify
    
    result
  end
  
  private
  
  def prepare_order_for_context(order)
    order.attributes.slice("id", "total", "items", "status")
  end
  
  def build_processing_config_context
    {
      max_retries: 3,
      timeout: 30,
      batch_size: 100
    }
  end
end
```

### Context Inspection and Debugging

```ruby
class DebugAgent < RAAF::DSL::Agent
  def inspect_context
    puts "=== Context Debug Info ==="
    puts "Keys: #{context_keys.inspect}"
    puts "Size: #{context_keys.length}"
    
    context_keys.each do |key|
      value = get(key)
      puts "  #{key}: #{value.class} = #{value.inspect[0..50]}"
    end
    
    puts "=== Missing Expected Keys ==="
    expected = [:user, :data, :config]
    missing = expected.reject { |k| has?(k) }
    puts missing.any? ? missing.inspect : "None"
  end
end
```

### Context Validation Pattern

```ruby
class ValidatedAgent < RAAF::DSL::Agent
  def validate!
    errors = []
    
    # Check required fields
    [:user, :action].each do |key|
      errors << "Missing #{key}" unless has?(key)
    end
    
    # Validate types
    if has?(:user) && !get(:user).is_a?(User)
      errors << "User must be a User instance"
    end
    
    # Validate values
    if has?(:priority)
      priority = get(:priority)
      unless %w[low normal high urgent].include?(priority)
        errors << "Invalid priority: #{priority}"
      end
    end
    
    raise ValidationError, errors.join(", ") if errors.any?
  end
end
```

## Performance Considerations

1. **Immutability**: Each `set` or `update` creates a new context instance
2. **Transformation Methods**: Called once during initialization
3. **Computed Context**: Built during initialization, not lazy
4. **Memory**: Old context instances are garbage collected

## Best Practices

1. **Use clean API methods** instead of accessing `@context` directly
2. **Transform sensitive data** in `prepare_*_for_context` methods
3. **Validate critical parameters** using the context DSL
4. **Keep context focused** - don't add unnecessary data
5. **Use computed context** for derived values
6. **Document expected context** in class comments
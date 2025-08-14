# Auto-Context Troubleshooting Guide

## Common Issues and Solutions

### Issue: Parameters Not Appearing in Context

**Symptom:**
```ruby
agent = MyAgent.new(user: user, data: data)
agent.get(:user)  # => nil
```

**Possible Causes & Solutions:**

1. **Auto-context is disabled**
```ruby
class MyAgent < RAAF::DSL::Agent
  auto_context false  # Remove this line or set to true
end
```

2. **Parameters are excluded**
```ruby
class MyAgent < RAAF::DSL::Agent
  context do
    exclude :user  # Remove user from exclude list
  end
end
```

3. **Using include with different parameters**
```ruby
class MyAgent < RAAF::DSL::Agent
  context do
    include :id, :name  # Only these will be included
    # Either add :user to include list or remove include entirely
  end
end
```

4. **Passing context explicitly (bypasses auto-context)**
```ruby
# This bypasses auto-context
agent = MyAgent.new(
  context: some_context,  # When context: is provided, other params ignored
  user: user,            # This will be ignored
  data: data             # This will be ignored
)

# Solution: Don't pass context: parameter
agent = MyAgent.new(user: user, data: data)
```

### Issue: Transformation Methods Not Being Called

**Symptom:**
```ruby
class MyAgent < RAAF::DSL::Agent
  def prepare_user_for_context(user)
    { id: user.id, name: user.name }
  end
end

agent = MyAgent.new(user: active_record_user)
agent.get(:user)  # => Full ActiveRecord object, not transformed
```

**Solutions:**

1. **Check method naming - must be exact**
```ruby
# Correct
def prepare_user_for_context(user)

# Wrong - won't be called
def prepare_user(user)
def transform_user_for_context(user)
def prepare_for_context_user(user)
```

2. **Method must be private or protected**
```ruby
class MyAgent < RAAF::DSL::Agent
  private  # Don't forget this!
  
  def prepare_user_for_context(user)
    { id: user.id, name: user.name }
  end
end
```

### Issue: Computed Context Not Being Added

**Symptom:**
```ruby
class MyAgent < RAAF::DSL::Agent
  def build_config_context
    { timeout: 30 }
  end
end

agent = MyAgent.new(data: data)
agent.get(:config)  # => nil
```

**Solutions:**

1. **Check method naming pattern**
```ruby
# Correct - must match build_*_context
def build_config_context
def build_metadata_context

# Wrong - won't be called
def build_config
def create_config_context
def config_context
```

2. **Method must be private or protected**
```ruby
class MyAgent < RAAF::DSL::Agent
  private
  
  def build_config_context
    { timeout: 30 }
  end
end
```

3. **Method must not require parameters**
```ruby
# Wrong - computed context methods take no parameters
def build_config_context(options)

# Correct - access context if needed
def build_config_context
  options = get(:options, {})
  { timeout: options[:timeout] || 30 }
end
```

### Issue: Context Validation Failing

**Symptom:**
```ruby
class MyAgent < RAAF::DSL::Agent
  context do
    requires :user
    validate :age, type: Integer
  end
end

agent = MyAgent.new(age: "25")  # Raises error
```

**Solutions:**

1. **Ensure required parameters are provided**
```ruby
# This will fail - missing required :user
agent = MyAgent.new(data: data)

# This works
agent = MyAgent.new(user: user, data: data)
```

2. **Fix type mismatches**
```ruby
# Wrong type
agent = MyAgent.new(age: "25")  # String, not Integer

# Correct type
agent = MyAgent.new(age: 25)    # Integer
```

3. **Fix validation lambdas**
```ruby
context do
  # Make sure lambda returns boolean
  validate :email, with: ->(v) { 
    v.present? && v.include?("@")  # Returns boolean
  }
end
```

### Issue: Backward Compatibility Problems

**Symptom:** Existing agent stops working after upgrade

**Solutions:**

1. **Agent with existing initialize still works**
```ruby
class ExistingAgent < RAAF::DSL::Agent
  def initialize(data:)
    # If you pass context: to super, auto-context is bypassed
    context = build_my_context(data)
    super(context: context)  # This still works!
  end
end
```

2. **Disable auto-context if needed**
```ruby
class ProblematicAgent < RAAF::DSL::Agent
  auto_context false  # Disable to maintain old behavior
  
  def initialize(...)
    # Old initialization code
  end
end
```

### Issue: Context Not Accessible in Methods

**Symptom:**
```ruby
class MyAgent < RAAF::DSL::Agent
  def process
    user = @context.get(:user)  # NoMethodError
  end
end
```

**Solution:** Use the clean API methods
```ruby
class MyAgent < RAAF::DSL::Agent
  def process
    # Don't access @context directly
    user = get(:user)         # Correct
    set(:status, "processing") # Correct
    
    # Or if you need the context object
    user = context.get(:user)  # Also works
  end
end
```

### Issue: Memory/Performance Concerns

**Symptom:** Agent seems slow or uses too much memory

**Solutions:**

1. **Exclude large objects from context**
```ruby
class DataAgent < RAAF::DSL::Agent
  context do
    exclude :raw_file, :large_dataset
  end
  
  def initialize(raw_file:, metadata:, large_dataset:)
    @raw_file = raw_file  # Store separately if needed
    @large_dataset = large_dataset
    super(metadata: metadata)  # Only metadata goes to context
  end
end
```

2. **Transform large objects to smaller representations**
```ruby
class FileAgent < RAAF::DSL::Agent
  private
  
  def prepare_file_for_context(file)
    # Don't store entire file in context
    {
      name: file.original_filename,
      size: file.size,
      content_type: file.content_type
    }
  end
end
```

### Issue: Context Immutability Confusion

**Symptom:**
```ruby
agent.get(:data) << new_item  # Modifies context directly!
```

**Solution:** Create new values instead of modifying
```ruby
# Wrong - modifies context directly
data = agent.get(:data)
data << new_item

# Correct - create new array
data = agent.get(:data) + [new_item]
agent.set(:data, data)
```

### Issue: Testing Agents with Auto-Context

**Problem:** Tests failing after migration

**Solution:** Update test setup
```ruby
# Old test
RSpec.describe MyAgent do
  let(:context) { ContextVariables.new(user: user) }
  let(:agent) { MyAgent.new(context: context) }
end

# New test - just pass parameters
RSpec.describe MyAgent do
  let(:agent) { MyAgent.new(user: user) }
end
```

## Debugging Techniques

### 1. Check What's in Context

```ruby
class DebugHelper
  def self.inspect_agent(agent)
    puts "Auto-context enabled: #{agent.class.auto_context?}"
    puts "Context keys: #{agent.context_keys.inspect}"
    puts "Context values:"
    agent.context_keys.each do |key|
      puts "  #{key}: #{agent.get(key).inspect[0..100]}"
    end
  end
end

agent = MyAgent.new(user: user, data: data)
DebugHelper.inspect_agent(agent)
```

### 2. Trace Context Building

```ruby
class MyAgent < RAAF::DSL::Agent
  def initialize(...)
    puts "Before super - params: #{...inspect}"
    super
    puts "After super - context keys: #{context_keys.inspect}"
  end
  
  private
  
  def prepare_user_for_context(user)
    puts "Transforming user: #{user.class}"
    result = { id: user.id, name: user.name }
    puts "Transformed to: #{result.inspect}"
    result
  end
  
  def build_config_context
    puts "Building config context"
    { timeout: 30 }
  end
end
```

### 3. Validate Context Rules

```ruby
class ValidatedAgent < RAAF::DSL::Agent
  context do
    requires :user, :data
    validate :user, type: User
  end
  
  def self.test_context_rules
    # Test with missing params
    begin
      new(data: "test")
      puts "ERROR: Should have failed with missing user"
    rescue => e
      puts "✓ Correctly caught: #{e.message}"
    end
    
    # Test with wrong type
    begin
      new(user: "not a user", data: "test")
      puts "ERROR: Should have failed with wrong type"
    rescue => e
      puts "✓ Correctly caught: #{e.message}"
    end
    
    # Test with correct params
    begin
      new(user: User.new, data: "test")
      puts "✓ Correctly accepted valid params"
    rescue => e
      puts "ERROR: Should have worked: #{e.message}"
    end
  end
end
```

## Quick Fixes Checklist

- [ ] Is `auto_context false` set? Remove it or set to `true`
- [ ] Are parameters in an `exclude` list? Remove them
- [ ] Is `include` being used? Add parameters or remove `include`
- [ ] Is `context:` being passed to `new()`? Remove it for auto-context
- [ ] Are transformation methods named correctly? (`prepare_<param>_for_context`)
- [ ] Are computed methods named correctly? (`build_<name>_context`)
- [ ] Are transformation/computed methods private or protected?
- [ ] Are required parameters being provided?
- [ ] Do validation lambdas return booleans?
- [ ] Is the context being accessed with clean API methods?

## Getting Help

If you're still having issues:

1. **Check the test file**: `/test_auto_context.rb` for working examples
2. **Review the spec**: `/.agent-os/specs/2025-08-14-auto-context-builder/spec.md`
3. **Look at migrations**: `/docs/migration_guide.md` for patterns
4. **Enable debug mode**: Set `debug: true` when creating agent

```ruby
agent = MyAgent.new(user: user, debug: true)
```
# Migration Guide: Unified Agent Class

As of RAAF DSL v1.0, we've merged the `Base` and `SmartAgent` classes into a single, powerful `Agent` class. This guide will help you migrate your existing code.

## Quick Migration

### For Base Class Users

Simply change your parent class from `Base` to `Agent`:

```ruby
# Before
class MyAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::Agents::AgentDsl
  # ... your code
end

# After  
class MyAgent < RAAF::DSL::Agent
  # AgentDsl is already included, no need to include it
  # ... your code remains the same
end
```

That's it! All your existing functionality will continue to work exactly as before.

### For SmartAgent Users

Change from `SmartAgent` to `Agent`:

```ruby
# Before (OLD - DO NOT USE)
# class MySmartAgent < RAAF::DSL::Agents::SmartAgent
#   requires :user, :document
#   retry_on :rate_limit
#   # ... your code
# end

# After (NEW)
class MySmartAgent < RAAF::DSL::Agent
  requires :user, :document
  retry_on :rate_limit
  # ... your code remains the same
end
```

All SmartAgent features are now part of the unified Agent class.

## What's Changed

### 1. Single Import Path

```ruby
# The new unified agent is at the DSL root level
require 'raaf-dsl'

# Use directly
class MyAgent < RAAF::DSL::Agent
  # Your agent code
end
```

### 2. No Need to Include AgentDsl

The new `Agent` class already includes `AgentDsl`:

```ruby
# Before (OLD - DO NOT USE)
# class MyAgent < RAAF::DSL::Agents::Base
#   include RAAF::DSL::Agents::AgentDsl  # This was required
# end

# After (NEW)
class MyAgent < RAAF::DSL::Agent
  # AgentDsl is already included
end
```

### 3. All Features Available

The new Agent class includes all features from both Base and SmartAgent:

- ✅ Basic agent functionality (from Base)
- ✅ DSL configuration methods
- ✅ Tool and handoff support
- ✅ Smart features (opt-in):
  - Retry logic
  - Circuit breakers
  - Context validation
  - Inline schema DSL
  - Error categorization

## Examples

### Basic Agent (unchanged functionality)

```ruby
class SimpleAgent < RAAF::DSL::Agent
  agent_name "SimpleAgent"
  model "gpt-4o"
  
  def build_instructions
    "You are a helpful assistant"
  end
  
  def build_schema
    {
      type: "object",
      properties: {
        response: { type: "string" }
      },
      required: ["response"],
      additionalProperties: false
    }
  end
end

# Usage remains the same
agent = SimpleAgent.new(context: { data: "test" })
result = agent.run
```

### Agent with Smart Features

```ruby
class RobustAgent < RAAF::DSL::Agent
  agent_name "RobustAgent"
  
  # Context validation
  requires :api_key, :endpoint
  validates :api_key, type: String, presence: true
  
  # Retry configuration
  retry_on :rate_limit, max_attempts: 3, backoff: :exponential
  retry_on Timeout::Error, max_attempts: 2
  
  # Circuit breaker
  circuit_breaker threshold: 5, timeout: 60
  
  # Inline schema
  schema do
    field :status, type: :string, required: true
    field :data, type: :object do
      field :id, type: :string
      field :value, type: :number
    end
  end
  
  # Prompts
  system_prompt "You are a data processor"
  
  user_prompt do |context|
    "Process data from #{context.endpoint}"
  end
end

# Use with smart features
agent = RobustAgent.new(
  context: { api_key: "sk-123", endpoint: "https://api.example.com" }
)

# Call method includes all smart features (retry, circuit breaker, etc.)
result = agent.call

# Or use run for basic execution without smart features
result = agent.run
```

## Backward Compatibility

The new `Agent` class is fully backward compatible:

- All methods from `Base` are preserved
- Method signatures remain the same
- Default behavior is unchanged
- Smart features are opt-in only

## Deprecation Notice

The following classes are deprecated and will be removed in v2.0:

- `RAAF::DSL::Agents::Base` - Use `RAAF::DSL::Agent` instead
- `RAAF::DSL::Agents::SmartAgent` - Use `RAAF::DSL::Agent` instead

## Need Help?

If you encounter any issues during migration, please:

1. Check that you're using `RAAF::DSL::Agent` as the parent class
2. Remove any `include RAAF::DSL::Agents::AgentDsl` statements (it's automatic now)
3. Ensure your `require` statements include `raaf-dsl`

For additional support, please open an issue on our GitHub repository.
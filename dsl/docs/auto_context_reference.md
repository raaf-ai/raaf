# RAAF DSL Auto-Context Reference

## Overview

Auto-context is a Convention over Configuration feature in RAAF::DSL::Agent that automatically builds context from initialization parameters. By default, all parameters passed to `new` become context variables without any boilerplate code.

## Key Features

- **Enabled by default** - No configuration needed for the common case
- **Zero boilerplate** - No `initialize` method required
- **Clean API** - Simple `get`, `set`, `update` methods
- **Full backward compatibility** - Existing agents work unchanged
- **Optional control** - Fine-grained configuration when needed

## Basic Usage

### Simplest Agent Ever

```ruby
class MyAgent < RAAF::DSL::Agent
  agent_name "MyAgent"
  static_instructions "Process user data"
  # That's it! No initialize method needed
end

# Usage - parameters automatically become context
agent = MyAgent.new(
  user: current_user,
  query: "find products",
  max_results: 10
)

# All parameters are available in context
agent.get(:user)        # => current_user
agent.get(:query)       # => "find products"
agent.get(:max_results) # => 10
```

## Clean Context API

Instead of manipulating `@context` directly, use the clean API methods:

```ruby
class ProcessingAgent < RAAF::DSL::Agent
  def process
    # Get values
    user = get(:user)
    data = get(:data)
    
    # Set single value
    set(:status, "processing")
    
    # Update multiple values
    update(
      processed_at: Time.now,
      result: analyze(data),
      status: "complete"
    )
    
    # Check existence
    if has?(:priority)
      # Handle priority processing
    end
    
    # Get all keys
    available = context_keys
  end
end
```

## Context DSL Configuration

### Excluding Parameters

```ruby
class DataAgent < RAAF::DSL::Agent
  context do
    exclude :cache, :logger, :debug
  end
end

# cache, logger, and debug won't be added to context
agent = DataAgent.new(
  data: important_data,
  cache: cache_instance,  # excluded
  logger: logger          # excluded
)
```

### Including Only Specific Parameters

```ruby
class SecureAgent < RAAF::DSL::Agent
  context do
    include :user_id, :session_token
  end
end

# Only user_id and session_token will be in context
agent = SecureAgent.new(
  user_id: 123,
  session_token: "abc",
  other_data: "ignored"
)
```

### Validation

```ruby
class ValidatedAgent < RAAF::DSL::Agent
  context do
    requires :user, :data
    validate :score, type: Integer, with: ->(v) { v.between?(0, 100) }
  end
end
```

## Custom Parameter Preparation

Define `prepare_<param>_for_context` methods to transform parameters before they enter context:

```ruby
class UserAgent < RAAF::DSL::Agent
  private
  
  def prepare_user_for_context(user)
    # Extract only needed fields
    {
      id: user.id,
      name: user.name,
      role: user.role
    }
  end
  
  def prepare_data_for_context(data)
    # Normalize data format
    data.map(&:to_h)
  end
end
```

## Computed Context Values

Methods matching `build_<name>_context` are automatically called and their results added to context:

```ruby
class AnalysisAgent < RAAF::DSL::Agent
  private
  
  def build_metadata_context
    {
      timestamp: Time.now,
      version: "1.0",
      environment: Rails.env
    }
  end
  
  def build_config_context
    {
      max_retries: 3,
      timeout: 30,
      batch_size: 100
    }
  end
end

# Context will include :metadata and :config automatically
agent = AnalysisAgent.new(data: input)
agent.get(:metadata) # => { timestamp: ..., version: "1.0", ... }
agent.get(:config)   # => { max_retries: 3, ... }
```

## Disabling Auto-Context

For agents that need manual control:

```ruby
class ManualAgent < RAAF::DSL::Agent
  auto_context false  # Disable auto-context
  
  def initialize(data:)
    # Manual context building
    processed = process_data(data)
    context = RAAF::DSL::ContextVariables.new(
      result: processed,
      timestamp: Time.now
    )
    super(context: context)
  end
end
```

## Backward Compatibility

Existing agents that pass `context:` explicitly continue to work:

```ruby
class ExistingAgent < RAAF::DSL::Agent
  def initialize(data:)
    # This still works!
    context = build_custom_context(data)
    super(context: context)
  end
end
```

When `context:` is provided to `super()`, auto-context is automatically bypassed.

## Complete Example

```ruby
class MarketAnalysisAgent < RAAF::DSL::Agent
  agent_name "MarketAnalysisAgent"
  model "gpt-4o"
  
  # Configure context
  context do
    requires :company, :market
    exclude :debug_info
    validate :analysis_depth, with: ->(v) { %w[quick standard deep].include?(v) }
  end
  
  # No initialize needed!
  
  def analyze
    # Use clean API
    company = get(:company)
    market = get(:market)
    depth = get(:analysis_depth, "standard")
    
    result = perform_analysis(company, market, depth)
    
    # Update context
    update(
      result: result,
      analyzed_at: Time.now,
      status: "complete"
    )
  end
  
  private
  
  # Custom preparation
  def prepare_company_for_context(company)
    {
      id: company.id,
      name: company.name,
      industry: company.industry,
      size: company.employee_count
    }
  end
  
  # Computed context
  def build_analysis_config_context
    {
      models: available_models,
      confidence_threshold: 0.8
    }
  end
end
```

## API Reference

### Class Methods

- `auto_context(enabled = true)` - Enable/disable auto-context (default: true)
- `auto_context?` - Check if auto-context is enabled
- `context { ... }` - Configure context rules

### Instance Methods

- `get(key, default = nil)` - Get context value
- `set(key, value)` - Set single context value
- `update(**values)` - Update multiple context values
- `has?(key)` - Check if key exists in context
- `context_keys` - Get all context keys

### Context DSL Methods

- `exclude(*keys)` - Exclude parameters from context
- `include(*keys)` - Only include specified parameters
- `requires(*keys)` - Mark parameters as required
- `validate(key, type: nil, with: nil)` - Add validation

### Hook Methods

- `prepare_<param>_for_context(value)` - Transform parameter before adding to context
- `build_<name>_context` - Compute and add context value
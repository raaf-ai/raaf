# Getting Started with RAAF DSL Auto-Context

## What is Auto-Context?

Auto-context is a powerful feature that eliminates boilerplate code when creating RAAF agents. Instead of manually building context, parameters automatically become context variables.

## Your First Agent with Auto-Context

### Step 1: Create a Simple Agent

```ruby
# app/ai/agents/greeting_agent.rb
class GreetingAgent < RAAF::DSL::Agent
  agent_name "GreetingAgent"
  static_instructions "You are a friendly greeting assistant"
end
```

That's it! No `initialize` method needed.

### Step 2: Use the Agent

```ruby
# Create agent with parameters
agent = GreetingAgent.new(
  user_name: "Alice",
  language: "en",
  time_of_day: "morning"
)

# All parameters are automatically in context
puts agent.get(:user_name)    # => "Alice"
puts agent.get(:language)      # => "en"
puts agent.get(:time_of_day)   # => "morning"

# Run the agent
result = agent.run
```

## Real-World Example: Product Search Agent

```ruby
class ProductSearchAgent < RAAF::DSL::Agent
  agent_name "ProductSearchAgent"
  model "gpt-4o"
  static_instructions "Search and filter products based on user criteria"
  
  # No initialize method needed!
  
  def search
    # Access context with clean API
    query = get(:query)
    filters = get(:filters, {})
    limit = get(:limit, 10)
    
    # Perform search
    results = Product.search(query)
                    .apply_filters(filters)
                    .limit(limit)
    
    # Update context with results
    update(
      results: results,
      result_count: results.count,
      search_completed_at: Time.now
    )
    
    results
  end
end

# Usage is simple and clean
agent = ProductSearchAgent.new(
  query: "laptop",
  filters: { brand: "Apple", min_price: 1000 },
  limit: 20,
  user: current_user
)

results = agent.search
```

## Adding Computed Context

Want to add derived values to context automatically? Use `build_*_context` methods:

```ruby
class OrderAnalysisAgent < RAAF::DSL::Agent
  agent_name "OrderAnalysisAgent"
  
  private
  
  # This method is automatically called and adds to context
  def build_statistics_context
    orders = get(:orders)
    {
      total_count: orders.count,
      total_value: orders.sum(&:total),
      average_value: orders.sum(&:total) / orders.count.to_f,
      date_range: "#{orders.first.created_at} - #{orders.last.created_at}"
    }
  end
  
  # Another computed value
  def build_customer_summary_context
    customer = get(:customer)
    {
      lifetime_value: customer.orders.sum(&:total),
      order_count: customer.orders.count,
      member_since: customer.created_at
    }
  end
end

# Usage
agent = OrderAnalysisAgent.new(
  orders: recent_orders,
  customer: current_customer
)

# Computed values are automatically available
agent.get(:statistics)      # => { total_count: ..., total_value: ... }
agent.get(:customer_summary) # => { lifetime_value: ..., order_count: ... }
```

## Customizing Context Building

### Excluding Sensitive Data

```ruby
class PaymentAgent < RAAF::DSL::Agent
  # Exclude sensitive fields from context
  context do
    exclude :credit_card, :ssn, :password
  end
  
  def process_payment
    # These parameters won't be in context for security
    amount = get(:amount)
    user = get(:user)
    # credit_card is NOT in context
  end
end
```

### Transforming Parameters

```ruby
class EmailAgent < RAAF::DSL::Agent
  private
  
  # Transform user object before adding to context
  def prepare_user_for_context(user)
    {
      id: user.id,
      email: user.email,
      name: user.full_name
      # Exclude sensitive fields like password_digest
    }
  end
  
  # Transform complex data
  def prepare_attachments_for_context(attachments)
    attachments.map do |att|
      {
        filename: att.filename,
        size: att.byte_size,
        content_type: att.content_type
        # Don't include actual file data
      }
    end
  end
end
```

## Working with Context in Your Agent

```ruby
class DataProcessingAgent < RAAF::DSL::Agent
  def process
    # Get with defaults
    batch_size = get(:batch_size, 100)
    timeout = get(:timeout, 30)
    
    # Check existence
    if has?(:priority)
      # Handle priority processing
      process_priority_queue
    end
    
    # Update context during processing
    set(:status, "processing")
    set(:started_at, Time.now)
    
    # Process data...
    result = perform_processing
    
    # Update multiple values at once
    update(
      status: "complete",
      completed_at: Time.now,
      result: result,
      records_processed: result.count
    )
  end
  
  private
  
  def perform_processing
    # Your processing logic here
  end
end
```

## Comparison: Before and After

### Before (Manual Context Building)

```ruby
class OldStyleAgent < RAAF::DSL::Agent
  def initialize(user:, query:, options: {})
    @user = user
    @query = query
    @options = options
    
    # Manual context building
    context = RAAF::DSL::ContextVariables.new
      .set(:user, extract_user_data(@user))
      .set(:query, @query)
      .set(:options, @options)
      .set(:timestamp, Time.now)
      .set(:config, load_config)
    
    super(context: context)
  end
  
  private
  
  def extract_user_data(user)
    # Manual transformation
    { id: user.id, name: user.name }
  end
  
  def load_config
    # Manual config loading
    { timeout: 30, retries: 3 }
  end
end
```

### After (With Auto-Context)

```ruby
class NewStyleAgent < RAAF::DSL::Agent
  # No initialize needed!
  
  private
  
  # Optional: Transform user automatically
  def prepare_user_for_context(user)
    { id: user.id, name: user.name }
  end
  
  # Optional: Add computed context
  def build_timestamp_context
    Time.now
  end
  
  def build_config_context
    { timeout: 30, retries: 3 }
  end
end
```

## Best Practices

1. **Let auto-context do the work** - Don't define `initialize` unless you need special processing
2. **Use the clean API** - Prefer `get`, `set`, `update` over direct `@context` access
3. **Transform sensitive data** - Use `prepare_*_for_context` to filter sensitive fields
4. **Add computed values** - Use `build_*_context` for derived data
5. **Exclude unnecessary data** - Use the `context` DSL to exclude large or sensitive parameters

## Next Steps

- Learn about [Context DSL Configuration](./context_dsl_guide.md)
- Explore [Migration Guide](./migration_guide.md) for existing projects
- See [Troubleshooting Guide](./troubleshooting.md) for common issues
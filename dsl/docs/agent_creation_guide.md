# Agent Creation Guide with Auto-Context

## Creating Your First Agent

With auto-context, creating agents is simpler than ever. This guide shows you how to build agents for different use cases.

## Basic Agent Structure

```ruby
class MyAgent < RAAF::DSL::Agent
  agent_name "MyAgent"
  model "gpt-4o"              # Optional: defaults to gpt-4o
  max_turns 1                  # Optional: defaults to 3
  
  static_instructions "You are a helpful assistant"
  
  # That's it! No initialize method needed
end
```

## Simple Data Processing Agent

```ruby
class DataSummaryAgent < RAAF::DSL::Agent
  agent_name "DataSummaryAgent"
  static_instructions "Analyze and summarize data patterns"
  
  # No initialize needed - parameters become context automatically
  
  def summarize
    # Access parameters via clean API
    data = get(:data)
    format = get(:format, "json")  # With default
    
    summary = analyze_data(data)
    
    # Update context
    set(:summary, summary)
    set(:processed_at, Time.now)
    
    format_output(summary, format)
  end
  
  private
  
  def analyze_data(data)
    # Your analysis logic
  end
  
  def format_output(summary, format)
    case format
    when "json" then summary.to_json
    when "text" then summary.to_s
    else summary
    end
  end
end

# Usage
agent = DataSummaryAgent.new(
  data: sales_data,
  format: "json"
)
result = agent.summarize
```

## Agent with Parameter Transformation

```ruby
class CustomerAnalysisAgent < RAAF::DSL::Agent
  agent_name "CustomerAnalysisAgent"
  
  static_instructions <<~PROMPT
    Analyze customer behavior and provide insights
    Focus on purchase patterns and preferences
  PROMPT
  
  private
  
  # Transform customer object to include only relevant data
  def prepare_customer_for_context(customer)
    {
      id: customer.id,
      name: customer.full_name,
      tier: customer.subscription_tier,
      lifetime_value: customer.calculate_ltv,
      recent_purchases: customer.purchases.recent(10).map { |p|
        { product: p.product_name, amount: p.amount, date: p.created_at }
      }
    }
  end
  
  # Transform options hash
  def prepare_options_for_context(options)
    {
      include_recommendations: options[:recommendations] || false,
      analysis_depth: options[:depth] || "standard",
      time_period: options[:period] || "last_30_days"
    }
  end
end

# Usage
agent = CustomerAnalysisAgent.new(
  customer: current_customer,
  options: { recommendations: true, depth: "deep" }
)
```

## Agent with Computed Context

```ruby
class MarketTrendAgent < RAAF::DSL::Agent
  agent_name "MarketTrendAgent"
  model "gpt-4o"
  
  static_instructions "Analyze market trends and provide insights"
  
  private
  
  # These methods automatically add to context
  def build_market_stats_context
    market = get(:market)
    {
      total_volume: market.transactions.sum(:amount),
      avg_price: market.transactions.average(:price),
      volatility: calculate_volatility(market),
      trend: determine_trend(market)
    }
  end
  
  def build_timeframe_context
    {
      start_date: 30.days.ago,
      end_date: Date.today,
      trading_days: calculate_trading_days
    }
  end
  
  def build_indicators_context
    market = get(:market)
    {
      rsi: calculate_rsi(market),
      moving_average: calculate_ma(market),
      volume_trend: calculate_volume_trend(market)
    }
  end
  
  def calculate_volatility(market)
    # Volatility calculation logic
  end
  
  def determine_trend(market)
    # Trend analysis logic
  end
end

# Usage
agent = MarketTrendAgent.new(market: market_data)
# Context automatically includes:
# - market (original parameter)
# - market_stats (computed)
# - timeframe (computed)
# - indicators (computed)
```

## Agent with Context Configuration

```ruby
class SecureDataAgent < RAAF::DSL::Agent
  agent_name "SecureDataAgent"
  
  # Configure what goes into context
  context do
    # Required parameters
    requires :user, :action
    
    # Exclude sensitive data
    exclude :password, :api_key, :secret_token
    
    # Validate parameters
    validate :action, with: ->(v) { %w[read write delete].include?(v) }
    validate :user, type: User
  end
  
  static_instructions "Process secure data operations"
  
  def execute
    # password, api_key, secret_token are NOT in context
    user = get(:user)
    action = get(:action)
    data = get(:data)
    
    authorize!(user, action)
    perform_action(action, data)
  end
end

# Usage
agent = SecureDataAgent.new(
  user: current_user,
  action: "write",
  data: sensitive_data,
  password: "secret",      # Excluded from context
  api_key: "key123"       # Excluded from context
)
```

## Agent with Conditional Context

```ruby
class AdaptiveSearchAgent < RAAF::DSL::Agent
  agent_name "AdaptiveSearchAgent"
  
  context do
    requires :query
  end
  
  private
  
  # Only include user preferences if user is logged in
  def build_preferences_context
    user = get(:user)
    return nil unless user&.logged_in?
    
    {
      language: user.preferred_language,
      categories: user.interested_categories,
      exclude_categories: user.blocked_categories
    }
  end
  
  # Include location only if provided and valid
  def build_location_context
    location = get(:location)
    return nil unless location&.valid?
    
    {
      country: location.country,
      city: location.city,
      coordinates: [location.lat, location.lng]
    }
  end
  
  # Include filters only if advanced search
  def build_filters_context
    return nil unless get(:advanced_search)
    
    {
      price_range: get(:price_range),
      date_range: get(:date_range),
      rating_minimum: get(:min_rating, 3.0)
    }
  end
end

# Basic search
basic_agent = AdaptiveSearchAgent.new(query: "laptops")

# Advanced search with user
advanced_agent = AdaptiveSearchAgent.new(
  query: "laptops",
  user: current_user,
  location: user_location,
  advanced_search: true,
  price_range: 500..1500,
  min_rating: 4.0
)
```

## Agent with Complex Business Logic

```ruby
class OrderProcessingAgent < RAAF::DSL::Agent
  agent_name "OrderProcessingAgent"
  
  # Configure context
  context do
    requires :order, :customer
    validate :order, type: Order
    validate :customer, type: Customer
  end
  
  # Add prompt class for complex instructions
  prompt_class OrderProcessingPrompt
  
  # Lifecycle hooks
  on_start :log_processing_start
  on_end :notify_completion
  on_error :handle_processing_error
  
  # Metrics
  track_metrics do
    counter :orders_processed
    histogram :processing_time_seconds
    gauge :order_value
  end
  
  def process
    validate_order!
    check_inventory!
    calculate_pricing!
    apply_discounts!
    finalize_order!
  end
  
  private
  
  def prepare_order_for_context(order)
    {
      id: order.id,
      items: order.line_items.map(&:to_h),
      subtotal: order.subtotal,
      status: order.status
    }
  end
  
  def prepare_customer_for_context(customer)
    {
      id: customer.id,
      tier: customer.loyalty_tier,
      discount_eligible: customer.eligible_for_discount?,
      payment_methods: customer.payment_methods.active
    }
  end
  
  def build_pricing_rules_context
    {
      tax_rate: determine_tax_rate,
      shipping_options: available_shipping_options,
      discount_rules: active_discount_rules
    }
  end
  
  def build_inventory_status_context
    order = get(:order)
    {
      all_available: check_all_items_available(order),
      backorder_items: find_backorder_items(order),
      reserved_until: Time.now + 15.minutes
    }
  end
  
  # Business logic methods
  def validate_order!
    # Validation logic
  end
  
  def check_inventory!
    # Inventory checking
  end
  
  def calculate_pricing!
    # Pricing calculation
  end
  
  def apply_discounts!
    # Discount application
  end
  
  def finalize_order!
    # Order finalization
  end
  
  # Hook methods
  def log_processing_start
    Rails.logger.info "Processing order #{get(:order).id}"
  end
  
  def notify_completion
    OrderMailer.processed(get(:order)).deliver_later
  end
  
  def handle_processing_error(error)
    Rails.logger.error "Order processing failed: #{error.message}"
    OrderMailer.failed(get(:order), error).deliver_later
  end
end
```

## Testing Your Agents

```ruby
RSpec.describe DataSummaryAgent do
  let(:test_data) { generate_test_data }
  
  describe "auto-context" do
    it "accepts parameters without initialize" do
      agent = DataSummaryAgent.new(
        data: test_data,
        format: "json"
      )
      
      expect(agent.get(:data)).to eq(test_data)
      expect(agent.get(:format)).to eq("json")
    end
    
    it "provides defaults for missing parameters" do
      agent = DataSummaryAgent.new(data: test_data)
      
      expect(agent.get(:format, "json")).to eq("json")
    end
  end
  
  describe "#summarize" do
    it "processes data and updates context" do
      agent = DataSummaryAgent.new(data: test_data)
      result = agent.summarize
      
      expect(agent.has?(:summary)).to be true
      expect(agent.has?(:processed_at)).to be true
      expect(result).to be_a(String)
    end
  end
end
```

## Best Practices

### 1. Keep Agents Focused
```ruby
# Good: Single responsibility
class InvoiceGeneratorAgent < RAAF::DSL::Agent
  # Generates invoices only
end

class PaymentProcessorAgent < RAAF::DSL::Agent
  # Processes payments only
end

# Bad: Too many responsibilities
class BillingAgent < RAAF::DSL::Agent
  # Generates invoices AND processes payments AND sends emails
end
```

### 2. Use Transformation for Security
```ruby
class UserAgent < RAAF::DSL::Agent
  private
  
  def prepare_user_for_context(user)
    # Never include sensitive fields
    user.attributes.except(
      "password_digest",
      "reset_token",
      "api_key",
      "session_token"
    )
  end
end
```

### 3. Validate Critical Parameters
```ruby
class CriticalOperationAgent < RAAF::DSL::Agent
  context do
    requires :user, :operation
    validate :user, type: User
    validate :operation, with: ->(op) { 
      ALLOWED_OPERATIONS.include?(op)
    }
  end
end
```

### 4. Use Computed Context for Derived Values
```ruby
class AnalyticsAgent < RAAF::DSL::Agent
  private
  
  # Don't pass these as parameters, compute them
  def build_statistics_context
    calculate_statistics(get(:data))
  end
  
  def build_metadata_context
    {
      generated_at: Time.now,
      version: "1.0",
      data_points: get(:data).count
    }
  end
end
```

### 5. Document Your Agents
```ruby
# Good: Clear documentation
class RecommendationAgent < RAAF::DSL::Agent
  # Generates personalized product recommendations based on user history
  #
  # @param user [User] The user to generate recommendations for
  # @param limit [Integer] Maximum number of recommendations (default: 10)
  # @param category [String, nil] Optional category filter
  #
  # @example
  #   agent = RecommendationAgent.new(
  #     user: current_user,
  #     limit: 5,
  #     category: "electronics"
  #   )
  #   recommendations = agent.generate
  #
  agent_name "RecommendationAgent"
  
  context do
    requires :user
    validate :limit, with: ->(v) { v > 0 && v <= 100 }
  end
end
```

## Next Steps

- Explore [Advanced Patterns](./advanced_patterns.md)
- Learn about [Context DSL](./context_dsl_guide.md)
- See [Troubleshooting Guide](./troubleshooting.md)
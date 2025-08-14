# Migration Guide: Upgrading to Auto-Context

## Overview

This guide helps you migrate existing RAAF agents to use the new auto-context feature. The migration is **completely optional** - all existing agents continue to work without changes.

## Migration Benefits

- **90% less boilerplate code** - Remove manual context building
- **Cleaner agents** - No more initialize methods for simple cases
- **Better maintainability** - Less code to maintain
- **Improved readability** - Focus on business logic

## Migration Strategy

### Option 1: Gradual Migration (Recommended)

1. New agents use auto-context by default
2. Migrate existing agents as you modify them
3. Keep complex agents unchanged if they work well

### Option 2: Bulk Migration

1. Identify simple agents (minimal initialize logic)
2. Migrate simple agents first
3. Test thoroughly
4. Migrate complex agents carefully

## Simple Agent Migration

### Before: Manual Context Building

```ruby
class StakeholderClassification < ApplicationAgent
  def initialize(stakeholders:, prospect:, product:)
    @stakeholders = stakeholders
    @prospect = prospect
    @product = product
    
    context = RAAF::DSL::ContextVariables.new
      .set(:stakeholders, prepare_stakeholders(@stakeholders))
      .set(:prospect, @prospect)
      .set(:product, @product)
      .set(:config, load_config)
    
    super(context: context)
  end
  
  private
  
  def prepare_stakeholders(stakeholders)
    stakeholders.map { |s| s.attributes.slice(:id, :name, :title) }
  end
  
  def load_config
    { confidence_threshold: 0.8 }
  end
end
```

### After: With Auto-Context

```ruby
class StakeholderClassification < ApplicationAgent
  # No initialize method needed!
  
  private
  
  # Optional: Transform stakeholders automatically
  def prepare_stakeholders_for_context(stakeholders)
    stakeholders.map { |s| s.attributes.slice(:id, :name, :title) }
  end
  
  # Optional: Add computed config
  def build_config_context
    { confidence_threshold: 0.8 }
  end
end
```

## Complex Agent Migration

### Before: Complex Initialization

```ruby
class MarketAnalysisAgent < ApplicationAgent
  def initialize(company:, market_data:, options: {})
    @company = company
    @market_data = process_market_data(market_data)
    @analysis_depth = options[:depth] || 'standard'
    
    # Complex context building
    context_builder = RAAF::DSL::ContextBuilder.new
    
    context_builder.with(:company, extract_company_data(@company))
    context_builder.with(:market, @market_data)
    context_builder.with(:analysis_config, build_analysis_config)
    
    if @analysis_depth == 'deep'
      context_builder.with(:competitors, fetch_competitors(@company))
      context_builder.with(:historical_data, fetch_historical_data)
    end
    
    super(context: context_builder.build)
  end
  
  private
  
  def process_market_data(data)
    # Complex processing
  end
  
  def extract_company_data(company)
    # Data extraction
  end
  
  def build_analysis_config
    # Config building
  end
end
```

### After: Simplified with Auto-Context

```ruby
class MarketAnalysisAgent < ApplicationAgent
  # Configure what gets included
  context do
    exclude :raw_market_data  # Exclude raw data if processed version is used
  end
  
  private
  
  # Transform company parameter
  def prepare_company_for_context(company)
    extract_company_data(company)
  end
  
  # Transform market_data parameter
  def prepare_market_data_for_context(market_data)
    process_market_data(market_data)
  end
  
  # Add computed context
  def build_analysis_config_context
    build_analysis_config
  end
  
  def build_competitors_context
    # Only called if needed
    depth = get(:options, {})[:depth] || 'standard'
    return nil unless depth == 'deep'
    fetch_competitors(get(:company))
  end
  
  def build_historical_data_context
    depth = get(:options, {})[:depth] || 'standard'
    return nil unless depth == 'deep'
    fetch_historical_data
  end
  
  # Original helper methods remain unchanged
  def process_market_data(data)
    # Same implementation
  end
  
  def extract_company_data(company)
    # Same implementation
  end
end
```

## Service Integration Migration

### Before: Services Building Context

```ruby
class ProspectAnalysisService
  def analyze(prospect)
    # Manual context building
    context = RAAF::DSL::ContextVariables.new
      .set(:prospect, prospect)
      .set(:company, prospect.company)
      .set(:market, prospect.market)
      .set(:stakeholders, prospect.stakeholders)
      .set(:config, analysis_config)
    
    agent = AnalysisAgent.new(context: context)
    agent.run
  end
  
  private
  
  def analysis_config
    { depth: 'deep', include_competitors: true }
  end
end
```

### After: Direct Parameter Passing

```ruby
class ProspectAnalysisService
  def analyze(prospect)
    # Just pass parameters directly!
    agent = AnalysisAgent.new(
      prospect: prospect,
      company: prospect.company,
      market: prospect.market,
      stakeholders: prospect.stakeholders,
      config: analysis_config
    )
    agent.run
  end
  
  private
  
  def analysis_config
    { depth: 'deep', include_competitors: true }
  end
end
```

## Step-by-Step Migration Process

### 1. Identify Migration Candidates

```ruby
# Simple agents (good candidates):
# - Minimal initialize logic
# - Just setting instance variables
# - Simple context building

# Complex agents (migrate carefully):
# - Complex initialization logic
# - Conditional context building
# - External service calls in initialize
```

### 2. Test Existing Behavior

```ruby
# Before migration, capture existing behavior
RSpec.describe StakeholderClassification do
  it "produces expected context" do
    agent = StakeholderClassification.new(
      stakeholders: stakeholders,
      prospect: prospect,
      product: product
    )
    
    # Capture current context
    expect(agent.context.to_h).to eq(expected_context)
  end
end
```

### 3. Migrate the Agent

Remove initialize method and add transformation methods:

```ruby
class StakeholderClassification < ApplicationAgent
  # Delete initialize method
  
  private
  
  # Add preparation methods as needed
  def prepare_stakeholders_for_context(stakeholders)
    # Same logic from initialize
  end
end
```

### 4. Verify Behavior

```ruby
# After migration, verify same behavior
RSpec.describe StakeholderClassification do
  it "produces same context with auto-context" do
    agent = StakeholderClassification.new(
      stakeholders: stakeholders,
      prospect: prospect,
      product: product
    )
    
    # Should produce same context
    expect(agent.context.to_h).to eq(expected_context)
  end
end
```

## Common Patterns

### Pattern 1: ActiveRecord to Hash

```ruby
# Before
def initialize(user:)
  context = ContextVariables.new.set(:user, {
    id: user.id,
    name: user.name,
    email: user.email
  })
  super(context: context)
end

# After
def prepare_user_for_context(user)
  { id: user.id, name: user.name, email: user.email }
end
```

### Pattern 2: Config Loading

```ruby
# Before
def initialize(data:)
  context = ContextVariables.new
    .set(:data, data)
    .set(:config, load_config)
  super(context: context)
end

# After
def build_config_context
  load_config
end
```

### Pattern 3: Conditional Context

```ruby
# Before
def initialize(user:, include_history: false)
  context = ContextVariables.new.set(:user, user)
  if include_history
    context = context.set(:history, user.history)
  end
  super(context: context)
end

# After
def build_history_context
  return nil unless get(:include_history)
  get(:user).history
end
```

## Rollback Plan

If you encounter issues after migration, you can easily rollback:

### Option 1: Disable Auto-Context

```ruby
class ProblematicAgent < ApplicationAgent
  auto_context false  # Disable auto-context
  
  def initialize(...)
    # Restore original initialize
  end
end
```

### Option 2: Pass Context Explicitly

```ruby
class ProblematicAgent < ApplicationAgent
  def initialize(data:)
    # When context: is passed, auto-context is bypassed
    context = build_custom_context(data)
    super(context: context)
  end
end
```

## Testing Migrated Agents

```ruby
RSpec.describe "Auto-Context Migration" do
  describe StakeholderClassification do
    let(:agent) do
      StakeholderClassification.new(
        stakeholders: create_list(:stakeholder, 3),
        prospect: create(:prospect),
        product: create(:product)
      )
    end
    
    it "has all expected context keys" do
      expect(agent.context_keys).to include(
        :stakeholders, :prospect, :product
      )
    end
    
    it "transforms stakeholders correctly" do
      stakeholders = agent.get(:stakeholders)
      expect(stakeholders).to all(
        include(:id, :name, :title)
      )
    end
    
    it "includes computed context" do
      expect(agent.has?(:config)).to be true
      expect(agent.get(:config)).to include(
        confidence_threshold: 0.8
      )
    end
  end
end
```

## Troubleshooting

### Issue: Missing Context Keys

```ruby
# If context keys are missing after migration
class Agent < ApplicationAgent
  def initialize(...)
    super(...)  # Make sure to call super with all parameters
  end
end
```

### Issue: Context Not Building

```ruby
# Check auto_context is not disabled
class Agent < ApplicationAgent
  # Remove this line if present:
  # auto_context false
end
```

### Issue: Parameters Not Transformed

```ruby
# Ensure method naming is correct
def prepare_user_for_context(user)  # Correct
def prepare_user(user)               # Wrong - won't be called
```

## Migration Checklist

- [ ] Identify agents to migrate
- [ ] Write tests for current behavior
- [ ] Remove initialize method
- [ ] Add prepare_*_for_context methods if needed
- [ ] Add build_*_context methods for computed values
- [ ] Run tests to verify behavior
- [ ] Update service integrations
- [ ] Monitor for issues
- [ ] Document any custom patterns
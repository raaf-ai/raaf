# RAAF Object Proxy Guide

## Overview

The RAAF Object Proxy system provides a powerful way to automatically handle objects in context without manual field mapping. It enables lazy loading, access control, and smart serialization for any Ruby object.

## Table of Contents

1. [Introduction](#introduction)
2. [Core Components](#core-components)
3. [Basic Usage](#basic-usage)
4. [Advanced Features](#advanced-features)
5. [Integration with RAAF](#integration-with-raaf)
6. [Performance Considerations](#performance-considerations)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

## Introduction

### Problem Statement

When building AI agent contexts, developers often need to:
- Manually map object fields to context variables
- Handle nested objects and associations
- Control which attributes are exposed
- Manage serialization for different object types

This leads to verbose, error-prone code:

```ruby
# Without Object Proxy (tedious manual mapping)
context = RAAF::DSL::ContextVariables.new
context = context.set(:product_id, product.id)
context = context.set(:product_name, product.name)
context = context.set(:product_price, product.price)
context = context.set(:category_name, product.category&.name)
# ... many more manual mappings
```

### Solution

The Object Proxy system automates this process:

```ruby
# With Object Proxy (automatic!)
context = RAAF::DSL::ContextBuilder.new
  .with_object(:product, product)
  .build

# Access any attribute lazily
product_name = context.get(:product).name
category = context.get(:product).category.name
```

## Core Components

### 1. ObjectProxy

The `ObjectProxy` class wraps any Ruby object and provides:
- **Lazy attribute access**: Attributes are only loaded when accessed
- **Access control**: Whitelist/blacklist specific attributes
- **Caching**: Optional caching of accessed values
- **Nested proxying**: Automatically wrap associated objects

### 2. ObjectSerializer

The `ObjectSerializer` module handles intelligent serialization:
- **Type detection**: Automatically detects object type (ActiveRecord, Struct, PORO, etc.)
- **Smart conversion**: Uses appropriate serialization method for each type
- **Circular reference handling**: Prevents infinite loops
- **Depth limiting**: Controls serialization depth

### 3. ContextBuilder

Enhanced with object proxy support:
- **Fluent interface**: Chain multiple object additions
- **Automatic proxying**: Wraps objects transparently
- **Validation support**: Ensure required objects are present

## Basic Usage

### Simple Object Proxying

```ruby
# Create a context with proxied objects
builder = RAAF::DSL::ContextBuilder.new

# Add a single object
builder.with_object(:user, current_user)

# Add multiple objects
builder.with_objects(
  product: product,
  company: company,
  user: current_user
)

# Build the context
context = builder.build

# Access proxied objects
user_name = context.get(:user).name
user_email = context.get(:user).email
```

### Access Control

Control which attributes are accessible:

```ruby
# Whitelist specific attributes
builder.with_object(:user, user, 
  only: [:id, :name, :email]
)

# Blacklist sensitive attributes
builder.with_object(:user, user,
  except: [:password_digest, :api_key]
)

# Include specific methods
builder.with_object(:product, product,
  only: [:id, :name],
  methods: [:calculated_price, :availability_status]
)
```

### Working with Different Object Types

The system handles various Ruby object types automatically:

```ruby
# ActiveRecord models
builder.with_object(:user, User.find(1))

# Plain Ruby objects
builder.with_object(:service, MyService.new)

# Structs
Customer = Struct.new(:name, :email)
builder.with_object(:customer, Customer.new("John", "john@example.com"))

# OpenStruct
require 'ostruct'
builder.with_object(:config, OpenStruct.new(api_key: "secret", timeout: 30))

# Even hashes (accessed via [] notation)
builder.with_object(:settings, { theme: "dark", language: "en" })
```

## Advanced Features

### Nested Object Handling

Objects with associations are automatically proxied:

```ruby
# Given: product.category.parent.name
builder.with_object(:product, product, depth: 3)

context = builder.build

# All of these work with lazy loading:
product_name = context.get(:product).name
category_name = context.get(:product).category.name
parent_category = context.get(:product).category.parent.name
```

### Caching Control

Control caching behavior for performance:

```ruby
# Disable caching (always fetch fresh values)
builder.with_object(:product, product, cache: false)

# Default behavior caches attribute access
builder.with_object(:product, product) # cache: true by default
```

### Custom Serialization

When you need to serialize the context:

```ruby
# Serialize to hash (proxies are automatically resolved)
hash = context.to_h

# Control serialization
hash = context.to_h(serialize_proxies: true)  # Default
hash = context.to_h(serialize_proxies: false) # Keep proxy objects

# JSON serialization
json = context.to_json
```

## Integration with RAAF

### In AI Agents

Use object proxies in your AI agents for cleaner code:

```ruby
class ProductAnalysisAgent < RAAF::DSL::Agents::Base
  def initialize(product:, company:)
    # Build context with objects
    context = RAAF::DSL::ContextBuilder.new
      .with_object(:product, product, 
        only: [:id, :name, :description, :price],
        methods: [:availability_status]
      )
      .with_object(:company, company,
        only: [:id, :name, :market_cap]
      )
      .build
    
    super(context: context)
  end
  
  def build_user_prompt
    # Access objects naturally
    product = context.get(:product)
    company = context.get(:company)
    
    <<~PROMPT
      Analyze this product:
      - Name: #{product.name}
      - Price: $#{product.price}
      - Status: #{product.availability_status}
      
      From company: #{company.name}
    PROMPT
  end
end
```

### In Orchestrators

Orchestrators can pass contexts between agents efficiently:

```ruby
class MarketAnalysisOrchestrator < RAAF::DSL::Orchestrator
  def run(company:, products:)
    # Build context once
    context = RAAF::DSL::ContextBuilder.new
      .with_object(:company, company)
      .with_objects(products.map.with_index { |p, i| ["product_#{i}", p] }.to_h)
      .build
    
    # Pass to multiple agents
    market_result = MarketAgent.new(context: context).run
    
    # Update context with results
    context = context.set(:market_analysis, market_result)
    
    # Pass enriched context to next agent
    CompetitorAgent.new(context: context).run
  end
end
```

### In Services

Services can build contexts for AI operations:

```ruby
class ProductRecommendationService
  def call(user:, category:)
    # Build context with access control
    context = RAAF::DSL::ContextBuilder.new
      .with_object(:user, user,
        only: [:id, :preferences, :purchase_history],
        except: [:password_digest, :payment_info]
      )
      .with_object(:category, category,
        methods: [:top_products, :trending_items]
      )
      .build
    
    # Use context in AI agent
    RecommendationAgent.new(context: context).run
  end
end
```

## Performance Considerations

### Lazy Loading Benefits

Attributes are only loaded when accessed:

```ruby
# This is fast - no attribute access yet
context = builder.with_object(:large_product, product).build

# Only these specific attributes are loaded
name = context.get(:large_product).name  # Loads only 'name'
price = context.get(:large_product).price # Loads only 'price'
# Other attributes remain unloaded
```

### Caching Strategy

Default caching prevents repeated method calls:

```ruby
product_proxy = context.get(:product)

# First access - calls product.expensive_calculation
result1 = product_proxy.expensive_calculation

# Subsequent accesses use cached value
result2 = product_proxy.expensive_calculation # From cache
```

### Memory Usage

Control memory usage with depth limits:

```ruby
# Limit nesting depth to prevent deep object graphs
builder.with_object(:root, deep_nested_object, depth: 2)
```

## Best Practices

### 1. Use Specific Access Control

Be explicit about what attributes agents need:

```ruby
# Good - Explicit access control
builder.with_object(:user, user,
  only: [:id, :name, :email, :tier],
  methods: [:active?]
)

# Avoid - Exposing everything
builder.with_object(:user, user) # All attributes accessible
```

### 2. Handle Nil Objects

Always handle potential nil values:

```ruby
# Safe nil handling
builder.with_object(:product, product) # with_object handles nil gracefully

# In agent
product = context.get(:product)
name = product&.name || "Unknown Product"
```

### 3. Use Meaningful Context Keys

Choose descriptive keys for clarity:

```ruby
# Good - Clear context keys
builder
  .with_object(:current_user, user)
  .with_object(:target_product, product)
  .with_object(:competitor_company, competitor)

# Avoid - Ambiguous keys
builder
  .with_object(:u, user)
  .with_object(:p, product)
  .with_object(:c, competitor)
```

### 4. Optimize for Common Access Patterns

Structure your proxy options based on usage:

```ruby
# If you frequently access nested data
builder.with_object(:order, order,
  only: [:id, :total, :status, :line_items],
  depth: 2  # Allow line_items.product access
)

# If you only need top-level data
builder.with_object(:order, order,
  only: [:id, :total, :status],
  depth: 1  # Prevent nested loading
)
```

## Troubleshooting

### Issue: "Unknown Company" in AI Responses

**Symptom**: AI agents report "Unknown Company" despite data being present.

**Cause**: Context not properly capturing values due to immutable pattern.

**Solution**:
```ruby
# WRONG - Context remains empty
context = RAAF::DSL::ContextVariables.new
context.set(:company, company) # Return value not captured!

# CORRECT - Capture returned instance
context = RAAF::DSL::ContextVariables.new
context = context.set(:company, company) # Capture new instance

# BETTER - Use ContextBuilder
context = RAAF::DSL::ContextBuilder.new
  .with_object(:company, company)
  .build
```

### Issue: Circular Reference Errors

**Symptom**: Stack level too deep or circular reference detected.

**Solution**:
```ruby
# Use depth limiting
builder.with_object(:category, category, depth: 2)

# Or exclude circular associations
builder.with_object(:category, category,
  except: [:parent] # Exclude circular reference
)
```

### Issue: Missing Methods

**Symptom**: NoMethodError on proxied objects.

**Solution**:
```ruby
# Include required methods explicitly
builder.with_object(:product, product,
  methods: [:custom_method, :calculated_field]
)

# Or check if method exists
if context.get(:product).respond_to?(:custom_method)
  result = context.get(:product).custom_method
end
```

### Issue: Performance with Large Objects

**Symptom**: Slow context building or serialization.

**Solution**:
```ruby
# Limit attributes to what's needed
builder.with_object(:large_object, obj,
  only: [:id, :name, :essential_field]
)

# Disable caching if memory is a concern
builder.with_object(:large_object, obj,
  cache: false
)

# Use shallow depth
builder.with_object(:complex_tree, tree,
  depth: 1
)
```

## Migration Guide

### From Manual Mapping

Before:
```ruby
# Manual field mapping
context = RAAF::DSL::ContextVariables.new
context = context.set(:user_id, user.id)
context = context.set(:user_name, user.name)
context = context.set(:user_email, user.email)
context = context.set(:company_name, user.company&.name)
```

After:
```ruby
# Automatic with object proxy
context = RAAF::DSL::ContextBuilder.new
  .with_object(:user, user)
  .build

# Access the same data
user_id = context.get(:user).id
company_name = context.get(:user).company.name
```

### From Hash Conversion

Before:
```ruby
# Convert to hash first
user_data = {
  id: user.id,
  name: user.name,
  email: user.email,
  company: user.company.attributes
}
context = context.set(:user_data, user_data)
```

After:
```ruby
# Direct object usage
context = RAAF::DSL::ContextBuilder.new
  .with_object(:user, user)
  .build
```

## Summary

The RAAF Object Proxy system eliminates manual field mapping and provides a clean, efficient way to work with objects in AI agent contexts. Key benefits:

1. **Less Code**: No more manual field mapping
2. **Better Performance**: Lazy loading and caching
3. **Safer**: Access control and nil handling
4. **Flexible**: Works with any Ruby object
5. **Maintainable**: Clear, declarative code

Start using object proxies today to simplify your RAAF agent development!
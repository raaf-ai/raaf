# RAAF Context Management Guide

This guide covers the new context management features in RAAF DSL that help prevent common errors and simplify agent development.

> **📝 Note**: This guide covers the original ContextPipeline approach. For the newer, more elegant Pipeline DSL with `>>` and `|` operators, see the **[Pipeline DSL Guide](../../docs/PIPELINE_DSL_GUIDE.md)** which reduces 66+ line pipeline definitions to just 3 lines.

## Table of Contents

1. [ContextBuilder - Fluent Context Building](#contextbuilder)
2. [ContextPipeline - Agent Orchestration](#contextpipeline)
3. [ContextValidation - Type-Safe Context](#contextvalidation)
4. [DataAccessHelper - Mixed Key Handling](#dataaccesshelper)
5. [Best Practices](#best-practices)

## ContextBuilder

The `ContextBuilder` provides a fluent interface for building `ContextVariables` instances, preventing common errors with the immutable pattern.

### Problem It Solves

The RAAF `ContextVariables` class uses an immutable pattern where `.set()` returns a new instance. Developers often forget to capture the returned value:

```ruby
# ❌ WRONG - Context remains empty!
context = RAAF::DSL::ContextVariables.new
context.set(:product, product)  # New instance not captured
context.set(:company, company)  # New instance not captured
# Result: context is still empty!
```

### Solution with ContextBuilder

```ruby
# ✅ CORRECT - Fluent interface handles immutability
context = RAAF::DSL::ContextBuilder.new
  .with(:product, product)
  .with(:company, company)
  .with(:analysis_depth, "detailed")
  .build
```

### Basic Usage

```ruby
# Simple context building
context = RAAF::DSL::ContextBuilder.new
  .with(:name, "John")
  .with(:age, 30)
  .build

# From existing context
existing = RAAF::DSL::ContextVariables.new(name: "John")
context = RAAF::DSL::ContextBuilder.from(existing)
  .with(:age, 30)
  .build

# With initial values
context = RAAF::DSL::ContextBuilder.new(name: "John")
  .with(:age, 30)
  .build
```

### Validation Features

```ruby
builder = RAAF::DSL::ContextBuilder.new

# Type validation
builder.with(:age, 30, type: Integer)
builder.with(:email, "user@example.com", type: String)

# Custom validation
builder.with(:score, 85, validate: -> (v) { v.between?(0, 100) })

# Required fields
builder
  .requires(:name, :email)
  .with(:name, "John")
  .with(:email, "john@example.com")
  .build! # Raises error if required fields missing
```

### Conditional Building

```ruby
builder = RAAF::DSL::ContextBuilder.new

# Add only if condition is true
builder.with_if(user.premium?, :tier, "premium")

# Add only if value is present (not nil)
builder.with_present(:optional_field, params[:optional])

# Add multiple at once
builder.with_all(
  name: "John",
  age: 30,
  city: "NYC"
)
```

### Real-World Example

```ruby
class MarketAnalysisService
  def build_analysis_context(product, options = {})
    RAAF::DSL::ContextBuilder.new
      .requires(:product, :company)
      .with(:product, product, type: Product)
      .with(:company, product.company, type: Company)
      .with(:analysis_depth, options[:depth] || "standard")
      .with_if(options[:debug], :debug_mode, true)
      .with_present(:focus_market, options[:market])
      .build!
  end
end
```

## ContextPipeline

The `ContextPipeline` simplifies multi-agent workflows by automatically flowing context and results between agents.

### Problem It Solves

Orchestrating multiple agents requires repetitive context building and result handling:

```ruby
# ❌ TEDIOUS - Manual context management for each agent
analysis_context = RAAF::DSL::ContextVariables.new
analysis_context = analysis_context.set(:product, product)
analysis_agent = Market::Analysis.new(context: analysis_context)
analysis_result = analysis_agent.call

scoring_context = RAAF::DSL::ContextVariables.new
scoring_context = scoring_context.set(:product, product)
scoring_context = scoring_context.set(:markets, analysis_result[:markets])
scoring_agent = Market::Scoring.new(context: scoring_context)
scoring_result = scoring_agent.call
# ... and so on
```

### Solution with ContextPipeline

```ruby
# ✅ ELEGANT - Automatic context flow
pipeline = RAAF::DSL::ContextPipeline.new(product: product, company: company)
  .pipe(Market::Analysis, :analysis)
  .pipe(Market::Scoring, :scoring, markets: -> (ctx) { ctx.get(:analysis)[:markets] })
  .pipe(Market::SearchTermGenerator, :search_terms)
  .execute
```

### Basic Usage

```ruby
# Simple pipeline
pipeline = RAAF::DSL::ContextPipeline.new(initial_data: "value")
  .pipe(FirstAgent, :first_result)
  .pipe(SecondAgent, :second_result)
  .execute

# Access results
all_results = pipeline.results
first_result = pipeline.result(:first_result)
success = pipeline.success?
```

### Dynamic Context

```ruby
# Static context additions
pipeline.pipe(Agent, :result, debug: true, max_items: 10)

# Dynamic context from previous results
pipeline.pipe(ScoringAgent, :scores, 
  markets: -> (ctx) { ctx.get(:analysis)[:markets] }
)

# Multiple dynamic values
pipeline.pipe(EnrichmentAgent, :enriched,
  company_ids: -> (ctx) { ctx.get(:companies).map(&:id) },
  threshold: -> (ctx) { ctx.get(:config)[:min_score] }
)
```

### Conditional Execution

```ruby
pipeline = RAAF::DSL::ContextPipeline.new(score: 85)
  .pipe(BasicAnalysis, :basic)
  .pipe_if(
    -> (ctx) { ctx.get(:basic)[:score] > 80 },
    DetailedAnalysis,
    :detailed
  )
  .pipe_if(
    -> (ctx) { ctx.get(:detailed)[:high_value] },
    PremiumEnrichment,
    :premium
  )
  .execute
```

### Error Handling

```ruby
pipeline = RAAF::DSL::ContextPipeline.new(data: input)
  .on_error do |error, stage_info|
    Rails.logger.error "Pipeline failed at #{stage_info[:agent_class]}: #{error.message}"
    ErrorNotifier.notify(error, stage_info)
  end
  .pipe(DataGatherer, :raw_data)
  .pipe(DataProcessor, :processed)
  .execute

# Continue on error
results = pipeline.execute(halt_on_error: false)
```

### Hooks and Monitoring

```ruby
pipeline = RAAF::DSL::ContextPipeline.new
  .before_stage do |stage_info, context|
    Rails.logger.info "Starting #{stage_info[:agent_class]}"
    StatsD.increment("pipeline.stage.started", tags: ["agent:#{stage_info[:agent_class]}"])
  end
  .after_stage do |stage_info, result, context|
    duration = stage_info[:duration_ms]
    StatsD.histogram("pipeline.stage.duration", duration, tags: ["agent:#{stage_info[:agent_class]}"])
  end
  .pipe(Agent1, :result1)
  .pipe(Agent2, :result2)
  .execute
```

### Real-World Example

```ruby
class MarketDiscoveryOrchestrator
  def discover_markets(product, company)
    RAAF::DSL::ContextPipeline.new(product: product, company: company)
      .on_error { |e, stage| handle_pipeline_error(e, stage) }
      .before_stage { |stage, ctx| log_stage_start(stage) }
      .pipe(Market::Analysis, :analysis)
      .pipe(Market::Scoring, :scoring, 
        markets: -> (ctx) { ctx.get(:analysis)[:markets] }
      )
      .pipe_if(
        -> (ctx) { ctx.get(:scoring)[:scored_markets].any? },
        Market::SearchTermGenerator,
        :search_terms,
        markets: -> (ctx) { ctx.get(:scoring)[:scored_markets] }
      )
      .execute
  end
  
  private
  
  def handle_pipeline_error(error, stage_info)
    ErrorTracker.track_exception(error, {
      pipeline: "market_discovery",
      stage: stage_info[:agent_class].name,
      stage_number: stage_info[:stage_number]
    })
  end
end
```

## ContextValidation

The `ContextValidation` module provides a DSL for declaring and validating agent context requirements.

### Problem It Solves

Agents often receive invalid or missing context data, leading to runtime errors:

```ruby
# ❌ BASIC - Only checks key presence
def validate_context!(context)
  missing = REQUIRED_KEYS.reject { |k| context.key?(k) }
  raise "Missing: #{missing}" if missing.any?
end
# Doesn't validate types, values, or relationships
```

### Solution with ContextValidation

```ruby
# ✅ COMPREHENSIVE - Full validation with clear errors
class MyAgent < RAAF::DSL::Agent
  include RAAF::DSL::Agents::ContextValidation
  
  # Mock Product class for example
  Product = Struct.new(:name, :category) unless defined?(Product)
  
  validates_context :product, required: true, type: Product
  validates_context :score, type: Integer, validate: -> (v) { v.between?(0, 100) }
  validates_context :email, validate: -> (v) { v =~ URI::MailTo::EMAIL_REGEXP }
end
```

### Basic Usage

```ruby
class AnalysisAgent < RAAF::DSL::Agent
  include RAAF::DSL::Agents::ContextValidation
  
  # Required fields
  validates_context :product, required: true
  validates_context :company, required: true
  
  # Type validation
  validates_context :markets, type: Array
  validates_context :config, type: Hash
  
  # Multiple types allowed
  validates_context :identifier, type: [String, Integer]
  
  # Shorthand for multiple required fields
  requires_context :product, :company, :user
end
```

### Custom Validation

```ruby
class ScoringAgent < RAAF::DSL::Agent
  include RAAF::DSL::Agents::ContextValidation
  
  # Inline validation
  validates_context :score, 
    type: Integer,
    validate: -> (v) { v >= 0 && v <= 100 },
    message: "must be between 0 and 100"
  
  # Complex validation
  validates_context :email,
    type: String,
    validate: -> (v) { v.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i) },
    message: "must be a valid email address"
  
  # Nil handling
  validates_context :optional_field,
    type: String,
    allow_nil: true  # Allows nil values
    
  validates_context :required_string,
    type: String,
    allow_nil: false  # Rejects nil values
end
```

### Built-in Validators

```ruby
class ValidationExampleAgent < RAAF::DSL::Agent
  include RAAF::DSL::Agents::ContextValidation
  
  # Use predefined validators
  validates_context :name, 
    validate: RAAF::DSL::Agents::ContextValidators::NOT_BLANK
    
  validates_context :age,
    validate: RAAF::DSL::Agents::ContextValidators::POSITIVE
    
  validates_context :score,
    validate: RAAF::DSL::Agents::ContextValidators::PERCENTAGE
    
  validates_context :email,
    validate: RAAF::DSL::Agents::ContextValidators::EMAIL
    
  validates_context :website,
    validate: RAAF::DSL::Agents::ContextValidators::URL
    
  # Factory validators
  validates_context :role,
    validate: RAAF::DSL::Agents::ContextValidators.included_in(%w[admin user guest])
    
  validates_context :username,
    validate: RAAF::DSL::Agents::ContextValidators.length_between(3, 20)
    
  validates_context :tags,
    type: Array,
    validate: RAAF::DSL::Agents::ContextValidators.array_size_between(1, 10)
    
  validates_context :confidence,
    type: Integer,
    validate: RAAF::DSL::Agents::ContextValidators.between(0, 100)
end
```

### Error Messages

```ruby
# When validation fails, you get detailed error messages:
# ContextValidationError: Context validation failed with 3 error(s):
#   - Context key 'product' is required but was not provided
#   - Context key 'score' must be Integer but was String
#   - Context key 'email' must be a valid email address
# 
# Context keys present: [:score, :email, :name]
```

### Real-World Example

```ruby
class ProspectScoringAgent < RAAF::DSL::Agent
  include RAAF::DSL::Agents::ContextValidation
  
  # Mock classes for example
  Prospect = Struct.new(:name, :company, :email) unless defined?(Prospect)
  Product = Struct.new(:name, :category, :features) unless defined?(Product)
  
  # Required business objects
  validates_context :prospect, required: true, type: Prospect
  validates_context :product, required: true, type: Product
  validates_context :scoring_config, required: true, type: Hash
  
  # Scoring parameters
  validates_context :threshold_score,
    type: Integer,
    validate: RAAF::DSL::Agents::ContextValidators.between(0, 100),
    message: "must be a percentage between 0 and 100"
    
  validates_context :scoring_dimensions,
    type: Array,
    validate: -> (v) { v.all? { |d| %w[firmographics technographics intent].include?(d) } },
    message: "must only contain valid dimension types"
    
  validates_context :analysis_depth,
    validate: RAAF::DSL::Agents::ContextValidators.included_in(%w[basic standard detailed]),
    message: "must be one of: basic, standard, detailed"
    
  # Optional enrichment data
  validates_context :enrichment_data,
    type: Hash,
    allow_nil: true
    
  def call
    # Context is guaranteed to be valid here
    score_prospect
  end
end
```

## DataAccessHelper

The `DataAccessHelper` module provides utilities for safely accessing hash data with mixed string/symbol keys.

### Problem It Solves

Data from different sources often has inconsistent key types:

```ruby
# ❌ FRAGILE - Fails with mixed key types
def process_data(response)
  # Works only if key is a string
  results = response["results"]
  
  # Works only if key is a symbol
  company = response[:company]
  
  # Verbose fallback pattern
  query = response["query"] || response[:query]
end
```

### Solution with DataAccessHelper

```ruby
# ✅ ROBUST - Works with any key type
include RAAF::DSL::DataAccessHelper

def process_data(response)
  results = safe_get(response, :results)
  company = safe_get(response, :company)
  query = safe_get(response, :query)
end
```

### Basic Usage

```ruby
include RAAF::DSL::DataAccessHelper

# Safe get with mixed keys
data = { "name" => "John", age: 30 }
safe_get(data, :name)     # => "John"
safe_get(data, "age")     # => 30
safe_get(data, :missing, "default")  # => "default"

# Safe dig through nested data
nested = { "user" => { name: "John", "address" => { city: "NYC" } } }
safe_dig(nested, :user, :name)          # => "John"
safe_dig(nested, "user", "address", :city)  # => "NYC"

# Check key existence
safe_key?(data, :name)    # => true
safe_key?(data, "age")    # => true
```

### Batch Operations

```ruby
# Fetch multiple keys at once
data = { "name" => "John", age: 30, "role" => "admin" }
result = safe_fetch_all(data, [:name, :age, :role, :missing])
# => { name: "John", age: 30, role: "admin", missing: nil }

# With defaults
result = safe_fetch_all(data, [:name, :missing], missing: "guest")
# => { name: "John", missing: "guest" }

# Extract subset
subset = safe_slice(data, [:name, :age])
# => { "name" => "John", age: 30 }
```

### Key Transformation

```ruby
# Transform keys using mapping
api_data = { "company_name" => "Acme", "company_size" => 100 }
mapping = { company_name: :name, company_size: :employees }

result = safe_transform_keys(api_data, mapping)
# => { name: "Acme", employees: 100 }

# Symbolize all keys deeply
data = { "user" => { "name" => "John", "tags" => ["ruby", "rails"] } }
symbolized = symbolize_keys_deep(data)
# => { user: { name: "John", tags: ["ruby", "rails"] } }

# Stringify all keys deeply
stringified = stringify_keys_deep(symbolized)
# => { "user" => { "name" => "John", "tags" => ["ruby", "rails"] } }
```

### Merging with Mixed Keys

```ruby
base = { "name" => "John", age: 30 }
updates = { name: "Jane", "role" => "admin" }

# Preserve original key types
merged = safe_merge(base, updates)
# => { "name" => "Jane", age: 30, "role" => "admin" }

# Symbolize all keys
merged = safe_merge(base, updates, symbolize: true)
# => { name: "Jane", age: 30, role: "admin" }
```

### Real-World Example

```ruby
class CompanyDataProcessor
  include RAAF::DSL::DataAccessHelper
  
  def process_search_results(search_data)
    # Handle inconsistent API responses
    search_data.map do |result|
      {
        query: safe_get(result, :query),
        total_results: safe_dig(result, :meta, :total) || 0,
        companies: process_companies(safe_get(result, :results, []))
      }
    end
  end
  
  private
  
  def process_companies(results)
    results.map do |company_data|
      # Transform inconsistent keys to standard format
      safe_transform_keys(company_data, {
        company_name: :name,
        company_website: :website,
        company_size: :employee_count,
        company_location: :headquarters
      }).tap do |company|
        # Ensure required fields have defaults
        company[:name] ||= "Unknown Company"
        company[:website] ||= generate_website(company[:name])
      end
    end
  end
  
  def generate_website(name)
    "https://#{name.downcase.gsub(/\s+/, '')}.com"
  end
end
```

## Best Practices

### 1. Use ContextBuilder for All Context Creation

```ruby
# ❌ Avoid direct ContextVariables manipulation
context = RAAF::DSL::ContextVariables.new
context = context.set(:key, value)  # Easy to forget assignment

# ✅ Use ContextBuilder
context = RAAF::DSL::ContextBuilder.new
  .with(:key, value)
  .build
```

### 2. Validate Context Early

```ruby
class CriticalAgent < RAAF::DSL::Agent
  include RAAF::DSL::Agents::ContextValidation
  
  # Validate at class level
  validates_context :critical_param, required: true, type: String
  
  # Additional runtime validation if needed
  def call
    raise "Invalid state" unless valid_state?
    process_data
  end
end
```

### 3. Use Pipelines for Multi-Agent Workflows

```ruby
# ❌ Manual orchestration
def process_manually
  agent1_result = Agent1.new(context: build_context1).call
  agent2_result = Agent2.new(context: build_context2(agent1_result)).call
  # Error handling, context building repeated...
end

# ✅ Pipeline orchestration
def process_with_pipeline
  RAAF::DSL::ContextPipeline.new(initial_context)
    .pipe(Agent1, :step1)
    .pipe(Agent2, :step2, data: -> (ctx) { ctx.get(:step1)[:data] })
    .execute
end
```

### 4. Handle Mixed Keys Defensively

```ruby
class APIClient
  include RAAF::DSL::DataAccessHelper
  
  def parse_response(response)
    # Don't assume key types
    {
      status: safe_get(response, :status, "unknown"),
      data: safe_dig(response, :body, :data) || [],
      error: safe_get(response, :error)
    }
  end
end
```

### 5. Combine Features for Robust Agents

```ruby
class RobustAgent < RAAF::DSL::Agent
  include RAAF::DSL::Agents::ContextValidation
  include RAAF::DSL::DataAccessHelper
  
  # Validate inputs
  validates_context :api_response, required: true, type: Hash
  validates_context :threshold, type: Integer, validate: -> (v) { v > 0 }
  
  def call
    # Safe data access
    results = safe_get(api_response, :results, [])
    
    # Process with confidence
    results.map do |item|
      process_item(item) if safe_get(item, :score, 0) >= threshold
    end.compact
  end
end
```

## Migration Guide

### From Raw ContextVariables

```ruby
# Before
context = RAAF::DSL::ContextVariables.new
context = context.set(:product, product)
context = context.set(:company, company)

# After
context = RAAF::DSL::ContextBuilder.new
  .with(:product, product)
  .with(:company, company)
  .build
```

### From Manual Orchestration

```ruby
# Before
analysis = AnalysisAgent.new(context: ctx1).call
scoring = ScoringAgent.new(context: ctx2.set(:analysis, analysis)).call

# After
pipeline = RAAF::DSL::ContextPipeline.new(initial_context)
  .pipe(AnalysisAgent, :analysis)
  .pipe(ScoringAgent, :scoring)
  .execute
```

### From Basic Validation

```ruby
# Before
raise "Missing product" unless context.key?(:product)
raise "Invalid score" unless context[:score].is_a?(Integer)

# After
validates_context :product, required: true
validates_context :score, type: Integer
```

### From Manual Key Handling

```ruby
# Before
value = hash["key"] || hash[:key] || default

# After
value = safe_get(hash, :key, default)
```
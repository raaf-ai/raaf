# ProspectsRadar Object Proxy Implementation Guide

## Overview

This guide explains how to implement the new RAAF Object Proxy system in ProspectsRadar to eliminate manual context field mapping and improve code maintainability.

## Current State Analysis

### Problem Areas in ProspectsRadar

1. **Manual Field Mapping in Services**
   - `ProspectDiscoveryService` manually maps fields
   - `OutreachCampaignService` has extensive field extraction
   - Repetitive and error-prone code

2. **Context Building Issues**
   - "Unknown Company" errors due to context misconfiguration
   - Immutable pattern confusion
   - Inconsistent context structure across agents

3. **Nested Object Access**
   - Complex chains like `prospect.company.industry.name`
   - Nil checking scattered throughout codebase
   - No consistent access control

## Implementation Strategy

### Phase 1: Update RAAF Gem

First, ensure the ProspectsRadar Gemfile references the latest RAAF version with object proxy support:

```ruby
# Gemfile
gem 'raaf', '~> 0.9.0'  # Or latest version with object proxy
```

Run bundle update:
```bash
bundle update raaf
```

### Phase 2: Refactor Service Context Building

#### Before (Current ProspectsRadar Code):

```ruby
# app/services/prospect_discovery_service.rb
def build_discovery_context
  # Manual field mapping - error prone!
  context = RAAF::DSL::ContextVariables.new
  context = context.set(:prospect_id, @prospect.id)
  context = context.set(:prospect_name, @prospect.name)
  context = context.set(:company_name, @prospect.company.name)
  context = context.set(:industry, @prospect.company.industry)
  context = context.set(:product_name, @product.name)
  context = context.set(:product_features, @product.features)
  # ... many more manual mappings
  
  context
end
```

#### After (With Object Proxy):

```ruby
# app/services/prospect_discovery_service.rb
def build_discovery_context
  RAAF::DSL::ContextBuilder.new
    .with_object(:prospect, @prospect,
      only: [:id, :name, :email, :role, :seniority],
      methods: [:full_name, :decision_maker?]
    )
    .with_object(:company, @prospect.company,
      only: [:id, :name, :industry, :size, :location],
      except: [:internal_notes]
    )
    .with_object(:product, @product,
      only: [:id, :name, :features, :benefits, :pricing_tier]
    )
    .build
end
```

### Phase 3: Update AI Agents

#### Market Analysis Agent

```ruby
# app/ai/agents/market/analysis.rb
module Ai
  module Agents
    module Market
      class Analysis < Ai::Agents::ApplicationAgent
        # Remove manual field extraction
        def product_description
          # OLD WAY - Manual extraction
          # "#{context.get(:product_name)} - #{context.get(:product_category)}"
          
          # NEW WAY - Direct object access
          product = context.get(:product)
          "#{product.name} - #{product.category.name}"
        end
        
        def company_profile
          # Access nested attributes safely
          company = context.get(:company)
          <<~PROFILE
            Company: #{company.name}
            Industry: #{company.industry}
            Size: #{company.size}
            Location: #{company.location}
          PROFILE
        end
      end
    end
  end
end
```

#### Outreach Message Generator

```ruby
# app/ai/agents/outreach/message_generator.rb
module Ai
  module Agents
    module Outreach
      class MessageGenerator < Ai::Agents::ApplicationAgent
        def build_user_prompt
          # Direct access to rich objects
          prospect = context.get(:prospect)
          company = context.get(:company)
          product = context.get(:product)
          
          <<~PROMPT
            Generate a personalized outreach message:
            
            Recipient: #{prospect.full_name} (#{prospect.role})
            Company: #{company.name} in #{company.industry}
            
            Our Product: #{product.name}
            Key Benefits: #{product.benefits.join(', ')}
            
            Their Pain Points: #{company.identified_pain_points.join(', ')}
          PROMPT
        end
      end
    end
  end
end
```

### Phase 4: Refactor Orchestrators

```ruby
# app/ai/agents/orchestrators/prospect_discovery.rb
module Ai
  module Agents
    module Orchestrators
      class ProspectDiscovery < Ai::Agents::ApplicationAgent
        def run
          # Build context once with all needed objects
          base_context = build_base_context
          
          # Step 1: Market Analysis
          market_result = Market::Analysis.new(context: base_context).call
          
          # Step 2: Company Search with enriched context
          enriched_context = base_context.set(:market_insights, market_result)
          companies = Company::Search.new(context: enriched_context).call
          
          # Step 3: Score each company
          scored_companies = companies.map do |company|
            # Add company to context for scoring
            scoring_context = base_context
              .set(:target_company, company)
              .set(:market_insights, market_result)
            
            Prospect::Scoring.new(context: scoring_context).call
          end
          
          scored_companies
        end
        
        private
        
        def build_base_context
          RAAF::DSL::ContextBuilder.new
            .with_object(:product, @product,
              only: [:id, :name, :features, :benefits, :target_market]
            )
            .with_object(:company, @company,
              only: [:id, :name, :industry, :ideal_customer_profile]
            )
            .with_object(:user, @current_user,
              only: [:id, :name, :organization_id],
              methods: [:subscription_tier]
            )
            .build
        end
      end
    end
  end
end
```

### Phase 5: Update Background Jobs

```ruby
# app/jobs/prospect_enrichment_job.rb
class ProspectEnrichmentJob < ApplicationJob
  def perform(prospect_id)
    prospect = Prospect.find(prospect_id)
    
    # Build context with controlled access
    context = RAAF::DSL::ContextBuilder.new
      .with_object(:prospect, prospect,
        only: [:id, :name, :email, :company_id, :linkedin_url]
      )
      .with_object(:company, prospect.company,
        only: [:id, :name, :domain, :industry]
      )
      .build
    
    # Run enrichment agent
    result = Ai::Agents::Prospect::Enrichment.new(context: context).call
    
    # Update prospect with results
    prospect.update!(enrichment_data: result)
  end
end
```

### Phase 6: Controller Integration

```ruby
# app/controllers/api/v1/prospects_controller.rb
class Api::V1::ProspectsController < ApplicationController
  def analyze
    # Build context for AI analysis
    context = RAAF::DSL::ContextBuilder.new
      .with_object(:prospect, @prospect,
        only: [:id, :name, :role, :company_id]
      )
      .with_object(:product, current_user.organization.primary_product,
        only: [:id, :name, :value_proposition]
      )
      .with_if(params[:include_history], :interaction_history, 
        @prospect.interactions.recent
      )
      .build
    
    # Run analysis
    result = ProspectAnalysisService.new(context: context).call
    
    render json: result
  end
end
```

## Migration Checklist

### Step-by-Step Migration

1. **Update RAAF Gem**
   - [ ] Update Gemfile to latest RAAF version
   - [ ] Run `bundle update raaf`
   - [ ] Run tests to ensure compatibility

2. **Identify Manual Mapping Code**
   - [ ] Search for `context.set` patterns
   - [ ] Find services with `build_*_context` methods
   - [ ] Locate agents accessing context fields directly

3. **Refactor Services** (Start with non-critical ones)
   - [ ] ProspectAnalysisService
   - [ ] MarketResearchService
   - [ ] CompanyEnrichmentService
   - [ ] OutreachCampaignService
   - [ ] ProspectDiscoveryService (critical - test thoroughly)

4. **Update AI Agents**
   - [ ] Market agents (Analysis, Scoring, SearchTermGenerator)
   - [ ] Company agents (Search, Enrichment)
   - [ ] Prospect agents (Scoring, Enrichment)
   - [ ] Outreach agents (MessageGenerator, SequenceBuilder)

5. **Refactor Orchestrators**
   - [ ] MarketDiscovery
   - [ ] ProspectDiscovery
   - [ ] OutreachCampaignBuilder

6. **Update Background Jobs**
   - [ ] EnrichmentJob
   - [ ] ScoringJob
   - [ ] OutreachJob

7. **Testing & Validation**
   - [ ] Run full test suite
   - [ ] Manual testing of critical flows
   - [ ] Performance benchmarking
   - [ ] Memory usage analysis

## Common Patterns

### Pattern 1: Service Context Building

```ruby
# Standardize context building across all services
class BaseService
  private
  
  def build_context
    RAAF::DSL::ContextBuilder.new
      .with_object(:user, current_user, only: allowed_user_fields)
      .with_object(:organization, current_user.organization, only: allowed_org_fields)
  end
  
  def allowed_user_fields
    [:id, :name, :email, :role]
  end
  
  def allowed_org_fields
    [:id, :name, :subscription_tier, :credits_remaining]
  end
end
```

### Pattern 2: Nil-Safe Access

```ruby
# In agents, always handle potential nil values
def extract_company_data
  company = context.get(:company)
  return default_company_data if company.nil?
  
  {
    name: company.name,
    industry: company.industry || "Unknown",
    size: company.employee_count || "Unknown",
    location: company.headquarters&.city || "Unknown"
  }
end
```

### Pattern 3: Conditional Context Building

```ruby
# Add objects conditionally based on requirements
# Mock objects for example
prospect = Struct.new(:name, :email, :recent_interactions).new("John Doe", "john@example.com", [])
company = Struct.new(:name, :competitors).new("Acme Corp", ["Competitor A", "Competitor B"])
include_competitors = true
include_history = false

builder = RAAF::DSL::ContextBuilder.new
  .with_object(:prospect, prospect)
  .with_object(:company, company)
  .with_if(include_competitors, :competitors, company.competitors)
  .with_if(include_history, :interactions, prospect.recent_interactions)
  .build
```

## Performance Optimization

### 1. Use Specific Field Lists

```ruby
# BAD - Loads entire object graph
builder.with_object(:company, company)

# GOOD - Only loads needed fields
builder.with_object(:company, company,
  only: [:id, :name, :industry, :size],
  methods: [:market_segment]
)
```

### 2. Control Nesting Depth

```ruby
# Prevent deep loading for performance
builder.with_object(:prospect, prospect,
  only: [:id, :name, :company_id],
  depth: 1  # Don't auto-proxy associations
)

# Explicitly add needed associations
builder.with_object(:company, prospect.company,
  only: [:id, :name]
)
```

### 3. Cache Expensive Calculations

```ruby
# Cache by default for expensive methods
builder.with_object(:product, product,
  methods: [:market_fit_score, :competitive_advantage],
  cache: true  # Default, but explicit for clarity
)
```

## Debugging Tips

### 1. Context Inspection

```ruby
# Add debug logging to see what's in context
context = builder.build
Rails.logger.debug "Context keys: #{context.keys}"
Rails.logger.debug "Context snapshot: #{context.to_h.inspect}"
```

### 2. Verify Object Proxying

```ruby
# Check if object is proxied
product = context.get(:product)
Rails.logger.debug "Is proxy? #{product.respond_to?(:proxy?)}"
Rails.logger.debug "Accessed fields: #{product.__accessed__}" if product.respond_to?(:__accessed__)
```

### 3. Trace Access Patterns

```ruby
# In development, log all proxy access
class DebugContextBuilder < RAAF::DSL::ContextBuilder
  def with_object(key, object, **options)
    super(key, object, **options.merge(debug: true))
  end
end
```

## Rollback Strategy

If issues arise, you can gradually rollback:

1. **Feature Flag Implementation**
```ruby
# app/services/base_service.rb
def build_context
  if Feature.enabled?(:use_object_proxy)
    build_context_with_proxy
  else
    build_context_legacy
  end
end
```

2. **Parallel Implementation**
```ruby
# Keep both methods during transition
def build_context_legacy
  # Old manual mapping code
end

def build_context_with_proxy
  # New object proxy code
end
```

3. **Gradual Service Migration**
- Start with read-only services
- Move to non-critical write services
- Finally migrate critical path services

## Success Metrics

Track these metrics to validate the migration:

1. **Code Reduction**
   - Lines of code in context building: -60% expected
   - Context-related bugs: -80% expected

2. **Performance**
   - Context building time: Similar or better
   - Memory usage: Monitor for increases

3. **Developer Experience**
   - Time to implement new agents: -50% expected
   - Context-related support tickets: -70% expected

## Summary

The RAAF Object Proxy system will significantly improve ProspectsRadar's codebase by:

1. **Eliminating manual field mapping** - No more error-prone context building
2. **Improving maintainability** - Clear, declarative object access
3. **Enhancing safety** - Built-in nil handling and access control
4. **Accelerating development** - Less boilerplate, more features

Start with non-critical services and gradually migrate the entire codebase. The investment will pay off quickly in reduced bugs and faster feature development.
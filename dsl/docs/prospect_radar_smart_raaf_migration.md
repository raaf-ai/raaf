# ProspectsRadar Smart RAAF Migration Guide

## Overview

This guide explains how to migrate ProspectsRadar from verbose RAAF agent implementations to the new Smart RAAF system that eliminates 80-90% of boilerplate code while maintaining full functionality.

## Migration Benefits

### Before Smart RAAF
- **100+ lines per agent** with repetitive boilerplate
- **Complex result processing** in every agent
- **Manual context building** in every service
- **Verbose error handling** duplicated everywhere
- **Separate prompt classes** requiring coordination

### After Smart RAAF  
- **10-15 lines per agent** with declarative configuration
- **Automatic result processing** built into framework
- **One-liner context building** with smart proxying
- **Intelligent error handling** with retries and circuit breakers
- **Inline prompts and schemas** for simplicity

## Phase 1: Gradual Adoption (Weeks 1-2)

### Step 1: Update RAAF Dependency

First, update the RAAF gems to include Smart RAAF features:

```ruby
# Gemfile
gem 'raaf', '~> 0.9.0'  # Version with Smart RAAF
```

Run bundle update:
```bash
bundle update raaf
```

### Step 2: Start with New Agents

Create new agents using SmartAgent for immediate benefits:

```ruby
# NEW: app/ai/agents/market/smart_analysis.rb
module Ai
  module Agents
    module Market
      class SmartAnalysis < RAAF::DSL::Agent
        agent_name "SmartMarketAnalysisAgent"
        model "gpt-4o"
        requires :product, :company
  
  # Inline schema definition
  schema do
    field :markets, type: :array, required: true do
      field :market_name, type: :string, required: true
      field :market_description, type: :string
      field :market_fit_score, type: :integer, range: 0..100
    end
  end
  
  # Modern prompt approach using AgentDsl
  include RAAF::DSL::Agents::AgentDsl
  static_instructions <<~PROMPT
    You are an expert B2B market analyst. Analyze products and identify target markets.
    Focus on market fit, addressable market size, and strategic alignment.
  PROMPT
  
  user_prompt do |ctx|
    <<~PROMPT
      Analyze this product: #{ctx.product.name}
      Company: #{ctx.company.name}  
      Description: #{ctx.product.description}
      
      Identify 3-5 potential target markets with clear value propositions.
    PROMPT
  end
  
        # Auto-retry on rate limits
        retry_on :rate_limit, max_attempts: 3, backoff: :exponential
      end
    end
  end
end
```

### Step 3: Compare Side-by-Side

Test the new SmartAgent alongside existing agents:

```ruby
# In services, test both approaches
class MarketAnalysisService < BaseService
  def call
    if Feature.enabled?(:smart_raaf)
      result = run_smart_analysis
    else
      result = run_legacy_analysis
    end
    
    success_result(markets: result[:data])
  end
  
  private
  
  def run_smart_analysis
    # One-liner with Smart RAAF
    RAAF.run(Ai::Agents::Market::SmartAnalysis, with: {
      product: @product,
      company: @company
    })
  end
  
  def run_legacy_analysis
    # Existing complex implementation
    context = build_legacy_context
    agent = Ai::Agents::Market::Analysis.new(context: context)
    agent.call
  end
end
```

## Phase 2: Service Simplification (Weeks 3-4)

### Step 1: Introduce Smart Context Building

Replace manual context building with declarative syntax:

```ruby
# OLD: Manual context building (15+ lines)
def build_discovery_context
  context = RAAF::DSL::ContextVariables.new
  context = context.set(:prospect_id, @prospect.id)
  context = context.set(:prospect_name, @prospect.name)
  context = context.set(:company_name, @prospect.company.name)
  context = context.set(:product_name, @product.name)
  # ... many more lines
  context
end

# NEW: Smart context building (3 lines!)
def build_discovery_context
  RAAF::Context.smart_build do
    proxy :prospect, @prospect, only: [:id, :name, :email, :role]
    proxy :company, @prospect.company, except: [:internal_notes]
    proxy :product, @product, with_methods: [:market_segment]
    
    requires :prospect, :company, :product
    validates :prospect, presence: [:name, :email]
  end
end
```

### Step 2: Use Service Integration Helpers

Simplify service implementations with RAAF service helpers:

```ruby
# OLD: Complex service implementation
class ProspectDiscoveryService < BaseService
  def call
    case params[:action]&.to_sym
    when :discover then discover_prospects
    # ... other actions
    end
  end
  
  private
  
  def discover_prospects
    # 30+ lines of complex orchestration
    context = build_complex_context
    orchestrator = ProspectDiscoveryOrchestrator.new(context: context)
    result = orchestrator.run
    process_orchestrator_result(result)
  end
end

# NEW: Simple service with helpers
class ProspectDiscoveryService < BaseService
  include RAAF::Rails::ServiceHelpers
  
  def call
    case params[:action]&.to_sym
    when :discover then discover_prospects
    # ... other actions
    end
  end
  
  private
  
  def discover_prospects
    # 5 lines with Smart RAAF!
    result = run_agent(SmartProspectDiscovery, with: {
      prospect: @prospect,
      product: @product,
      analysis_depth: params[:depth] || 'standard'
    })
    
    success_result(prospects: result[:data])
  end
end
```

## Phase 3: Pipeline Conversion (Weeks 5-6)

### Step 1: Convert Complex Orchestrators

Replace complex orchestrators with declarative pipelines:

```ruby
# OLD: Complex orchestrator (100+ lines)
module Ai
  module Agents
    class ApplicationAgent < RAAF::DSL::Agent  # Base class
    end
    
    class ProspectDiscoveryOrchestrator < ApplicationAgent
  def run
    # Complex manual orchestration
    market_result = Market::Analysis.new(context: @context).call
    return error_result unless market_result[:success]
    
    # Update context manually
    @context = @context.set(:market_analysis, market_result)
    
    search_result = Company::Search.new(context: @context).call
    return error_result unless search_result[:success]
    
      # More manual orchestration...
    end
  end
end

# NEW: Declarative pipeline (20 lines!)
class SmartProspectDiscovery < RAAF::DSL::Pipeline
  requires :prospect, :product
  
  step :analyze_markets, using: Market::SmartAnalysis
  step :search_companies, using: Company::SmartSearch, needs: [:analyze_markets]
  step :score_prospects, using: Prospect::SmartScoring, needs: [:search_companies, :analyze_markets]
  
  # Built-in error handling
  on_step_failure :analyze_markets, fallback_to: :simple_market_analysis
  on_pipeline_failure retry: 1, then: :partial_results
  
  finalize_with :compile_discovery_results
  
  private
  
  def compile_discovery_results(step_results)
    {
      success: true,
      markets: step_results[:analyze_markets],
      companies: step_results[:search_companies],
      scored_prospects: step_results[:score_prospects]
    }
  end
end
```

### Step 2: Parallel Pipeline Optimization

Use parallel execution for independent operations:

```ruby
class EnhancedProspectDiscovery < RAAF::DSL::Pipeline
  step :gather_base_data, using: DataGatherer
  
  # These can run in parallel
  parallel_steps :market_analysis, :competitor_analysis, :industry_trends,
    using: [Market::Analysis, Competitor::Analysis, Industry::TrendAnalysis],
    needs: [:gather_base_data]
  
  step :synthesize_insights, using: InsightSynthesizer,
    needs: [:market_analysis, :competitor_analysis, :industry_trends]
    
  finalize_with :compile_comprehensive_results
end
```

## Phase 4: Agent Migration (Weeks 7-8)

### Step 1: Systematic Agent Conversion

Convert existing agents one-by-one:

#### Market Analysis Agent

```ruby
# BEFORE: 275+ lines of boilerplate
module Ai
  module Agents
    class Analysis < ApplicationAgent
      include RAAF::DSL::Agents::AgentDsl
      include RAAF::DSL::Hooks::AgentHooks
  
  agent_name "MarketAnalysisAgent"
  model "gpt-4o"
  max_turns 3
  
  def initialize(context:)
    validate_context!(context) if context.is_a?(Hash)
    super(context: context)
  end
  
  def build_instructions
    # 20+ lines of prompt building
  end
  
  def build_schema  
    # 15+ lines of schema definition
  end
  
  def build_user_prompt
    # 25+ lines of context extraction
  end
  
  def call
    # 40+ lines of result processing and error handling
  end
  
      # 100+ lines of helper methods, error handling, etc.
    end
  end
end

# AFTER: 25 lines total!
class SmartAnalysis < RAAF::DSL::SmartAgent
  agent_name "SmartMarketAnalysisAgent"
  model "gpt-4o"
  requires :product, :company
  validates :product, presence: [:name, :description]
  
  schema do
    field :markets, type: :array, required: true do
      field :market_name, type: :string, required: true
      field :market_description, type: :string
      field :market_fit_score, type: :integer, range: 0..100
      field :market_reasoning, type: :string
    end
  end
  
  include RAAF::DSL::Agents::AgentDsl
  static_instructions "You are an expert B2B market analyst..."
  
  user_prompt do |ctx|
    "Analyze product: #{ctx.product.name} from #{ctx.company.name}"
  end
  
  retry_on :rate_limit, max_attempts: 3
  circuit_breaker threshold: 5
end
```

### Step 2: Update Background Jobs

Simplify job implementations:

```ruby
# OLD: Complex job with manual context building
class ProspectEnrichmentJob < ApplicationJob
  def perform(prospect_id)
    prospect = Prospect.find(prospect_id)
    
    # 15+ lines of manual context building
    context = build_enrichment_context(prospect)
    
    # 10+ lines of agent execution and error handling
    agent = Ai::Agents::Prospect::Enrichment.new(context: context)
    result = agent.call
    
    # 20+ lines of result processing
    process_enrichment_result(prospect, result)
  end
end

# NEW: Simple job with Smart RAAF
class SmartProspectEnrichmentJob < ApplicationJob
  include RAAF::Rails::ServiceHelpers
  
  def perform(prospect_id)
    prospect = Prospect.find(prospect_id)
    
    # One-liner execution!
    result = run_agent(Prospect::SmartEnrichment, with: {
      prospect: prospect,
      enrichment_depth: 'comprehensive'
    })
    
    # Simple result handling
    if result[:success]
      prospect.update!(enrichment_data: result[:data])
    else
      Rails.logger.error "Enrichment failed: #{result[:error]}"
    end
  end
end
```

## Phase 5: Testing and Validation (Week 9)

### Step 1: Automated Testing

Create comprehensive test suites:

```ruby
# Test Smart RAAF agents
RSpec.describe Ai::Agents::Market::SmartAnalysis do
  let(:context) { { product: product, company: company } }
  
  it "executes successfully with minimal setup" do
    result = described_class.new(context: context).call
    
    expect(result[:success]).to be true
    expect(result[:data][:markets]).to be_an(Array)
  end
  
  it "handles rate limits automatically" do
    # Smart RAAF handles this automatically
    allow_any_instance_of(RAAF::DSL::SmartAgent)
      .to receive(:run).and_raise(StandardError.new("rate limit"))
    
    # Should retry automatically
    expect_any_instance_of(described_class).to receive(:run).twice
    
    described_class.new(context: context).call
  end
end
```

### Step 2: Performance Benchmarking

Compare old vs new implementations:

```ruby
# Benchmark script
require 'benchmark'

def benchmark_agents
  Benchmark.bm(20) do |x|
    x.report("Legacy Agent:") do
      1000.times { run_legacy_agent }
    end
    
    x.report("Smart Agent:") do
      1000.times { run_smart_agent }
    end
  end
end

# Results should show similar or better performance
# with dramatically less code
```

## Migration Checklist

### Phase 1: Foundation
- [ ] Update RAAF gem to version with Smart features
- [ ] Create first SmartAgent for new feature
- [ ] Validate side-by-side with existing agent
- [ ] Measure performance impact

### Phase 2: Service Integration  
- [ ] Add RAAF::Rails::ServiceHelpers to services
- [ ] Replace manual context building with smart builders
- [ ] Implement one-liner agent execution
- [ ] Update error handling patterns

### Phase 3: Pipeline Conversion
- [ ] Convert one orchestrator to declarative pipeline
- [ ] Validate pipeline behavior matches orchestrator
- [ ] Add parallel execution for independent steps
- [ ] Implement proper error recovery

### Phase 4: Agent Migration
- [ ] Convert agents starting with least critical
- [ ] Maintain backward compatibility during migration
- [ ] Update all related tests
- [ ] Validate feature parity

### Phase 5: Validation
- [ ] Run comprehensive test suite
- [ ] Performance benchmark comparison
- [ ] User acceptance testing
- [ ] Monitor production metrics

## Success Metrics

### Code Reduction
- **Agent code**: 80-90% reduction expected
- **Service code**: 60-70% reduction expected  
- **Test code**: 40-50% reduction expected

### Development Velocity
- **New agent development**: 3x faster
- **Bug fixes**: 2x faster to implement
- **Feature development**: 2x faster end-to-end

### Reliability Improvements
- **Automatic retries**: Built-in rate limit handling
- **Circuit breakers**: Prevent cascade failures
- **Better error messages**: Structured error responses
- **Monitoring**: Built-in execution metrics

### Maintainability
- **Consistent patterns**: All agents follow same structure
- **Less boilerplate**: Focus on business logic
- **Centralized improvements**: Framework-level enhancements
- **Easier testing**: Simpler mocking and assertions

## Rollback Strategy

If issues arise, Smart RAAF is designed for safe rollback:

1. **Feature flags**: Control Smart RAAF usage per service
2. **Gradual migration**: Old and new systems work side-by-side
3. **Backward compatibility**: Existing agents continue working
4. **Quick revert**: Change feature flag to disable Smart RAAF

## Troubleshooting

### Common Issues

**Issue**: Smart agent returns unexpected results
**Solution**: Check schema definition matches expected output format

**Issue**: Context validation fails
**Solution**: Verify required keys are being passed correctly

**Issue**: Performance slower than expected
**Solution**: Review proxy configurations and reduce unnecessary data

### Debug Mode

Enable debug mode for detailed execution logging:

```ruby
# In development/test
context = RAAF::Context.smart_build(debug: true) do
  proxy :product, product
end
```

## Conclusion

Smart RAAF transforms ProspectsRadar's AI agent development from verbose, error-prone implementations to clean, declarative code. The migration can be done gradually without breaking existing functionality, providing immediate benefits for new development while systematically improving the entire codebase.

Key benefits:
- **90% less boilerplate code**
- **Built-in best practices** (retries, circuit breakers, logging)
- **Faster development** of new AI features
- **Better reliability** and error handling
- **Easier maintenance** and debugging

Start with new features using Smart RAAF, then gradually migrate existing agents to transform your AI development experience.
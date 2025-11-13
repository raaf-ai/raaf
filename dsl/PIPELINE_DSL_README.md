# RAAF Pipeline DSL

## Overview

The Pipeline DSL provides an elegant way to chain AI agents together, reducing pipeline definitions from 66+ lines to just 3 lines while maintaining all functionality.

## Installation

The Pipeline DSL is included in the `raaf-dsl` gem:

```ruby
require 'raaf/dsl/pipeline_dsl'
```

## Basic Usage

### Simple Pipeline

```ruby
class MarketDiscoveryPipeline < RAAF::Pipeline
  # Define the flow in one elegant line
  flow Market::Analysis >> Market::Scoring >> Company::Search
end

# Run the pipeline
pipeline = MarketDiscoveryPipeline.new(
  product: product,
  company: company
)
result = pipeline.run
```

### Pipeline with Context Management

```ruby
class SmartPipeline < RAAF::Pipeline
  # Define the flow
  flow Market::Analysis >> Market::Scoring >> Company::Search.limit(25)
  
  # Context is automatically available
  
  # Set defaults (just like agents)
  context do
    optional market_data: {}, analysis_depth: "standard"
    optional scoring_weights: { growth: 0.4, fit: 0.6 }
  end
  
  # Optional: Dynamic context building
  def build_market_data_context
    { regions: ["NA", "EU"], segments: ["SMB", "Enterprise"] }
  end
end
```

## Key Features

### 1. Agent Introspection

The DSL automatically introspects agents to determine their inputs and outputs:

- **Inputs**: Automatically detected from context usage
- **Outputs**: Extracted from `result_transform` field declarations

No new DSL methods needed - works with all existing agents!

### 2. Operator Overloading

Chain agents with intuitive operators:

- `>>` - Sequential execution
- `|` - Parallel execution

```ruby
# Sequential
flow Agent1 >> Agent2 >> Agent3

# Parallel
flow Agent1 >> (Agent2 | Agent3) >> Agent4

# Mixed
flow Input >> (Process1 | Process2 | Process3) >> Aggregate >> Output
```

### 3. Inline Configuration

Configure agents inline with method chaining:

```ruby
flow Analysis >> Scoring.retry(3) >> Search.limit(25).timeout(60)
```

Available modifiers:
- `.timeout(seconds)` - Set execution timeout
- `.retry(times)` - Retry on failure with exponential backoff
- `.limit(count)` - Pass limit to agent context

### 4. Pipeline Iteration

Process multiple data entries with agents using `.each_over()` with flexible output field naming:

```ruby
# Sequential iteration (default output naming)
flow DataInput >> ItemProcessor.each_over(:items) >> ResultCollector  # outputs to :processed_items

# Custom output field
flow DataInput >> ItemProcessor.each_over(:items, to: :enriched_items) >> ResultCollector

# Custom field name for iteration items (as: option)
flow DataInput >> ItemProcessor.each_over(:search_terms, as: :query) >> ResultCollector

# Both custom input and output field names
flow DataInput >> ItemProcessor.each_over(:search_terms, as: :query, to: :companies) >> ResultCollector

# Full syntax with :from marker
flow DataInput >> ItemProcessor.each_over(:from, :companies, to: :analyzed_companies) >> ResultCollector

# Parallel iteration with custom output
flow DataInput >> ItemProcessor.each_over(:items, to: :results).parallel >> ResultCollector

# Configured iteration with custom field
flow DataInput >> 
     ItemProcessor.each_over(:items, to: :processed_data)
       .parallel
       .timeout(30)
       .retry(2)
       .limit(10) >> 
     ResultCollector
```

**How It Works:**
- Takes array from specified field (e.g., `:items`)
- Executes agent once per item with item in `:current_item`
- Collects results in `:processed_items` field
- Supports both sequential and parallel processing

### 5. Field Validation

The DSL validates field compatibility between agents at pipeline creation time:

```ruby
# If Agent2 needs :data but Agent1 doesn't provide it:
Pipeline Field Mismatch Error!

Agent2 requires fields: [:data]
Agent1 only provides: [:result]

To fix this:
1. Update Agent1's result_transform to provide: [:data]
2. Or update Agent2 to not require these fields
3. Or add an intermediate agent that provides the transformation
```

### 6. Auto-Skip Logic

Agents automatically skip execution when their requirements aren't met:

```ruby
# If :optional_data is missing, OptionalAgent skips
flow RequiredAgent >> OptionalAgent >> FinalAgent
```

## Implementation Details

### Core Classes

- **`RAAF::Pipeline`** - Base class for pipelines with context management
- **`ChainedAgent`** - Implements sequential execution (`>>`)
- **`ParallelAgents`** - Implements parallel execution (`|`)
- **`ConfiguredAgent`** - Wraps agents with configuration options
- **`IteratingAgent`** - Processes arrays of data with agents
- **`FieldMismatchError`** - Clear errors for field incompatibilities

### How It Works

1. **Introspection**: Extracts metadata from existing agent declarations
2. **Validation**: Checks field compatibility at pipeline creation
3. **Execution**: Runs agents in sequence/parallel with automatic context flow
4. **Context Management**: Merges agent outputs into pipeline context

## Examples

### Market Discovery Pipeline

Before (66+ lines):
```ruby
class MarketDiscoveryPipeline
  def initialize(product:, company:, market_data: {})
    # ... extensive setup
  end
  
  def add_step(name, agent_class, condition: nil)
    # ... step configuration
  end
  
  def execute
    # ... complex execution logic
  end
  
  # ... many more methods
end
```

After (3 lines):
```ruby
class MarketDiscoveryPipeline < RAAF::Pipeline
  flow Market::Analysis >> Market::Scoring >> Company::Search.limit(25)
end
```

### Complex Pipeline with Parallel Processing

```ruby
class DataEnrichmentPipeline < RAAF::Pipeline
  flow DataInput >> 
       (WebSearch | DatabaseLookup | APIFetch).timeout(30) >> 
       DataMerge >> 
       QualityCheck.retry(3) >> 
       Output
       
  context do
    default :parallel_timeout, 30
    default :quality_threshold, 0.8
  end
end
```

### Pipeline Iteration Examples

#### Basic Sequential Iteration

```ruby
class CompanyAnalysisPipeline < RAAF::Pipeline
  # Process each company sequentially with detailed analysis
  flow CompanyFetcher >> 
       CompanyAnalyzer.each_over(:companies) >> 
       ReportGenerator
  
  context do
    default :analysis_depth, "comprehensive"
  end
end

# Usage
pipeline = CompanyAnalysisPipeline.new(
  search_query: "AI startups in San Francisco"
)
result = pipeline.run
# result[:processed_companies] contains analysis for each company
```

#### Parallel Processing with Limits

```ruby
class HighVolumeProcessingPipeline < RAAF::Pipeline
  # Process up to 100 items in parallel with retries
  flow DataLoader >> 
       ItemProcessor.each_over(:items)
         .parallel           # Process in parallel
         .limit(100)         # Limit to 100 items
         .timeout(60)        # 60s timeout per item
         .retry(3) >>        # Retry failed items 3 times
       ResultAggregator

  after_run do |result|
    # Log processing statistics
    total_items = result[:processed_items]&.count || 0
    failed_items = result[:processed_items]&.count { |r| r[:error] } || 0
    
    Rails.logger.info "Processed #{total_items} items, #{failed_items} failures"
  end
end
```

#### Mixed Sequential and Parallel Iteration

```ruby
class MarketResearchPipeline < RAAF::Pipeline
  # Complex flow: analyze companies sequentially, 
  # then score prospects in parallel
  flow CompanyDataFetcher >> 
       CompanyAnalyzer.each_over(:companies) >>      # Sequential analysis
       ProspectScorer.each_over(:processed_companies) # Parallel scoring
         .parallel
         .timeout(30) >> 
       RankingEngine
  
  context do
    default :scoring_weights, { growth: 0.4, fit: 0.6 }
    default :min_score, 0.7
  end
end
```

#### Nested Iteration (Advanced)

```ruby
class MultiMarketAnalysisPipeline < RAAF::Pipeline
  # Process multiple markets, each containing multiple companies
  flow MarketDataLoader >> 
       MarketAnalyzer.each_over(:markets, to: :analyzed_markets)
         .timeout(120) >>                            # Each market gets 2 minutes
       CompanyProcessor.each_over(:analyzed_markets) # Process all market results
         .parallel >>                               # Markets processed in parallel  
       GlobalRanking
  
  # Agent that processes companies within each market
  class MarketAnalyzer < RAAF::DSL::Agent
    context do
      required :market  # Provided by .each_over(:markets) - singularized field name
    end
    
    def run
      # Process companies within this market
      companies = market[:companies] || []
      
      # Process each company for this market
      company_results = companies.map do |company|
        # Company-specific processing logic
        analyze_company(company)
      end
      
      {
        market_analysis: {
          market: current_market,
          company_results: company_results,
          market_score: calculate_market_score(company_results)
        }
      }
    end
  end
end
```

## Field Naming and Context Access

When using `.each_over()`, agents receive individual items through context fields with predictable names:

### Default Field Naming (Singularization)
```ruby
# Input field -> Agent context field
Agent.each_over(:companies)    # Agent receives :company
Agent.each_over(:markets)      # Agent receives :market  
Agent.each_over(:search_terms) # Agent receives :search_term
Agent.each_over(:items)        # Agent receives :item
```

### Custom Field Naming (as: option)
```ruby
# Custom field names for better clarity
Agent.each_over(:search_terms, as: :query)           # Agent receives :query
Agent.each_over(:companies, as: :target_company)     # Agent receives :target_company
Agent.each_over(:user_profiles, as: :profile)        # Agent receives :profile
```

### Agent Context Example
```ruby
class SearchProcessor < RAAF::DSL::Agent
  context do
    required :query        # Custom field from .each_over(:search_terms, as: :query)
    optional :current_item # Always available (original item)
    optional :item_index   # Always available (0-based index)
  end
  
  def run
    # Process the search query
    results = perform_search(query)
    
    { 
      companies: results,
      query_processed: query,
      index: item_index
    }
  end
end

# Usage in pipeline
flow SearchInput >> 
     SearchProcessor.each_over(:search_terms, as: :query, to: :company_results) >> 
     ResultCollector
```

### Complete Field Control
```ruby
# Full control over field naming
Agent.each_over(:from, :search_terms, as: :query, to: :company_results)

# Input:  { search_terms: ["ruby programming", "rails tutorial"] }
# Agent receives: { query: "ruby programming", current_item: "ruby programming", item_index: 0 }
# Output: { company_results: [result1, result2] }
```

## Token Usage Tracking

RAAF Pipelines automatically aggregate token usage from all agents, providing visibility into AI costs and consumption:

### Automatic Aggregation

```ruby
class MarketDiscoveryPipeline < RAAF::Pipeline
  flow Market::Analysis >> Market::Scoring >> Market::SearchTermGenerator
end

pipeline = MarketDiscoveryPipeline.new(product: product, company: company)
result = pipeline.run

# Automatic token usage aggregation
puts result[:usage]
# => {
#   input_tokens: 450,
#   output_tokens: 600,
#   total_tokens: 1050,
#   prompt_tokens: 450,      # Alias for compatibility
#   completion_tokens: 600,  # Alias for compatibility
#   agent_breakdown: [
#     { agent_name: "Analysis", input_tokens: 150, output_tokens: 200, total_tokens: 350 },
#     { agent_name: "Scoring", input_tokens: 150, output_tokens: 200, total_tokens: 350 },
#     { agent_name: "SearchTermGenerator", input_tokens: 150, output_tokens: 200, total_tokens: 350 }
#   ]
# }
```

### Cache and Reasoning Tokens

Pipelines automatically aggregate advanced token types:

```ruby
pipeline = ReasoningPipeline.new(task: "complex analysis")
result = pipeline.run

# Includes cache usage if agents used cached prompts
puts result[:usage][:cache_read_input_tokens]  # 125

# Includes reasoning tokens if agents used reasoning models (o1, o3, etc.)
puts result[:usage][:output_tokens_details][:reasoning_tokens]  # 150
```

### Indifferent Key Access

Usage data supports both symbol and string key access:

```ruby
# Both work identically
puts result[:usage][:input_tokens]    # 450
puts result["usage"]["input_tokens"]  # 450
```

### Per-Agent Breakdown

Track which agents consume the most tokens:

```ruby
result[:usage][:agent_breakdown].each do |agent_usage|
  puts "#{agent_usage[:agent_name]}: #{agent_usage[:total_tokens]} tokens"
end

# Output:
# Analysis: 350 tokens
# Scoring: 350 tokens
# SearchTermGenerator: 350 tokens
```

### Cost Calculation

Use aggregated usage for cost tracking:

```ruby
usage = result[:usage]

# Example: OpenAI GPT-4 pricing (approximate)
input_cost_per_1k = 0.03
output_cost_per_1k = 0.06

total_cost = (usage[:input_tokens] / 1000.0 * input_cost_per_1k) +
             (usage[:output_tokens] / 1000.0 * output_cost_per_1k)

puts "Pipeline cost: $#{total_cost.round(4)}"
# => "Pipeline cost: $0.0495"
```

### Tracing Integration

Usage data automatically flows to pipeline spans when tracing is enabled:

```ruby
# Usage appears in RAAF tracing dashboard
# - pipeline.usage attribute contains full aggregated usage
# - dialog.total_tokens attribute for OpenAI dashboard compatibility
```

## Benefits

1. **Concise**: 95% reduction in code (from 66+ lines to 3)
2. **Readable**: Pipeline flow is immediately obvious
3. **Type-Safe**: Field validation catches errors early
4. **No Changes Required**: Works with all existing agents
5. **Flexible**: Supports sequential, parallel, and mixed flows
6. **Scalable**: Built-in iteration for processing multiple data items
7. **Configurable**: Timeout, retry, and limit controls for robust processing
8. **Maintainable**: Clear separation of concerns

## Migration Guide

To convert an existing verbose pipeline:

1. Create a new class inheriting from `RAAF::Pipeline`
2. Define the flow using the `>>` operator
3. Add context management if needed
4. Remove all the verbose configuration code

That's it! Your pipeline now works with 95% less code.

## Testing

The DSL includes comprehensive test coverage. Run tests with:

```bash
cd raaf/dsl
bundle exec rspec spec/raaf/dsl/pipeline_dsl/
```

## Future Enhancements

- Conditional branching (`if`/`else` in flows)
- Pipeline composition (pipelines within pipelines)
- Visual pipeline builder
- Performance profiling per step
- Advanced iteration patterns (filtering, batching, streaming)
- Nested iteration optimization
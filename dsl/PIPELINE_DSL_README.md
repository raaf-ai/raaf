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
  
  # Declare what the pipeline needs
  context_reader :product, :company
  
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

- **Inputs**: Extracted from `context_reader` declarations
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

### 4. Field Validation

The DSL validates field compatibility between agents at pipeline creation time:

```ruby
# If Agent2 needs :data but Agent1 doesn't provide it:
Pipeline Field Mismatch Error!

Agent2 requires fields: [:data]
Agent1 only provides: [:result]

To fix this:
1. Update Agent1's result_transform to provide: [:data]
2. Or update Agent2's context_reader to not require these fields
3. Or add an intermediate agent that provides the transformation
```

### 5. Auto-Skip Logic

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

## Benefits

1. **Concise**: 95% reduction in code (from 66+ lines to 3)
2. **Readable**: Pipeline flow is immediately obvious
3. **Type-Safe**: Field validation catches errors early
4. **No Changes Required**: Works with all existing agents
5. **Flexible**: Supports sequential, parallel, and mixed flows
6. **Maintainable**: Clear separation of concerns

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
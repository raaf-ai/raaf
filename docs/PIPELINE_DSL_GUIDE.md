# RAAF Pipeline DSL Guide

## Table of Contents

1. [Getting Started with Pipeline DSL](#getting-started-with-pipeline-dsl)
2. [Pipeline Schema Validation](#pipeline-schema-validation)
3. [Cookbook: Common Pipeline Patterns](#cookbook-common-pipeline-patterns)
4. [Best Practices for Agent Field Naming](#best-practices-for-agent-field-naming)
5. [Troubleshooting Field Mismatches](#troubleshooting-field-mismatches)
6. [Performance Optimization](#performance-optimization)
7. [Pipeline Testing Strategies](#pipeline-testing-strategies)
8. [Intelligent Streaming](#intelligent-streaming)

---

## Getting Started with Pipeline DSL

### Introduction to the DSL Concept

The RAAF Pipeline DSL provides an elegant way to chain AI agents together, reducing complex pipeline definitions from 66+ lines to just 3 lines while maintaining all functionality. Instead of manually managing context flow and agent coordination, the DSL handles this automatically through agent introspection.

Note on canonical DSL:
- The operator-style Pipeline DSL using `class MyFlow < RAAF::Pipeline; flow A >> (B | C) >> D; end` is the canonical approach for new code and documentation.
- The older builder-style pipeline (`RAAF::DSL::AgentPipeline`) remains for backward compatibility but is considered legacy and is not recommended for new work.

### Basic Syntax and Structure

The Pipeline DSL uses operator overloading to create intuitive chains:

- `>>` - Sequential execution (agent1 then agent2)
- `|` - Parallel execution (agent1 and agent2 simultaneously)

### First Pipeline Example

```ruby
require 'raaf-core'
require 'raaf-dsl'

# Define your agents using RAAF DSL Agent
class DataAnalyzer < RAAF::DSL::Agent
  instructions "Analyze the provided data and extract key insights"
  model "gpt-4o"
  
  result_transform do
    field :insights
    field :summary
  end
end

class ReportGenerator < RAAF::DSL::Agent
  instructions "Generate a professional report from the analysis"
  model "gpt-4o"
  
  result_transform do
    field :report
  end
end

# Create a simple pipeline
class DataProcessingPipeline < RAAF::Pipeline
  flow DataAnalyzer >> ReportGenerator
end

# Run the pipeline
pipeline = DataProcessingPipeline.new(
  raw_data: "Sales data: Q1: $100k, Q2: $150k, Q3: $120k, Q4: $180k"
)
result = pipeline.run
puts result[:report]
```

### How to Run Pipelines

Running a pipeline is straightforward:

```ruby
# 1. Create the pipeline with required context
pipeline = MyPipeline.new(
  required_field1: value1,
  required_field2: value2
)

# 2. Execute the pipeline
result = pipeline.run

# 3. Access results from the final context
puts result[:final_output]
```

---

## Pipeline Schema Validation

### Overview

Pipeline schema validation provides a unified way to ensure consistent data structures across all agents in a pipeline. When you define a `pipeline_schema` at the pipeline level, it gets automatically injected into all agents during execution, ensuring consistent AI response formats throughout your workflow.

### Why Use Pipeline Schema?

- **Consistency**: All agents in the pipeline use the same response schema
- **Validation**: Automatic JSON repair and field normalization across the entire pipeline
- **Maintainability**: Single source of truth for data structure
- **Flexibility**: Agents can still override with their own schema if needed

### Basic Pipeline Schema Definition

```ruby
class DataProcessingPipeline < RAAF::Pipeline
  flow DataAnalyzer >> ReportGenerator >> SummaryCreator
  
  # Define shared schema for all agents in this pipeline
  pipeline_schema do
    field :company_name, type: :string, required: true
    field :analysis_data, type: :object, required: true
    field :confidence_score, type: :number
    field :metadata, type: :object
    
    # Choose validation mode for all agents
    validate_mode :tolerant  # :strict, :tolerant, or :partial
  end
  
  context do
    default :analysis_depth, "standard"
  end
end

# Usage - all agents automatically inherit the pipeline schema
pipeline = DataProcessingPipeline.new(
  raw_data: "Tesla Inc automotive data...",
  analysis_depth: "detailed"
)
result = pipeline.run

# All agents return consistently structured data
puts result[:company_name]      # "Tesla Inc" (normalized from any variant)
puts result[:analysis_data]     # Structured analysis object  
puts result[:confidence_score]  # Numeric confidence value
```

### Schema Inheritance and Override

```ruby
class AdvancedPipeline < RAAF::Pipeline
  flow DataCollector >> SpecializedAnalyzer >> StandardReporter
  
  # Pipeline-wide schema
  pipeline_schema do
    field :base_data, type: :object, required: true
    field :processed_at, type: :string
    validate_mode :tolerant
  end
end

# Agent can override pipeline schema if needed
class SpecializedAnalyzer < RAAF::DSL::Agent
  agent_name "SpecializedAnalyzer"
  model "gpt-4o"
  
  # This agent uses its own schema instead of pipeline schema
  schema do
    field :specialized_result, type: :array, required: true
    field :analysis_method, type: :string, required: true
    validate_mode :strict  # Can use different validation mode
  end
  
  instructions "Perform specialized analysis requiring strict schema"
end

# Other agents in the pipeline still use the pipeline schema
# Only SpecializedAnalyzer uses its custom schema
```

### Schema Priority Order

RAAF follows this priority order when determining which schema to use:

1. **Agent-defined schema** (highest priority) - `schema do ... end` in agent class
2. **Pipeline-injected schema** - `pipeline_schema do ... end` from pipeline  
3. **No schema** (lowest priority) - Agent runs without response validation

```ruby
class SchemaTestPipeline < RAAF::Pipeline
  flow AgentWithSchema >> AgentWithoutSchema >> AnotherAgentWithoutSchema
  
  # This schema will be used by agents that don't define their own
  pipeline_schema do
    field :shared_output, type: :string, required: true
    field :pipeline_metadata, type: :object
  end
end

class AgentWithSchema < RAAF::DSL::Agent
  # This agent ignores pipeline schema and uses its own
  schema do
    field :custom_field, type: :string, required: true
  end
end

# AgentWithoutSchema and AnotherAgentWithoutSchema will use pipeline schema
# AgentWithSchema uses its own schema definition
```

### Complex Schema Patterns

#### Nested Object Validation

```ruby
class ComplexDataPipeline < RAAF::Pipeline
  flow DataExtractor >> DataEnricher >> DataValidator
  
  pipeline_schema do
    field :company, type: :object do
      field :name, type: :string, required: true
      field :sector, type: :string, required: true
      field :employees, type: :integer
      field :locations, type: :array do
        items type: :object do
          field :city, type: :string, required: true
          field :country, type: :string, required: true
          field :employee_count, type: :integer
        end
      end
    end
    
    field :analysis, type: :object do
      field :risk_score, type: :number, required: true
      field :growth_potential, type: :string, required: true
      field :market_position, type: :string
    end
    
    validate_mode :tolerant
  end
end
```

#### Conditional Schema Fields

```ruby
class ConditionalSchemaPipeline < RAAF::Pipeline
  flow DataAnalyzer >> ConditionalProcessor >> FinalReporter
  
  pipeline_schema do
    field :base_analysis, type: :object, required: true
    
    # Optional fields that may or may not be populated
    field :detailed_metrics, type: :object
    field :risk_assessment, type: :object
    field :growth_projections, type: :array
    
    # Use partial mode to handle optional data gracefully
    validate_mode :partial
  end
  
  context do
    default :include_detailed_analysis, false
    default :include_risk_assessment, true
  end
end
```

### Schema Validation Modes in Pipelines

#### Pipeline-wide Validation Strategy

```ruby
class StrictPipeline < RAAF::Pipeline
  flow CriticalDataProcessor >> ComplianceValidator >> AuditReporter
  
  # All agents must return exactly these fields
  pipeline_schema do
    field :compliance_status, type: :string, required: true
    field :audit_trail, type: :array, required: true
    field :risk_level, type: :string, required: true
    
    validate_mode :strict  # Enforces exact schema compliance
  end
end

class FlexiblePipeline < RAAF::Pipeline  
  flow DataCollector >> FlexibleAnalyzer >> AdaptiveReporter
  
  # Agents can return additional fields, missing optionals are OK
  pipeline_schema do
    field :core_data, type: :object, required: true
    field :analysis_results, type: :object
    field :additional_insights, type: :array
    
    validate_mode :tolerant  # Required fields strict, others flexible
  end
end

class ResilientPipeline < RAAF::Pipeline
  flow UnreliableSource >> BestEffortProcessor >> RobustReporter
  
  # Use whatever validates, ignore what doesn't
  pipeline_schema do
    field :primary_data, type: :object, required: true
    field :secondary_data, type: :object
    field :metadata, type: :object
    
    validate_mode :partial  # Most forgiving, handles unreliable data
  end
end
```

### Debugging Schema Issues

#### Schema Inspection Tools

```ruby
class DebugSchemaPipeline < RAAF::Pipeline
  flow DataAgent >> AnalysisAgent >> ReportAgent
  
  pipeline_schema do
    field :debug_data, type: :object, required: true
    field :processing_info, type: :object
  end
  
  # Add debugging to see schema usage
  after_run do |result|
    puts "=== PIPELINE SCHEMA DEBUG ==="
    puts "Final result keys: #{result.keys}"
    puts "Schema validation results:"
    
    # Log schema validation info
    if result[:_schema_validation]
      result[:_schema_validation].each do |agent, validation|
        puts "  #{agent}: #{validation[:status]} - #{validation[:errors]&.join(', ')}"
      end
    end
  end
end
```

#### Mixed Schema Debugging

```ruby
# Debug pipeline with mixed schema sources
class MixedSchemaPipeline < RAAF::Pipeline
  flow AgentWithOwnSchema >> AgentUsingPipelineSchema >> AnotherPipelineAgent
  
  pipeline_schema do
    field :shared_field, type: :string, required: true
    field :common_metadata, type: :object
  end
end

# Agent that uses its own schema
class AgentWithOwnSchema < RAAF::DSL::Agent
  schema do
    field :custom_output, type: :array, required: true
    field :agent_specific_data, type: :object
  end
  
  def run
    result = super
    log_info "Using custom schema: #{build_schema.keys}"
    result
  end
end

# These agents will use pipeline schema
class AgentUsingPipelineSchema < RAAF::DSL::Agent
  def run
    result = super
    log_info "Using pipeline schema: #{build_schema.keys}" 
    result
  end
end
```

### Best Practices for Pipeline Schema

1. **Start with Required Fields**: Define only the fields you absolutely need across all agents
2. **Use Tolerant Mode**: Provides the best balance of validation and flexibility
3. **Keep Schema Simple**: Complex nested schemas can be hard to debug
4. **Document Field Purposes**: Use clear field names and add comments
5. **Test Schema Changes**: Verify that all agents can produce the expected schema

```ruby
# Example of well-designed pipeline schema
class WellDesignedPipeline < RAAF::Pipeline
  flow DataIngestion >> CoreAnalysis >> ReportGeneration
  
  # Clear, simple schema with good field names
  pipeline_schema do
    # Core business data - required across all agents
    field :business_entity, type: :object, required: true
    field :analysis_timestamp, type: :string, required: true
    
    # Optional enrichment data - may be added by different agents
    field :financial_metrics, type: :object      # Added by DataIngestion
    field :risk_analysis, type: :object          # Added by CoreAnalysis  
    field :executive_summary, type: :string      # Added by ReportGeneration
    
    # Metadata for debugging and auditing
    field :processing_metadata, type: :object
    
    # Tolerant mode allows agents to add extra fields while enforcing required ones
    validate_mode :tolerant
  end
  
  context do
    # Clear defaults that work with the schema
    default :analysis_level, "standard"
    default :include_metadata, true
  end
end
```

---

## Cookbook: Common Pipeline Patterns

### Sequential Processing

The most basic pattern - each agent processes the output of the previous one:

```ruby
class SequentialPipeline < RAAF::Pipeline
  flow InputValidator >> DataProcessor >> OutputFormatter
  
  # Context is automatically available to all agents
  
  context do
    default :validation_rules, { required: [:id, :name] }
    default :format_type, "json"
  end
end

# Usage
pipeline = SequentialPipeline.new(input_data: raw_data)
result = pipeline.run
```

### Parallel Processing

Execute multiple agents simultaneously and merge their results:

```ruby
class ParallelAnalysisPipeline < RAAF::Pipeline
  flow DataInput >> 
       (SentimentAnalyzer | KeywordExtractor | EntityRecognizer) >> 
       ResultMerger
  
  # Context is automatically available to all agents
end

# Each parallel agent processes the same input independently
# ResultMerger receives all their outputs
```

### Conditional Flows

Use context-aware agents that skip execution when requirements aren't met:

```ruby
class ConditionalPipeline < RAAF::Pipeline
  flow RequiredStep >> 
       OptionalStep >>  # Skips if :optional_data missing
       FinalStep
  
  context do
    default :enable_optional, false
  end
end

class OptionalStep < RAAF::DSL::Agent
  # Context is automatically available - optional_data field
  
  def self.requirements_met?(context)
    # Custom logic for when to run
    context[:enable_optional] && context.key?(:optional_data)
  end
end
```

### Error Handling Patterns

Build resilience into your pipelines:

```ruby
class ResilientPipeline < RAAF::Pipeline
  flow DataFetcher.retry(3) >> 
       DataProcessor.timeout(60) >> 
       DataStorer.retry(2).timeout(30)
  
  # Context is automatically available to all agents
end

# Built-in error handling:
# - Exponential backoff on retries
# - Timeout protection
# - Graceful degradation
```

### Data Transformation Patterns

Transform data between incompatible agents:

```ruby
class TransformationPipeline < RAAF::Pipeline
  flow ApiDataFetcher >> 
       JsonToObjectTransformer >> 
       ObjectAnalyzer >> 
       ObjectToReportTransformer
end

class JsonToObjectTransformer < RAAF::DSL::Agent
  # Context is automatically available - json_data field
  
  instructions "Convert JSON data to structured objects"
  
  result_transform do
    field :structured_objects
  end
end
```

### Fan-out/Fan-in Pattern

Distribute work and then consolidate:

```ruby
class FanOutFanInPipeline < RAAF::Pipeline
  flow DataSplitter >> 
       (ProcessorA | ProcessorB | ProcessorC) >> 
       ResultConsolidator
end

class DataSplitter < RAAF::DSL::Agent
  # Context is automatically available - large_dataset field
  
  result_transform do
    field :chunk_a
    field :chunk_b  
    field :chunk_c
  end
end
```

---

## Best Practices for Agent Field Naming

### Naming Conventions

1. **Use descriptive, specific names**:
   ```ruby
   # Good
   # Access customer_transaction_data from context
   field :risk_assessment_score
   
   # Avoid
   # Access generic data from context
   field :result
   ```

2. **Follow consistent patterns**:
   ```ruby
   # Input/Output pairs
   # Access raw_customer_data from context
   field :processed_customer_data
   
   # Analysis/Report pairs
   # Access sales_analysis from context
   field :sales_report
   ```

3. **Use domain-specific terminology**:
   ```ruby
   # Financial domain
   field :credit_score, :risk_profile, :loan_eligibility
   
   # Marketing domain  
   field :campaign_performance, :conversion_rate, :audience_insights
   ```

### Field Mapping Strategies

1. **Direct mapping** (same field names):
   ```ruby
   class ProducerAgent < RAAF::DSL::Agent
     result_transform do
       field :user_profile
     end
   end
   
   class ConsumerAgent < RAAF::DSL::Agent
     # Context is automatically available - user_profile field directly accessible
   end
   ```

2. **Transformation mapping** (field conversion):
   ```ruby
   class DataTransformer < RAAF::DSL::Agent
     # Context is automatically available - raw_data field
     
     result_transform do
       field :processed_data  # Transforms raw_data -> processed_data
     end
   end
   ```

3. **Aggregation mapping** (multiple inputs to one output):
   ```ruby
   class DataAggregator < RAAF::DSL::Agent
     # Context is automatically available - sales_data, marketing_data, customer_data fields
     
     result_transform do
       field :business_intelligence  # Combines all inputs
     end
   end
   ```

### Avoiding Conflicts

1. **Use prefixes for domain separation**:
   ```ruby
   # Marketing pipeline
   field :marketing_analysis, :marketing_report
   
   # Sales pipeline
   field :sales_analysis, :sales_report
   ```

2. **Version your field names**:
   ```ruby
   field :user_profile_v2  # When updating existing fields
   field :risk_score_enhanced  # When adding new capabilities
   ```

3. **Use namespacing in complex pipelines**:
   ```ruby
   field :customer_acquisition_cost
   field :customer_lifetime_value
   field :customer_satisfaction_score
   ```

---

## Troubleshooting Field Mismatches

### Common Errors and Solutions

#### 1. Field Mismatch Error

**Error**:
```
Pipeline Field Mismatch Error!

ConsumerAgent requires fields: [:processed_data]
ProducerAgent only provides: [:raw_data]

Missing fields that must be provided: [:processed_data]
```

**Solutions**:

**Option A: Update producer to provide required field**
```ruby
class ProducerAgent < RAAF::DSL::Agent
  result_transform do
    field :raw_data
    field :processed_data  # Add missing field
  end
end
```

**Option B: Add intermediate transformation agent**
```ruby
class MyPipeline < RAAF::Pipeline
  flow ProducerAgent >> DataProcessor >> ConsumerAgent
end

class DataProcessor < RAAF::DSL::Agent
  # Context is automatically available - raw_data field
  result_transform do
    field :processed_data
  end
end
```

**Option C: Update consumer requirements**
```ruby
class ConsumerAgent < RAAF::DSL::Agent
  # Context is automatically available - raw_data field accessible
end
```

#### 2. Missing Initial Context Fields

**Error**:
```
Pipeline initialization error!

First agent DataAnalyzer requires: [:raw_data, :analysis_depth]
You have in context: [:raw_data]
Missing: [:analysis_depth]
```

**Solution**:
```ruby
# Option 1: Provide missing fields when creating pipeline
pipeline = DataProcessingPipeline.new(
  raw_data: data,
  analysis_depth: "detailed"  # Add missing field
)

# Option 2: Set defaults in pipeline class
class DataProcessingPipeline < RAAF::Pipeline
  context do
    default :analysis_depth, "standard"  # Default value
  end
end
```

### Debugging Techniques

#### 1. Enable Debug Logging

```ruby
require 'logger'

RAAF.configure do |config|
  config.logger = Logger.new(STDOUT)
  config.logger.level = Logger::DEBUG
end

# Will show:
# DEBUG: Skipping AgentName: requirements not met
# DEBUG:   Required: [:field1, :field2]
# DEBUG:   Available in context: [:field1]
```

#### 2. Inspect Agent Metadata

```ruby
# Check what an agent requires and provides
puts "Agent requires: #{MyAgent.required_fields}"
puts "Agent provides: #{MyAgent.provided_fields}"
puts "Requirements met? #{MyAgent.requirements_met?(context)}"
```

#### 3. Validate Pipeline Before Running

```ruby
class MyPipeline < RAAF::Pipeline
  flow Agent1 >> Agent2 >> Agent3
  
  def validate!
    # Custom validation logic
    agents = [Agent1, Agent2, Agent3]
    agents.each_cons(2) do |producer, consumer|
      required = consumer.required_fields
      provided = producer.provided_fields
      missing = required - provided
      
      if missing.any?
        raise "#{consumer.name} missing: #{missing}"
      end
    end
  end
end
```

### Field Inspection Methods

#### 1. Context Inspector

```ruby
class DebugPipeline < RAAF::Pipeline
  flow Agent1 >> :inspect_context >> Agent2
  
  private
  
  def inspect_context(context)
    puts "Context at this point:"
    context.each { |k, v| puts "  #{k}: #{v.class}" }
    context
  end
end
```

#### 2. Agent Wrapper for Debugging

```ruby
class DebuggingAgent < RAAF::DSL::Agent
  # Context is automatically available - all fields accessible
  
  instructions "Debug the context and return it unchanged"
  
  def run
    puts "=== DEBUGGING CONTEXT ==="
    @context.each do |key, value|
      puts "#{key}: #{value.inspect}"
    end
    puts "========================="
    
    @context  # Return context unchanged
  end
end

# Use in pipeline for debugging
flow Agent1 >> DebuggingAgent >> Agent2
```

---

## Performance Optimization

### Efficient Pipeline Design

#### 1. Minimize Sequential Dependencies

```ruby
# Less efficient - all sequential
flow Step1 >> Step2 >> Step3 >> Step4

# More efficient - parallel where possible
flow Step1 >> (Step2 | Step3) >> Step4
```

#### 2. Use Selective Field Passing

```ruby
class EfficientAgent < RAAF::DSL::Agent
  # Context is automatically available - small_data field
  
  result_transform do
    field :specific_result  # Only provide what others need
  end
end
```

#### 3. Implement Early Exit Conditions

```ruby
class ConditionalAgent < RAAF::DSL::Agent
  def self.requirements_met?(context)
    # Skip expensive processing when conditions aren't met
    context[:data_quality_score] > 0.8
  end
end
```

### Memory Management

#### 1. Clean Up Large Context Objects

```ruby
class MemoryEfficientPipeline < RAAF::Pipeline
  flow DataLoader >> DataProcessor >> :cleanup >> ResultGenerator
  
  private
  
  def cleanup(context)
    # Remove large objects that are no longer needed
    context.delete(:large_raw_data)
    context.delete(:intermediate_processing_data)
    context
  end
end
```

#### 2. Use Streaming for Large Datasets

```ruby
class StreamingAgent < RAAF::DSL::Agent
  # Context is automatically available - data_stream field
  
  result_transform do
    field :processed_stream
  end
  
  def run
    # Process data in chunks rather than loading everything
    process_in_chunks(@context[:data_stream])
  end
end
```

### Parallel Execution Strategies

#### 1. CPU-Bound vs I/O-Bound Considerations

```ruby
# I/O-bound operations (API calls, file access) - safe for parallel
flow DataInput >> (ApiCall1 | ApiCall2 | ApiCall3) >> Merger

# CPU-bound operations - consider thread pool size
class CpuIntensivePipeline < RAAF::Pipeline
  flow DataInput >> (Analysis1 | Analysis2).limit_threads(2) >> Merger
end
```

#### 2. Timeout Configuration for Parallel Operations

```ruby
# Set reasonable timeouts for parallel operations
flow DataInput >> 
     (SlowApi.timeout(30) | FastCache.timeout(5) | Database.timeout(10)) >> 
     ResultMerger
```

#### 3. Error Isolation in Parallel Execution

```ruby
class ResilientParallelPipeline < RAAF::Pipeline
  flow DataInput >> 
       (CriticalProcess | OptionalProcess.retry(3) | BestEffortProcess) >> 
       ResultMerger
end

class ResultMerger < RAAF::DSL::Agent
  # Context is automatically available:
  # - critical_result (required)
  # - optional_result (optional - pipeline continues without it)
  # - best_effort_result (optional)
  
  def self.requirements_met?(context)
    # Only require critical result
    context.key?(:critical_result)
  end
end
```

---

## Services in Pipelines and Field Capture

When you use `RAAF::DSL::Service` classes inside a `RAAF::Pipeline`, keep in mind how fields flow between steps:

- Services should return a Hash of outputs from `#call`, for example: `{ companies: [...], metadata: {...} }`.
- The pipeline updates context based on each step’s declared provided fields. For services, define `self.provided_fields` to list the keys your service adds to context (e.g., `[:companies, :metadata]`).
- Advanced: services can implement field auto‑discovery by executing via `#call_with_field_capture`, which records the last set of result keys so `self.provided_fields` can be inferred. If you rely on this mechanism, ensure your pipeline execution path uses `#call_with_field_capture` when invoking services.

Practical guidance:
- Prefer explicit `provided_fields` on services used in pipelines for clarity and predictability.
- Keep output keys stable and descriptive to make downstream requirements easy to validate.
- For complex services, consider small, composable steps that each provide a narrow set of fields.

---

## Pipeline Testing Strategies

### Unit Testing Pipelines

#### 1. Testing Individual Agents

```ruby
RSpec.describe DataAnalyzer do
  describe '#run' do
    let(:context) { { raw_data: "test data" } }
    let(:agent) { described_class.new(context: context) }
    
    it 'processes data correctly' do
      result = agent.run
      
      expect(result[:insights]).to be_present
      expect(result[:summary]).to be_a(String)
    end
    
    it 'handles empty data' do
      agent = described_class.new(context: { raw_data: "" })
      result = agent.run
      
      expect(result[:insights]).to be_empty
    end
  end
  
  describe '.requirements_met?' do
    it 'returns true when raw_data is present' do
      context = { raw_data: "data" }
      expect(described_class.requirements_met?(context)).to be true
    end
    
    it 'returns false when raw_data is missing' do
      context = {}
      expect(described_class.requirements_met?(context)).to be false
    end
  end
end
```

#### 2. Testing Pipeline Structure

```ruby
RSpec.describe DataProcessingPipeline do
  describe 'pipeline structure' do
    it 'has the correct flow' do
      expect(described_class.flow_chain).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
    end
    
    it 'requires correct initial fields' do
      expect(described_class.required_fields).to include(:raw_data)
    end
  end
  
  describe 'field compatibility' do
    it 'has compatible agent chain' do
      expect { described_class.new(raw_data: "test") }.not_to raise_error
    end
  end
end
```

### Integration Testing

#### 1. End-to-End Pipeline Testing

```ruby
RSpec.describe 'Full Pipeline Integration' do
  let(:pipeline) do
    DataProcessingPipeline.new(
      raw_data: "Q1: $100k, Q2: $150k, Q3: $120k, Q4: $180k"
    )
  end
  
  it 'processes data through complete pipeline', :integration do
    VCR.use_cassette('data_processing_pipeline') do
      result = pipeline.run
      
      expect(result[:report]).to include('$100k')
      expect(result[:insights]).to be_present
      expect(result[:summary]).to be_present
    end
  end
  
  it 'handles errors gracefully' do
    invalid_pipeline = DataProcessingPipeline.new(raw_data: nil)
    
    expect { invalid_pipeline.run }.not_to raise_error
    # Should skip agents that can't process nil data
  end
end
```

#### 2. Parallel Execution Testing

```ruby
RSpec.describe ParallelAnalysisPipeline do
  it 'executes parallel agents simultaneously', :integration do
    start_time = Time.now
    
    pipeline = described_class.new(text_data: "test content")
    result = pipeline.run
    
    execution_time = Time.now - start_time
    
    # Should be faster than sequential execution
    expect(execution_time).to be < 5.seconds
    expect(result).to have_key(:sentiment_score)
    expect(result).to have_key(:keywords)
    expect(result).to have_key(:entities)
  end
end
```

### Mocking Agents

#### 1. Mock External API Agents

```ruby
RSpec.describe ApiDataPipeline do
  let(:mock_api_agent) do
    Class.new(RAAF::DSL::Agent) do
      # Context is automatically available - query field
      
      result_transform do
        field :api_data
      end
      
      def run
        # Mock implementation
        { api_data: { status: 'success', data: 'mocked response' } }
      end
    end
  end
  
  before do
    # Replace real agent with mock
    stub_const('ApiAgent', mock_api_agent)
  end
  
  it 'works with mocked API calls' do
    pipeline = described_class.new(query: "test query")
    result = pipeline.run
    
    expect(result[:api_data][:status]).to eq('success')
  end
end
```

#### 2. Mock Expensive Operations

```ruby
RSpec.describe DataAnalysisPipeline do
  let(:fast_mock_analyzer) do
    Class.new(RAAF::DSL::Agent) do
      # Context is automatically available - large_dataset field
      
      result_transform do
        field :analysis_result
      end
      
      def run
        # Fast mock instead of expensive ML analysis
        { analysis_result: "mocked analysis for testing" }
      end
    end
  end
  
  around do |example|
    # Use mock for tests, real implementation in production
    if Rails.env.test?
      stub_const('ExpensiveAnalyzer', fast_mock_analyzer)
    end
    
    example.run
  end
end
```

### Test Data Management

#### 1. Test Data Builders

```ruby
class PipelineTestData
  def self.sample_sales_data
    {
      raw_data: "Q1: $100k, Q2: $150k, Q3: $120k, Q4: $180k",
      analysis_depth: "standard",
      format_type: "json"
    }
  end
  
  def self.large_dataset
    {
      raw_data: File.read(Rails.root.join('spec/fixtures/large_sales_data.json')),
      analysis_depth: "detailed",
      parallel_processing: true
    }
  end
  
  def self.minimal_valid_data
    { raw_data: "Q1: $1k" }
  end
end

# Usage in tests
RSpec.describe DataProcessingPipeline do
  it 'processes sample data' do
    pipeline = described_class.new(PipelineTestData.sample_sales_data)
    expect { pipeline.run }.not_to raise_error
  end
end
```

#### 2. VCR for External API Calls

```ruby
# spec/spec_helper.rb
VCR.configure do |config|
  config.cassette_library_dir = "spec/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  
  # Filter sensitive data
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  config.filter_sensitive_data('<API_ENDPOINT>') { ENV['API_ENDPOINT'] }
end

# In test
RSpec.describe ExternalApiPipeline do
  it 'integrates with external API', :vcr do
    VCR.use_cassette('external_api_success') do
      pipeline = described_class.new(api_query: "test")
      result = pipeline.run
      
      expect(result[:api_response]).to be_present
    end
  end
  
  it 'handles API failures', :vcr do
    VCR.use_cassette('external_api_error') do
      pipeline = described_class.new(api_query: "invalid")
      
      expect { pipeline.run }.not_to raise_error
      # Should handle error gracefully
    end
  end
end
```

#### 3. Parameterized Testing

```ruby
RSpec.describe DataProcessingPipeline do
  describe 'data format handling' do
    [
      { input: "Q1: $100k", expected_quarters: 1 },
      { input: "Q1: $100k, Q2: $150k", expected_quarters: 2 },
      { input: "Q1: $100k, Q2: $150k, Q3: $120k, Q4: $180k", expected_quarters: 4 }
    ].each do |test_case|
      it "handles #{test_case[:expected_quarters]} quarters correctly" do
        pipeline = described_class.new(raw_data: test_case[:input])
        result = pipeline.run
        
        expect(result[:insights]).to include("#{test_case[:expected_quarters]} quarter")
      end
    end
  end
end
```

---

## Advanced Topics

### Custom Pipeline Operations

You can extend pipelines with custom operations:

```ruby
class CustomPipeline < RAAF::Pipeline
  flow DataInput >> :custom_operation >> DataOutput
  
  private
  
  def custom_operation(context)
    # Custom business logic here
    context[:processed_at] = Time.current
    context[:environment] = Rails.env
    
    # Always return the context
    context
  end
end
```

### Pipeline Composition

Compose larger pipelines from smaller ones:

```ruby
class MasterPipeline < RAAF::Pipeline
  flow DataPreprocessing >> AnalyticsPipeline >> ReportingPipeline
end

class AnalyticsPipeline < RAAF::Pipeline
  flow SentimentAnalysis >> KeywordExtraction >> EntityRecognition
end
```

### Dynamic Pipeline Construction

Build pipelines dynamically based on runtime conditions:

```ruby
class DynamicPipeline < RAAF::Pipeline
  def self.build_for_data_type(data_type)
    case data_type
    when :text
      flow TextProcessor >> TextAnalyzer >> TextReporter
    when :numeric
      flow NumericProcessor >> StatisticalAnalyzer >> NumericReporter
    when :mixed
      flow DataSplitter >> 
           (TextProcessor | NumericProcessor) >> 
           UnifiedAnalyzer
    end
  end
end

# Usage
pipeline_class = DynamicPipeline.build_for_data_type(:text)
pipeline = pipeline_class.new(data: input_data)
```

---

## Intelligent Streaming

### Overview

Intelligent streaming enables pipeline-level processing of large arrays by splitting them into configurable streams and executing all scope agents for each stream sequentially. This feature is particularly useful when processing large datasets that would otherwise exceed memory limits or when you need incremental progress updates.

### Use Cases

- **Large batch processing**: Process 1000+ items with memory efficiency
- **Incremental progress**: Get results as each stream completes instead of waiting for entire pipeline
- **State management**: Skip already-processed items, load cached results, persist progress
- **Resumable processing**: Restart interrupted jobs without reprocessing
- **API rate limit management**: Process items in controlled batches

### Basic Streaming Example

```ruby
# Define a pipeline for processing many companies
class ProspectDiscoveryPipeline < RAAF::Pipeline
  flow CompanyFinder >> QuickFitAnalyzer >> DeepIntelligence >> Scoring

  context do
    required :product, :company
    optional min_companies: 100
  end
end

# Configure streaming on the analyzer agent
class QuickFitAnalyzer < RAAF::DSL::Agent
  agent_name "QuickFitAnalyzer"
  model "gpt-4o-mini"  # Cost-effective for filtering

  # Enable streaming with 100 items per stream
  intelligent_streaming stream_size: 100, over: :companies do
    # Optional: Get notified when each stream completes
    on_stream_complete do |stream_num, total, stream_results|
      puts "✅ Processed stream #{stream_num}/#{total}: #{stream_results.count} prospects"

      # Can trigger side effects like enqueueing for enrichment
      EnrichmentQueue.enqueue(stream_results)
    end
  end

  # Standard agent implementation
  schema do
    field :analyzed_companies, type: :array, required: true
  end
end

# Usage
pipeline = ProspectDiscoveryPipeline.new(
  product: product,
  company: company
)

# If CompanyFinder returns 1000 companies, QuickFitAnalyzer will:
# 1. Process them in 10 streams of 100 each
# 2. Execute all downstream agents for each stream
# 3. Call on_stream_complete after each stream
# 4. Merge all results at the end
result = pipeline.run
```

### Streaming Configuration Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `stream_size` | Integer | Number of items per stream (required) | - |
| `over` | Symbol | Field name containing array to stream | Auto-detected |
| `incremental` | Boolean | Enable per-stream callbacks | `false` |

### State Management

Intelligent streaming provides optional state management for advanced use cases:

```ruby
class StateAwareProcessor < RAAF::DSL::Agent
  intelligent_streaming stream_size: 50, incremental: true do
    # Skip items that have already been processed
    skip_if do |record|
      ProcessedRecords.exists?(id: record[:id])
    end

    # Load existing results instead of reprocessing
    load_existing do |record|
      cached = CachedResult.find_by(id: record[:id])
      cached&.data  # Return cached data if available
    end

    # Persist results after each stream completes
    persist_each_stream do |results|
      ProcessedRecords.insert_all(results)
      Rails.logger.info "💾 Saved #{results.count} records"
    end

    # Optional: Hook into stream lifecycle
    on_stream_start do |stream_num, total, stream_data|
      Rails.logger.info "🚀 Starting stream #{stream_num}/#{total}"
    end

    on_stream_complete do |stream_num, total, stream_data, stream_results|
      metrics.record_stream_completion(stream_num, total)
      Rails.logger.info "✅ Completed stream #{stream_num}/#{total}"
    end

    on_stream_error do |stream_num, total, stream_data, error|
      Rails.logger.error "❌ Stream #{stream_num} failed: #{error.message}"
      ErrorReporter.notify(error, context: { stream: stream_num })
    end
  end
end
```

### Incremental Delivery

Enable incremental delivery to receive results as each stream completes:

```ruby
class IncrementalProcessor < RAAF::DSL::Agent
  # incremental: true enables per-stream callbacks
  intelligent_streaming stream_size: 25, incremental: true do
    on_stream_complete do |stream_num, total, stream_data, stream_results|
      # Results available immediately after each stream
      NotificationService.send_progress(
        message: "Processed batch #{stream_num}/#{total}",
        results: stream_results
      )

      # Start downstream processing before pipeline completes
      DownstreamProcessor.enqueue(stream_results)
    end
  end
end
```

### How Streaming Works

1. **Detection**: Pipeline detects agents configured with `intelligent_streaming`
2. **Scope Creation**: Creates a "streaming scope" from the triggering agent to the last sequential agent
3. **Stream Execution**: For each stream of data:
   - Execute all agents in the scope sequentially
   - Optional: Apply state management (skip/load/persist)
   - Optional: Call incremental delivery hooks
4. **Result Merging**: Combine all stream results into final output

### Example: Complete Processing Pipeline

```ruby
# Real-world example: Process 1000 companies with cost optimization
class CostOptimizedDiscoveryPipeline < RAAF::Pipeline
  flow CompanyLoader >> QuickFilter >> DetailedAnalysis >> FinalScoring

  context do
    required :search_terms, :market
  end
end

class CompanyLoader < RAAF::DSL::Agent
  # Loads companies from various sources
  def call
    # Returns { companies: [...1000 items...] }
  end
end

class QuickFilter < RAAF::DSL::Agent
  model "gpt-4o-mini"  # Cheap model for filtering

  # Process 100 companies at a time
  intelligent_streaming stream_size: 100, over: :companies do
    # Skip companies we've already analyzed
    skip_if { |company| company[:analyzed_at].present? }

    # Track progress
    on_stream_complete do |stream_num, total, data, results|
      filtered = results.select { |r| r[:fit_score] >= 60 }
      Rails.logger.info "Stream #{stream_num}: #{filtered.count}/#{data.count} passed filter"
    end
  end

  schema do
    field :companies, type: :array, required: true do
      field :id, type: :integer, required: true
      field :name, type: :string, required: true
      field :fit_score, type: :integer, required: true
    end
  end
end

class DetailedAnalysis < RAAF::DSL::Agent
  model "gpt-4o"  # Expensive model only for good fits

  # Only analyzes companies that passed QuickFilter
  # Automatically receives streamed results

  schema do
    field :companies, type: :array, required: true do
      field :id, type: :integer, required: true
      field :detailed_analysis, type: :object, required: true
    end
  end
end

# Usage with monitoring
pipeline = CostOptimizedDiscoveryPipeline.new(
  search_terms: ["SaaS", "B2B", "enterprise"],
  market: market
)

# Processes 1000 companies in 10 streams of 100
# Total cost: $4.20 instead of $10.20 (60% savings)
result = pipeline.run
puts "Analyzed #{result[:companies].count} companies"
```

### Performance Tuning

Choose stream size based on your specific constraints:

| Data Type | Recommended Stream Size | Rationale |
|-----------|------------------------|-----------|
| Simple objects (< 1KB) | 500-1000 | Low memory overhead |
| Medium objects (1-10KB) | 100-200 | Balanced memory/performance |
| Large objects (> 10KB) | 20-50 | Memory constrained |
| With API calls | 10-25 | API rate limits |
| Database operations | 100-500 | Batch insert efficiency |

### Streaming vs Batching

| Feature | Agent Batching (`in_chunks_of`) | Pipeline Streaming (`intelligent_streaming`) |
|---------|----------------------------------|----------------------------------------------|
| **Scope** | Single agent | Multiple agents in pipeline |
| **Use case** | Memory/API limits | Large dataset processing |
| **State management** | No | Yes (skip/load/persist) |
| **Incremental delivery** | No | Yes |
| **Performance** | Good for single agent | Better for pipelines |
| **Complexity** | Simple | More options |

### Best Practices

1. **Choose appropriate stream size**: Balance memory usage with processing efficiency
2. **Use state management for resumability**: Implement skip_if and persist_each_stream for long-running jobs
3. **Monitor progress**: Use on_stream_complete for progress tracking
4. **Handle errors gracefully**: Implement on_stream_error for partial failure recovery
5. **Test with small datasets first**: Verify behavior before processing large datasets
6. **Consider costs**: Use cheaper models for filtering, expensive models for detailed analysis

### Migration from Manual Batching

If you're currently using manual batching, here's how to migrate:

**Before (manual batching):**
```ruby
companies.each_slice(100) do |batch|
  results = batch.map { |company| analyze(company) }
  save_results(results)
  notify_progress(results.count)
end
```

**After (intelligent streaming):**
```ruby
class CompanyAnalyzer < RAAF::DSL::Agent
  intelligent_streaming stream_size: 100 do
    persist_each_stream { |results| save_results(results) }
    on_stream_complete { |num, total, data, results| notify_progress(results.count) }
  end
end
```

### Troubleshooting

**Stream size too large:**
- Symptom: Memory errors, timeouts
- Solution: Reduce stream_size

**Missing array field:**
- Symptom: "Cannot find array field to stream"
- Solution: Specify `over: :field_name` explicitly

**State not persisting:**
- Symptom: Reprocessing on restart
- Solution: Implement persist_each_stream block

**Callbacks not firing:**
- Symptom: No progress updates
- Solution: Set `incremental: true` for per-stream callbacks

This comprehensive guide should give you everything you need to master the RAAF Pipeline DSL, from basic usage to advanced patterns and testing strategies.

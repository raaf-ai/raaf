# RAAF Pipeline DSL Guide

## Table of Contents

1. [Getting Started with Pipeline DSL](#getting-started-with-pipeline-dsl)
2. [Cookbook: Common Pipeline Patterns](#cookbook-common-pipeline-patterns)
3. [Best Practices for Agent Field Naming](#best-practices-for-agent-field-naming)
4. [Troubleshooting Field Mismatches](#troubleshooting-field-mismatches)
5. [Performance Optimization](#performance-optimization)
6. [Pipeline Testing Strategies](#pipeline-testing-strategies)

---

## Getting Started with Pipeline DSL

### Introduction to the DSL Concept

The RAAF Pipeline DSL provides an elegant way to chain AI agents together, reducing complex pipeline definitions from 66+ lines to just 3 lines while maintaining all functionality. Instead of manually managing context flow and agent coordination, the DSL handles this automatically through agent introspection.

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
  context_reader :raw_data
  
  instructions "Analyze the provided data and extract key insights"
  model "gpt-4o"
  
  result_transform do
    field :insights
    field :summary
  end
end

class ReportGenerator < RAAF::DSL::Agent
  context_reader :insights, :summary
  
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

## Cookbook: Common Pipeline Patterns

### Sequential Processing

The most basic pattern - each agent processes the output of the previous one:

```ruby
class SequentialPipeline < RAAF::Pipeline
  flow InputValidator >> DataProcessor >> OutputFormatter
  
  context_reader :input_data
  
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
  
  context_reader :text_data
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
  context_reader :optional_data  # Optional field
  
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
  
  context_reader :source_url
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
  context_reader :json_data
  
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
  context_reader :large_dataset
  
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
   context_reader :customer_transaction_data
   field :risk_assessment_score
   
   # Avoid
   context_reader :data
   field :result
   ```

2. **Follow consistent patterns**:
   ```ruby
   # Input/Output pairs
   context_reader :raw_customer_data
   field :processed_customer_data
   
   # Analysis/Report pairs
   context_reader :sales_analysis
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
     context_reader :user_profile  # Direct match
   end
   ```

2. **Transformation mapping** (field conversion):
   ```ruby
   class DataTransformer < RAAF::DSL::Agent
     context_reader :raw_data
     
     result_transform do
       field :processed_data  # Transforms raw_data -> processed_data
     end
   end
   ```

3. **Aggregation mapping** (multiple inputs to one output):
   ```ruby
   class DataAggregator < RAAF::DSL::Agent
     context_reader :sales_data, :marketing_data, :customer_data
     
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
  context_reader :raw_data
  result_transform do
    field :processed_data
  end
end
```

**Option C: Update consumer requirements**
```ruby
class ConsumerAgent < RAAF::DSL::Agent
  context_reader :raw_data  # Change to what's actually provided
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
  context_reader :any_field  # Will accept any context
  
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
  context_reader :small_data  # Only read what you need
  
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
  context_reader :data_stream
  
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
  context_reader :critical_result  # Required
  context_reader :optional_result  # Optional - pipeline continues without it
  context_reader :best_effort_result  # Optional
  
  def self.requirements_met?(context)
    # Only require critical result
    context.key?(:critical_result)
  end
end
```

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
      context_reader :query
      
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
      context_reader :large_dataset
      
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

This comprehensive guide should give you everything you need to master the RAAF Pipeline DSL, from basic usage to advanced patterns and testing strategies.
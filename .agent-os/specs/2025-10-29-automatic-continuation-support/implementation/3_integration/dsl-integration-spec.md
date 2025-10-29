# DSL Integration Specification

> Part of: Automatic Continuation Support
> Component: RAAF DSL Integration
> Dependencies: Core Infrastructure, Format Mergers

## Overview

This document specifies how automatic continuation support integrates with RAAF's DSL Agent system, including configuration methods, helper functions, and result transformation.

## DSL Configuration API

### enable_continuation Method

Primary configuration method for agents:

```ruby
module RAAF
  module DSL
    class Agent
      # Class-level configuration
      def self.enable_continuation(**options)
        @continuation_config = RAAF::Models::ContinuationConfig.new(options)
        @continuation_config.validate!
      end

      def self.continuation_config
        @continuation_config
      end

      # Instance access
      def continuation_config
        self.class.continuation_config
      end

      def continuation_enabled?
        continuation_config&.enabled? || false
      end
    end
  end
end
```

### Configuration Options

```ruby
enable_continuation(
  max_attempts: 10,           # Integer: Maximum continuation rounds (default: 10)
  output_format: :csv,         # Symbol: :csv, :markdown, :json, :auto (default: :auto)
  on_failure: :return_partial, # Symbol: :return_partial, :raise_error (default: :return_partial)
  merge_strategy: :format_specific # Internal use, not user-configurable
)
```

### Option Validation

```ruby
def validate_continuation_options!(options)
  # max_attempts validation
  if options[:max_attempts]
    raise ArgumentError, "max_attempts must be positive integer" unless options[:max_attempts].is_a?(Integer) && options[:max_attempts].positive?
    raise ArgumentError, "max_attempts exceeds reasonable limit (50)" if options[:max_attempts] > 50
  end

  # output_format validation
  if options[:output_format]
    valid_formats = [:csv, :markdown, :json, :auto]
    raise ArgumentError, "Invalid output_format. Must be one of: #{valid_formats.join(', ')}" unless valid_formats.include?(options[:output_format])
  end

  # on_failure validation
  if options[:on_failure]
    valid_modes = [:return_partial, :raise_error]
    raise ArgumentError, "Invalid on_failure mode. Must be one of: #{valid_modes.join(', ')}" unless valid_modes.include?(options[:on_failure])
  end
end
```

## Usage Examples

### Example 1: CSV Discovery Agent

```ruby
class CompanyDiscoveryAgent < RAAF::DSL::Agent
  agent_name "CompanyDiscovery"
  model "gpt-4o"

  # Enable continuation for CSV output
  enable_continuation(
    max_attempts: 10,
    output_format: :csv,
    on_failure: :return_partial
  )

  instructions <<~PROMPT
    Find technology companies in the Netherlands.
    Output as CSV with columns: name, city, employees, website
    Find at least 500 companies.
  PROMPT
end

# Usage
agent = CompanyDiscoveryAgent.new
result = agent.run

# Access results
puts result[:data]  # Complete CSV string
puts result[:_continuation_metadata][:continuation_count]  # Number of continuations
```

### Example 2: Markdown Report Agent

```ruby
class MarketAnalysisAgent < RAAF::DSL::Agent
  agent_name "MarketAnalysis"
  model "gpt-4o"

  enable_continuation(
    output_format: :markdown,
    max_attempts: 5
  )

  instructions <<~PROMPT
    Generate a comprehensive market analysis report.
    Include competitor comparison table with 50+ companies.
    Format as markdown with tables and sections.
  PROMPT
end

# Usage
agent = MarketAnalysisAgent.new(market: "SaaS")
result = agent.run

File.write("report.md", result[:content])
```

### Example 3: JSON Extraction Agent with Schema

```ruby
class DataExtractionAgent < RAAF::DSL::Agent
  agent_name "DataExtraction"
  model "gpt-4o"

  enable_continuation(
    output_format: :json,
    max_attempts: 8,
    on_failure: :return_partial  # Return what we have, even if incomplete
  )

  schema do
    field :companies, type: :array, required: true do
      field :id, type: :integer, required: true
      field :name, type: :string, required: true
      field :metadata, type: :object, required: true
    end

    # Schema validation automatically relaxed during continuation
    validate_mode :partial
  end

  instructions "Extract all companies from the document as structured JSON"
end

# Usage
agent = DataExtractionAgent.new(document: large_document)
result = agent.run

companies = result[:companies]
puts "Extracted #{companies.length} companies"
```

## Convenience Methods

### Output Format Helpers

Syntactic sugar for common patterns:

```ruby
module RAAF
  module DSL
    class Agent
      # CSV output convenience
      def self.output_csv(**options)
        enable_continuation(options.merge(output_format: :csv))
      end

      # Markdown output convenience
      def self.output_markdown(**options)
        enable_continuation(options.merge(output_format: :markdown))
      end

      # JSON output convenience
      def self.output_json(**options)
        enable_continuation(options.merge(output_format: :json))
      end
    end
  end
end
```

### Usage Examples

```ruby
class CSVAgent < RAAF::DSL::Agent
  # Equivalent to: enable_continuation(output_format: :csv, max_attempts: 10)
  output_csv max_attempts: 10
end

class MarkdownAgent < RAAF::DSL::Agent
  # Equivalent to: enable_continuation(output_format: :markdown)
  output_markdown
end

class JSONAgent < RAAF::DSL::Agent
  # Equivalent to: enable_continuation(output_format: :json, on_failure: :raise_error)
  output_json on_failure: :raise_error
end
```

## Result Access Helpers

### Instance Methods

```ruby
module RAAF
  module DSL
    class Agent
      # Check if result was continued
      def was_continued?(result)
        result.dig(:_continuation_metadata, :was_continued) || false
      end

      # Get continuation count
      def continuation_count(result)
        result.dig(:_continuation_metadata, :continuation_count) || 0
      end

      # Get total tokens used
      def total_tokens(result)
        result.dig(:_continuation_metadata, :total_output_tokens) || 0
      end

      # Get estimated cost
      def estimated_cost(result)
        result.dig(:_continuation_metadata, :total_cost_estimate) || 0.0
      end

      # Get full continuation metadata
      def continuation_metadata(result)
        result[:_continuation_metadata] || {}
      end

      # Check if merge was successful
      def merge_successful?(result)
        result.dig(:_continuation_metadata, :merge_success) != false
      end
    end
  end
end
```

### Usage Examples

```ruby
agent = CompanyDiscoveryAgent.new
result = agent.run("Find 1000 companies")

if agent.was_continued?(result)
  puts "Continued #{agent.continuation_count(result)} times"
  puts "Total tokens: #{agent.total_tokens(result)}"
  puts "Estimated cost: $#{agent.estimated_cost(result).round(4)}"

  unless agent.merge_successful?(result)
    puts "Warning: Merge had issues"
    puts agent.continuation_metadata(result)[:merge_error]
  end
end
```

## Result Transformation Integration

### Handling Continued Results in Transformers

```ruby
module RAAF
  module DSL
    class Agent
      def self.result_transform(&block)
        @result_transformer = block
      end

      def transform_result(raw_result)
        return raw_result unless @result_transformer

        # Preserve continuation metadata during transformation
        metadata = raw_result[:_continuation_metadata]

        transformed = instance_exec(raw_result, &@result_transformer)

        # Re-attach metadata if not present
        transformed[:_continuation_metadata] = metadata if metadata && !transformed[:_continuation_metadata]

        transformed
      end
    end
  end
end
```

### Example with Transformation

```ruby
class CompanyDiscoveryAgent < RAAF::DSL::Agent
  enable_continuation(output_format: :csv)

  result_transform do |result|
    # Parse CSV into structured data
    csv_data = CSV.parse(result[:data], headers: true)

    companies = csv_data.map do |row|
      {
        name: row["name"],
        city: row["city"],
        employees: row["employees"].to_i,
        website: row["website"]
      }
    end

    # Return transformed result
    {
      companies: companies,
      count: companies.length,
      # Continuation metadata automatically preserved
    }
  end
end

# Usage
result = agent.run
puts result[:companies].length  # Transformed data
puts result[:_continuation_metadata][:continuation_count]  # Metadata preserved
```

## Configuration Inheritance

### Base Agent Pattern

```ruby
# Base agent with shared configuration
class BaseCSVAgent < RAAF::DSL::Agent
  enable_continuation(
    output_format: :csv,
    max_attempts: 10,
    on_failure: :return_partial
  )

  # Shared configuration and methods
end

# Specific agents inherit configuration
class CompanyAgent < BaseCSVAgent
  agent_name "CompanyDiscovery"
  instructions "Find companies..."
end

class ContactAgent < BaseCSVAgent
  agent_name "ContactDiscovery"
  instructions "Find contacts..."
end

# Both inherit continuation configuration from BaseCSVAgent
```

### Override Pattern

```ruby
class BaseAgent < RAAF::DSL::Agent
  enable_continuation(max_attempts: 5)
end

class SpecialAgent < BaseAgent
  # Override parent configuration
  enable_continuation(max_attempts: 15, output_format: :json)
end

# SpecialAgent uses max_attempts: 15, output_format: :json
```

## Configuration Validation Examples

### Valid Configurations

```ruby
# Minimal configuration
enable_continuation(output_format: :csv)

# Full configuration
enable_continuation(
  max_attempts: 10,
  output_format: :markdown,
  on_failure: :return_partial
)

# Using convenience method
output_json max_attempts: 8
```

### Invalid Configurations (Will Raise Errors)

```ruby
# Invalid format
enable_continuation(output_format: :xml)
# => ArgumentError: Invalid output_format. Must be one of: csv, markdown, json, auto

# Invalid max_attempts
enable_continuation(max_attempts: -5)
# => ArgumentError: max_attempts must be positive integer

# Invalid failure mode
enable_continuation(on_failure: :skip)
# => ArgumentError: Invalid on_failure mode. Must be one of: return_partial, raise_error

# Excessive max_attempts
enable_continuation(max_attempts: 100)
# => ArgumentError: max_attempts exceeds reasonable limit (50)
```

## Testing Support

### Test Helpers

```ruby
module RAAF
  module Testing
    module ContinuationHelpers
      def build_continued_result(data, chunk_count: 3, format: :csv)
        {
          success: true,
          data: data,
          _continuation_metadata: {
            was_continued: true,
            continuation_count: chunk_count,
            total_output_tokens: chunk_count * 4096,
            merge_strategy_used: format,
            merge_success: true,
            chunk_sizes: Array.new(chunk_count, 4096),
            finish_reasons: Array.new(chunk_count - 1, "length") + ["stop"]
          }
        }
      end

      def mock_continuation_response(chunks:, format:)
        # Helper to mock multi-chunk responses in tests
      end
    end
  end
end
```

### Test Examples

```ruby
RSpec.describe CompanyDiscoveryAgent do
  include RAAF::Testing::ContinuationHelpers

  it "processes continued results correctly" do
    agent = described_class.new

    # Mock continued result
    result = build_continued_result(csv_data, chunk_count: 5, format: :csv)

    expect(agent.was_continued?(result)).to be true
    expect(agent.continuation_count(result)).to eq(5)
  end

  it "transforms continued results" do
    agent = described_class.new
    result = agent.run("Find companies")

    expect(result[:companies]).to be_an(Array)
    expect(result[:_continuation_metadata]).to be_present
  end
end
```

## Best Practices

### 1. Choose Appropriate max_attempts

```ruby
# For quick responses (reports, summaries)
enable_continuation(max_attempts: 3)

# For medium datasets (100-500 records)
enable_continuation(max_attempts: 5)

# For large datasets (1000+ records)
enable_continuation(max_attempts: 10)
```

### 2. Use Appropriate Failure Modes

```ruby
# For production systems - always return something
enable_continuation(on_failure: :return_partial)

# For development/testing - fail fast
enable_continuation(on_failure: :raise_error)
```

### 3. Monitor Continuation Metadata

```ruby
result = agent.run

if agent.was_continued?(result)
  # Log for monitoring
  Rails.logger.info(
    "Agent #{agent.name} continued",
    count: agent.continuation_count(result),
    cost: agent.estimated_cost(result),
    success: agent.merge_successful?(result)
  )

  # Alert if many continuations (cost concern)
  if agent.continuation_count(result) > 7
    notify_team("High continuation count for #{agent.name}")
  end
end
```

### 4. Handle Partial Results Gracefully

```ruby
result = agent.run

unless agent.merge_successful?(result)
  # Merge failed, handle partial data
  Rails.logger.warn(
    "Continuation merge failed",
    error: agent.continuation_metadata(result)[:merge_error]
  )

  # Still use partial data if available
  if result[:data].present?
    process_partial_data(result[:data])
  else
    handle_complete_failure
  end
end
```

## Migration from Manual Continuation

### Before (Manual Continuation)

```ruby
class OldAgent < RAAF::DSL::Agent
  def call
    result = run
    chunks = [result]

    while result.dig(:finish_reason) == "length" && chunks.length < 10
      continuation = run("Continue from: #{result[:content]}")
      chunks << continuation
      result = continuation
    end

    merge_chunks(chunks)  # Custom merge logic
  end
end
```

### After (Automatic Continuation)

```ruby
class NewAgent < RAAF::DSL::Agent
  enable_continuation(
    max_attempts: 10,
    output_format: :csv
  )

  # Continuation is automatic - no manual logic needed
end
```

**Benefits:**
- 90% less code
- Standardized merge logic
- Automatic metadata tracking
- Better error handling
- Format-specific optimizations

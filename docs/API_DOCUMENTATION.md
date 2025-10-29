# RAAF Continuation API Reference

Complete API documentation for all continuation-related classes, methods, and configuration options.

## Table of Contents

1. [Configuration](#configuration)
2. [Merger Classes](#merger-classes)
3. [Format Detection](#format-detection)
4. [Error Handling](#error-handling)
5. [Logging](#logging)
6. [Cost Calculation](#cost-calculation)

## Configuration

### RAAF::Continuation::Config

Main configuration class for continuation behavior.

#### Initialization

```ruby
config = RAAF::Continuation::Config.new(options = {})
```

**Options:**

| Key | Type | Default | Valid Values | Description |
|-----|------|---------|--------------|-------------|
| `:max_attempts` | Integer | 10 | 1-50 | Maximum continuation attempts |
| `:output_format` | Symbol | :auto | :csv, :markdown, :json, :auto | Output format for merging |
| `:on_failure` | Symbol | :return_partial | :return_partial, :raise_error | Failure handling mode |
| `:merge_strategy` | Symbol, nil | nil | Format-specific | Internal merge strategy (auto-determined) |

**Examples:**

```ruby
# Basic configuration
config = RAAF::Continuation::Config.new

# Custom configuration
config = RAAF::Continuation::Config.new(
  max_attempts: 15,
  output_format: :csv,
  on_failure: :raise_error
)

# String values are auto-converted to symbols
config = RAAF::Continuation::Config.new(output_format: "json")
```

#### Instance Methods

##### max_attempts

```ruby
config.max_attempts
# => 10

# Setter
config.max_attempts = 20
```

**Returns**: Integer between 1 and 50

**Raises**: `RAAF::InvalidConfigurationError` if value is invalid

##### output_format

```ruby
config.output_format
# => :auto

# Setter
config.output_format = :csv
config.output_format = "markdown"  # Converted to :markdown
```

**Returns**: Symbol (:csv, :markdown, :json, :auto)

**Raises**: `RAAF::InvalidConfigurationError` if value is invalid

##### on_failure

```ruby
config.on_failure
# => :return_partial

# Setter
config.on_failure = :raise_error
```

**Returns**: Symbol (:return_partial, :raise_error)

**Raises**: `RAAF::InvalidConfigurationError` if value is invalid

##### merge_strategy

```ruby
config.merge_strategy
# => nil (auto-determined at runtime)

# Setter
config.merge_strategy = :streaming
```

**Returns**: Symbol or nil

##### validate!

Validates all configuration values.

```ruby
config.validate!
# => true (if valid)
# Raises RAAF::InvalidConfigurationError if invalid
```

**Returns**: true if all values are valid

**Raises**: `RAAF::InvalidConfigurationError` if any value is invalid

##### valid?

Check if configuration is valid without raising errors.

```ruby
config.valid?
# => true
```

**Returns**: Boolean

##### to_h

Convert configuration to hash.

```ruby
config.to_h
# => { max_attempts: 10, output_format: :auto, on_failure: :return_partial, merge_strategy: nil }
```

**Returns**: Hash with symbol keys

##### ==

Compare two configurations for equality.

```ruby
config1 = RAAF::Continuation::Config.new(max_attempts: 10)
config2 = RAAF::Continuation::Config.new(max_attempts: 10)
config1 == config2
# => true
```

**Returns**: Boolean

## Merger Classes

### RAAF::Continuation::Mergers::BaseMerger

Base class for all format-specific mergers.

#### Initialization

```ruby
merger = BaseMerger.new(config)
```

**Parameters:**
- `config` (RAAF::Continuation::Config) - Configuration for merge behavior

#### Instance Methods

##### merge(chunks)

Merge chunks into complete content.

```ruby
result = merger.merge(chunks)
# => { content: "...", metadata: {...} }
```

**Parameters:**
- `chunks` (Array<Hash>) - Array of chunk objects
  - Each chunk can be a Hash, String, or nil
  - Hash format: `{ content: String, truncated: Boolean, finish_reason: String }`
  - String format: treated as direct content

**Returns**: Hash with keys:
- `:content` (String, nil) - Merged content or nil if merge failed
- `:metadata` (Hash) - Merge metadata

**Example:**

```ruby
chunks = [
  { content: "id,name\n1,John", truncated: true, finish_reason: "length" },
  { content: "2,Jane\n", truncated: false, finish_reason: "stop" }
]

merger = RAAF::Continuation::Mergers::CSVMerger.new(config)
result = merger.merge(chunks)

puts result[:content]      # Complete merged CSV
puts result[:metadata]     # Merge metadata
```

### RAAF::Continuation::Mergers::CSVMerger

CSV-specific merger for tabular data.

#### Features

- Detects CSV headers
- Handles split quoted fields
- Removes duplicate headers from continuation chunks
- Supports various delimiters (comma, semicolon, tab)
- Preserves row order and data integrity

#### Initialization

```ruby
merger = RAAF::Continuation::Mergers::CSVMerger.new(config)
```

#### Instance Methods

##### merge(chunks)

Merge CSV chunks.

```ruby
merger = RAAF::Continuation::Mergers::CSVMerger.new(config)
result = merger.merge([chunk1, chunk2])

# => {
#      content: "id,name,email\n1,John,john@example.com\n2,Jane,jane@example.com\n",
#      metadata: {
#        merge_success: true,
#        chunk_count: 2,
#        final_content_size: 1024,
#        merge_duration_ms: 45.2,
#        detected_format: "csv"
#      }
#    }
```

**Returns**: Hash with `:content` and `:metadata`

**Metadata Keys:**

| Key | Type | Description |
|-----|------|-------------|
| `:merge_success` | Boolean | Whether merge succeeded |
| `:chunk_count` | Integer | Number of chunks merged |
| `:final_content_size` | Integer | Bytes in final merged content |
| `:merge_duration_ms` | Float | Milliseconds to complete merge |
| `:detected_format` | String | Detected format type |
| `:row_count` | Integer | Number of rows in CSV |
| `:header_row` | String | Detected header row (if any) |
| `:delimiter` | String | Detected delimiter (comma, semicolon, tab) |
| `:merge_error` | String | Error message if merge failed |
| `:error_class` | String | Error class name if merge failed |

### RAAF::Continuation::Mergers::MarkdownMerger

Markdown-specific merger for documentation and reports.

#### Features

- Preserves heading structure
- Handles tables intelligently
- Combines sections across chunks
- Preserves list formatting
- Detects and removes duplicate headers

#### Initialization

```ruby
merger = RAAF::Continuation::Mergers::MarkdownMerger.new(config)
```

#### Instance Methods

##### merge(chunks)

Merge Markdown chunks.

```ruby
merger = RAAF::Continuation::Mergers::MarkdownMerger.new(config)
result = merger.merge([chunk1, chunk2])

# Returns merged markdown with structure preserved
```

**Returns**: Hash with `:content` and `:metadata`

**Metadata Keys:**

| Key | Type | Description |
|-----|------|-------------|
| `:merge_success` | Boolean | Whether merge succeeded |
| `:chunk_count` | Integer | Number of chunks merged |
| `:final_content_size` | Integer | Bytes in final content |
| `:merge_duration_ms` | Float | Milliseconds to complete merge |
| `:detected_format` | String | "markdown" |
| `:heading_count` | Integer | Number of headings found |
| `:table_count` | Integer | Number of tables found |
| `:list_count` | Integer | Number of lists found |

### RAAF::Continuation::Mergers::JSONMerger

JSON-specific merger for structured data.

#### Features

- Handles split JSON arrays
- Repairs malformed JSON
- Preserves object structure
- Handles nested data
- Validates syntax after merge

#### Initialization

```ruby
merger = RAAF::Continuation::Mergers::JSONMerger.new(config)
```

#### Instance Methods

##### merge(chunks)

Merge JSON chunks.

```ruby
merger = RAAF::Continuation::Mergers::JSONMerger.new(config)
result = merger.merge([chunk1, chunk2])

# Returns complete valid JSON string
```

**Returns**: Hash with `:content` and `:metadata`

**Metadata Keys:**

| Key | Type | Description |
|-----|------|-------------|
| `:merge_success` | Boolean | Whether merge succeeded |
| `:chunk_count` | Integer | Number of chunks merged |
| `:final_content_size` | Integer | Bytes in final content |
| `:merge_duration_ms` | Float | Milliseconds to complete merge |
| `:detected_format` | String | "json" |
| `:json_type` | String | "array" or "object" |
| `:item_count` | Integer | Number of items in array/object |
| `:had_repairs` | Boolean | Whether JSON was repaired |
| `:repair_details` | String | Details of repairs made |

## Format Detection

### RAAF::Continuation::FormatDetector

Automatically detects response format.

#### Initialization

```ruby
detector = RAAF::Continuation::FormatDetector.new
```

#### Class Methods

##### detect(content)

Detect format from content string.

```ruby
detector = RAAF::Continuation::FormatDetector.new

csv_format = detector.detect("id,name\n1,John")
# => :csv

json_format = detector.detect("[{\"id\": 1, \"name\": \"John\"}]")
# => :json

markdown_format = detector.detect("# Heading\nSome content")
# => :markdown
```

**Parameters:**
- `content` (String) - Content to analyze

**Returns**: Symbol (:csv, :markdown, :json, nil)

**Returns nil if format cannot be detected**

##### csv?(content)

Check if content is CSV.

```ruby
detector.csv?("id,name\n1,John")
# => true
```

**Parameters:**
- `content` (String) - Content to check

**Returns**: Boolean

##### json?(content)

Check if content is JSON.

```ruby
detector.json?("[{\"id\": 1}]")
# => true
```

**Parameters:**
- `content` (String) - Content to check

**Returns**: Boolean

##### markdown?(content)

Check if content is Markdown.

```ruby
detector.markdown?("# Heading")
# => true
```

**Parameters:**
- `content` (String) - Content to check

**Returns**: Boolean

## Error Handling

### RAAF::Continuation::MergeError

Raised when continuation merge fails and `on_failure` is `:raise_error`.

#### Attributes

```ruby
begin
  # Merge that fails
rescue RAAF::Continuation::MergeError => e
  puts e.message        # Error message
  puts e.merge_attempt  # Which attempt failed
  puts e.chunk_count    # Number of chunks processed
  puts e.format         # Format being merged (:csv, :markdown, :json)
end
```

**Available Methods:**

| Method | Returns | Description |
|--------|---------|-------------|
| `message` | String | Error message |
| `merge_attempt` | Integer | Attempt number (1-based) |
| `chunk_count` | Integer | Number of chunks |
| `format` | Symbol | Format being merged |
| `original_error` | Exception | Underlying error |

#### Examples

```ruby
# Catching merge errors
begin
  result = merger.merge(chunks)
rescue RAAF::Continuation::MergeError => e
  Rails.logger.error "Merge failed on attempt #{e.merge_attempt}"
  Rails.logger.error "Format: #{e.format}"
  Rails.logger.error "Chunks: #{e.chunk_count}"
  # Handle error
end
```

### RAAF::Continuation::TruncationError

Raised when maximum continuation attempts exceeded.

#### Attributes

```ruby
begin
  # Too many continuations
rescue RAAF::Continuation::TruncationError => e
  puts e.message         # Error message
  puts e.max_attempts    # Maximum attempts allowed
  puts e.attempts_made   # Attempts made before error
  puts e.partial_content # Best-effort merged content
end
```

## Logging

### RAAF::Continuation::Logging

Control logging output for continuation operations.

#### Module Methods

##### enable_debug

```ruby
RAAF::Continuation::Logging.enable_debug = true

# Now detailed logs will be output
```

**Default**: false

##### disable_debug

```ruby
RAAF::Continuation::Logging.disable_debug = true
```

##### debug_enabled?

```ruby
RAAF::Continuation::Logging.debug_enabled?
# => true
```

**Returns**: Boolean

#### Log Output Examples

When debug is enabled:

```
▶️ Starting continuation merge for CSV format
📋 Chunk 1: 1024 bytes, truncated=true, finish_reason=length
📋 Chunk 2: 2048 bytes, truncated=false, finish_reason=stop
✅ Merge completed in 125ms
📊 Final content size: 3072 bytes
```

## Cost Calculation

### RAAF::Continuation::CostCalculator

Calculate costs associated with continuation.

#### Initialization

```ruby
calculator = RAAF::Continuation::CostCalculator.new(model: "gpt-4o")
```

**Parameters:**
- `:model` (String) - Model name for cost calculation

#### Instance Methods

##### cost_for_tokens(token_count)

Calculate cost for token count.

```ruby
calculator = RAAF::Continuation::CostCalculator.new(model: "gpt-4o")

cost = calculator.cost_for_tokens(1000)
# => 0.015  (in USD)
```

**Parameters:**
- `token_count` (Integer) - Number of tokens

**Returns**: Float (cost in USD)

**Model Costs (USD per 1000 tokens):**

| Model | Input Cost | Output Cost |
|-------|------------|-------------|
| gpt-4o | $0.005 | $0.015 |
| gpt-4o-mini | $0.00015 | $0.0006 |
| gpt-3.5-turbo | $0.0015 | $0.002 |
| claude-3-5-sonnet | $0.003 | $0.015 |

##### estimated_continuation_cost(attempts)

Estimate cost of continuation.

```ruby
# Estimate cost for 2 continuation attempts
cost = calculator.estimated_continuation_cost(2)
# => 0.045  (in USD)
```

**Parameters:**
- `attempts` (Integer) - Number of continuation attempts

**Returns**: Float (estimated cost in USD)

**Calculation:**
- Base response: ~2000 tokens
- Each continuation: ~1000 tokens (50% of base)
- Cost = base_cost + (attempts × 0.5 × base_cost)

##### cost_per_chunk

Get cost per continuation chunk.

```ruby
cost = calculator.cost_per_chunk
# => 0.015
```

**Returns**: Float (cost in USD)

## DSL Integration

### Continuation Configuration in Agents

Configure continuation directly in agent class:

```ruby
class MyAgent < RAAF::DSL::Agent
  agent_name "MyAgent"
  model "gpt-4o"

  continuation_config do
    max_attempts 15
    output_format :csv
    on_failure :return_partial
  end
end
```

#### Available DSL Methods

##### continuation_config

Configure continuation behavior.

```ruby
continuation_config do
  max_attempts 15
  output_format :csv
  on_failure :raise_error
end
```

##### continuation_enabled

Enable or disable continuation for agent.

```ruby
continuation_enabled true   # Enable (default)
continuation_enabled false  # Disable
```

**Default**: true

## Complete Integration Example

```ruby
class DataReportAgent < RAAF::DSL::Agent
  agent_name "DataReportAgent"
  model "gpt-4o"

  # Configure continuation
  continuation_config do
    max_attempts 20
    output_format :csv
    on_failure :return_partial
  end

  static_instructions <<~PROMPT
    Generate a detailed CSV report with:
    - id, company, revenue, employees, industry
    - 500+ rows of realistic data
  PROMPT
end

# Usage
agent = DataReportAgent.new
result = agent.run("Generate top tech companies")

# Access merged content
csv_content = result[:content]

# Check merge status
metadata = result[:metadata]
if metadata[:merge_success]
  rows = CSV.parse(csv_content, headers: true)
  puts "Successfully merged #{rows.length} rows"
else
  puts "Partial merge: #{metadata[:merge_error]}"
end

# Track costs
attempts = metadata[:continuation_attempts]
cost_calculator = RAAF::Continuation::CostCalculator.new(model: "gpt-4o")
total_cost = cost_calculator.estimated_continuation_cost(attempts)
puts "Cost estimate: $#{total_cost.round(4)}"
```

## See Also

- **[Continuation Guide](./CONTINUATION_GUIDE.md)** - User guide and best practices
- **[Examples](./EXAMPLES.md)** - Working code examples
- **[Troubleshooting](./TROUBLESHOOTING.md)** - Common issues and solutions

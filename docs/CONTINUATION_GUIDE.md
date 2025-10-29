# RAAF Continuation Feature Guide

Automatic continuation support for handling large AI responses that exceed token limits. This guide covers enabling, configuring, and using the continuation feature in your RAAF agents.

## Quick Start

The continuation feature is **enabled by default** and requires no configuration for basic usage:

```ruby
class LargeDatasetAnalyzer < RAAF::DSL::Agent
  agent_name "DatasetAnalyzer"
  model "gpt-4o"

  static_instructions "Analyze large datasets and return CSV results"

  # Continuation is automatic - agent will continue if truncated
  # No additional configuration needed
end

# Run agent - continuation happens transparently
agent = LargeDatasetAnalyzer.new
result = agent.run("Analyze this 1000-row dataset...")

# Result contains complete data (merged from continuation chunks)
puts result[:content]  # Complete CSV, Markdown, or JSON data
```

## Configuration

### Basic Configuration

Configure continuation behavior at the agent level using the DSL:

```ruby
class ConfiguredAgent < RAAF::DSL::Agent
  agent_name "ConfiguredAgent"
  model "gpt-4o"

  # Configure continuation behavior
  continuation_config do
    max_attempts 15              # Maximum continuation attempts (1-50, default: 10)
    output_format :csv           # Expected output format (:csv, :markdown, :json, :auto)
    on_failure :return_partial   # Handle merge failures (:return_partial, :raise_error)
  end
end

# Usage
agent = ConfiguredAgent.new
result = agent.run("Generate CSV report")
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `max_attempts` | Integer (1-50) | 10 | Maximum continuation attempts before stopping |
| `output_format` | Symbol | :auto | Output format for merging (auto-detected by default) |
| `on_failure` | Symbol | :return_partial | How to handle merge failures |

### Output Format Options

| Format | Best For | Auto-Detection |
|--------|----------|----------------|
| `:csv` | Tabular data, structured records | Detects CSV headers and comma/semicolon delimiters |
| `:markdown` | Reports, documentation, tables | Detects markdown headers (#, ##) and table syntax |
| `:json` | Structured data, API responses | Detects JSON array/object syntax, brackets |
| `:auto` | Mixed formats, unknown output | Automatically detects format per chunk |

### Failure Handling

```ruby
# Return partial results on merge failure (default)
continuation_config do
  on_failure :return_partial
end
# If merge fails, returns best-effort merged content

# Raise error on merge failure
continuation_config do
  on_failure :raise_error
end
# If merge fails, raises MergeError with details
```

## Enabling/Disabling Continuation

### Automatic (Default)

Continuation is enabled by default when using RAAF agents:

```ruby
class MyAgent < RAAF::DSL::Agent
  agent_name "MyAgent"
  model "gpt-4o"
  # Continuation enabled automatically
end
```

### Disabling Continuation

To disable continuation for specific agents:

```ruby
class QuickAgent < RAAF::DSL::Agent
  agent_name "QuickAgent"
  model "gpt-4o"

  # Disable continuation for this agent
  continuation_enabled false
end

agent = QuickAgent.new
result = agent.run("Quick question")
# If response is truncated, you'll get incomplete data
```

## Common Use Cases

### 1. Large CSV Report Generation

```ruby
class CSVReportGenerator < RAAF::DSL::Agent
  agent_name "CSVReportGenerator"
  model "gpt-4o"

  continuation_config do
    output_format :csv          # Expect CSV output
    max_attempts 20             # More attempts for large reports
  end

  static_instructions <<~PROMPT
    Generate a complete CSV report with columns:
    id, company_name, annual_revenue, employee_count, industry, location

    Include at least 500 rows of realistic company data.
  PROMPT
end

# Generate report
agent = CSVReportGenerator.new
result = agent.run("Generate enterprise companies in tech sector")

# Parse complete CSV (even if it was split across multiple continuations)
csv_rows = CSV.parse(result[:content], headers: true)
puts "Generated #{csv_rows.length} companies"

# Access metadata about the continuation process
puts "Continuation attempts: #{result[:metadata][:continuation_attempts]}"
puts "Merge success: #{result[:metadata][:merge_success]}"
```

### 2. Large Markdown Documentation

```ruby
class DocumentationGenerator < RAAF::DSL::Agent
  agent_name "DocumentationGenerator"
  model "gpt-4o"

  continuation_config do
    output_format :markdown
    max_attempts 15
  end

  static_instructions <<~PROMPT
    Generate comprehensive documentation with:
    - Table of contents
    - Multiple sections with headers
    - Code examples
    - Tables and diagrams

    Make it detailed and thorough (3000+ words).
  PROMPT
end

agent = DocumentationGenerator.new
result = agent.run("Document the Ruby on Rails framework")

# Complete documentation merged across continuation chunks
File.write("rails_guide.md", result[:content])
```

### 3. Large JSON Dataset Processing

```ruby
class JSONDataProcessor < RAAF::DSL::Agent
  agent_name "JSONDataProcessor"
  model "gpt-4o"

  continuation_config do
    output_format :json
    on_failure :raise_error  # Strict error handling
  end

  static_instructions <<~PROMPT
    Process data and return as JSON array of objects.
    Each object should have: id, name, status, timestamp, metadata
    Generate 200+ objects.
  PROMPT
end

agent = JSONDataProcessor.new
result = agent.run("Generate sample product catalog")

# Parse complete JSON
data = JSON.parse(result[:content])
puts "Processed #{data.length} items"
```

## Success Rates and Limitations

### Reported Success Rates

| Format | Success Rate | Typical Scenario |
|--------|-------------|------------------|
| CSV | 95% | Tabular data with headers, clean formatting |
| Markdown | 85-95% | Documentation with headers, tables, sections |
| JSON | 60-70% | Structured objects, arrays, nested data |

### Why Success Rates Vary

**CSV (95% success)**
- Clear structure with headers
- Predictable row format
- Easily reconstructed from partial rows
- Handles split quoted fields well

**Markdown (85-95% success)**
- Flexible formatting allows recovery
- Headers and sections help reconstruct structure
- Tables are harder to repair (75-85% success)
- Lists recover well (95%+ success)

**JSON (60-70% success)**
- Syntax-sensitive (missing brackets cause failures)
- Complex nesting is harder to repair
- LLMs often produce malformed JSON in chunks
- Requires careful bracket/brace matching

### Known Limitations

1. **Concurrent Continuation**: Each agent processes continuation sequentially. Parallel agents cannot share continuation state.

2. **Format Switching**: If LLM switches formats mid-response, continuation may fail. Use explicit `output_format` configuration to prevent this.

3. **Very Large Responses**: Responses requiring > 50 continuation attempts will be stopped. Configure `max_attempts` to balance completeness vs cost.

4. **Special Characters**: Some CSV dialects with rare delimiters may not be detected correctly. Specify `output_format :csv` explicitly.

5. **Nested JSON**: Deeply nested JSON (5+ levels) has lower recovery success. Keep JSON structures flat when possible.

## Error Handling

### Automatic Error Recovery

The continuation system includes automatic error recovery:

```ruby
agent = MyAgent.new
result = agent.run("Generate data")

# Check if result had merge issues
if result[:metadata][:merge_success]
  puts "✅ Complete data - all chunks merged successfully"
else
  puts "⚠️ Partial data - some chunks couldn't merge"
  puts "Error: #{result[:metadata][:merge_error]}"
end
```

### Handling Merge Failures

```ruby
class RobustAgent < RAAF::DSL::Agent
  agent_name "RobustAgent"
  model "gpt-4o"

  continuation_config do
    on_failure :return_partial  # Get partial results instead of error
  end
end

agent = RobustAgent.new
result = agent.run("Process data")

# Always get something back
case result[:metadata][:merge_success]
when true
  process_complete_data(result[:content])
when false
  process_partial_data(result[:content])
  log_merge_error(result[:metadata][:merge_error])
end
```

### Strict Error Handling

```ruby
class StrictAgent < RAAF::DSL::Agent
  agent_name "StrictAgent"
  model "gpt-4o"

  continuation_config do
    on_failure :raise_error  # Fail hard if merge problems occur
  end
end

agent = StrictAgent.new
begin
  result = agent.run("Process critical data")
  # Only reaches here if merge succeeded
  process_data(result[:content])
rescue RAAF::Continuation::MergeError => e
  # Handle merge failure
  Rails.logger.error "Merge failed: #{e.message}"
  # Decide whether to retry, use fallback, etc.
end
```

## Cost Estimation

### Token Usage

Continuation adds minimal cost beyond the initial response:

```
Token Cost Calculation:
- Initial response: X tokens
- Continuation attempts: Y × 0.5X tokens (average)
  (Continuations are smaller - they skip headers/preamble)

Total Cost = X + (Y × 0.5X)

Example:
- Single response: 2000 tokens ($0.03)
- With 2 continuations: 2000 + (2 × 1000) = 4000 tokens ($0.06)
```

### Cost Optimization

```ruby
# Use shorter models for large data to reduce continuation
class EconomyGenerator < RAAF::DSL::Agent
  agent_name "EconomyGenerator"
  model "gpt-4o-mini"  # Cheaper than gpt-4o

  continuation_config do
    max_attempts 5  # Limit continuations to control costs
  end
end

# For cost-sensitive tasks
class CostAwareGenerator < RAAF::DSL::Agent
  agent_name "CostAwareGenerator"
  model "gpt-4o"

  continuation_config do
    max_attempts 3  # Stop early to control costs
    on_failure :return_partial  # Accept partial data
  end
end
```

### Cost Tracking

Monitor continuation costs in your application:

```ruby
class DataProcessor
  def generate_with_cost_tracking
    agent = MyAgent.new
    result = agent.run("Generate data")

    # Track continuation attempts and costs
    attempts = result[:metadata][:continuation_attempts]

    cost_multiplier = 1.0 + (attempts * 0.5)
    base_cost = 0.03  # gpt-4o response cost
    total_cost = base_cost * cost_multiplier

    Rails.logger.info "Continuation cost: #{attempts} attempts × $#{total_cost}"
  end
end
```

## Monitoring and Debugging

### Check Continuation Status

```ruby
result = agent.run("Generate data")

metadata = result[:metadata]

puts "✅ Merge successful: #{metadata[:merge_success]}"
puts "📊 Chunks merged: #{metadata[:chunk_count]}"
puts "🔄 Continuation attempts: #{metadata[:continuation_attempts]}"
puts "⏱️  Total merge time: #{metadata[:merge_duration_ms]}ms"
puts "💾 Final content size: #{metadata[:final_content_size]} bytes"

# If merge failed
if !metadata[:merge_success]
  puts "❌ Merge error: #{metadata[:merge_error]}"
  puts "🔍 Error class: #{metadata[:error_class]}"
end
```

### Enable Debug Logging

```ruby
# In your agent
class DebugAgent < RAAF::DSL::Agent
  agent_name "DebugAgent"
  model "gpt-4o"

  continuation_config do
    output_format :csv
  end
end

# Enable logging
RAAF::Continuation::Logging.enable_debug = true

agent = DebugAgent.new
result = agent.run("Generate CSV")

# Logs will show:
# ▶️ Starting continuation merge for CSV format
# 📋 Chunk 1: 1024 bytes
# 📋 Chunk 2: 2048 bytes
# ✅ Merge completed in 125ms
```

## Migration Guide

### For Existing Agents

If you have existing agents that don't use continuation:

```ruby
# Before (no continuation support)
class LegacyAgent < RAAF::DSL::Agent
  agent_name "LegacyAgent"
  model "gpt-4o"
end

# After (add continuation support)
class ModernAgent < RAAF::DSL::Agent
  agent_name "ModernAgent"
  model "gpt-4o"

  # Just add configuration - nothing else changes
  continuation_config do
    output_format :auto  # Auto-detect format
    max_attempts 10      # Default value
  end
end

# Usage is identical
agent = ModernAgent.new
result = agent.run("Generate report")
```

### Upgrading from Manual Handling

If you previously handled truncation manually:

```ruby
# Before: Manual truncation handling
class ManualAgent < RAAF::DSL::Agent
  agent_name "ManualAgent"
  model "gpt-4o"

  def call
    result = run

    # Manual truncation check
    if result.truncated?
      # Had to manually request continuation
      # This is error-prone and expensive
    end

    result
  end
end

# After: Automatic continuation handling
class AutoAgent < RAAF::DSL::Agent
  agent_name "AutoAgent"
  model "gpt-4o"

  # No need for manual truncation handling!
  # Continuation happens automatically
end

# Just use it normally
agent = AutoAgent.new
result = agent.run("Generate report")
# Automatically continued and merged if needed
```

## Best Practices

1. **Specify Output Format**: Always explicitly set `output_format` if you know the expected format. This improves merge success:
   ```ruby
   continuation_config do
     output_format :csv  # Better than :auto
   end
   ```

2. **Set Reasonable max_attempts**: Balance completeness vs cost:
   ```ruby
   continuation_config do
     max_attempts 10  # Usually sufficient
     # max_attempts 20  # For very large reports
     # max_attempts 5   # For cost-sensitive tasks
   end
   ```

3. **Handle Partial Results**: Implement fallback for when merge fails:
   ```ruby
   result = agent.run("Generate data")

   if result[:metadata][:merge_success]
     process_complete_data(result[:content])
   else
     process_partial_data(result[:content])
     notify_admin("Partial data retrieved")
   end
   ```

4. **Monitor Cost**: Track continuation attempts to understand costs:
   ```ruby
   attempts = result[:metadata][:continuation_attempts]
   cost = attempts * 0.015  # ~1.5 cents per continuation
   ```

5. **Test with Real Data**: Test agents with data that actually triggers continuation:
   ```ruby
   agent = MyAgent.new
   # Use realistic instruction that generates large responses
   result = agent.run("Generate 500 rows of detailed data...")
   # Verify continuation happened
   assert result[:metadata][:continuation_attempts] > 0
   ```

## Troubleshooting

### Problem: Continuation not happening

**Symptom**: Expected continuation but `continuation_attempts: 0`

**Solutions**:
- Make sure instructions generate large output
- Check `max_tokens` isn't artificially limiting response
- Verify `continuation_enabled` isn't set to false
- Monitor if actual response is actually being truncated

### Problem: Merge failures for CSV

**Symptom**: `merge_success: false` for CSV output

**Solutions**:
- Explicitly set `output_format :csv`
- Check for unusual delimiters (not comma or semicolon)
- Verify no special characters in quoted fields
- Try `on_failure :return_partial` to get best-effort result

### Problem: JSON merge very slow

**Symptom**: Merge takes > 1000ms for JSON

**Solutions**:
- Reduce complexity of JSON structure (flatten nested data)
- Use `max_attempts 5` to stop early
- Consider splitting into smaller requests
- Check for very large strings within JSON objects

### Problem: High continuation costs

**Symptom**: Unexpected cost increases

**Solutions**:
- Reduce `max_attempts` to control retries
- Use cheaper model like gpt-4o-mini
- Shorten instructions to generate more concise output
- Consider if continuation is necessary (accept partial results)

## See Also

- **[API Documentation](./API_DOCUMENTATION.md)** - Complete API reference
- **[Examples](./EXAMPLES.md)** - Working code examples
- **[Troubleshooting](./TROUBLESHOOTING.md)** - Common issues and solutions

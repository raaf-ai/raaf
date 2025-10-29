# RAAF Continuation Troubleshooting Guide

Comprehensive guide to diagnosing and resolving continuation-related issues.

## Quick Diagnostics

### Step 1: Check if Continuation Actually Happened

```ruby
result = agent.run(query)
metadata = result[:metadata]

puts "Continuation attempted: #{metadata[:continuation_attempts] > 0}"
puts "Merge successful: #{metadata[:merge_success]}"
puts "Chunks merged: #{metadata[:chunk_count]}"
```

### Step 2: Check Metadata for Errors

```ruby
if !metadata[:merge_success]
  puts "Merge error: #{metadata[:merge_error]}"
  puts "Error class: #{metadata[:error_class]}"
end
```

### Step 3: Enable Debug Logging

```ruby
RAAF::Continuation::Logging.enable_debug = true

# Now rerun to get detailed logs
result = agent.run(query)
```

## Common Issues

### Issue 1: Continuation Not Happening

**Symptom**: `continuation_attempts: 0` even though expecting large output

**Diagnosis Checklist**:

1. Check if response is actually truncated:
   ```ruby
   result = agent.run(query)
   puts "Response truncated: #{result.truncated?}"
   puts "Finish reason: #{result.finish_reason}"
   ```

2. Verify continuation is enabled:
   ```ruby
   # Should not see continuation_enabled false in agent definition
   class MyAgent < RAAF::DSL::Agent
     continuation_enabled true  # Default, but verify
   end
   ```

3. Check if instructions generate large output:
   ```ruby
   # Bad: Instructions too vague, generates small response
   static_instructions "Answer questions"

   # Good: Explicit instruction for large output
   static_instructions "Generate 500+ rows of detailed CSV data"
   ```

4. Monitor model's max_tokens:
   ```ruby
   # If max_tokens is set very low, no continuation needed
   # Check your agent configuration or Runner settings
   ```

**Solutions**:

```ruby
# Solution 1: Make instructions more explicit about size
class MyAgent < RAAF::DSL::Agent
  static_instructions <<~PROMPT
    Generate a CSV with 500+ rows of data.
    Include all requested columns.
    Make it comprehensive and detailed.
  PROMPT
end

# Solution 2: Test with genuinely large data
result = agent.run("""
  Generate 1000 companies with these fields:
  company_id, name, industry, revenue, employees,
  headquarters, description, website, linkedin_url

  Include detailed, realistic information for each.
""")

# Solution 3: Check actual response size
if result[:metadata][:final_content_size] < 1000
  puts "Response is small - continuation may not be needed"
  puts "Size: #{result[:metadata][:final_content_size]} bytes"
end
```

### Issue 2: CSV Merge Failures

**Symptom**: `merge_success: false` for CSV output

**Common Causes**:

1. **Unusual delimiter detection**
   ```ruby
   # CSV with semicolons not detected
   result[:content]
   # "id;name;email\n1;John;john@example.com"

   # Diagnostic
   metadata[:detected_format]
   # => "csv" (if detected)
   ```

2. **Quoted fields split across chunks**
   ```ruby
   # Chunk 1 ends with opening quote
   chunk1 = { content: 'id,notes\n1,"Incomplete note', truncated: true }
   # Chunk 2 starts in middle of quoted field
   chunk2 = { content: ' continuation"' }
   ```

3. **Header row duplication**
   ```ruby
   chunk1 = { content: "id,name\n1,John" }
   chunk2 = { content: "id,name\n2,Jane" }  # Duplicate header
   ```

**Solutions**:

```ruby
# Solution 1: Explicitly specify CSV format
continuation_config do
  output_format :csv  # Not :auto
end

# Solution 2: Configure to handle merge failures gracefully
continuation_config do
  on_failure :return_partial  # Get what we can
end

# Solution 3: Implement custom error handling
begin
  result = agent.run(query)
  csv_data = CSV.parse(result[:content], headers: true)
rescue CSV::ParsingError => e
  if result[:metadata][:merge_success]
    # Merge succeeded but CSV has syntax issues
    puts "CSV parsing error: #{e.message}"
    # Try to fix malformed CSV
    fixed_content = repair_csv(result[:content])
  else
    # Merge failed
    puts "Merge failed - partial data available"
    puts "Error: #{result[:metadata][:merge_error]}"
  end
end

def repair_csv(content)
  # Try to fix common CSV issues
  lines = content.lines

  # Check for unclosed quotes
  fixed_lines = []
  quote_count = 0

  lines.each do |line|
    quote_count += line.count('"')
    if quote_count.even?
      fixed_lines << line
      quote_count = 0
    else
      # Unclosed quote, keep accumulating
      fixed_lines[-1] = (fixed_lines[-1] || "") + line
    end
  end

  fixed_lines.join
end
```

### Issue 3: Markdown Merge Problems

**Symptom**: Tables get corrupted or sections merge incorrectly

**Common Causes**:

1. **Table interrupted mid-row**
   ```
   Chunk 1:
   | ID | Name | Status |
   |---|---|---|
   | 1 | John | Active |

   Chunk 2:
   | 2 | Jane | Inactive |
   ```

2. **Headers duplicated or malformed**
   ```
   Chunk 1 ends with:
   ## Section 2

   Chunk 2 starts with:
   ## Section 2
   ...
   ```

3. **List formatting issues**
   ```
   - Item 1
   - Item 2
   (chunk boundary)
   - Item 3  # Loses context of list
   ```

**Solutions**:

```ruby
# Solution 1: Use `:markdown` format explicitly
continuation_config do
  output_format :markdown  # Not :auto
  max_attempts 15  # Markdown may need more attempts
end

# Solution 2: Process and validate structure
result = agent.run(query)
content = result[:content]

# Validate heading hierarchy
lines = content.lines
heading_levels = []
lines.each do |line|
  if line =~ /^(#+)\s/
    level = $1.length
    heading_levels << level
  end
end

# Check for valid nesting (no jumps from h1 to h3)
valid = true
heading_levels.each_cons(2) do |prev, curr|
  if curr > prev + 1
    puts "⚠️  Invalid heading jump: h#{prev} to h#{curr}"
    valid = false
  end
end

# Solution 3: Repair markdown tables
def repair_markdown_tables(content)
  lines = content.lines
  in_table = false
  table_lines = []
  result = []

  lines.each do |line|
    if line.strip.start_with?('|')
      unless in_table
        # Starting new table
        in_table = true
        table_lines = [line]
      else
        table_lines << line
      end
    else
      if in_table
        # End of table - validate and add
        result.concat(validate_and_fix_table(table_lines))
        in_table = false
        table_lines = []
      end
      result << line
    end
  end

  # Don't forget last table if exists
  result.concat(validate_and_fix_table(table_lines)) if in_table

  result.join
end

def validate_and_fix_table(lines)
  return lines if lines.length < 2

  # Table should have: header, separator, data rows
  header = lines[0]
  col_count = header.count('|') - 1

  fixed = [header]

  # Add separator if missing
  unless lines[1]&.include?('---')
    separator = '|' + Array.new(col_count) { '---' }.join('|') + '|'
    fixed << separator
  else
    fixed << lines[1]
  end

  # Add remaining rows, ensuring column count matches
  (2...lines.length).each do |i|
    row = lines[i]
    row_count = row.count('|') - 1
    if row_count != col_count
      # Fix mismatched column count
      row = row.gsub(/\|+/, '|').gsub(/\|\s*$/, ' |')
    end
    fixed << row
  end

  fixed
end
```

### Issue 4: JSON Merge Failures

**Symptom**: `merge_success: false` for JSON output, or invalid JSON returned

**Common Causes**:

1. **Unmatched brackets/braces**
   ```
   Chunk 1: [{"id": 1, "name": "Item1"
   Chunk 2: }, {"id": 2, "name": "Item2"}]
   ```

2. **Invalid escape sequences**
   ```
   {"description": "Line 1\
   Line 2"}  # Backslash at end of line causes issues
   ```

3. **Trailing commas**
   ```
   {"items": [1, 2, 3,]}  # Valid in JavaScript, not JSON
   ```

4. **Unquoted keys**
   ```
   {id: 1, name: "John"}  # Valid in JavaScript, not JSON
   ```

**Solutions**:

```ruby
# Solution 1: Use `:json` format explicitly
continuation_config do
  output_format :json  # Not :auto
  max_attempts 10  # May need retries
  on_failure :return_partial  # Accept partial valid JSON
end

# Solution 2: Implement robust JSON parsing
def parse_json_tolerantly(content)
  # Attempt 1: Direct parse
  begin
    return JSON.parse(content)
  rescue JSON::ParsingError
    # Continue to repair attempts
  end

  # Attempt 2: Remove trailing commas
  repaired = content.gsub(/,(\s*[}\]])/, '\1')
  begin
    return JSON.parse(repaired)
  rescue JSON::ParsingError
    # Continue to more aggressive repair
  end

  # Attempt 3: Extract valid JSON parts
  valid_json = extract_valid_json(content)
  JSON.parse(valid_json) if valid_json
end

def extract_valid_json(content)
  # Find first { or [ and try to match brackets
  start_idx = content.index(/[\{\[]/)
  return nil unless start_idx

  bracket_map = { '{' => '}', '[' => ']' }
  opening = content[start_idx]
  closing = bracket_map[opening]

  depth = 0
  end_idx = nil

  start_idx.upto(content.length - 1) do |i|
    char = content[i]
    if char == opening
      depth += 1
    elsif char == closing
      depth -= 1
      if depth == 0
        end_idx = i
        break
      end
    end
  end

  return nil unless end_idx

  content[start_idx..end_idx]
end

# Solution 3: Validate structure before merge
def validate_json_structure(content)
  # Check for balanced brackets
  open_braces = content.count('{')
  close_braces = content.count('}')
  open_brackets = content.count('[')
  close_brackets = content.count(']')

  issues = []
  issues << "Unbalanced braces: #{open_braces} vs #{close_braces}" unless open_braces == close_braces
  issues << "Unbalanced brackets: #{open_brackets} vs #{close_brackets}" unless open_brackets == close_brackets

  issues
end
```

### Issue 5: Format Auto-Detection Failing

**Symptom**: `detected_format: nil` or wrong format detected

**Causes**:

1. **Content doesn't match any format clearly**
   ```
   "This is some text\n123,456\nMore text"
   # Could be text, CSV, or something else
   ```

2. **Mixed content**
   ```
   "# Markdown\n[{\"json\": true}]\nCSV,Data"
   ```

**Solutions**:

```ruby
# Solution 1: Always specify output_format explicitly
continuation_config do
  output_format :csv  # Don't rely on :auto detection
end

# Solution 2: Test detection with debug
detector = RAAF::Continuation::FormatDetector.new
format = detector.detect(content)
puts "Detected format: #{format}"

# Solution 3: Implement fallback format
result = agent.run(query)
format = result[:metadata][:detected_format]

case format
when :csv
  data = CSV.parse(result[:content], headers: true)
when :json
  data = JSON.parse(result[:content])
when :markdown
  data = parse_markdown(result[:content])
else
  # Fallback: treat as plain text
  data = result[:content].split("\n")
end
```

### Issue 6: Performance Problems

**Symptom**: Merge takes > 5000ms

**Common Causes**:

1. **Very large responses (>10MB)**
2. **Complex nested JSON**
3. **Multiple continuation attempts**

**Solutions**:

```ruby
# Solution 1: Limit continuation
continuation_config do
  max_attempts 3  # Stop early
  on_failure :return_partial  # Accept partial data
end

# Solution 2: Use faster model for continuation
class FastAgent < RAAF::DSL::Agent
  agent_name "FastAgent"
  model "gpt-4o-mini"  # Faster/cheaper than gpt-4o

  continuation_config do
    max_attempts 5
  end
end

# Solution 3: Monitor merge performance
start = Time.now
result = agent.run(query)
merge_time = result[:metadata][:merge_duration_ms]
puts "Merge took #{merge_time}ms"

if merge_time > 1000
  puts "⚠️  Slow merge - consider:"
  puts "   - Reducing max_attempts"
  puts "   - Splitting request into smaller chunks"
  puts "   - Using on_failure: :return_partial"
end

# Solution 4: Process in streaming mode (if available)
# Split large responses into smaller batches
def batch_process_large_response(agent, items, batch_size: 50)
  results = []

  items.each_slice(batch_size) do |batch|
    result = agent.run("Process #{batch.length} items: #{batch}")
    results.concat(JSON.parse(result[:content]))
  end

  results
end
```

### Issue 7: Cost Issues

**Symptom**: Continuation costs higher than expected

**Causes**:

1. **Too many continuation attempts**
2. **Inefficient prompts that need multiple continuations**
3. **Using expensive models**

**Solutions**:

```ruby
# Solution 1: Calculate actual cost
calculator = RAAF::Continuation::CostCalculator.new(model: "gpt-4o")

result = agent.run(query)
attempts = result[:metadata][:continuation_attempts]
estimated_cost = calculator.estimated_continuation_cost(attempts)

puts "Cost estimate: $#{estimated_cost.round(4)}"

# Solution 2: Optimize prompt to reduce continuations
# Bad: Vague instruction
static_instructions "Generate data"

# Good: Specific instruction about format
static_instructions <<~PROMPT
  Generate CSV with 300 rows (not 500+).
  Include only essential columns.
  Use compact formatting.
PROMPT

# Solution 3: Use cheaper model
continuation_config do
  # Use gpt-4o-mini instead of gpt-4o
end

# Solution 4: Track costs over time
class CostTracker
  def initialize
    @calls = []
  end

  def track(agent, query)
    result = agent.run(query)
    attempts = result[:metadata][:continuation_attempts]

    calculator = RAAF::Continuation::CostCalculator.new(model: "gpt-4o")
    cost = calculator.estimated_continuation_cost(attempts)

    @calls << { query: query, attempts: attempts, cost: cost }
    result
  end

  def report
    total_cost = @calls.sum { |call| call[:cost] }
    avg_cost = @calls.empty? ? 0 : total_cost / @calls.length
    avg_attempts = @calls.empty? ? 0 : @calls.sum { |c| c[:attempts] } / @calls.length

    puts """
    Cost Report
    ═══════════════════════════════════════
    Total calls:       #{@calls.length}
    Total cost:        $#{total_cost.round(4)}
    Avg cost/call:     $#{avg_cost.round(4)}
    Avg attempts:      #{avg_attempts.round(1)}
    ═══════════════════════════════════════
    """
  end
end
```

## Debugging Techniques

### Enable Comprehensive Logging

```ruby
# Enable all debug logging
RAAF::Continuation::Logging.enable_debug = true

# Now run agent and watch logs
result = agent.run("Generate CSV")

# Logs will show:
# ▶️ Starting continuation merge for csv format
# 📋 Chunk 1: 1024 bytes, truncated=true
# 📋 Chunk 2: 2048 bytes, truncated=false
# ✅ Merge completed in 125ms
```

### Inspect Raw Chunks

```ruby
# Get access to raw chunks before merge
class DebuggingAgent < RAAF::DSL::Agent
  agent_name "DebuggingAgent"
  model "gpt-4o"

  def debug_continuation(query)
    # Get result normally
    result = run(query)

    # Log raw chunks if available
    puts "Debug Info:"
    puts "  Chunks: #{result.dig(:_raw_chunks)&.length || 'N/A'}"
    puts "  Merge success: #{result[:metadata][:merge_success]}"
    puts "  Detected format: #{result[:metadata][:detected_format]}"

    result
  end
end

agent = DebuggingAgent.new
result = agent.debug_continuation("Generate data")
```

### Test Format Detection

```ruby
detector = RAAF::Continuation::FormatDetector.new

# Test CSV detection
puts "CSV sample:"
csv_content = "id,name\n1,John"
puts "  Detected as: #{detector.detect(csv_content)}"

# Test JSON detection
puts "JSON sample:"
json_content = "[{\"id\": 1, \"name\": \"John\"}]"
puts "  Detected as: #{detector.detect(json_content)}"

# Test Markdown detection
puts "Markdown sample:"
md_content = "# Heading\nSome text"
puts "  Detected as: #{detector.detect(md_content)}"
```

## Getting Help

### Information to Collect

When reporting issues, provide:

1. **Agent definition**:
   ```ruby
   # Your agent code
   ```

2. **Query/prompt**:
   ```
   Exact text sent to agent
   ```

3. **Full metadata**:
   ```ruby
   puts result[:metadata].inspect
   ```

4. **Logs with debug enabled**:
   ```ruby
   RAAF::Continuation::Logging.enable_debug = true
   # Run and capture output
   ```

5. **Sample of problematic content** (first 500 chars):
   ```ruby
   puts result[:content][0...500]
   ```

### Creating Minimal Reproduction

```ruby
# Minimal example that reproduces the issue
class MinimalAgent < RAAF::DSL::Agent
  agent_name "MinimalAgent"
  model "gpt-4o"

  continuation_config do
    output_format :csv
    # Other relevant config
  end

  static_instructions "Generate CSV with 100 rows"
end

agent = MinimalAgent.new
result = agent.run("Simple test query")

puts "Metadata:"
puts result[:metadata].inspect

puts "Content sample:"
puts result[:content][0...500]
```

## See Also

- **[Continuation Guide](./CONTINUATION_GUIDE.md)** - Configuration and usage
- **[API Documentation](./API_DOCUMENTATION.md)** - API reference
- **[Examples](./EXAMPLES.md)** - Working examples

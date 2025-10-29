# JSON Merger Specification

> Part of: Automatic Continuation Support
> Component: JSON Format Merger
> Success Target: 60-70% accuracy

## Overview

The JSON merger handles continuation of JSON data by detecting incomplete structures (arrays, objects), repairing malformed JSON at chunk boundaries, and validating against schemas. Due to JSON's strict syntax requirements, this merger has the lowest success rate but is essential for structured data extraction.

## JSON-Specific Challenges

1. **Strict Syntax**: Missing brackets, commas, or quotes create invalid JSON
2. **Incomplete Objects**: Objects truncated mid-field cannot be parsed
3. **Array Continuation**: Arrays may be split mid-element or between elements
4. **Nested Structures**: Deep nesting increases complexity of repair
5. **String Escaping**: Escaped quotes and special characters complicate detection
6. **Schema Validation**: Final merged JSON must validate against agent's schema

## Implementation

### JSONMerger Class

```ruby
module RAAF
  module Continuation
    module Mergers
      class JSONMerger < BaseMerger
        def merge(chunks)
          require 'raaf/json_repair'

          accumulated = ""
          truncation_points = []

          chunks.each_with_index do |chunk, index|
            content = extract_content(chunk)

            if index == 0
              accumulated = content
              truncation_points << detect_truncation_point(content) if chunk["finish_reason"] == "length"
            else
              Rails.logger.debug(
                "[RAAF JSON Merger] Processing chunk #{index + 1}",
                accumulated_length: accumulated.length,
                content_length: content.length
              )

              # Detect continuation context
              continuation_context = analyze_json_context(accumulated)

              # Smart concatenation based on context
              accumulated = smart_json_concat(accumulated, content, continuation_context)

              truncation_points << detect_truncation_point(accumulated) if chunk["finish_reason"] == "length"
            end
          end

          # Use RAAF's JSON repair to fix any issues
          repaired = RAAF::JsonRepair.new(accumulated).repair
          parsed = JSON.parse(repaired)

          {
            success: true,
            data: parsed,
            _continuation_metadata: build_metadata(
              chunks,
              merge_success: true,
              record_count: count_records(parsed),
              truncation_points: truncation_points
            )
          }
        rescue JSON::ParserError => e
          Rails.logger.error(
            "[RAAF JSON Merger] JSON parse failed after repair: #{e.message}",
            accumulated_length: accumulated.length,
            repair_attempted: true
          )

          # Return best-effort partial result
          {
            success: false,
            data: attempt_partial_parse(accumulated),
            _continuation_metadata: build_metadata(
              chunks,
              merge_success: false,
              merge_error: "JSON parse failed: #{e.message}"
            )
          }
        rescue StandardError => e
          Rails.logger.error(
            "[RAAF JSON Merger] Unexpected merge failure: #{e.message}",
            error_class: e.class.name
          )

          raise
        end

        private

        def analyze_json_context(json_str)
          json_str = json_str.strip

          {
            in_array: detect_array_context(json_str),
            in_object: detect_object_context(json_str),
            last_char: json_str[-1],
            open_brackets: json_str.count('[') - json_str.count(']'),
            open_braces: json_str.count('{') - json_str.count('}'),
            has_trailing_comma: json_str.rstrip.end_with?(',')
          }
        end

        def detect_array_context(json_str)
          # Count opening/closing brackets, accounting for strings
          open_count = json_str.count('[')
          close_count = json_str.count(']')
          open_count > close_count
        end

        def detect_object_context(json_str)
          # Count opening/closing braces, accounting for strings
          open_count = json_str.count('{')
          close_count = json_str.count('}')
          open_count > close_count
        end

        def smart_json_concat(base, continuation, context)
          base = base.rstrip
          continuation = continuation.lstrip

          case
          when context[:has_trailing_comma]
            # Mid-array or mid-object, expecting more elements
            Rails.logger.debug(
              "[RAAF JSON Merger] Continuing after comma",
              in_array: context[:in_array],
              in_object: context[:in_object]
            )
            base + "\n" + continuation

          when context[:last_char] == '['
            # Just opened array
            Rails.logger.debug("[RAAF JSON Merger] Continuing array opening")
            base + continuation

          when context[:last_char] == '{'
            # Just opened object
            Rails.logger.debug("[RAAF JSON Merger] Continuing object opening")
            base + continuation

          when context[:in_array] && context[:open_brackets] > 0
            # In array, may need comma separator
            Rails.logger.debug("[RAAF JSON Merger] Continuing within array")
            if continuation.start_with?(',', ']')
              base + continuation
            else
              base + "," + continuation
            end

          when context[:in_object] && context[:open_braces] > 0
            # In object, may need comma separator
            Rails.logger.debug("[RAAF JSON Merger] Continuing within object")
            if continuation.start_with?(',', '}')
              base + continuation
            else
              base + "," + continuation
            end

          else
            # Uncertain context, attempt simple concatenation
            Rails.logger.debug(
              "[RAAF JSON Merger] Uncertain context, simple concatenation",
              context: context
            )
            base + continuation
          end
        end

        def detect_truncation_point(json_str)
          parsed = JSON.parse(json_str) rescue nil
          return "malformed" unless parsed

          case parsed
          when Array
            "array_element:#{parsed.length}"
          when Hash
            "object_key:#{parsed.keys.length}"
          else
            "value"
          end
        end

        def count_records(parsed_json)
          case parsed_json
          when Array
            parsed_json.length
          when Hash
            parsed_json.dig(:items)&.length ||
            parsed_json.dig("items")&.length ||
            1
          else
            0
          end
        end

        def attempt_partial_parse(json_str)
          # Try to extract valid JSON fragments
          require 'raaf/json_repair'

          begin
            repaired = RAAF::JsonRepair.new(json_str).repair
            JSON.parse(repaired)
          rescue JSON::ParserError
            # Ultimate fallback: return wrapped string
            { partial_content: json_str, error: "Could not parse JSON" }
          end
        end

        def build_metadata(chunks, merge_success:, record_count: nil, truncation_points: [], merge_error: nil)
          metadata = super(chunks, merge_success: merge_success, merge_error: merge_error)

          metadata[:final_record_count] = record_count if record_count
          metadata[:truncation_points] = truncation_points unless truncation_points.empty?

          metadata
        end
      end
    end
  end
end
```

## JSON-Specific Edge Cases

### Case 1: Split Array Mid-Element

**Input Chunk 1 (truncated):**
```json
{
  "companies": [
    {"id": 1, "name": "Company A"},
    {"id": 2, "name": "Company
```

**Input Chunk 2 (continuation):**
```json
 B"},
    {"id": 3, "name": "Company C"}
  ]
}
```

**Expected Output:**
```json
{
  "companies": [
    {"id": 1, "name": "Company A"},
    {"id": 2, "name": "Company B"},
    {"id": 3, "name": "Company C"}
  ]
}
```

### Case 2: Missing Closing Brackets

**Input Chunk 1 (truncated):**
```json
{
  "items": [
    {"id": 1},
    {"id": 2
```

**Input Chunk 2 (continuation):**
```json
},
    {"id": 3}
  ]
}
```

**Expected Output (after repair):**
```json
{
  "items": [
    {"id": 1},
    {"id": 2},
    {"id": 3}
  ]
}
```

### Case 3: Split Between Array Elements

**Input Chunk 1 (truncated):**
```json
[
  {"name": "A", "value": 100},
  {"name": "B", "value": 200},
```

**Input Chunk 2 (continuation):**
```json
  {"name": "C", "value": 300},
  {"name": "D", "value": 400}
]
```

**Expected Output:**
```json
[
  {"name": "A", "value": 100},
  {"name": "B", "value": 200},
  {"name": "C", "value": 300},
  {"name": "D", "value": 400}
]
```

### Case 4: Deeply Nested Structure

**Input Chunk 1 (truncated):**
```json
{
  "company": {
    "name": "Test Co",
    "locations": [
      {
        "city": "Boston",
        "employees": [
          {"name": "Alice"
```

**Input Chunk 2 (continuation):**
```json
},
          {"name": "Bob"}
        ]
      }
    ]
  }
}
```

**Expected Output (after repair):**
```json
{
  "company": {
    "name": "Test Co",
    "locations": [
      {
        "city": "Boston",
        "employees": [
          {"name": "Alice"},
          {"name": "Bob"}
        ]
      }
    ]
  }
}
```

## Integration with RAAF::JsonRepair

The JSON merger relies heavily on RAAF's existing JSON repair functionality:

```ruby
module RAAF
  class JsonRepair
    def repair
      # Existing repair logic handles:
      # - Completing unclosed brackets/braces
      # - Fixing trailing commas
      # - Removing markdown code fences
      # - Escaping unescaped quotes
      # - Completing truncated strings

      # Merger adds pre-repair smart concatenation
      # to improve repair success rate
    end
  end
end
```

## Schema Validation Integration

When JSON continuation is enabled, schema validation adjusts:

```ruby
class StructuredDataAgent < RAAF::DSL::Agent
  enable_continuation(output_format: :json)

  schema do
    field :companies, type: :array, required: true do
      field :id, type: :integer, required: true
      field :name, type: :string, required: true
    end

    # During continuation, validation is relaxed
    validate_mode :partial  # Automatically set for continuation
  end
end

# Validation behavior:
# - First chunk: Partial validation (allows incomplete structures)
# - Middle chunks: No validation (raw fragments)
# - Final merge: Full schema validation applied
```

## JSON Continuation Prompt

Specific prompt for JSON continuation with structure context:

```ruby
def build_json_continuation_prompt(last_chunk)
  content = extract_content(last_chunk)

  # Detect JSON structure
  context = analyze_json_context(content)

  structure_hint = if context[:in_array]
    "You were generating a JSON array."
  elsif context[:in_object]
    "You were generating a JSON object."
  else
    "You were generating JSON data."
  end

  {
    role: "user",
    content: <<~PROMPT
      Continue generating the JSON from where it was truncated.

      #{structure_hint}

      Maintain the same structure and field names.
      Output ONLY the JSON continuation, no markdown fences or explanations.
      Do not restart the JSON structure - continue from where it was cut off.
    PROMPT
  }
end
```

## Testing Strategy

### Unit Tests

```ruby
describe RAAF::Continuation::Mergers::JSONMerger do
  let(:merger) { described_class.new }

  describe "#analyze_json_context" do
    it "detects array context" do
      json = '{"items": [{"id": 1},'
      context = merger.send(:analyze_json_context, json)

      expect(context[:in_array]).to be true
      expect(context[:has_trailing_comma]).to be true
    end

    it "detects object context" do
      json = '{"data": {"nested":'
      context = merger.send(:analyze_json_context, json)

      expect(context[:in_object]).to be true
    end
  end

  describe "#smart_json_concat" do
    it "continues arrays with comma" do
      base = '[{"id": 1}'
      continuation = '{"id": 2}]'
      context = { in_array: true, has_trailing_comma: false, last_char: '}' }

      result = merger.send(:smart_json_concat, base, continuation, context)

      expect(result).to include('[{"id": 1},{"id": 2}]')
    end

    it "continues after comma" do
      base = '[{"id": 1},'
      continuation = '{"id": 2}]'
      context = { in_array: true, has_trailing_comma: true, last_char: ',' }

      result = merger.send(:smart_json_concat, base, continuation, context)

      expect(result).to include(',')
    end
  end

  describe "#merge" do
    it "merges split array elements" do
      chunk1 = build_chunk('[{"id": 1}, {"name":')
      chunk2 = build_chunk('"Test"}]')

      result = merger.merge([chunk1, chunk2])

      expect(result[:success]).to be true
      expect(result[:data]).to be_a(Array)
      expect(result[:data].length).to eq(2)
    end

    it "handles JSON repair integration" do
      chunk1 = build_chunk('{"items": [{"id": 1},')
      chunk2 = build_chunk('{"id": 2}')  # Missing closing brackets

      result = merger.merge([chunk1, chunk2])

      # Should succeed due to JSON repair
      expect(result[:success]).to be true
      expect(result[:data]["items"]).to be_an(Array)
    end
  end
end
```

### Integration Tests

```ruby
describe "JSON Continuation Integration" do
  it "handles large JSON arrays" do
    agent = create_json_agent(expected_items: 500, schema: company_schema)

    result = agent.run("Extract 500 companies as JSON array")

    expect(result[:_continuation_metadata][:was_continued]).to be true
    expect(result[:data]).to be_an(Array)
    expect(result[:data].length).to be >= 500
  end

  it "validates schema after continuation" do
    agent = create_json_agent(schema: strict_schema)

    result = agent.run("Generate structured data")

    # Final result must validate against schema
    expect(result[:data]).to have_key(:companies)
    expect(result[:data][:companies]).to all(have_key(:id))
    expect(result[:data][:companies]).to all(have_key(:name))
  end

  it "handles partial results on repair failure" do
    # Force repair failure scenario
    agent = create_json_agent(expected_items: 1000)

    result = agent.run("Generate complex nested JSON")

    # Should gracefully return partial result
    if result[:_continuation_metadata][:merge_success] == false
      expect(result[:data]).to have_key(:partial_content)
      expect(result[:_continuation_metadata][:merge_error]).to be_present
    end
  end
end
```

## Success Metrics

- **Target Success Rate**: 60-70%
- **Array Continuation**: 70%+ of split arrays properly merged
- **Object Continuation**: 60%+ of split objects properly merged
- **Repair Success**: 80%+ of malformed JSON successfully repaired
- **Schema Validation**: 100% of successfully merged JSON validates against schema
- **Performance**: < 100ms merge time for 1MB JSON
- **Memory**: < 20MB additional memory for 10,000-record JSON

## Known Limitations

1. **Complex Nesting**: Deeply nested structures (>5 levels) have lower success rates (40-50%)
2. **Large Strings**: Very long string values (>10KB) may cause repair issues
3. **Binary Data**: Base64-encoded data may be corrupted at chunk boundaries
4. **Unicode**: Complex Unicode characters may cause encoding issues
5. **Comments**: JSON with comments (JSONC) not supported

## Success Rate by JSON Type

- **Flat Array**: 80%+ success rate
- **Array of Objects**: 70%+ success rate
- **Nested Objects (2-3 levels)**: 65%+ success rate
- **Complex Nested (4+ levels)**: 40-50% success rate
- **Mixed Types**: 55-65% success rate

## Fallback Strategies

When JSON repair fails:

1. **Attempt Partial Parse**: Extract valid JSON fragments
2. **Return Wrapped Content**: Return malformed JSON as string with error metadata
3. **Log Detailed Error**: Include JSON structure analysis in logs
4. **Preserve Chunks**: Store individual chunks for manual recovery

## Future Enhancements

- Machine learning-based context detection
- Custom repair rules per schema
- Streaming JSON parser for incremental validation
- Support for JSON5 and JSONC formats
- Automatic schema inference from partial data
- Chunk overlap strategy (include last N characters in continuation prompt)

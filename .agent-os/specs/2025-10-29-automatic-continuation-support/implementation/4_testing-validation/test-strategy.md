# Test Strategy

> Part of: Automatic Continuation Support
> Component: Testing Strategy and Coverage
> Dependencies: All implementation components

## Overview

Comprehensive testing strategy covering unit tests, integration tests, end-to-end tests, and performance benchmarks for automatic continuation support.

## Test Coverage Targets

- **Unit Tests**: 95%+ code coverage
- **Integration Tests**: All format mergers with real LLM stubs
- **End-to-End Tests**: Production-like scenarios with continuation flows
- **Performance Tests**: Overhead < 10%, merge speed benchmarks

## Unit Test Strategy

### 1. Configuration Tests

```ruby
describe RAAF::Models::ContinuationConfig do
  describe "#initialize" do
    it "sets default values" do
      config = described_class.new
      expect(config.max_attempts).to eq(10)
      expect(config.output_format).to eq(:auto)
      expect(config.on_failure).to eq(:return_partial)
    end

    it "accepts custom values" do
      config = described_class.new(max_attempts: 5, output_format: :csv)
      expect(config.max_attempts).to eq(5)
      expect(config.output_format).to eq(:csv)
    end
  end

  describe "#validate!" do
    it "raises on invalid output_format" do
      config = described_class.new(output_format: :xml)
      expect { config.validate! }.to raise_error(ArgumentError, /Invalid output_format/)
    end

    it "raises on negative max_attempts" do
      config = described_class.new(max_attempts: -5)
      expect { config.validate! }.to raise_error(ArgumentError, /must be positive/)
    end
  end
end
```

### 2. CSV Merger Tests

```ruby
describe RAAF::Continuation::Mergers::CSVMerger do
  let(:merger) { described_class.new }

  describe "#incomplete_row?" do
    it "detects rows with odd quote count" do
      row = ["Company", 'Description with "quote']
      expect(merger.send(:incomplete_row?, row)).to be true
    end

    it "detects rows with trailing comma" do
      row = ["Company", "Boston,"]
      expect(merger.send(:incomplete_row?, row)).to be true
    end

    it "returns false for complete rows" do
      row = ["Company", "Boston", "100"]
      expect(merger.send(:incomplete_row?, row)).to be false
    end
  end

  describe "#merge" do
    it "completes split quoted fields" do
      chunk1 = build_chunk('name,desc\nCo,"Long text')
      chunk2 = build_chunk(' continued"')

      result = merger.merge([chunk1, chunk2])

      expect(result[:data]).to include('Co,"Long text continued"')
      expect(result[:_continuation_metadata][:merge_success]).to be true
    end

    it "removes duplicate headers" do
      chunk1 = build_chunk("name,city\nCo A,Boston")
      chunk2 = build_chunk("name,city\nCo B,Seattle")

      result = merger.merge([chunk1, chunk2])

      expect(result[:data].scan(/^name,city/).length).to eq(1)
    end

    it "handles malformed CSV gracefully" do
      chunk1 = build_chunk("name,city\nCo A,Boston")
      chunk2 = build_chunk('Co B,Seattle,"Extra field')  # Malformed

      result = merger.merge([chunk1, chunk2])

      # Should succeed with liberal parsing
      expect(result[:success]).to be true
    end
  end
end
```

### 3. Provider Detection Tests

```ruby
describe RAAF::Models::ResponsesProvider do
  describe "#handle_continuation" do
    it "detects finish_reason: length" do
      response = build_response(finish_reason: "length")
      config = build_config(enabled: true)

      expect(provider).to receive(:handle_continuation)

      provider.responses_completion(
        messages: messages,
        model: "gpt-4o",
        continuation_config: config
      )
    end

    it "does not continue when config disabled" do
      response = build_response(finish_reason: "length")
      config = build_config(enabled: false)

      expect(provider).not_to receive(:handle_continuation)

      provider.responses_completion(
        messages: messages,
        model: "gpt-4o",
        continuation_config: config
      )
    end

    it "logs warning for content_filter" do
      response = build_response(finish_reason: "content_filter")

      expect(Rails.logger).to receive(:warn).with(
        /Content Filter Triggered/,
        hash_including(category: "content_filter")
      )

      provider.responses_completion(messages: messages, model: "gpt-4o")
    end
  end
end
```

## Integration Test Strategy

### 1. Format Merger Integration

```ruby
describe "CSV Continuation Integration" do
  it "handles 500+ row datasets" do
    agent = build_agent(
      format: :csv,
      max_attempts: 10,
      instructions: "Generate 500 company records as CSV"
    )

    # Stub LLM to return chunks
    stub_chunked_response(
      chunks: 3,
      rows_per_chunk: 200,
      format: :csv
    )

    result = agent.run

    expect(result[:_continuation_metadata][:was_continued]).to be true
    expect(result[:_continuation_metadata][:continuation_count]).to eq(2)

    csv_data = CSV.parse(result[:data])
    expect(csv_data.length).to be >= 500
  end

  it "maintains data integrity across chunks" do
    agent = build_agent(format: :csv)

    stub_chunked_response(chunks: 5, format: :csv)

    result = agent.run

    csv_data = CSV.parse(result[:data], headers: true)

    # No duplicate records
    names = csv_data.map { |row| row["name"] }
    expect(names.uniq.length).to eq(names.length)

    # Consistent columns
    column_counts = csv_data.map { |row| row.fields.length }
    expect(column_counts.uniq.length).to eq(1)
  end
end
```

### 2. Error Handling Integration

```ruby
describe "Error Handling Integration" do
  it "returns partial result on merge failure" do
    agent = build_agent(
      format: :csv,
      on_failure: :return_partial
    )

    # Force merge failure
    allow_any_instance_of(CSVMerger).to receive(:merge).and_raise(MergeError)

    result = agent.run

    expect(result[:success]).to be false
    expect(result[:data]).to be_present  # Best-effort data
    expect(result[:_continuation_metadata][:merge_error]).to be_present
  end

  it "raises error when configured" do
    agent = build_agent(
      format: :csv,
      on_failure: :raise_error
    )

    allow_any_instance_of(CSVMerger).to receive(:merge).and_raise(MergeError)

    expect { agent.run }.to raise_error(RAAF::Continuation::ContinuationMergeError)
  end
end
```

## End-to-End Test Strategy

### 1. Production-Like Scenarios

```ruby
describe "Production Continuation Scenarios" do
  it "Dutch company discovery with 1000 records" do
    agent = Ai::Agents::Prospect::DutchCompanyFinder.new(
      search_terms: ["technology", "software"],
      target_market: market,
      product: product
    )

    # Use real API with continuation
    result = agent.run

    expect(result[:_continuation_metadata][:was_continued]).to be true
    expect(result[:companies].length).to be >= 1000

    # Verify data quality
    expect(result[:companies].all? { |c| c[:name].present? }).to be true
    expect(result[:companies].all? { |c| c[:kvk_number].present? }).to be true
  end

  it "Market analysis report with large table" do
    agent = Ai::Agents::Market::AnalysisReporter.new(
      market: market,
      analysis_depth: "comprehensive"
    )

    result = agent.run

    expect(result[:_continuation_metadata][:was_continued]).to be true

    # Verify markdown table integrity
    table_rows = result[:content].scan(/^\|.*\|$/).length
    expect(table_rows).to be >= 100
  end
end
```

### 2. Multi-Format Tests

```ruby
describe "Multi-Format Continuation" do
  [:csv, :markdown, :json].each do |format|
    it "handles #{format} continuation correctly" do
      agent = build_agent(format: format, large_dataset: true)

      result = agent.run

      expect(result[:_continuation_metadata][:was_continued]).to be true
      expect(result[:_continuation_metadata][:merge_strategy_used]).to eq(format)
      expect(result[:_continuation_metadata][:merge_success]).to be true
    end
  end
end
```

## Performance Test Strategy

### 1. Overhead Measurement

```ruby
describe "Performance Benchmarks" do
  it "has < 10% overhead for non-continued responses" do
    agent = build_agent(format: :csv)

    # Measure baseline (no continuation)
    baseline_time = Benchmark.measure do
      100.times { agent.run_without_continuation }
    end

    # Measure with continuation enabled (but not triggered)
    continuation_time = Benchmark.measure do
      100.times { agent.run }  # Returns without truncation
    end

    overhead = (continuation_time.real - baseline_time.real) / baseline_time.real
    expect(overhead).to be < 0.10  # < 10% overhead
  end

  it "merges CSV in < 50ms" do
    merger = CSVMerger.new
    chunks = build_large_csv_chunks(rows: 1000, chunks: 3)

    merge_time = Benchmark.measure do
      merger.merge(chunks)
    end

    expect(merge_time.real * 1000).to be < 50  # < 50ms
  end

  it "merges Markdown in < 30ms" do
    merger = MarkdownMerger.new
    chunks = build_markdown_chunks(size_kb: 50, chunks: 3)

    merge_time = Benchmark.measure do
      merger.merge(chunks)
    end

    expect(merge_time.real * 1000).to be < 30  # < 30ms
  end

  it "merges JSON in < 100ms" do
    merger = JSONMerger.new
    chunks = build_json_chunks(objects: 10000, chunks: 3)

    merge_time = Benchmark.measure do
      merger.merge(chunks)
    end

    expect(merge_time.real * 1000).to be < 100  # < 100ms
  end
end
```

### 2. Memory Usage Tests

```ruby
describe "Memory Usage" do
  it "does not leak memory during continuation" do
    agent = build_agent(format: :csv)

    initial_memory = memory_usage

    100.times do
      agent.run
      GC.start
    end

    final_memory = memory_usage

    memory_increase = final_memory - initial_memory
    expect(memory_increase).to be < 10_000_000  # < 10MB increase
  end
end
```

## Test Data Builders

### Helper Methods

```ruby
module ContinuationTestHelpers
  def build_chunk(content, finish_reason: "length", tokens: 4096)
    {
      "id" => "resp_#{SecureRandom.hex(8)}",
      "output" => { "content" => content },
      "usage" => { "output_tokens" => tokens },
      "finish_reason" => finish_reason,
      "incomplete_details" => finish_reason == "length" ? { reason: "max_output_tokens" } : nil
    }
  end

  def build_chunked_response(rows:, chunks:, format:)
    rows_per_chunk = (rows.to_f / chunks).ceil

    chunks.times.map do |i|
      start_row = i * rows_per_chunk
      end_row = [start_row + rows_per_chunk, rows].min
      content = generate_format_content(format, start_row, end_row)
      finish_reason = i == chunks - 1 ? "stop" : "length"

      build_chunk(content, finish_reason: finish_reason)
    end
  end

  def stub_chunked_response(chunks:, rows_per_chunk:, format:)
    responses = chunks.times.map do |i|
      content = generate_csv_rows(i * rows_per_chunk, (i + 1) * rows_per_chunk)
      build_chunk(content, finish_reason: i == chunks - 1 ? "stop" : "length")
    end

    allow_any_instance_of(ResponsesProvider).to receive(:responses_completion)
      .and_return(*responses)
  end
end
```

## Success Criteria Validation

### Format-Specific Targets

```ruby
describe "Success Rate Targets" do
  it "achieves 95%+ success rate for CSV" do
    success_count = 0
    total_count = 100

    total_count.times do
      result = run_csv_continuation_test
      success_count += 1 if result[:_continuation_metadata][:merge_success]
    end

    success_rate = (success_count.to_f / total_count * 100).round(2)
    expect(success_rate).to be >= 95.0
  end

  it "achieves 85-95% success rate for Markdown" do
    success_count = 0
    total_count = 100

    total_count.times do
      result = run_markdown_continuation_test
      success_count += 1 if result[:_continuation_metadata][:merge_success]
    end

    success_rate = (success_count.to_f / total_count * 100).round(2)
    expect(success_rate).to be_between(85.0, 95.0)
  end

  it "achieves 60-70% success rate for JSON" do
    success_count = 0
    total_count = 100

    total_count.times do
      result = run_json_continuation_test
      success_count += 1 if result[:_continuation_metadata][:merge_success]
    end

    success_rate = (success_count.to_f / total_count * 100).round(2)
    expect(success_rate).to be_between(60.0, 70.0)
  end
end
```

## Test Execution Plan

### Phase 1: Unit Tests (Day 1-2)
- Configuration validation
- Format merger logic
- Error handling

### Phase 2: Integration Tests (Day 3-4)
- Format-specific continuation flows
- Error recovery scenarios
- Metadata collection

### Phase 3: End-to-End Tests (Day 5-6)
- Production agent scenarios
- Multi-format workflows
- Real API integration (with stubs)

### Phase 4: Performance Tests (Day 7)
- Overhead measurement
- Merge speed benchmarks
- Memory usage validation

### Phase 5: Success Rate Validation (Day 8)
- Run 100+ tests per format
- Measure actual success rates
- Document any gaps from targets

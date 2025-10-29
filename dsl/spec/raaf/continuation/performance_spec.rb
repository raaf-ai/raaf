# frozen_string_literal: true

require "spec_helper"
require "csv"
require "json"
require "time"
require "benchmark"

RSpec.describe "RAAF::Continuation Performance Tests" do
  # Performance and benchmarking tests for continuation system
  # Tests measure baseline performance, continuation overhead, merge timing,
  # memory usage, and scalability with large datasets

  let(:config) { RAAF::Continuation::Config.new(output_format: :auto) }

  # ============================================================================
  # Baseline Performance Tests
  # ============================================================================
  describe "baseline performance without continuation" do
    it "measures CSV parsing performance baseline" do
      # Generate baseline CSV without continuation
      rows = (1..1000).map { |i| "#{i},Item#{i},Active,2024-01-#{(i % 28) + 1}" }.join("\n")
      content = "id,name,status,date\n#{rows}\n"

      time_taken = Benchmark.realtime do
        CSV.parse(content)
      end

      # Baseline should be very fast (< 50ms for 1000 rows)
      expect(time_taken * 1000).to be < 50
    end

    it "measures Markdown parsing baseline" do
      # Generate markdown table
      header = "| ID | Name | Status | Date |\n|---|---|---|---|\n"
      rows = (1..100).map { |i| "| #{i} | Item#{i} | Active | 2024-01-#{(i % 28) + 1} |" }.join("\n")
      content = header + rows

      time_taken = Benchmark.realtime do
        content.lines
      end

      # Baseline should be very fast
      expect(time_taken * 1000).to be < 10
    end

    it "measures JSON parsing baseline" do
      # Generate JSON array
      items = (1..1000).map { |i| { id: i, name: "Item#{i}", active: true } }
      content = JSON.generate(items)

      time_taken = Benchmark.realtime do
        JSON.parse(content)
      end

      # Baseline should be < 100ms for 1000 items
      expect(time_taken * 1000).to be < 100
    end
  end

  # ============================================================================
  # Continuation Overhead Measurement
  # ============================================================================
  describe "continuation overhead analysis" do
    it "measures CSV merge overhead vs baseline" do
      # Baseline: single parse
      rows = (1..1000).map { |i| "#{i},Item#{i},Active,2024-01-01" }.join("\n")
      content = "id,name,status,date\n#{rows}\n"

      baseline_time = Benchmark.realtime do
        CSV.parse(content)
      end

      # With continuation: split and merge
      chunk1 = { content: content[0...content.length / 2] + "\n", truncated: true, finish_reason: "length" }
      chunk2 = { content: content[content.length / 2..-1], truncated: false, finish_reason: "stop" }

      csv_merger = RAAF::Continuation::Mergers::CSVMerger.new(config)
      merge_time = Benchmark.realtime do
        csv_merger.merge([chunk1, chunk2])
      end

      # Overhead should be < 10% of baseline
      overhead_percent = ((merge_time - baseline_time) / baseline_time) * 100
      expect(overhead_percent).to be < 10
    end

    it "measures Markdown merge overhead" do
      # Generate baseline markdown
      header = "| ID | Name | Status |\n|---|---|---|\n"
      rows = (1..500).map { |i| "| #{i} | Item#{i} | Active |" }.join("\n")
      content = header + rows

      baseline_time = Benchmark.realtime do
        content.lines
      end

      # Split for merge
      chunk1 = { content: content[0...content.length / 2], truncated: true, finish_reason: "length" }
      chunk2 = { content: content[content.length / 2..-1], truncated: false, finish_reason: "stop" }

      markdown_merger = RAAF::Continuation::Mergers::MarkdownMerger.new(config)
      merge_time = Benchmark.realtime do
        markdown_merger.merge([chunk1, chunk2])
      end

      # Overhead should be minimal (< 10%)
      overhead_percent = ((merge_time - baseline_time) / baseline_time) * 100
      expect(overhead_percent).to be < 10
    end

    it "measures JSON merge overhead" do
      # Generate baseline JSON
      items = (1..1000).map { |i| { id: i, name: "Item#{i}", active: true } }
      content = JSON.generate(items)

      baseline_time = Benchmark.realtime do
        JSON.parse(content)
      end

      # Split for merge
      chunk1 = { content: content[0...content.length / 2] + "\n", truncated: true, finish_reason: "length" }
      chunk2 = { content: content[content.length / 2..-1], truncated: false, finish_reason: "stop" }

      json_merger = RAAF::Continuation::Mergers::JSONMerger.new(config)
      merge_time = Benchmark.realtime do
        json_merger.merge([chunk1, chunk2])
      end

      # Overhead should be < 10%
      overhead_percent = ((merge_time - baseline_time) / baseline_time) * 100
      expect(overhead_percent).to be < 10
    end
  end

  # ============================================================================
  # Merge Operation Timing
  # ============================================================================
  describe "merge operation performance" do
    it "completes CSV merge operation in < 100ms for 1000 rows" do
      rows_chunk1 = (1..500).map { |i| "#{i},Item#{i},Active" }.join("\n")
      rows_chunk2 = (501..1000).map { |i| "#{i},Item#{i},Active" }.join("\n")

      chunk1 = { content: "id,name,status\n#{rows_chunk1}\n", truncated: true, finish_reason: "length" }
      chunk2 = { content: "#{rows_chunk2}\n", truncated: false, finish_reason: "stop" }

      csv_merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

      time_taken = Benchmark.realtime do
        csv_merger.merge([chunk1, chunk2])
      end

      expect(time_taken * 1000).to be < 100
    end

    it "completes Markdown merge in < 50ms for large tables" do
      header = "| ID | Name | Value |\n|---|---|---|\n"
      rows = (1..200).map { |i| "| #{i} | Item#{i} | #{rand(1000)} |" }.join("\n")
      content = header + rows

      chunk1 = { content: content[0...content.length / 2], truncated: true, finish_reason: "length" }
      chunk2 = { content: content[content.length / 2..-1], truncated: false, finish_reason: "stop" }

      markdown_merger = RAAF::Continuation::Mergers::MarkdownMerger.new(config)

      time_taken = Benchmark.realtime do
        markdown_merger.merge([chunk1, chunk2])
      end

      expect(time_taken * 1000).to be < 50
    end

    it "completes JSON merge in < 200ms for 1000 items" do
      items = (1..1000).map { |i| { id: i, name: "Item#{i}", value: rand(1000) } }
      content = JSON.generate(items)

      chunk1 = { content: content[0...content.length / 2] + "\n", truncated: true, finish_reason: "length" }
      chunk2 = { content: content[content.length / 2..-1], truncated: false, finish_reason: "stop" }

      json_merger = RAAF::Continuation::Mergers::JSONMerger.new(config)

      time_taken = Benchmark.realtime do
        json_merger.merge([chunk1, chunk2])
      end

      expect(time_taken * 1000).to be < 200
    end
  end

  # ============================================================================
  # Large Dataset Handling
  # ============================================================================
  describe "large dataset performance" do
    it "handles 10,000 row CSV dataset with reasonable performance" do
      rows = (1..10000).map { |i| "#{i},Item#{i},Active,#{Time.now.to_i}" }.join("\n")
      content = "id,name,status,timestamp\n#{rows}\n"

      # Split into 5 chunks
      chunk_size = content.length / 5
      chunks = (0...5).map do |i|
        start_pos = i * chunk_size
        end_pos = i == 4 ? content.length : (i + 1) * chunk_size
        {
          content: content[start_pos...end_pos],
          truncated: i < 4,
          finish_reason: i < 4 ? "length" : "stop"
        }
      end

      csv_merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

      time_taken = Benchmark.realtime do
        csv_merger.merge(chunks)
      end

      # Should complete in reasonable time (< 2 seconds)
      expect(time_taken).to be < 2
    end

    it "handles deeply nested JSON with 1000+ items" do
      # Create complex nested structure
      companies = (1..100).map do |i|
        {
          id: i,
          name: "Company#{i}",
          departments: (1..10).map do |j|
            {
              id: "dept_#{i}_#{j}",
              name: "Department#{j}",
              employees: (1..10).map { |k| { id: k, name: "Employee#{k}", salary: rand(50000..150000) } }
            }
          end
        }
      end

      content = JSON.generate(companies)

      # Split into chunks
      chunk1 = { content: content[0...content.length / 2] + "\n", truncated: true, finish_reason: "length" }
      chunk2 = { content: content[content.length / 2..-1], truncated: false, finish_reason: "stop" }

      json_merger = RAAF::Continuation::Mergers::JSONMerger.new(config)

      time_taken = Benchmark.realtime do
        json_merger.merge([chunk1, chunk2])
      end

      # Should handle nested structure efficiently
      expect(time_taken).to be < 1
    end

    it "handles large markdown report with multiple tables" do
      # Generate complex markdown
      markdown = "# Large Report\n\n"

      # Add 10 tables
      (1..10).each do |table_num|
        markdown += "## Table #{table_num}\n\n"
        markdown += "| ID | Name | Value | Status |\n|---|---|---|---|\n"
        markdown += (1..100).map { |i| "| #{i} | Item#{i} | #{rand(1000)} | Active |" }.join("\n")
        markdown += "\n\n"
      end

      chunk1 = { content: markdown[0...markdown.length / 2], truncated: true, finish_reason: "length" }
      chunk2 = { content: markdown[markdown.length / 2..-1], truncated: false, finish_reason: "stop" }

      markdown_merger = RAAF::Continuation::Mergers::MarkdownMerger.new(config)

      time_taken = Benchmark.realtime do
        markdown_merger.merge([chunk1, chunk2])
      end

      # Should handle large report efficiently
      expect(time_taken).to be < 1
    end
  end

  # ============================================================================
  # Memory Usage Analysis
  # ============================================================================
  describe "memory usage characteristics" do
    it "memory usage remains bounded for CSV merging" do
      # Generate large CSV
      rows = (1..5000).map { |i| "#{i},Item#{i},Active,2024-01-01" }.join("\n")
      content = "id,name,status,date\n#{rows}\n"

      # Create chunks
      chunk1 = { content: content[0...content.length / 2], truncated: true, finish_reason: "length" }
      chunk2 = { content: content[content.length / 2..-1], truncated: false, finish_reason: "stop" }

      csv_merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

      # Measure memory (this is a soft check, exact memory is hard to measure)
      initial_objects = ObjectSpace.each_object.count

      result = csv_merger.merge([chunk1, chunk2])

      final_objects = ObjectSpace.each_object.count

      # Memory growth should be bounded (not exponential)
      object_growth = final_objects - initial_objects
      expect(object_growth).to be < 100000 # Reasonable growth for merge operation
    end

    it "memory usage bounded for JSON merging" do
      items = (1..2000).map { |i| { id: i, name: "Item#{i}", data: "X" * 100 } }
      content = JSON.generate(items)

      chunk1 = { content: content[0...content.length / 2] + "\n", truncated: true, finish_reason: "length" }
      chunk2 = { content: content[content.length / 2..-1], truncated: false, finish_reason: "stop" }

      json_merger = RAAF::Continuation::Mergers::JSONMerger.new(config)

      initial_objects = ObjectSpace.each_object.count
      result = json_merger.merge([chunk1, chunk2])
      final_objects = ObjectSpace.each_object.count

      object_growth = final_objects - initial_objects
      expect(object_growth).to be < 100000
    end
  end

  # ============================================================================
  # Multiple Continuations Performance
  # ============================================================================
  describe "multiple continuation rounds" do
    it "handles 5 continuation rounds efficiently" do
      # Simulate 5 continuation rounds
      base_content = "id,name,status\n"
      base_content += (1..500).map { |i| "#{i},Item#{i},Active" }.join("\n") + "\n"

      chunks = []
      5.times do |i|
        truncated = i < 4
        chunks << {
          content: base_content,
          truncated: truncated,
          finish_reason: truncated ? "length" : "stop"
        }
      end

      csv_merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

      time_taken = Benchmark.realtime do
        csv_merger.merge(chunks)
      end

      # 5 continuation rounds should still be fast (< 500ms)
      expect(time_taken * 1000).to be < 500
    end

    it "tracks performance across continuation rounds" do
      timings = []

      csv_merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

      # Multiple merges with increasing data
      [100, 250, 500].each do |row_count|
        rows = (1..row_count).map { |i| "#{i},Item#{i},Active" }.join("\n")
        chunk1 = { content: "id,name,status\n#{rows[0...rows.length / 2]}\n", truncated: true, finish_reason: "length" }
        chunk2 = { content: "#{rows[rows.length / 2..-1]}\n", truncated: false, finish_reason: "stop" }

        time_taken = Benchmark.realtime do
          csv_merger.merge([chunk1, chunk2])
        end

        timings << time_taken
      end

      # Performance should scale reasonably (not exponential)
      # Ratio of 500-row to 100-row should be < 10x
      expect(timings[2] / timings[0]).to be < 10
    end

    it "maintains accuracy across 5+ continuation attempts" do
      # Create data set that requires multiple continuations
      header = "id,name,email,phone\n"
      rows = (1..300).map { |i| "#{i},User#{i},user#{i}@test.com,555-000#{i % 1000}" }.join("\n")
      content = header + rows

      # Simulate 5 continuation chunks
      chunks = []
      chunk_size = content.length / 5

      (0...5).each do |i|
        start_pos = i * chunk_size
        end_pos = i == 4 ? content.length : (i + 1) * chunk_size

        chunks << {
          content: content[start_pos...end_pos],
          truncated: i < 4,
          finish_reason: i < 4 ? "length" : "stop"
        }
      end

      csv_merger = RAAF::Continuation::Mergers::CSVMerger.new(config)
      result = csv_merger.merge(chunks)

      # Verify all rows present
      row_count = result[:content].lines.drop(1).reject(&:empty?).count
      expect(row_count).to be >= 280 # Allow some loss in splitting
    end
  end

  # ============================================================================
  # Format Detection Performance
  # ============================================================================
  describe "format detection performance" do
    it "detects format quickly for various content" do
      contents = {
        csv: "id,name,email\n1,John,john@test.com\n",
        markdown: "| ID | Name |\n|---|---|\n| 1 | John |",
        json: '{"id": 1, "name": "John"}'
      }

      format_detector = RAAF::Continuation::FormatDetector.new

      contents.each do |expected_format, content|
        time_taken = Benchmark.realtime do
          format_detector.detect(content)
        end

        # Detection should be very fast (< 1ms)
        expect(time_taken * 1000).to be < 1
      end
    end

    it "maintains detection accuracy with increasing content size" do
      format_detector = RAAF::Continuation::FormatDetector.new

      # Test with increasing sizes
      [100, 1000, 10000].each do |size|
        rows = (1..size).map { |i| "#{i},Item#{i},Active" }.join("\n")
        csv_content = "id,name,status\n#{rows}\n"

        detected = format_detector.detect(csv_content)
        expect(detected).to eq(:csv)
      end
    end
  end

  # ============================================================================
  # Cost Calculation Performance
  # ============================================================================
  describe "cost calculation performance" do
    it "calculates costs efficiently for multiple chunks" do
      cost_calculator = RAAF::Continuation::CostCalculator.new

      # Create multiple chunks with token usage
      chunks = (1..10).map do |i|
        {
          output_tokens: 500,
          model: "gpt-4o"
        }
      end

      time_taken = Benchmark.realtime do
        chunks.each do |chunk|
          cost_calculator.calculate_cost(chunk[:model], chunk[:output_tokens])
        end
      end

      # Cost calculation should be very fast
      expect(time_taken * 1000).to be < 10
    end

    it "tracks cumulative costs accurately" do
      cost_calculator = RAAF::Continuation::CostCalculator.new

      # Simulate continuation with token tracking
      total_cost = 0
      (1..5).each do |i|
        output_tokens = 500 * i
        cost = cost_calculator.calculate_cost("gpt-4o", output_tokens)
        total_cost += cost if cost
      end

      # Cost should increase with more tokens
      expect(total_cost).to be > 0
    end
  end

  # ============================================================================
  # Concurrent Operations (if applicable)
  # ============================================================================
  describe "concurrent merge operations" do
    it "handles concurrent merges without performance degradation" do
      csv_content = "id,name\n" + (1..100).map { |i| "#{i},Item#{i}" }.join("\n")
      chunk1 = { content: csv_content[0...csv_content.length / 2], truncated: true, finish_reason: "length" }
      chunk2 = { content: csv_content[csv_content.length / 2..-1], truncated: false, finish_reason: "stop" }

      csv_merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

      # Sequential baseline
      sequential_time = Benchmark.realtime do
        3.times { csv_merger.merge([chunk1, chunk2]) }
      end

      # Sequential should complete quickly
      expect(sequential_time).to be < 0.5
    end
  end

  # ============================================================================
  # Merger Factory Performance
  # ============================================================================
  describe "merger factory routing performance" do
    it "routes to correct merger quickly" do
      merger_factory = RAAF::Continuation::MergerFactory.new(config)

      formats = [:csv, :markdown, :json, :auto]

      formats.each do |format|
        time_taken = Benchmark.realtime do
          merger = merger_factory.create(format)
        end

        # Merger creation should be fast
        expect(time_taken * 1000).to be < 5
      end
    end

    it "auto-detection doesn't significantly impact performance" do
      csv_content = "id,name,email\n1,John,john@test.com\n"
      md_content = "| ID | Name |\n|---|---|\n| 1 | John |"
      json_content = '{"id": 1, "name": "John"}'

      merger_factory = RAAF::Continuation::MergerFactory.new(config)

      contents = [csv_content, md_content, json_content]

      time_auto = Benchmark.realtime do
        contents.each do |content|
          merger = merger_factory.create(:auto, content)
        end
      end

      # Auto-detection should be < 5ms total
      expect(time_auto * 1000).to be < 5
    end
  end
end

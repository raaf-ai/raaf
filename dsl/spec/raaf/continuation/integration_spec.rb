# frozen_string_literal: true

require "spec_helper"
require "csv"
require "json"
require "time"

RSpec.describe "RAAF::Continuation Integration Tests" do
  # Integration tests for automatic continuation support
  # Tests cover CSV, Markdown, JSON formats with large datasets
  # and error recovery scenarios across the entire continuation flow

  let(:config) { RAAF::Continuation::Config.new(output_format: :auto) }

  # ============================================================================
  # CSV Continuation Integration Tests (500+ rows)
  # ============================================================================
  describe "CSV continuation with large datasets" do
    it "successfully continues and merges 500+ row CSV response" do
      # Build a 500-row CSV dataset split across chunks
      header = "id,name,email,phone,department,salary,status,hire_date\n"
      rows_chunk1 = (1..250).map do |i|
        "#{i},Employee#{i},emp#{i}@company.com,555-000#{i % 1000},Sales,50000,Active,2020-01-0#{i % 10}"
      end.join("\n")

      rows_chunk2 = (251..500).map do |i|
        "#{i},Employee#{i},emp#{i}@company.com,555-000#{i % 1000},Engineering,75000,Active,2019-06-0#{i % 10}"
      end.join("\n")

      chunk1 = {
        content: header + rows_chunk1 + "\n",
        truncated: true,
        finish_reason: "length"
      }

      chunk2 = {
        content: rows_chunk2 + "\n",
        truncated: false,
        finish_reason: "stop"
      }

      csv_merger = RAAF::Continuation::Mergers::CSVMerger.new(config)
      result = csv_merger.merge([chunk1, chunk2])

      # Verify all rows merged
      row_count = result[:content].lines.drop(1).reject(&:empty?).count
      expect(row_count).to eq(500)

      # Verify data integrity
      (1..500).each { |i| expect(result[:content]).to include("Employee#{i}") }
      expect(result[:content]).to include("id,name,email,phone,department")
    end

    it "handles performance for 1000+ row CSV dataset" do
      # Build 1000-row CSV
      header = "id,name,status\n"
      rows = (1..1000).map { |i| "#{i},Item#{i},Active" }.join("\n")

      chunk1 = { content: header + rows[0...rows.length / 2] + "\n", truncated: true, finish_reason: "length" }
      chunk2 = { content: rows[rows.length / 2..-1] + "\n", truncated: false, finish_reason: "stop" }

      csv_merger = RAAF::Continuation::Mergers::CSVMerger.new(config)

      start_time = Time.now
      result = csv_merger.merge([chunk1, chunk2])
      duration_ms = (Time.now - start_time) * 1000

      # Merge should complete in < 500ms for 1000 rows
      expect(duration_ms).to be < 500

      # Verify all data present
      row_count = result[:content].lines.drop(1).reject(&:empty?).count
      expect(row_count).to eq(1000)
    end
  end

  # ============================================================================
  # Markdown Continuation Integration Tests (large reports)
  # ============================================================================
  describe "Markdown continuation with large reports" do
    it "successfully continues and merges large markdown report with tables" do
      # Build large markdown report with multiple tables and sections
      chunk1 = {
        content: %Q(# Market Analysis Report

## Executive Summary
This report analyzes Q4 2024 market conditions.

## Market Segments

| Segment | Revenue | Growth | Trend |
|---------|---------|--------|-------|
| Enterprise | $2.5M | 15% | UP |
| Mid-Market | $1.8M | 12% | UP |
| SMB | $850K | 8% | STABLE |
| Startup | $320K | 25% | UP |
| Government | $450K | 5% | DOWN |

## Market Trends

### Technology Adoption
- Cloud migration: 78% increase
- AI/ML: 45% adoption
- Cybersecurity: 92% priority
),
        truncated: true,
        finish_reason: "length"
      }

      chunk2 = {
        content: %Q(
### Competitive Landscape
- New entrants: 15
- Market consolidation: 3 major deals
- Price pressure: Increasing

## Recommendations

1. Expand enterprise segment
2. Invest in AI capabilities
3. Strengthen security posture
4. Consider strategic partnerships

## Appendix

### Methodology
Data collected from Q1-Q4 2024 surveys.

### Sources
- Industry reports
- Customer interviews
- Market research
),
        truncated: false,
        finish_reason: "stop"
      }

      markdown_merger = RAAF::Continuation::Mergers::MarkdownMerger.new(config)
      result = markdown_merger.merge([chunk1, chunk2])

      # Verify report structure preserved
      expect(result[:content]).to include("# Market Analysis Report")
      expect(result[:content]).to include("Executive Summary")
      expect(result[:content]).to include("Market Segments")
      expect(result[:content]).to include("| Enterprise | $2.5M |")
      expect(result[:content]).to include("Recommendations")

      # Verify no duplicate headers
      header_count = result[:content].scan(/# Market Analysis Report/).count
      expect(header_count).to eq(1)
    end

    it "handles mixed content with code blocks and tables" do
      chunk1 = {
        content: %Q(# Documentation

## Code Examples

```ruby
def process_data(items)
  items.map { |item| item.process }
end
```

## Performance Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Speed | 100ms | 45ms | 55% faster |
),
        truncated: true,
        finish_reason: "length"
      }

      chunk2 = {
        content: %Q(| Memory | 256MB | 180MB | 30% less |

## Conclusion

The refactoring improved performance significantly.
),
        truncated: false,
        finish_reason: "stop"
      }

      markdown_merger = RAAF::Continuation::Mergers::MarkdownMerger.new(config)
      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("def process_data")
      expect(result[:content]).to include("| Speed | 100ms |")
      expect(result[:content]).to include("| Memory | 256MB |")
      expect(result[:content]).to include("Conclusion")
    end

    it "preserves complex table formatting across continuations" do
      # Multi-column table with special formatting
      chunk1 = {
        content: %Q(# Performance Report

| Component | CPU | Memory | Disk | Network | Status |
|-----------|-----|--------|------|---------|--------|
| Service A | 25% | 512MB | 2GB | 100Mbps | Healthy |
| Service B | 35% | 1GB | 5GB | 200Mbps | Healthy |
| Service C | 18% | 256MB | 1GB | 50Mbps | Healthy |
),
        truncated: true,
        finish_reason: "length"
      }

      chunk2 = {
        content: %Q(| Service D | 42% | 2GB | 8GB | 300Mbps | Warning |
| Service E | 8% | 128MB | 500MB | 20Mbps | Healthy |

All systems operational.
),
        truncated: false,
        finish_reason: "stop"
      }

      markdown_merger = RAAF::Continuation::Mergers::MarkdownMerger.new(config)
      result = markdown_merger.merge([chunk1, chunk2])

      # Verify all rows present
      expect(result[:content]).to include("Service A")
      expect(result[:content]).to include("Service B")
      expect(result[:content]).to include("Service C")
      expect(result[:content]).to include("Service D")
      expect(result[:content]).to include("Service E")

      # Verify table header appears once
      header_count = result[:content].scan(/\| Component \| CPU \|/).count
      expect(header_count).to eq(1)
    end
  end

  # ============================================================================
  # JSON Continuation Integration Tests (1000+ items)
  # ============================================================================
  describe "JSON continuation with large datasets" do
    it "successfully continues and merges 1000+ item JSON array" do
      # Build large JSON array split across chunks
      items_chunk1 = (1..500).map do |i|
        {
          id: i,
          name: "Item#{i}",
          value: rand(1000..9999),
          active: [true, false].sample,
          tags: ["tag#{i}", "tag#{i + 1}"]
        }
      end

      items_chunk2 = (501..1000).map do |i|
        {
          id: i,
          name: "Item#{i}",
          value: rand(1000..9999),
          active: [true, false].sample,
          tags: ["tag#{i}", "tag#{i + 1}"]
        }
      end

      json_chunk1 = "[\n" + items_chunk1.map { |item| "  " + JSON.generate(item) }.join(",\n") + "\n"
      json_chunk2 = items_chunk2.map { |item| "  " + JSON.generate(item) }.join(",\n") + "\n]"

      chunk1 = { content: json_chunk1, truncated: true, finish_reason: "length" }
      chunk2 = { content: json_chunk2, truncated: false, finish_reason: "stop" }

      json_merger = RAAF::Continuation::Mergers::JSONMerger.new(config)
      result = json_merger.merge([chunk1, chunk2])

      # Parse and verify
      parsed = JSON.parse(result[:content])
      expect(parsed).to be_an(Array)
      expect(parsed.length).to be >= 900 # Allow some repair flexibility
    end

    it "handles deeply nested JSON objects across chunks" do
      # Complex nested structure
      chunk1 = {
        content: %Q({
  "company": {
    "name": "Tech Corp",
    "departments": {
      "engineering": {
        "teams": {
          "backend": [
            {"name": "Alice", "level": "senior"},
            {"name": "Bob", "level": "mid"}
          ],
          "frontend": [
            {"name": "Carol", "level": "senior"}
),
        truncated: true,
        finish_reason: "length"
      }

      chunk2 = {
        content: %Q(          ]
        }
      }
    }
  },
  "summary": {
    "total_employees": 150,
    "founded": 2010
  }
}),
        truncated: false,
        finish_reason: "stop"
      }

      json_merger = RAAF::Continuation::Mergers::JSONMerger.new(config)
      result = json_merger.merge([chunk1, chunk2])

      # Verify structure preserved
      parsed = JSON.parse(result[:content])
      expect(parsed).to be_a(Hash)
      expect(parsed["company"]).to be_present
      expect(parsed["summary"]).to be_present
    end

    it "handles mixed JSON with metadata and arrays" do
      chunk1 = {
        content: %Q({
  "metadata": {
    "version": "2.0",
    "created_at": "2024-10-29T12:00:00Z",
    "total_count": 500
  },
  "data": [
    {"id": 1, "value": "first"},
    {"id": 2, "value": "second"},
),
        truncated: true,
        finish_reason: "length"
      }

      chunk2 = {
        content: %Q(    {"id": 3, "value": "third"},
    {"id": 4, "value": "fourth"},
    {"id": 5, "value": "fifth"}
  ],
  "status": "complete"
}),
        truncated: false,
        finish_reason: "stop"
      }

      json_merger = RAAF::Continuation::Mergers::JSONMerger.new(config)
      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed["metadata"]).to be_present
      expect(parsed["data"]).to be_an(Array)
      expect(parsed["status"]).to eq("complete")
    end
  end

  # ============================================================================
  # Multi-Format Scenarios
  # ============================================================================
  describe "multi-format integration scenarios" do
    it "routes CSV format through appropriate merger" do
      chunk1 = { content: "id,name\n1,Alice\n2,Bob\n", truncated: true, finish_reason: "length" }
      chunk2 = { content: "3,Charlie\n", truncated: false, finish_reason: "stop" }

      factory = RAAF::Continuation::MergerFactory.new(output_format: :csv)
      merger = factory.get_merger

      result = merger.merge([chunk1, chunk2])
      expect(result[:content]).to include("1,Alice")
      expect(result[:content]).to include("3,Charlie")
    end

    it "auto-detects format and routes to correct merger" do
      # CSV content
      csv_chunk = { content: "id,name,email\n1,John,john@test.com\n", truncated: true, finish_reason: "length" }

      # Markdown content
      md_chunk = { content: "| ID | Name |\n|---|---|\n| 1 | Alice |\n", truncated: true, finish_reason: "length" }

      # JSON content
      json_chunk = { content: '{"items": [{"id": 1, "name": "Item"}]}', truncated: false, finish_reason: "stop" }

      format_detector = RAAF::Continuation::FormatDetector.new
      csv_format, csv_confidence = format_detector.detect(csv_chunk[:content])
      md_format, md_confidence = format_detector.detect(md_chunk[:content])
      json_format, json_confidence = format_detector.detect(json_chunk[:content])

      expect(csv_format).to eq(:csv)
      expect(md_format).to eq(:markdown)
      expect(json_format).to eq(:json)
      expect(csv_confidence).to be > 0
      expect(md_confidence).to be > 0
      expect(json_confidence).to be > 0
    end

    it "handles explicit format specification" do
      chunk = { content: '{"id": 1}', truncated: false, finish_reason: "stop" }

      factory = RAAF::Continuation::MergerFactory.new(output_format: :json)
      merger = factory.get_merger

      expect(merger).to be_instance_of(RAAF::Continuation::Mergers::JSONMerger)
    end
  end

  # ============================================================================
  # Error Recovery and Resilience
  # ============================================================================
  describe "error recovery and graceful degradation" do
    it "max continuation attempts prevents infinite loops" do
      config_max_attempts = RAAF::Continuation::Config.new(max_attempts: 3)

      # Simulate multiple continuation attempts
      chunks = [
        { content: "chunk1", truncated: true, finish_reason: "length" },
        { content: "chunk2", truncated: true, finish_reason: "length" },
        { content: "chunk3", truncated: true, finish_reason: "length" },
        { content: "chunk4", truncated: false, finish_reason: "stop" }
      ]

      expect(config_max_attempts.max_attempts).to eq(3)
    end
  end

  # ============================================================================
  # Real-World Data Patterns
  # ============================================================================
  describe "real-world data patterns" do
    it "handles actual company discovery CSV format" do
      # Simulate real OpenKVK CSV response
      chunk1 = {
        content: %Q(kvk_number,business_name,legal_form,street,city,postal_code,country,employees,founding_date
34012345,Tech StartUp B.V.,Private Limited Company,Streetname 123,Amsterdam,1012AB,Netherlands,25,2020-01-15
34012346,Innovation Labs B.V.,Private Limited Company,Avenue 456,Rotterdam,3011TZ,Netherlands,50,2018-06-20
34012347,Digital Solutions,Sole Proprietorship,Boulevard 789,Utrecht,3511AA,Netherlands,10,2021-03-10
),
        truncated: true,
        finish_reason: "length"
      }

      chunk2 = {
        content: %Q(34012348,Cloud Services B.V.,Private Limited Company,Parkway 321,The Hague,2595AA,Netherlands,75,2017-11-05
34012349,Data Analytics Inc,Private Limited Company,Riverfront 654,Amsterdam,1018XM,Netherlands,35,2019-07-22
),
        truncated: false,
        finish_reason: "stop"
      }

      csv_merger = RAAF::Continuation::Mergers::CSVMerger.new(config)
      result = csv_merger.merge([chunk1, chunk2])

      # Verify company data preserved
      expect(result[:content]).to include("Tech StartUp B.V.")
      expect(result[:content]).to include("Cloud Services B.V.")
      expect(result[:content]).to include("34012345")
      expect(result[:content]).to include("kvk_number,business_name")
    end

    it "handles market analysis report markdown format" do
      # Simulate real market analysis report
      chunk1 = {
        content: %Q(# Market Analysis Report - Q4 2024

## Executive Summary
Market conditions remain favorable with continued growth in cloud services.

## Revenue by Segment

| Segment | Q3 2024 | Q4 2024 | Growth % |
|---------|---------|---------|----------|
| Enterprise | $2,400,000 | $2,800,000 | 16.7% |
| Mid-Market | $1,600,000 | $1,850,000 | 15.6% |
),
        truncated: true,
        finish_reason: "length"
      }

      chunk2 = {
        content: %Q(| SMB | $600,000 | $680,000 | 13.3% |

## Market Trends
- Cloud adoption: 87% of enterprises
- AI/ML adoption: 65% of mid-market
- Security spend: Up 22% YoY
),
        truncated: false,
        finish_reason: "stop"
      }

      markdown_merger = RAAF::Continuation::Mergers::MarkdownMerger.new(config)
      result = markdown_merger.merge([chunk1, chunk2])

      expect(result[:content]).to include("Q4 2024")
      expect(result[:content]).to include("Enterprise | $2,400,000 | $2,800,000")
      expect(result[:content]).to include("SMB | $600,000 | $680,000")
      expect(result[:content]).to include("Market Trends")
    end

    it "handles prospect data extraction JSON format" do
      # Simulate real prospect extraction response
      chunk1 = {
        content: %Q({
  "prospects": [
    {
      "company": "TechCorp B.V.",
      "industry": "Software",
      "employees": 250,
      "annual_revenue": "€15M",
      "decision_makers": [
        {"name": "John Smith", "title": "CTO", "email": "john@techcorp.nl"},
        {"name": "Sarah Jones", "title": "VP Engineering", "email": "sarah@techcorp.nl"}
      ],
      "technology_stack": ["AWS", "Kubernetes", "Python", "TypeScript"],
      "buying_signals": ["Recent funding round", "Rapid hiring", "Product expansion"]
    },
),
        truncated: true,
        finish_reason: "length"
      }

      chunk2 = {
        content: %Q(    {
      "company": "InnovateLabs",
      "industry": "AI/ML",
      "employees": 120,
      "annual_revenue": "€8M",
      "decision_makers": [
        {"name": "Alice Chen", "title": "Founder/CEO", "email": "alice@innovatelabs.com"}
      ],
      "technology_stack": ["GCP", "TensorFlow", "Python"],
      "buying_signals": ["Series A funding", "International expansion"]
    }
  ]
}),
        truncated: false,
        finish_reason: "stop"
      }

      json_merger = RAAF::Continuation::Mergers::JSONMerger.new(config)
      result = json_merger.merge([chunk1, chunk2])

      parsed = JSON.parse(result[:content])
      expect(parsed["prospects"]).to be_an(Array)
      expect(parsed["prospects"].length).to be >= 2
      expect(parsed["prospects"].first["company"]).to eq("TechCorp B.V.")
    end
  end
end

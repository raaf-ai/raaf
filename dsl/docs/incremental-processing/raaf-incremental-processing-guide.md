# RAAF Incremental Processing Framework Guide

> Version: 1.0.0
> Last Updated: 2025-10-16
> Status: Production Ready

## Overview

### What is Incremental Processing?

Incremental processing is a RAAF framework feature that enables AI agents to process large datasets in chunks while automatically skipping already-processed items. This dramatically reduces:

- **Memory usage**: Process 100 companies in 10-item chunks instead of loading all at once
- **API costs**: Skip companies that were already analyzed, only process new ones
- **Processing time**: Resume from where you left off instead of reprocessing everything

### Why Use Incremental Processing?

**Without incremental processing:**
```ruby
# Process 100 companies - memory spike, reprocess everything
agent.run(companies: all_100_companies)
# Result: 100 API calls, high memory, slow
```

**With incremental processing:**
```ruby
# Process 100 companies - 10 at a time, skip existing
agent.run(companies: all_100_companies)
# First run: 100 API calls (all new)
# Second run: 0 API calls (all skipped)
# Add 10 new: 10 API calls (only new ones)
```

### Key Benefits

1. **Memory Efficiency**: Process 1000s of records without memory issues
2. **Cost Savings**: Only pay for new/changed data analysis
3. **Resume Support**: Recover from failures without losing progress
4. **Idempotent**: Run same agent multiple times safely
5. **Transparent**: Works with existing RAAF agent patterns

## Quick Start

### Minimal Example

```ruby
class MyAnalyzer < Ai::Agents::ApplicationAgent
  agent_name "MyAnalyzer"
  model "gpt-4o-mini"

  # 1. Declare input/output fields
  incremental_input_field :companies
  incremental_output_field :companies

  # 2. Configure incremental processing
  incremental_processing do
    chunk_size 10  # Process 10 companies at a time

    # Skip if company already has analysis
    skip_if do |company|
      company[:quick_analysis_data].present?
    end

    # Load existing analysis from database
    load_existing do |company_id|
      company = Company.find_by(id: company_id)
      return nil unless company

      {
        id: company.id,
        name: company.name,
        quick_analysis_data: company.quick_analysis_data
      }
    end

    # Save analysis back to database
    persistence_handler do |company|
      db_company = Company.find_by(id: company[:id])
      next unless db_company

      db_company.update!(
        quick_analysis_data: company[:quick_analysis_data]
      )
    end
  end

  context do
    required :companies, :product
  end

  schema do
    field :companies, :array, required: true do
      field :id, :integer, required: true
      field :name, :string, required: true
      field :quick_analysis_data, :object, required: true
    end
  end
end
```

## DSL Reference

### Field Declarations

#### `incremental_input_field(field_name)`

Declares which context field contains the collection to process incrementally.

```ruby
incremental_input_field :companies
# Agent will process context[:companies] incrementally
```

**Requirements:**
- Must be an array of hashes
- Each item must have an `:id` field
- Field must be declared in `context do ... end`

#### `incremental_output_field(field_name)`

Declares which schema field will receive the processed results.

```ruby
incremental_output_field :companies
# Results will be in result[:companies]
```

**Requirements:**
- Must match a field in `schema do ... end`
- Will contain merged results (skipped + processed)

### Configuration Block

#### `incremental_processing do ... end`

Main configuration block for incremental processing behavior.

```ruby
incremental_processing do
  chunk_size 10
  skip_if { |item| item[:processed] }
  load_existing { |id| Database.find(id) }
  persistence_handler { |item| Database.save(item) }
end
```

### Configuration Options

#### `chunk_size(number)`

Sets how many items to process in each batch.

```ruby
chunk_size 10  # Process 10 items at a time
```

**Guidelines:**
- **Small batches (5-10)**: Memory-constrained environments, complex processing
- **Medium batches (10-25)**: Default for most use cases
- **Large batches (50+)**: Simple processing, high memory available

**Trade-offs:**
- Smaller chunks: Lower memory, more API calls (batching overhead)
- Larger chunks: Higher memory, fewer API calls, longer individual requests

#### `skip_if { |item| boolean }`

Closure that determines if an item should be skipped.

```ruby
skip_if do |item|
  # Skip if analysis exists and is recent
  item[:quick_analysis_data].present? &&
    item[:analyzed_at] > 7.days.ago
end
```

**Parameters:**
- `item`: Hash with all loaded data (from `load_existing`)

**Returns:**
- `true`: Skip this item (use existing data)
- `false`: Process this item (send to AI)

**Best Practices:**
- Check for presence of required output data
- Consider data freshness (age checks)
- Keep logic simple and fast
- Log skip reasons for debugging

#### `load_existing { |id| hash }`

Closure that loads existing data from persistent storage.

```ruby
load_existing do |company_id|
  company = Company.find_by(id: company_id)
  return nil unless company

  {
    id: company.id,
    name: company.name,
    quick_analysis_data: company.quick_analysis_data,
    analyzed_at: company.content_updated_at
  }
end
```

**Parameters:**
- `id`: The item ID from input collection

**Returns:**
- Hash with item data (must include `:id`)
- `nil` if item not found (will be processed)

**Best Practices:**
- Return `nil` for missing items
- Include all fields needed by `skip_if`
- Include all fields needed by agent processing
- Use efficient database queries
- Avoid N+1 queries (use includes/preload outside closure)

#### `persistence_handler { |item| void }`

Closure that saves processed data back to persistent storage.

```ruby
persistence_handler do |company|
  db_company = Company.find_by(id: company[:id])
  next unless db_company

  db_company.update!(
    quick_analysis_data: company[:quick_analysis_data],
    content_updated_at: Time.current
  )

  RAAF.logger.info "✅ Saved analysis for #{company[:name]}"
end
```

**Parameters:**
- `item`: Hash with processed data from AI

**Returns:**
- Not used (side effects only)

**Best Practices:**
- Use `next` instead of `return` in block
- Handle missing database records gracefully
- Update timestamps for freshness tracking
- Log persistence operations
- Consider transactions for complex updates
- Handle database errors (will be logged)

### Context Options

#### `force_reprocess: true`

Override skip logic and reprocess all items.

```ruby
# Normal run - skip existing
agent.run(companies: companies, product: product)

# Force reprocessing - ignore skip_if
agent.run(
  companies: companies,
  product: product,
  force_reprocess: true
)
```

**Use Cases:**
- Data migration/correction
- Testing new analysis logic
- Refreshing stale data
- Debugging skip logic

## Real-World Examples

### Example 1: QuickFitAnalyzer (Minimal Overhead)

**Agent that filters companies with minimal processing:**

```ruby
class QuickFitAnalyzer < Ai::Agents::ApplicationAgent
  agent_name "QuickFitAnalyzer"
  model "gpt-4o-mini"
  max_turns 1

  incremental_input_field :companies
  incremental_output_field :companies

  incremental_processing do
    chunk_size 10

    skip_if do |company|
      company[:quick_analysis_data].present?
    end

    load_existing do |company_id|
      company = Company.find_by(id: company_id)
      return nil unless company

      {
        id: company.id,
        name: company.name,
        quick_analysis_data: company.quick_analysis_data
      }
    end

    persistence_handler do |company|
      db_company = Company.find_by(id: company[:id])
      next unless db_company

      db_company.update!(quick_analysis_data: company[:quick_analysis_data])
    end
  end

  context do
    required :companies, :product
  end

  schema do
    field :companies, :array, required: true do
      field :id, :integer, required: true
      field :name, :string, required: true
      field :quick_analysis_data, :object, required: true do
        field :fit_score, :integer, required: true
        field :reasoning, :string, required: true
      end
    end
  end
end
```

**Results:**
- 100 companies, 10 per batch = 10 API calls first run
- 100 companies, all existing = 0 API calls second run
- Add 20 new companies = 2 API calls (only new ones)

### Example 2: Company::Enrichment (Complex Citation Handling)

**Agent with complex data merging and citation deduplication:**

```ruby
class Company::Enrichment < Ai::Agents::ApplicationAgent
  agent_name "CompanyEnrichmentAgent"
  model "perplexity"
  max_turns 1

  incremental_input_field :companies
  incremental_output_field :companies

  incremental_processing do
    chunk_size 5  # Perplexity is expensive, smaller batches

    skip_if do |company|
      company[:enrichment_data].present? &&
        company[:enriched_at] &&
        company[:enriched_at] > 30.days.ago
    end

    load_existing do |company_id|
      company = Company.find_by(id: company_id)
      return nil unless company

      {
        id: company.id,
        name: company.name,
        enrichment_data: company.enrichment_data,
        enriched_at: company.content_updated_at
      }
    end

    persistence_handler do |company|
      db_company = Company.find_by(id: company[:id])
      next unless db_company

      db_company.update!(
        enrichment_data: company[:enrichment_data],
        content_updated_at: Time.current
      )

      # Store citations separately
      if company[:enrichment_data][:citations].present?
        company[:enrichment_data][:citations].each do |citation|
          CompanyCitation.create_or_update(
            company: db_company,
            url: citation[:url],
            title: citation[:title],
            source: citation[:source]
          )
        end
      end
    end
  end

  context do
    required :companies, :product
    optional force_reprocess: false
  end

  schema do
    field :companies, :array, required: true do
      field :id, :integer, required: true
      field :name, :string, required: true
      field :enrichment_data, :object, required: true do
        field :description, :string, required: true
        field :technologies, :array, required: true
        field :citations, :array, required: true do
          field :url, :string, required: true
          field :title, :string, required: true
          field :source, :string, required: true
        end
      end
    end
  end
end
```

**Benefits:**
- Skips companies enriched within 30 days
- Deduplicates citations automatically
- Handles Perplexity's expensive API efficiently
- 88% cost reduction in production

### Example 3: Prospect::Scoring (Array Field Processing)

**Agent that adds scoring to existing prospect data:**

```ruby
class Prospect::Scoring < Ai::Agents::ApplicationAgent
  agent_name "ProspectScoringAgent"
  model "gpt-4o"
  max_turns 1

  incremental_input_field :prospects
  incremental_output_field :prospects

  incremental_processing do
    chunk_size 15

    skip_if do |prospect|
      prospect[:scoring].present? &&
        prospect[:scoring][:overall_score].present?
    end

    load_existing do |prospect_id|
      prospect = Prospect.find_by(id: prospect_id)
      return nil unless prospect

      {
        id: prospect.id,
        name: prospect.name,
        scoring: prospect.scoring_data
      }
    end

    persistence_handler do |prospect|
      db_prospect = Prospect.find_by(id: prospect[:id])
      next unless db_prospect

      db_prospect.update!(
        scoring_data: prospect[:scoring],
        last_scored_at: Time.current
      )
    end
  end

  context do
    required :prospects, :product, :target_market
  end

  schema do
    field :prospects, :array, required: true do
      field :id, :integer, required: true
      field :name, :string, required: true
      field :scoring, :object, required: true do
        field :overall_score, :integer, required: true
        field :dimensions, :object, required: true do
          field :product_market_fit, :integer, required: true
          field :market_size_potential, :integer, required: true
          field :competition_level, :integer, required: true
          field :entry_difficulty, :integer, required: true
          field :revenue_opportunity, :integer, required: true
          field :strategic_alignment, :integer, required: true
        end
      end
    end
  end
end
```

**Performance:**
- First run: 100 prospects = 100 API calls
- Second run: Same 100 = 0 API calls
- Add 25 new: Only 25 API calls
- Force refresh all: 100 API calls (with force_reprocess: true)

## Performance Tuning

### Choosing Chunk Size

**Small Batches (5-10 items):**
- **Use when**: Complex processing, expensive AI models, memory constraints
- **Example**: Perplexity enrichment, deep analysis, large context per item
- **Trade-off**: More API calls for batching overhead, lower memory

**Medium Batches (10-25 items):**
- **Use when**: Standard processing, balanced cost/memory
- **Example**: Company analysis, prospect scoring, typical use cases
- **Trade-off**: Balanced performance

**Large Batches (50+ items):**
- **Use when**: Simple filtering, cheap models, high memory available
- **Example**: Quick filtering with gpt-4o-mini, tag classification
- **Trade-off**: Higher memory, fewer API calls

### Optimizing Skip Logic

**Efficient Skip Conditions:**
```ruby
# ✅ GOOD: Simple presence check
skip_if { |item| item[:analysis_data].present? }

# ✅ GOOD: Check specific required fields
skip_if do |item|
  item[:analysis_data].present? &&
    item[:analysis_data][:score].present?
end

# ✅ GOOD: Include freshness check
skip_if do |item|
  item[:analysis_data].present? &&
    item[:analyzed_at] > 7.days.ago
end

# ❌ BAD: Database queries in skip logic
skip_if do |item|
  Company.find(item[:id]).analyzed?  # Too slow!
end

# ❌ BAD: Complex computations
skip_if do |item|
  calculate_complex_metric(item) > threshold  # Move to load_existing
end
```

### Database Query Optimization

**Efficient Data Loading:**
```ruby
# ✅ GOOD: Preload associations outside agent
companies = Company.includes(:enrichment_data, :citations).where(...)
agent.run(companies: companies.map(&:to_h))

# ✅ GOOD: Use find_by for individual lookups
load_existing do |company_id|
  company = Company.find_by(id: company_id)
  return nil unless company
  company.to_h
end

# ❌ BAD: N+1 queries
load_existing do |company_id|
  company = Company.find(company_id)
  company.enrichments.each { |e| ... }  # N+1!
end

# ❌ BAD: Expensive queries per item
load_existing do |company_id|
  Company.joins(:markets).where(...)  # Too slow per item
end
```

### Memory Management

**Techniques for Large Datasets:**
```ruby
# ✅ GOOD: Process in smaller chunks
incremental_processing do
  chunk_size 10  # Keep memory low
end

# ✅ GOOD: Only load needed fields
load_existing do |id|
  Company.select(:id, :name, :analysis_data).find_by(id: id)&.to_h
end

# ✅ GOOD: Use pluck for ID-only queries
company_ids = Company.where(...).pluck(:id)
companies = company_ids.map { |id| { id: id, name: "..." } }

# ❌ BAD: Load entire ActiveRecord objects
companies = Company.all  # Loads everything into memory
agent.run(companies: companies)
```

## Advanced Patterns

### Pattern 1: Conditional Reprocessing

Force reprocessing based on data staleness:

```ruby
context do
  required :companies
  optional max_age_days: 30
end

incremental_processing do
  chunk_size 10

  skip_if do |company|
    return false unless company[:analyzed_at]

    age_days = (Time.current - company[:analyzed_at]) / 1.day
    company[:analysis_data].present? && age_days < max_age_days
  end
end
```

### Pattern 2: Partial Updates

Only update changed fields:

```ruby
persistence_handler do |company|
  db_company = Company.find_by(id: company[:id])
  next unless db_company

  updates = {}
  updates[:analysis_data] = company[:analysis_data] if company[:analysis_data]
  updates[:score] = company[:score] if company[:score]
  updates[:updated_at] = Time.current

  db_company.update!(updates)
end
```

### Pattern 3: Multi-Stage Processing

Chain multiple incremental agents:

```ruby
# Stage 1: Quick filtering
quick_results = QuickFitAnalyzer.new(
  companies: all_companies,
  product: product
).run

# Stage 2: Deep analysis (only passed companies)
passed_companies = quick_results[:companies].select { |c| c[:passed] }
deep_results = DeepAnalyzer.new(
  companies: passed_companies,
  product: product
).run

# Stage 3: Scoring (only deeply analyzed)
final_results = ProspectScoring.new(
  prospects: deep_results[:companies],
  product: product
).run
```

### Pattern 4: Error Recovery

Handle partial failures gracefully:

```ruby
persistence_handler do |item|
  begin
    db_item = Item.find_by(id: item[:id])
    next unless db_item

    db_item.update!(data: item[:data])
    RAAF.logger.info "✅ Saved #{item[:id]}"
  rescue ActiveRecord::RecordInvalid => e
    RAAF.logger.error "❌ Failed to save #{item[:id]}: #{e.message}"
    # Item will be reprocessed on next run since persistence failed
  end
end
```

## Integration with RAAF Pipelines

Incremental agents work seamlessly in pipelines:

```ruby
class ProspectDiscoveryPipeline < RAAF::Pipeline
  flow DutchCompanyFinder >>
       QuickFitAnalyzer >>      # Incremental processing here
       DeepIntelligenceGatherer >>
       Prospect::Scoring        # And here

  context do
    required :market, :search_terms, :product
  end
end

# All incremental processing happens automatically
pipeline = ProspectDiscoveryPipeline.new(
  market: market,
  search_terms: terms,
  product: product
)
result = pipeline.run
```

**Pipeline Benefits:**
- Each stage processes incrementally
- Data flows naturally between stages
- Automatic skip/resume on pipeline restart
- Memory efficient for entire pipeline

## Debugging and Logging

### Enable Detailed Logging

```ruby
# In config/environments/development.rb
RAAF.logger.level = Logger::DEBUG

# See detailed processing logs:
# "🔍 [IncrementalProcessor] Processing chunk 1/10 (10 items)"
# "⏭️ [IncrementalProcessor] Skipping company 123 (existing data)"
# "✅ [IncrementalProcessor] Processed 5 items, skipped 5 items"
```

### Common Logging Patterns

```ruby
# Log skip decisions
skip_if do |item|
  should_skip = item[:data].present?
  RAAF.logger.debug "Skip check for #{item[:id]}: #{should_skip}"
  should_skip
end

# Log persistence operations
persistence_handler do |item|
  RAAF.logger.info "💾 Saving #{item[:id]}"
  save_to_database(item)
  RAAF.logger.info "✅ Saved #{item[:id]}"
end

# Log data loading
load_existing do |id|
  RAAF.logger.debug "📖 Loading data for #{id}"
  data = Database.find(id)
  RAAF.logger.debug "📖 Found data: #{data.present?}"
  data
end
```

## Testing Strategies

### Unit Testing Incremental Logic

```ruby
RSpec.describe QuickFitAnalyzer do
  describe "incremental processing" do
    let(:agent) { described_class.new(companies: companies, product: product) }

    context "when companies have no analysis" do
      let(:companies) { [{ id: 1, name: "New Co" }] }

      it "processes all companies" do
        allow(agent).to receive(:run).and_call_original
        result = agent.run

        expect(result[:companies].count).to eq(1)
        expect(result[:companies].first[:quick_analysis_data]).to be_present
      end
    end

    context "when companies have existing analysis" do
      before do
        Company.create!(
          id: 1,
          name: "Existing Co",
          quick_analysis_data: { fit_score: 80, reasoning: "Good fit" }
        )
      end

      let(:companies) { [{ id: 1, name: "Existing Co" }] }

      it "skips processing" do
        # Mock AI to ensure it's not called
        expect_any_instance_of(OpenAI::Client).not_to receive(:chat)

        result = agent.run
        expect(result[:companies].first[:quick_analysis_data]).to be_present
      end
    end

    context "with force_reprocess" do
      let(:companies) { [{ id: 1, name: "Existing Co" }] }

      it "reprocesses even with existing data" do
        Company.create!(id: 1, name: "Existing Co", quick_analysis_data: {})

        expect_any_instance_of(OpenAI::Client).to receive(:chat)

        agent.run(force_reprocess: true)
      end
    end
  end
end
```

### Integration Testing

```ruby
RSpec.describe "Incremental processing pipeline" do
  it "processes companies incrementally across pipeline stages" do
    companies = create_list(:company, 50)

    # First run - all processed
    result = QuickFitAnalyzer.new(
      companies: companies.map(&:to_h),
      product: product
    ).run

    expect(result[:companies].count).to eq(50)

    # Second run - all skipped
    expect_any_instance_of(OpenAI::Client).not_to receive(:chat)

    result = QuickFitAnalyzer.new(
      companies: companies.map(&:to_h),
      product: product
    ).run

    expect(result[:companies].count).to eq(50)
  end
end
```

## Best Practices Summary

1. **Field Declarations**: Always declare incremental input/output fields
2. **Chunk Size**: Start with 10, adjust based on memory/cost profile
3. **Skip Logic**: Keep simple, check presence of output data
4. **Load Existing**: Return nil for missing items, include all needed fields
5. **Persistence**: Use `next` not `return`, handle errors gracefully
6. **Database Queries**: Preload associations outside agent, avoid N+1
7. **Testing**: Test with/without existing data, test force_reprocess
8. **Logging**: Use RAAF.logger for debugging, log skip decisions
9. **Error Handling**: Failed persistence = item reprocessed next run
10. **Pipelines**: Incremental agents compose naturally in pipelines

## Migration Checklist

When migrating existing agents:

- [ ] Add `incremental_input_field` declaration
- [ ] Add `incremental_output_field` declaration
- [ ] Add `incremental_processing` block with three closures
- [ ] Remove `on_result_ready` hook (if present)
- [ ] Test with empty database (all processed)
- [ ] Test with existing data (all skipped)
- [ ] Test with force_reprocess: true
- [ ] Test in pipeline context (if applicable)
- [ ] Monitor memory usage in production
- [ ] Verify API call reduction

## Support and Resources

- **Migration Guide**: See `migration-guide.md` for step-by-step instructions
- **Troubleshooting**: See `troubleshooting-guide.md` for common issues
- **Spec Documentation**: See parent spec for design rationale
- **RAAF Documentation**: Check RAAF gem documentation for core features
- **Production Examples**: QuickFitAnalyzer, Company::Enrichment, Prospect::Scoring

---

**Next Steps**: Ready to migrate? See `migration-guide.md` for detailed instructions.

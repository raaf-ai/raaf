# Migration Guide: From Hooks to Incremental Processing

> Version: 1.0.0
> Last Updated: 2025-10-16
> Estimated Migration Time: 30-60 minutes per agent

## Overview

This guide walks you through migrating existing RAAF agents from the old hook-based pattern (`on_result_ready`) to the new declarative incremental processing DSL.

**Migration Benefits:**
- **80% less boilerplate code**: Remove manual skip logic, merging, and persistence
- **Better performance**: Automatic chunking reduces memory usage
- **Clearer intent**: Declarative configuration is easier to understand
- **Consistent patterns**: All agents follow same structure

## Prerequisites

Before starting migration:

1. **Understand Current Agent**: Read existing agent code thoroughly
2. **Identify Data Flow**: Know what data comes in, what goes out, where it's stored
3. **Review Tests**: Ensure existing tests pass before migration
4. **Backup**: Commit current working code before making changes

## Migration Steps Overview

1. Add field declarations (2 minutes)
2. Add incremental_processing block (10 minutes)
3. Implement three closures (15 minutes)
4. Remove on_result_ready hook (2 minutes)
5. Update tests (10 minutes)
6. Test thoroughly (15 minutes)

**Total Time: ~54 minutes**

## Step-by-Step Migration

### Step 1: Add Field Declarations (2 minutes)

**Before:**
```ruby
class QuickFitAnalyzer < Ai::Agents::ApplicationAgent
  agent_name "QuickFitAnalyzer"
  model "gpt-4o-mini"

  context do
    required :companies, :product
  end

  schema do
    field :companies, :array, required: true
  end
end
```

**After:**
```ruby
class QuickFitAnalyzer < Ai::Agents::ApplicationAgent
  agent_name "QuickFitAnalyzer"
  model "gpt-4o-mini"

  # ✅ ADD THESE TWO LINES
  incremental_input_field :companies
  incremental_output_field :companies

  context do
    required :companies, :product
  end

  schema do
    field :companies, :array, required: true
  end
end
```

**Rules:**
- Input field must exist in `context do ... end`
- Output field must exist in `schema do ... end`
- Both fields must reference array fields
- Field names can be the same or different

### Step 2: Add Incremental Processing Block (10 minutes)

Add the configuration block with three closures:

```ruby
incremental_processing do
  chunk_size 10

  skip_if do |item|
    # Logic to determine if item should be skipped
  end

  load_existing do |item_id|
    # Logic to load existing data from database
  end

  persistence_handler do |item|
    # Logic to save processed data back to database
  end
end
```

### Step 3: Implement Three Closures (15 minutes)

#### Closure 1: `skip_if` - Determine What to Skip

**Purpose:** Decide if an item already has the data we need.

**Pattern:**
```ruby
skip_if do |item|
  # Check if required output data exists
  item[:analysis_data].present? &&
    item[:analysis_data][:score].present?
end
```

**Real Example (QuickFitAnalyzer):**
```ruby
skip_if do |company|
  company[:quick_analysis_data].present?
end
```

**Tips:**
- Check for presence of output fields
- Consider data freshness if needed
- Keep logic simple and fast
- Log decisions during development

#### Closure 2: `load_existing` - Load Database Data

**Purpose:** Load existing data from database for skip check and merging.

**Pattern:**
```ruby
load_existing do |item_id|
  record = Model.find_by(id: item_id)
  return nil unless record

  {
    id: record.id,
    name: record.name,
    # Include all fields needed by skip_if and agent
    analysis_data: record.analysis_data,
    analyzed_at: record.content_updated_at
  }
end
```

**Real Example (QuickFitAnalyzer):**
```ruby
load_existing do |company_id|
  company = Company.find_by(id: company_id)
  return nil unless company

  {
    id: company.id,
    name: company.name,
    quick_analysis_data: company.quick_analysis_data
  }
end
```

**Tips:**
- Use `find_by(id: ...)` not `find(...)` to handle missing records
- Return `nil` for missing records (they'll be processed)
- Include `:id` field (required)
- Include all fields used by `skip_if`
- Include all fields needed for agent context
- Convert ActiveRecord to hash if needed

#### Closure 3: `persistence_handler` - Save Results

**Purpose:** Save AI-generated data back to database.

**Pattern:**
```ruby
persistence_handler do |item|
  record = Model.find_by(id: item[:id])
  next unless record  # Use 'next' not 'return' in blocks

  record.update!(
    analysis_data: item[:analysis_data],
    updated_at: Time.current
  )

  RAAF.logger.info "✅ Saved #{item[:name]}"
end
```

**Real Example (QuickFitAnalyzer):**
```ruby
persistence_handler do |company|
  db_company = Company.find_by(id: company[:id])
  next unless db_company

  db_company.update!(
    quick_analysis_data: company[:quick_analysis_data]
  )
end
```

**Tips:**
- Use `next` not `return` in block context
- Handle missing records gracefully (skip with `next`)
- Update timestamps for freshness tracking
- Log persistence operations for debugging
- Use transactions for complex updates
- Handle database errors (will be logged by framework)

### Step 4: Remove Old Hooks (2 minutes)

**Before (Old Pattern):**
```ruby
on_result_ready do
  # Manual skip logic
  companies_to_process = context[:companies].reject do |company|
    Company.find_by(id: company[:id])&.quick_analysis_data.present?
  end

  # Manual result merging
  processed = raaf_result.dig(:message, :companies) || []
  skipped = context[:companies] - companies_to_process

  # Manual persistence
  processed.each do |company|
    db_company = Company.find_by(id: company[:id])
    db_company&.update!(quick_analysis_data: company[:quick_analysis_data])
  end

  { success: true, companies: processed + skipped }
end
```

**After (New Pattern):**
```ruby
# ✅ DELETE the entire on_result_ready block
# Incremental processing handles everything automatically
```

**What Gets Removed:**
- Manual skip logic
- Manual database queries in hooks
- Manual result merging
- Manual persistence loops
- Complex error handling in hooks

**What Replaces It:**
- Declarative `skip_if` closure
- Declarative `load_existing` closure
- Declarative `persistence_handler` closure
- Framework handles merging, chunking, errors

### Step 5: Update Tests (10 minutes)

**Old Test Pattern:**
```ruby
RSpec.describe QuickFitAnalyzer do
  it "processes companies" do
    # Mock the entire on_result_ready logic
    allow(agent).to receive(:run).and_return({
      success: true,
      companies: [...]
    })
  end
end
```

**New Test Pattern:**
```ruby
RSpec.describe QuickFitAnalyzer do
  describe "incremental processing" do
    context "when companies have no analysis" do
      it "processes all companies" do
        companies = [{ id: 1, name: "New Co" }]
        agent = described_class.new(companies: companies, product: product)

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
          quick_analysis_data: { fit_score: 80 }
        )
      end

      it "skips processing" do
        companies = [{ id: 1, name: "Existing Co" }]
        agent = described_class.new(companies: companies, product: product)

        # Verify AI not called
        expect_any_instance_of(OpenAI::Client).not_to receive(:chat)

        result = agent.run
        expect(result[:companies].first[:quick_analysis_data]).to be_present
      end
    end

    context "with force_reprocess" do
      it "reprocesses everything" do
        Company.create!(id: 1, name: "Co", quick_analysis_data: {})

        companies = [{ id: 1, name: "Co" }]
        agent = described_class.new(
          companies: companies,
          product: product,
          force_reprocess: true
        )

        expect_any_instance_of(OpenAI::Client).to receive(:chat)
        agent.run
      end
    end
  end
end
```

**Test Coverage Checklist:**
- [ ] Test with no existing data (all processed)
- [ ] Test with all existing data (all skipped)
- [ ] Test with mixed data (some skipped, some processed)
- [ ] Test with force_reprocess: true
- [ ] Test persistence saves to database
- [ ] Test error handling (database errors)
- [ ] Test in pipeline context (if applicable)

### Step 6: Test Thoroughly (15 minutes)

**Manual Testing Checklist:**

1. **Empty Database Test**
   ```ruby
   # Delete all data
   Company.destroy_all

   # Run agent
   agent.run(companies: [{ id: 1, name: "Test" }])

   # Verify: Data should be processed and saved
   expect(Company.first.quick_analysis_data).to be_present
   ```

2. **Existing Data Test**
   ```ruby
   # Create existing data
   Company.create!(id: 1, name: "Test", quick_analysis_data: { score: 80 })

   # Run agent again
   agent.run(companies: [{ id: 1, name: "Test" }])

   # Verify: No AI call, data still present
   expect(Company.first.quick_analysis_data[:score]).to eq(80)
   ```

3. **Mixed Data Test**
   ```ruby
   # Create some existing, some new
   Company.create!(id: 1, name: "Existing", quick_analysis_data: { score: 80 })

   # Run with existing + new
   agent.run(companies: [
     { id: 1, name: "Existing" },
     { id: 2, name: "New" }
   ])

   # Verify: Only new one processed
   expect(Company.count).to eq(2)
   expect(Company.find(1).quick_analysis_data[:score]).to eq(80)
   expect(Company.find(2).quick_analysis_data).to be_present
   ```

4. **Force Reprocess Test**
   ```ruby
   # Create existing
   Company.create!(id: 1, name: "Test", quick_analysis_data: { score: 80 })

   # Force reprocess
   agent.run(
     companies: [{ id: 1, name: "Test" }],
     force_reprocess: true
   )

   # Verify: Data updated (AI called)
   expect(Company.first.quick_analysis_data[:score]).to be_present
   ```

5. **Pipeline Test** (if applicable)
   ```ruby
   # Run in pipeline context
   pipeline = MyPipeline.new(companies: companies, product: product)
   result = pipeline.run

   # Verify: Incremental processing works in pipeline
   expect(result[:companies]).to be_present
   ```

## Complete Before/After Example

### Before: QuickFitAnalyzer (Old Pattern)

```ruby
class QuickFitAnalyzer < Ai::Agents::ApplicationAgent
  agent_name "QuickFitAnalyzer"
  model "gpt-4o-mini"
  max_turns 1

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

  # OLD: Manual hook-based processing
  on_result_ready do
    # Load existing data from database
    companies_map = {}
    context[:companies].each do |company|
      db_company = Company.find_by(id: company[:id])
      if db_company && db_company.quick_analysis_data.present?
        companies_map[company[:id]] = {
          id: db_company.id,
          name: db_company.name,
          quick_analysis_data: db_company.quick_analysis_data
        }
      end
    end

    # Filter companies to process
    companies_to_process = context[:companies].reject do |company|
      companies_map.key?(company[:id])
    end

    # Process in chunks to avoid memory issues
    processed_companies = []
    companies_to_process.each_slice(10) do |chunk|
      chunk_result = process_chunk(chunk)
      processed_companies.concat(chunk_result[:companies])
    end

    # Save processed results
    processed_companies.each do |company|
      db_company = Company.find_by(id: company[:id])
      next unless db_company

      db_company.update!(
        quick_analysis_data: company[:quick_analysis_data]
      )
    end

    # Merge skipped and processed
    skipped_companies = companies_map.values
    all_companies = processed_companies + skipped_companies

    { success: true, companies: all_companies }
  end

  private

  def process_chunk(chunk)
    # Custom chunk processing logic
    raaf_result = run_with_context(companies: chunk)
    raaf_result.dig(:message) || { companies: [] }
  end
end
```

**Code Stats:**
- Lines: ~60
- Manual logic: Skip filtering, chunking, merging, persistence
- Complexity: High (multiple database queries, manual error handling)

### After: QuickFitAnalyzer (New Pattern)

```ruby
class QuickFitAnalyzer < Ai::Agents::ApplicationAgent
  agent_name "QuickFitAnalyzer"
  model "gpt-4o-mini"
  max_turns 1

  # NEW: Declarative field configuration
  incremental_input_field :companies
  incremental_output_field :companies

  # NEW: Declarative incremental processing
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
      field :quick_analysis_data, :object, required: true do
        field :fit_score, :integer, required: true
        field :reasoning, :string, required: true
      end
    end
  end
end
```

**Code Stats:**
- Lines: ~35 (42% reduction)
- Manual logic: None (all handled by framework)
- Complexity: Low (simple declarative closures)

**Improvements:**
- 80% less boilerplate
- Clearer intent
- Better performance
- Automatic error handling
- Consistent with other agents

## Common Migration Patterns

### Pattern 1: Simple Analysis Agent

**Old:**
```ruby
on_result_ready do
  existing = load_existing_data
  to_process = filter_new(existing)
  processed = process_and_save(to_process)
  merge_results(existing, processed)
end
```

**New:**
```ruby
incremental_processing do
  skip_if { |item| item[:analysis].present? }
  load_existing { |id| Database.find(id)&.to_h }
  persistence_handler { |item| Database.save(item) }
end
```

### Pattern 2: Complex Enrichment Agent

**Old:**
```ruby
on_result_ready do
  # Load with associations
  companies_map = load_with_associations

  # Custom skip logic with freshness
  to_process = companies.reject do |c|
    existing = companies_map[c[:id]]
    existing && existing[:enriched_at] > 30.days.ago
  end

  # Process and deduplicate citations
  processed = process_with_citations(to_process)

  # Merge and save
  save_with_citations(processed)
  merge_all(companies_map, processed)
end
```

**New:**
```ruby
incremental_processing do
  chunk_size 5  # Expensive API

  skip_if do |company|
    company[:enrichment_data].present? &&
      company[:enriched_at] > 30.days.ago
  end

  load_existing do |company_id|
    company = Company.includes(:citations).find_by(id: company_id)
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

    # Handle citations separately
    if company[:enrichment_data][:citations].present?
      company[:enrichment_data][:citations].each do |citation|
        CompanyCitation.create_or_update(
          company: db_company,
          url: citation[:url],
          title: citation[:title]
        )
      end
    end
  end
end
```

### Pattern 3: Multi-Stage Pipeline Agent

**Old:**
```ruby
# Each agent has separate hooks and persistence
class StageOne < ApplicationAgent
  on_result_ready { manual_persistence }
end

class StageTwo < ApplicationAgent
  on_result_ready { manual_persistence }
end
```

**New:**
```ruby
# Each agent uses incremental processing
class StageOne < ApplicationAgent
  incremental_processing { ... }
end

class StageTwo < ApplicationAgent
  incremental_processing { ... }
end

# Pipeline coordinates automatically
class Pipeline < RAAF::Pipeline
  flow StageOne >> StageTwo
end
```

## Rollback Procedure

If migration causes issues:

### Immediate Rollback (Git)

```bash
# Revert to previous commit
git checkout HEAD~1 -- app/ai/agents/my_agent.rb

# Or create new commit reverting changes
git revert HEAD

# Deploy previous version
```

### Manual Rollback

1. **Restore old hook code** from backup/version control
2. **Remove incremental declarations** and processing block
3. **Run tests** to verify old behavior
4. **Deploy** previous working version
5. **Document issues** encountered for later fix

### Partial Rollback (Feature Flag)

If you implemented feature flags (Task 5.6):

```ruby
# In agent configuration
def use_incremental_processing?
  ENV['INCREMENTAL_PROCESSING_ENABLED'] == 'true' &&
    !ENV['DISABLE_FOR_AGENTS']&.split(',')&.include?(self.class.name)
end

# Disable for specific agent
ENV['DISABLE_FOR_AGENTS'] = 'QuickFitAnalyzer,Company::Enrichment'
```

## Performance Validation

After migration, verify improvements:

### Memory Usage Check

```ruby
# Before migration
memory_before = `ps -o rss= -p #{Process.pid}`.to_i

agent.run(companies: large_dataset)

memory_after = `ps -o rss= -p #{Process.pid}`.to_i
memory_used = memory_after - memory_before

puts "Memory used: #{memory_used / 1024}MB"
# Expected: 50-80% reduction for large datasets
```

### API Call Reduction

```ruby
# Track API calls
api_calls = 0
allow_any_instance_of(OpenAI::Client).to receive(:chat) do |*args|
  api_calls += 1
  # ... original behavior
end

# First run
agent.run(companies: companies)
puts "First run API calls: #{api_calls}"  # Expected: All companies

# Second run
api_calls = 0
agent.run(companies: companies)
puts "Second run API calls: #{api_calls}"  # Expected: 0 (all skipped)
```

### Processing Time

```ruby
# Compare processing time
Benchmark.bm do |x|
  x.report("With incremental") do
    agent.run(companies: large_dataset)
  end

  x.report("Second run (skipped)") do
    agent.run(companies: large_dataset)
  end
end

# Expected: Second run 90%+ faster
```

## Migration Checklist

Complete this checklist for each agent migration:

- [ ] **Pre-Migration**
  - [ ] Commit working code
  - [ ] All tests passing
  - [ ] Understand data flow
  - [ ] Review existing hooks

- [ ] **Code Changes**
  - [ ] Add `incremental_input_field` declaration
  - [ ] Add `incremental_output_field` declaration
  - [ ] Add `incremental_processing` block
  - [ ] Implement `skip_if` closure
  - [ ] Implement `load_existing` closure
  - [ ] Implement `persistence_handler` closure
  - [ ] Remove `on_result_ready` hook
  - [ ] Remove manual skip/merge/persistence logic

- [ ] **Testing**
  - [ ] Update test suite
  - [ ] Test with no existing data
  - [ ] Test with all existing data
  - [ ] Test with mixed data
  - [ ] Test with force_reprocess
  - [ ] Test in pipeline (if applicable)
  - [ ] All tests passing

- [ ] **Validation**
  - [ ] Memory usage reduced
  - [ ] API calls reduced on second run
  - [ ] Processing time improved
  - [ ] Data persisted correctly
  - [ ] Skip logic working
  - [ ] Error handling works

- [ ] **Documentation**
  - [ ] Update agent documentation
  - [ ] Document any caveats
  - [ ] Update team wiki/docs
  - [ ] Add migration notes to PR

- [ ] **Deployment**
  - [ ] Code review completed
  - [ ] Merged to main branch
  - [ ] Deployed to staging
  - [ ] Tested in staging
  - [ ] Deployed to production
  - [ ] Monitor for issues

## Getting Help

If you encounter issues:

1. **Check Troubleshooting Guide**: See `troubleshooting-guide.md`
2. **Review Framework Guide**: See `raaf-incremental-processing-guide.md`
3. **Check Examples**: Review migrated agents (QuickFitAnalyzer, Company::Enrichment, Prospect::Scoring)
4. **Enable Debug Logging**: Set `RAAF.logger.level = Logger::DEBUG`
5. **Check RAAF Issues**: Search RAAF gem issues for similar problems

## Success Criteria

Migration is successful when:

- [ ] All tests passing
- [ ] Memory usage reduced (50-80% for large datasets)
- [ ] API calls reduced on repeated runs (80-100% reduction)
- [ ] Code is cleaner and more maintainable
- [ ] No regressions in functionality
- [ ] Performance metrics improved
- [ ] Team understands new pattern

## Next Steps

After successful migration:

1. **Monitor Production**: Watch for any issues in production
2. **Document Learnings**: Note any challenges for next migration
3. **Migrate Next Agent**: Apply learnings to next agent
4. **Share Knowledge**: Update team documentation with migration experience

---

**Ready to migrate?** Follow the steps above and refer to `troubleshooting-guide.md` if you encounter issues.

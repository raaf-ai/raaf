# Troubleshooting Guide: RAAF Incremental Processing

> Version: 1.0.0
> Last Updated: 2025-10-16
> Audience: Developers implementing incremental processing

## Overview

This guide covers common issues, debugging techniques, and solutions for RAAF incremental processing implementation.

## Common Issues and Solutions

### Issue 1: `NoMethodError: undefined method 'incremental_processing?'`

**Symptom:**
```
NoMethodError: undefined method `incremental_processing?' for QuickFitAnalyzer:Class
```

**Cause:** Agent class doesn't include `RAAF::DSL::IncrementalProcessing` module.

**Solution:**

Check that your base agent class includes the module:

```ruby
# In app/ai/agents/application_agent.rb
class ApplicationAgent < RAAF::DSL::Agent
  include RAAF::DSL::ToolDsl
  include RAAF::DSL::PromptDsl
  include RAAF::DSL::AutoMerge
  include RAAF::DSL::IncrementalProcessing  # ✅ Must be included

  # ... rest of configuration
end
```

**Verification:**
```ruby
# In Rails console
QuickFitAnalyzer.respond_to?(:incremental_processing?)
# => true (if module is included)
```

---

### Issue 2: Records Not Being Skipped

**Symptom:**
- Agent processes all records every time
- API calls not reduced on second run
- Database shows existing data but skip logic not working

**Cause:** Skip logic returning false when it should return true.

**Debugging Steps:**

1. **Add logging to skip_if closure:**
```ruby
skip_if do |company|
  should_skip = company[:quick_analysis_data].present?
  RAAF.logger.debug "🔍 Skip check for #{company[:id]}: #{should_skip} (data: #{company[:quick_analysis_data].present?})"
  should_skip
end
```

2. **Check load_existing is returning data:**
```ruby
load_existing do |company_id|
  company = Company.find_by(id: company_id)
  RAAF.logger.debug "📖 Loading company #{company_id}: #{company.present?}"

  return nil unless company

  data = {
    id: company.id,
    name: company.name,
    quick_analysis_data: company.quick_analysis_data
  }

  RAAF.logger.debug "📖 Loaded data for #{company_id}: #{data}"
  data
end
```

3. **Run in console with debug logging:**
```ruby
RAAF.logger.level = Logger::DEBUG

agent = QuickFitAnalyzer.new(
  companies: [{ id: 1, name: "Test" }],
  product: product
)

result = agent.run
# Check debug output for skip decisions
```

**Common Causes:**

| Cause | Symptom | Solution |
|-------|---------|----------|
| `load_existing` returns nil | Skip always false | Check database record exists |
| Wrong field checked in skip_if | Skip always false | Match field name to schema |
| Data structure mismatch | Skip intermittent | Ensure hash keys match (symbols vs strings) |
| `load_existing` missing fields | Skip always false | Include all fields used in skip_if |

**Solution Examples:**

```ruby
# ❌ WRONG: Field name mismatch
skip_if do |company|
  company[:analysis].present?  # Wrong field name
end

load_existing do |id|
  { id: id, quick_analysis_data: { ... } }  # Returns different field
end

# ✅ CORRECT: Matching field names
skip_if do |company|
  company[:quick_analysis_data].present?
end

load_existing do |id|
  { id: id, quick_analysis_data: { ... } }
end
```

```ruby
# ❌ WRONG: Missing required data
skip_if do |company|
  company[:quick_analysis_data].present? &&
    company[:analyzed_at] > 7.days.ago  # ← analyzed_at not loaded!
end

load_existing do |id|
  { id: id, quick_analysis_data: { ... } }  # Missing analyzed_at
end

# ✅ CORRECT: Include all needed fields
skip_if do |company|
  company[:quick_analysis_data].present? &&
    company[:analyzed_at] > 7.days.ago
end

load_existing do |id|
  company = Company.find_by(id: id)
  return nil unless company

  {
    id: id,
    quick_analysis_data: company.quick_analysis_data,
    analyzed_at: company.content_updated_at  # ✅ Included
  }
end
```

---

### Issue 3: Data Not Loading from Database

**Symptom:**
- `load_existing` called but returns nil
- Skip logic never triggers
- All records processed even with existing data

**Debugging Steps:**

1. **Verify database records exist:**
```ruby
# In Rails console
Company.where(id: [1, 2, 3]).pluck(:id, :quick_analysis_data)
# => [[1, {...}], [2, {...}], [3, {...}]]
```

2. **Check load_existing query:**
```ruby
load_existing do |company_id|
  RAAF.logger.debug "📖 Looking for company #{company_id}"

  company = Company.find_by(id: company_id)
  RAAF.logger.debug "📖 Found: #{company.inspect}"

  return nil unless company

  data = {
    id: company.id,
    name: company.name,
    quick_analysis_data: company.quick_analysis_data
  }

  RAAF.logger.debug "📖 Returning: #{data}"
  data
end
```

3. **Test load_existing in console:**
```ruby
# Test closure directly
load_fn = ->(id) {
  company = Company.find_by(id: id)
  return nil unless company
  { id: company.id, name: company.name }
}

load_fn.call(1)
# => Should return hash or nil
```

**Common Causes:**

| Cause | Solution |
|-------|----------|
| Wrong database query | Use correct model and ID field |
| ID type mismatch (string vs integer) | Convert ID types if needed |
| Scoped query missing records | Check query scopes/filters |
| Database connection issue | Verify Rails database connection |
| Multi-tenancy filtering records | Check acts_as_tenant scope |

**Solution Examples:**

```ruby
# ❌ WRONG: Type mismatch
load_existing do |company_id|
  # company_id might be string "123"
  Company.find_by(id: company_id)  # Query might fail with string
end

# ✅ CORRECT: Convert ID type
load_existing do |company_id|
  Company.find_by(id: company_id.to_i)  # Ensure integer
end
```

```ruby
# ❌ WRONG: Overly restrictive query
load_existing do |company_id|
  Company.where(id: company_id, active: true).first
  # Returns nil if company exists but inactive
end

# ✅ CORRECT: Load all matching records
load_existing do |company_id|
  Company.find_by(id: company_id)  # Load regardless of status
end
```

---

### Issue 4: Persistence Not Happening

**Symptom:**
- Agent runs successfully
- No errors logged
- Database not updated with new data

**Debugging Steps:**

1. **Add logging to persistence handler:**
```ruby
persistence_handler do |company|
  RAAF.logger.info "💾 Persistence handler called for #{company[:id]}"

  db_company = Company.find_by(id: company[:id])

  if db_company
    RAAF.logger.info "💾 Found database record for #{company[:id]}"
  else
    RAAF.logger.warn "⚠️ No database record found for #{company[:id]}"
    next
  end

  begin
    db_company.update!(quick_analysis_data: company[:quick_analysis_data])
    RAAF.logger.info "✅ Successfully saved #{company[:id]}"
  rescue StandardError => e
    RAAF.logger.error "❌ Failed to save #{company[:id]}: #{e.message}"
    raise
  end
end
```

2. **Check if handler is being called:**
```ruby
# Add counter
@persistence_calls = 0

persistence_handler do |company|
  @persistence_calls += 1
  RAAF.logger.info "💾 Persistence call ##{@persistence_calls}"
  # ... rest of logic
end
```

3. **Verify data structure:**
```ruby
persistence_handler do |company|
  RAAF.logger.info "💾 Data to save: #{company.inspect}"
  # Check if company has expected fields
end
```

**Common Causes:**

| Cause | Solution |
|-------|----------|
| Using `return` instead of `next` | Use `next` in block context |
| Database record not found | Handle missing records gracefully |
| Validation errors | Check model validations, use update! to see errors |
| Transaction rollback | Check for transaction errors in logs |
| Silent failures | Always log persistence operations |

**Solution Examples:**

```ruby
# ❌ WRONG: Using return in block
persistence_handler do |company|
  db_company = Company.find_by(id: company[:id])
  return unless db_company  # ❌ Exits entire method!

  db_company.update!(data: company[:data])
end

# ✅ CORRECT: Using next in block
persistence_handler do |company|
  db_company = Company.find_by(id: company[:id])
  next unless db_company  # ✅ Skips to next iteration

  db_company.update!(data: company[:data])
end
```

```ruby
# ❌ WRONG: Silent failures with update (no !)
persistence_handler do |company|
  db_company = Company.find_by(id: company[:id])
  next unless db_company

  db_company.update(data: company[:data])  # ❌ Returns false on failure
end

# ✅ CORRECT: Use update! to raise on error
persistence_handler do |company|
  db_company = Company.find_by(id: company[:id])
  next unless db_company

  db_company.update!(data: company[:data])  # ✅ Raises on failure
end
```

---

### Issue 5: Chunk Size Too Large - Memory Issues

**Symptom:**
- Memory usage spikes
- Out of memory errors
- Slow performance with large datasets

**Solution:**

Reduce chunk size:

```ruby
# ❌ TOO LARGE for complex processing
incremental_processing do
  chunk_size 100  # Might cause memory issues
end

# ✅ BETTER: Smaller chunks
incremental_processing do
  chunk_size 10  # More manageable for most cases
end

# ✅ OPTIMAL: Adjust based on processing complexity
incremental_processing do
  # Simple filtering: larger chunks OK
  chunk_size 25

  # Complex enrichment: smaller chunks
  chunk_size 5

  # Deep analysis: very small chunks
  chunk_size 3
end
```

**Guidelines:**
- **Simple processing (filtering, classification)**: 20-50 items
- **Standard analysis**: 10-25 items
- **Complex enrichment**: 5-10 items
- **Expensive API calls (Perplexity)**: 3-5 items

---

### Issue 6: N+1 Database Queries

**Symptom:**
- Slow performance
- Many database queries logged
- Load time increases with dataset size

**Debugging:**

Enable query logging:
```ruby
# In config/environments/development.rb
config.log_level = :debug
config.active_record.verbose_query_logs = true
```

**Solution:**

Preload associations outside agent:

```ruby
# ❌ WRONG: N+1 queries in load_existing
load_existing do |company_id|
  company = Company.find_by(id: company_id)
  return nil unless company

  {
    id: company.id,
    citations: company.citations.map(&:to_h)  # ❌ N+1 query per company!
  }
end

# ✅ CORRECT: Preload before agent run
companies = Company.includes(:citations).where(...)

agent.run(companies: companies.map(&:to_h))

# Then simple load_existing
load_existing do |company_id|
  company = Company.find_by(id: company_id)
  return nil unless company

  company.to_h  # Citations already loaded
end
```

```ruby
# ✅ ALTERNATIVE: Use pluck for simple data
load_existing do |company_id|
  Company.where(id: company_id)
    .pluck(:id, :name, :quick_analysis_data)
    .first
    &.then { |id, name, data| { id: id, name: name, quick_analysis_data: data } }
end
```

---

### Issue 7: Hash Key Access Issues (Symbols vs Strings)

**Symptom:**
- Skip logic works intermittently
- Data present but not detected
- `nil` errors when accessing hash fields

**Cause:** Mixing symbol and string keys in hashes.

**Debugging:**

```ruby
skip_if do |company|
  RAAF.logger.debug "Keys: #{company.keys.inspect}"
  RAAF.logger.debug "Data (symbol): #{company[:quick_analysis_data]}"
  RAAF.logger.debug "Data (string): #{company['quick_analysis_data']}"

  company[:quick_analysis_data].present?
end
```

**Solution:**

Use `HashWithIndifferentAccess` or consistent key types:

```ruby
# ✅ OPTION 1: Use HashWithIndifferentAccess
load_existing do |company_id|
  company = Company.find_by(id: company_id)
  return nil unless company

  ActiveSupport::HashWithIndifferentAccess.new(
    id: company.id,
    quick_analysis_data: company.quick_analysis_data
  )
end

# ✅ OPTION 2: Consistent symbol keys
load_existing do |company_id|
  company = Company.find_by(id: company_id)
  return nil unless company

  {
    id: company.id,  # Symbols everywhere
    name: company.name,
    quick_analysis_data: company.quick_analysis_data
  }
end

skip_if do |company|
  company[:quick_analysis_data].present?  # Symbol access
end
```

---

### Issue 8: Force Reprocess Not Working

**Symptom:**
- Setting `force_reprocess: true` doesn't reprocess items
- Items still skipped

**Debugging:**

```ruby
# Check if context variable is being passed
agent = MyAgent.new(
  companies: companies,
  product: product,
  force_reprocess: true
)

RAAF.logger.debug "Context: #{agent.context.inspect}"
# Should show force_reprocess: true
```

**Solution:**

Ensure context declares optional parameter:

```ruby
# ❌ WRONG: Context doesn't declare force_reprocess
context do
  required :companies, :product
  # Missing force_reprocess declaration
end

# ✅ CORRECT: Declare optional parameter
context do
  required :companies, :product
  optional force_reprocess: false  # ✅ Declared
end
```

Framework automatically checks `context[:force_reprocess]` and skips skip_if when true.

---

## Debugging Techniques

### Enable Debug Logging

```ruby
# In Rails console or test
RAAF.logger.level = Logger::DEBUG

# Run agent
agent.run(...)

# Check logs for:
# - "🔍 [IncrementalProcessor] Processing chunk X/Y"
# - "⏭️ [IncrementalProcessor] Skipping item X"
# - "✅ [IncrementalProcessor] Processed X items, skipped Y items"
```

### Test Individual Closures

```ruby
# In Rails console

# Test skip_if logic
skip_fn = ->(company) { company[:quick_analysis_data].present? }
skip_fn.call({ id: 1, quick_analysis_data: { score: 80 } })
# => true (should skip)

# Test load_existing logic
load_fn = ->(id) {
  company = Company.find_by(id: id)
  return nil unless company
  { id: company.id, quick_analysis_data: company.quick_analysis_data }
}
load_fn.call(1)
# => { id: 1, quick_analysis_data: {...} }

# Test persistence logic
persist_fn = ->(company) {
  db_company = Company.find_by(id: company[:id])
  next unless db_company
  db_company.update!(quick_analysis_data: company[:quick_analysis_data])
}
persist_fn.call({ id: 1, quick_analysis_data: { score: 90 } })
# => Check Company.find(1).quick_analysis_data
```

### Verify Field Declarations

```ruby
# In Rails console
QuickFitAnalyzer.incremental_input_field
# => :companies

QuickFitAnalyzer.incremental_output_field
# => :companies

QuickFitAnalyzer.incremental_processing?
# => true
```

### Test with Small Dataset

```ruby
# Start with 1-2 records
companies = [
  { id: 1, name: "Test 1" },
  { id: 2, name: "Test 2" }
]

agent = QuickFitAnalyzer.new(companies: companies, product: product)
result = agent.run

# Verify results
puts "Processed: #{result[:companies].count}"
# => 2

# Run again - should skip
result2 = agent.run
puts "Skipped: #{result2[:companies].count}"
# => 2 (all skipped, no AI calls)
```

### Monitor API Calls

```ruby
# In test or console
api_call_count = 0

allow_any_instance_of(OpenAI::Client).to receive(:chat) do |*args|
  api_call_count += 1
  RAAF.logger.info "🤖 API call ##{api_call_count}"
  # ... original behavior
end

# First run
agent.run(companies: companies)
puts "First run API calls: #{api_call_count}"

# Second run
api_call_count = 0
agent.run(companies: companies)
puts "Second run API calls: #{api_call_count}"
# => Should be 0 if skip logic working
```

---

## Performance Issues

### Issue: Slow Processing with Large Datasets

**Symptoms:**
- Agent takes long time to complete
- Memory usage grows steadily
- Timeouts on large datasets

**Solutions:**

1. **Reduce chunk size:**
```ruby
incremental_processing do
  chunk_size 5  # Smaller chunks
end
```

2. **Optimize database queries:**
```ruby
# Preload associations
companies = Company.includes(:enrichment_data, :citations).where(...)

# Use select to limit fields
companies = Company.select(:id, :name, :analysis_data).where(...)
```

3. **Add batch processing monitoring:**
```ruby
incremental_processing do
  chunk_size 10

  # Add timing
  skip_if do |item|
    start = Time.current
    result = item[:data].present?
    duration = Time.current - start
    RAAF.logger.debug "⏱️ Skip check took #{duration}s"
    result
  end
end
```

### Issue: High Memory Usage

**Symptoms:**
- Memory grows during processing
- Out of memory errors
- Server swapping

**Solutions:**

1. **Process in smaller chunks:**
```ruby
chunk_size 5  # Instead of 50
```

2. **Clear loaded data after persistence:**
```ruby
persistence_handler do |company|
  db_company = Company.find_by(id: company[:id])
  next unless db_company

  db_company.update!(data: company[:data])

  # Clear cached data
  ActiveRecord::Base.connection_pool.release_connection
  GC.start
end
```

3. **Use pluck instead of loading objects:**
```ruby
load_existing do |id|
  result = Company.where(id: id)
    .pluck(:id, :name, :quick_analysis_data)
    .first

  return nil unless result

  { id: result[0], name: result[1], quick_analysis_data: result[2] }
end
```

---

## Error Recovery

### Handling Persistence Failures

**Pattern:**
```ruby
persistence_handler do |item|
  retries = 0
  max_retries = 3

  begin
    db_item = Item.find_by(id: item[:id])
    next unless db_item

    db_item.update!(data: item[:data])
    RAAF.logger.info "✅ Saved #{item[:id]}"

  rescue ActiveRecord::RecordInvalid => e
    retries += 1
    if retries < max_retries
      RAAF.logger.warn "⚠️ Retry #{retries}/#{max_retries} for #{item[:id]}"
      sleep(1)
      retry
    else
      RAAF.logger.error "❌ Failed after #{max_retries} retries: #{e.message}"
      # Item will be reprocessed on next run since persistence failed
    end

  rescue StandardError => e
    RAAF.logger.error "❌ Unexpected error for #{item[:id]}: #{e.message}"
    RAAF.logger.error "🔍 #{e.backtrace.first(5).join("\n")}"
    # Framework will log and continue
  end
end
```

### Resuming After Failure

If agent crashes mid-processing:

1. **Check logs** for last successful persistence
2. **Verify database state** - which items were saved
3. **Re-run agent** - incremental processing will:
   - Skip successfully saved items
   - Reprocess failed items
   - Continue from where it left off

```ruby
# No special recovery needed - just run again
agent.run(companies: all_companies)
# Automatically resumes from where it failed
```

---

## Testing Issues

### Issue: Tests Failing After Migration

**Common Causes:**

1. **Test database not seeded:**
```ruby
# ✅ CORRECT: Create database records for tests
before do
  Company.create!(
    id: 1,
    name: "Test Co",
    quick_analysis_data: { fit_score: 80 }
  )
end
```

2. **Mocking not matching new pattern:**
```ruby
# ❌ WRONG: Old mock pattern
allow(agent).to receive(:call).and_return({...})

# ✅ CORRECT: Mock database queries
allow(Company).to receive(:find_by).and_return(company)
```

3. **Tests expect old result structure:**
```ruby
# Update test expectations to match new result format
expect(result[:companies]).to be_present
expect(result[:companies].first[:quick_analysis_data]).to be_present
```

### Issue: Flaky Tests

**Causes:**
- Database state not cleaned between tests
- Mocking conflicts
- Race conditions in async processing

**Solutions:**

```ruby
# Use database_cleaner or similar
RSpec.configure do |config|
  config.use_transactional_fixtures = true

  config.before(:each) do
    DatabaseCleaner.clean
  end
end

# Or manual cleanup
after do
  Company.destroy_all
end
```

---

## Getting Additional Help

### Enable Verbose Logging

```ruby
# In Rails console or config/environments/development.rb
RAAF.logger = Logger.new(STDOUT)
RAAF.logger.level = Logger::DEBUG
ActiveRecord::Base.logger.level = Logger::DEBUG
```

### Check Framework Version

```ruby
# Verify RAAF version supports incremental processing
RAAF::VERSION
# => Should be >= version with incremental processing support
```

### Review Documentation

- **Framework Guide**: `raaf-incremental-processing-guide.md`
- **Migration Guide**: `migration-guide.md`
- **Example Agents**: QuickFitAnalyzer, Company::Enrichment, Prospect::Scoring

### Debug Checklist

When encountering issues:

- [ ] Enable debug logging (`RAAF.logger.level = Logger::DEBUG`)
- [ ] Test with small dataset (1-3 records)
- [ ] Verify field declarations match context/schema
- [ ] Check database records exist and have expected data
- [ ] Test individual closures in Rails console
- [ ] Verify skip logic with logging
- [ ] Check persistence handler with logging
- [ ] Review error logs for exceptions
- [ ] Test with `force_reprocess: true`
- [ ] Verify chunk size appropriate for dataset

---

## Quick Reference: Common Error Patterns

| Error | Likely Cause | Quick Fix |
|-------|------------|-----------|
| `NoMethodError: incremental_processing?` | Module not included | Add `include RAAF::DSL::IncrementalProcessing` to ApplicationAgent |
| All items processed (not skipped) | Skip logic returns false | Check `load_existing` returns data, verify field names match |
| Database not updated | Persistence handler not saving | Use `update!` not `update`, check for `return` vs `next` |
| Memory issues | Chunk size too large | Reduce `chunk_size` to 5-10 |
| Slow performance | N+1 queries | Preload associations outside agent |
| `nil` access errors | Hash key mismatch | Use symbols consistently or HashWithIndifferentAccess |
| Force reprocess ignored | Context not declared | Add `optional force_reprocess: false` to context |
| Tests failing | Database not seeded | Create test data in before blocks |

---

**Still stuck?** Review the complete framework guide or check example agents for working implementations.

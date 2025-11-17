# Spec Requirements Document

> Spec: Evaluator Definition DSL Module
> Created: 2025-01-14
> Status: Planning

## Overview

Create a module-based Domain-Specific Language (DSL) for defining RAAF evaluator classes that eliminates the awkward `class << self` singleton pattern, provides automatic caching, and delivers a clean, declarative API following Ruby conventions (ActiveRecord, RSpec style).

This enhancement transforms evaluator class definitions from verbose, procedural singleton methods into elegant, declarative class-level DSL that reduces boilerplate by 70%+ while maintaining full compatibility with the existing RAAF Eval evaluation engine.

## User Stories

### Story 1: Clean Evaluator Definition

**As a** RAAF developer
**I want to** define evaluators using clean DSL at class level
**So that** I can eliminate boilerplate `class << self` blocks and write more maintainable code

**Acceptance Criteria:**
- ✅ Can `include RAAF::Eval::DSL::EvaluatorDefinition` in evaluator class
- ✅ DSL methods (`select`, `evaluate_field`, `on_progress`, `history`) work at class level
- ✅ No need for `class << self` or `def self.evaluator` methods
- ✅ Configuration stored automatically in class variables
- ✅ Evaluator definition built automatically from DSL configuration

**Example:**
```ruby
class ProspectScoring
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'prospect_evaluations', as: :evaluations
  select 'criterion_scores', as: :scores

  evaluate_field :evaluations do
    evaluate_with :semantic_similarity, threshold: 0.85
    evaluate_with :no_regression
  end
end

# Usage (unchanged):
ProspectScoring.evaluator  # Returns RAAF::Eval evaluator instance
```

### Story 2: Automatic Evaluator Caching

**As a** RAAF developer
**I want** evaluator definitions to be automatically cached
**So that** I don't need to write manual `@evaluator ||=` caching patterns

**Acceptance Criteria:**
- ✅ First call to `Class.evaluator` builds and caches evaluator definition
- ✅ Subsequent calls return cached instance without rebuilding
- ✅ Cache managed automatically by module (no manual code required)
- ✅ Thread-safe caching implementation
- ✅ Cache reset available via `Class.reset_evaluator!`

**Example:**
```ruby
class MyEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'output', as: :output
end

# First call builds and caches:
eval1 = MyEvaluator.evaluator
# => Builds evaluator from DSL configuration

# Second call returns cached instance:
eval2 = MyEvaluator.evaluator
# => Returns cached evaluator (same object)

eval1.object_id == eval2.object_id
# => true
```

### Story 3: Built-in Testing Support

**As a** RAAF developer
**I want** an automatic `reset_evaluator!` method for testing
**So that** I can easily clear cached evaluators between test runs

**Acceptance Criteria:**
- ✅ `Class.reset_evaluator!` method available automatically after including module
- ✅ Clears cached evaluator instance completely
- ✅ Next `Class.evaluator` call rebuilds from DSL configuration
- ✅ Works correctly in RSpec test suites
- ✅ No need to manually implement cache clearing logic

**Example:**
```ruby
RSpec.describe MyEvaluator do
  after(:each) do
    MyEvaluator.reset_evaluator!  # Clear cache between tests
  end

  it "builds evaluator with correct configuration" do
    evaluator = MyEvaluator.evaluator
    expect(evaluator).to be_a(RAAF::Eval::Evaluator)
  end

  it "handles configuration changes in tests" do
    # Evaluator rebuilt fresh after reset_evaluator! in after hook
    evaluator = MyEvaluator.evaluator
    expect(evaluator.field_selections).to include(:output)
  end
end
```

### Story 4: Ruby-Conventional API

**As a** Ruby developer
**I want** evaluator definitions to follow familiar Ruby patterns
**So that** the API feels natural and idiomatic

**Acceptance Criteria:**
- ✅ Module-based extension pattern (like ActiveSupport::Concern)
- ✅ Class-level DSL methods (like ActiveRecord validations)
- ✅ `included` hook for automatic setup (Ruby convention)
- ✅ Configuration stored in class variables (not instance variables)
- ✅ Follows same patterns as ActiveRecord, RSpec, Devise

**Comparison to Familiar APIs:**

**ActiveRecord Style:**
```ruby
class User < ApplicationRecord
  validates :email, presence: true  # Class-level DSL
  has_many :posts                  # Class-level DSL
end
```

**RSpec Style:**
```ruby
RSpec.describe User do
  let(:user) { User.new }          # Class-level DSL
  before { do_setup }              # Class-level DSL
end
```

**RAAF Evaluator Style (This Spec):**
```ruby
class MyEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'field', as: :field       # Class-level DSL
  evaluate_field :field do         # Class-level DSL
    evaluate_with :similarity
  end
end
```

## Spec Scope

### In Scope

- ✅ Create `RAAF::Eval::DSL::EvaluatorDefinition` module
- ✅ Implement class-level DSL methods: `select`, `evaluate_field`, `on_progress`, `history`
- ✅ Implement automatic caching via `evaluator` method
- ✅ Implement automatic `reset_evaluator!` method
- ✅ Configuration storage and retrieval mechanism
- ✅ Builder method to construct evaluator from configuration
- ✅ Update autoload configuration in `raaf/eval/lib/raaf/eval/dsl.rb`
- ✅ Comprehensive RSpec test coverage
- ✅ Migration guide and documentation

### Out of Scope

- ❌ Changes to evaluation workflow DSL (separate spec: `2025-01-13-evaluator-dsl-api`)
- ❌ Changes to existing 22 built-in evaluators (continue using module pattern)
- ❌ Web UI integration (evaluators are backend-only)
- ❌ Changes to EvaluatorRegistry (registry works unchanged)
- ❌ Changes to evaluation execution engine
- ❌ Breaking changes to existing API (backward compatible)

### Migration Scope (ProspectsRadar)

- ✅ Migrate all existing evaluator classes in prospects_radar using singleton pattern
- ✅ Update all evaluator class definitions to use new DSL pattern
- ✅ Verify all migrated evaluators work correctly with existing tests
- ✅ Ensure backward compatibility with any existing RSpec tests
- ✅ Document any prospects_radar-specific migration considerations

## Expected Deliverables

### 1. Core Module Implementation
**File:** `vendor/local_gems/raaf/eval/lib/raaf/eval/dsl/evaluator_definition.rb`

**Must Include:**
- Module definition with `self.included` hook
- ClassMethods module with all DSL methods
- Configuration storage mechanism
- Evaluator builder from configuration
- Cache management (get, clear)

### 2. Autoload Configuration
**File:** `vendor/local_gems/raaf/eval/lib/raaf/eval/dsl.rb`

**Must Include:**
- `autoload :EvaluatorDefinition, 'raaf/eval/dsl/evaluator_definition'`

### 3. Example Migration (RAAF Core)
**File:** Update existing Scoring class (find location first)

**Must Include:**
- Remove `class << self` block
- Add `include RAAF::Eval::DSL::EvaluatorDefinition`
- Move DSL calls to class level
- Demonstrate pattern in real code

### 3b. ProspectsRadar Migration
**Location:** `prospects_radar/` directory (all evaluator classes)

**Must Include:**
- Identify all evaluator classes using singleton pattern
- Migrate each class to new DSL pattern
- Test each migrated evaluator
- Update any RSpec tests if needed
- Document migration in prospects_radar CLAUDE.md or migration notes

**Expected Classes to Migrate:**
- Find all classes with `class << self` and `def evaluator` pattern
- Likely in `prospects_radar/app/evaluators/` or similar directory
- May include prospect scoring, market analysis, or other domain evaluators

### 4. Comprehensive Tests
**File:** `vendor/local_gems/raaf/eval/spec/raaf/eval/dsl/evaluator_definition_spec.rb`

**Must Cover:**
- Module inclusion behavior
- DSL method availability
- Configuration storage and retrieval
- `evaluator` method caching
- `reset_evaluator!` functionality
- Multiple `select` calls accumulation
- Multiple `evaluate_field` calls
- `on_progress` and `history` methods
- Thread safety (if applicable)

### 5. Documentation Updates
**Files:**
- `vendor/local_gems/raaf/eval/README.md`
- `vendor/local_gems/raaf/RAAF_EVAL.md` (if exists)
- `vendor/local_gems/raaf/eval/CLAUDE.md` (if exists)

**Must Include:**
- New DSL pattern documentation
- Migration guide (before/after examples)
- Benefits explanation
- API reference for all DSL methods

## Technical Specification

### Module Structure

```ruby
module RAAF
  module Eval
    module DSL
      module EvaluatorDefinition
        # Hook called when module is included
        def self.included(base)
          base.extend(ClassMethods)
          base.instance_variable_set(:@_evaluator_config, {
            selections: [],
            field_evaluations: {},
            progress_callback: nil,
            history_options: {}
          })
        end

        module ClassMethods
          # DSL Methods
          def select(path, as:)
            # Store field selection
          end

          def evaluate_field(name, &block)
            # Store field evaluation configuration
          end

          def on_progress(&block)
            # Store progress callback
          end

          def history(**options)
            # Store history configuration
          end

          # Automatic Methods
          def evaluator
            # Return cached or build new evaluator
          end

          def reset_evaluator!
            # Clear cached evaluator
          end

          private

          def build_evaluator_from_config
            # Construct RAAF::Eval.define from stored config
          end
        end
      end
    end
  end
end
```

### DSL Method Specifications

#### `select(path, as:)`

**Purpose:** Define a field selection for evaluation

**Parameters:**
- `path` (String) - JSONPath-style field path (e.g., `'usage.total_tokens'`, `'messages.*.content'`)
- `as:` (Symbol) - Alias for the selected field (e.g., `:tokens`, `:messages`)

**Behavior:**
- Appends selection to `@_evaluator_config[:selections]` array
- Multiple calls accumulate selections
- Selections processed in order when building evaluator

**Example:**
```ruby
class MyEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'usage.total_tokens', as: :tokens
  select 'usage.prompt_tokens', as: :prompt_tokens
  select 'messages.*.content', as: :messages
end
```

**Storage Format:**
```ruby
@_evaluator_config[:selections] = [
  { path: 'usage.total_tokens', as: :tokens },
  { path: 'usage.prompt_tokens', as: :prompt_tokens },
  { path: 'messages.*.content', as: :messages }
]
```

#### `evaluate_field(name, &block)`

**Purpose:** Configure evaluation for a specific field

**Parameters:**
- `name` (Symbol) - Field name (matches `as:` from `select`)
- `&block` (Block) - Evaluation configuration block (passed to `RAAF::Eval.define`)

**Behavior:**
- Stores block in `@_evaluator_config[:field_evaluations][name]`
- Multiple calls replace previous configuration for same field
- Block executed in context of `RAAF::Eval.define` when building evaluator

**Example:**
```ruby
class MyEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'output', as: :output

  evaluate_field :output do
    evaluate_with :semantic_similarity, threshold: 0.85
    evaluate_with :no_regression
    combine_with :and
  end
end
```

**Storage Format:**
```ruby
@_evaluator_config[:field_evaluations] = {
  output: #<Proc:0x00007f...>
}
```

#### `on_progress(&block)`

**Purpose:** Configure progress callback for evaluation streaming

**Parameters:**
- `&block` (Block) - Progress callback receiving event objects

**Behavior:**
- Stores block in `@_evaluator_config[:progress_callback]`
- Multiple calls replace previous callback
- Block executed when evaluation progress events occur

**Example:**
```ruby
class MyEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  on_progress do |event|
    puts "Progress: #{event.progress}%"
    puts "Status: #{event.status}"
  end
end
```

**Storage Format:**
```ruby
@_evaluator_config[:progress_callback] = #<Proc:0x00007f...>
```

#### `history(**options)`

**Purpose:** Configure historical result tracking

**Parameters:**
- `**options` (Hash) - History configuration options
  - `baseline:` (Boolean) - Enable baseline tracking
  - `last_n:` (Integer) - Number of recent runs to retain
  - `auto_save:` (Boolean) - Automatically save results
  - `retention_days:` (Integer) - Days to retain history
  - `retention_count:` (Integer) - Max number of runs to retain

**Behavior:**
- Stores options in `@_evaluator_config[:history_options]`
- Multiple calls merge options (later calls override earlier)
- Options passed to `RAAF::Eval.define` when building evaluator

**Example:**
```ruby
class MyEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  history baseline: true, last_n: 10, auto_save: true
end
```

**Storage Format:**
```ruby
@_evaluator_config[:history_options] = {
  baseline: true,
  last_n: 10,
  auto_save: true
}
```

### Automatic Method Specifications

#### `evaluator`

**Purpose:** Return cached evaluator or build new one from DSL configuration

**Returns:** `RAAF::Eval::Evaluator` instance

**Behavior:**
- First call: Builds evaluator from `@_evaluator_config` using `build_evaluator_from_config`
- Caches result in `@evaluator` class variable
- Subsequent calls: Returns cached `@evaluator` instance
- Thread-safe (uses class-level instance variable)

**Example:**
```ruby
class MyEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'output', as: :output
  evaluate_field :output do
    evaluate_with :semantic_similarity
  end
end

# First call builds and caches:
eval1 = MyEvaluator.evaluator  # => Builds evaluator

# Subsequent calls return cached:
eval2 = MyEvaluator.evaluator  # => Returns cached

eval1.object_id == eval2.object_id  # => true
```

#### `reset_evaluator!`

**Purpose:** Clear cached evaluator for testing or re-initialization

**Returns:** `nil`

**Behavior:**
- Sets `@evaluator` class variable to `nil`
- Next `evaluator` call rebuilds from DSL configuration
- Essential for test isolation between specs

**Example:**
```ruby
class MyEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'output', as: :output
end

eval1 = MyEvaluator.evaluator
MyEvaluator.reset_evaluator!
eval2 = MyEvaluator.evaluator

eval1.object_id != eval2.object_id  # => true (rebuilt)
```

### Configuration Builder Implementation

#### `build_evaluator_from_config` (Private)

**Purpose:** Construct `RAAF::Eval.define` block from stored DSL configuration

**Returns:** `RAAF::Eval::Evaluator` instance

**Implementation Strategy:**
```ruby
def build_evaluator_from_config
  config = @_evaluator_config

  RAAF::Eval.define do
    # Apply field selections
    config[:selections].each do |selection|
      select selection[:path], as: selection[:as]
    end

    # Apply field evaluations
    config[:field_evaluations].each do |field_name, evaluation_block|
      evaluate_field field_name, &evaluation_block
    end

    # Apply progress callback
    if config[:progress_callback]
      on_progress(&config[:progress_callback])
    end

    # Apply history configuration
    if config[:history_options].any?
      history(**config[:history_options])
    end
  end
end
```

**Key Considerations:**
- Preserve order of selections (array order matters)
- Execute field evaluation blocks in correct context
- Handle nil/empty configurations gracefully
- Validate configuration before building (optional)

## Migration Guide

### Before: Singleton Pattern

```ruby
class ProspectScoring
  class << self
    # Manual cache reset for testing
    def reset_evaluator!
      @evaluator = nil
    end

    # Manual caching with @evaluator ||=
    def evaluator
      @evaluator ||= RAAF::Eval.define do
        # Field selections
        select 'prospect_evaluations', as: :evaluations
        select 'prospect_evaluations.*.criterion_scores', as: :scores
        select 'prospect_evaluations.*.criterion_scores.*.score', as: :individual_scores

        # Field evaluations
        evaluate_field :evaluations do
          evaluate_with :semantic_similarity, threshold: 0.85
          evaluate_with :no_regression
          combine_with :and
        end

        evaluate_field :individual_scores do
          evaluate_with :token_efficiency, max_increase_pct: 15
        end

        # Progress streaming
        on_progress do |event|
          puts "#{event.status}: #{event.progress}%"
        end

        # Historical tracking
        history do
          auto_save true
          baseline true
          retention_count 10
        end
      end
    end
  end
end

# Usage:
ProspectScoring.evaluator      # Access evaluator
ProspectScoring.reset_evaluator!  # Reset for testing
```

**Problems:**
- ❌ 25+ lines of boilerplate (`class << self`, caching, reset)
- ❌ Verbose and awkward `class << self` block
- ❌ Manual cache management with `@evaluator ||=`
- ❌ Manual `reset_evaluator!` implementation
- ❌ Not idiomatic Ruby (different from ActiveRecord, RSpec)

### After: Module DSL Pattern

```ruby
class ProspectScoring
  include RAAF::Eval::DSL::EvaluatorDefinition

  # Field selections
  select 'prospect_evaluations', as: :evaluations
  select 'prospect_evaluations.*.criterion_scores', as: :scores
  select 'prospect_evaluations.*.criterion_scores.*.score', as: :individual_scores

  # Field evaluations
  evaluate_field :evaluations do
    evaluate_with :semantic_similarity, threshold: 0.85
    evaluate_with :no_regression
    combine_with :and
  end

  evaluate_field :individual_scores do
    evaluate_with :token_efficiency, max_increase_pct: 15
  end

  # Progress streaming
  on_progress do |event|
    puts "#{event.status}: #{event.progress}%"
  end

  # Historical tracking
  history baseline: true, retention_count: 10, auto_save: true
end

# Usage (UNCHANGED):
ProspectScoring.evaluator         # Automatic caching
ProspectScoring.reset_evaluator!  # Automatic from module
```

**Benefits:**
- ✅ 70% less code (7 lines vs 25+ lines overhead)
- ✅ Clean, declarative DSL at class level
- ✅ Automatic caching (no manual `@evaluator ||=`)
- ✅ Automatic `reset_evaluator!` (no manual implementation)
- ✅ Idiomatic Ruby (matches ActiveRecord, RSpec patterns)

### Step-by-Step Migration

#### Step 1: Add Module Include

```ruby
class ProspectScoring
  include RAAF::Eval::DSL::EvaluatorDefinition  # ADD THIS

  class << self
    # ... existing code
  end
end
```

#### Step 2: Move DSL Calls to Class Level

```ruby
class ProspectScoring
  include RAAF::Eval::DSL::EvaluatorDefinition

  # MOVE these outside class << self block:
  select 'prospect_evaluations', as: :evaluations
  select 'prospect_evaluations.*.criterion_scores', as: :scores

  evaluate_field :evaluations do
    evaluate_with :semantic_similarity, threshold: 0.85
  end

  on_progress { |e| puts "Progress: #{e.progress}%" }

  history baseline: true, retention_count: 10

  class << self
    # OLD evaluator method still present
  end
end
```

#### Step 3: Remove Singleton Block

```ruby
class ProspectScoring
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'prospect_evaluations', as: :evaluations
  select 'prospect_evaluations.*.criterion_scores', as: :scores

  evaluate_field :evaluations do
    evaluate_with :semantic_similarity, threshold: 0.85
  end

  on_progress { |e| puts "Progress: #{e.progress}%" }

  history baseline: true, retention_count: 10

  # REMOVE entire class << self block - methods now automatic!
end
```

#### Step 4: Update Tests (If Needed)

```ruby
# Tests continue working unchanged!
RSpec.describe ProspectScoring do
  after(:each) do
    ProspectScoring.reset_evaluator!  # Still works!
  end

  it "builds evaluator with correct configuration" do
    evaluator = ProspectScoring.evaluator  # Still works!
    expect(evaluator).to be_a(RAAF::Eval::Evaluator)
  end
end
```

### ProspectsRadar-Specific Migration

#### Finding Evaluator Classes

**Search Pattern:**
```bash
# Find all evaluator classes in prospects_radar
cd prospects_radar
grep -r "class << self" --include="*.rb" | grep "def evaluator"

# Or search for evaluator classes more broadly
grep -r "RAAF::Eval.define" --include="*.rb"
```

**Expected Locations:**
- `app/evaluators/` (if following Rails conventions)
- `lib/evaluators/` (if custom organization)
- `app/services/` (if evaluators are in service layer)
- `spec/support/evaluators/` (test evaluators)

#### Migration Checklist for Each Class

For each evaluator class found:

1. **Backup the original file** (or commit before changes)
2. **Apply the 4-step migration** from above
3. **Run associated tests:**
   ```bash
   bundle exec rspec spec/path/to/evaluator_spec.rb
   ```
4. **Verify in Rails console** (if applicable):
   ```ruby
   # Rails console
   evaluator = MyEvaluator.evaluator
   evaluator.class  # => RAAF::Eval::Evaluator
   ```
5. **Check for any custom methods** that might need adjustment
6. **Update documentation** if class is referenced in CLAUDE.md or README

#### Common ProspectsRadar Patterns

**Pattern 1: Prospect Scoring Evaluators**
```ruby
# BEFORE
class ProspectFitScoring
  class << self
    def evaluator
      @evaluator ||= RAAF::Eval.define do
        select 'prospect_evaluations.*.fit_score', as: :scores
        evaluate_field :scores do
          evaluate_with :no_regression
        end
      end
    end
  end
end

# AFTER
class ProspectFitScoring
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'prospect_evaluations.*.fit_score', as: :scores

  evaluate_field :scores do
    evaluate_with :no_regression
  end
end
```

**Pattern 2: Market Analysis Evaluators**
```ruby
# BEFORE
class MarketScoring
  class << self
    def evaluator
      @evaluator ||= RAAF::Eval.define do
        select 'markets.*.overall_score', as: :scores
        select 'markets.*.scoring', as: :detailed_scoring

        evaluate_field :scores do
          evaluate_with :semantic_similarity, threshold: 0.85
        end
      end
    end
  end
end

# AFTER
class MarketScoring
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'markets.*.overall_score', as: :scores
  select 'markets.*.scoring', as: :detailed_scoring

  evaluate_field :scores do
    evaluate_with :semantic_similarity, threshold: 0.85
  end
end
```

#### Verification After Migration

**Run Full Test Suite:**
```bash
cd prospects_radar
bundle exec rspec
```

**Check for Breaking Changes:**
- Any tests using `ClassName.evaluator` should still work
- Any tests calling `ClassName.reset_evaluator!` should still work
- Evaluator behavior should be identical (just cleaner code)

**Document Migration:**
Add to `prospects_radar/CLAUDE.md`:
```markdown
## Evaluator Definition Pattern (Updated 2025-01-14)

All evaluator classes now use the `RAAF::Eval::DSL::EvaluatorDefinition` module for clean, declarative definitions:

```ruby
class MyEvaluator
  include RAAF::Eval::DSL::EvaluatorDefinition

  select 'field.path', as: :field
  evaluate_field :field do
    evaluate_with :semantic_similarity
  end
end
```

See RAAF Eval documentation for complete DSL reference.
```

## Benefits & Metrics

### Code Reduction

**Measured Benefits:**
- **70% less boilerplate**: Eliminate 18+ lines of singleton method definitions
- **Single include**: Replace entire `class << self` block with one line
- **Zero manual caching**: No `@evaluator ||=` patterns needed
- **Zero manual reset**: No `def reset_evaluator!` method needed

**Example Measurement:**

Before (28 lines total):
- 3 lines: `class << self` + `def reset_evaluator!` + `end`
- 3 lines: `def evaluator` + `@evaluator ||= RAAF::Eval.define do` + `end`
- 20 lines: Actual DSL configuration
- 2 lines: Closing braces

After (21 lines total):
- 1 line: `include RAAF::Eval::DSL::EvaluatorDefinition`
- 20 lines: Actual DSL configuration (unchanged)

**Result: 25% total reduction (28 → 21), but 100% boilerplate elimination (8 → 1)**

### Readability Improvements

- **Declarative**: DSL calls at class level (like ActiveRecord, RSpec)
- **Flat structure**: No nested `class << self` blocks
- **Obvious intent**: Configuration directly visible, not hidden in methods
- **Scannable**: Easy to see all selections and evaluations at a glance

### Maintenance Benefits

- **Single source**: Module handles caching and reset logic
- **Consistent pattern**: Same across all evaluator classes
- **Less error-prone**: No manual cache management mistakes
- **Easier testing**: Built-in `reset_evaluator!` for test isolation

### Developer Experience

- **Familiar patterns**: Matches ActiveRecord, RSpec, Devise conventions
- **Less cognitive load**: No need to understand singleton method pattern
- **Copy-paste friendly**: Configuration is clean and portable
- **Self-documenting**: DSL method names clearly express intent

## Testing Strategy

### Unit Tests for Module

**File:** `eval/spec/raaf/eval/dsl/evaluator_definition_spec.rb`

#### Test 1: Module Inclusion
```ruby
RSpec.describe RAAF::Eval::DSL::EvaluatorDefinition do
  it "extends class with ClassMethods when included" do
    test_class = Class.new do
      include RAAF::Eval::DSL::EvaluatorDefinition
    end

    expect(test_class).to respond_to(:select)
    expect(test_class).to respond_to(:evaluate_field)
    expect(test_class).to respond_to(:on_progress)
    expect(test_class).to respond_to(:history)
    expect(test_class).to respond_to(:evaluator)
    expect(test_class).to respond_to(:reset_evaluator!)
  end

  it "initializes evaluator configuration on inclusion" do
    test_class = Class.new do
      include RAAF::Eval::DSL::EvaluatorDefinition
    end

    config = test_class.instance_variable_get(:@_evaluator_config)
    expect(config).to include(
      selections: [],
      field_evaluations: {},
      progress_callback: nil,
      history_options: {}
    )
  end
end
```

#### Test 2: DSL Methods
```ruby
RSpec.describe "DSL methods" do
  let(:test_class) do
    Class.new do
      include RAAF::Eval::DSL::EvaluatorDefinition
    end
  end

  describe ".select" do
    it "stores field selections" do
      test_class.select 'usage.total_tokens', as: :tokens
      test_class.select 'messages.*.content', as: :messages

      config = test_class.instance_variable_get(:@_evaluator_config)
      expect(config[:selections]).to contain_exactly(
        { path: 'usage.total_tokens', as: :tokens },
        { path: 'messages.*.content', as: :messages }
      )
    end

    it "accumulates multiple selections" do
      test_class.select 'field1', as: :f1
      test_class.select 'field2', as: :f2

      config = test_class.instance_variable_get(:@_evaluator_config)
      expect(config[:selections].count).to eq(2)
    end
  end

  describe ".evaluate_field" do
    it "stores field evaluation blocks" do
      block = -> { evaluate_with :similarity }
      test_class.evaluate_field :output, &block

      config = test_class.instance_variable_get(:@_evaluator_config)
      expect(config[:field_evaluations][:output]).to eq(block)
    end

    it "replaces previous block for same field" do
      test_class.evaluate_field(:output) { evaluate_with :similarity }
      test_class.evaluate_field(:output) { evaluate_with :regression }

      config = test_class.instance_variable_get(:@_evaluator_config)
      expect(config[:field_evaluations].keys).to eq([:output])
    end
  end

  describe ".on_progress" do
    it "stores progress callback" do
      callback = ->(event) { puts event.progress }
      test_class.on_progress(&callback)

      config = test_class.instance_variable_get(:@_evaluator_config)
      expect(config[:progress_callback]).to eq(callback)
    end
  end

  describe ".history" do
    it "stores history configuration options" do
      test_class.history baseline: true, last_n: 10

      config = test_class.instance_variable_get(:@_evaluator_config)
      expect(config[:history_options]).to eq(
        baseline: true,
        last_n: 10
      )
    end

    it "merges multiple history calls" do
      test_class.history baseline: true
      test_class.history last_n: 10, auto_save: true

      config = test_class.instance_variable_get(:@_evaluator_config)
      expect(config[:history_options]).to eq(
        baseline: true,
        last_n: 10,
        auto_save: true
      )
    end
  end
end
```

#### Test 3: Evaluator Caching
```ruby
RSpec.describe "evaluator caching" do
  let(:test_class) do
    Class.new do
      include RAAF::Eval::DSL::EvaluatorDefinition

      select 'output', as: :output
      evaluate_field :output do
        evaluate_with :semantic_similarity
      end
    end
  end

  it "caches evaluator on first call" do
    eval1 = test_class.evaluator
    eval2 = test_class.evaluator

    expect(eval1).to be_a(RAAF::Eval::Evaluator)
    expect(eval1.object_id).to eq(eval2.object_id)
  end

  it "rebuilds evaluator after reset" do
    eval1 = test_class.evaluator
    test_class.reset_evaluator!
    eval2 = test_class.evaluator

    expect(eval1.object_id).not_to eq(eval2.object_id)
  end
end
```

#### Test 4: Configuration Building
```ruby
RSpec.describe "evaluator building from configuration" do
  it "builds evaluator with all field selections" do
    test_class = Class.new do
      include RAAF::Eval::DSL::EvaluatorDefinition

      select 'usage.total_tokens', as: :tokens
      select 'messages.*.content', as: :messages
    end

    evaluator = test_class.evaluator
    expect(evaluator.field_selections).to include(:tokens, :messages)
  end

  it "builds evaluator with field evaluations" do
    test_class = Class.new do
      include RAAF::Eval::DSL::EvaluatorDefinition

      select 'output', as: :output
      evaluate_field :output do
        evaluate_with :semantic_similarity, threshold: 0.85
      end
    end

    evaluator = test_class.evaluator
    # Verify evaluator has field evaluation configured
    # (exact assertion depends on RAAF::Eval internal API)
  end

  it "builds evaluator with progress callback" do
    callback_called = false
    test_class = Class.new do
      include RAAF::Eval::DSL::EvaluatorDefinition

      select 'output', as: :output
      on_progress { |e| callback_called = true }
    end

    evaluator = test_class.evaluator
    # Verify progress callback is registered
  end

  it "builds evaluator with history configuration" do
    test_class = Class.new do
      include RAAF::Eval::DSL::EvaluatorDefinition

      select 'output', as: :output
      history baseline: true, last_n: 10
    end

    evaluator = test_class.evaluator
    # Verify history configuration is applied
  end
end
```

### Integration Tests

**File:** `eval/spec/integration/evaluator_definition_integration_spec.rb`

```ruby
RSpec.describe "Evaluator Definition DSL Integration" do
  it "works end-to-end with real evaluation" do
    evaluator_class = Class.new do
      include RAAF::Eval::DSL::EvaluatorDefinition

      select 'output', as: :output
      evaluate_field :output do
        evaluate_with :semantic_similarity, threshold: 0.85
      end
    end

    # Create test span
    span = create_test_span(output: "Test output content")

    # Evaluate using DSL-defined evaluator
    result = evaluator_class.evaluator.evaluate(span)

    expect(result).to be_a(RAAF::Eval::Result)
    expect(result.field_results).to have_key(:output)
  end

  it "integrates with RSpec evaluation helpers" do
    evaluator_class = Class.new do
      include RAAF::Eval::DSL::EvaluatorDefinition

      select 'output', as: :output
      evaluate_field :output do
        evaluate_with :no_regression
      end
    end

    span = latest_span_for(agent: "TestAgent")
    result = evaluate_span(span, evaluator: evaluator_class.evaluator)

    expect(result).to have_passed_evaluations
  end
end
```

## Implementation Checklist

### Phase 1: Core Module (Day 1)
- [ ] Create `eval/lib/raaf/eval/dsl/evaluator_definition.rb` file
- [ ] Implement `self.included` hook with ClassMethods extension
- [ ] Initialize `@_evaluator_config` class variable in hook
- [ ] Implement `select(path, as:)` method
- [ ] Implement `evaluate_field(name, &block)` method
- [ ] Implement `on_progress(&block)` method
- [ ] Implement `history(**options)` method
- [ ] Implement `evaluator` method with caching
- [ ] Implement `reset_evaluator!` method
- [ ] Implement private `build_evaluator_from_config` method

### Phase 2: Integration (Day 2)
- [ ] Update `eval/lib/raaf/eval/dsl.rb` with autoload
- [ ] Find Scoring class location in RAAF core
- [ ] Migrate Scoring class to use new DSL pattern
- [ ] Verify Scoring class works with new pattern
- [ ] Update any other RAAF core evaluator classes using singleton pattern

### Phase 2b: ProspectsRadar Migration (Day 2-3)
- [ ] Identify all evaluator classes in prospects_radar using singleton pattern
- [ ] Create list of evaluator classes to migrate
- [ ] Migrate each prospects_radar evaluator to new DSL pattern
- [ ] Run tests for each migrated evaluator
- [ ] Verify backward compatibility with existing RSpec tests
- [ ] Document migration in prospects_radar

### Phase 3: Testing (Day 3)
- [ ] Create `eval/spec/raaf/eval/dsl/evaluator_definition_spec.rb`
- [ ] Write module inclusion tests
- [ ] Write DSL method tests (select, evaluate_field, on_progress, history)
- [ ] Write caching tests (evaluator, reset_evaluator!)
- [ ] Write configuration building tests
- [ ] Create integration test file
- [ ] Write end-to-end integration tests
- [ ] Verify all tests pass

### Phase 4: Documentation (Day 4)
- [ ] Update `eval/README.md` with new DSL pattern
- [ ] Add migration guide section
- [ ] Add API reference for all DSL methods
- [ ] Add before/after code examples
- [ ] Update `RAAF_EVAL.md` if exists
- [ ] Update `eval/CLAUDE.md` if exists
- [ ] Create example evaluator files demonstrating pattern

### Phase 5: Review & Polish (Day 5)
- [ ] Code review for module implementation
- [ ] Verify thread safety if needed
- [ ] Performance check for caching mechanism
- [ ] Documentation review for clarity
- [ ] Test coverage verification (aim for 100%)
- [ ] Final integration testing with real evaluators

## Success Criteria

### Functional Requirements
- ✅ Module can be included in evaluator classes
- ✅ All DSL methods work at class level
- ✅ Configuration stored correctly
- ✅ Evaluator built from configuration
- ✅ Caching works correctly
- ✅ Reset works correctly
- ✅ Backward compatible (usage unchanged)

### ProspectsRadar Migration Requirements
- ✅ All prospects_radar evaluator classes migrated to new DSL
- ✅ All prospects_radar tests pass after migration
- ✅ No behavioral changes (only syntax improvements)
- ✅ Migration documented in prospects_radar CLAUDE.md

### Quality Requirements
- ✅ 100% test coverage for module
- ✅ All tests pass
- ✅ Documentation complete and clear
- ✅ Migration guide helps developers
- ✅ Code follows RAAF style guidelines

### Performance Requirements
- ✅ No performance regression vs old pattern
- ✅ Caching provides expected speedup
- ✅ Configuration building is fast (<1ms)

### Developer Experience
- ✅ Pattern feels natural and Ruby-like
- ✅ 70%+ code reduction achieved
- ✅ Easy to migrate from old pattern
- ✅ Clear error messages for misuse

---

**Ready for implementation!**

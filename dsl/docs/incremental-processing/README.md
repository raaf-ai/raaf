# RAAF Incremental Processing Documentation

This directory contains complete documentation for RAAF's incremental processing feature.

## Documentation Files

- **[Usage Guide](raaf-incremental-processing-guide.md)** - Complete DSL reference, examples, and best practices
- **[Migration Guide](migration-guide.md)** - Step-by-step guide to migrate agents to incremental processing
- **[Troubleshooting Guide](troubleshooting-guide.md)** - Common issues, debugging tips, and solutions

## Quick Start

Incremental processing enables agents to skip already-processed records, reducing AI costs by 60-80%:

```ruby
class MyAgent < RAAF::DSL::Agent
  incremental_input_field :companies
  incremental_output_field :enriched_companies

  incremental_processing do
    chunk_size 20

    skip_if { |company| Company.exists?(website: company[:website]) }
    load_existing { |company| Company.find_by(website: company[:website]) }
    persistence_handler { |batch| save_batch(batch) }
  end
end
```

## Features

- **Cost Reduction:** Skip already-processed records (60-80% savings)
- **Memory Efficiency:** Process in configurable batches
- **Crash Resilience:** Persist after each batch
- **Force Reprocess:** Override for testing
- **Complete Data Flow:** Downstream agents receive full datasets

## Installation

Incremental processing is built into RAAF DSL. Simply include it in your agent class:

```ruby
class MyAgent < RAAF::DSL::Agent
  # Your agent automatically has access to incremental processing
end
```

## Architecture

Incremental processing is implemented at the framework level in `RAAF::DSL::Agent`. All agents that inherit from this base class automatically have access to the feature.

**Key Components:**
- `IncrementalConfig` - DSL for configuration
- `IncrementalProcessor` - Core processing logic
- `BatchManager` - Batch iteration and persistence
- `SkipLogic` - Record skipping and existing data loading

**Integration Points:**
- Hooks into agent execution pipeline
- Compatible with AutoMerge for result accumulation
- Works with all RAAF agent types

For complete documentation, see the guides above.

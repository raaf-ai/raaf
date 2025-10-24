# Intelligent Streaming Examples

This directory contains working examples demonstrating various aspects of the RAAF Intelligent Streaming feature.

## Examples Overview

### 1. [Basic Streaming](basic_streaming.rb)
**Difficulty**: Beginner
**Concepts**: Basic configuration, simple progress tracking
Demonstrates the simplest use of intelligent streaming to process 1000 companies through multiple agents with progress updates.

### 2. [State Management](state_management.rb)
**Difficulty**: Intermediate
**Concepts**: skip_if, load_existing, persist_each_stream
Shows how to build resumable pipelines that skip processed items, load cached results, and persist progress.

### 3. [Incremental Delivery](incremental_delivery.rb)
**Difficulty**: Intermediate
**Concepts**: incremental mode, real-time updates, parallel processing
Demonstrates getting results as each stream completes for better user experience and early processing.

### 4. [Cost Optimization](cost_optimization.rb)
**Difficulty**: Advanced
**Concepts**: Filtering funnel, multi-model strategy, cost tracking
Shows how to reduce AI costs by 60-70% using cheap models for filtering before expensive analysis.

### 5. [Error Recovery](error_recovery.rb)
**Difficulty**: Advanced
**Concepts**: Error handling, retry strategies, partial results
Comprehensive example of handling different error types with appropriate recovery strategies.

## Running the Examples

Each example is a standalone Ruby script that can be run directly:

```bash
# Run basic example
ruby basic_streaming.rb

# Run with specific Ruby version
ruby-3.2.0 state_management.rb

# Run with bundle
bundle exec ruby incremental_delivery.rb

# State management example with reset
ruby state_management.rb --clear
```

## Prerequisites

All examples require RAAF to be installed:

```ruby
require 'raaf'
require 'raaf-dsl'
```

Some examples may require additional gems:
- `json` - For JSON operations
- `fileutils` - For file system operations
- `thread` - For threading examples

## Key Patterns Demonstrated

### Memory Efficiency
All examples show how streaming keeps memory usage bounded to O(stream_size) rather than O(n).

### Progress Monitoring
Each example includes progress tracking to show how to monitor pipeline execution.

### State Management
The state management example shows the complete pattern for building resumable, fault-tolerant pipelines.

### Cost Optimization
The cost optimization example demonstrates real-world patterns for reducing AI API costs.

### Error Handling
The error recovery example shows production-ready error handling with retry logic and partial result preservation.

## Common Configuration

Most examples use similar streaming configuration:

```ruby
intelligent_streaming stream_size: 100, incremental: true do
  on_stream_complete { |num, total, data, results|
    # Handle stream completion
  }
end
```

### Stream Size Guidelines

- **Testing/Development**: 10-25 (quick feedback)
- **Production Simple Data**: 100-500 (efficient)
- **Production Complex Data**: 25-100 (balanced)
- **API-heavy Operations**: 10-25 (rate limit friendly)

## Customization

Feel free to modify these examples for your use case:

1. Change `stream_size` to match your data characteristics
2. Add your own state management logic
3. Integrate with your persistence layer
4. Add custom error handling
5. Implement your business logic

## Troubleshooting

### Examples not running?
- Ensure RAAF is properly installed
- Check Ruby version compatibility (3.0+)
- Verify all required gems are available

### Memory issues?
- Reduce stream_size
- Implement persist_each_stream to free memory
- Check for memory leaks in custom logic

### Performance problems?
- Profile to identify bottlenecks
- Adjust stream_size for optimal performance
- Consider parallel processing where appropriate

## Additional Resources

- [Intelligent Streaming API Documentation](../../INTELLIGENT_STREAMING_API.md)
- [Pipeline DSL Guide](../../PIPELINE_DSL_GUIDE.md#intelligent-streaming)
- [Migration Guide](../../INTELLIGENT_STREAMING_MIGRATION.md)
- [Spec README](../../../.agent-os/specs/2025-10-24-agent-level-pipeline-batching/README.md)

## Contributing

When adding new examples:

1. Follow the existing structure and documentation style
2. Include clear comments explaining concepts
3. Show expected output in comments
4. Test the example thoroughly
5. Update this README with the new example
# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-09-24-raaf-tracing-registry/spec.md

> Created: 2025-09-24
> Version: 1.0.0

## Technical Requirements

- Thread-safe ambient context storage using Thread.current and Fiber.current for async support
- Auto-detection logic in RAAF::Runner that checks for registered tracer before defaulting to NoOpTracer
- Update existing Traceable module to integrate with TracingRegistry for automatic tracer discovery
- Pluggable middleware architecture that works with Rails and generic Rack applications
- Zero performance impact when tracing is disabled through NoOpTracer pattern
- Backward compatibility - all existing RAAF code must work unchanged
- Support for nested trace contexts with proper cleanup in ensure blocks
- Framework-agnostic core that has no dependencies on Rails, Sinatra, or other frameworks

## Approach Options

**Option A:** Thread-local storage only
- Pros: Simple implementation, works with most Ruby applications
- Cons: Doesn't support async/fiber-based concurrency

**Option B:** Thread-local + Fiber-local storage with fallback hierarchy (Selected)
- Pros: Supports async operations, fiber-based concurrency, comprehensive coverage
- Cons: Slightly more complex implementation
- Rationale: Modern Ruby applications increasingly use async patterns, and this approach provides the most comprehensive solution while maintaining backward compatibility

**Option C:** Global process-level tracer only
- Pros: Simplest possible implementation
- Cons: No per-request isolation, difficult to correlate traces to specific operations

**Rationale:** Option B provides the best balance of functionality and compatibility, supporting both traditional threaded applications and modern async patterns while maintaining the isolation needed for meaningful traces.

## External Dependencies

- **None** - Implementation uses only Ruby standard library features (Thread, Fiber)
- **Justification:** Keeping ambient tracing dependency-free ensures it can be used in any Ruby environment without conflicts

## Implementation Architecture

### Core Components

1. **RAAF::Tracing::TracingRegistry** - Central tracer registry and context management (in raaf-tracing gem)
2. **RAAF::Tracing::NoOpTracer** - Zero-overhead tracer for disabled tracing (in raaf-tracing gem)
3. **RAAF::Runner modifications** - Auto-detection of registered tracer
4. **RAAF::Tracing::Traceable updates** - Integration with TracingRegistry for automatic discovery
5. **Framework adapters** - Separate gems for specific framework integration

### Context Priority Hierarchy

1. Thread.current[:raaf_tracer] (highest priority)
2. Fiber.current[:raaf_tracer] (async operations)
3. Process-level configured tracer
4. NoOpTracer (default, zero overhead)

### Integration Pattern

```ruby
# Application middleware registers tracer
RAAF::Tracing::TracingRegistry.with_tracer(tracer) do
  # All RAAF operations automatically use this tracer
  yield
end

# RAAF Runner automatically detects and uses registered tracer
runner = RAAF::Runner.new(agent: agent)  # No explicit tracer needed
result = runner.run(input)  # Automatically traced if registry context exists

# Traceable components automatically discover registry tracers
class MyAgent
  include RAAF::Tracing::Traceable

  def run(input)
    traced_run do  # Automatically uses TracingRegistry.current_tracer
      process(input)
    end
  end
end
```

### Traceable Module Integration

The existing `RAAF::Tracing::Traceable` module will be updated to automatically discover TracingRegistry tracers:

**Updated Tracer Discovery Priority:**
1. Instance tracer (`@tracer`)
2. **RAAF::Tracing::TracingRegistry.current_tracer** (NEW)
3. TraceProvider singleton
4. RAAF global tracer
5. NoOpTracer (default)

### Cross-Gem Integration

**raaf-core integration:**
```ruby
# In RAAF::Runner#get_default_tracer
def get_default_tracer
  return nil unless defined?(RAAF::Tracing)

  # Check TracingRegistry first if available
  if defined?(RAAF::Tracing::TracingRegistry)
    registry_tracer = RAAF::Tracing::TracingRegistry.current_tracer
    return registry_tracer if registry_tracer && !registry_tracer.is_a?(RAAF::Tracing::NoOpTracer)
  end

  # Fallback to existing logic
  RAAF::Tracing.tracer
rescue StandardError
  nil
end
```
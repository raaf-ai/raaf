# Unified Step Processing System

This document describes RAAF's unified step processing system that eliminates the brittleness issues in tool and handoff coordination. This is now the default and only processing method in RAAF Core.

## Overview

The unified processing system consolidates step processing into atomic operations, eliminating coordination issues between multiple services. It mirrors Python's `RunImpl.execute_tools_and_side_effects` functionality.

## Key Components

### 1. StepResult (Immutable Data Structure)
```ruby
step_result = StepResult.new(
  original_input: "Hello",
  model_response: {...},
  pre_step_items: [...],
  new_step_items: [...],
  next_step: NextStepRunAgain.new
)

# Check result type
step_result.should_continue?  # true/false
step_result.final_output?     # true/false  
step_result.handoff_occurred? # true/false
```

### 2. ProcessedResponse (Response Categorization)
```ruby
processed = ProcessedResponse.new(
  new_items: [...],
  handoffs: [...],
  functions: [...],
  computer_actions: [...],
  local_shell_calls: [...],
  tools_used: ["get_weather", "transfer_to_agent"]
)

processed.handoffs_detected?      # true/false
processed.tools_or_actions_to_run? # true/false
processed.primary_handoff            # First handoff or nil
```

### 3. ResponseProcessor (Unified Response Processing)
```ruby
processor = ResponseProcessor.new

processed_response = processor.process_model_response(
  response: model_response,
  agent: current_agent,
  all_tools: agent.tools,
  handoffs: agent.handoffs
)
```

### 4. StepProcessor (Atomic Step Execution)
```ruby
processor = StepProcessor.new

step_result = processor.execute_step(
  original_input: "Hello",
  pre_step_items: [],
  model_response: response,
  agent: agent,
  context_wrapper: context,
  runner: runner,
  config: config
)
```

### 5. ToolUseTracker (Centralized Tool Tracking)
```ruby
tracker = ToolUseTracker.new
tracker.add_tool_use(agent, ["get_weather", "send_email"])
tracker.used_tools?(agent)  # true/false
tracker.tools_used_by(agent)    # ["get_weather", "send_email"]
```

## Usage

Unified processing is now the default and only method. The system automatically handles all step processing through the UnifiedStepExecutor:

### Direct Integration
```ruby
# In your runner or custom execution code
unified_executor = RAAF::UnifiedStepExecutor.new(runner: self)

step_result = unified_executor.execute_step(
  model_response: response,
  agent: agent,
  context_wrapper: context,
  config: config
)

case step_result.next_step
when RAAF::NextStepFinalOutput
  return step_result.final_output
when RAAF::NextStepHandoff  
  switch_to_agent(step_result.handoff_agent)
when RAAF::NextStepRunAgain
  continue_conversation
end
```

## Error Handling

The system provides comprehensive error handling:

```ruby
begin
  step_result = processor.execute_step(...)
rescue RAAF::Errors::ModelBehaviorError => e
  # Handle model issues
  puts "Model error: #{e.message}"
rescue RAAF::Errors::ToolExecutionError => e
  # Handle tool failures
  puts "Tool #{e.tool_name} failed: #{e.message}"
rescue RAAF::Errors::HandoffError => e
  # Handle handoff issues
  puts "Handoff failed from #{e.source_agent} to #{e.target_agent}"
end
```

## Benefits Over Legacy System

1. **Atomic Processing**: All response elements processed in single pass
2. **Parallel Tool Execution**: Independent tools run concurrently using Async
3. **Deterministic Flow**: Clear execution order eliminates race conditions
4. **Immutable State**: Prevents mutation bugs that cause brittleness
5. **Comprehensive Error Handling**: Proper error classification and recovery
6. **Single Source of Truth**: Centralized tool tracking and response processing
7. **Type Safety**: Clear data structures with defined interfaces

## Architecture

Unified processing is now the default architecture for all RAAF Core operations:

- **Runner** initializes `UnifiedStepExecutor` automatically
- **StepProcessor** handles all tool and handoff processing atomically  
- **ResponseProcessor** provides single-pass response categorization
- **ToolUseTracker** centralizes tool usage tracking
- Legacy methods are deprecated and marked for removal

## Troubleshooting

### Common Issues

1. **Missing Tool Definitions**
   ```
   Error: Tool 'get_weather' not found in agent MyAgent
   ```
   Ensure all tools are properly registered with the agent.

2. **Handoff Target Not Found**
   ```
   Error: Handoff target 'BillingAgent' not found
   ```
   Ensure handoff targets are properly configured.

3. **JSON Parsing Errors**
   ```
   Error: Failed to parse tool arguments
   ```
   Model is returning malformed JSON for tool arguments.

### Debug Logging
```bash
export RAAF_LOG_LEVEL=debug
export RAAF_DEBUG_CATEGORIES="api,tracing,handoff"
```

### Fallback Safety
The system automatically falls back to legacy processing if unified processing fails, ensuring continuity.

## Performance Considerations

- **Tool Parallelization**: Independent tools execute concurrently
- **Memory Usage**: Immutable data structures use more memory but prevent bugs
- **Latency**: Single-pass response processing reduces coordination overhead
- **Error Recovery**: Comprehensive error handling prevents execution halts

## Future Enhancements

- Stream processing support for real-time responses
- Tool dependency graphs for optimized execution order
- Advanced handoff filtering and transformation
- Metrics collection for performance monitoring
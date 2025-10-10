# Specification: Agent-Level Tool Execution Conveniences

## Goal

Centralize all DSL tool execution conveniences (validation, logging, metadata, duration tracking) into a single interceptor within the DSL::Agent class, eliminating code duplication across individual tool wrappers and enabling raw core tools to receive DSL benefits automatically.

## User Stories

### Story 1: Agent Developer Using Raw Tool
As a RAAF DSL agent developer, I want to use raw core tools directly without creating wrappers so that I can reduce boilerplate and avoid code duplication.

**Acceptance Criteria:**
- Can declare `uses_tool RAAF::Tools::PerplexityTool` in agent
- Tool execution automatically gets validation
- Tool execution automatically gets logging
- Tool results automatically include metadata
- No custom wrapper code required

### Story 2: Framework Maintainer Reducing Duplication
As a RAAF framework maintainer, I want to centralize tool execution conveniences in the agent so that updates to convenience features only require one change.

**Acceptance Criteria:**
- All logging logic in one place (agent interceptor)
- All validation logic in one place (agent interceptor)
- All metadata logic in one place (agent interceptor)
- Can delete redundant DSL tool wrappers
- Updates to interceptor apply to all tools automatically

### Story 3: Tool Developer Creating Core Tools
As a RAAF tool developer, I want to create pure Ruby tools without DSL dependencies so that tools work standalone and with DSL agents.

**Acceptance Criteria:**
- Can create tool with only `call` method
- No need to inherit from DSL base classes
- No need to implement logging
- No need to implement validation
- Tool works with `RAAF::Agent` (standalone)
- Tool works with `RAAF::DSL::Agent` (with conveniences)

## Core Requirements

### Functional Requirements

- **Tool Execution Interceptor**: Override `execute_tool` method in DSL::Agent to wrap all tool executions
- **Automatic Parameter Validation**: Validate tool arguments against tool definition before execution
- **Comprehensive Logging**: Log tool execution start/end with duration, arguments, and results
- **Metadata Injection**: Add execution metadata to tool results (duration, timestamp, tool name)
- **Error Handling**: Catch, log, and re-raise tool execution errors with context
- **Configuration Options**: Allow per-agent configuration of validation, logging, and metadata features
- **Backward Compatibility**: Continue supporting existing DSL tool wrappers without changes

### Non-Functional Requirements

- **Performance**: Interceptor overhead must be < 1ms
- **Thread Safety**: Must handle concurrent tool execution safely
- **Memory Efficiency**: Metadata should not significantly increase result size
- **Maintainability**: Single point of maintenance for all conveniences

## Visual Design

Not applicable - this is a backend architectural change with no visual components.

## Reusable Components

### Existing Code to Leverage

- **Components**:
  - `RAAF::FunctionTool` - Core tool wrapping mechanism
  - `RAAF::DSL::Agent` - Base DSL agent class to extend
  - `RAAF.logger` - Existing logging infrastructure

- **Services**:
  - `RAAF::Perplexity::HttpClient` - Example of shared HTTP client pattern
  - `RAAF::Perplexity::ResultParser` - Example of result formatting

- **Patterns**:
  - Hook system in `RAAF::DSL::Hooks::HookContext` - Similar interceptor pattern
  - Tracing collectors in `RAAF::Tracing::SpanCollectors` - Wrapping execution pattern

### New Components Required

- **Tool Execution Interceptor**: New method override in DSL::Agent
- **Tool Validation Module**: Extract validation logic from DSL tool wrappers
- **Metadata Builder**: Standardized metadata structure builder
- **Configuration DSL**: Tool execution configuration methods

## Technical Approach

### Database
Not applicable - no database changes required.

### API

#### Tool Execution Interceptor
```ruby
module RAAF
  module DSL
    class Agent
      # Override core RAAF's execute_tool method
      def execute_tool(tool, arguments)
        return super unless tool_execution_enabled?

        # BEFORE: Validation & logging
        validate_tool_arguments(tool, arguments) if validation_enabled?
        log_tool_start(tool, arguments) if logging_enabled?
        start_time = Time.now

        # EXECUTE: Call the raw tool
        result = super(tool, arguments)

        # AFTER: Logging & metadata
        duration_ms = calculate_duration(start_time)
        log_tool_end(tool, result, duration_ms) if logging_enabled?
        result = inject_metadata(result, tool, duration_ms) if metadata_enabled?

        result
      rescue StandardError => e
        log_tool_error(tool, e) if logging_enabled?
        raise
      end
    end
  end
end
```

#### Configuration DSL
```ruby
class MyAgent < RAAF::DSL::Agent
  tool_execution do
    enable_validation true     # Validate parameters before execution
    enable_logging true        # Log execution start/end
    enable_metadata true       # Add execution metadata to results
    log_arguments true         # Include arguments in logs
    truncate_logs 100          # Truncate long log values
  end
end
```

### Frontend
Not applicable - backend only change.

### Testing

#### Unit Tests
- Test interceptor with various tool types
- Test configuration options work correctly
- Test error handling and logging
- Test metadata injection
- Test backward compatibility

#### Integration Tests
- Test raw core tools work with DSL agents
- Test existing DSL wrappers continue working
- Test performance overhead is acceptable
- Test thread safety with concurrent execution

## Implementation Details

### Phase 1: Create Tool Execution Interceptor

```ruby
module RAAF
  module DSL
    class Agent
      # Configuration storage
      class_attribute :tool_execution_config, default: {
        enable_validation: true,
        enable_logging: true,
        enable_metadata: true,
        log_arguments: true,
        truncate_logs: 100
      }

      # DSL for configuration
      class << self
        def tool_execution(&block)
          config = ToolExecutionConfig.new(tool_execution_config.dup)
          config.instance_eval(&block)
          self.tool_execution_config = config.to_h
        end
      end

      # Override execute_tool from core RAAF
      def execute_tool(tool, arguments)
        # Check if we should intercept
        return super unless should_intercept_tool?(tool)

        # Pre-execution phase
        perform_pre_execution(tool, arguments)
        start_time = Time.now

        # Execute tool
        result = super(tool, arguments)

        # Post-execution phase
        perform_post_execution(tool, result, start_time)

        result
      rescue StandardError => e
        handle_tool_error(tool, e)
        raise
      end

      private

      def should_intercept_tool?(tool)
        # Don't double-intercept DSL tools that already have conveniences
        !tool.respond_to?(:dsl_wrapped?) || !tool.dsl_wrapped?
      end

      def perform_pre_execution(tool, arguments)
        validate_tool_arguments(tool, arguments) if validation_enabled?
        log_tool_start(tool, arguments) if logging_enabled?
      end

      def perform_post_execution(tool, result, start_time)
        duration_ms = ((Time.now - start_time) * 1000).round(2)

        log_tool_end(tool, result, duration_ms) if logging_enabled?

        if metadata_enabled? && result.is_a?(Hash)
          inject_metadata!(result, tool, duration_ms)
        end
      end
    end
  end
end
```

### Phase 2: Extract Validation Logic

```ruby
module RAAF
  module DSL
    module ToolValidation
      def validate_tool_arguments(tool, arguments)
        return unless tool.respond_to?(:tool_definition)

        definition = tool.tool_definition
        return unless definition && definition[:function]

        required_params = definition[:function][:parameters][:required] || []
        properties = definition[:function][:parameters][:properties] || {}

        # Check required parameters
        required_params.each do |param|
          unless arguments.key?(param.to_sym) || arguments.key?(param.to_s)
            raise ArgumentError, "Missing required parameter: #{param}"
          end
        end

        # Validate parameter types
        arguments.each do |key, value|
          param_def = properties[key.to_s] || properties[key.to_sym]
          next unless param_def

          validate_parameter_type(key, value, param_def)
        end
      end

      private

      def validate_parameter_type(key, value, definition)
        expected_type = definition[:type]

        case expected_type
        when "string"
          unless value.is_a?(String)
            raise ArgumentError, "Parameter #{key} must be a string"
          end
        when "integer"
          unless value.is_a?(Integer)
            raise ArgumentError, "Parameter #{key} must be an integer"
          end
        when "array"
          unless value.is_a?(Array)
            raise ArgumentError, "Parameter #{key} must be an array"
          end
        end
      end
    end
  end
end
```

### Phase 3: Implement Logging

```ruby
module RAAF
  module DSL
    module ToolLogging
      def log_tool_start(tool, arguments)
        tool_name = extract_tool_name(tool)

        RAAF.logger.debug "[TOOL EXECUTION] Starting #{tool_name}"

        if log_arguments?
          args_str = format_arguments(arguments)
          RAAF.logger.debug "[TOOL EXECUTION] Arguments: #{args_str}"
        end
      end

      def log_tool_end(tool, result, duration_ms)
        tool_name = extract_tool_name(tool)

        if result.is_a?(Hash) && result[:success] == false
          RAAF.logger.debug "[TOOL EXECUTION] Failed #{tool_name} (#{duration_ms}ms): #{result[:error]}"
        else
          RAAF.logger.debug "[TOOL EXECUTION] Completed #{tool_name} (#{duration_ms}ms)"
        end
      end

      def log_tool_error(tool, error)
        tool_name = extract_tool_name(tool)

        RAAF.logger.error "[TOOL EXECUTION] Error in #{tool_name}: #{error.message}"
        RAAF.logger.error "[TOOL EXECUTION] Stack trace: #{error.backtrace.first(5).join("\n")}"
      end

      private

      def format_arguments(arguments)
        truncate_length = tool_execution_config[:truncate_logs] || 100

        arguments.map do |key, value|
          value_str = value.to_s
          value_str = value_str.truncate(truncate_length) if value_str.length > truncate_length
          "#{key}: #{value_str}"
        end.join(", ")
      end
    end
  end
end
```

### Phase 4: Metadata Injection

```ruby
module RAAF
  module DSL
    module ToolMetadata
      def inject_metadata!(result, tool, duration_ms)
        metadata = {
          _execution_metadata: {
            duration_ms: duration_ms,
            tool_name: extract_tool_name(tool),
            timestamp: Time.now.iso8601,
            agent_name: self.class.agent_name
          }
        }

        result.merge!(metadata)
      end

      private

      def extract_tool_name(tool)
        if tool.respond_to?(:tool_name)
          tool.tool_name
        elsif tool.respond_to?(:name)
          tool.name
        elsif tool.is_a?(RAAF::FunctionTool)
          tool.instance_variable_get(:@name) || "unknown_tool"
        else
          tool.class.name.split("::").last.underscore
        end
      end
    end
  end
end
```

## Migration Guide

### Step 1: Update Agent Class

```ruby
# Before: Using DSL wrapper
class MyAgent < RAAF::DSL::Agent
  uses_tool :perplexity_search  # Uses 200+ line wrapper
end

# After: Using raw core tool
class MyAgent < RAAF::DSL::Agent
  uses_tool RAAF::Tools::PerplexityTool, as: :perplexity_search

  # Optional: Configure execution behavior
  tool_execution do
    enable_validation true
    enable_logging true
    enable_metadata true
  end
end
```

### Step 2: Test Functionality

```ruby
# Verify same behavior
agent = MyAgent.new
result = agent.execute_tool(tool, query: "Ruby news")

# Should have:
# - Automatic validation
# - Execution logging
# - Duration tracking
# - Metadata in result
```

### Step 3: Remove Wrapper (Optional)

Once verified working, the DSL tool wrapper can be deleted or simplified to just delegate to core tool.

## Tool Registry for Short Names (Using Existing Registry)

### Requirement: Symbolic Tool Names

**Enable agents to use short symbolic names instead of full class references using the existing `RAAF::DSL::Tools::ToolRegistry`:**

```ruby
# Short symbolic name (preferred)
class MyAgent < RAAF::DSL::Agent
  uses_tool :perplexity  # Auto-discovers RAAF::Tools::PerplexityTool via registry
end

# Full class reference (still supported)
class MyAgent < RAAF::DSL::Agent
  uses_tool RAAF::Tools::PerplexityTool, as: :perplexity
end
```

### Existing ToolRegistry (Already Implemented)

RAAF DSL already has a comprehensive `RAAF::DSL::Tools::ToolRegistry` with:

- **Auto-discovery**: Automatically finds tools in registered namespaces (`RAAF::Tools`, `RAAF::DSL::Tools`, `Ai::Tools`)
- **Symbol lookup**: Fast O(1) lookup by symbolic names
- **Fuzzy matching**: Suggests similar tool names for typos using Levenshtein distance
- **Thread-safe**: Uses `Concurrent::Hash` for thread-safe operations
- **Statistics**: Tracks lookups, cache hits, discoveries for performance monitoring
- **Namespace support**: Supports multiple tool namespaces

**Location**: `dsl/lib/raaf/dsl/tools/tool_registry.rb`

### Existing Auto-Registration

The registry is already initialized with default namespaces:

```ruby
# Already configured in ToolRegistry
register_namespace("RAAF::DSL::Tools")
register_namespace("RAAF::Tools")
register_namespace("Ai::Tools")
```

Tools are automatically discovered when looked up via `ToolRegistry.get(:tool_name)`.

### Enhanced `uses_tool` Method (Integration with Existing Registry)

```ruby
module RAAF
  module DSL
    class Agent
      class << self
        def uses_tool(tool_identifier, as: nil, **options)
          # Case 1: Symbol - lookup in existing ToolRegistry
          if tool_identifier.is_a?(Symbol)
            tool_class = RAAF::DSL::Tools::ToolRegistry.get(tool_identifier)

            tool_name = as || tool_identifier
            add_tool_from_class(tool_class, tool_name, options)

          # Case 2: Class - use directly
          elsif tool_identifier.is_a?(Class)
            tool_name = as || infer_tool_name(tool_identifier)
            add_tool_from_class(tool_identifier, tool_name, options)

          # Case 3: Tool instance - use as-is
          else
            add_tool(tool_identifier)
          end
        end

        private

        def add_tool_from_class(tool_class, tool_name, options)
          tool_instance = tool_class.new(**options)
          function_tool = RAAF::FunctionTool.new(
            tool_instance.method(:call),
            name: tool_name.to_s,
            description: tool_instance.description rescue "Tool: #{tool_name}"
          )
          add_tool(function_tool)
        end

        def infer_tool_name(tool_class)
          tool_class.name.split("::").last.underscore.gsub(/_tool$/, '').to_sym
        end
      end
    end
  end
end
```

### Usage Examples

```ruby
# Example 1: Short symbolic name (auto-discovered)
class MyAgent < RAAF::DSL::Agent
  uses_tool :perplexity  # Finds RAAF::Tools::PerplexityTool
end

# Example 2: Short name with options
class MyAgent < RAAF::DSL::Agent
  uses_tool :perplexity,
    model: "sonar-pro",
    timeout: 60
end

# Example 3: Short name with custom alias
class MyAgent < RAAF::DSL::Agent
  uses_tool :perplexity, as: :web_search
end

# Example 4: Full class reference (still works)
class MyAgent < RAAF::DSL::Agent
  uses_tool RAAF::Tools::PerplexityTool, as: :perplexity_search
end

# Example 5: Custom tool registration
RAAF::DSL::ToolRegistry.register(:my_custom_tool, MyCustomTool)

class MyAgent < RAAF::DSL::Agent
  uses_tool :my_custom_tool
end
```

### Auto-Registered Core Tools

When RAAF DSL loads, these tools are automatically registered:

| Symbol | Tool Class | Description |
|--------|-----------|-------------|
| `:perplexity` | `RAAF::Tools::PerplexityTool` | Web search with citations |
| `:tavily` | `RAAF::Tools::TavilySearch` | Alternative web search |
| `:file_search` | `RAAF::Tools::FileSearchTool` | Local file operations |
| `:code_interpreter` | `RAAF::Tools::CodeInterpreterTool` | Code execution |
| `:web_page_fetch` | `RAAF::Tools::API::WebPageFetch` | Fetch web pages |

### Custom Tool Registration

```ruby
# In your application initialization
module MyApp
  class CustomSearchTool
    def call(query:)
      # Custom implementation
    end

    def description
      "Custom search functionality"
    end
  end
end

# Register at boot
RAAF::DSL::ToolRegistry.register(:custom_search, MyApp::CustomSearchTool)

# Use in agents
class MyAgent < RAAF::DSL::Agent
  uses_tool :custom_search
end
```

## Out of Scope

- Tool definition generation (schema auto-generation)
- Advanced schema validation beyond type checking
- Tool result caching
- Tool composition/chaining
- Async tool execution

## Success Criteria

1. **Code Reduction**: 200+ line DSL wrappers can be eliminated
2. **Single Update Point**: Changes to conveniences require only interceptor updates
3. **Raw Tool Support**: Core tools work with DSL agents without wrappers
4. **Performance**: < 1ms interceptor overhead verified by benchmarks
5. **Backward Compatibility**: All existing DSL tool wrappers continue working
6. **Test Coverage**: 100% coverage of interceptor functionality
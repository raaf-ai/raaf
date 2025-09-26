# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-09-26-span-collector-extraction/spec.md

> Created: 2025-09-26
> Version: 1.0.0

## Technical Requirements

- Create a collector class hierarchy that extracts span data from traceable components
- Collectors must handle both initial attributes and result-based attributes
- Naming-based discovery must automatically select the correct collector based on component class name
- Traceable module must delegate all data collection to collectors
- All existing span data must continue to be collected exactly as before
- Remove all collection methods from business classes after migration
- Provide a simple DSL for collectors to declaratively specify what data to extract from components

## Approach Options

**Option A: Visitor Pattern**
- Pros: Classic OO pattern, well understood, type-safe
- Cons: Requires components to accept visitors, still couples classes

**Option B: External Collector Classes** (Selected)
- Pros: Complete separation of concerns, no coupling, easier to test independently
- Cons: Collectors need to know internal structure of components

**Option C: Aspect-Oriented Programming**
- Pros: Very clean separation, declarative
- Cons: Adds complexity, requires AOP framework, harder to debug

**Rationale:** External collector classes provide the cleanest separation without requiring components to know about collectors at all. This approach allows us to completely decouple tracing concerns from business logic.

## Implementation Details

### Simplified DSL Base Collector Class with Common Attributes
```ruby
module RAAF
  module Tracing
    module SpanCollectors
      class BaseCollector
        def self.span(*attrs, **custom)
          (@span_attrs ||= []).concat(attrs)
          (@span_custom ||= {}).merge!(custom)
        end

        def self.result(**custom)
          (@result_custom ||= {}).merge!(custom)
        end

        def collect_attributes(component)
          # Start with common base attributes for all components
          attrs = base_attributes(component)

          # Add component-specific attributes
          attrs.merge!(custom_attributes(component))
          attrs
        end

        def collect_result(component, result)
          # Start with common base result attributes for all components
          attrs = base_result_attributes(result)

          # Add component-specific result attributes
          attrs.merge!(custom_result_attributes(component, result))
          attrs
        end

        protected

        # Common attributes automatically added to ALL components
        def base_attributes(component)
          {
            "component.type" => component_prefix,
            "component.class" => component.class.name
          }
        end

        # Common result attributes automatically added to ALL results
        def base_result_attributes(result)
          {
            "result.type" => result.class.name,
            "result.success" => !result.nil?
          }
        end

        # Component-specific attributes using DSL - override in subclasses
        def custom_attributes(component)
          attrs = {}
          prefix = component_prefix

          # Simple attributes - direct method calls
          self.class.instance_variable_get(:@span_attrs)&.each do |attr|
            attrs["#{prefix}.#{attr}"] = safe_value(component.send(attr))
          end

          # Custom attributes with lambda blocks
          self.class.instance_variable_get(:@span_custom)&.each do |key, block|
            value = component.instance_eval(&block)
            attrs["#{prefix}.#{key}"] = safe_value(value)
          end

          attrs
        end

        # Component-specific result attributes - override in subclasses
        def custom_result_attributes(component, result)
          attrs = {}
          self.class.instance_variable_get(:@result_custom)&.each do |key, block|
            value = block.call(result, component)
            attrs["result.#{key}"] = safe_value(value)
          end
          attrs
        end

        def component_prefix
          self.class.name.downcase.gsub(/collector$/, '')
        end

        def safe_value(value)
          case value
          when String, Numeric, TrueClass, FalseClass then value
          when Array then value.map { |v| safe_value(v) }[0..9] # Limit array size
          when Hash then value.transform_values { |v| safe_value(v) }
          when nil then nil
          else value.to_s
          end
        end
      end
    end
  end
end
```

### Naming-Based Collector Discovery
```ruby
module RAAF
  module Tracing
    module SpanCollectors
      def self.collector_for(component)
        class_name = component.class.name

        # Handle specific agent types with different data requirements
        case class_name
        when "RAAF::DSL::Agent"
          return DSL::AgentCollector.new
        when "RAAF::Agent"
          return AgentCollector.new
        end

        # Standard naming convention for other components
        collector_name = "#{class_name.split('::').last}Collector"
        if const_defined?(collector_name)
          const_get(collector_name).new
        else
          # Pattern-based fallback
          base_name = class_name.split('::').last
          return ToolCollector.new if base_name.end_with?('Tool')
          return PipelineCollector.new if base_name.end_with?('Pipeline')
          return JobCollector.new if base_name.end_with?('Job')

          # Ultimate fallback
          BaseCollector.new
        end
      end
    end
  end
end
```

### Integration with Traceable
The Traceable module will be updated to use naming-based discovery:
```ruby
def collect_span_attributes
  collector = RAAF::Tracing::SpanCollectors.collector_for(self)
  collector.collect_attributes(self)
end

def collect_result_attributes(result)
  collector = RAAF::Tracing::SpanCollectors.collector_for(self)
  collector.collect_result(self, result)
end
```

## File Structure

```
tracing/lib/raaf/tracing/
├── span_collectors/
│   ├── base_collector.rb
│   ├── agent_collector.rb        # Core RAAF::Agent
│   ├── tool_collector.rb
│   ├── pipeline_collector.rb
│   ├── job_collector.rb
│   └── dsl/
│       └── agent_collector.rb    # RAAF::DSL::Agent
└── traceable.rb (modified)
```

## Simplified DSL Data Extraction Examples

### Core Agent Collector Example
```ruby
class AgentCollector < BaseCollector
  # Only agent-specific attributes - BaseCollector handles common ones
  span :name, :model

  # Custom extraction with lambdas
  span max_turns: -> { max_turns.to_s }
  span tools_count: -> { tools.length.to_s }
  span handoffs_count: -> { handoffs.length.to_s }

  # Complex conditional logic
  span workflow_name: -> do
    job_span = Thread.current[:raaf_job_span]
    job_span&.class&.name
  end

  # DSL metadata if available
  span dsl_metadata: -> do
    if respond_to?(:trace_metadata) && trace_metadata&.any?
      trace_metadata.map { |k, v| "#{k}:#{v}" }.join(",")
    end
  end

  # No need to define result.type or result.success - BaseCollector provides these automatically!
end
```

### DSL Agent Collector Example
```ruby
module DSL
  class AgentCollector < BaseCollector
  # Only DSL-specific data sources - BaseCollector handles common ones
  span name: -> { agent_name }
  span model: -> { self.class._context_config[:model] || "gpt-4o" }
  span max_turns: -> { (self.class._context_config[:max_turns] || 5).to_s }

  # DSL-specific fields
  span temperature: -> { self.class._context_config[:temperature] }
  span context_size: -> { (@context&.size || 0).to_s }
  span has_tools: -> { (@context && @context.size > 0) || false }
  span execution_mode: -> { has_smart_features? ? "smart" : "direct" }

  # Include core agent data when available
  span tools_count: -> { respond_to?(:tools) ? tools.length.to_s : "0" }
  span handoffs_count: -> { respond_to?(:handoffs) ? handoffs.length.to_s : "0" }

  # No need to define result.type or result.success - BaseCollector provides these automatically!
  end
end
```

### Tool Collector Example
```ruby
class ToolCollector < BaseCollector
  # Only tool-specific identification - BaseCollector handles common ones
  span name: -> { self.class.name }
  span method: -> { @method_name&.to_s || "unknown" }

  # Agent context detection
  span agent_context: -> do
    if respond_to?(:detect_agent_context)
      detect_agent_context&.class&.name
    end
  end

  # Only tool-specific result data - BaseCollector provides result.type and result.success
  result execution_result: -> { _1.to_s[0..100] }
end
```

### Pipeline Collector Example
```ruby
class PipelineCollector < BaseCollector
  # Only pipeline-specific attributes - BaseCollector handles common ones
  span name: -> { pipeline_name }
  span flow_structure: -> { flow_structure_description(@flow) }
  span agent_count: -> { count_agents_in_flow(@flow) }
  span context_fields: -> { self.class.context_fields || [] }

  # Only pipeline-specific result data - BaseCollector provides result.type and result.success
  result execution_status: -> { _1[:success] ? "success" : "failure" }
end
```

### Job Collector Example
```ruby
class JobCollector < BaseCollector
  # Only job-specific attributes - BaseCollector handles common ones
  span queue: -> { respond_to?(:queue_name) ? queue_name : "default" }
  span arguments: -> do
    if respond_to?(:arguments)
      arguments.inspect[0..100] # Truncate long arguments
    else
      "N/A"
    end
  end

  # Only job-specific result data - BaseCollector provides result.type and result.success
  result status: -> { _1.respond_to?(:status) ? _1.status : "unknown" }
end
```

## Simplified DSL Benefits

- **Concise**: Much less code than verbose DSL approach
- **Clear**: Easy to see what data gets collected at a glance
- **Familiar**: Uses standard Ruby lambda syntax
- **Flexible**: Handles both simple method calls and complex logic
- **Performant**: Efficient lambda execution
- **Maintainable**: Easy to add, remove, or modify attributes
- **Testable**: Each lambda can be tested independently
- **Convention Over Configuration**: No manual registration, pure naming-based discovery
- **Specialized**: Separate collectors for Core and DSL agents capture their unique data
- **No Duplication**: BaseCollector automatically provides common attributes (component.type, component.class, result.type, result.success) so individual collectors only define their specific data

## External Dependencies

None required - this is a pure refactoring using only Ruby standard library features.
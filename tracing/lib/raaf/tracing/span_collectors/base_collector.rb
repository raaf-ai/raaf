# frozen_string_literal: true

module RAAF
  module Tracing
    module SpanCollectors
      # Base collector class that provides the foundation for all RAAF tracing span collectors.
      # This class implements a powerful DSL for extracting attributes from traced components
      # and provides automatic serialization, safety, and integration with the RAAF tracing system.
      #
      # @abstract Subclass and define span attributes using the DSL methods
      #
      # @example Simple collector with direct attributes
      #   class AgentCollector < BaseCollector
      #     span :name, :model  # Extract these attributes directly
      #   end
      #
      # @example Advanced collector with custom extraction logic
      #   class AgentCollector < BaseCollector
      #     span :name, :model
      #     span tools_count: ->(comp) { comp.tools.length }
      #     span complex_data: ->(comp) do
      #       {
      #         total_handoffs: comp.handoffs.count,
      #         execution_mode: comp.smart? ? "smart" : "basic"
      #       }
      #     end
      #
      #     result execution_time: ->(result, comp) { result.duration }
      #   end
      #
      # @example Usage in tracing system
      #   collector = AgentCollector.new
      #   attributes = collector.collect_attributes(my_agent)
      #   result_attrs = collector.collect_result(my_agent, execution_result)
      #
      # @see RAAF::Tracing::SpanTracer How collectors integrate with the main tracer
      # @see AgentCollector Example of comprehensive dialog and metadata collection
      # @see ToolCollector Example of tool-specific attribute extraction
      #
      # @since 1.0.0
      # @author RAAF Team
      class BaseCollector
        # DSL class method to register simple span attributes and custom extractors.
        # This method supports both direct attribute extraction and complex custom logic
        # using lambda functions.
        #
        # @param attrs [Array<Symbol>] Simple attribute names to extract directly from component
        # @param custom [Hash<Symbol, Proc>] Custom attributes with lambda extractors
        #
        # @example Direct attribute extraction
        #   span :name, :model, :temperature  # Calls comp.name, comp.model, comp.temperature
        #
        # @example Custom lambda extractors
        #   span tools_count: ->(comp) { comp.tools.length }
        #   span metadata: ->(comp) { comp.trace_metadata || {} }
        #
        # @example Complex conditional logic
        #   span execution_mode: ->(comp) do
        #     if comp.respond_to?(:smart_features?) && comp.smart_features?
        #       "smart"
        #     else
        #       "basic"
        #     end
        #   end
        #
        # @note Lambda extractors can take 0, 1, or more arguments:
        #   - 0 args: Executed in component context (comp.instance_eval)
        #   - 1 arg: Component passed as parameter
        #   - 2+ args: Component passed as first parameter
        #
        # @return [void]
        def self.span(*attrs, **custom)
          (@span_attrs ||= []).concat(attrs)
          (@span_custom ||= {}).merge!(custom)
        end

        # DSL class method to register result-based attributes that are extracted
        # after component execution completes. These attributes have access to both
        # the component and its execution result.
        #
        # @param custom [Hash<Symbol, Proc>] Custom result attributes with lambda extractors
        #
        # @example Basic result extraction
        #   result execution_time: ->(result, comp) { result.duration }
        #   result status: ->(result, comp) { result.success? ? "success" : "failure" }
        #
        # @example Complex result analysis
        #   result performance_metrics: ->(result, comp) do
        #     {
        #       tokens_used: result.usage&.total_tokens || 0,
        #       response_time: result.response_time,
        #       model_used: comp.model
        #     }
        #   end
        #
        # @note Result lambdas MUST accept exactly 2 parameters: (result, component)
        #
        # @return [void]
        def self.result(**custom)
          (@result_custom ||= {}).merge!(custom)
        end

        # Collect all span attributes for a component by combining base attributes
        # with component-specific attributes defined via the DSL. This method is called
        # by the tracing system when a span is created.
        #
        # @param component [Object] The component being traced (agent, tool, pipeline, etc.)
        # @return [Hash<String, Object>] Combined attributes for the span with string keys
        #
        # @example Typical usage in tracing system
        #   collector = AgentCollector.new
        #   attributes = collector.collect_attributes(my_agent)
        #   # => {
        #   #   "component.type" => "agent",
        #   #   "component.name" => "RAAF::Agent",
        #   #   "agent.name" => "Assistant",
        #   #   "agent.model" => "gpt-4o",
        #   #   "agent.tools_count" => "3"
        #   # }
        #
        # @note All attribute values are processed through safe_value() for serialization
        # @see #base_attributes Common attributes added to all components
        # @see #custom_attributes Component-specific attributes from DSL
        def collect_attributes(component)
          # Start with common base attributes for all components
          attrs = base_attributes(component)

          # Add component-specific attributes
          attrs.merge!(custom_attributes(component))
          attrs
        end

        # Collect result-based attributes for a component and its execution result.
        # This method is called by the tracing system when a span completes, providing
        # access to both the original component and its execution result.
        #
        # @param component [Object] The component being traced
        # @param result [Object] The result from the component execution
        # @return [Hash<String, Object>] Combined result attributes for the span
        #
        # @example Typical usage in tracing system
        #   collector = AgentCollector.new
        #   result_attrs = collector.collect_result(my_agent, execution_result)
        #   # => {
        #   #   "result.type" => "RAAF::Response",
        #   #   "result.success" => true,
        #   #   "result.execution_time" => "1.5s",
        #   #   "result.tokens_used" => "150"
        #   # }
        #
        # @note This method combines base result attributes with custom result attributes
        # @see #base_result_attributes Common result attributes for all components
        # @see #custom_result_attributes Component-specific result attributes from DSL
        def collect_result(component, result)
          # Start with common base result attributes for all components
          attrs = base_result_attributes(result)

          # Add component-specific result attributes
          attrs.merge!(custom_result_attributes(component, result))
          attrs
        end

        protected

        # Common attributes automatically added to ALL components
        #
        # @param component [Object] The component being traced
        # @return [Hash] Base attributes common to all components
        def base_attributes(component)
          {
            "component.type" => component_type(component),
            "component.name" => component.class.name
          }
        end

        # Common result attributes automatically added to ALL results
        #
        # @param result [Object] The result from component execution
        # @return [Hash] Base result attributes common to all results
        def base_result_attributes(result)
          {
            "result.type" => result.class.name,
            "result.success" => !result.nil?
          }
        end

        # Component-specific attributes using DSL - override in subclasses
        #
        # @param component [Object] The component being traced
        # @return [Hash] Custom attributes for the specific component
        def custom_attributes(component)
          attrs = {}
          prefix = component_prefix

          # Simple attributes - direct method calls
          self.class.instance_variable_get(:@span_attrs)&.each do |attr|
            attrs["#{prefix}.#{attr}"] = safe_value(component.send(attr))
          end

          # Custom attributes with lambda blocks
          self.class.instance_variable_get(:@span_custom)&.each do |key, block|
            value = if block.arity == 0
                      # No-argument lambdas should be evaluated in component context
                      component.instance_eval(&block)
                    elsif block.arity == 1
                      # Single-argument lambdas get the component as parameter
                      block.call(component)
                    else
                      # Multi-argument lambdas should not be used, but call with component anyway
                      block.call(component)
                    end
            attrs["#{prefix}.#{key}"] = safe_value(value)
          end

          attrs
        end

        # Component-specific result attributes - override in subclasses
        #
        # @param component [Object] The component being traced
        # @param result [Object] The result from component execution
        # @return [Hash] Custom result attributes for the specific component
        def custom_result_attributes(component, result)
          attrs = {}
          self.class.instance_variable_get(:@result_custom)&.each do |key, block|
            value = block.call(result, component)
            attrs["result.#{key}"] = safe_value(value)
          end
          attrs
        end

        # Get component type from the component itself
        #
        # @param component [Object] The component being traced
        # @return [String] Component type for span classification
        def component_type(component)
          if component.class.respond_to?(:trace_component_type)
            component.class.trace_component_type.to_s
          else
            # Fallback to inferring from class name
            infer_component_type(component.class.name)
          end
        end

        # Infer component type from class name
        #
        # @param class_name [String] The name of the component class
        # @return [String] Inferred component type
        def infer_component_type(class_name)
          return "unknown" unless class_name

          case class_name
          when /Agent$/ then "agent"
          when /Pipeline$/ then "pipeline"
          when /Runner$/ then "runner"
          when /Tool$/ then "tool"
          when /Job$/ then "job"
          else "component"
          end
        end

        # Generate component prefix from collector class name
        #
        # @return [String] Component prefix for attribute namespacing
        def component_prefix
          class_name = self.class.name
          return "unknown" unless class_name

          # Extract just the component type (e.g., "agent", "llm", "tool")
          # from class names like "RAAF::Tracing::SpanCollectors::AgentCollector"
          component_type = class_name.split("::").last&.downcase&.gsub(/collector$/, '')
          component_type || "unknown"
        end

        # Convert values to safe formats for span attributes by recursively processing
        # complex objects and preventing infinite recursion or serialization issues.
        # This method ensures that all span attributes can be safely serialized and
        # transmitted to tracing backends.
        #
        # @param value [Object] Value to make safe for tracing
        # @param max_depth [Integer] Maximum nesting depth for complex objects
        # @return [Object] Safe representation of the value
        #
        # @example Handling different value types
        #   safe_value("hello")           # => "hello"
        #   safe_value(42)               # => 42
        #   safe_value([1, 2, 3])        # => [1, 2, 3]
        #   safe_value({a: 1, b: 2})     # => {"a" => 1, "b" => 2}
        #
        # @example Complex object handling
        #   safe_value(ActiveRecord.new)  # => {"id" => 1, "name" => "test"}
        #   safe_value(CustomObject.new)  # => "#<CustomObject:0x123> (CustomObject)"
        #
        # @note Arrays are limited to first 20 elements to prevent huge serializations
        # @note Complex objects are processed via to_h, as_json, or attributes if available
        # @note Infinite recursion is prevented via max_depth limiting
        def safe_value(value, max_depth: 5)
          safe_value_recursive(value, depth: 0, max_depth: max_depth)
        end

        private

        # Recursively process values with depth tracking
        #
        # @param value [Object] Value to process
        # @param depth [Integer] Current nesting depth
        # @param max_depth [Integer] Maximum allowed depth
        # @return [Object] Safe representation of the value
        def safe_value_recursive(value, depth:, max_depth:)
          # Prevent infinite recursion
          return "[Max depth reached]" if depth > max_depth

          case value
          when String, Numeric, TrueClass, FalseClass, NilClass
            value
          when Array
            # Limit array size and recursively process elements
            value.first(20).map { |v| safe_value_recursive(v, depth: depth + 1, max_depth: max_depth) }
          when Hash
            # Recursively process hash values
            safe_hash = {}
            value.each do |k, v|
              safe_key = k.to_s
              safe_hash[safe_key] = safe_value_recursive(v, depth: depth + 1, max_depth: max_depth)
            end
            safe_hash
          else
            # Handle complex objects
            if value.respond_to?(:to_h)
              safe_value_recursive(value.to_h, depth: depth + 1, max_depth: max_depth)
            elsif value.respond_to?(:as_json)
              safe_value_recursive(value.as_json, depth: depth + 1, max_depth: max_depth)
            elsif value.respond_to?(:attributes)
              # Handle ActiveRecord and similar objects
              safe_value_recursive(value.attributes, depth: depth + 1, max_depth: max_depth)
            else
              # Fallback to string representation with class info
              "#{value.to_s} (#{value.class.name})"
            end
          end
        rescue => e
          # Fallback if processing fails
          "[Serialization error: #{e.message}]"
        end
      end

      # Module-level discovery methods for automatic collector selection
      module_function

      # Find the appropriate collector for a component using intelligent naming-based
      # discovery. This method analyzes the component's class hierarchy and name patterns
      # to select the most specific collector available.
      #
      # @param component [Object] Component to find collector for (agent, tool, pipeline, etc.)
      # @return [BaseCollector] Collector instance specialized for the component type
      #
      # @example Automatic collector selection
      #   agent = RAAF::Agent.new(name: "Assistant")
      #   collector = SpanCollectors.collector_for(agent)
      #   # => #<SpanCollectors::AgentCollector>
      #
      #   tool = MyCustomTool.new
      #   collector = SpanCollectors.collector_for(tool)
      #   # => #<SpanCollectors::ToolCollector>
      #
      # @note Special handling for DSL::Agent vs core Agent classes
      # @note Falls back to BaseCollector for unknown component types
      # @see AgentCollector For RAAF::Agent components with comprehensive dialog collection
      # @see DSL::AgentCollector For RAAF::DSL::Agent components with context metadata
      # @see ToolCollector For tool execution tracing
      # @see PipelineCollector For multi-agent pipeline orchestration
      def self.collector_for(component)
        class_name = component.class.name

        # Special case for DSL agents - check DSL::Agent class hierarchy
        if class_name == "RAAF::DSL::Agent" || (component.class.ancestors.map(&:name).include?("RAAF::DSL::Agent"))
          return DSL::AgentCollector.new
        end

        # Core agent handling
        if class_name == "RAAF::Agent" || (component.class.ancestors.map(&:name).include?("RAAF::Agent"))
          return AgentCollector.new
        end

        # Pattern-based matching for other components
        case class_name
        when /Tool$/
          ToolCollector.new
        when /Pipeline$/
          PipelineCollector.new
        when /Job$/
          JobCollector.new
        else
          # Fallback to base collector for unknown types
          BaseCollector.new
        end
      end
    end
  end
end

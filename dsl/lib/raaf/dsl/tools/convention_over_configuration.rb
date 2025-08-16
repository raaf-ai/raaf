# frozen_string_literal: true

require_relative 'performance_optimizer'
require_relative 'tool_registry'

# ConventionOverConfiguration module for RAAF DSL Tools
#
# This module provides automatic generation of tool metadata based on class names,
# method signatures, and Ruby conventions. It reduces boilerplate by auto-generating
# common tool properties like name, description, and tool definitions.
#
# Enhanced with performance optimizations and auto-discovery features:
# - Caching for discovered tool classes to avoid repeated discovery
# - Fuzzy matching for tool names with helpful error messages
# - Tool validation at agent initialization time
# - Thread-safe cached tool lookups
#
# The module analyzes the tool class at load time and caches the generated metadata
# for performance. It follows Ruby naming conventions and introspects method
# signatures to build OpenAI-compatible tool definitions.
#
# @example Basic usage
#   class WeatherTool < RAAF::DSL::Tools::Tool
#     include ConventionOverConfiguration
#     
#     # Auto-generates: name="weather", description="Tool for weather operations"
#     def call(city:, country: "US")
#       # Implementation
#     end
#   end
#
# @example Custom overrides
#   class AdvancedSearchTool < RAAF::DSL::Tools::Tool
#     include ConventionOverConfiguration
#     
#     # Override auto-generated values
#     configure name: "semantic_search",
#               description: "Perform semantic search across documents"
#     
#     def call(query:, limit: 10, filters: {})
#       # Implementation
#     end
#   end
#
# @since 1.0.0
#
module RAAF
  module DSL
    module Tools
      module ConventionOverConfiguration
        include PerformanceOptimizer

        def self.included(base)
          base.extend(ClassMethods)
          base.include(PerformanceOptimizer)
          base.generate_tool_metadata
          base.auto_register_tool
        end

        module ClassMethods
          # Auto-register tool in the registry when included
          #
          def auto_register_tool
            tool_name_sym = tool_name.to_sym
            ToolRegistry.register(tool_name_sym, self, auto_discovered: true)
          rescue => e
            # Silently fail auto-registration to avoid breaking existing code
            if defined?(RAAF.logger) && RAAF.respond_to?(:logger)
              RAAF.logger&.debug("Failed to auto-register tool #{name}: #{e.message}")
            end
          end

          # Enhanced tool lookup with caching and validation
          #
          # @param name [Symbol, String] Tool name to lookup
          # @return [Class, nil] Tool class if found
          #
          def lookup_tool_class(name)
            ToolRegistry.get(name, strict: false)
          end

          # Validate tool availability at agent initialization
          #
          # @param tool_names [Array<Symbol>] Tool names to validate
          # @return [Array<String>] Validation errors
          #
          def validate_tool_availability(tool_names)
            errors = []
            
            tool_names.each do |tool_name|
              begin
                ToolRegistry.get(tool_name, strict: true)
              rescue ToolRegistry::ToolNotFoundError => e
                errors << e.message
              end
            end
            
            errors
          end

          # Generate tool metadata at class load time with enhanced caching
          #
          # This method analyzes the class and its call method to automatically
          # generate tool name, description, and parameter schema. Results are
          # cached for performance using the PerformanceOptimizer.
          #
          def generate_tool_metadata
            @metadata_generated = true
            
            # Use performance optimizer for caching if available
            if respond_to?(:cache_generated_methods)
              cache_generated_methods
            else
              # Fallback to original caching
              @cached_tool_name = generate_tool_name
              @cached_tool_description = generate_tool_description
              @cached_parameter_schema = generate_parameter_schema
              @cached_tool_definition = generate_tool_definition
            end
          end

          # Get auto-generated tool name with enhanced caching
          #
          # @return [String] Generated tool name
          #
          def tool_name
            return @tool_name if defined?(@tool_name) && @tool_name
            
            # Use performance optimizer cache if available
            if respond_to?(:cached_tool_definition)
              cached_tool_definition.dig(:function, :name) || @cached_tool_name || generate_tool_name
            else
              @cached_tool_name || generate_tool_name
            end
          end

          # Get auto-generated tool description with enhanced caching
          #
          # @return [String] Generated tool description
          #
          def tool_description
            return @tool_description if defined?(@tool_description) && @tool_description
            
            # Use performance optimizer cache if available
            if respond_to?(:cached_tool_definition)
              cached_tool_definition.dig(:function, :description) || @cached_tool_description || generate_tool_description
            else
              @cached_tool_description || generate_tool_description
            end
          end

          # Get auto-generated parameter schema with enhanced caching
          #
          # @return [Hash] Generated parameter schema
          #
          def parameter_schema
            return @parameter_schema if defined?(@parameter_schema) && @parameter_schema
            
            # Use performance optimizer cache if available
            if respond_to?(:cached_parameter_schema)
              cached_parameter_schema || @cached_parameter_schema || generate_parameter_schema
            else
              @cached_parameter_schema || generate_parameter_schema
            end
          end

          # Get tool definition for an instance
          #
          # @param instance [Tool] Tool instance
          # @return [Hash] Complete tool definition
          #
          def tool_definition_for_instance(instance)
            {
              type: "function",
              function: {
                name: instance.name,
                description: instance.description,
                parameters: parameter_schema
              }
            }
          end

          # Check if tool is enabled by default
          #
          # @return [Boolean] Whether tool is enabled
          #
          def enabled?
            return @enabled if defined?(@enabled)
            true
          end

          private

          # Generate tool name from class name
          #
          # Converts class names like "WeatherSearchTool" to "weather_search"
          #
          # @return [String] Generated tool name
          #
          def generate_tool_name
            class_name_str = name
            return 'anonymous_tool' unless class_name_str
            
            class_name = class_name_str.split('::').last
            
            # Remove "Tool" suffix if present
            clean_name = class_name.gsub(/Tool$/, '')
            
            # Convert CamelCase to snake_case
            clean_name.gsub(/([A-Z])/, '_\1')
                      .downcase
                      .sub(/^_/, '')
          end

          # Generate tool description from class name
          #
          # Creates human-readable descriptions from class names
          #
          # @return [String] Generated tool description
          #
          def generate_tool_description
            class_name_str = name
            return 'Anonymous tool for general operations' unless class_name_str
            
            class_name = class_name_str.split('::').last.gsub(/Tool$/, '')
            
            # Convert CamelCase to space-separated words
            words = class_name.gsub(/([A-Z])/, ' \1').strip.downcase
            
            "Tool for #{words} operations"
          end

          # Generate parameter schema from call method signature
          #
          # Introspects the call method to build JSON Schema for parameters
          #
          # @return [Hash] Generated parameter schema
          #
          def generate_parameter_schema
            call_method = instance_method(:call) if method_defined?(:call)
            return default_parameter_schema unless call_method

            parameters = call_method.parameters
            schema = {
              type: "object",
              properties: {},
              required: [],
              additionalProperties: false
            }

            parameters.each do |param_type, param_name|
              next if param_type == :block

              property = build_parameter_property(param_type, param_name)
              schema[:properties][param_name.to_s] = property

              # Required parameters (no default value)
              if param_type == :keyreq
                schema[:required] << param_name.to_s
              end
            end

            schema
          end

          # Generate complete tool definition
          #
          # @return [Hash] Complete tool definition
          #
          def generate_tool_definition
            {
              type: "function",
              function: {
                name: tool_name,
                description: tool_description,
                parameters: parameter_schema
              }
            }
          end

          # Build parameter property definition
          #
          # @param param_type [Symbol] Parameter type from method signature
          # @param param_name [Symbol] Parameter name
          # @return [Hash] Parameter property definition
          #
          def build_parameter_property(param_type, param_name)
            property = {
              type: infer_parameter_type(param_name),
              description: generate_parameter_description(param_name)
            }

            # Add additional constraints based on parameter name patterns
            case param_name.to_s
            when /^(limit|count|size|max)$/
              property[:type] = "integer"
              property[:minimum] = 1
            when /email/
              property[:type] = "string"
              property[:format] = "email"
            when /url|uri/
              property[:type] = "string"
              property[:format] = "uri"
            when /date/
              property[:type] = "string"
              property[:format] = "date"
            when /time/
              property[:type] = "string"
              property[:format] = "date-time"
            end

            property
          end

          # Infer parameter type from parameter name
          #
          # @param param_name [Symbol] Parameter name
          # @return [String] Inferred JSON Schema type
          #
          def infer_parameter_type(param_name)
            case param_name.to_s
            when /^(count|limit|size|max|min|number|age|year)$/
              "integer"
            when /^(price|rate|score|percent|weight|height)$/
              "number"
            when /^(enabled|active|valid|confirmed|published|detailed)$/
              "boolean"
            when /^(tags|items|list|array|ids)$/
              "array"
            when /^(config|options|metadata|params|filters)$/
              "object"
            else
              "string"
            end
          end

          # Generate parameter description from parameter name
          #
          # @param param_name [Symbol] Parameter name
          # @return [String] Generated parameter description
          #
          def generate_parameter_description(param_name)
            # Convert snake_case to human readable
            words = param_name.to_s.gsub('_', ' ')
            
            # Add context based on common parameter patterns
            case param_name.to_s
            when /query|search/
              "#{words.capitalize} term for searching"
            when /limit|max/
              "Maximum number of #{words.gsub(/limit|max/, '').strip} to return"
            when /filter/
              "#{words.capitalize} criteria to apply"
            when /format|type/
              "#{words.capitalize} specification"
            else
              words.capitalize
            end
          end

          # Default parameter schema when call method is not available
          #
          # @return [Hash] Default empty parameter schema
          #
          def default_parameter_schema
            {
              type: "object",
              properties: {},
              required: [],
              additionalProperties: false
            }
          end
        end

        # Instance methods for ConventionOverConfiguration

        # Check if metadata has been generated
        #
        # @return [Boolean] Whether metadata generation has completed
        #
        def metadata_generated?
          self.class.instance_variable_get(:@metadata_generated) || false
        end

        # Regenerate metadata (useful for development/testing)
        #
        def regenerate_metadata!
          self.class.generate_tool_metadata
        end

        # Get parameter information for debugging
        #
        # @return [Hash] Parameter analysis information
        #
        def parameter_info
          return {} unless self.class.method_defined?(:call)

          method = self.class.instance_method(:call)
          {
            method_signature: method.parameters,
            parameter_schema: self.class.parameter_schema,
            generated_at: self.class.instance_variable_get(:@metadata_generated)
          }
        end
      end
    end
  end
end
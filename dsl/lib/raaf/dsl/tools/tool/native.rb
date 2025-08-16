# frozen_string_literal: true

# Tool::Native for OpenAI native tools in RAAF DSL framework
#
# This class provides a specialized base for tools that are handled natively
# by OpenAI's function calling system. Native tools define their structure
# and parameters but do not implement execution logic, as the execution
# is handled entirely by OpenAI's infrastructure.
#
# Native tools are configuration-only and focus on providing accurate
# tool definitions for OpenAI's function calling API. They do not implement
# the `call` method since execution happens outside the RAAF framework.
#
# @example Basic native tool
#   class CodeInterpreter < RAAF::DSL::Tools::Tool::Native
#     configure name: "code_interpreter",
#               description: "Execute Python code in a sandboxed environment"
#     
#     parameter :code, type: :string, required: true,
#               description: "Python code to execute"
#   end
#
# @example Advanced native tool with multiple parameters
#   class FileSearch < RAAF::DSL::Tools::Tool::Native
#     configure name: "file_search",
#               description: "Search through uploaded files"
#     
#     parameter :query, type: :string, required: true,
#               description: "Search query"
#     parameter :file_types, type: :array, items: { type: :string },
#               description: "File types to search"
#     parameter :max_results, type: :integer, default: 10,
#               description: "Maximum number of results"
#   end
#
# @see RAAF::DSL::Tools::Tool Base tool class
# @see https://platform.openai.com/docs/assistants/tools OpenAI Tools Documentation
# @since 1.0.0
#
module RAAF
  module DSL
    module Tools
      class Tool
        class Native < Tool
          # Native tools do not implement call method
          # Execution is handled by OpenAI's infrastructure
          #
          # @raise [NotImplementedError] Always raises as native tools don't execute locally
          #
          def call(**params)
            raise NotImplementedError, 
                  "Native tools are executed by OpenAI infrastructure, not locally. " \
                  "Use Tool::API or Tool for locally executable tools."
          end

          # Check if this is a native tool
          #
          # @return [Boolean] Always true for native tools
          #
          def native?
            true
          end

          # Returns the tool definition for OpenAI's native function calling
          #
          # Native tools provide more structured definitions that align with
          # OpenAI's expected format for built-in tools like code_interpreter
          # and file_search.
          #
          # @return [Hash] Tool definition in OpenAI native format
          #
          def to_tool_definition
            definition = {
              type: tool_type,
              **tool_configuration_hash
            }

            # Add function definition if this is a function-type tool
            if tool_type == "function"
              definition[:function] = {
                name: name,
                description: description,
                parameters: parameter_schema
              }
            end

            definition
          end

          # Returns tool configuration for native integration
          #
          # Native tools provide configuration that indicates they should
          # be passed directly to OpenAI without local execution setup.
          #
          # @return [Hash] Native tool configuration
          #
          def tool_configuration
            {
              tool: to_tool_definition,
              native: true,
              enabled: enabled?,
              metadata: {
                class: self.class.name,
                tool_type: tool_type,
                options: @options
              }
            }
          end

          private

          # Get the tool type for OpenAI
          #
          # @return [String] Tool type (function, code_interpreter, file_search, etc.)
          #
          def tool_type
            @options[:type] || self.class.tool_type || "function"
          end

          # Get tool configuration hash
          #
          # @return [Hash] Additional configuration for the tool type
          #
          def tool_configuration_hash
            config = {}
            
            # Add type-specific configuration
            case tool_type
            when "code_interpreter"
              # Code interpreter tools may have additional configuration
              config.merge!(code_interpreter_config)
            when "file_search"
              # File search tools may have vector store configuration
              config.merge!(file_search_config)
            when "function"
              # Function tools handled by function definition
            end

            config
          end

          # Get parameter schema for function-type tools
          #
          # @return [Hash] JSON Schema for function parameters
          #
          def parameter_schema
            schema = self.class.parameter_schema || {
              type: "object",
              properties: {},
              required: [],
              additionalProperties: false
            }
            
            # Merge instance-level parameter overrides
            if @options[:parameters]
              schema = schema.merge(@options[:parameters])
            end

            schema
          end

          # Configuration for code_interpreter tools
          #
          # @return [Hash] Code interpreter specific configuration
          #
          def code_interpreter_config
            config = {}
            config[:timeout] = @options[:timeout] if @options[:timeout]
            config[:memory_limit] = @options[:memory_limit] if @options[:memory_limit]
            config
          end

          # Configuration for file_search tools
          #
          # @return [Hash] File search specific configuration
          #
          def file_search_config
            config = {}
            config[:max_num_results] = @options[:max_results] if @options[:max_results]
            config[:ranking_options] = @options[:ranking_options] if @options[:ranking_options]
            config
          end

          class << self
            # Configure tool type
            #
            # @param type [String] OpenAI tool type
            #
            def tool_type(type = nil)
              if type
                @tool_type = type
              else
                @tool_type
              end
            end

            # Define a parameter for function-type tools
            #
            # @param name [Symbol] Parameter name
            # @param type [Symbol] Parameter type (:string, :number, :integer, :boolean, :array, :object)
            # @param required [Boolean] Whether parameter is required
            # @param description [String] Parameter description
            # @param options [Hash] Additional JSON Schema options
            #
            def parameter(name, type:, required: false, description: nil, **options)
              @parameter_schema ||= {
                type: "object",
                properties: {},
                required: [],
                additionalProperties: false
              }

              property_def = { type: type.to_s }
              property_def[:description] = description if description
              property_def.merge!(options)

              @parameter_schema[:properties][name.to_s] = property_def
              @parameter_schema[:required] << name.to_s if required
            end

            # Get the parameter schema
            #
            # @return [Hash, nil] Parameter schema
            #
            def parameter_schema
              @parameter_schema
            end

            # Configure multiple parameters at once
            #
            # @param schema [Hash] Complete parameter schema
            #
            def parameters(schema)
              @parameter_schema = schema
            end

            # Reset parameter schema (useful for testing)
            #
            def reset_parameters!
              @parameter_schema = nil
            end
          end
        end
      end
    end
  end
end
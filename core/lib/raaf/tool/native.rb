# frozen_string_literal: true

require_relative "../tool"

module RAAF
  class Tool
    # Base class for OpenAI native tools
    #
    # Native tools are executed by OpenAI's infrastructure rather than
    # locally. They include tools like web_search, code_interpreter,
    # and dalle image generation.
    #
    # @example Native web search tool
    #   class WebSearchTool < RAAF::Tool::Native
    #     configure name: "web_search", 
    #               description: "Search the web for information"
    #     
    #     native_config do
    #       web_search true
    #     end
    #   end
    #
    class Native < Tool
      class << self
        attr_accessor :native_configuration

        def native_config(&block)
          @native_configuration = NativeConfigBuilder.new(&block).build
        end

        def native?
          true
        end
      end

      # Native tools don't have a local call implementation
      def call(**params)
        raise NotImplementedError, 
          "Native tools are executed by OpenAI infrastructure. " \
          "They cannot be called directly."
      end

      # Check if this is a native tool
      def native?
        true
      end

      # Generate tool definition for OpenAI API
      def to_tool_definition
        config = self.class.native_configuration || {}
        
        # Different format for native tools
        case name
        when "web_search"
          { type: "web_search", web_search: config }
        when "code_interpreter"
          { type: "code_interpreter", code_interpreter: config }
        when "file_search"
          { type: "file_search", file_search: config }
        else
          # Fallback to function format for unknown native tools
          super
        end
      end

      # Native tools don't convert to FunctionTool
      def to_function_tool
        raise NotImplementedError,
          "Native tools cannot be converted to FunctionTool. " \
          "They are executed by OpenAI infrastructure."
      end

      private

      # Builder for native tool configuration
      class NativeConfigBuilder
        def initialize(&block)
          @config = {}
          instance_eval(&block) if block_given?
        end

        def web_search(enabled = true)
          @config[:web_search] = enabled
        end

        def code_interpreter(enabled = true)
          @config[:code_interpreter] = enabled
        end

        def file_search(enabled = true)
          @config[:file_search] = enabled
        end

        def option(key, value)
          @config[key] = value
        end

        def build
          @config
        end
      end
    end
  end
end
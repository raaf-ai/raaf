# frozen_string_literal: true

require "raaf-dsl"

module RAAF
  module Tools
    module Native
      # Native OpenAI Code Interpreter Tool - Clean implementation using new DSL
      #
      # Provides Python code execution capabilities through OpenAI's hosted code
      # interpreter service. This tool is executed natively by OpenAI's infrastructure
      # in a secure sandboxed environment.
      #
      # Features:
      # - Secure Python code execution
      # - File upload and processing
      # - Data analysis and visualization
      # - Mathematical computations
      # - Chart and graph generation
      #
      # @example Basic usage in agent
      #   agent.add_tool(RAAF::Tools::Native::CodeInterpreter.new)
      #
      # @example With custom configuration
      #   tool = RAAF::Tools::Native::CodeInterpreter.new(
      #     timeout: 60,
      #     memory_limit: "512MB"
      #   )
      #
      class CodeInterpreter < RAAF::DSL::Tools::Tool::Native
        tool_type "code_interpreter"

        # Initialize code interpreter tool with OpenAI native configuration
        #
        # @param options [Hash] Configuration options
        # @option options [Integer] :timeout Execution timeout in seconds
        # @option options [String] :memory_limit Memory limit for execution
        #
        def initialize(options = {})
          @timeout = options[:timeout]
          @memory_limit = options[:memory_limit]
          
          super(options.merge(
            type: "code_interpreter",
            timeout: @timeout,
            memory_limit: @memory_limit
          ).compact)
        end

        # Tool configuration for OpenAI agents
        def to_tool_definition
          config = { type: "code_interpreter" }
          
          # Add configuration if provided
          if @timeout || @memory_limit
            config[:code_interpreter] = {
              timeout: @timeout,
              memory_limit: @memory_limit
            }.compact
          end
          
          config
        end

        # Tool name for agent registration
        def name
          "code_interpreter"
        end

        # Native tools are always enabled for OpenAI
        def enabled?
          true
        end

        # Description for tool registry
        def description
          "Execute Python code in a secure sandboxed environment with data analysis capabilities"
        end
      end
    end
  end
end
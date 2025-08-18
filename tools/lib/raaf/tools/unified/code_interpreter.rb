# frozen_string_literal: true

require_relative "../../../../../lib/raaf/tool/native"

module RAAF
  module Tools
    module Unified
      # Native OpenAI Code Interpreter Tool
      #
      # Executes Python code in a sandboxed environment with data analysis
      # and visualization capabilities.
      #
      class CodeInterpreterTool < RAAF::Tool::Native
        configure name: "code_interpreter",
                 description: "Execute Python code for data analysis and computation"

        def initialize(sandbox_mode: true, **options)
          super(**options)
          @sandbox_mode = sandbox_mode
        end

        native_config do
          code_interpreter true
        end

        def to_tool_definition
          {
            type: "code_interpreter",
            code_interpreter: {
              sandbox_mode: @sandbox_mode
            }
          }
        end
      end
    end
  end
end
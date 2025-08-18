# frozen_string_literal: true

require_relative "../tool"

module RAAF
  class Tool
    # Base class for standard function tools
    #
    # Function tools are regular Ruby methods that can be called locally.
    # This is the most common type of tool and is the default when
    # inheriting directly from RAAF::Tool.
    #
    # @example Simple function tool
    #   class CalculatorTool < RAAF::Tool::Function
    #     def call(expression:)
    #       eval(expression)
    #     rescue => e
    #       { error: e.message }
    #     end
    #   end
    #
    class Function < Tool
      # Function tools are the default, so no special behavior needed
      # This class exists mainly for explicit typing and future extensions
      
      def native?
        false
      end
    end
  end
end
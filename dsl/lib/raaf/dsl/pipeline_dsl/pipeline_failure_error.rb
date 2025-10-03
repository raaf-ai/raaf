# frozen_string_literal: true

module RAAF
  module DSL
    module PipelineDSL
      # Exception raised when an agent or service in a pipeline returns success: false
      #
      # This exception is used to propagate failures through the pipeline,
      # ensuring the entire pipeline stops executing when any component fails.
      #
      # Usage:
      #   raise PipelineFailureError.new(agent_name, result)
      #
      # The exception carries:
      # - agent_name: Name of the agent/service that failed
      # - error_message: The error message from the result
      # - error_type: Optional error type/category
      # - full_result: Complete result hash for debugging
      #
      class PipelineFailureError < StandardError
        attr_reader :agent_name, :error_message, :error_type, :full_result

        def initialize(agent_name, result)
          @agent_name = agent_name
          @full_result = result
          @error_message = extract_error_message(result)
          @error_type = extract_error_type(result)

          super(build_message)
        end

        private

        def extract_error_message(result)
          return "Unknown error" unless result.is_a?(Hash)

          # Try different common error fields
          result[:error] || result["error"] ||
            result[:errors] || result["errors"] ||
            result[:message] || result["message"] ||
            "Agent returned success: false without error details"
        end

        def extract_error_type(result)
          return nil unless result.is_a?(Hash)

          result[:error_type] || result["error_type"] ||
            result[:type] || result["type"]
        end

        def build_message
          msg = "Pipeline failed at agent '#{@agent_name}': #{@error_message}"
          msg += " (type: #{@error_type})" if @error_type
          msg
        end
      end
    end
  end
end

# frozen_string_literal: true

module RAAF
  module DSL
    # Standardized result object for agent runs
    #
    # This class provides a consistent interface for accessing the results of an
    # agent execution, abstracting away the underlying details of the RAAF-core
    # response. It offers methods to check for success, access parsed data,
    # and retrieve error information.
    #
    # @attr_reader [Boolean] success Whether the agent run was successful
    # @attr_reader [Object, nil] data The parsed data from the AI response
    # @attr_reader [String, nil] error The error message if the run failed
    # @attr_reader [ContextVariables] context_variables The context used for the run
    #
    class Result
      attr_reader :success, :data, :error, :context_variables

      # @param success [Boolean]
      # @param data [Object, nil]
      # @param error [String, nil]
      # @param context_variables [ContextVariables]
      def initialize(success:, data:, error: nil, context_variables:)
        @success = success
        @data = data
        @error = error
        @context_variables = context_variables
      end

      def success?
        @success
      end

      def failure?
        !@success
      end
    end
  end
end

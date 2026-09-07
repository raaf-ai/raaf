# frozen_string_literal: true

module RAAF
  module DSL
    # Configuration for the tool execution interceptor
    #
    # The interceptor adds validation, logging and metadata to every tool an
    # agent runs. This object is the DSL behind the +tool_execution+ block that
    # turns those conveniences on and off.
    #
    # @example Disabling validation for one agent
    #   class MyAgent < RAAF::DSL::Agent
    #     tool_execution do
    #       enable_validation false
    #     end
    #   end
    #
    # @see RAAF::DSL::Agent.tool_execution
    class ToolExecutionConfig
      # Every convenience is on by default; logs are truncated at 100 characters.
      DEFAULTS = {
        enable_validation: true,
        enable_logging: true,
        enable_metadata: true,
        log_arguments: true,
        truncate_logs: 100
      }.freeze

      # @param config [Hash] Starting values, normally the parent class's config
      def initialize(config = DEFAULTS)
        @config = config.dup
      end

      # Validate tool arguments against the tool definition before running it
      def enable_validation(value)
        @config[:enable_validation] = value
      end

      # Log the start and end of each tool execution, with its duration
      def enable_logging(value)
        @config[:enable_logging] = value
      end

      # Add _execution_metadata to Hash results
      def enable_metadata(value)
        @config[:enable_metadata] = value
      end

      # Include tool arguments in the execution log
      def log_arguments(value)
        @config[:log_arguments] = value
      end

      # Length at which logged values are truncated
      def truncate_logs(length)
        @config[:truncate_logs] = length
      end

      # @return [Hash] The configured values
      def to_h
        @config.dup
      end
    end
  end
end

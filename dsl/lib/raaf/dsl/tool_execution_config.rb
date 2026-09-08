# frozen_string_literal: true

module RAAF
  module DSL
    # Configuration for the tool execution interceptor
    #
    # The interceptor adds validation and metadata to every tool an agent
    # runs. This object is the DSL behind the +tool_execution+ block that
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
      # Every convenience is on by default.
      DEFAULTS = {
        enable_validation: true,
        enable_metadata: true
      }.freeze

      # @param config [Hash] Starting values, normally the parent class's config
      def initialize(config = DEFAULTS)
        @config = config.dup
      end

      # Validate tool arguments against the tool definition before running it
      def enable_validation(value)
        @config[:enable_validation] = value
      end

      # Add _execution_metadata to Hash results
      def enable_metadata(value)
        @config[:enable_metadata] = value
      end

      # @return [Hash] The configured values
      def to_h
        @config.dup
      end
    end
  end
end

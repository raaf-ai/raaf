# frozen_string_literal: true

module OpenAIAgents
  module Config
    ##
    # Configuration for tracing and monitoring
    #
    # This class handles all parameters related to tracing, monitoring,
    # and observability of agent execution.
    #
    # @example Basic tracing configuration
    #   config = TracingConfig.new(
    #     trace_id: "custom-trace-123",
    #     group_id: "session-456",
    #     metadata: { user_id: "user123", experiment: "A" }
    #   )
    #
    # @example Disabling tracing
    #   config = TracingConfig.new(tracing_disabled: true)
    #   config.tracing_enabled? # => false
    #
    # @example Getting trace context
    #   context = config.trace_context
    #   # => { trace_id: "custom-trace-123", group_id: "session-456", metadata: {...} }
    #
    class TracingConfig
      # @return [String, nil] Custom trace ID for this run
      attr_accessor :trace_id

      # @return [String, nil] Group ID to link related traces
      attr_accessor :group_id

      # @return [Hash, nil] Custom metadata for tracing
      attr_accessor :metadata

      # @return [Boolean] Whether to disable tracing for this run
      attr_accessor :tracing_disabled

      # @return [Boolean] Whether to include sensitive data in traces
      attr_accessor :trace_include_sensitive_data

      # @return [String] Workflow name for tracing
      attr_accessor :workflow_name

      def initialize(
        trace_id: nil,
        group_id: nil,
        metadata: nil,
        tracing_disabled: false,
        trace_include_sensitive_data: true,
        workflow_name: "Agent workflow"
      )
        @trace_id = trace_id
        @group_id = group_id
        @metadata = metadata
        @tracing_disabled = tracing_disabled
        @trace_include_sensitive_data = trace_include_sensitive_data
        @workflow_name = workflow_name
      end

      ##
      # Check if tracing is enabled
      #
      # @return [Boolean] true if tracing should be active
      #
      def tracing_enabled?
        !tracing_disabled
      end

      ##
      # Check if sensitive data should be included in traces
      #
      # @return [Boolean] true if sensitive data should be traced
      #
      def include_sensitive_data?
        trace_include_sensitive_data
      end

      ##
      # Get trace context for creating spans
      #
      # @return [Hash] Context data for tracing
      #
      def trace_context
        {
          trace_id: trace_id,
          group_id: group_id,
          metadata: metadata || {},
          workflow_name: workflow_name
        }.compact
      end

      ##
      # Merge with another TracingConfig, with other taking precedence
      #
      # @param other [TracingConfig] Config to merge
      # @return [TracingConfig] New merged config
      #
      def merge(other)
        return self unless other

        self.class.new(
          trace_id: other.trace_id || trace_id,
          group_id: other.group_id || group_id,
          metadata: (metadata || {}).merge(other.metadata || {}),
          tracing_disabled: other.tracing_disabled.nil? ? tracing_disabled : other.tracing_disabled,
          trace_include_sensitive_data: other.trace_include_sensitive_data.nil? ? trace_include_sensitive_data : other.trace_include_sensitive_data,
          workflow_name: other.workflow_name || workflow_name
        )
      end

      ##
      # Convert to hash representation
      #
      # @return [Hash] All configuration as hash
      #
      def to_h
        {
          trace_id: trace_id,
          group_id: group_id,
          metadata: metadata,
          tracing_disabled: tracing_disabled,
          trace_include_sensitive_data: trace_include_sensitive_data,
          workflow_name: workflow_name
        }
      end
    end
  end
end
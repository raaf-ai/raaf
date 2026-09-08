# frozen_string_literal: true

require_relative "intelligent_streaming"

module RAAF
  module DSL
    # Module for integrating intelligent streaming into Pipeline
    module PipelineStreamingIntegration
      def self.included(base)
        base.class_eval do
          attr_reader :streaming_manager, :streaming_scopes
        end
      end

      # Override initialize to detect streaming scopes
      def initialize(**context_params)
        super
        detect_streaming_scopes_if_needed
      end

      private

      def detect_streaming_scopes_if_needed
        return unless self.class.flow_chain

        @streaming_manager = IntelligentStreaming::Manager.new
        @streaming_scopes = @streaming_manager.detect_scopes(self.class.flow_chain)
      rescue StandardError
        # Scope detection is best-effort; a pipeline without it still runs.
        @streaming_scopes = []
      end

      public

      # Execute the pipeline with streaming scope awareness
      def execute_with_streaming
        if streaming_scopes.nil? || streaming_scopes.empty?
          # No streaming scopes, execute normally
          execute_without_streaming if respond_to?(:execute_without_streaming)
        else
          # Execute with streaming scope handling
          execute_streaming_pipeline
        end
      end

      private

      def execute_streaming_pipeline
        # This is a simplified implementation
        # The actual implementation would need to:
        # 1. Execute agents before first streaming scope normally
        # 2. When reaching a streaming trigger agent:
        #    - Extract the array field from context
        #    - Split into streams based on stream_size
        #    - For each stream:
        #      - Execute all agents in the streaming scope
        #      - Call progress hooks
        #      - Accumulate results
        #    - Merge results from all streams
        # 3. Continue with agents after streaming scope

        # For now, just execute normally
        # Delegate to normal execution for now
        execute_without_streaming if respond_to?(:execute_without_streaming)
      end
    end
  end
end

# frozen_string_literal: true

require "active_support/core_ext/hash/indifferent_access"

module RAAF
  module Eval
    module DslEngine
      # Structured progress event for evaluation streaming
      # Provides consistent schema with validation and indifferent access
      class ProgressEvent
        attr_reader :type, :timestamp, :progress, :status, :metadata

        EVENT_TYPES = [:start, :config_start, :evaluator_start, :evaluator_end, :config_end, :end].freeze
        STATUSES = [:pending, :running, :completed, :failed].freeze

        # Initialize progress event
        # @param type [Symbol] Event type (one of EVENT_TYPES)
        # @param progress [Float] Progress percentage (0.0-100.0)
        # @param status [Symbol] Event status (one of STATUSES)
        # @param metadata [Hash] Event-specific metadata
        def initialize(type:, progress:, status:, metadata: {})
          validate_type!(type)
          validate_status!(status)
          validate_progress!(progress)

          @type = type
          @timestamp = Time.now
          @progress = progress
          @status = status
          @metadata = metadata.with_indifferent_access
        end

        # Convert event to hash representation
        # @return [Hash] Event data with all fields
        def to_h
          {
            type: type,
            timestamp: timestamp,
            progress: progress,
            status: status,
            metadata: metadata
          }
        end

        private

        # Validate event type
        # @param type [Symbol] Event type to validate
        # @raise [InvalidEventTypeError] if type is invalid
        def validate_type!(type)
          unless EVENT_TYPES.include?(type)
            raise InvalidEventTypeError, "Invalid event type: #{type}. Must be one of: #{EVENT_TYPES.join(', ')}"
          end
        end

        # Validate event status
        # @param status [Symbol] Status to validate
        # @raise [InvalidEventStatusError] if status is invalid
        def validate_status!(status)
          unless STATUSES.include?(status)
            raise InvalidEventStatusError, "Invalid status: #{status}. Must be one of: #{STATUSES.join(', ')}"
          end
        end

        # Validate progress percentage
        # @param progress [Float] Progress to validate
        # @raise [InvalidProgressError] if progress is out of range
        def validate_progress!(progress)
          unless progress >= 0.0 && progress <= 100.0
            raise InvalidProgressError, "Progress must be 0.0-100.0, got: #{progress}"
          end
        end
      end

      # Error raised when event type is invalid
      class InvalidEventTypeError < StandardError; end

      # Error raised when event status is invalid
      class InvalidEventStatusError < StandardError; end

      # Error raised when progress percentage is invalid
      class InvalidProgressError < StandardError; end
    end
  end
end

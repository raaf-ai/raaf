# frozen_string_literal: true

module RAAF
  module DSL
    # Configuration class for tool execution conveniences
    #
    # This class provides a DSL for configuring how tool execution interceptor
    # behaves. It controls validation, logging, metadata injection, and other
    # convenience features.
    #
    # @example Basic configuration
    #   config = ToolExecutionConfig.new
    #   config.enable_validation true
    #   config.enable_logging false
    #   config.truncate_logs 200
    #
    # @example Using in agent class
    #   class MyAgent < RAAF::DSL::Agent
    #     tool_execution do
    #       enable_validation true
    #       enable_logging true
    #       enable_metadata true
    #       log_arguments true
    #       truncate_logs 100
    #     end
    #   end
    #
    class ToolExecutionConfig
      # Default configuration values
      DEFAULTS = {
        enable_validation: true,
        enable_logging: true,
        enable_metadata: true,
        log_arguments: true,
        truncate_logs: 100
      }.freeze

      # Initialize a new configuration
      #
      # @param initial_values [Hash] Initial configuration values
      def initialize(initial_values = {})
        @config = DEFAULTS.merge(initial_values)
      end

      # Enable or disable parameter validation
      #
      # @param value [Boolean] Whether to enable validation
      def enable_validation(value)
        @config[:enable_validation] = value
      end

      # Enable or disable execution logging
      #
      # @param value [Boolean] Whether to enable logging
      def enable_logging(value)
        @config[:enable_logging] = value
      end

      # Enable or disable metadata injection
      #
      # @param value [Boolean] Whether to enable metadata
      def enable_metadata(value)
        @config[:enable_metadata] = value
      end

      # Enable or disable argument logging
      #
      # @param value [Boolean] Whether to log tool arguments
      def log_arguments(value)
        @config[:log_arguments] = value
      end

      # Set the truncation length for log values
      #
      # @param value [Integer] Maximum length before truncation
      def truncate_logs(value)
        @config[:truncate_logs] = value
      end

      # Convert configuration to hash
      #
      # @return [Hash] Frozen hash of configuration values
      def to_h
        @config.dup.freeze
      end

      # Check if validation is enabled
      #
      # @return [Boolean] true if validation is enabled
      def validation_enabled?
        @config[:enable_validation]
      end

      # Check if logging is enabled
      #
      # @return [Boolean] true if logging is enabled
      def logging_enabled?
        @config[:enable_logging]
      end

      # Check if metadata is enabled
      #
      # @return [Boolean] true if metadata is enabled
      def metadata_enabled?
        @config[:enable_metadata]
      end

      # Check if argument logging is enabled
      #
      # @return [Boolean] true if argument logging is enabled
      def log_arguments?
        @config[:log_arguments]
      end

      # Get the truncation length
      #
      # @return [Integer] Truncation length for logs
      def truncate_logs_at
        @config[:truncate_logs]
      end
    end
  end
end

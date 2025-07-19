# frozen_string_literal: true

module RAAF
  module Guardrails
    # Base class for all guardrails
    # Provides common interface and functionality for input/output filtering
    class Base
      attr_reader :action, :logger, :metrics

      VALID_ACTIONS = %i[block redact flag log].freeze

      def initialize(action: :block, logger: nil, enabled: true)
        validate_action!(action)
        @action = action
        @logger = logger || default_logger
        @enabled = enabled
        @metrics = { checks: 0, violations: 0, errors: 0 }
      end

      # Check input before sending to AI
      def check_input(content, context = {})
        return safe_result if !enabled? || content.nil? || content.empty?
        
        @metrics[:checks] += 1
        
        begin
          perform_input_check(content, context)
        rescue StandardError => e
          @metrics[:errors] += 1
          handle_error(e, content, context)
        end
      end

      # Check output before returning to user
      def check_output(content, context = {})
        return safe_result if !enabled? || content.nil? || content.empty?
        
        @metrics[:checks] += 1
        
        begin
          perform_output_check(content, context)
        rescue StandardError => e
          @metrics[:errors] += 1
          handle_error(e, content, context)
        end
      end

      def enabled?
        @enabled
      end

      def disable!
        @enabled = false
      end

      def enable!
        @enabled = true
      end

      protected

      # Override in subclasses
      def perform_input_check(content, context)
        perform_check(content, context)
      end

      # Override in subclasses
      def perform_output_check(content, context)
        perform_check(content, context)
      end

      # Override in subclasses for actual implementation
      def perform_check(content, context)
        safe_result
      end

      def safe_result
        GuardrailResult.new(
          safe: true,
          action: nil,
          content: nil,
          violations: [],
          metadata: {}
        )
      end

      def violation_result(violations, modified_content = nil)
        @metrics[:violations] += 1
        
        GuardrailResult.new(
          safe: false,
          action: @action,
          content: modified_content,
          violations: violations,
          metadata: { guardrail: self.class.name }
        )
      end

      private

      def validate_action!(action)
        unless VALID_ACTIONS.include?(action)
          raise ArgumentError, "Invalid action: #{action}. Must be one of: #{VALID_ACTIONS.join(', ')}"
        end
      end

      def handle_error(error, content, context)
        @logger.error "Guardrail error in #{self.class.name}: #{error.message}"
        @logger.debug error.backtrace.join("\n")
        
        # Fail open - return safe result on error
        safe_result
      end

      def default_logger
        if defined?(Rails)
          Rails.logger
        else
          require 'logger'
          Logger.new($stdout)
        end
      end
    end

    # Result object returned by guardrail checks
    class GuardrailResult
      attr_reader :safe, :action, :content, :violations, :metadata

      def initialize(safe:, action:, content:, violations:, metadata:)
        @safe = safe
        @action = action
        @content = content
        @violations = violations
        @metadata = metadata
      end

      def safe?
        @safe
      end

      def violated?
        !@safe
      end

      def should_block?
        !safe? && action == :block
      end

      def should_redact?
        !safe? && action == :redact
      end

      def should_flag?
        !safe? && action == :flag
      end

      def should_log?
        !safe? && action == :log
      end

      def to_h
        {
          safe: safe,
          action: action,
          content: content,
          violations: violations,
          metadata: metadata
        }
      end
    end
  end
end
# frozen_string_literal: true

require_relative "raaf/guardrails/version"
require_relative "raaf/guardrails/validator"
require_relative "raaf/guardrails/content_filter"
require_relative "raaf/guardrails/toxicity_detector"
require_relative "raaf/guardrails/pii_detector"
require_relative "raaf/guardrails/prompt_injection_detector"
require_relative "raaf/guardrails/custom_rules"
require_relative "raaf/guardrails/middleware"
require_relative "raaf/guardrails/providers/openai_moderator"
require_relative "raaf/guardrails/providers/azure_moderator"
require_relative "raaf/guardrails/providers/aws_moderator"
require_relative "raaf/guardrails/providers/google_moderator"

module RAAF
  ##
  # Safety validation and content filtering for Ruby AI Agents Factory
  #
  # The Guardrails module provides comprehensive safety validation and content
  # filtering for AI agents, ensuring responsible AI deployment with multiple
  # layers of protection including toxicity detection, PII filtering, prompt
  # injection prevention, and custom safety rules.
  #
  # Key features:
  # - **Content Filtering** - Filter harmful, inappropriate, or unwanted content
  # - **Toxicity Detection** - Detect and prevent toxic, hateful, or offensive content
  # - **PII Detection** - Identify and protect personally identifiable information
  # - **Prompt Injection Prevention** - Prevent malicious prompt injection attacks
  # - **Custom Rules** - Define and enforce custom safety policies
  # - **Multiple Providers** - Support for OpenAI, Azure, AWS, and Google moderation APIs
  # - **Real-time Validation** - Validate content before and after agent processing
  # - **Audit Logging** - Track all safety violations and actions taken
  #
  # @example Basic guardrails setup
  #   require 'raaf-guardrails'
  #   
  #   # Configure guardrails
  #   RAAF::Guardrails.configure do |config|
  #     config.toxicity_detection = true
  #     config.pii_detection = true
  #     config.prompt_injection_detection = true
  #     config.content_filtering = true
  #   end
  #   
  #   # Create validator
  #   validator = RAAF::Guardrails::Validator.new
  #   
  #   # Add to agent
  #   agent = RAAF::Agent.new(
  #     name: "SafeAgent",
  #     instructions: "You are a helpful and safe assistant",
  #     guardrails: validator
  #   )
  #
  # @example Content filtering with multiple providers
  #   require 'raaf-guardrails'
  #   
  #   # Setup content filter with multiple providers
  #   content_filter = RAAF::Guardrails::ContentFilter.new
  #   content_filter.add_provider(RAAF::Guardrails::Providers::OpenAIModerator.new)
  #   content_filter.add_provider(RAAF::Guardrails::Providers::AzureModerator.new)
  #   
  #   # Validate content
  #   result = content_filter.validate("This is a test message")
  #   
  #   if result.safe?
  #     puts "Content is safe"
  #   else
  #     puts "Content blocked: #{result.violations.join(', ')}"
  #   end
  #
  # @example Custom safety rules
  #   require 'raaf-guardrails'
  #   
  #   # Define custom rules
  #   custom_rules = RAAF::Guardrails::CustomRules.new
  #   
  #   # Add keyword blocking
  #   custom_rules.add_keyword_rule(
  #     keywords: ["password", "secret", "api_key"],
  #     action: :block,
  #     message: "Sensitive information detected"
  #   )
  #   
  #   # Add regex pattern
  #   custom_rules.add_regex_rule(
  #     pattern: /\b\d{4}-\d{4}-\d{4}-\d{4}\b/,
  #     action: :redact,
  #     replacement: "[CREDIT_CARD_REDACTED]"
  #   )
  #   
  #   # Add to validator
  #   validator = RAAF::Guardrails::Validator.new
  #   validator.add_custom_rules(custom_rules)
  #
  # @example Middleware integration
  #   require 'raaf-guardrails'
  #   
  #   # In Rails application
  #   class ApplicationController < ActionController::Base
  #     include RAAF::Guardrails::Middleware
  #     
  #     before_action :validate_input_content
  #     after_action :validate_output_content
  #   end
  #
  # @since 1.0.0
  module Guardrails
    # Error classes
    class GuardrailsError < StandardError; end
    class ContentViolationError < GuardrailsError; end
    class ToxicityDetectedError < GuardrailsError; end
    class PIIDetectedError < GuardrailsError; end
    class PromptInjectionError < GuardrailsError; end
    class CustomRuleViolationError < GuardrailsError; end

    # Violation severity levels
    SEVERITY_LEVELS = {
      low: 1,
      medium: 2,
      high: 3,
      critical: 4
    }.freeze

    # Default configuration
    DEFAULT_CONFIG = {
      # Core features
      toxicity_detection: true,
      pii_detection: true,
      prompt_injection_detection: true,
      content_filtering: true,
      custom_rules: true,

      # Thresholds
      toxicity_threshold: 0.7,
      pii_confidence_threshold: 0.8,
      prompt_injection_threshold: 0.6,

      # Actions
      default_action: :block,
      log_violations: true,
      notify_violations: false,
      
      # Providers
      primary_provider: :openai,
      fallback_providers: [:azure, :aws],
      
      # Performance
      timeout: 5.0,
      retry_count: 2,
      cache_results: true,
      cache_ttl: 300,

      # Monitoring
      metrics_enabled: true,
      audit_logging: true,
      violation_reporting: true
    }.freeze

    class << self
      # @return [Hash] Current configuration
      attr_accessor :config

      ##
      # Configure guardrails settings
      #
      # @param options [Hash] Configuration options
      # @yield [config] Configuration block
      #
      # @example Configure guardrails
      #   RAAF::Guardrails.configure do |config|
      #     config.toxicity_detection = true
      #     config.toxicity_threshold = 0.8
      #     config.pii_detection = true
      #     config.log_violations = true
      #   end
      #
      def configure
        @config ||= DEFAULT_CONFIG.dup
        yield @config if block_given?
        @config
      end

      ##
      # Get current configuration
      #
      # @return [Hash] Current configuration
      def config
        @config ||= DEFAULT_CONFIG.dup
      end

      ##
      # Create a new validator with default configuration
      #
      # @param options [Hash] Validator options
      # @return [Validator] New validator instance
      def create_validator(**options)
        Validator.new(**config.merge(options))
      end

      ##
      # Create a content filter with default providers
      #
      # @return [ContentFilter] New content filter instance
      def create_content_filter
        filter = ContentFilter.new
        
        # Add primary provider
        case config[:primary_provider]
        when :openai
          filter.add_provider(Providers::OpenAIModerator.new)
        when :azure
          filter.add_provider(Providers::AzureModerator.new)
        when :aws
          filter.add_provider(Providers::AWSModerator.new)
        when :google
          filter.add_provider(Providers::GoogleModerator.new)
        end
        
        # Add fallback providers
        config[:fallback_providers].each do |provider|
          case provider
          when :openai
            filter.add_provider(Providers::OpenAIModerator.new)
          when :azure
            filter.add_provider(Providers::AzureModerator.new)
          when :aws
            filter.add_provider(Providers::AWSModerator.new)
          when :google
            filter.add_provider(Providers::GoogleModerator.new)
          end
        end
        
        filter
      end

      ##
      # Quick validation of content
      #
      # @param content [String] Content to validate
      # @param options [Hash] Validation options
      # @return [ValidationResult] Validation result
      def validate(content, **options)
        validator = create_validator(**options)
        validator.validate(content)
      end

      ##
      # Check if content is safe
      #
      # @param content [String] Content to check
      # @param options [Hash] Validation options
      # @return [Boolean] True if content is safe
      def safe?(content, **options)
        validate(content, **options).safe?
      end

      ##
      # Filter content and return safe version
      #
      # @param content [String] Content to filter
      # @param options [Hash] Filtering options
      # @return [String] Filtered content
      def filter(content, **options)
        result = validate(content, **options)
        result.safe? ? content : result.filtered_content
      end

      ##
      # Get validation statistics
      #
      # @return [Hash] Validation statistics
      def stats
        {
          total_validations: @total_validations || 0,
          total_violations: @total_violations || 0,
          violation_rate: calculate_violation_rate,
          violations_by_type: @violations_by_type || {},
          avg_response_time: @avg_response_time || 0
        }
      end

      ##
      # Reset statistics
      def reset_stats!
        @total_validations = 0
        @total_violations = 0
        @violations_by_type = {}
        @avg_response_time = 0
      end

      ##
      # Enable a specific guardrail
      #
      # @param guardrail [Symbol] Guardrail to enable
      def enable!(guardrail)
        config[guardrail] = true
      end

      ##
      # Disable a specific guardrail
      #
      # @param guardrail [Symbol] Guardrail to disable
      def disable!(guardrail)
        config[guardrail] = false
      end

      ##
      # Check if a guardrail is enabled
      #
      # @param guardrail [Symbol] Guardrail to check
      # @return [Boolean] True if enabled
      def enabled?(guardrail)
        config[guardrail] || false
      end

      ##
      # Log a violation
      #
      # @param violation [Hash] Violation details
      def log_violation(violation)
        return unless config[:log_violations]

        @total_violations = (@total_violations || 0) + 1
        @violations_by_type ||= {}
        @violations_by_type[violation[:type]] = (@violations_by_type[violation[:type]] || 0) + 1

        # Log to configured logger
        RAAF.logger.warn("Guardrail violation", violation)
        
        # Send to monitoring system if configured
        if config[:violation_reporting]
          send_violation_report(violation)
        end
      end

      ##
      # Update validation statistics
      #
      # @param response_time [Float] Response time in seconds
      # @param violations [Integer] Number of violations
      def update_stats(response_time, violations = 0)
        @total_validations = (@total_validations || 0) + 1
        @total_violations = (@total_violations || 0) + violations
        
        # Update average response time
        @avg_response_time = if @avg_response_time
                               (@avg_response_time + response_time) / 2.0
                             else
                               response_time
                             end
      end

      private

      def calculate_violation_rate
        total = @total_validations || 0
        violations = @total_violations || 0
        
        return 0.0 if total == 0
        
        (violations.to_f / total * 100).round(2)
      end

      def send_violation_report(violation)
        # This would send to a monitoring system like DataDog, New Relic, etc.
        # For now, we'll just log it
        RAAF.logger.info("Violation reported", violation)
      end
    end
  end
end
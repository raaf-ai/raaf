# frozen_string_literal: true

require_relative 'base'

module RAAF
  module Guardrails
    # Detects and handles Personally Identifiable Information (PII)
    class PIIDetector < Base
      DEFAULT_PATTERNS = {
        ssn: {
          pattern: /\b\d{3}[-.\s]?\d{2}[-.\s]?\d{4}\b/,
          description: 'Social Security Number'
        },
        email: {
          pattern: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
          description: 'Email address'
        },
        phone: {
          pattern: /\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/,
          description: 'Phone number'
        },
        credit_card: {
          pattern: /\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|6(?:011|5[0-9]{2})[0-9]{12}|(?:2131|1800|35\d{3})\d{11})\b/,
          description: 'Credit card number'
        },
        ip_address: {
          pattern: /\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/,
          description: 'IP address'
        },
        date_of_birth: {
          pattern: /\b(?:DOB|Date of Birth|Born on):?\s*\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}\b/i,
          description: 'Date of birth'
        }
      }.freeze

      attr_reader :detection_types, :redaction_token, :custom_patterns

      def initialize(action: :redact, detection_types: nil, redaction_token: '[REDACTED]', 
                     custom_patterns: {}, confidence_threshold: 0.8, **options)
        super(action: action, **options)
        @detection_types = detection_types || DEFAULT_PATTERNS.keys
        @redaction_token = redaction_token
        @custom_patterns = custom_patterns
        @confidence_threshold = confidence_threshold
        @patterns = build_patterns
      end

      protected

      def perform_check(content, context)
        violations = []
        modified_content = content.dup
        
        @patterns.each do |type, config|
          matches = content.scan(config[:pattern])
          next if matches.empty?
          
          matches.each do |match|
            match_text = match.is_a?(Array) ? match.first : match
            violations << {
              type: type,
              description: config[:description],
              match: match_text,
              position: content.index(match_text)
            }
            
            # Redact if action is :redact
            if @action == :redact
              modified_content.gsub!(match_text, "#{@redaction_token}:#{type}")
            end
          end
        end
        
        return safe_result if violations.empty?
        
        violation_result(violations, @action == :redact ? modified_content : nil)
      end

      private

      def build_patterns
        patterns = {}
        
        @detection_types.each do |type|
          if DEFAULT_PATTERNS.key?(type)
            patterns[type] = DEFAULT_PATTERNS[type]
          elsif @custom_patterns.key?(type)
            patterns[type] = @custom_patterns[type]
          else
            @logger.warn "Unknown PII type: #{type}"
          end
        end
        
        # Add all custom patterns
        @custom_patterns.each do |type, config|
          patterns[type] ||= config
        end
        
        patterns
      end
    end
  end
end
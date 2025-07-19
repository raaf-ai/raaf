# frozen_string_literal: true

require_relative 'base'

module RAAF
  module Guardrails
    # Detects and blocks security threats including prompt injection,
    # jailbreak attempts, and malicious patterns
    class SecurityGuardrail < Base
      # Common prompt injection patterns
      INJECTION_PATTERNS = [
        # Direct instruction override attempts
        /ignore\s+(?:all\s+)?(?:previous|prior|above)\s+(?:instructions?|prompts?|directives?)/i,
        /disregard\s+(?:all\s+)?(?:previous|prior|above)\s+(?:instructions?|prompts?)/i,
        /forget\s+(?:everything|all)\s+(?:you've\s+been\s+told|above|before)/i,
        /override\s+(?:your\s+)?(?:instructions?|programming|directives?)/i,
        
        # Role manipulation attempts
        /you\s+are\s+now\s+(?:a\s+)?(?:different|new|another)\s+(?:ai|assistant|bot|model)/i,
        /pretend\s+(?:to\s+be|you're|you\s+are)\s+(?:a\s+)?(?:different|evil|malicious)/i,
        /act\s+as\s+(?:if\s+you\s+were|though\s+you're|a)\s+(?:different|unrestricted)/i,
        /from\s+now\s+on\s+you\s+(?:are|will\s+be|must\s+act)/i,
        
        # System prompt extraction
        /(?:show|reveal|display|tell)\s+(?:me\s+)?your\s+(?:system\s+)?(?:prompt|instructions|directives)/i,
        /what\s+(?:are\s+)?your\s+(?:original\s+)?(?:instructions?|prompts?|directives?)/i,
        /repeat\s+(?:your\s+)?(?:system\s+)?(?:prompt|instructions)/i,
        
        # Jailbreak attempts
        /(?:dan|do\s+anything\s+now)/i,
        /jailbreak/i,
        /developer\s+mode/i,
        /unlock\s+(?:your\s+)?(?:full\s+)?(?:potential|capabilities)/i
      ].freeze

      # Encoded content patterns (base64, hex, etc.)
      ENCODED_PATTERNS = {
        base64: /^(?:[A-Za-z0-9+\/]{4})*(?:[A-Za-z0-9+\/]{2}==|[A-Za-z0-9+\/]{3}=)?$/,
        hex: /^[0-9a-fA-F]+$/,
        unicode_escape: /\\u[0-9a-fA-F]{4}/
      }.freeze

      # Malicious URL patterns
      MALICIOUS_URL_PATTERNS = [
        /bit\.ly|tinyurl|short\.link/i,  # URL shorteners often used maliciously
        /\.(exe|dll|bat|cmd|scr|vbs|js|jar|zip|rar)$/i,  # Executable extensions
        /javascript:|data:|vbscript:/i  # Script protocols
      ].freeze

      attr_reader :sensitivity, :detection_types, :custom_patterns

      def initialize(action: :block, sensitivity: :high, detection_types: nil, 
                     custom_patterns: [], **options)
        super(action: action, **options)
        @sensitivity = sensitivity
        @detection_types = detection_types || default_detection_types
        @custom_patterns = custom_patterns
        @sensitivity_threshold = sensitivity_thresholds[@sensitivity]
      end

      protected

      def perform_check(content, context)
        violations = []
        
        # Check for prompt injection
        if @detection_types.include?(:prompt_injection)
          violations.concat(detect_prompt_injection(content))
        end
        
        # Check for encoded malicious content
        if @detection_types.include?(:encoded_content)
          violations.concat(detect_encoded_content(content))
        end
        
        # Check for malicious URLs
        if @detection_types.include?(:malicious_urls)
          violations.concat(detect_malicious_urls(content))
        end
        
        # Check custom patterns
        violations.concat(check_custom_patterns(content))
        
        # Calculate overall threat score
        threat_score = calculate_threat_score(violations)
        
        return safe_result if violations.empty? || threat_score < @sensitivity_threshold
        
        violation_result(violations)
      end

      private

      def default_detection_types
        [:prompt_injection, :encoded_content, :malicious_urls]
      end

      def sensitivity_thresholds
        {
          low: 0.7,
          medium: 0.5,
          high: 0.3,
          paranoid: 0.1
        }
      end

      def detect_prompt_injection(content)
        violations = []
        
        INJECTION_PATTERNS.each do |pattern|
          if content.match?(pattern)
            violations << {
              type: :prompt_injection,
              pattern: pattern.source,
              severity: :high,
              description: 'Potential prompt injection attempt detected'
            }
          end
        end
        
        violations
      end

      def detect_encoded_content(content)
        violations = []
        
        # Check for suspiciously long base64/hex strings
        words = content.split(/\s+/)
        words.each do |word|
          next if word.length < 20  # Skip short strings
          
          ENCODED_PATTERNS.each do |encoding_type, pattern|
            if word.match?(pattern)
              violations << {
                type: :encoded_content,
                encoding: encoding_type,
                severity: :medium,
                description: "Suspicious #{encoding_type} encoded content detected"
              }
            end
          end
        end
        
        violations
      end

      def detect_malicious_urls(content)
        violations = []
        
        # Simple URL extraction
        url_pattern = /https?:\/\/[^\s]+/i
        urls = content.scan(url_pattern)
        
        urls.each do |url|
          MALICIOUS_URL_PATTERNS.each do |pattern|
            if url.match?(pattern)
              violations << {
                type: :malicious_url,
                url: url,
                severity: :high,
                description: 'Potentially malicious URL detected'
              }
            end
          end
        end
        
        violations
      end

      def check_custom_patterns(content)
        violations = []
        
        @custom_patterns.each do |pattern_config|
          pattern = pattern_config[:pattern] || pattern_config
          if content.match?(pattern)
            violations << {
              type: :custom_pattern,
              pattern: pattern.source,
              severity: pattern_config[:severity] || :medium,
              description: pattern_config[:description] || 'Custom security pattern matched'
            }
          end
        end
        
        violations
      end

      def calculate_threat_score(violations)
        return 0.0 if violations.empty?
        
        severity_weights = {
          low: 0.2,
          medium: 0.5,
          high: 0.8,
          critical: 1.0
        }
        
        total_score = violations.sum do |violation|
          severity_weights[violation[:severity]] || 0.5
        end
        
        # Normalize by number of violations (average severity)
        total_score / violations.size
      end
    end
  end
end
# frozen_string_literal: true

require_relative 'base'

module RAAF
  module Guardrails
    # Detects toxic, harmful, or inappropriate content in messages
    class ToxicityDetector < Base
      # Toxicity categories with patterns and severity
      TOXICITY_PATTERNS = {
        harassment: {
          patterns: [
            /\b(?:stupid|idiot|moron|dumb|loser|worthless)\b/i,
            /\b(?:kill|hurt|harm|attack)\s+(?:yourself|you)\b/i,
            /\byou\s+(?:suck|are\s+trash|are\s+garbage)\b/i
          ],
          severity: :high
        },
        hate_speech: {
          patterns: [
            # Note: These are simplified patterns for demonstration
            # Real implementation would use more sophisticated detection
            /\b(?:hate|despise)\s+(?:all|every)\s+\w+s\b/i,
            /\ball\s+\w+s\s+(?:are|should)\s+(?:die|be\s+eliminated)\b/i
          ],
          severity: :critical
        },
        violence: {
          patterns: [
            /\b(?:kill|murder|assassinate|execute)\s+(?:someone|people|them)\b/i,
            /\b(?:bomb|explode|destroy)\s+(?:the|a)\s+\w+\b/i,
            /\bhow\s+to\s+(?:kill|hurt|harm|torture)\b/i
          ],
          severity: :critical
        },
        self_harm: {
          patterns: [
            /\b(?:kill|hurt|harm)\s+(?:myself|yourself)\b/i,
            /\bsuicid(?:e|al)\b/i,
            /\bself[- ]?harm\b/i
          ],
          severity: :critical
        },
        sexual_content: {
          patterns: [
            # Simplified patterns - real implementation would be more nuanced
            /\bexplicit\s+sexual\s+content\b/i,
            /\bsexually\s+explicit\b/i
          ],
          severity: :high
        },
        profanity: {
          patterns: [
            # Common profanity patterns (simplified)
            /\b(?:damn|hell|crap)\b/i,  # Mild profanity
            # Stronger profanity would be included in production
          ],
          severity: :low
        }
      }.freeze

      attr_reader :toxicity_types, :threshold, :severity_levels

      def initialize(action: :flag, toxicity_types: nil, threshold: 0.7, 
                     severity_levels: nil, **options)
        super(action: action, **options)
        @toxicity_types = toxicity_types || TOXICITY_PATTERNS.keys
        @threshold = threshold
        @severity_levels = severity_levels || default_severity_levels
      end

      protected

      def perform_check(content, context)
        violations = []
        
        # Check each toxicity type
        @toxicity_types.each do |type|
          next unless TOXICITY_PATTERNS.key?(type)
          
          category = TOXICITY_PATTERNS[type]
          category[:patterns].each do |pattern|
            if content.match?(pattern)
              violations << {
                type: type,
                pattern: pattern.source,
                severity: category[:severity],
                description: "#{type.to_s.tr('_', ' ').capitalize} detected"
              }
            end
          end
        end
        
        return safe_result if violations.empty?
        
        # Determine action based on severity
        max_severity = violations.map { |v| v[:severity] }.max_by { |s| severity_score(s) }
        action = @severity_levels[max_severity] || @action
        
        # Create result with appropriate action
        result = violation_result(violations)
        result.instance_variable_set(:@action, action)
        result
      end

      private

      def default_severity_levels
        {
          low: :log,
          medium: :flag,
          high: :block,
          critical: :block_and_alert
        }
      end

      def severity_score(severity)
        {
          low: 1,
          medium: 2,
          high: 3,
          critical: 4
        }[severity] || 0
      end

      # Override violation_result to support custom actions
      def violation_result(violations, modified_content = nil)
        @metrics[:violations] += 1
        
        # Determine action based on severity
        max_severity = violations.map { |v| v[:severity] }.max_by { |s| severity_score(s) }
        determined_action = @severity_levels[max_severity] || @action
        
        # Handle special actions
        case determined_action
        when :block_and_alert
          alert_on_critical_violation(violations)
          determined_action = :block
        end
        
        GuardrailResult.new(
          safe: false,
          action: determined_action,
          content: modified_content,
          violations: violations,
          metadata: { 
            guardrail: self.class.name,
            toxicity_types: violations.map { |v| v[:type] }.uniq,
            max_severity: max_severity
          }
        )
      end

      def alert_on_critical_violation(violations)
        # In production, this would send alerts to monitoring systems
        @logger.error "CRITICAL TOXICITY DETECTED: #{violations.inspect}"
        
        # Could also:
        # - Send to alerting service
        # - Create incident ticket
        # - Notify security team
        # - Log to audit trail
      end
    end
  end
end
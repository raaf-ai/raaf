# frozen_string_literal: true

module RAAF
  module DSL
    module Guidelines
      # Result of guideline matching
      # Tracks which guidelines were applied and why
      class GuidelineMatchResult
        attr_reader :guideline, :matched, :match_reason, :evaluated_at

        def initialize(guideline:, matched:, match_reason: nil)
          @guideline = guideline
          @matched = matched
          @match_reason = match_reason
          @evaluated_at = Time.now
        end

        def matched?
          @matched == true
        end

        def to_h
          {
            guideline_name: @guideline.name,
            matched: @matched,
            match_reason: @match_reason,
            condition_type: @guideline.condition.class.name.split("::").last,
            evaluated_at: @evaluated_at.iso8601
          }
        end
      end

      # Result of self-critique evaluation
      # Contains per-guideline compliance status and overall verdict
      class CritiqueResult
        attr_reader :guidelines_evaluated, :violations, :passed, :critique_model,
                    :evaluated_at, :raw_response, :evaluation_duration_ms

        def initialize(
          guidelines_evaluated:,
          violations: [],
          passed: true,
          critique_model: nil,
          raw_response: nil,
          evaluation_duration_ms: nil
        )
          @guidelines_evaluated = guidelines_evaluated
          @violations = violations
          @passed = passed
          @critique_model = critique_model
          @raw_response = raw_response
          @evaluated_at = Time.now
          @evaluation_duration_ms = evaluation_duration_ms
        end

        def passed?
          @passed
        end

        def failed?
          !@passed
        end

        def violation_count
          @violations.size
        end

        def violated_guideline_names
          @violations.map { |v| v[:guideline_name] }
        end

        def to_h
          {
            passed: @passed,
            guidelines_evaluated: @guidelines_evaluated,
            violation_count: violation_count,
            violations: @violations,
            critique_model: @critique_model,
            evaluated_at: @evaluated_at.iso8601,
            evaluation_duration_ms: @evaluation_duration_ms
          }
        end

        # Create a successful result with no violations
        def self.success(guidelines_evaluated:, critique_model: nil, evaluation_duration_ms: nil)
          new(
            guidelines_evaluated: guidelines_evaluated,
            violations: [],
            passed: true,
            critique_model: critique_model,
            evaluation_duration_ms: evaluation_duration_ms
          )
        end

        # Create a failed result with violations
        def self.failure(guidelines_evaluated:, violations:, critique_model: nil, raw_response: nil, evaluation_duration_ms: nil)
          new(
            guidelines_evaluated: guidelines_evaluated,
            violations: violations,
            passed: false,
            critique_model: critique_model,
            raw_response: raw_response,
            evaluation_duration_ms: evaluation_duration_ms
          )
        end

        # Create a result when no guidelines need evaluation
        def self.no_guidelines
          new(
            guidelines_evaluated: 0,
            violations: [],
            passed: true
          )
        end
      end

      # Individual guideline violation detail
      class Violation
        attr_reader :guideline_name, :guideline_action, :reason, :severity, :output_excerpt

        def initialize(guideline_name:, guideline_action:, reason:, severity: :high, output_excerpt: nil)
          @guideline_name = guideline_name
          @guideline_action = guideline_action
          @reason = reason
          @severity = severity
          @output_excerpt = output_excerpt
        end

        def to_h
          {
            guideline_name: @guideline_name,
            guideline_action: @guideline_action,
            reason: @reason,
            severity: @severity,
            output_excerpt: @output_excerpt
          }
        end
      end

      # Aggregate result tracking all guideline operations for a single agent run
      class GuidelineExecutionLog
        attr_reader :agent_name, :started_at, :match_results, :critique_result,
                    :applied_guidelines, :constraint_text_injected

        def initialize(agent_name:)
          @agent_name = agent_name
          @started_at = Time.now
          @match_results = []
          @critique_result = nil
          @applied_guidelines = []
          @constraint_text_injected = nil
          @completed_at = nil
        end

        def add_match_result(result)
          @match_results << result
          @applied_guidelines << result.guideline if result.matched?
        end

        def set_critique_result(result)
          @critique_result = result
        end

        def set_constraint_text(text)
          @constraint_text_injected = text
        end

        def complete!
          @completed_at = Time.now
        end

        def duration_ms
          return nil unless @completed_at

          ((@completed_at - @started_at) * 1000).round(2)
        end

        def passed?
          @critique_result.nil? || @critique_result.passed?
        end

        def to_h
          {
            agent_name: @agent_name,
            started_at: @started_at.iso8601,
            completed_at: @completed_at&.iso8601,
            duration_ms: duration_ms,
            guidelines_matched: @applied_guidelines.size,
            guidelines_evaluated: @match_results.size,
            match_results: @match_results.map(&:to_h),
            critique_result: @critique_result&.to_h,
            constraint_text_length: @constraint_text_injected&.length,
            passed: passed?
          }
        end

        # Generate human-readable summary for logging
        def summary
          status = passed? ? "✓ PASSED" : "✗ FAILED"
          matched = @applied_guidelines.map(&:name).join(", ")
          matched = "none" if matched.empty?

          lines = [
            "[Guidelines] #{status} for #{@agent_name}",
            "  Matched: #{matched}",
            "  Duration: #{duration_ms}ms"
          ]

          if @critique_result&.failed?
            lines << "  Violations: #{@critique_result.violated_guideline_names.join(', ')}"
          end

          lines.join("\n")
        end
      end
    end
  end
end

# frozen_string_literal: true

module RAAF
  module Eval
    module RSpec
      module Matchers
        ##
        # Quality-related matchers for evaluation assertions
        module QualityMatchers
          ##
          # Matcher for checking if evaluation maintains quality within threshold
          module MaintainQuality
            include Base

            def initialize(*args)
              super
              @threshold = 0.7
              @across_all = false
            end

            def within(percent)
              @threshold = 1.0 - (percent / 100.0)
              self
            end

            def percent
              self
            end

            def across_all_configurations
              @across_all = true
              self
            end

            def matches?(evaluation_result)
              @evaluation_result = evaluation_result

              if @across_all
                check_all_configurations
              else
                check_single_result(evaluation_result)
              end
            end

            def failure_message
              if @across_all
                "Expected all configurations to maintain quality above #{format_percent(@threshold * 100)}, " \
                  "but #{@failures.join(', ')} failed"
              else
                "Expected quality similarity of at least #{format_percent(@threshold * 100)}, " \
                  "but got #{format_percent(@similarity * 100)}"
              end
            end

            def failure_message_when_negated
              "Expected quality to drop below #{format_percent(@threshold * 100)}, but it was maintained"
            end

            private

            def check_single_result(result)
              baseline_output = extract_output(result.is_a?(EvaluationResult) ? result.baseline : result)
              eval_output = extract_output(result)

              @similarity = Metrics.semantic_similarity(baseline_output, eval_output)
              @similarity >= @threshold
            end

            def check_all_configurations
              @failures = []

              @evaluation_result.results.each do |name, result|
                baseline_output = @evaluation_result.baseline_output
                eval_output = result[:output] || ""

                similarity = Metrics.semantic_similarity(baseline_output, eval_output)
                @failures << "#{name} (#{format_percent(similarity * 100)})" if similarity < @threshold
              end

              @failures.empty?
            end
          end

          ##
          # Matcher for checking output similarity to a target
          module HaveSimilarOutputTo
            include Base

            def initialize(target)
              super()
              @target = target
              @threshold = 0.7
            end

            def within(percent)
              @threshold = 1.0 - (percent / 100.0)
              self
            end

            def percent
              self
            end

            def matches?(evaluation_result)
              @evaluation_result = evaluation_result

              actual_output = extract_output(evaluation_result)
              target_output = resolve_target_output(@target, evaluation_result)

              @similarity = Metrics.semantic_similarity(actual_output, target_output)
              @similarity >= @threshold
            end

            def failure_message
              "Expected output similarity of at least #{format_percent(@threshold * 100)} to target, " \
                "but got #{format_percent(@similarity * 100)}"
            end

            def failure_message_when_negated
              "Expected output to differ from target by more than #{format_percent((1.0 - @threshold) * 100)}, " \
                "but similarity was #{format_percent(@similarity * 100)}"
            end

            private

            def resolve_target_output(target, evaluation_result)
              case target
              when :baseline
                evaluation_result.baseline_output
              when Symbol
                result = evaluation_result[target]
                result ? (result[:output] || "") : ""
              when String
                target
              when Hash
                extract_output(target)
              else
                target.to_s
              end
            end
          end

          ##
          # Matcher for checking output coherence
          module HaveCoherentOutput
            include Base

            def initialize(*args)
              super
              @threshold = 0.7
            end

            def with_threshold(value)
              @threshold = value
              self
            end

            def matches?(evaluation_result)
              @evaluation_result = evaluation_result
              output = extract_output(evaluation_result)

              # Check for coherence indicators
              @coherence_score = calculate_coherence(output)
              @coherence_score >= @threshold
            end

            def failure_message
              "Expected coherent output with score >= #{@threshold}, but got #{@coherence_score.round(2)}"
            end

            def failure_message_when_negated
              "Expected incoherent output with score < #{@threshold}, but got #{@coherence_score.round(2)}"
            end

            private

            def calculate_coherence(text)
              return 0.0 if text.nil? || text.empty?

              # Simplified coherence calculation
              # Real implementation would use more sophisticated NLP
              score = 0.5

              # Check for proper sentence structure
              sentences = text.split(/[.!?]+/)
              score += 0.2 if sentences.size > 1

              # Check for varied vocabulary
              words = text.downcase.split(/\W+/)
              unique_ratio = words.uniq.size.to_f / [words.size, 1].max
              score += 0.3 * unique_ratio

              [score, 1.0].min
            end
          end

          ##
          # Matcher for checking absence of hallucinations
          module NotHallucinate
            include Base

            def matches?(evaluation_result)
              @evaluation_result = evaluation_result
              output = extract_output(evaluation_result)

              # Check for hallucination indicators
              @hallucination_detected = detect_hallucination(output)
              !@hallucination_detected
            end

            def failure_message
              "Expected no hallucination, but hallucination indicators were detected in the output"
            end

            def failure_message_when_negated
              "Expected hallucination to be present, but none was detected"
            end

            private

            def detect_hallucination(text)
              return false if text.nil? || text.empty?

              # Simplified hallucination detection
              # Real implementation would use more sophisticated checks
              hallucination_patterns = [
                /I apologize, but I (don't have|cannot)/i,
                /As an AI/i,
                /I (don't|do not) actually (know|have access)/i
              ]

              hallucination_patterns.any? { |pattern| text.match?(pattern) }
            end
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module RAAF
  module Eval
    module RSpec
      module Matchers
        ##
        # G-Eval specific matchers for custom criteria evaluation
        module GEvalMatchers
          include Base

          ##
          # Matcher to check if all individual criteria passed
          ::RSpec::Matchers.define :meet_all_criteria do |min_score: 0.70|
            match do |result|
              return false unless result[:details]&.[](:criteria_evaluation)

              criteria_eval = result[:details][:criteria_evaluation]
              criteria_eval.all? { |criterion| criterion[:score] >= min_score }
            end

            def format_percent(value)
              format("%.0f%%", value)
            end

            failure_message do |result|
              criteria_eval = result[:details][:criteria_evaluation]
              failed = criteria_eval.select { |c| c[:score] < min_score }

              failed_details = failed.map do |c|
                "  - #{c[:criterion]} (#{c[:description]}): #{format_percent(c[:score] * 100)} < #{format_percent(min_score * 100)}"
              end.join("\n")

              "Expected all criteria to meet minimum score #{format_percent(min_score * 100)}, " \
                "but #{failed.size} criteria failed:\n#{failed_details}"
            end

            failure_message_when_negated do |result|
              "Expected some criteria to fail minimum score #{format_percent(min_score * 100)}, but all passed"
            end
          end

          ##
          # Matcher to check a specific criterion by name or index
          ::RSpec::Matchers.define :meet_criterion do |criterion_identifier, min_score: 0.70|
            match do |result|
              return false unless result[:details]&.[](:criteria_evaluation)

              criteria_eval = result[:details][:criteria_evaluation]

              # Find criterion by name (symbol) or index (integer)
              @criterion = if criterion_identifier.is_a?(Integer)
                             criteria_eval[criterion_identifier]
                           else
                             criteria_eval.find { |c| c[:criterion] == criterion_identifier }
                           end

              return false unless @criterion

              @criterion[:score] >= min_score
            end

            def format_percent(value)
              format("%.0f%%", value)
            end

            failure_message do |result|
              if @criterion
                "Expected criterion '#{@criterion[:criterion]}' to meet score #{format_percent(min_score * 100)}, " \
                  "but got #{format_percent(@criterion[:score] * 100)}: #{@criterion[:reasoning]}"
              else
                "Expected to find criterion '#{criterion_identifier}', but it was not found in evaluation results"
              end
            end

            failure_message_when_negated do |result|
              "Expected criterion '#{@criterion[:criterion]}' to fail score #{format_percent(min_score * 100)}, " \
                "but it passed with #{format_percent(@criterion[:score] * 100)}"
            end
          end

          ##
          # Matcher to verify chain-of-thought reasoning exists and is detailed
          ::RSpec::Matchers.define :have_chain_of_thought do |min_length: 50|
            match do |result|
              chain = result[:details]&.[](:chain_of_thought)

              return false unless chain.is_a?(String)
              return false if chain.strip.empty?

              chain.length >= min_length
            end

            failure_message do |result|
              chain = result[:details]&.[](:chain_of_thought)

              if chain.nil?
                "Expected result to have chain_of_thought in details, but it was missing"
              elsif chain.strip.empty?
                "Expected chain_of_thought to be non-empty, but it was empty"
              else
                "Expected chain_of_thought to be at least #{min_length} characters, " \
                  "but got #{chain.length} characters"
              end
            end

            failure_message_when_negated do |result|
              "Expected chain_of_thought to be absent or short, but it was present with #{result[:details][:chain_of_thought].length} characters"
            end
          end

          ##
          # Matcher to check weighted criteria evaluation
          ::RSpec::Matchers.define :respect_criteria_weights do
            match do |result|
              return false unless result[:details]&.[](:criteria_evaluation)

              criteria_eval = result[:details][:criteria_evaluation]

              # Check that weighted average matches overall score
              total_weight = criteria_eval.sum { |c| c[:weight] }
              return false if total_weight.zero?

              weighted_sum = criteria_eval.sum { |c| c[:score] * c[:weight] }
              expected_score = weighted_sum / total_weight

              # Allow small floating point difference
              (result[:score] - expected_score).abs < 0.01
            end

            def format_score(score)
              format("%.2f", score)
            end

            failure_message do |result|
              criteria_eval = result[:details][:criteria_evaluation]
              total_weight = criteria_eval.sum { |c| c[:weight] }
              weighted_sum = criteria_eval.sum { |c| c[:score] * c[:weight] }
              expected_score = weighted_sum / total_weight

              "Expected overall score to be weighted average of criteria scores (#{format_score(expected_score)}), " \
                "but got #{format_score(result[:score])}"
            end

            failure_message_when_negated do |result|
              "Expected overall score to not match weighted average, but it did"
            end
          end

          ##
          # Matcher to check criteria count
          ::RSpec::Matchers.define :evaluate_criteria_count do |expected_count|
            match do |result|
              result[:details]&.[](:criteria_count) == expected_count &&
                result[:details]&.[](:criteria_evaluation)&.size == expected_count
            end

            failure_message do |result|
              actual_count = result[:details]&.[](:criteria_evaluation)&.size || 0

              "Expected #{expected_count} criteria to be evaluated, but got #{actual_count}"
            end

            failure_message_when_negated do |result|
              "Expected criteria count to not be #{expected_count}, but it was"
            end
          end

          ##
          # Composite matcher for complete G-Eval validation
          ::RSpec::Matchers.define :be_valid_g_eval_result do
            match do |result|
              # Check standard result structure
              return false unless result[:label] && result[:score] && result[:message] && result[:details]

              # Check G-Eval specific fields
              details = result[:details]
              return false unless details[:evaluated_field]
              return false unless details[:method] == "g_eval"
              return false unless details[:criteria_count]
              return false unless details[:chain_of_thought].is_a?(String)
              return false unless details[:criteria_evaluation].is_a?(Array)

              # Check criteria evaluation structure
              details[:criteria_evaluation].all? do |criterion|
                criterion[:criterion] &&
                  criterion[:score].is_a?(Numeric) &&
                  criterion[:reasoning].is_a?(String)
              end
            end

            failure_message do |result|
              issues = []

              issues << "Missing label" unless result[:label]
              issues << "Missing score" unless result[:score]
              issues << "Missing message" unless result[:message]
              issues << "Missing details" unless result[:details]

              if result[:details]
                details = result[:details]
                issues << "Missing evaluated_field" unless details[:evaluated_field]
                issues << "Method not 'g_eval'" unless details[:method] == "g_eval"
                issues << "Missing criteria_count" unless details[:criteria_count]
                issues << "chain_of_thought not a String" unless details[:chain_of_thought].is_a?(String)
                issues << "criteria_evaluation not an Array" unless details[:criteria_evaluation].is_a?(Array)

                if details[:criteria_evaluation].is_a?(Array)
                  details[:criteria_evaluation].each_with_index do |crit, idx|
                    issues << "Criterion #{idx} missing :criterion field" unless crit[:criterion]
                    issues << "Criterion #{idx} :score not numeric" unless crit[:score].is_a?(Numeric)
                    issues << "Criterion #{idx} :reasoning not a String" unless crit[:reasoning].is_a?(String)
                  end
                end
              end

              "Expected valid G-Eval result, but found issues:\n#{issues.map { |i| "  - #{i}" }.join("\n")}"
            end

            failure_message_when_negated do |result|
              "Expected invalid G-Eval result, but result structure was valid"
            end
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module RAAF
  module Eval
    module RSpec
      module Matchers
        ##
        # Agentic evaluation matchers (Task Completion and Tool Correctness)
        module AgenticMatchers
          include Base

          ##
          # Matcher for task completion score threshold
          ::RSpec::Matchers.define :have_high_task_completion do |min_score: 0.85|
            match do |result|
              return false unless result[:details]&.[](:method) == "llm_judge"
              return false unless result[:details]&.[](:task_description)

              result[:score] >= min_score
            end

            def format_percent(value)
              format("%.0f%%", value * 100)
            end

            failure_message do |result|
              "Expected task completion score to be at least #{format_percent(min_score)}, " \
                "but got #{format_percent(result[:score])}"
            end

            failure_message_when_negated do |result|
              "Expected task completion score to be below #{format_percent(min_score)}, " \
                "but got #{format_percent(result[:score])}"
            end
          end

          ##
          # Matcher to validate task was completed successfully
          ::RSpec::Matchers.define :complete_task_successfully do
            match do |result|
              return false unless result[:details]&.[](:method) == "llm_judge"
              return false unless result[:details]&.[](:completion_analysis)

              analysis = result[:details][:completion_analysis]
              analysis[:goal_achieved] == true
            end

            failure_message do |result|
              analysis = result[:details][:completion_analysis]
              issues = analysis[:issues_found] || []
              "Expected task to be completed successfully, but goal was not achieved. " \
                "Issues: #{issues.join(', ')}"
            end

            failure_message_when_negated do |result|
              "Expected task to not be completed, but goal was achieved"
            end
          end

          ##
          # Matcher to validate required steps completion
          ::RSpec::Matchers.define :meet_task_requirements do
            match do |result|
              return false unless result[:details]&.[](:method) == "llm_judge"
              return false unless result[:details]&.[](:required_steps_provided)

              analysis = result[:details][:completion_analysis]
              steps_completed = analysis[:steps_completed]

              # Parse "4/4 steps addressed" format
              if steps_completed =~ /(\d+)\/(\d+)/
                completed = ::Regexp.last_match(1).to_i
                total = ::Regexp.last_match(2).to_i
                completed == total
              else
                false
              end
            end

            failure_message do |result|
              analysis = result[:details][:completion_analysis]
              steps = analysis[:steps_completed]
              "Expected all required steps to be completed, but got: #{steps}"
            end

            failure_message_when_negated do |result|
              "Expected some steps to be incomplete, but all steps were completed"
            end
          end

          ##
          # Matcher to validate task completion result structure
          ::RSpec::Matchers.define :be_valid_task_completion_result do
            match do |result|
              # Check standard result structure
              return false unless result[:label] && result[:score] && result[:message] && result[:details]

              # Check task completion specific fields
              details = result[:details]
              return false unless details[:method] == "llm_judge"
              return false unless details[:task_description].is_a?(String)
              return false unless details[:expected_output].is_a?(String)
              return false unless details[:actual_output].is_a?(String)
              return false unless details[:completion_analysis].is_a?(Hash)

              # Validate completion analysis structure
              analysis = details[:completion_analysis]
              return false unless [true, false].include?(analysis[:goal_achieved])
              return false unless %w[high medium low].include?(analysis[:output_quality])
              return false unless analysis[:completeness].is_a?(String)
              return false unless analysis[:reasoning].is_a?(String)

              true
            end

            failure_message do |result|
              issues = []

              issues << "Missing label" unless result[:label]
              issues << "Missing score" unless result[:score]
              issues << "Missing message" unless result[:message]
              issues << "Missing details" unless result[:details]

              if result[:details]
                details = result[:details]
                issues << "Invalid method (must be llm_judge)" unless details[:method] == "llm_judge"
                issues << "Missing or invalid task_description" unless details[:task_description].is_a?(String)
                issues << "Missing or invalid expected_output" unless details[:expected_output].is_a?(String)
                issues << "Missing or invalid actual_output" unless details[:actual_output].is_a?(String)
                issues << "Missing completion_analysis" unless details[:completion_analysis].is_a?(Hash)

                if details[:completion_analysis]
                  analysis = details[:completion_analysis]
                  issues << "Missing goal_achieved" unless [true, false].include?(analysis[:goal_achieved])
                  issues << "Invalid output_quality" unless %w[high medium low].include?(analysis[:output_quality])
                  issues << "Missing completeness" unless analysis[:completeness].is_a?(String)
                  issues << "Missing reasoning" unless analysis[:reasoning].is_a?(String)
                end
              end

              "Expected valid task completion result, but found issues:\n#{issues.map { |i| "  - #{i}" }.join("\n")}"
            end

            failure_message_when_negated do |result|
              "Expected invalid task completion result, but result structure was valid"
            end
          end

          ##
          # Matcher for tool correctness score threshold
          ::RSpec::Matchers.define :have_correct_tool_usage do |min_score: 0.85|
            match do |result|
              return false unless result[:details]&.[](:method) == "llm_judge"
              return false unless result[:details]&.[](:task_context)

              result[:score] >= min_score
            end

            def format_percent(value)
              format("%.0f%%", value * 100)
            end

            failure_message do |result|
              "Expected tool correctness score to be at least #{format_percent(min_score)}, " \
                "but got #{format_percent(result[:score])}"
            end

            failure_message_when_negated do |result|
              "Expected tool correctness score to be below #{format_percent(min_score)}, " \
                "but got #{format_percent(result[:score])}"
            end
          end

          ##
          # Matcher to validate tools were used appropriately
          ::RSpec::Matchers.define :use_tools_correctly do
            match do |result|
              return false unless result[:details]&.[](:method) == "llm_judge"
              return false unless result[:details]&.[](:tool_selection_analysis)

              analysis = result[:details][:tool_selection_analysis]
              analysis.include?("appropriate")
            end

            failure_message do |result|
              analysis = result[:details][:tool_selection_analysis]
              "Expected tools to be used correctly, but analysis shows: #{analysis}"
            end

            failure_message_when_negated do |result|
              "Expected tools to be used incorrectly, but they were used appropriately"
            end
          end

          ##
          # Matcher to validate appropriate tool selection
          ::RSpec::Matchers.define :select_appropriate_tools do
            match do |result|
              return false unless result[:details]&.[](:method) == "llm_judge"

              selection = result[:details][:tool_selection_analysis]
              selection.include?("appropriate") && !selection.include?("invalid")
            end

            failure_message do |result|
              selection = result[:details][:tool_selection_analysis]
              "Expected appropriate tool selection, but got: #{selection}"
            end

            failure_message_when_negated do |result|
              "Expected inappropriate tool selection, but selection was appropriate"
            end
          end

          ##
          # Matcher to validate tool parameters are correct
          ::RSpec::Matchers.define :have_valid_tool_parameters do
            match do |result|
              return false unless result[:details]&.[](:method) == "llm_judge"

              params = result[:details][:parameter_correctness_analysis]
              params.include?("provided") && !params.include?("missing")
            end

            failure_message do |result|
              params = result[:details][:parameter_correctness_analysis]
              "Expected valid tool parameters, but got: #{params}"
            end

            failure_message_when_negated do |result|
              "Expected invalid tool parameters, but parameters were valid"
            end
          end

          ##
          # Matcher to validate minimal tool usage issues
          ::RSpec::Matchers.define :have_minimal_tool_issues do |max_issues: 1|
            match do |result|
              return false unless result[:details]&.[](:method) == "llm_judge"

              # Issues can be in the result details or in the overall reasoning
              issues_found = result[:details][:issues_found] || []
              issues_found.size <= max_issues
            end

            failure_message do |result|
              issues = result[:details][:issues_found] || []
              "Expected at most #{max_issues} tool usage issues, but found #{issues.size}: #{issues.join(', ')}"
            end

            failure_message_when_negated do |result|
              issues = result[:details][:issues_found] || []
              "Expected more than #{max_issues} tool usage issues, but found #{issues.size}"
            end
          end

          ##
          # Matcher to validate tool correctness result structure
          ::RSpec::Matchers.define :be_valid_tool_correctness_result do
            match do |result|
              # Check standard result structure
              return false unless result[:label] && result[:score] && result[:message] && result[:details]

              # Check tool correctness specific fields
              details = result[:details]
              return false unless details[:method] == "llm_judge"
              return false unless details[:task_context].is_a?(String)
              return false unless details[:available_tools_count].is_a?(Integer)
              return false unless details[:tools_used_count].is_a?(Integer)
              return false unless details[:tool_selection_analysis].is_a?(String)
              return false unless details[:parameter_correctness_analysis].is_a?(String)
              return false unless details[:sequence_analysis].is_a?(String)
              return false unless details[:output_handling_analysis].is_a?(String)
              return false unless details[:overall_reasoning].is_a?(String)

              true
            end

            failure_message do |result|
              issues = []

              issues << "Missing label" unless result[:label]
              issues << "Missing score" unless result[:score]
              issues << "Missing message" unless result[:message]
              issues << "Missing details" unless result[:details]

              if result[:details]
                details = result[:details]
                issues << "Invalid method (must be llm_judge)" unless details[:method] == "llm_judge"
                issues << "Missing or invalid task_context" unless details[:task_context].is_a?(String)
                issues << "Missing available_tools_count" unless details[:available_tools_count].is_a?(Integer)
                issues << "Missing tools_used_count" unless details[:tools_used_count].is_a?(Integer)
                issues << "Missing tool_selection_analysis" unless details[:tool_selection_analysis].is_a?(String)
                issues << "Missing parameter_correctness_analysis" unless details[:parameter_correctness_analysis].is_a?(String)
                issues << "Missing sequence_analysis" unless details[:sequence_analysis].is_a?(String)
                issues << "Missing output_handling_analysis" unless details[:output_handling_analysis].is_a?(String)
                issues << "Missing overall_reasoning" unless details[:overall_reasoning].is_a?(String)
              end

              "Expected valid tool correctness result, but found issues:\n#{issues.map { |i| "  - #{i}" }.join("\n")}"
            end

            failure_message_when_negated do |result|
              "Expected invalid tool correctness result, but result structure was valid"
            end
          end

          ##
          # Matcher to compare task completion across different configurations
          ::RSpec::Matchers.define :have_better_task_completion_than do |baseline_result|
            match do |result|
              return false unless result[:details]&.[](:method) == "llm_judge"
              return false unless baseline_result[:details]&.[](:method) == "llm_judge"

              @result_score = result[:score]
              @baseline_score = baseline_result[:score]
              @improvement = @result_score - @baseline_score

              @result_score > @baseline_score
            end

            def format_percent(value)
              format("%.0f%%", value * 100)
            end

            failure_message do |result|
              "Expected task completion to be better than baseline, " \
                "but got #{format_percent(@result_score)} vs #{format_percent(@baseline_score)} " \
                "(#{format_percent(@improvement)} change)"
            end

            failure_message_when_negated do |result|
              "Expected task completion to not be better than baseline, " \
                "but got #{format_percent(@result_score)} vs #{format_percent(@baseline_score)} " \
                "(#{format_percent(@improvement)} improvement)"
            end
          end

          ##
          # Matcher to compare tool correctness across different configurations
          ::RSpec::Matchers.define :have_better_tool_usage_than do |baseline_result|
            match do |result|
              return false unless result[:details]&.[](:method) == "llm_judge"
              return false unless baseline_result[:details]&.[](:method) == "llm_judge"

              @result_score = result[:score]
              @baseline_score = baseline_result[:score]
              @improvement = @result_score - @baseline_score

              @result_score > @baseline_score
            end

            def format_percent(value)
              format("%.0f%%", value * 100)
            end

            failure_message do |result|
              "Expected tool usage to be better than baseline, " \
                "but got #{format_percent(@result_score)} vs #{format_percent(@baseline_score)} " \
                "(#{format_percent(@improvement)} change)"
            end

            failure_message_when_negated do |result|
              "Expected tool usage to not be better than baseline, " \
                "but got #{format_percent(@result_score)} vs #{format_percent(@baseline_score)} " \
                "(#{format_percent(@improvement)} improvement)"
            end
          end
        end
      end
    end
  end
end

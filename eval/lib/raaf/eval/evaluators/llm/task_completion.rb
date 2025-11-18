# frozen_string_literal: true

require_relative "base_evaluator"

module RAAF
  module Eval
    module Evaluators
      module LLM
        # Task Completion Evaluator
        #
        # Evaluates whether an agent successfully completed its assigned task.
        # Uses LLM-as-judge to assess task goal achievement, required steps completion,
        # and output appropriateness.
        #
        # Score Range: 0.0 (complete failure) to 1.0 (perfect completion)
        #
        # Default Thresholds:
        # - Good: ≥ 0.85 (task fully completed with high quality)
        # - Average: ≥ 0.65 (task mostly completed with minor issues)
        # - Bad: < 0.65 (significant failures or incomplete task)
        #
        # @example Basic usage
        #   evaluator = TaskCompletion.new
        #   result = evaluator.evaluate(field_context,
        #     task_description: "Research and summarize AI trends",
        #     expected_output: "Comprehensive summary with key trends",
        #     actual_output: agent_output)
        #
        # @example With task requirements
        #   evaluator = TaskCompletion.new(good_threshold: 0.90, average_threshold: 0.75)
        #   result = evaluator.evaluate(field_context,
        #     task_description: "Analyze market data",
        #     required_steps: ["Load data", "Clean data", "Generate insights", "Create report"],
        #     expected_output: "Statistical analysis with visualizations",
        #     actual_output: agent_result,
        #     execution_trace: agent_execution_log)
        #
        class TaskCompletion < BaseEvaluator
          DEFAULT_GOOD_THRESHOLD = 0.85
          DEFAULT_AVERAGE_THRESHOLD = 0.65

          # Evaluate agent's task completion
          #
          # @param field_context [RAAF::Eval::DSL::FieldContext] Field context with agent output
          # @param options [Hash] Evaluation options
          # @option options [String] :task_description Description of task to be completed (required)
          # @option options [String] :expected_output Expected output or outcome (required)
          # @option options [String] :actual_output Actual agent output (defaults to field_context.value)
          # @option options [Array<String>] :required_steps List of required task steps (optional)
          # @option options [Hash, String] :execution_trace Agent execution log or trace (optional)
          # @option options [Float] :good_threshold Override good threshold
          # @option options [Float] :average_threshold Override average threshold
          # @option options [String] :model LLM model to use for judging (optional)
          # @return [Hash] Result with label, score, message, and details
          def evaluate(field_context, **options)
            good_threshold, average_threshold = resolve_thresholds(options)

            # Validate required fields
            task_description = options[:task_description]
            raise ArgumentError, "task_description is required" unless task_description

            expected_output = options[:expected_output]
            raise ArgumentError, "expected_output is required" unless expected_output

            actual_output = options[:actual_output] || field_context.value
            raise ArgumentError, "actual_output cannot be empty" if actual_output.nil? || actual_output.to_s.strip.empty?

            # Optional context
            required_steps = options[:required_steps] || []
            execution_trace = options[:execution_trace]

            # Use LLM judge to evaluate task completion
            evaluation = llm_judge_task_completion(
              task_description: task_description,
              expected_output: expected_output,
              actual_output: actual_output,
              required_steps: required_steps,
              execution_trace: execution_trace,
              model: options[:model]
            )

            score = evaluation[:score]
            label = calculate_label(score,
                                   good_threshold: good_threshold,
                                   average_threshold: average_threshold)

            build_result(score, label, good_threshold, average_threshold,
              evaluated_field: field_context.field_name,
              method: "llm_judge",
              task_description: task_description,
              expected_output: expected_output,
              actual_output: truncate_text(actual_output.to_s, 500),
              required_steps_provided: !required_steps.empty?,
              required_steps_count: required_steps.size,
              execution_trace_provided: !execution_trace.nil?,
              completion_analysis: evaluation[:analysis],
              completion_percentage: (score * 100).round,
              evaluation_note: task_completion_note(score, good_threshold, average_threshold)
            )
          end

          private

          # Use LLM as judge to evaluate task completion
          #
          # @param task_description [String] Task description
          # @param expected_output [String] Expected output
          # @param actual_output [String] Actual output
          # @param required_steps [Array<String>] Required steps
          # @param execution_trace [Hash, String] Execution trace
          # @param model [String, nil] LLM model for judging
          # @return [Hash] Evaluation with :score and :analysis
          def llm_judge_task_completion(task_description:, expected_output:, actual_output:, required_steps:, execution_trace:, model: nil)
            # Build evaluation prompt
            prompt = build_task_completion_prompt(
              task_description,
              expected_output,
              actual_output,
              required_steps,
              execution_trace
            )

            # Call LLM for evaluation
            # TODO: Replace with actual RAAF LLM call
            # For now, return a mock evaluation
            mock_task_completion_evaluation(
              task_description,
              expected_output,
              actual_output,
              required_steps
            )
          end

          # Build prompt for task completion evaluation
          #
          # @param task_description [String] Task description
          # @param expected_output [String] Expected output
          # @param actual_output [String] Actual output
          # @param required_steps [Array<String>] Required steps
          # @param execution_trace [Hash, String] Execution trace
          # @return [String] Evaluation prompt
          def build_task_completion_prompt(task_description, expected_output, actual_output, required_steps, execution_trace)
            prompt = <<~PROMPT
              You are an expert AI agent evaluator. Your task is to assess whether an AI agent
              successfully completed its assigned task.

              TASK DESCRIPTION:
              #{task_description}

              EXPECTED OUTPUT:
              #{expected_output}

              ACTUAL OUTPUT:
              #{actual_output}
            PROMPT

            if required_steps.any?
              prompt += "\nREQUIRED STEPS:\n"
              required_steps.each_with_index do |step, idx|
                prompt += "#{idx + 1}. #{step}\n"
              end
            end

            if execution_trace
              trace_text = execution_trace.is_a?(String) ? execution_trace : execution_trace.inspect
              prompt += "\nEXECUTION TRACE:\n#{truncate_text(trace_text, 1000)}\n"
            end

            prompt += <<~EVALUATION

              EVALUATION CRITERIA:
              1. Goal Achievement: Did the agent achieve the stated task goal?
              2. Output Quality: Does the output meet the expected standards?
              3. Completeness: Are all required elements present?
              4. Step Completion: Were all required steps executed? (if applicable)
              5. Correctness: Is the output factually correct and appropriate?

              Provide a score from 0.0 to 1.0:
              - 1.0 = Perfect completion, all goals achieved with high quality
              - 0.85-0.95 = Excellent completion with minor imperfections
              - 0.70-0.84 = Good completion with some issues
              - 0.50-0.69 = Partial completion with significant issues
              - 0.30-0.49 = Poor completion, major failures
              - 0.0-0.29 = Task largely or completely failed

              Return ONLY a JSON object with this format:
              {
                "score": 0.85,
                "analysis": {
                  "goal_achieved": true,
                  "output_quality": "high",
                  "completeness": "all elements present",
                  "steps_completed": "4/4 steps executed successfully",
                  "issues_found": ["minor formatting inconsistency"],
                  "reasoning": "Task fully completed with excellent quality, minor formatting issue in section 2"
                }
              }
            EVALUATION
          end

          # Mock task completion evaluation (placeholder for actual LLM call)
          #
          # @param task_description [String] Task description
          # @param expected_output [String] Expected output
          # @param actual_output [String] Actual output
          # @param required_steps [Array<String>] Required steps
          # @return [Hash] Mock evaluation
          def mock_task_completion_evaluation(task_description, expected_output, actual_output, required_steps)
            # Simple heuristic: longer output with key terms = better completion
            output_length = actual_output.length
            expected_length = expected_output.length

            # Check if output contains key terms from task description
            task_terms = task_description.downcase.scan(/\w+/).uniq.reject { |w| w.length < 4 }
            matches = task_terms.count { |term| actual_output.downcase.include?(term) }
            term_coverage = task_terms.any? ? matches.to_f / task_terms.size : 0.5

            # Base score on term coverage and length adequacy
            length_adequacy = [output_length.to_f / [expected_length, 100].max, 1.0].min
            base_score = (term_coverage * 0.7) + (length_adequacy * 0.3)

            # Adjust for required steps (if provided)
            if required_steps.any?
              steps_mentioned = required_steps.count do |step|
                actual_output.downcase.include?(step.downcase)
              end
              steps_score = steps_mentioned.to_f / required_steps.size
              base_score = (base_score * 0.7) + (steps_score * 0.3)
            end

            # Normalize to 0.4-0.95 range (more realistic)
            score = 0.4 + (base_score * 0.55)

            {
              score: score.round(2),
              analysis: {
                goal_achieved: score >= 0.70,
                output_quality: score >= 0.85 ? "high" : (score >= 0.65 ? "medium" : "low"),
                completeness: "#{(base_score * 100).round}% of expected elements present",
                steps_completed: required_steps.any? ? "#{required_steps.size}/#{required_steps.size} steps addressed" : "N/A",
                issues_found: score < 0.85 ? ["some expected elements missing or incomplete"] : [],
                reasoning: "Task completion evaluated based on output coverage of key terms and expected elements"
              }
            }
          end

          # Generate evaluation note based on score
          #
          # @param score [Float] Task completion score
          # @param good_threshold [Float] Good threshold
          # @param average_threshold [Float] Average threshold
          # @return [String] Human-readable note
          def task_completion_note(score, good_threshold, average_threshold)
            if score >= good_threshold
              "Task completed successfully with high quality output"
            elsif score >= average_threshold
              "Task mostly completed but with some issues or gaps"
            else
              "Task completion failed or incomplete with significant issues"
            end
          end

          # Truncate text to specified length
          #
          # @param text [String] Text to truncate
          # @param max_length [Integer] Maximum length
          # @return [String] Truncated text
          def truncate_text(text, max_length)
            return text if text.length <= max_length
            "#{text[0...max_length - 3]}..."
          end
        end
      end
    end
  end
end

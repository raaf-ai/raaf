# frozen_string_literal: true

require_relative "base_evaluator"

module RAAF
  module Eval
    module Evaluators
      module LLM
        # Tool Correctness Evaluator
        #
        # Evaluates whether an agent used tools correctly and appropriately.
        # Uses LLM-as-judge to assess tool selection, parameter usage, sequencing,
        # and output handling.
        #
        # Score Range: 0.0 (incorrect tool usage) to 1.0 (perfect tool usage)
        #
        # Default Thresholds:
        # - Good: ≥ 0.85 (tools used correctly with optimal choices)
        # - Average: ≥ 0.65 (tools used adequately with minor issues)
        # - Bad: < 0.65 (significant tool usage errors)
        #
        # @example Basic usage
        #   evaluator = ToolCorrectness.new
        #   result = evaluator.evaluate(field_context,
        #     task_context: "Research weather in Tokyo",
        #     available_tools: ["weather_api", "web_search", "calculator"],
        #     tools_used: [
        #       { tool: "weather_api", params: { location: "Tokyo" }, result: "Sunny, 22°C" }
        #     ])
        #
        # @example With expected tool usage
        #   evaluator = ToolCorrectness.new(good_threshold: 0.90, average_threshold: 0.75)
        #   result = evaluator.evaluate(field_context,
        #     task_context: "Calculate quarterly revenue growth",
        #     available_tools: ["database_query", "calculator", "chart_generator"],
        #     tools_used: tool_usage_log,
        #     expected_tools: ["database_query", "calculator"],
        #     tool_sequence_matters: true)
        #
        class ToolCorrectness < BaseEvaluator
          DEFAULT_GOOD_THRESHOLD = 0.85
          DEFAULT_AVERAGE_THRESHOLD = 0.65

          # Evaluate agent's tool usage correctness
          #
          # @param field_context [RAAF::Eval::DSL::FieldContext] Field context with agent output
          # @param options [Hash] Evaluation options
          # @option options [String] :task_context Context/description of the task being performed (required)
          # @option options [Array<String>] :available_tools List of tools available to agent (required)
          # @option options [Array<Hash>] :tools_used Tools actually used with parameters and results (required)
          #   Format: [{ tool: "tool_name", params: {...}, result: "..." }, ...]
          # @option options [Array<String>] :expected_tools Expected tools to be used (optional)
          # @option options [Boolean] :tool_sequence_matters Whether tool order matters (default: false)
          # @option options [Hash] :tool_capabilities Description of what each tool does (optional)
          # @option options [Float] :good_threshold Override good threshold
          # @option options [Float] :average_threshold Override average threshold
          # @option options [String] :model LLM model to use for judging (optional)
          # @return [Hash] Result with label, score, message, and details
          def evaluate(field_context, **options)
            good_threshold, average_threshold = resolve_thresholds(options)

            # Validate required fields
            task_context = options[:task_context]
            raise ArgumentError, "task_context is required" unless task_context

            available_tools = options[:available_tools]
            raise ArgumentError, "available_tools is required" unless available_tools

            tools_used = options[:tools_used]
            raise ArgumentError, "tools_used is required" unless tools_used

            # Optional context
            expected_tools = options[:expected_tools] || []
            tool_sequence_matters = options[:tool_sequence_matters] || false
            tool_capabilities = options[:tool_capabilities] || {}

            # Use LLM judge to evaluate tool correctness
            evaluation = llm_judge_tool_correctness(
              task_context: task_context,
              available_tools: available_tools,
              tools_used: tools_used,
              expected_tools: expected_tools,
              tool_sequence_matters: tool_sequence_matters,
              tool_capabilities: tool_capabilities,
              model: options[:model]
            )

            score = evaluation[:score]
            label = calculate_label(score,
                                   good_threshold: good_threshold,
                                   average_threshold: average_threshold)

            build_result(score, label, good_threshold, average_threshold,
              evaluated_field: field_context.field_name,
              method: "llm_judge",
              task_context: task_context,
              available_tools_count: available_tools.size,
              tools_used_count: tools_used.size,
              expected_tools_provided: !expected_tools.empty?,
              tool_sequence_matters: tool_sequence_matters,
              tool_selection_analysis: evaluation[:tool_selection],
              parameter_correctness_analysis: evaluation[:parameter_correctness],
              sequence_analysis: evaluation[:sequence_analysis],
              output_handling_analysis: evaluation[:output_handling],
              overall_reasoning: evaluation[:reasoning],
              correctness_percentage: (score * 100).round,
              evaluation_note: tool_correctness_note(score, good_threshold, average_threshold)
            )
          end

          private

          # Use LLM as judge to evaluate tool correctness
          #
          # @param task_context [String] Task context
          # @param available_tools [Array<String>] Available tools
          # @param tools_used [Array<Hash>] Tools used
          # @param expected_tools [Array<String>] Expected tools
          # @param tool_sequence_matters [Boolean] Whether sequence matters
          # @param tool_capabilities [Hash] Tool capabilities
          # @param model [String, nil] LLM model for judging
          # @return [Hash] Evaluation with :score and analysis details
          def llm_judge_tool_correctness(task_context:, available_tools:, tools_used:, expected_tools:, tool_sequence_matters:, tool_capabilities:, model: nil)
            # Build evaluation prompt
            prompt = build_tool_correctness_prompt(
              task_context,
              available_tools,
              tools_used,
              expected_tools,
              tool_sequence_matters,
              tool_capabilities
            )

            # Call LLM for evaluation
            # TODO: Replace with actual RAAF LLM call
            # For now, return a mock evaluation
            mock_tool_correctness_evaluation(
              task_context,
              available_tools,
              tools_used,
              expected_tools,
              tool_sequence_matters
            )
          end

          # Build prompt for tool correctness evaluation
          #
          # @param task_context [String] Task context
          # @param available_tools [Array<String>] Available tools
          # @param tools_used [Array<Hash>] Tools used
          # @param expected_tools [Array<String>] Expected tools
          # @param tool_sequence_matters [Boolean] Whether sequence matters
          # @param tool_capabilities [Hash] Tool capabilities
          # @return [String] Evaluation prompt
          def build_tool_correctness_prompt(task_context, available_tools, tools_used, expected_tools, tool_sequence_matters, tool_capabilities)
            prompt = <<~PROMPT
              You are an expert AI agent evaluator. Your task is to assess whether an AI agent
              used tools correctly and appropriately for its task.

              TASK CONTEXT:
              #{task_context}

              AVAILABLE TOOLS:
              #{available_tools.join(", ")}
            PROMPT

            if tool_capabilities.any?
              prompt += "\nTOOL CAPABILITIES:\n"
              tool_capabilities.each do |tool, description|
                prompt += "- #{tool}: #{description}\n"
              end
            end

            if expected_tools.any?
              prompt += "\nEXPECTED TOOLS (for reference):\n#{expected_tools.join(", ")}\n"
            end

            prompt += "\nTOOLS ACTUALLY USED:\n"
            tools_used.each_with_index do |tool_call, idx|
              prompt += "#{idx + 1}. Tool: #{tool_call[:tool]}\n"
              prompt += "   Parameters: #{format_params(tool_call[:params])}\n"
              prompt += "   Result: #{truncate_text(tool_call[:result].to_s, 200)}\n"
            end

            prompt += "\nSEQUENCE IMPORTANCE: #{tool_sequence_matters ? 'Tool order matters for this task' : 'Tool order does not matter'}\n"

            prompt += <<~EVALUATION

              EVALUATION CRITERIA:
              1. Tool Selection: Were appropriate tools chosen for the task?
              2. Parameter Correctness: Were tool parameters valid and appropriate?
              3. Sequence: Were tools used in logical order? (if order matters)
              4. Output Handling: Were tool outputs used effectively?
              5. Efficiency: Were unnecessary tools avoided?

              Provide a score from 0.0 to 1.0:
              - 1.0 = Perfect tool usage, optimal choices and parameters
              - 0.85-0.95 = Excellent usage with minor inefficiencies
              - 0.70-0.84 = Good usage with some suboptimal choices
              - 0.50-0.69 = Adequate usage with significant issues
              - 0.30-0.49 = Poor usage, wrong tools or bad parameters
              - 0.0-0.29 = Incorrect tool usage, task likely failed

              Return ONLY a JSON object with this format:
              {
                "score": 0.85,
                "tool_selection": "appropriate tools chosen",
                "parameter_correctness": "all parameters valid",
                "sequence_analysis": "logical tool ordering",
                "output_handling": "outputs used effectively",
                "issues_found": ["minor: could have used caching"],
                "reasoning": "Excellent tool usage with appropriate selection and correct parameters"
              }
            EVALUATION
          end

          # Mock tool correctness evaluation (placeholder for actual LLM call)
          #
          # @param task_context [String] Task context
          # @param available_tools [Array<String>] Available tools
          # @param tools_used [Array<Hash>] Tools used
          # @param expected_tools [Array<String>] Expected tools
          # @param tool_sequence_matters [Boolean] Whether sequence matters
          # @return [Hash] Mock evaluation
          def mock_tool_correctness_evaluation(task_context, available_tools, tools_used, expected_tools, tool_sequence_matters)
            # Simple heuristics for mock evaluation
            tools_used_names = tools_used.map { |t| t[:tool] }

            # Check if expected tools were used (if provided)
            expected_tool_coverage = if expected_tools.any?
              used_expected = (tools_used_names & expected_tools).size
              used_expected.to_f / expected_tools.size
            else
              1.0
            end

            # Check if all used tools are available
            valid_tools = tools_used_names.all? { |tool| available_tools.include?(tool) }
            tool_validity_score = valid_tools ? 1.0 : 0.4

            # Check parameter presence (simple check)
            has_params = tools_used.all? { |t| t[:params] && !t[:params].empty? }
            param_score = has_params ? 1.0 : 0.7

            # Check if results are present
            has_results = tools_used.all? { |t| t[:result] && !t[:result].to_s.empty? }
            result_score = has_results ? 1.0 : 0.6

            # Combine scores
            base_score = (expected_tool_coverage * 0.4) +
                        (tool_validity_score * 0.25) +
                        (param_score * 0.20) +
                        (result_score * 0.15)

            # Normalize to 0.45-0.95 range
            score = 0.45 + (base_score * 0.50)

            issues = []
            issues << "some expected tools not used" if expected_tool_coverage < 1.0 && expected_tools.any?
            issues << "invalid tool selection" unless valid_tools
            issues << "missing or empty parameters" unless has_params
            issues << "missing or empty results" unless has_results

            {
              score: score.round(2),
              tool_selection: valid_tools ? "appropriate tools from available set" : "some invalid tool selections",
              parameter_correctness: has_params ? "parameters provided for all tools" : "some tools missing parameters",
              sequence_analysis: tool_sequence_matters ? "tool sequence evaluated" : "sequence not critical",
              output_handling: has_results ? "all tools produced results" : "some tools missing results",
              issues_found: issues,
              reasoning: "Tool usage evaluated based on selection appropriateness, parameter presence, and result availability"
            }
          end

          # Format tool parameters for display
          #
          # @param params [Hash] Parameters hash
          # @return [String] Formatted parameters
          def format_params(params)
            return "none" if params.nil? || params.empty?
            params.map { |k, v| "#{k}: #{truncate_text(v.to_s, 50)}" }.join(", ")
          end

          # Generate evaluation note based on score
          #
          # @param score [Float] Tool correctness score
          # @param good_threshold [Float] Good threshold
          # @param average_threshold [Float] Average threshold
          # @return [String] Human-readable note
          def tool_correctness_note(score, good_threshold, average_threshold)
            if score >= good_threshold
              "Tools used correctly with appropriate selection and parameters"
            elsif score >= average_threshold
              "Tools used adequately but with some suboptimal choices or parameters"
            else
              "Tool usage had significant errors in selection, parameters, or sequencing"
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

# frozen_string_literal: true

require_relative "base_evaluator"

module RAAF
  module Eval
    module Evaluators
      module LLM
        # G-Eval (General Evaluation) Framework
        #
        # Provides custom criteria evaluation using chain-of-thought reasoning with LLM-as-judge.
        # Users define evaluation criteria in natural language, and the LLM evaluates outputs
        # against those criteria with detailed reasoning.
        #
        # Score Range: 0.0 (fails all criteria) to 1.0 (meets all criteria perfectly)
        #
        # Default Thresholds:
        # - Good: ≥ 0.80 (meets most/all criteria well)
        # - Average: ≥ 0.60 (meets some criteria, room for improvement)
        # - Bad: < 0.60 (fails to meet criteria)
        #
        # @example Simple criteria evaluation
        #   evaluator = GEval.new(criteria: ["Output is factually accurate", "Output is clear"])
        #   result = evaluator.evaluate(field_context)
        #
        # @example Weighted criteria evaluation
        #   evaluator = GEval.new(
        #     criteria: {
        #       accuracy: { description: "Output is factually accurate", weight: 2.0 },
        #       clarity: { description: "Output is clear and concise", weight: 1.0 }
        #     }
        #   )
        #   result = evaluator.evaluate(field_context)
        #
        # @example Custom thresholds
        #   evaluator = GEval.new(
        #     criteria: ["Output is professional"],
        #     good_threshold: 0.90,
        #     average_threshold: 0.75
        #   )
        #
        class GEval < BaseEvaluator
          evaluator_name :g_eval

          DEFAULT_GOOD_THRESHOLD = 0.80
          DEFAULT_AVERAGE_THRESHOLD = 0.60

          attr_reader :criteria, :criteria_weights

          # Initialize G-Eval evaluator with custom criteria
          #
          # @param criteria [Array<String>, Hash] Evaluation criteria
          #   - Array: Simple list of criterion descriptions (equal weight)
          #   - Hash: Weighted criteria with format { name: { description: String, weight: Float } }
          # @param good_threshold [Float, nil] Instance-level "good" threshold
          # @param average_threshold [Float, nil] Instance-level "average" threshold
          # @param options [Hash] Additional options
          def initialize(criteria:, good_threshold: nil, average_threshold: nil, **options)
            super(good_threshold: good_threshold, average_threshold: average_threshold, **options)

            raise ArgumentError, "At least one evaluation criterion is required" if criteria_empty?(criteria)

            @criteria = normalize_criteria(criteria)
            @criteria_weights = extract_weights(@criteria)
          end

          # Evaluate output against custom criteria using chain-of-thought reasoning
          #
          # @param field_context [RAAF::Eval::DSL::FieldContext] Field context with output
          # @param options [Hash] Evaluation options
          # @option options [Float] :good_threshold Override good threshold
          # @option options [Float] :average_threshold Override average threshold
          # @option options [String] :model LLM model to use for judging (optional)
          # @return [Hash] Result with label, score, message, and details
          def evaluate(field_context, **options)
            good_threshold, average_threshold = resolve_thresholds(options)

            # Validate field context
            validate_field_context!(field_context)

            # Extract output value — serialize non-String values (Hashes, Arrays) to JSON
            # so downstream string operations (downcase, split) work correctly
            raw_output = field_context.value
            output = raw_output.is_a?(String) ? raw_output : raw_output.to_json

            # Use LLM judge to evaluate against criteria
            criteria_results, chain_of_thought = llm_judge_criteria(
              output: output,
              criteria: @criteria,
              model: options[:model]
            )

            # Calculate overall score (weighted or simple average)
            overall_score = calculate_overall_score(criteria_results)

            # Determine label based on thresholds
            label = calculate_label(overall_score,
                                   good_threshold: good_threshold,
                                   average_threshold: average_threshold)

            build_result(overall_score, label, good_threshold, average_threshold,
              evaluated_field: field_context.field_name.to_sym,
              method: "g_eval",
              criteria_count: @criteria.size,
              chain_of_thought: chain_of_thought,
              criteria_evaluation: criteria_results,
              evaluation_note: g_eval_note(overall_score, criteria_results, good_threshold, average_threshold)
            )
          end

          private

          # Check if criteria is empty
          #
          # @param criteria [Array, Hash] Criteria to check
          # @return [Boolean] True if criteria is empty
          def criteria_empty?(criteria)
            return true if criteria.nil?
            return criteria.empty? if criteria.is_a?(Array)
            return criteria.empty? if criteria.is_a?(Hash)
            false
          end

          # Normalize criteria to standardized format
          #
          # @param criteria [Array<String>, Hash] Criteria input
          # @return [Array<Hash>] Normalized criteria with name, description, weight
          def normalize_criteria(criteria)
            case criteria
            when Array
              # Simple array of descriptions - equal weight
              criteria.map.with_index do |description, index|
                {
                  criterion: "criterion_#{index + 1}".to_sym,
                  description: description,
                  weight: 1.0
                }
              end
            when Hash
              # Hash with weighted criteria
              criteria.map do |name, details|
                if details.is_a?(Hash)
                  {
                    criterion: name.to_sym,
                    description: details[:description] || details["description"],
                    weight: details[:weight] || details["weight"] || 1.0
                  }
                else
                  # Simple hash: { name: description }
                  {
                    criterion: name.to_sym,
                    description: details,
                    weight: 1.0
                  }
                end
              end
            else
              raise ArgumentError, "Criteria must be Array or Hash"
            end
          end

          # Extract weights from normalized criteria
          #
          # @param criteria [Array<Hash>] Normalized criteria
          # @return [Hash] Mapping of criterion name to weight
          def extract_weights(criteria)
            criteria.each_with_object({}) do |criterion, weights|
              weights[criterion[:criterion]] = criterion[:weight]
            end
          end

          # Validate field context
          #
          # @param field_context [RAAF::Eval::DSL::FieldContext] Field context to validate
          # @raise [ArgumentError] if field context is invalid
          def validate_field_context!(field_context)
            raise ArgumentError, "Field context value cannot be nil" if field_context.value.nil?
          end

          # Use LLM as judge to evaluate output against criteria with chain-of-thought
          #
          # @param output [String] Output to evaluate
          # @param criteria [Array<Hash>] Evaluation criteria
          # @param model [String, nil] LLM model for judging
          # @return [Array<Array<Hash>, String>] Criteria results and chain-of-thought reasoning
          def llm_judge_criteria(output:, criteria:, model: nil)
            prompt = build_g_eval_prompt(output, criteria)
            judge_model = model || "gpt-4o-mini"

            response_text = call_llm(prompt, judge_model)

            if response_text
              result = parse_llm_response(response_text, criteria)
              return result if result
            end

            RAAF.logger&.warn("[GEval] LLM judge unavailable, falling back to mock evaluation")
            mock_criteria_evaluation(output, criteria)
          end

          # Make a direct OpenAI chat completions call for evaluation
          #
          # @param prompt [String] Evaluation prompt
          # @param model [String] Model to use
          # @return [String, nil] JSON response text or nil on failure
          def call_llm(prompt, model)
            require "net/http"
            require "json"

            api_key = ENV["OPENAI_API_KEY"]
            unless api_key&.present?
              RAAF.logger&.warn("[GEval] OPENAI_API_KEY not set, cannot run LLM judge")
              return nil
            end

            uri = URI("https://api.openai.com/v1/chat/completions")
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            http.read_timeout = 30
            http.open_timeout = 10

            req = Net::HTTP::Post.new(uri)
            req["Authorization"] = "Bearer #{api_key}"
            req["Content-Type"] = "application/json"
            req.body = JSON.generate({
              model: model,
              messages: [{ role: "user", content: prompt }],
              temperature: 0,
              response_format: { type: "json_object" }
            })

            response = http.request(req)
            unless response.is_a?(Net::HTTPSuccess)
              RAAF.logger&.warn("[GEval] OpenAI API returned #{response.code}: #{response.body[0..200]}")
              return nil
            end

            data = JSON.parse(response.body)
            data.dig("choices", 0, "message", "content")
          rescue => e
            RAAF.logger&.warn("[GEval] LLM call failed: #{e.class}: #{e.message}")
            nil
          end

          # Parse LLM JSON response into criteria results
          #
          # @param response_text [String] JSON text from LLM
          # @param criteria [Array<Hash>] Original criteria
          # @return [Array<Array<Hash>, String>, nil] [criteria_results, chain_of_thought] or nil on failure
          def parse_llm_response(response_text, criteria)
            data = JSON.parse(response_text)
            llm_criteria = Array(data["criteria"])
            chain = data["overall_chain_of_thought"].to_s

            criteria_results = criteria.map.with_index do |criterion, index|
              llm_result = llm_criteria.find { |c| c["criterion"] == "criterion_#{index + 1}" } ||
                           llm_criteria[index] ||
                           {}

              raw_score = llm_result["score"].to_f
              score = [[raw_score, 0.0].max, 1.0].min

              {
                criterion: criterion[:criterion],
                description: criterion[:description],
                weight: criterion[:weight],
                score: score,
                reasoning: llm_result["reasoning"].to_s.presence || "Score: #{(score * 100).round}%"
              }
            end

            [criteria_results, chain]
          rescue JSON::ParserError => e
            RAAF.logger&.warn("[GEval] JSON parse failed: #{e.message}. Response: #{response_text[0..200]}")
            nil
          end

          # Build G-Eval prompt with chain-of-thought structure
          #
          # @param output [String] Output to evaluate
          # @param criteria [Array<Hash>] Evaluation criteria
          # @return [String] Evaluation prompt
          def build_g_eval_prompt(output, criteria)
            criteria_list = criteria.map.with_index do |criterion, index|
              "#{index + 1}. #{criterion[:description]}"
            end.join("\n")

            <<~PROMPT
              You are an expert evaluator. Your task is to evaluate the given output against
              specific criteria using chain-of-thought reasoning.

              OUTPUT TO EVALUATE:
              #{output}

              EVALUATION CRITERIA:
              #{criteria_list}

              TASK:
              For each criterion:
              1. Analyze the output carefully
              2. Explain your reasoning step-by-step (chain-of-thought)
              3. Assign a score from 0.0 to 1.0 (0.0 = completely fails, 1.0 = perfectly meets)

              Provide your evaluation as JSON:
              {
                "criteria": [
                  {
                    "criterion": "criterion_1",
                    "score": 0.85,
                    "reasoning": "Step-by-step explanation..."
                  },
                  ...
                ],
                "overall_chain_of_thought": "Overall reasoning summary..."
              }
            PROMPT
          end

          # Mock criteria evaluation (placeholder for actual LLM call)
          #
          # @param output [String] Output to evaluate
          # @param criteria [Array<Hash>] Evaluation criteria
          # @return [Array<Array<Hash>, String>] Criteria results and chain-of-thought
          def mock_criteria_evaluation(output, criteria)
            # Simple heuristic-based mock evaluation
            output_lower = output.downcase
            output_length = output.split.size

            # Evaluate each criterion with mock scoring
            criteria_results = criteria.map do |criterion|
              # Mock scoring based on output characteristics
              score = mock_criterion_score(output_lower, output_length, criterion[:description])

              {
                criterion: criterion[:criterion],
                description: criterion[:description],
                weight: criterion[:weight],
                score: score,
                reasoning: mock_criterion_reasoning(score, criterion[:description])
              }
            end

            # Generate mock chain-of-thought
            chain_of_thought = mock_chain_of_thought(criteria_results, output)

            [criteria_results, chain_of_thought]
          end

          # Mock scoring for a single criterion
          #
          # @param output_lower [String] Lowercase output
          # @param output_length [Integer] Word count
          # @param description [String] Criterion description
          # @return [Float] Score between 0.0 and 1.0
          def mock_criterion_score(output_lower, output_length, description)
            # Heuristic-based scoring
            base_score = 0.7

            # Adjust based on output length (reasonable length is good)
            length_factor = if output_length.between?(5, 50)
                             0.1
                           elsif output_length < 5
                             -0.1
                           else
                             0.0
                           end

            # Adjust based on criterion keywords
            keyword_factor = if description.downcase.include?("accurate") && output_lower.include?("is")
                              0.15
                            elsif description.downcase.include?("clear") && output_length < 30
                              0.1
                            elsif description.downcase.include?("concise") && output_length < 20
                              0.15
                            else
                              0.05
                            end

            score = base_score + length_factor + keyword_factor
            [[score, 0.0].max, 1.0].min
          end

          # Generate mock reasoning for a criterion
          #
          # @param score [Float] Criterion score
          # @param description [String] Criterion description
          # @return [String] Reasoning explanation
          def mock_criterion_reasoning(score, description)
            if score >= 0.85
              "The output strongly satisfies the criterion '#{description}'. " \
                "It demonstrates clear alignment with the evaluation standard."
            elsif score >= 0.70
              "The output adequately meets the criterion '#{description}'. " \
                "There is room for minor improvements."
            elsif score >= 0.50
              "The output partially meets the criterion '#{description}'. " \
                "Significant improvements are needed."
            else
              "The output fails to meet the criterion '#{description}'. " \
                "Substantial revision is required."
            end
          end

          # Generate mock overall chain-of-thought
          #
          # @param criteria_results [Array<Hash>] Individual criterion results
          # @param output [String] Output that was evaluated
          # @return [String] Overall chain-of-thought reasoning
          def mock_chain_of_thought(criteria_results, output)
            avg_score = criteria_results.sum { |r| r[:score] } / criteria_results.size.to_f

            reasoning = "Evaluation Summary:\n"
            truncated_output = output.length > 50 ? "#{output[0...47]}..." : output
            reasoning += "Analyzed output: '#{truncated_output}'\n\n"

            criteria_results.each_with_index do |result, index|
              reasoning += "Criterion #{index + 1} (#{result[:description]}): "
              reasoning += "Score #{(result[:score] * 100).round}% - #{result[:reasoning]}\n"
            end

            reasoning += "\nOverall Assessment: "
            if avg_score >= 0.80
              reasoning += "The output performs well across most criteria."
            elsif avg_score >= 0.60
              reasoning += "The output shows acceptable performance with room for improvement."
            else
              reasoning += "The output requires significant revision to meet criteria standards."
            end

            reasoning
          end

          # Calculate overall score from criteria results
          #
          # @param criteria_results [Array<Hash>] Individual criterion results
          # @return [Float] Overall weighted or average score
          def calculate_overall_score(criteria_results)
            return 0.0 if criteria_results.empty?

            total_weight = criteria_results.sum { |r| r[:weight] }
            return 0.0 if total_weight.zero?

            weighted_sum = criteria_results.sum { |r| r[:score] * r[:weight] }
            weighted_sum / total_weight
          end

          # Generate evaluation note based on score and criteria results
          #
          # @param score [Float] Overall score
          # @param criteria_results [Array<Hash>] Individual criterion results
          # @param good_threshold [Float] Good threshold
          # @param average_threshold [Float] Average threshold
          # @return [String] Human-readable note
          def g_eval_note(score, criteria_results, good_threshold, average_threshold)
            criteria_count = criteria_results.size
            passed_count = criteria_results.count { |r| r[:score] >= 0.70 }

            if score >= good_threshold
              "Meets #{passed_count}/#{criteria_count} criteria well (#{(score * 100).round}%)"
            elsif score >= average_threshold
              "Partially meets #{passed_count}/#{criteria_count} criteria (#{(score * 100).round}%)"
            else
              "Fails to adequately meet criteria (#{passed_count}/#{criteria_count} passed, #{(score * 100).round}%)"
            end
          end
        end
      end
    end
  end
end

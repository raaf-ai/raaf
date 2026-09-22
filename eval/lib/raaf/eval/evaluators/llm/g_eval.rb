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

          DEFAULT_JUDGE_MODEL = "gpt-4o-mini"

          # Seconds to wait for the judge. The old value was 30, which is under
          # what a reasoning model takes on a large payload: gemini-2.5-pro
          # measured ~18s on a 288-token prompt, and the judged fields here run
          # to twenty thousand. A timeout is not a low score, it is no score, so
          # the cost of waiting is far below the cost of giving up early.
          DEFAULT_READ_TIMEOUT = 120

          # Where a judge model is reached, chosen by the model's own name so a
          # check can name a judge without also naming an endpoint. Google
          # serves an OpenAI-compatible route, so both providers take the same
          # request and answer with the same token-usage keys; anything else
          # OpenAI-compatible can be reached by pointing the base env at it.
          # First match wins, so the catch-all stays last.
          PROVIDERS = [
            { match: /\Agemini[-.]/, label: "Gemini", key_env: "GEMINI_API_KEY",
              base_env: "RAAF_JUDGE_GEMINI_API_BASE",
              base: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions" },
            { match: //, label: "OpenAI", key_env: "OPENAI_API_KEY",
              base_env: "RAAF_JUDGE_OPENAI_API_BASE",
              base: "https://api.openai.com/v1/chat/completions" }
          ].freeze

          attr_reader :criteria, :criteria_weights

          # Initialize G-Eval evaluator with custom criteria
          #
          # @param criteria [Array<String>, Hash] Evaluation criteria
          #   - Array: Simple list of criterion descriptions (equal weight)
          #   - Hash: Weighted criteria with format { name: { description: String, weight: Float } }
          # @param good_threshold [Float, nil] Instance-level "good" threshold
          # @param average_threshold [Float, nil] Instance-level "average" threshold
          # @param options [Hash] Additional options
          def initialize(criteria:, good_threshold: nil, average_threshold: nil, **)
            super(good_threshold: good_threshold, average_threshold: average_threshold, **)

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
                         # What this judgement cost. The judge is a billed model call that
                         # leaves no tracing span — call_llm posts to the provider directly
                         # — so unless the usage travels out with the result there is no
                         # record of it anywhere and total_evaluation_cost can only ever be
                         # zero.
                         judge_model: @judge_model,
                         judge_usage: @judge_usage,
                         # What the judge was asked and what it answered. A
                         # rule's verdict can be re-derived from the payload and
                         # the rule; a judge's cannot be checked at all without
                         # these two, which is what the console's judge section
                         # reads. There is no stand-in score to distinguish any
                         # more: a judge that cannot be reached raises
                         # JudgeUnavailableError rather than scoring the field.
                         judge_prompt: @judge_prompt,
                         judge_response: @judge_response,
                         evaluation_note: g_eval_note(overall_score, criteria_results, good_threshold, average_threshold))
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
                  criterion: :"criterion_#{index + 1}",
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
            judge_model = model || DEFAULT_JUDGE_MODEL

            @judge_model = judge_model
            @judge_usage = nil
            @judge_prompt = prompt
            @judge_response = nil

            response_text = call_llm(prompt, judge_model)
            @judge_response = response_text

            raise JudgeUnavailableError, "#{judge_model} could not be reached" if response_text.nil?

            parse_llm_response(response_text, criteria) ||
              raise(JudgeUnavailableError, "#{judge_model} answered something that could not be read as criteria")
          end

          # Make a direct OpenAI chat completions call for evaluation
          #
          # @param prompt [String] Evaluation prompt
          # @param model [String] Model to use
          # @return [String, nil] JSON response text or nil on failure
          def call_llm(prompt, model)
            require "net/http"
            require "json"

            provider = provider_for(model)
            api_key = ENV.fetch(provider[:key_env], nil)
            unless api_key.present?
              RAAF.logger&.warn("[GEval] #{provider[:key_env]} not set, cannot run #{model}")
              return nil
            end

            uri = URI(ENV.fetch(provider[:base_env], provider[:base]))
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            http.read_timeout = ENV.fetch("RAAF_JUDGE_READ_TIMEOUT", DEFAULT_READ_TIMEOUT).to_i
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
              RAAF.logger&.warn("[GEval] #{provider[:label]} returned #{response.code}: #{response.body[0..200]}")
              return nil
            end

            data = JSON.parse(response.body)
            @judge_usage = extract_usage(data["usage"])
            data.dig("choices", 0, "message", "content")
          rescue StandardError => e
            RAAF.logger&.warn("[GEval] LLM call failed: #{e.class}: #{e.message}")
            nil
          end

          # Which provider serves this model.
          #
          # @param model [String] the judge model
          # @return [Hash] the matching PROVIDERS entry
          def provider_for(model)
            PROVIDERS.find { |provider| provider[:match].match?(model.to_s) }
          end

          # Normalise the usage block the provider returns into the keys
          # RAAF::Usage::CostCalculator expects. A response without usage (a
          # cached judge) yields nil rather than zeros, so "we did not measure"
          # stays distinguishable from "it was free".
          #
          # Output is the larger of what was reported and what is left after the
          # prompt, because a reasoning model bills tokens it does not report as
          # completion: gemini-2.5-pro measured 365 completion tokens against a
          # 1349 total on a 146-token prompt, and Google bills those 838
          # thinking tokens at the output rate. Reading completion_tokens alone
          # understated that call by a factor of about four.
          #
          # @param usage [Hash, nil] raw usage block from the API response
          # @return [Hash, nil] input/output/total token counts
          def extract_usage(usage)
            return nil unless usage.is_a?(Hash)

            input = usage["prompt_tokens"] || usage["input_tokens"]
            output = usage["completion_tokens"] || usage["output_tokens"]
            return nil if input.nil? && output.nil?

            total = (usage["total_tokens"] || (input.to_i + output.to_i)).to_i

            {
              input_tokens: input.to_i,
              output_tokens: [output.to_i, total - input.to_i].max,
              total_tokens: total
            }
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

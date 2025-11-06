# frozen_string_literal: true

module RAAF
  module Eval
    module Metrics
      ##
      # AIComparator uses an AI model to compare outputs qualitatively
      class AIComparator
        def initialize(model: nil)
          @model = model || RAAF::Eval.configuration.ai_comparator_model
        end

        ##
        # Compare baseline and result outputs using AI
        # @param baseline_output [String] Baseline output
        # @param result_output [String] Result output
        # @param context [Hash, nil] Additional context for comparison
        # @return [Hash] AI comparison metrics
        def compare(baseline_output, result_output, context: nil)
          return skip_comparison unless RAAF::Eval.configuration.enable_ai_comparator

          agent = create_comparator_agent
          runner = RAAF::Runner.new(agent: agent)

          prompt = build_comparison_prompt(baseline_output, result_output, context)
          result = runner.run(prompt)

          parse_comparison_result(result)
        rescue StandardError => e
          RAAF::Eval.logger.error("AI comparison failed: #{e.message}")
          comparison_error(e)
        end

        private

        def skip_comparison
          {
            status: "skipped",
            reason: "AI comparator disabled"
          }
        end

        def create_comparator_agent
          RAAF::Agent.new(
            name: "EvalComparator",
            instructions: comparator_instructions,
            model: @model
          )
        end

        def comparator_instructions
          <<~INSTRUCTIONS
            You are an expert evaluator comparing two AI-generated outputs.
            
            Analyze the outputs and provide:
            1. Semantic similarity score (0.0 to 1.0)
            2. Coherence score (0.0 to 1.0)
            3. Whether hallucinations are detected (true/false)
            4. Bias detection across gender, race, and region (true/false for each)
            5. Tone consistency score (0.0 to 1.0)
            6. Factuality score (0.0 to 1.0)
            7. Brief reasoning for your assessment
            
            Return your analysis in JSON format.
          INSTRUCTIONS
        end

        def build_comparison_prompt(baseline, result, context)
          prompt = "Compare these two outputs:\n\n"
          prompt += "BASELINE OUTPUT:\n#{baseline}\n\n"
          prompt += "RESULT OUTPUT:\n#{result}\n\n"
          prompt += "CONTEXT: #{context.inspect}\n\n" if context
          prompt += "Provide your analysis in JSON format."
          prompt
        end

        def parse_comparison_result(result)
          content = result.messages.last[:content] || result.messages.last["content"]
          
          # Try to extract JSON from the response
          json_match = content.match(/\{.*\}/m)
          if json_match
            parsed = JSON.parse(json_match[0])
            normalize_comparison_result(parsed)
          else
            default_comparison_result(content)
          end
        rescue JSON::ParserError
          default_comparison_result(content)
        end

        def normalize_comparison_result(parsed)
          {
            semantic_similarity_score: parsed["semantic_similarity"] || parsed["semantic_similarity_score"] || 0.5,
            coherence_score: parsed["coherence"] || parsed["coherence_score"] || 0.5,
            hallucination_detected: parsed["hallucination_detected"] || false,
            bias_detected: {
              gender: parsed.dig("bias_detected", "gender") || false,
              race: parsed.dig("bias_detected", "race") || false,
              region: parsed.dig("bias_detected", "region") || false
            },
            tone_consistency: parsed["tone_consistency"] || 0.5,
            factuality_score: parsed["factuality"] || parsed["factuality_score"] || 0.5,
            comparison_reasoning: parsed["reasoning"] || parsed["explanation"] || "No reasoning provided"
          }
        end

        def default_comparison_result(content)
          {
            semantic_similarity_score: 0.5,
            coherence_score: 0.5,
            hallucination_detected: false,
            bias_detected: { gender: false, race: false, region: false },
            tone_consistency: 0.5,
            factuality_score: 0.5,
            comparison_reasoning: content || "Default comparison"
          }
        end

        def comparison_error(error)
          {
            status: "failed",
            error: error.message,
            semantic_similarity_score: nil,
            coherence_score: nil,
            comparison_reasoning: "Comparison failed: #{error.message}"
          }
        end
      end
    end
  end
end

# frozen_string_literal: true

require "json"
require_relative "guideline_result"

module RAAF
  module DSL
    module Guidelines
      # SelfCritiqueEngine verifies agent responses against applicable guidelines
      #
      # This engine implements Parlant's self-critique pattern:
      # After response generation, the engine checks each applicable guideline
      # and returns pass/fail status with detailed violation information.
      #
      # @example Basic usage
      #   engine = SelfCritiqueEngine.new(llm_provider: provider)
      #   result = engine.critique(
      #     output: agent_response,
      #     guidelines: applicable_guidelines,
      #     context: { company_name: "Acme" }
      #   )
      #
      #   if result.failed?
      #     puts "Violations: #{result.violations.map(&:reason)}"
      #   end
      #
      class SelfCritiqueEngine
        # Default model for critique - fast and cost-effective
        DEFAULT_CRITIQUE_MODEL = "gpt-4o-mini"
        DEFAULT_TIMEOUT = 30
        DEFAULT_MAX_TOKENS = 1000
        DEFAULT_TEMPERATURE = 0.1

        attr_reader :llm_provider, :critique_model, :timeout

        # @param llm_provider [Object] LLM provider for critique requests
        # @param critique_model [String] Model to use for critique (default: gpt-4o-mini)
        # @param timeout [Integer] Timeout in seconds for critique request
        def initialize(llm_provider:, critique_model: DEFAULT_CRITIQUE_MODEL, timeout: DEFAULT_TIMEOUT)
          @llm_provider = llm_provider
          @critique_model = critique_model
          @timeout = timeout
        end

        # Verify agent output against applicable guidelines
        #
        # @param output [String, Hash] The agent's response to verify
        # @param guidelines [Array<Guideline>] Guidelines to check against
        # @param context [Hash] Execution context for reference
        # @return [CritiqueResult] Result with pass/fail and violation details
        def critique(output:, guidelines:, context: {})
          return CritiqueResult.no_guidelines if guidelines.empty?

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          begin
            prompt = build_critique_prompt(output, guidelines, context)

            response = execute_critique(prompt)
            violations = parse_critique_response(response, guidelines)

            duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

            if violations.empty?
              CritiqueResult.success(
                guidelines_evaluated: guidelines.size,
                critique_model: @critique_model,
                evaluation_duration_ms: duration_ms
              )
            else
              CritiqueResult.failure(
                guidelines_evaluated: guidelines.size,
                violations: violations,
                critique_model: @critique_model,
                raw_response: response,
                evaluation_duration_ms: duration_ms
              )
            end
          rescue StandardError => e
            RAAF.logger.error "[SelfCritique] Critique failed: #{e.message}"
            RAAF.logger.error e.backtrace.first(5).join("\n") if e.backtrace

            # On error, pass through (fail open for reliability)
            CritiqueResult.success(
              guidelines_evaluated: guidelines.size,
              critique_model: @critique_model
            )
          end
        end

        # Verify a single guideline (for selective verification)
        #
        # @param output [String, Hash] The agent's response
        # @param guideline [Guideline] Single guideline to verify
        # @param context [Hash] Execution context
        # @return [Boolean] true if compliant, false if violated
        def verify_guideline(output:, guideline:, context: {})
          result = critique(output: output, guidelines: [guideline], context: context)
          result.passed?
        end

        private

        # Build the critique prompt for the LLM
        def build_critique_prompt(output, guidelines, context)
          output_text = output.is_a?(Hash) ? JSON.pretty_generate(output) : output.to_s
          context_text = context.empty? ? "None provided" : JSON.pretty_generate(context)

          guidelines_text = guidelines.map.with_index do |g, i|
            verification = g.verification_prompt(output)
            <<~GUIDELINE
              ## Guideline #{i + 1}: #{g.name}
              Priority: #{g.priority.upcase}
              Requirement: #{g.action}
              Verification Instructions: #{verification}
            GUIDELINE
          end.join("\n")

          <<~PROMPT
            You are a strict compliance verifier. Your task is to check if an AI agent's response
            follows the specified behavioral guidelines. Be thorough but fair.

            # AGENT OUTPUT TO VERIFY
            ```
            #{output_text.truncate(3000)}
            ```

            # CONTEXT
            #{context_text.truncate(500)}

            # GUIDELINES TO CHECK
            #{guidelines_text}

            # YOUR TASK
            For each guideline, determine if the output COMPLIES or VIOLATES.

            Respond with a JSON object in this EXACT format:
            {
              "evaluations": [
                {
                  "guideline_name": "name_of_guideline",
                  "compliant": true_or_false,
                  "reason": "Brief explanation of why compliant or why violated",
                  "severity": "high|medium|low",
                  "excerpt": "Quote from output showing compliance or violation (optional)"
                }
              ],
              "overall_passed": true_or_false,
              "summary": "One sentence summary of evaluation"
            }

            IMPORTANT:
            - Be strict about compliance but don't be overly pedantic
            - If unclear, lean toward compliance (benefit of the doubt)
            - Focus on the spirit of the guideline, not just the letter
            - Consider context when evaluating
          PROMPT
        end

        # Execute the critique request to the LLM
        def execute_critique(prompt)
          Timeout.timeout(@timeout) do
            response = @llm_provider.chat_completion(
              messages: [{ role: "user", content: prompt }],
              model: @critique_model,
              max_tokens: DEFAULT_MAX_TOKENS,
              temperature: DEFAULT_TEMPERATURE
            )

            extract_content(response)
          end
        end

        # Extract content from LLM response (handles different response formats)
        def extract_content(response)
          # Handle different provider response formats
          content = response.dig(:choices, 0, :message, :content) ||
                    response.dig("choices", 0, "message", "content") ||
                    response.dig(:content) ||
                    response.dig("content") ||
                    response.to_s

          content.to_s.strip
        end

        # Parse the critique response and extract violations
        def parse_critique_response(response, guidelines)
          violations = []

          begin
            # Extract JSON from response (may be wrapped in markdown)
            json_str = extract_json(response)
            result = JSON.parse(json_str, symbolize_names: true)

            evaluations = result[:evaluations] || []

            evaluations.each do |eval|
              next if eval[:compliant]

              guideline_name = eval[:guideline_name]&.to_sym
              guideline = guidelines.find { |g| g.name == guideline_name }

              next unless guideline

              violations << Violation.new(
                guideline_name: guideline_name,
                guideline_action: guideline.action,
                reason: eval[:reason] || "No reason provided",
                severity: (eval[:severity] || "high").to_sym,
                output_excerpt: eval[:excerpt]
              ).to_h
            end
          rescue JSON::ParserError => e
            RAAF.logger.warn "[SelfCritique] Failed to parse JSON response: #{e.message}"
            # Try simple text-based parsing as fallback
            violations = parse_text_response(response, guidelines)
          end

          violations
        end

        # Extract JSON from potentially markdown-wrapped response
        def extract_json(response)
          # Try to extract JSON from markdown code blocks
          if response.include?("```json")
            match = response.match(/```json\s*\n?(.*?)\n?```/m)
            return match[1].strip if match
          end

          if response.include?("```")
            match = response.match(/```\s*\n?(.*?)\n?```/m)
            return match[1].strip if match
          end

          # Try to find JSON object directly
          match = response.match(/\{.*\}/m)
          return match[0] if match

          response
        end

        # Fallback text-based parsing when JSON fails
        def parse_text_response(response, guidelines)
          violations = []
          response_lower = response.downcase

          guidelines.each do |guideline|
            name_str = guideline.name.to_s.downcase

            # Look for violation indicators
            violation_patterns = [
              /#{name_str}.*(?:violat|fail|not.+compli|non-?compli)/i,
              /(?:violat|fail).*#{name_str}/i
            ]

            if violation_patterns.any? { |pattern| response_lower.match?(pattern) }
              violations << Violation.new(
                guideline_name: guideline.name,
                guideline_action: guideline.action,
                reason: "Detected violation in critique response (text-based parsing)",
                severity: :medium
              ).to_h
            end
          end

          violations
        end
      end
    end
  end
end

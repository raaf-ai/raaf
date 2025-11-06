# frozen_string_literal: true

require "digest"

module RAAF
  module Eval
    module RSpec
      ##
      # LLM Judge for subjective quality evaluation
      #
      # This class uses an AI model as a judge to evaluate outputs based on
      # natural language criteria.
      class LLMJudge
        attr_reader :model, :temperature, :cache_enabled

        ##
        # Creates a new LLM judge
        #
        # @param config [Hash] judge configuration
        # @option config [String] :model the model to use for judging
        # @option config [Float] :temperature temperature for judge model
        # @option config [Boolean] :cache whether to cache judge results
        # @option config [Integer] :timeout timeout in seconds
        def initialize(config = {})
          @model = config[:model] || "gpt-4o"
          @temperature = config[:temperature] || 0.3
          @cache_enabled = config.fetch(:cache, true)
          @timeout = config[:timeout] || 30
          @cache = {}
          @retry_count = 1
        end

        ##
        # Performs a simple check
        #
        # @param output [String] the output to judge
        # @param check_prompt [String] the check to perform
        # @return [Hash] judgment result with :passed, :confidence, :reasoning
        def check(output, check_prompt)
          cache_key = generate_cache_key("check", output, check_prompt)

          if @cache_enabled && @cache.key?(cache_key)
            return @cache[cache_key]
          end

          result = execute_check(output, check_prompt)

          @cache[cache_key] = result if @cache_enabled
          result
        rescue StandardError => e
          {
            passed: false,
            confidence: 0.0,
            reasoning: "Judge execution failed: #{e.message}",
            error: e.message
          }
        end

        ##
        # Performs multi-criteria check
        #
        # @param output [String] the output to judge
        # @param criteria [Array<Hash>] array of criteria with :name, :description, :weight
        # @return [Hash] judgment result with :passed, :criteria
        def check_criteria(output, criteria)
          cache_key = generate_cache_key("criteria", output, criteria.to_s)

          if @cache_enabled && @cache.key?(cache_key)
            return @cache[cache_key]
          end

          result = execute_criteria_check(output, criteria)

          @cache[cache_key] = result if @cache_enabled
          result
        rescue StandardError => e
          {
            passed: false,
            criteria: [],
            reasoning: "Criteria check failed: #{e.message}",
            error: e.message
          }
        end

        ##
        # Judges a single output
        #
        # @param output [String] the output to judge
        # @param prompt [String] the judgment prompt
        # @return [Hash] judgment result
        def judge_single(output, prompt)
          cache_key = generate_cache_key("judge_single", output, prompt)

          if @cache_enabled && @cache.key?(cache_key)
            return @cache[cache_key]
          end

          result = execute_judgment(output, nil, prompt)

          @cache[cache_key] = result if @cache_enabled
          result
        rescue StandardError => e
          {
            passed: false,
            reasoning: "Judgment failed: #{e.message}",
            error: e.message
          }
        end

        ##
        # Judges output against a target
        #
        # @param output [String] the output to judge
        # @param target [String] the target to compare against
        # @param prompt [String] the judgment prompt
        # @return [Hash] judgment result
        def judge(output, target, prompt)
          cache_key = generate_cache_key("judge", output, target, prompt)

          if @cache_enabled && @cache.key?(cache_key)
            return @cache[cache_key]
          end

          result = execute_judgment(output, target, prompt)

          @cache[cache_key] = result if @cache_enabled
          result
        rescue StandardError => e
          {
            passed: false,
            reasoning: "Judgment failed: #{e.message}",
            error: e.message
          }
        end

        ##
        # Clears the judgment cache
        def clear_cache
          @cache.clear
        end

        private

        def generate_cache_key(*parts)
          Digest::SHA256.hexdigest(parts.join("|"))
        end

        def execute_check(output, check_prompt)
          prompt = build_check_prompt(output, check_prompt)

          response = call_judge_model(prompt)

          parse_check_response(response)
        end

        def execute_criteria_check(output, criteria)
          prompt = build_criteria_prompt(output, criteria)

          response = call_judge_model(prompt)

          parse_criteria_response(response, criteria)
        end

        def execute_judgment(output, target, prompt)
          response = call_judge_model(prompt)

          parse_judgment_response(response)
        end

        def build_check_prompt(output, check_prompt)
          <<~PROMPT
            You are an AI judge evaluating output quality. Determine if the following output satisfies this criterion:

            Criterion: #{check_prompt}

            Output to evaluate:
            #{output}

            Respond in JSON format with:
            {
              "passed": true/false,
              "confidence": 0.0-1.0,
              "reasoning": "explanation of your decision"
            }
          PROMPT
        end

        def build_criteria_prompt(output, criteria)
          criteria_list = criteria.map.with_index do |c, i|
            "#{i + 1}. #{c[:name]}: #{c[:description]} (weight: #{c[:weight]})"
          end.join("\n")

          <<~PROMPT
            You are an AI judge evaluating output quality against multiple criteria. Evaluate the following output:

            Output to evaluate:
            #{output}

            Criteria to check:
            #{criteria_list}

            Respond in JSON format with:
            {
              "criteria": [
                {
                  "name": "criterion_name",
                  "passed": true/false,
                  "reasoning": "explanation"
                }
              ]
            }
          PROMPT
        end

        def call_judge_model(prompt)
          # Create a simple agent to act as judge
          judge_agent = RAAF::Agent.new(
            name: "Judge",
            instructions: "You are a helpful AI judge evaluating outputs objectively.",
            model: @model
          )

          runner = RAAF::Runner.new(agent: judge_agent)

          # Call with retry
          attempts = 0
          begin
            result = runner.run(prompt, temperature: @temperature)
            result.messages.last[:content]
          rescue StandardError => e
            attempts += 1
            retry if attempts <= @retry_count
            raise
          end
        end

        def parse_check_response(response)
          # Try to extract JSON from response
          json_match = response.match(/\{.*\}/m)
          if json_match
            parsed = JSON.parse(json_match[0])
            {
              passed: parsed["passed"],
              confidence: parsed["confidence"] || 0.8,
              reasoning: parsed["reasoning"] || "No reasoning provided"
            }
          else
            # Fallback parsing
            {
              passed: response.match?(/\bpassed?\b.*\btrue\b/i) || response.match?(/\byes\b/i),
              confidence: 0.6,
              reasoning: response
            }
          end
        rescue JSON::ParserError
          {
            passed: response.match?(/\bpassed?\b.*\btrue\b/i) || response.match?(/\byes\b/i),
            confidence: 0.5,
            reasoning: response
          }
        end

        def parse_criteria_response(response, criteria)
          # Try to extract JSON from response
          json_match = response.match(/\{.*\}/m)
          if json_match
            parsed = JSON.parse(json_match[0])
            criteria_results = parsed["criteria"] || []

            {
              passed: criteria_results.all? { |c| c["passed"] },
              criteria: criteria_results.map do |c|
                {
                  name: c["name"],
                  passed: c["passed"],
                  reasoning: c["reasoning"] || "No reasoning provided"
                }
              end
            }
          else
            # Fallback
            {
              passed: false,
              criteria: criteria.map { |c| { name: c[:name], passed: false, reasoning: "Parse failed" } }
            }
          end
        rescue JSON::ParserError
          {
            passed: false,
            criteria: criteria.map { |c| { name: c[:name], passed: false, reasoning: "Parse error" } }
          }
        end

        def parse_judgment_response(response)
          # Extract decision from response
          json_match = response.match(/\{.*\}/m)
          if json_match
            parsed = JSON.parse(json_match[0])
            {
              passed: parsed["passed"] || parsed["result"],
              reasoning: parsed["reasoning"] || parsed["explanation"] || "No reasoning provided"
            }
          else
            {
              passed: response.match?(/\byes\b/i) || response.match?(/\btrue\b/i),
              reasoning: response
            }
          end
        rescue JSON::ParserError
          {
            passed: response.match?(/\byes\b/i) || response.match?(/\btrue\b/i),
            reasoning: response
          }
        end
      end
    end
  end
end

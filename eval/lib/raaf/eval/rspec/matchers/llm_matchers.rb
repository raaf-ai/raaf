# frozen_string_literal: true

require_relative "../llm_judge"

module RAAF
  module Eval
    module RSpec
      module Matchers
        ##
        # LLM-powered matchers for subjective quality assessments
        module LLMMatchers
          ##
          # New label-specific matchers
          module LabelMatchers
            ::RSpec::Matchers.define :be_good do
              match do |evaluation_result|
                label = evaluation_result.is_a?(Hash) ? evaluation_result[:label] : evaluation_result.label
                label == "good"
              end

              failure_message do |evaluation_result|
                label = evaluation_result.is_a?(Hash) ? evaluation_result[:label] : evaluation_result.label
                "Expected label to be 'good', but got '#{label}'"
              end
            end

            ::RSpec::Matchers.define :be_average do
              match do |evaluation_result|
                label = evaluation_result.is_a?(Hash) ? evaluation_result[:label] : evaluation_result.label
                label == "average"
              end

              failure_message do |evaluation_result|
                label = evaluation_result.is_a?(Hash) ? evaluation_result[:label] : evaluation_result.label
                "Expected label to be 'average', but got '#{label}'"
              end
            end

            ::RSpec::Matchers.define :be_bad do
              match do |evaluation_result|
                label = evaluation_result.is_a?(Hash) ? evaluation_result[:label] : evaluation_result.label
                label == "bad"
              end

              failure_message do |evaluation_result|
                label = evaluation_result.is_a?(Hash) ? evaluation_result[:label] : evaluation_result.label
                "Expected label to be 'bad', but got '#{label}'"
              end
            end

            ::RSpec::Matchers.define :be_at_least do |expected_level|
              match do |evaluation_result|
                label = evaluation_result.is_a?(Hash) ? evaluation_result[:label] : evaluation_result.label
                levels = { "bad" => 0, "average" => 1, "good" => 2 }
                levels[label] >= levels[expected_level]
              end

              failure_message do |evaluation_result|
                label = evaluation_result.is_a?(Hash) ? evaluation_result[:label] : evaluation_result.label
                "Expected label to be at least '#{expected_level}', but got '#{label}'"
              end
            end
          end

          ##
          # Matcher for natural language assertions using LLM judge
          module SatisfyLLMCheck
            include Base

            def initialize(prompt)
              super()
              @check_prompt = prompt
              @judge_model = nil
              @confidence_threshold = 0.7
            end

            def using_model(model)
              @judge_model = model
              self
            end

            def with_confidence(threshold)
              @confidence_threshold = threshold
              self
            end

            def matches?(evaluation_result)
              @evaluation_result = evaluation_result
              output = extract_output(evaluation_result)

              # Get judge configuration
              config = judge_config(@judge_model)

              # Create judge
              judge = LLMJudge.new(config)

              # Execute check
              @judgment = judge.check(output, @check_prompt)

              # Check label instead of passed field
              label = @judgment.is_a?(Hash) ? @judgment[:label] : @judgment.label
              label == "good" && @judgment[:confidence] >= @confidence_threshold
            end

            def failure_message
              label = @judgment.is_a?(Hash) ? @judgment[:label] : @judgment.label
              "Expected output to satisfy '#{@check_prompt}' with 'good' label, " \
                "but got '#{label}': #{@judgment[:reasoning]} " \
                "(confidence: #{format_percent(@judgment[:confidence] * 100)})"
            end

            def failure_message_when_negated
              "Expected output to not satisfy '#{@check_prompt}', but it did"
            end

            private

            def judge_config(model)
              {
                model: model || RAAF::Eval::RSpec.configuration.llm_judge_model,
                temperature: RAAF::Eval::RSpec.configuration.llm_judge_temperature,
                cache: RAAF::Eval::RSpec.configuration.llm_judge_cache,
                timeout: RAAF::Eval::RSpec.configuration.llm_judge_timeout
              }
            end
          end

          ##
          # Matcher for multi-criteria LLM evaluation
          module SatisfyLLMCriteria
            include Base

            def initialize(criteria)
              super()
              @criteria = criteria
              @judge_model = nil
            end

            def using_model(model)
              @judge_model = model
              self
            end

            def matches?(evaluation_result)
              @evaluation_result = evaluation_result
              output = extract_output(evaluation_result)

              # Get judge configuration
              config = judge_config(@judge_model)

              # Create judge
              judge = LLMJudge.new(config)

              # Normalize criteria
              normalized_criteria = normalize_criteria(@criteria)

              # Execute multi-criteria check
              @judgment = judge.check_criteria(output, normalized_criteria)

              # Check if all criteria have good or average labels (not bad)
              label = @judgment.is_a?(Hash) ? @judgment[:label] : @judgment.label
              label != "bad"
            end

            def failure_message
              failed = @judgment[:criteria].select { |c| c[:label] == "bad" }
              details = failed.map { |c| "- #{c[:name]} (#{c[:label]}): #{c[:reasoning]}" }.join("\n")

              "Expected output to satisfy all criteria (not 'bad'), but #{failed.size} failed:\n#{details}"
            end

            def failure_message_when_negated
              "Expected output to fail criteria, but all passed (no 'bad' labels)"
            end

            private

            def judge_config(model)
              {
                model: model || RAAF::Eval::RSpec.configuration.llm_judge_model,
                temperature: RAAF::Eval::RSpec.configuration.llm_judge_temperature,
                cache: RAAF::Eval::RSpec.configuration.llm_judge_cache,
                timeout: RAAF::Eval::RSpec.configuration.llm_judge_timeout
              }
            end

            def normalize_criteria(criteria)
              case criteria
              when Array
                # Simple array of criterion descriptions
                criteria.map.with_index { |desc, i| { name: "criterion_#{i + 1}", description: desc, weight: 1.0 } }
              when Hash
                # Hash with criterion names and details
                criteria.map do |name, details|
                  if details.is_a?(Hash)
                    { name: name, description: details[:description], weight: details[:weight] || 1.0 }
                  else
                    { name: name, description: details, weight: 1.0 }
                  end
                end
              else
                raise ArgumentError, "Criteria must be Array or Hash"
              end
            end
          end

          ##
          # Matcher for flexible quality judgments
          module BeJudgedAs
            include Base

            def initialize(description)
              super()
              @judgment_description = description
              @comparison_target = nil
              @judge_model = nil
            end

            def than(target)
              @comparison_target = target
              self
            end

            def using_model(model)
              @judge_model = model
              self
            end

            def matches?(evaluation_result)
              @evaluation_result = evaluation_result
              output = extract_output(evaluation_result)

              # Get judge configuration
              config = judge_config(@judge_model)

              # Create judge
              judge = LLMJudge.new(config)

              # Build judgment prompt
              if @comparison_target
                target_output = resolve_target_output(@comparison_target, evaluation_result)
                prompt = build_comparison_prompt(output, target_output, @judgment_description)
                @judgment = judge.judge(output, target_output, prompt)
              else
                prompt = build_judgment_prompt(output, @judgment_description)
                @judgment = judge.judge_single(output, prompt)
              end

              # Check if label is good or average (not bad)
              label = @judgment.is_a?(Hash) ? @judgment[:label] : @judgment.label
              label != "bad"
            end

            def failure_message
              label = @judgment.is_a?(Hash) ? @judgment[:label] : @judgment.label
              if @comparison_target
                "Expected output to be judged as '#{@judgment_description}' compared to #{@comparison_target}, " \
                  "but got label '#{label}': #{@judgment[:reasoning]}"
              else
                "Expected output to be judged as '#{@judgment_description}', " \
                  "but got label '#{label}': #{@judgment[:reasoning]}"
              end
            end

            def failure_message_when_negated
              "Expected output to not be judged as '#{@judgment_description}', but it was"
            end

            private

            def judge_config(model)
              {
                model: model || RAAF::Eval::RSpec.configuration.llm_judge_model,
                temperature: RAAF::Eval::RSpec.configuration.llm_judge_temperature,
                cache: RAAF::Eval::RSpec.configuration.llm_judge_cache,
                timeout: RAAF::Eval::RSpec.configuration.llm_judge_timeout
              }
            end

            def resolve_target_output(target, evaluation_result)
              case target
              when :baseline
                evaluation_result.baseline_output
              when Symbol
                result = evaluation_result[target]
                result ? (result[:output] || "") : ""
              when String
                target
              else
                target.to_s
              end
            end

            def build_comparison_prompt(output, target, description)
              "Compare the following two outputs and determine if the first output is #{description} compared to the second.\n\n" \
                "First output:\n#{output}\n\n" \
                "Second output:\n#{target}\n\n" \
                "Is the first output #{description} compared to the second? Provide reasoning."
            end

            def build_judgment_prompt(output, description)
              "Evaluate the following output and determine if it can be described as '#{description}'.\n\n" \
                "Output:\n#{output}\n\n" \
                "Does this output match the description '#{description}'? Provide reasoning."
            end
          end

          ##
          # DeepEval-inspired specific matchers for LLM quality evaluation
          module DeepEvalMatchers
            include Base

            # Hallucination matchers
            ::RSpec::Matchers.define :have_hallucinations do |threshold: 0.90|
              match do |result|
                result[:score] < threshold
              end

              failure_message do |result|
                "Expected hallucinations (score < #{threshold}), but got score #{result[:score]}"
              end

              failure_message_when_negated do |result|
                "Expected no hallucinations (score ≥ #{threshold}), but got score #{result[:score]}"
              end
            end

            ::RSpec::Matchers.define :be_factually_accurate do |threshold: 0.90|
              match do |result|
                result[:label] == "good" && result[:score] >= threshold
              end

              failure_message do |result|
                "Expected factually accurate output (good label, score ≥ #{threshold}), " \
                  "but got label '#{result[:label]}' with score #{result[:score]}"
              end
            end

            # Answer relevancy matchers
            ::RSpec::Matchers.define :have_answer_relevancy do |threshold: 0.80|
              match do |result|
                result[:score] >= threshold
              end

              failure_message do |result|
                "Expected answer relevancy score ≥ #{threshold}, but got #{result[:score]}"
              end
            end

            ::RSpec::Matchers.define :be_relevant_to_query do |threshold: 0.80|
              match do |result|
                result[:label] != "bad" && result[:score] >= threshold
              end

              failure_message do |result|
                "Expected relevant answer (not bad, score ≥ #{threshold}), " \
                  "but got label '#{result[:label]}' with score #{result[:score]}"
              end
            end

            # Faithfulness matchers (RAG-specific)
            ::RSpec::Matchers.define :be_faithful_to_context do |threshold: 0.90|
              match do |result|
                result[:score] >= threshold
              end

              failure_message do |result|
                "Expected faithfulness to context (score ≥ #{threshold}), " \
                  "but got score #{result[:score]}"
              end
            end

            # Bias matchers
            ::RSpec::Matchers.define :have_bias do |threshold: 0.90|
              match do |result|
                result[:score] < threshold
              end

              failure_message do |result|
                "Expected bias (score < #{threshold}), but got score #{result[:score]}"
              end

              failure_message_when_negated do |result|
                "Expected no bias (score ≥ #{threshold}), but got score #{result[:score]}"
              end
            end

            ::RSpec::Matchers.define :be_unbiased do |threshold: 0.90|
              match do |result|
                result[:label] == "good" && result[:score] >= threshold
              end

              failure_message do |result|
                "Expected unbiased content (good label, score ≥ #{threshold}), " \
                  "but got label '#{result[:label]}' with score #{result[:score]}"
              end
            end

            # Toxicity matchers
            ::RSpec::Matchers.define :be_toxic do |threshold: 0.95|
              match do |result|
                result[:score] < threshold
              end

              failure_message do |result|
                "Expected toxic content (score < #{threshold}), but got score #{result[:score]}"
              end

              failure_message_when_negated do |result|
                "Expected safe content (score ≥ #{threshold}), but got score #{result[:score]}"
              end
            end

            ::RSpec::Matchers.define :be_safe do |threshold: 0.95|
              match do |result|
                result[:label] == "good" && result[:score] >= threshold
              end

              failure_message do |result|
                "Expected safe content (good label, score ≥ #{threshold}), " \
                  "but got label '#{result[:label]}' with score #{result[:score]}"
              end
            end

            # Generic threshold matcher
            ::RSpec::Matchers.define :meet_quality_threshold do |expected_threshold|
              match do |result|
                result[:score] >= expected_threshold
              end

              failure_message do |result|
                "Expected score ≥ #{expected_threshold}, but got #{result[:score]} " \
                  "(label: #{result[:label]})"
              end

              failure_message_when_negated do |result|
                "Expected score < #{expected_threshold}, but got #{result[:score]}"
              end
            end

            # Composite matcher for multiple evaluations
            ::RSpec::Matchers.define :pass_all_evaluations do
              match do |results|
                return false unless results.is_a?(Hash)

                results.values.all? do |result|
                  result[:label] == "good" || result[:label] == "average"
                end
              end

              failure_message do |results|
                failed = results.select { |_, v| v[:label] == "bad" }
                "Expected all evaluations to pass (good or average), but #{failed.size} failed: " \
                  "#{failed.keys.join(', ')}"
              end
            end
          end
        end
      end
    end
  end
end

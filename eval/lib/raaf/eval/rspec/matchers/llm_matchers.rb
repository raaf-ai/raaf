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

              @judgment[:passed] && @judgment[:confidence] >= @confidence_threshold
            end

            def failure_message
              "Expected output to satisfy '#{@check_prompt}', " \
                "but judge ruled: #{@judgment[:reasoning]} " \
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

              @judgment[:passed]
            end

            def failure_message
              failed = @judgment[:criteria].select { |c| !c[:passed] }
              details = failed.map { |c| "- #{c[:name]}: #{c[:reasoning]}" }.join("\n")

              "Expected output to satisfy all criteria, but #{failed.size} failed:\n#{details}"
            end

            def failure_message_when_negated
              "Expected output to fail criteria, but all passed"
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

              @judgment[:passed]
            end

            def failure_message
              if @comparison_target
                "Expected output to be judged as '#{@judgment_description}' compared to #{@comparison_target}, " \
                  "but judge ruled: #{@judgment[:reasoning]}"
              else
                "Expected output to be judged as '#{@judgment_description}', " \
                  "but judge ruled: #{@judgment[:reasoning]}"
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
        end
      end
    end
  end
end

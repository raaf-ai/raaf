# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # Scores one experiment result with the scorers the experiment declares.
    #
    # An experiment has been able to name its scorers since the edit screen was
    # built — a list of `field:evaluator` checks with weights, drawn from the
    # same registry a continuous policy reads, so the two cannot end up calling
    # one check by two names. Nothing read that list. `ExperimentEngine` took
    # scoring as a block, the console passed no block, and every run recorded an
    # empty scores hash. The screens then had nothing to colour, order or
    # compare, which is the whole of why an experiment's results could not be
    # judged.
    #
    # This turns the declared list into the block the engine was always missing.
    #
    # @example
    #   scorer = ExperimentScorer.new(experiment)
    #   scorer.call(dataset_item, agent_output)
    #   # => { "quality:value_range" => 0.92 }
    #
    class ExperimentScorer
      # A check is named `field:evaluator_type`, the same spelling a policy
      # weights it under.
      CHECK_SEPARATOR = ":"

      # @param experiment [Models::Experiment]
      def initialize(experiment)
        @experiment = experiment
      end

      ##
      # Whether this experiment declares anything to score with. An experiment
      # that names no scorer gets no block, so the engine records the run
      # without pretending it was graded.
      #
      # @return [Boolean]
      def scorable?
        enabled_scorers.any?
      end

      ##
      # @param item [Models::DatasetItem] the case being scored
      # @param output [Hash] what the agent produced for it
      # @return [Hash] score per declared check, keyed as the check is named
      def call(item, output)
        return {} unless scorable?

        subject = subject_for(item, output)

        enabled_scorers.group_by { |scorer| scorer[:evaluator] }
                       .each_with_object({}) do |(evaluator_name, scorers), scores|
          scores.merge!(scores_from(evaluator_name, scorers, subject))
        end
      end

      ##
      # What each check the experiment picked says it measures, so a result can
      # carry it rather than have the console read the evaluator back when
      # somebody opens the screen. That reconstruction answers for the
      # evaluator of the same name today, which is a different object as soon
      # as anybody widens a bound.
      #
      # @return [Array<Hash>] one entry per declared check, empty where the
      #   evaluators describe none
      def declared_checks
        enabled_scorers.filter_map { |scorer| declared_check(scorer) }
      end

      private

      def enabled_scorers
        @enabled_scorers ||= @experiment.scorers.select { |scorer| scorer[:enabled] }
      end

      def declared_check(scorer)
        field, type = scorer[:check].to_s.split(CHECK_SEPARATOR, 2)

        declared_for(scorer[:evaluator]).find do |check|
          check[:field_name].to_s == field && (type.nil? || check[:evaluator_type].to_s == type)
        end
      end

      # Read once per evaluator: an experiment usually takes several checks
      # from one, and the class answers the same for all of them.
      def declared_for(evaluator_name)
        @declared_for ||= {}
        key = evaluator_name.to_s
        return @declared_for[key] if @declared_for.key?(key)

        @declared_for[key] = read_declared(evaluator_name)
      end

      def read_declared(evaluator_name)
        klass = RAAF::Eval::Continuous::EvaluatorDiscovery.find_custom_evaluator_by_name(evaluator_name)
        return [] unless klass.respond_to?(:evaluated_checks)

        Array(klass.evaluated_checks)
      rescue StandardError => e
        RAAF::Eval.logger.warn("Could not read checks for '#{evaluator_name}': #{e.message}")
        []
      end

      ##
      # One evaluator answers for every check the experiment picked from it, so
      # it runs once and its fields are read off the single result.
      #
      # An evaluator that raises takes its own checks down and leaves the rest
      # of the run scored. A failed scorer is not a failed case: recording zero
      # would say the agent answered badly when what broke was the measurement.
      def scores_from(evaluator_name, scorers, subject)
        result = evaluate(evaluator_name, subject)
        return {} if result.nil?

        fields = result.field_results || {}

        scorers.each_with_object({}) do |scorer, scores|
          score = field_score(fields, scorer[:check])
          scores[scorer[:check]] = score unless score.nil?
        end
      end

      def evaluate(evaluator_name, subject)
        evaluator = RAAF::Eval::Continuous::EvaluatorDiscovery.build({ "name" => evaluator_name })
        evaluator.evaluate(subject)
      rescue StandardError => e
        RAAF::Eval.logger.warn("Experiment scorer '#{evaluator_name}' failed: #{e.message}")
        nil
      end

      # A check names the field ahead of the colon. What comes after it is the
      # evaluator that graded the field, which the result does not key by.
      def field_score(fields, check)
        field = check.to_s.split(CHECK_SEPARATOR).first
        entry = fields[field.to_sym] || fields[field]
        return nil unless entry.is_a?(Hash)

        value = entry[:score] || entry["score"]
        value&.to_f
      end

      ##
      # What the evaluators are handed. The same shape the continuous job builds
      # out of a span, so an evaluator cannot tell whether it is grading
      # production traffic or a dataset case, and grades both the same way.
      def subject_for(item, output)
        text = output_text(output)

        base = { agent_name: @experiment.agent_name, model: @experiment.model,
                 provider: @experiment.provider,
                 input_messages: item.input_messages,
                 output: text, output_text: text,
                 expected_output: item.expected_output,
                 metadata: item.metadata || {} }

        structured = structured_output(output)
        structured.is_a?(Hash) ? base.merge(symbolize(structured)) : base
      end

      def output_text(output)
        return output.to_s unless output.is_a?(Hash)

        content = output[:content] || output["content"]
        content.presence&.to_s || JSON.generate(output)
      end

      # An agent answering with a schema puts its fields where an evaluator
      # reads them, rather than leaving them inside a JSON string it would have
      # to parse itself.
      def structured_output(output)
        return nil unless output.is_a?(Hash)

        parsed = output[:parsed] || output["parsed"]
        return parsed if parsed.is_a?(Hash)

        output.except(:messages, "messages", :content, "content").presence
      end

      def symbolize(hash)
        hash.each_with_object({}) { |(key, value), out| out[key.to_sym] = value }
      end
    end
  end
end

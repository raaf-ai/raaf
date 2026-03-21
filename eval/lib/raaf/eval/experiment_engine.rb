# frozen_string_literal: true

module RAAF
  module Eval
    ##
    # ExperimentEngine orchestrates running experiments against datasets.
    # Inspired by Opik's experiment management system.
    #
    # The engine handles:
    # - Running an agent against every item in a dataset
    # - Collecting outputs and computing scores
    # - Aggregating results and metrics
    #
    # @example Running an experiment
    #   engine = ExperimentEngine.new
    #   experiment = engine.create_experiment(
    #     name: "GPT-4o Customer Support Test",
    #     dataset: dataset,
    #     agent_name: "CustomerSupportAgent",
    #     model: "gpt-4o",
    #     configuration: { temperature: 0.7 }
    #   )
    #
    #   engine.run_experiment(experiment) do |item, output|
    #     # Custom scoring callback
    #     { relevance: score_relevance(item, output) }
    #   end
    class ExperimentEngine
      ##
      # Create a new experiment
      # @param name [String] Experiment name
      # @param dataset [Models::Dataset] Dataset to evaluate against
      # @param agent_name [String] Agent being tested
      # @param model [String] Model to use
      # @param provider [String] Provider name
      # @param configuration [Hash] Agent configuration
      # @param created_by [String] Creator identifier
      # @return [Models::Experiment]
      def create_experiment(name:, dataset:, agent_name: nil, model: nil, provider: nil, configuration: {}, created_by: nil)
        Models::Experiment.create!(
          name: name,
          dataset: dataset,
          agent_name: agent_name,
          model: model,
          provider: provider,
          configuration: configuration,
          created_by: created_by
        )
      end

      ##
      # Run an experiment, executing the agent against each dataset item.
      # Accepts an optional block for custom scoring.
      #
      # @param experiment [Models::Experiment] The experiment to run
      # @param agent [RAAF::Agent, nil] Agent instance to use (optional)
      # @param runner [RAAF::Runner, nil] Runner instance to use (optional)
      # @yield [item, output] Block for custom scoring
      # @yieldparam item [Models::DatasetItem] The dataset item
      # @yieldparam output [Hash] The agent's output
      # @yieldreturn [Hash] Custom scores
      # @return [Models::Experiment]
      def run_experiment(experiment, agent: nil, runner: nil, &scoring_block)
        experiment.start!

        experiment.dataset.dataset_items.find_each do |item|
          run_single_item(experiment, item, agent: agent, runner: runner, &scoring_block)
        end

        experiment.complete!
        experiment
      rescue StandardError => e
        experiment.fail!(e)
        raise
      end

      ##
      # Compare two experiments side by side
      # @param experiment_a [Models::Experiment] First experiment
      # @param experiment_b [Models::Experiment] Second experiment
      # @return [Hash] Comparison results
      def compare_experiments(experiment_a, experiment_b)
        {
          experiments: {
            a: experiment_summary(experiment_a),
            b: experiment_summary(experiment_b)
          },
          metrics_comparison: compare_metrics(experiment_a, experiment_b),
          item_comparison: compare_items(experiment_a, experiment_b)
        }
      end

      private

      def run_single_item(experiment, item, agent: nil, runner: nil, &scoring_block)
        start_time = Time.current
        output = execute_agent(item, agent: agent, runner: runner, experiment: experiment)
        end_time = Time.current

        scores = scoring_block ? scoring_block.call(item, output) : {}

        experiment.record_result!(
          dataset_item: item,
          output: output,
          scores: scores,
          token_metrics: extract_token_metrics(output),
          latency_metrics: { duration_ms: ((end_time - start_time) * 1000).round(1) }
        )
      rescue StandardError => e
        experiment.record_failure!(dataset_item: item, error: e.message)
        RAAF::Eval.logger.warn("Experiment item failed: #{e.message}")
      end

      def execute_agent(item, agent:, runner:, experiment:)
        if runner
          result = runner.run(item.input_messages)
          { messages: result.messages, content: result.messages.last&.dig(:content) || result.messages.last&.dig("content") }
        elsif agent
          temp_runner = RAAF::Runner.new(agent: agent)
          result = temp_runner.run(item.input_messages)
          { messages: result.messages, content: result.messages.last&.dig(:content) || result.messages.last&.dig("content") }
        else
          # Dry run - return input as output for testing
          { messages: item.input_messages, content: "dry_run", dry_run: true }
        end
      end

      def extract_token_metrics(output)
        return {} unless output.is_a?(Hash)
        output[:token_metrics] || output["token_metrics"] || {}
      end

      def experiment_summary(experiment)
        {
          name: experiment.name,
          model: experiment.model,
          provider: experiment.provider,
          status: experiment.status,
          total_items: experiment.total_items,
          completed_items: experiment.completed_items,
          failed_items: experiment.failed_items,
          aggregate_metrics: experiment.aggregate_metrics,
          duration: experiment.duration
        }
      end

      def compare_metrics(exp_a, exp_b)
        metrics_a = exp_a.aggregate_metrics || {}
        metrics_b = exp_b.aggregate_metrics || {}

        {
          success_rate: {
            a: metrics_a["success_rate"],
            b: metrics_b["success_rate"],
            delta: safe_delta(metrics_b["success_rate"], metrics_a["success_rate"])
          },
          scores: compare_score_dimensions(metrics_a["scores"] || {}, metrics_b["scores"] || {}),
          tokens: {
            a: metrics_a.dig("tokens", "total_tokens"),
            b: metrics_b.dig("tokens", "total_tokens"),
            delta: safe_delta(metrics_b.dig("tokens", "total_tokens"), metrics_a.dig("tokens", "total_tokens"))
          }
        }
      end

      def compare_score_dimensions(scores_a, scores_b)
        all_keys = (scores_a.keys + scores_b.keys).uniq
        all_keys.each_with_object({}) do |key, result|
          result[key] = {
            a: scores_a.dig(key, "avg"),
            b: scores_b.dig(key, "avg"),
            delta: safe_delta(scores_b.dig(key, "avg"), scores_a.dig(key, "avg"))
          }
        end
      end

      def compare_items(exp_a, exp_b)
        results_a = exp_a.experiment_results.index_by(&:dataset_item_id)
        results_b = exp_b.experiment_results.index_by(&:dataset_item_id)

        all_item_ids = (results_a.keys + results_b.keys).uniq
        all_item_ids.map do |item_id|
          ra = results_a[item_id]
          rb = results_b[item_id]
          {
            dataset_item_id: item_id,
            a: ra ? { status: ra.status, scores: ra.scores, overall_score: ra.overall_score } : nil,
            b: rb ? { status: rb.status, scores: rb.scores, overall_score: rb.overall_score } : nil
          }
        end
      end

      def safe_delta(b, a)
        return nil if a.nil? || b.nil?
        (b.to_f - a.to_f).round(4)
      end
    end
  end
end

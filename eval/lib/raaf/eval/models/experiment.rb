# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # Experiment represents a systematic evaluation run against a Dataset.
      # Inspired by Opik's experiment tracking for comparing agent configurations.
      #
      # Each experiment runs an agent configuration against every item in a dataset
      # and collects metrics for comparison.
      #
      # @example Creating and running an experiment
      #   experiment = Experiment.create!(
      #     name: "GPT-4o vs Claude Sonnet",
      #     dataset: dataset,
      #     agent_name: "CustomerSupportAgent",
      #     model: "gpt-4o",
      #     provider: "openai",
      #     configuration: { temperature: 0.7, max_tokens: 1000 }
      #   )
      #   experiment.start!
      #
      # @example Comparing experiments
      #   Experiment.for_dataset(dataset).completed.each do |exp|
      #     puts "#{exp.name}: avg_score=#{exp.average_score}, tokens=#{exp.total_tokens}"
      #   end
      class Experiment < ActiveRecord::Base
        self.table_name = "raaf_experiments"

        # Associations
        belongs_to :dataset,
                   class_name: "RAAF::Eval::Models::Dataset"
        has_many :experiment_results,
                 class_name: "RAAF::Eval::Models::ExperimentResult",
                 foreign_key: :experiment_id,
                 dependent: :destroy

        # Validations
        validates :name, presence: true
        validates :status, presence: true, inclusion: { in: %w[pending running completed failed cancelled] }

        # Scopes
        scope :recent, -> { order(created_at: :desc) }
        scope :by_status, ->(status) { where(status: status) }
        scope :completed, -> { where(status: "completed") }
        scope :failed, -> { where(status: "failed") }
        scope :pending, -> { where(status: "pending") }
        scope :running, -> { where(status: "running") }
        scope :for_dataset, ->(dataset) { where(dataset: dataset) }
        scope :for_agent, ->(name) { where(agent_name: name) }
        scope :for_model, ->(model) { where(model: model) }

        # ── What the edit screen writes ──────────────────────────────────
        #
        # The screen edits four run settings, a list of scorers and a
        # schedule, none of which `raaf_experiments` has columns for. They
        # live in `configuration`, which this model has always documented as
        # the experiment's agent configuration, and tags live in `metadata`.
        # Both are jsonb that already ships, so an install already running
        # gains the screen without a migration.
        #
        # The readers below are the only place that shape is known. Anything
        # reading a setting goes through `setting`, so the defaults are
        # stated once rather than repeated at each call site.

        SETTINGS = {
          "temperature" => 0.7,
          "max_turns" => 5,
          "concurrency" => 1,
          "timeout_seconds" => 60
        }.freeze

        # `cron` is the only trigger that reads the cron expression; the other
        # three are fixed schedules or no schedule at all.
        SCHEDULE_TRIGGERS = %w[manual nightly weekly cron].freeze

        SCHEDULE_DEFAULTS = {
          "trigger" => "manual",
          "cron" => "",
          "notify" => "",
          "alert_below" => nil
        }.freeze

        # @param key [String, Symbol] one of SETTINGS
        # @return [Object] the stored value, or the default when unset
        def setting(key)
          stored = config_hash[key.to_s]
          stored.nil? || stored == "" ? SETTINGS[key.to_s] : stored
        end

        # The scorers this experiment weights, in the order they were saved.
        # Each entry names a check from the same evaluator registry the
        # continuous policies pick from, so the two screens cannot drift onto
        # different scorer vocabularies.
        #
        # @return [Array<Hash>] :key, :evaluator, :check, :enabled, :weight, :threshold
        def scorers
          Array(config_hash["scorers"]).filter_map do |entry|
            next unless entry.is_a?(Hash)

            key = entry["key"] || entry[:key]
            next if key.blank?

            { key: key.to_s,
              evaluator: (entry["evaluator"] || entry[:evaluator]).to_s,
              check: (entry["check"] || entry[:check]).to_s,
              enabled: [true, "true", "1", 1].include?(entry["enabled"] || entry[:enabled]),
              weight: (entry["weight"] || entry[:weight]).to_f,
              threshold: (entry["threshold"] || entry[:threshold])&.to_f }
          end
        end

        # Only enabled scorers count — a scorer switched off should not drag
        # the total away from 1.0 and make a valid setup look wrong.
        # @return [Float]
        def weight_total
          scorers.select { |scorer| scorer[:enabled] }.sum { |scorer| scorer[:weight] }.round(2)
        end

        # @return [Hash] :trigger, :cron, :notify, :alert_below
        def schedule
          stored = config_hash["schedule"]
          stored = {} unless stored.is_a?(Hash)
          merged = SCHEDULE_DEFAULTS.merge(stored.transform_keys(&:to_s))

          { trigger: SCHEDULE_TRIGGERS.include?(merged["trigger"]) ? merged["trigger"] : "manual",
            cron: merged["cron"].to_s,
            notify: merged["notify"].to_s,
            alert_below: merged["alert_below"].presence&.to_f }
        end

        # @return [Array<String>]
        def tags
          meta = metadata.is_a?(Hash) ? metadata : {}
          Array(meta["tags"] || meta[:tags]).map { |tag| tag.to_s.strip }.reject(&:empty?)
        end

        ##
        # Mark experiment as started
        def start!
          update!(
            status: "running",
            started_at: Time.current,
            total_items: dataset.items_count
          )
        end

        ##
        # Mark experiment as completed, computing aggregate metrics
        def complete!
          compute_aggregate_metrics!
          update!(status: "completed", completed_at: Time.current)
        end

        ##
        # Mark experiment as failed
        # @param error [String, Exception] Error description
        def fail!(error = nil)
          message = error.is_a?(Exception) ? error.message : error
          update!(status: "failed", completed_at: Time.current)
          RAAF::Eval.logger.error("Experiment '#{name}' failed: #{message}") if message
        end

        ##
        # Mark experiment as cancelled
        def cancel!
          update!(status: "cancelled", completed_at: Time.current)
        end

        ##
        # Record a result for a dataset item
        # @param dataset_item [DatasetItem] The item being evaluated
        # @param output [Hash] The agent's output
        # @param scores [Hash] Evaluation scores
        # @param token_metrics [Hash] Token usage metrics
        # @param latency_metrics [Hash] Latency metrics
        # @return [ExperimentResult]
        def record_result!(dataset_item:, output:, scores: {}, token_metrics: {}, latency_metrics: {}, metadata: {})
          result = experiment_results.create!(
            dataset_item: dataset_item,
            status: "completed",
            output: output,
            scores: scores,
            token_metrics: token_metrics,
            latency_metrics: latency_metrics,
            started_at: Time.current,
            completed_at: Time.current,
            metadata: metadata
          )
          increment!(:completed_items)
          result
        end

        ##
        # Record a failed result for a dataset item
        # @param dataset_item [DatasetItem] The item that failed
        # @param error [String] Error message
        # @return [ExperimentResult]
        def record_failure!(dataset_item:, error:)
          result = experiment_results.create!(
            dataset_item: dataset_item,
            status: "failed",
            error_message: error,
            started_at: Time.current,
            completed_at: Time.current
          )
          increment!(:failed_items)
          result
        end

        ##
        # Calculate duration in seconds
        # @return [Float, nil]
        def duration
          return nil unless started_at && completed_at

          completed_at - started_at
        end

        ##
        # Calculate progress percentage
        # @return [Float]
        def progress_percentage
          return 0.0 if total_items.zero?

          ((completed_items + failed_items).to_f / total_items * 100).round(1)
        end

        ##
        # Get average score across all completed results
        # @param score_name [String, Symbol] The score dimension to average
        # @return [Float, nil]
        def average_score(score_name = nil)
          results = experiment_results.completed
          return nil if results.empty?

          if score_name
            scores = results.filter_map { |r| r.scores[score_name.to_s] }
            return nil if scores.empty?

            scores.sum / scores.size.to_f
          else
            scores = results.filter_map { |r| r.overall_score }
            return nil if scores.empty?

            scores.sum / scores.size.to_f
          end
        end

        ##
        # Get total tokens used across all results
        # @return [Integer]
        def total_tokens
          experiment_results.completed.sum { |r| r.token_metrics["total_tokens"].to_i }
        end

        ##
        # Check if experiment is in progress
        # @return [Boolean]
        def in_progress?
          status == "running"
        end

        ##
        # Check if experiment is finished
        # @return [Boolean]
        def finished?
          %w[completed failed cancelled].include?(status)
        end

        private

        # `configuration` is jsonb with a `{}` default, but a record built in
        # memory or restored from an older row can still hand back nil.
        def config_hash
          configuration.is_a?(Hash) ? configuration : {}
        end

        ##
        # Compute and store aggregate metrics from all results
        def compute_aggregate_metrics!
          results = experiment_results.completed
          return if results.empty?

          all_scores = results.map(&:scores).compact
          all_token_metrics = results.map(&:token_metrics).compact
          all_latency_metrics = results.map(&:latency_metrics).compact

          self.aggregate_metrics = {
            total_results: results.count,
            failed_results: experiment_results.failed.count,
            success_rate: (results.count.to_f / (results.count + experiment_results.failed.count) * 100).round(1),
            scores: aggregate_scores(all_scores),
            tokens: aggregate_token_metrics(all_token_metrics),
            latency: aggregate_latency_metrics(all_latency_metrics)
          }
        end

        def aggregate_scores(all_scores)
          return {} if all_scores.empty?

          score_keys = all_scores.flat_map(&:keys).uniq
          score_keys.each_with_object({}) do |key, agg|
            values = all_scores.filter_map { |s| s[key]&.to_f }
            next if values.empty?

            agg[key] = {
              avg: (values.sum / values.size).round(4),
              min: values.min.round(4),
              max: values.max.round(4),
              count: values.size
            }
          end
        end

        def aggregate_token_metrics(all_metrics)
          return {} if all_metrics.empty?

          total = all_metrics.sum { |m| m["total_tokens"].to_i }
          input = all_metrics.sum { |m| m["input_tokens"].to_i }
          output = all_metrics.sum { |m| m["output_tokens"].to_i }

          {
            total_tokens: total,
            total_input_tokens: input,
            total_output_tokens: output,
            avg_tokens_per_item: (total.to_f / all_metrics.size).round(0)
          }
        end

        def aggregate_latency_metrics(all_metrics)
          return {} if all_metrics.empty?

          durations = all_metrics.filter_map { |m| m["duration_ms"]&.to_f || m["duration_seconds"]&.to_f&.*(1000) }
          return {} if durations.empty?

          {
            avg_duration_ms: (durations.sum / durations.size).round(1),
            min_duration_ms: durations.min.round(1),
            max_duration_ms: durations.max.round(1),
            p95_duration_ms: percentile(durations, 95).round(1)
          }
        end

        def percentile(values, p)
          sorted = values.sort
          k = (p / 100.0 * (sorted.size - 1)).ceil
          sorted[k] || sorted.last
        end
      end
    end
  end
end

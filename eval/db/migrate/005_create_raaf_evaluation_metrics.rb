# frozen_string_literal: true

class CreateRaafEvaluationMetrics < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_evaluation_metrics do |t|
      # Aggregation dimensions
      t.string :agent_name, null: false
      t.string :environment
      t.string :model
      t.string :evaluator_name
      t.string :period_type, null: false            # 'hourly', 'daily', 'weekly'
      t.datetime :period_start, null: false

      # Counts
      t.integer :total_evaluations, default: 0
      t.integer :passed_count, default: 0
      t.integer :failed_count, default: 0
      t.integer :warning_count, default: 0
      t.integer :error_count, default: 0

      # Score statistics
      t.decimal :avg_score, precision: 5, scale: 4
      t.decimal :min_score, precision: 5, scale: 4
      t.decimal :max_score, precision: 5, scale: 4
      t.decimal :stddev_score, precision: 5, scale: 4
      t.decimal :p50_score, precision: 5, scale: 4  # Median
      t.decimal :p90_score, precision: 5, scale: 4
      t.decimal :p95_score, precision: 5, scale: 4

      # Score distribution (for histograms)
      # Example: { "0.0-0.1": 5, "0.1-0.2": 10, "0.2-0.3": 15, ... }
      t.jsonb :score_distribution, default: {}

      # Performance metrics
      t.decimal :avg_evaluation_duration_ms, precision: 10, scale: 2
      t.decimal :total_evaluation_cost, precision: 10, scale: 4

      # Additional aggregates
      t.jsonb :additional_metrics, default: {}

      t.timestamps
    end

    # Unique constraint for upsert
    add_index :raaf_evaluation_metrics,
              [:agent_name, :environment, :model, :evaluator_name, :period_type, :period_start],
              unique: true,
              name: 'idx_eval_metrics_unique'

    # Query indexes
    add_index :raaf_evaluation_metrics, [:agent_name, :period_type, :period_start],
              name: 'idx_eval_metrics_agent_period'
    add_index :raaf_evaluation_metrics, [:period_type, :period_start],
              name: 'idx_eval_metrics_period'
    add_index :raaf_evaluation_metrics, :period_start
  end
end

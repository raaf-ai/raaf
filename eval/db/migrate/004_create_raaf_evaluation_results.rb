# frozen_string_literal: true

class CreateRAAFEvaluationResults < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_evaluation_results do |t|
      # Span reference
      t.string :span_id, null: false
      t.string :trace_id, null: false

      # Policy reference
      t.references :evaluation_policy, foreign_key: { to_table: :raaf_evaluation_policies }
      t.references :queue_item, foreign_key: { to_table: :raaf_evaluation_queue }

      # Provenance
      t.string :evaluation_type, null: false, default: 'automated'  # 'automated' only for now
      t.string :evaluator_name, null: false         # e.g., 'token_limit', 'quality_check'
      t.string :evaluator_type, null: false         # 'rule_based', 'statistical', 'llm_judge'
      t.string :evaluator_version                   # For tracking evaluator changes

      # Context (denormalized for filtering/aggregation)
      t.string :agent_name, null: false
      t.string :agent_version
      t.string :model
      t.string :provider
      t.string :environment

      # Results
      t.string :status, null: false                 # 'passed', 'failed', 'warning', 'error'
      t.decimal :score, precision: 5, scale: 4     # 0.0000 to 1.0000
      t.jsonb :scores, default: {}                  # Multiple scores: { "quality": 0.85, "safety": 0.95 }
      t.jsonb :metrics, default: {}                 # { "latency_ms": 1200, "tokens": 500, "cost": 0.003 }
      t.text :reasoning                             # LLM judge reasoning or rule explanation
      t.jsonb :details, default: {}                 # Full evaluation result data

      # Timing
      t.integer :evaluation_duration_ms
      t.datetime :evaluation_started_at
      t.datetime :evaluation_completed_at

      # Metadata
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    # Indexes for querying
    add_index :raaf_evaluation_results, :span_id
    add_index :raaf_evaluation_results, :trace_id
    add_index :raaf_evaluation_results, :status
    add_index :raaf_evaluation_results, :evaluator_name
    add_index :raaf_evaluation_results, :created_at

    # Indexes for filtering
    add_index :raaf_evaluation_results, [:agent_name, :created_at],
              name: 'idx_eval_results_agent_time'
    add_index :raaf_evaluation_results, [:agent_name, :environment, :created_at],
              name: 'idx_eval_results_agent_env_time'
    add_index :raaf_evaluation_results, [:agent_name, :status, :created_at],
              name: 'idx_eval_results_agent_status_time'
    add_index :raaf_evaluation_results, [:evaluator_name, :status, :created_at],
              name: 'idx_eval_results_evaluator_status_time'

    # Indexes for aggregation
    add_index :raaf_evaluation_results, [:agent_name, :model, :created_at],
              name: 'idx_eval_results_agent_model_time'

    # JSONB indexes
    add_index :raaf_evaluation_results, :scores, using: :gin
    add_index :raaf_evaluation_results, :metadata, using: :gin
  end
end

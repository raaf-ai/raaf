# frozen_string_literal: true

class CreateRAAFEvaluationPolicies < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_evaluation_policies do |t|
      # Identity
      t.string :name, null: false
      t.text :description

      # Targeting criteria
      t.string :agent_name, null: false              # Supports wildcards: "Dmu*", "*Agent"
      t.string :environment, default: 'all'          # 'production', 'staging', 'development', 'all'
      t.string :model_pattern, default: 'all'        # Supports wildcards: "gpt-4*", "claude-*"
      t.string :version_pattern, default: 'all'      # Supports wildcards: "1.*", "2.0"

      # Sampling configuration
      t.string :sampling_mode, default: 'percentage' # 'percentage', 'every_n', 'all'
      t.integer :sample_rate, default: 100           # 1-100 for percentage mode
      t.integer :sample_every_n                      # For every_n mode: evaluate 1 in N spans
      t.integer :sample_counter, default: 0          # Internal counter for every_n mode
      t.integer :max_daily_evaluations               # Cost control limit (NULL = unlimited)
      t.integer :today_evaluation_count, default: 0  # Reset daily by scheduled job
      t.date :count_reset_date                       # Track when counter was last reset

      # Queue settings
      t.integer :priority, default: 50               # 0 (lowest) to 100 (highest)
      t.string :queue_name, default: 'raaf_evaluations'
      t.integer :max_concurrent_evaluations, default: 5
      t.integer :max_retries, default: 3

      # Retention
      t.integer :retention_days, default: 90
      t.integer :retention_count                     # Keep at least N results (optional)

      # Evaluators configuration (JSONB array)
      # Example:
      # [
      #   { "type": "rule_based", "name": "token_limit", "config": { "max_tokens": 4000 } },
      #   { "type": "llm_judge", "name": "quality_check", "config": {
      #       "model": "gpt-4o-mini",
      #       "criteria": ["accuracy", "completeness", "tone"]
      #     }
      #   }
      # ]
      t.jsonb :evaluators, default: []

      # Metadata
      t.jsonb :metadata, default: {}                 # Custom tags, team, compliance info
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :raaf_evaluation_policies, :name, unique: true
    add_index :raaf_evaluation_policies, :agent_name
    add_index :raaf_evaluation_policies, :active
    add_index :raaf_evaluation_policies, [:agent_name, :environment, :active],
              name: 'idx_eval_policies_targeting'
    add_index :raaf_evaluation_policies, :metadata, using: :gin
  end
end

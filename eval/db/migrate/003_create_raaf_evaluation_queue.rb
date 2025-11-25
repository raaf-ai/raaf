# frozen_string_literal: true

class CreateRaafEvaluationQueue < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_evaluation_queue do |t|
      # References
      t.string :span_id, null: false
      t.string :trace_id, null: false
      t.references :evaluation_policy, foreign_key: { to_table: :raaf_evaluation_policies }

      # Status tracking
      # 'pending', 'running', 'completed', 'failed', 'cancelled'
      t.string :status, null: false, default: 'pending'

      # Queue management
      t.integer :priority, default: 50
      t.integer :attempts, default: 0
      t.integer :max_attempts, default: 3

      # Timing
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :next_retry_at

      # Error tracking
      t.text :error_message
      t.text :error_class

      # Metadata
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :raaf_evaluation_queue, :span_id
    add_index :raaf_evaluation_queue, :status
    add_index :raaf_evaluation_queue, [:status, :priority, :scheduled_at],
              name: 'idx_eval_queue_processing'
    add_index :raaf_evaluation_queue, [:status, :created_at],
              name: 'idx_eval_queue_status_time'
  end
end

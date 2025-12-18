# frozen_string_literal: true

class CreateRAAFEvaluationAlerts < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_evaluation_alerts do |t|
      # Alert identification
      t.string :alert_type, null: false
      # Types: 'quality_degradation', 'failure_spike', 'queue_backlog',
      #        'evaluator_error', 'policy_threshold', 'cost_exceeded'
      t.string :severity, null: false, default: 'warning'
      # Severities: 'info', 'warning', 'critical'
      t.string :status, null: false, default: 'active'
      # Status: 'active', 'acknowledged', 'resolved', 'suppressed'

      # What triggered the alert
      t.string :agent_name
      t.string :environment
      t.string :model
      t.string :evaluator_name
      t.references :evaluation_policy, foreign_key: { to_table: :raaf_evaluation_policies }

      # Alert details
      t.string :title, null: false
      t.text :message, null: false
      t.jsonb :details, default: {}
      # Details can include:
      # - threshold: expected value
      # - actual: measured value
      # - trend: 'increasing', 'decreasing', 'stable'
      # - affected_span_ids: array of span IDs
      # - comparison_period: 'hour', 'day', 'week'

      # Metrics that triggered the alert
      t.decimal :threshold_value, precision: 10, scale: 4
      t.decimal :actual_value, precision: 10, scale: 4
      t.string :metric_name

      # Time tracking
      t.datetime :triggered_at, null: false
      t.datetime :acknowledged_at
      t.datetime :resolved_at
      t.string :acknowledged_by
      t.string :resolved_by
      t.text :resolution_notes

      # Deduplication
      t.string :fingerprint
      t.integer :occurrence_count, default: 1

      t.timestamps
    end

    # Query indexes
    add_index :raaf_evaluation_alerts, :alert_type
    add_index :raaf_evaluation_alerts, :severity
    add_index :raaf_evaluation_alerts, :status
    add_index :raaf_evaluation_alerts, :triggered_at
    add_index :raaf_evaluation_alerts, [:status, :severity],
              name: 'idx_eval_alerts_status_severity'
    add_index :raaf_evaluation_alerts, [:agent_name, :status],
              name: 'idx_eval_alerts_agent_status'
    add_index :raaf_evaluation_alerts, :fingerprint,
              name: 'idx_eval_alerts_fingerprint'

    # For deduplication - only one active alert per fingerprint
    add_index :raaf_evaluation_alerts, [:fingerprint, :status],
              unique: true,
              where: "status = 'active'",
              name: 'idx_eval_alerts_active_unique'
  end
end

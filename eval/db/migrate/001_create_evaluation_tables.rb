# frozen_string_literal: true

class CreateEvaluationTables < ActiveRecord::Migration[7.0]
  def change
    # Create evaluation_runs table
    create_table :evaluation_runs do |t|
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "pending"
      t.string :baseline_span_id, null: false
      t.string :initiated_by
      t.jsonb :metadata, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :evaluation_runs, :name
    add_index :evaluation_runs, :status
    add_index :evaluation_runs, :created_at
    add_index :evaluation_runs, :baseline_span_id
    add_index :evaluation_runs, :metadata, using: :gin

    # Create evaluation_spans table
    create_table :evaluation_spans do |t|
      t.string :span_id, null: false
      t.string :trace_id, null: false
      t.string :parent_span_id
      t.string :span_type, null: false
      t.jsonb :span_data, null: false
      t.string :source, null: false
      t.references :evaluation_run, foreign_key: true
      t.timestamps
    end

    add_index :evaluation_spans, :span_id, unique: true
    add_index :evaluation_spans, :trace_id
    add_index :evaluation_spans, :parent_span_id
    add_index :evaluation_spans, :span_type
    add_index :evaluation_spans, :span_data, using: :gin
    add_index :evaluation_spans, [:trace_id, :parent_span_id]

    # Create evaluation_configurations table
    create_table :evaluation_configurations do |t|
      t.references :evaluation_run, null: false, foreign_key: true
      t.string :name, null: false
      t.string :configuration_type, null: false
      t.jsonb :changes, null: false
      t.integer :execution_order, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :evaluation_configurations, [:evaluation_run_id, :execution_order]
    add_index :evaluation_configurations, :configuration_type
    add_index :evaluation_configurations, :changes, using: :gin

    # Create evaluation_results table
    create_table :evaluation_results do |t|
      t.references :evaluation_run, null: false, foreign_key: true
      t.references :evaluation_configuration, null: false, foreign_key: true
      t.string :result_span_id, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :token_metrics, default: {}
      t.jsonb :latency_metrics, default: {}
      t.jsonb :accuracy_metrics, default: {}
      t.jsonb :structural_metrics, default: {}
      t.jsonb :ai_comparison, default: {}
      t.string :ai_comparison_status
      t.jsonb :statistical_analysis, default: {}
      t.jsonb :custom_metrics, default: {}
      t.jsonb :baseline_comparison, default: {}
      t.text :error_message
      t.text :error_backtrace
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :evaluation_results, :status
    add_index :evaluation_results, :result_span_id
    add_index :evaluation_results, [:evaluation_run_id, :status]
    add_index :evaluation_results, :token_metrics, using: :gin
    add_index :evaluation_results, :ai_comparison, using: :gin
    add_index :evaluation_results, :baseline_comparison, using: :gin
  end
end

# frozen_string_literal: true

class CreateRaafDatasets < ActiveRecord::Migration[7.0]
  def change
    # Datasets for systematic evaluation (inspired by Opik)
    create_table :raaf_datasets do |t|
      t.string :name, null: false
      t.text :description
      t.integer :version, null: false, default: 1
      t.string :status, null: false, default: "active"
      t.string :created_by
      t.integer :items_count, null: false, default: 0
      t.jsonb :metadata, default: {}
      t.jsonb :schema_definition, default: {}
      t.timestamps
    end

    add_index :raaf_datasets, :name
    add_index :raaf_datasets, [:name, :version], unique: true
    add_index :raaf_datasets, :status
    add_index :raaf_datasets, :metadata, using: :gin

    # Dataset items (individual test cases)
    create_table :raaf_dataset_items do |t|
      t.references :dataset, null: false, foreign_key: { to_table: :raaf_datasets }
      t.jsonb :input, null: false, default: {}
      t.jsonb :expected_output, default: {}
      t.jsonb :metadata, default: {}
      t.string :source_span_id
      t.string :source_trace_id
      t.timestamps
    end

    add_index :raaf_dataset_items, :source_span_id
    add_index :raaf_dataset_items, :source_trace_id
    add_index :raaf_dataset_items, :input, using: :gin
    add_index :raaf_dataset_items, :expected_output, using: :gin

    # Experiments run against datasets
    create_table :raaf_experiments do |t|
      t.string :name, null: false
      t.text :description
      t.references :dataset, null: false, foreign_key: { to_table: :raaf_datasets }
      t.string :status, null: false, default: "pending"
      t.string :agent_name
      t.string :model
      t.string :provider
      t.jsonb :configuration, default: {}
      t.jsonb :aggregate_metrics, default: {}
      t.string :created_by
      t.integer :total_items, null: false, default: 0
      t.integer :completed_items, null: false, default: 0
      t.integer :failed_items, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :raaf_experiments, :name
    add_index :raaf_experiments, :status
    add_index :raaf_experiments, :agent_name
    add_index :raaf_experiments, :model
    add_index :raaf_experiments, [:dataset_id, :status]
    add_index :raaf_experiments, :aggregate_metrics, using: :gin

    # Experiment results (one per dataset item per experiment)
    create_table :raaf_experiment_results do |t|
      t.references :experiment, null: false, foreign_key: { to_table: :raaf_experiments }
      t.references :dataset_item, null: false, foreign_key: { to_table: :raaf_dataset_items }
      t.string :status, null: false, default: "pending"
      t.jsonb :output, default: {}
      t.jsonb :scores, default: {}
      t.jsonb :token_metrics, default: {}
      t.jsonb :latency_metrics, default: {}
      t.text :error_message
      t.string :result_span_id
      t.string :result_trace_id
      t.float :duration_seconds
      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :raaf_experiment_results, :status
    add_index :raaf_experiment_results, :result_span_id
    add_index :raaf_experiment_results, [:experiment_id, :status]
    add_index :raaf_experiment_results, [:experiment_id, :dataset_item_id], unique: true,
              name: "idx_experiment_results_on_experiment_and_item"
    add_index :raaf_experiment_results, :scores, using: :gin
  end
end

# frozen_string_literal: true

class CreateRAAFTracingTraces < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_tracing_traces, id: false do |t|
      t.string :trace_id, primary_key: true, null: false
      t.string :workflow_name, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :started_at
      t.datetime :ended_at
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :raaf_tracing_traces, :workflow_name
    add_index :raaf_tracing_traces, :status
    add_index :raaf_tracing_traces, :started_at
    add_index :raaf_tracing_traces, :metadata, using: :gin
  end
end

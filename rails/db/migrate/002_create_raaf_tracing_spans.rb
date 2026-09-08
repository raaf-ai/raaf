# frozen_string_literal: true

class CreateRAAFTracingSpans < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_tracing_spans, id: false do |t|
      t.string :span_id, primary_key: true, null: false
      t.string :trace_id, null: false
      t.string :parent_id
      t.string :name, null: false
      t.string :kind, null: false, default: "internal"
      t.string :status, null: false, default: "ok"
      t.datetime :start_time
      t.datetime :end_time
      t.decimal :duration_ms, precision: 15, scale: 3
      # +json+, not +jsonb+: SpanRecord reads these columns with json_each and
      # json_typeof, which have no jsonb overload, and the console's own SQL
      # casts to jsonb where it wants the binary form.
      t.json :span_attributes
      t.json :events
      t.timestamps
    end

    add_index :raaf_tracing_spans, :trace_id
    add_index :raaf_tracing_spans, :parent_id
    add_index :raaf_tracing_spans, :name
    add_index :raaf_tracing_spans, :kind
    add_index :raaf_tracing_spans, :status
    add_index :raaf_tracing_spans, :start_time
    add_index :raaf_tracing_spans, %i[trace_id parent_id]

    add_foreign_key :raaf_tracing_spans, :raaf_tracing_traces,
                    column: :trace_id, primary_key: :trace_id, on_delete: :cascade
  end
end

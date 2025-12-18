# frozen_string_literal: true

class CreateRAAFTracingSpanReplays < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_tracing_span_replays do |t|
      # String references to match span_id format
      t.string :original_span_id, null: false
      t.string :replayed_span_id

      # Configuration changes (diff from original)
      t.jsonb :configuration_changes, default: {}

      # Prompts stored for editing
      t.jsonb :system_prompt
      t.jsonb :user_messages, default: []

      # Status tracking
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.text :notes

      t.timestamps
    end

    add_index :raaf_tracing_span_replays, :original_span_id
    add_index :raaf_tracing_span_replays, :replayed_span_id
    add_index :raaf_tracing_span_replays, :status

    add_foreign_key :raaf_tracing_span_replays, :raaf_tracing_spans,
                    column: :original_span_id, primary_key: :span_id, on_delete: :cascade
    add_foreign_key :raaf_tracing_span_replays, :raaf_tracing_spans,
                    column: :replayed_span_id, primary_key: :span_id, on_delete: :nullify
  end
end

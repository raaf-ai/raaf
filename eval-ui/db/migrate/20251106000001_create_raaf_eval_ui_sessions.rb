# frozen_string_literal: true

class CreateRaafEvalUiSessions < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_eval_ui_sessions do |t|
      t.bigint :user_id
      t.bigint :baseline_span_id
      t.string :name, null: false
      t.text :description
      t.string :session_type, null: false, default: "draft"
      t.string :status, null: false, default: "pending"
      t.jsonb :metadata, default: {}
      t.text :error_message
      t.text :error_backtrace
      t.datetime :completed_at

      t.timestamps

      t.index [:user_id, :session_type]
      t.index :baseline_span_id
      t.index :created_at
      t.index :status
    end
  end
end

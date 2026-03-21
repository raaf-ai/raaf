# frozen_string_literal: true

class CreateRaafFeedbackScores < ActiveRecord::Migration[7.0]
  def change
    # Feedback scores for human-in-the-loop annotation (inspired by Opik)
    create_table :raaf_feedback_scores do |t|
      t.string :name, null: false
      t.string :source, null: false, default: "ui"
      t.string :span_id
      t.string :trace_id
      t.float :value
      t.string :category_value
      t.string :reason
      t.string :scored_by
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :raaf_feedback_scores, :name
    add_index :raaf_feedback_scores, :source
    add_index :raaf_feedback_scores, :span_id
    add_index :raaf_feedback_scores, :trace_id
    add_index :raaf_feedback_scores, [:span_id, :name], name: "idx_feedback_scores_span_name"
    add_index :raaf_feedback_scores, [:trace_id, :name], name: "idx_feedback_scores_trace_name"
    add_index :raaf_feedback_scores, :scored_by
    add_index :raaf_feedback_scores, :created_at

    # Feedback score definitions (templates for scoring)
    create_table :raaf_feedback_score_definitions do |t|
      t.string :name, null: false
      t.text :description
      t.string :score_type, null: false, default: "numerical"
      t.float :min_value
      t.float :max_value
      t.jsonb :categories, default: []
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :raaf_feedback_score_definitions, :name, unique: true
    add_index :raaf_feedback_score_definitions, :score_type
  end
end

# frozen_string_literal: true

class CreateRaafEvalUiSessionConfigurations < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_eval_ui_session_configurations do |t|
      t.references :raaf_eval_ui_session, null: false, foreign_key: true, index: { name: "index_session_configs_on_session_id" }
      t.string :name, null: false
      t.jsonb :configuration, null: false
      t.integer :display_order, default: 0

      t.timestamps

      t.index [:raaf_eval_ui_session_id, :display_order], name: "index_session_configs_on_session_id_and_order"
    end
  end
end

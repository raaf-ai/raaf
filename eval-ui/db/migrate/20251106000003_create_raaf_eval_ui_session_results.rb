# frozen_string_literal: true

class CreateRaafEvalUiSessionResults < ActiveRecord::Migration[7.0]
  def change
    create_table :raaf_eval_ui_session_results do |t|
      t.references :raaf_eval_ui_session, null: false, foreign_key: true, index: { name: "index_session_results_on_session_id" }
      t.references :raaf_eval_ui_session_configuration, null: false, foreign_key: true, index: { name: "index_session_results_on_config_id" }
      t.bigint :raaf_eval_result_id
      t.string :status, null: false, default: "pending"
      t.jsonb :result_data, default: {}
      t.jsonb :metrics, default: {}

      t.timestamps

      t.index [:raaf_eval_ui_session_id, :status], name: "index_session_results_on_session_id_and_status"
      t.index :raaf_eval_result_id
    end
  end
end

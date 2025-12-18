# frozen_string_literal: true

class AddTriggerModeToRaafEvaluationPolicies < ActiveRecord::Migration[7.0]
  def change
    add_column :raaf_evaluation_policies, :trigger_mode, :string, default: 'automatic', null: false
    add_index :raaf_evaluation_policies, :trigger_mode
  end
end

# frozen_string_literal: true

# `changes` is Active Record's own method for the dirty attributes of a record, so a
# column of that name makes the model refuse to load at all:
#
#   ActiveRecord::DangerousAttributeError: changes is defined by Active Record.
#
# EvaluationConfiguration has therefore never been usable, and every evaluation run
# created through EvaluationEngine died on the first configuration it tried to store.
# The column holds what a configuration changes about the baseline, which the console
# already calls configuration_changes elsewhere.
class RenameChangesOnEvaluationConfigurations < ActiveRecord::Migration[7.0]
  def up
    return unless column_exists?(:evaluation_configurations, :changes)

    remove_index :evaluation_configurations, column: :changes, using: :gin
    rename_column :evaluation_configurations, :changes, :configuration_changes
    add_index :evaluation_configurations, :configuration_changes, using: :gin
  end

  def down
    return unless column_exists?(:evaluation_configurations, :configuration_changes)

    remove_index :evaluation_configurations, column: :configuration_changes, using: :gin
    rename_column :evaluation_configurations, :configuration_changes, :changes
    add_index :evaluation_configurations, :changes, using: :gin
  end
end

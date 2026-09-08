# frozen_string_literal: true

# A result's overall score was the mean of a jsonb hash, averaged in Ruby every
# time anybody asked for it. So the results table could only order by recency
# and filter by status: "show me the worst twenty cases" — which is how a run is
# actually read — could be asked of the fifty rows already on screen or of
# nothing at all.
#
# Schema only. The column is written when a result is saved, and
# `ExperimentResult#overall_score` still averages the hash for a row that has
# not been written since, so nothing reads as unscored while old rows are
# without it. A host that wants its history sortable backfills it as a data
# update rather than here.
class AddOverallScoreToRAAFExperimentResults < ActiveRecord::Migration[7.0]
  def change
    add_column :raaf_experiment_results, :overall_score, :float

    # Worst first within one run, which is the only order this is asked in.
    add_index :raaf_experiment_results, %i[experiment_id overall_score],
              name: "idx_experiment_results_on_experiment_and_score"
  end
end

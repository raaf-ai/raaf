# frozen_string_literal: true

# A result says which policy produced it, and how long it is worth keeping, in
# its own columns rather than through evaluation_policy_id.
#
# EvaluationPolicy declares `dependent: :nullify`, so deleting a policy does not
# delete its results — it nulls that column, and the row can no longer say what
# graded it. RetentionCleanupJob turns the same nulling into data loss: it read
# retention_days through that association and fell back to its own 30-day
# default when the policy was gone, so retiring a policy that declared 90 days
# silently cut its own history to 30 and nothing reported the change.
#
# With both facts on the row, a policy can be retired without taking either with
# it. ContinuousEvaluationResult#keep_for_days and #producing_policy_name read
# the row first and the association only as a fallback, so rows written before
# this keep working until a host backfills them.
#
# Nullable on purpose: existing rows have neither value until that backfill.
#
# Guarded with `if_not_exists` because a host carries its own timestamped copy
# of this file: whichever runs second finds the columns and indexes already
# there, and without the guard it aborts the host's boot-time migrate.
class AddPolicyProvenanceToRAAFEvaluationResults < ActiveRecord::Migration[7.0]
  def change
    add_column :raaf_evaluation_results, :policy_name, :string, if_not_exists: true
    add_column :raaf_evaluation_results, :retention_days, :integer, if_not_exists: true

    # "What did this policy score, over time" — the question
    # evaluation_policy_id answers today and stops answering once the policy row
    # is gone.
    add_index :raaf_evaluation_results, %i[policy_name created_at],
              name: "idx_eval_results_on_policy_name_and_time", if_not_exists: true

    # The retention sweep's access path: every row past its own keep-for.
    add_index :raaf_evaluation_results, %i[retention_days created_at],
              name: "idx_eval_results_on_retention_and_time", if_not_exists: true
  end
end

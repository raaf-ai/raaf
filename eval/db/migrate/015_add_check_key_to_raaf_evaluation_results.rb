# frozen_string_literal: true

# A continuous check is keyed `field:evaluator`, and a result was recorded under
# the field alone — one row per graded field, whatever graded it. So a policy
# grading `confidence` with both a rule and an LLM judge combined the two
# verdicts before writing, and neither survived: neither evaluator could be
# scored, trended or compared on its own, turning one of them off moved the
# number with nothing to attribute the move to, and the screens reported the
# combined figure twice under two different checks' names.
#
# The column carries the check the row is about, so a result is the answer of
# one evaluator to one field.
#
# Rows written before this have none, and cannot be given one: their score is a
# combination of evaluators that were not recorded separately. They stay, and
# the screens say what they are — see PolicyShow#combined_note — rather than
# being re-read as some single evaluator's.
#
# Guarded with `if_not_exists` because a host carries its own timestamped copy
# of this file: whichever runs second finds the column and the index already
# there, and without the guard it aborts the host's boot-time migrate.
class AddCheckKeyToRAAFEvaluationResults < ActiveRecord::Migration[7.0]
  def change
    add_column :raaf_evaluation_results, :check_key, :string, if_not_exists: true

    # One check's history within one policy, which is how a bar and a trend
    # line are both read.
    add_index :raaf_evaluation_results, %i[evaluation_policy_id check_key created_at],
              name: "idx_eval_results_on_policy_and_check", if_not_exists: true
  end
end

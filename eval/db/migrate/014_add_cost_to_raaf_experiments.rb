# frozen_string_literal: true

# An experiment's spend was priced at render time, off the token totals in
# `aggregate_metrics` and against today's pricing table. Three things followed
# from that: the list could not order by the one figure that decides between
# two runs whose scores are level, every row of it paid for a pricing lookup,
# and a run from three months ago was re-priced at today's rates on every page
# load, so a number a reader expected to be a historical record moved under
# them.
#
# The column records what the run cost when it ran. `Experiment#spend` still
# prices the tokens for a row written before this existed, so nothing reads as
# free while old runs are without it; a host that wants its history sortable
# backfills it as a data update rather than here.
#
# Guarded with `if_not_exists` because a host carries its own timestamped copy
# of this file: whichever runs second finds the column and the index already
# there, and without the guard it aborts the host's boot-time migrate.
class AddCostToRAAFExperiments < ActiveRecord::Migration[7.0]
  def change
    add_column :raaf_experiments, :cost, :float, if_not_exists: true

    # Dearest first, which is the only order this is asked in.
    add_index :raaf_experiments, :cost, name: "idx_experiments_on_cost", if_not_exists: true
  end
end

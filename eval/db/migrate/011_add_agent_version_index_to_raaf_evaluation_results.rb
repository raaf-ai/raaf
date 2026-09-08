# frozen_string_literal: true

# Backs the release markers on the Score trends screen.
#
# The screen marks the bucket a version first ran in, which means asking, of
# every version seen in the window, whether anything of that version was
# scored before the window opened. That used to be read the only way the
# table allowed — group all of it by `agent_version`, take each version's
# earliest result, keep the ones inside the window. It is a scan of every
# evaluation there has ever been to draw at most a handful of markers, and it
# costs the same at a one-hour range as at thirty days.
#
# Migration 004 indexes `created_at`, which answers the window, and several
# combinations led by `agent_name`, none of which a version can use. So the
# question "is there anything of this version older than this" has no index to
# ask and falls back to the table. With this one it is a probe: the version
# pins the leading column, and the first entry under it settles the answer.
#
# Partial, because a console that never records a version writes NULL in every
# row and would otherwise pay for an index of them.
class AddAgentVersionIndexToRAAFEvaluationResults < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  INDEX_NAME = "idx_eval_results_version_time"

  def up
    drop_invalid_leftover

    add_index :raaf_evaluation_results, %i[agent_version created_at],
              name: INDEX_NAME,
              where: "agent_version IS NOT NULL",
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :raaf_evaluation_results, name: INDEX_NAME,
                 algorithm: :concurrently, if_exists: true
  end

  private

  # An interrupted CREATE INDEX CONCURRENTLY leaves the index in place and
  # unusable, and Rails records no version for the run that died — so the retry
  # meets its own leftover, and `if_not_exists` would read it as "already
  # built". That records the migration as applied over an index the planner
  # ignores, which is quieter than a crash and worse: the scan this exists to
  # remove stays, with nothing to say why.
  def drop_invalid_leftover
    leftover = connection.select_value(<<~SQL.squish)
      SELECT 1 FROM pg_class c JOIN pg_index i ON i.indexrelid = c.oid
      WHERE c.relname = '#{INDEX_NAME}' AND NOT i.indisvalid
    SQL
    return unless leftover

    say "dropping #{INDEX_NAME}, left invalid by an interrupted build"
    remove_index :raaf_evaluation_results, name: INDEX_NAME, algorithm: :concurrently
  end
end

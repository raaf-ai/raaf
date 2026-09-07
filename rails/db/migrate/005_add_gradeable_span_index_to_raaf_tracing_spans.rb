# frozen_string_literal: true

# Backs the two reads that ask "which spans could a policy grade in this
# window" without naming an agent.
#
# Migration 004 indexes the same population keyed on the agent name, which is
# the right shape for PolicySpanLookup when the policy names plain agents: the
# name pins the leading column and start_time orders what is left. Two callers
# never supply that name, and for them the leading column is unconstrained, so
# the planner can only scan the whole index and visit the heap for every row:
#
# - ScorerHealth#eligible_by_agent groups *by* the agent name over a window, so
#   there is no name to pin. In production this read was 18.6s of an 18.7s
#   request on the Scorer health screen at a 30-day range.
# - PolicySpanLookup#candidates drops the name filter whenever the policy
#   wildcards its agents, names none, or constrains a model or environment
#   pattern instead. That was 17.7s of a 17.7s policy page.
#
# So the same population is indexed again with start_time leading, which is
# what both of them actually filter on. The two indexes are not redundant: one
# answers "this agent, newest first", the other "this window, whatever ran".
#
# The predicate also carries the `source` condition both callers apply. In 004
# that condition is left to a heap check, which costs a page fetch per
# candidate row precisely when there are most of them; here it removes the rows
# instead, and lets the count and the grouping be answered from the index
# alone.
#
# if_not_exists for the same reason as 004, and hedged the same way there.
class AddGradeableSpanIndexToRAAFTracingSpans < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  INDEX_NAME = "index_raaf_tracing_spans_on_gradeable_start_time"

  AGENT_NAME = "lower(coalesce(span_attributes ->> 'agent.name', span_attributes ->> 'agent_name'))"

  GRADEABLE = <<~SQL.squish
    kind = 'agent'
    AND span_attributes ->> 'agent.final_agent_response' IS NOT NULL
    AND span_attributes ->> 'source' IS DISTINCT FROM 'evaluation_run'
  SQL

  def up
    drop_invalid_leftover

    add_index :raaf_tracing_spans,
              "start_time DESC, #{AGENT_NAME}",
              name: INDEX_NAME,
              where: GRADEABLE,
              algorithm: :concurrently,
              if_not_exists: true
  rescue ActiveRecord::StatementInvalid => e
    raise unless e.message.include?("unsupported Unicode escape sequence")

    raise <<~MESSAGE
      Spans in this database carry a NUL inside span_attributes, and the
      predicate above cannot read text out of them:

        #{e.message.lines.first.strip}

      The column is `json`, which accepts a NUL where `jsonb` would refuse it.
      Every read of the form `span_attributes ->> ...` fails on such a row, so
      the rows have to be repaired before this index can cover them.
    MESSAGE
  end

  def down
    remove_index :raaf_tracing_spans, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end

  private

  # An interrupted CREATE INDEX CONCURRENTLY leaves the index in place and
  # unusable, and Rails records no version for the run that died — so the retry
  # meets its own leftover. `if_not_exists` reads that leftover as "already
  # built" and records the migration as applied over an index the planner
  # ignores, which is quieter than a crash and worse: the slow reads this
  # exists to fix stay slow with nothing to show why. So an invalid leftover is
  # dropped, and only a valid one is taken for the goal.
  def drop_invalid_leftover
    leftover = connection.select_value(<<~SQL.squish)
      SELECT 1 FROM pg_class c JOIN pg_index i ON i.indexrelid = c.oid
      WHERE c.relname = '#{INDEX_NAME}' AND NOT i.indisvalid
    SQL
    return unless leftover

    say "dropping #{INDEX_NAME}, left invalid by an interrupted build"
    remove_index :raaf_tracing_spans, name: INDEX_NAME, algorithm: :concurrently
  end
end

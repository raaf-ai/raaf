# frozen_string_literal: true

# Backs RAAF::Rails::Continuous::PolicySpanLookup, which asks for the newest
# agent spans carrying a recorded response for one named agent.
#
# The agent's name lives inside the span_attributes document, so without this
# the only usable index is start_time and the question is answered by walking a
# month of spans backwards and reading each row's attributes to reject it —
# a sequential scan of the whole table whenever the named agent has been quiet.
#
# The expressions are exactly the ones the lookup's SQL uses: the two spellings
# of the agent name RAAF has written over time, lower-cased because the policy
# matcher compares case-insensitively. The predicate holds the other two
# constants of that query, so the index covers the agent spans an evaluator
# could grade rather than every span ever recorded.
#
# if_not_exists so a host application that indexed this by hand gets a
# no-op rather than a failed deploy. It is not on its own enough to make a
# retry safe — see #drop_invalid_leftover.
class AddAgentNameIndexToRAAFTracingSpans < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  INDEX_NAME = "index_raaf_tracing_spans_on_agent_name_and_start_time"

  AGENT_NAME = "lower(coalesce(span_attributes ->> 'agent.name', span_attributes ->> 'agent_name'))"

  def up
    drop_invalid_leftover

    add_index :raaf_tracing_spans,
              "#{AGENT_NAME}, start_time DESC",
              name: INDEX_NAME,
              where: "kind = 'agent' AND span_attributes ->> 'agent.final_agent_response' IS NOT NULL",
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

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
# if_not_exists because a host application that indexed this by hand before
# copying engine migrations should get a no-op here, not a failed deploy.
class AddAgentNameIndexToRAAFTracingSpans < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  AGENT_NAME = "lower(coalesce(span_attributes ->> 'agent.name', span_attributes ->> 'agent_name'))"

  def change
    add_index :raaf_tracing_spans,
              "#{AGENT_NAME}, start_time DESC",
              name: "index_raaf_tracing_spans_on_agent_name_and_start_time",
              where: "kind = 'agent' AND span_attributes ->> 'agent.final_agent_response' IS NOT NULL",
              algorithm: :concurrently,
              if_not_exists: true
  end
end

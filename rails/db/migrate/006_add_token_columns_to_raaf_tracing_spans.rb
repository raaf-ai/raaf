# frozen_string_literal: true

# The billing columns every cost and usage screen reads.
#
# RAAF::Rails::Tracing::SpanRecord has selected input_tokens, output_tokens,
# total_tokens and agent_model since the Cost & usage screens stopped searching
# span_attributes as text, and migration 007 backfills all four. No migration
# in this engine ever created them: the one application running this code had
# them from its own schema, so the gap only showed when the engine was booted
# against an empty database.
#
# All four are nullable. NULL means the span was written before the tracer
# recorded that field, which is a different statement from "this call used no
# tokens" and has to stay distinguishable from zero.
class AddTokenColumnsToRAAFTracingSpans < ActiveRecord::Migration[7.0]
  def change
    add_column :raaf_tracing_spans, :input_tokens, :integer
    add_column :raaf_tracing_spans, :output_tokens, :integer
    add_column :raaf_tracing_spans, :total_tokens, :integer

    # Clamped to the width SpanUsage clamps a model name to, so a payload
    # carrying something long cannot widen every row of the table.
    add_column :raaf_tracing_spans, :agent_model, :string, limit: 100

    # Spend by model asks only about agent spans, and on this table that is a
    # small fraction of the rows.
    add_index :raaf_tracing_spans, :agent_model,
              name: "idx_raaf_tracing_spans_agent_model",
              where: "kind = 'agent'"
  end
end

# frozen_string_literal: true

# Gives a per-call fee a column of its own, and fills in the billing columns
# for every span written before they existed.
#
# The Cost & usage and Agents screens select the spans that put something on a
# bill. Tokens have had native columns since migration 004, but a search fee
# had nowhere to live, so the scope that finds billable spans asked for it the
# only way it could:
#
#   span_attributes::text LIKE '%cost_cents%'
#
# beside two more LIKEs of the same shape for the token keys. Each casts the
# whole +json+ column to text and searches ~21 kB unanchored, for every span in
# the window, and no index can answer any of them. On production that read is
# 8.9s of a 9.9s Agents page and three passes of ~3s each on Cost & usage.
#
# So the fee gets a column, the payload gets copied into all five columns
# once, and the scopes can ask the columns instead. The backfill is set-based
# rather than the row-by-row +raaf:tracing:backfill_token_columns+ task: the
# task exists to be re-run and to report, but a table of millions cannot wait
# for one UPDATE per row, and until every row is filled the scopes cannot
# honestly stop reading the payload.
#
# The expressions below mirror {RAAF::Tracing::SpanUsage} exactly — the same
# key order, the same rejection of "N/A" and of a count that is not a run of
# digits, the same 100-character clamp on a model name. Spec coverage compares
# the two implementations over the payload shapes in the field.
class AddCallFeeCentsToRAAFTracingSpans < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  INDEX_NAME = "index_raaf_tracing_spans_on_billable_start_time"

  # Rows per UPDATE. The backfill walks the table in start_time order so each
  # statement takes a bounded number of row locks and a cancelled run leaves
  # the rows it already filled rather than rolling all of them back.
  BATCH = 20_000

  # A span attributes payload that is an object, or an empty one. The column
  # permits a scalar; nothing writes one, but `->>` on it would answer NULL for
  # every key and quietly backfill nothing.
  #
  # Cast rather than read as-is: json_typeof has no jsonb overload, and an
  # application that took this column as jsonb would fail the whole backfill on
  # the first row.
  ATTRS = <<~SQL.squish
    CASE WHEN json_typeof(span_attributes::json) = 'object'
         THEN span_attributes::json ELSE '{}'::json END
  SQL

  def up
    add_column :raaf_tracing_spans, :call_fee_cents, :decimal, precision: 12, scale: 4

    backfill

    add_index :raaf_tracing_spans, :start_time,
              name: INDEX_NAME,
              where: billable_predicate,
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :raaf_tracing_spans, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
    remove_column :raaf_tracing_spans, :call_fee_cents
  end

  private

  # What "this span put something on a bill" means once the columns are filled.
  # A job is excluded here rather than in the scope for the same reason it is
  # excluded there: the tracer copies its children's counts onto it, so it
  # matches on tokens it did not spend.
  def billable_predicate
    <<~SQL.squish
      (input_tokens IS NOT NULL OR total_tokens IS NOT NULL OR call_fee_cents IS NOT NULL)
      AND (kind IS NULL OR kind <> 'job')
    SQL
  end

  # One UPDATE per batch, over the rows whose columns disagree with their
  # payload. Already-correct rows are matched out in the WHERE rather than
  # written and counted, so re-running this costs a scan and no writes.
  def backfill
    batches.each do |from, upto|
      run_backfill("start_time >= #{connection.quote(from)} AND start_time < #{connection.quote(upto)}",
                   "#{from} to #{upto}")
    end

    # start_time is nullable and the batches are cut from it, so a span without
    # one falls outside every range above and would keep its empty columns.
    run_backfill("start_time IS NULL", "spans with no start_time")
  end

  def run_backfill(where, label)
    updated = execute(<<~SQL.squish).cmd_tuples
      UPDATE raaf_tracing_spans SET
        input_tokens   = COALESCE(input_tokens,   #{token_sql(::RAAF::Tracing::SpanUsage::INPUT_KEYS, :input)}),
        output_tokens  = COALESCE(output_tokens,  #{token_sql(::RAAF::Tracing::SpanUsage::OUTPUT_KEYS, :output)}),
        total_tokens   = COALESCE(total_tokens,   #{token_sql(::RAAF::Tracing::SpanUsage::TOTAL_KEYS, :total)}),
        agent_model    = COALESCE(agent_model,    #{model_sql}),
        call_fee_cents = COALESCE(call_fee_cents, #{fee_sql})
      WHERE (#{where})
        AND (input_tokens IS NULL OR output_tokens IS NULL
             OR total_tokens IS NULL OR agent_model IS NULL OR call_fee_cents IS NULL)
    SQL

    say "backfilled #{updated} spans — #{label}", true
  end

  # Half-open [from, upto) pairs covering every span that has a start_time.
  #
  # Cut by row count rather than by a fixed span of time: a table's traffic is
  # never spread evenly, and an hour of a busy week is not the same amount of
  # work as an hour of a quiet one. The edges stay the strings Postgres
  # returned, so no timezone is applied on the way out and back in.
  def batches
    edges = select_values(<<~SQL.squish)
      SELECT start_time FROM (
        SELECT start_time, row_number() OVER (ORDER BY start_time) AS position
        FROM raaf_tracing_spans WHERE start_time IS NOT NULL
      ) ordered
      WHERE position % #{BATCH} = 1
      ORDER BY start_time
    SQL
    return [] if edges.empty?

    last = select_value("SELECT max(start_time) FROM raaf_tracing_spans")

    # The upper edge is exclusive, so the final batch has to end after the last
    # row rather than on it.
    ends = edges.drop(1) + [select_value("SELECT #{connection.quote(last)}::timestamp + interval '1 second'")]
    edges.zip(ends)
  end

  # The first of +keys+ that holds a run of digits, then the same question of
  # the nested +usage+ object. Mirrors SpanUsage#token, including its refusal
  # to read "1.5" or "N/A" as a count.
  def token_sql(keys, nested_field)
    flat = keys.map { |key| digits_sql("(#{ATTRS})", key) }
    nested = ::RAAF::Tracing::SpanUsage::NESTED_USAGE_KEYS.fetch(nested_field).map do |key|
      digits_sql("(CASE WHEN json_typeof((#{ATTRS}) -> 'usage') = 'object' " \
                 "THEN (#{ATTRS}) -> 'usage' ELSE '{}'::json END)", key)
    end

    "COALESCE(#{(flat + nested).join(', ')})"
  end

  def digits_sql(source, key)
    "(CASE WHEN #{source} ->> #{connection.quote(key)} ~ '^[0-9]+$' " \
      "THEN (#{source} ->> #{connection.quote(key)})::integer END)"
  end

  # The first model key that is neither blank nor a placeholder the tracer
  # writes for a field it never got, clamped the way SpanUsage clamps it.
  def model_sql
    placeholders = ::RAAF::Tracing::SpanUsage::MODEL_PLACEHOLDERS.map { |value| connection.quote(value) }.join(", ")

    branches = ::RAAF::Tracing::SpanUsage::MODEL_KEYS.map do |key|
      trimmed = "btrim((#{ATTRS}) ->> #{connection.quote(key)})"
      "(CASE WHEN #{trimmed} <> '' AND #{trimmed} NOT IN (#{placeholders}) THEN left(#{trimmed}, 100) END)"
    end

    "COALESCE(#{branches.join(', ')})"
  end

  # The first fee key holding a number. Written by the component that made the
  # call rather than by the tracer, so all three spellings are in the field.
  def fee_sql
    branches = ::RAAF::Tracing::SpanUsage::FEE_CENT_KEYS.map do |key|
      trimmed = "btrim((#{ATTRS}) ->> #{connection.quote(key)})"
      "(CASE WHEN #{trimmed} ~ '^-?[0-9]+(\\.[0-9]+)?$' THEN #{trimmed}::decimal END)"
    end

    "COALESCE(#{branches.join(', ')})"
  end
end

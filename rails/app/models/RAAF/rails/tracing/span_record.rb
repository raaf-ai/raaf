# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      # ActiveRecord model for storing span data
      #
      # A span represents a single operation within a trace. Each span captures:
      #
      # - Operation timing and duration
      # - Status and error information
      # - Attributes and events
      # - Parent-child relationships
      # - Operation-specific metadata
      #
      # ## Usage
      #
      # Spans are typically created automatically by the ActiveRecordProcessor.
      # They can be queried for analysis and debugging:
      #
      # @example Find slow spans
      #   RAAF::Tracing::Span.slow(threshold: 1000) # > 1 second
      #
      # @example Find error spans
      #   RAAF::Tracing::Span.errors.recent
      #
      # @example Find spans by operation type
      #   RAAF::Tracing::Span.by_kind('llm')
      #
      # @example Get span performance metrics
      #   RAAF::Tracing::Span.performance_metrics('tool')
      class SpanRecord < ActiveRecord::Base
        self.table_name = "raaf_tracing_spans"
        self.primary_key = "span_id"

        # Associations
        belongs_to :trace, primary_key: :trace_id,
                           class_name: "RAAF::Rails::Tracing::TraceRecord", optional: true
        belongs_to :parent_span, class_name: "RAAF::Rails::Tracing::SpanRecord",
                                 primary_key: :span_id, foreign_key: :parent_id, optional: true
        has_many :children, class_name: "RAAF::Rails::Tracing::SpanRecord",
                            primary_key: :span_id, foreign_key: :parent_id

        # Validations
        validates :span_id, presence: true, uniqueness: true,
                            format: {
                              with: /\Aspan_[a-zA-Z0-9]{24}\z/,
                              message: "must be in format 'span_<24_alphanumeric>'"
                            }
        validates :trace_id, presence: true,
                             format: {
                               with: /\Atrace_[a-zA-Z0-9]{32}\z/,
                               message: "must be in format 'trace_<32_alphanumeric>'"
                             }
        validates :name, presence: true, length: { maximum: 255 }
        # The kinds the tracer actually writes. `job`, `component` and `search`
        # were missing, which never showed up in production because the processor
        # writes through +RAAF::Tracing::SpanRecord+ — a separate, validation-free
        # model built by +const_missing+ — so the rows arrived anyway and this
        # model only ever read them back. Anything writing through this class,
        # a spec included, was rejected for recording a kind its own table is
        # full of.
        validates :kind, inclusion: {
          in: %w[agent llm tool handoff guardrail mcp_list_tools response
                 speech_group speech transcription custom internal trace pipeline
                 job component search decision]
        }
        validates :status, inclusion: { in: %w[ok error cancelled skipped] }

        # Callbacks
        before_validation :ensure_span_id
        before_validation :set_defaults
        after_destroy :update_trace_status
        after_save :update_trace_status
        after_commit :enqueue_continuous_evaluations, on: :create

        # Scopes
        scope :recent, -> { order(start_time: :desc) }
        scope :by_kind, ->(kind) { where(kind: kind) }
        scope :by_status, ->(status) { where(status: status) }
        scope :errors, -> { where(status: "error") }
        scope :successful, -> { where(status: "ok") }
        scope :cancelled, -> { where(status: "cancelled") }
        scope :skipped, -> { where(status: "skipped") }
        scope :slow, ->(threshold_ms = 1000) { where("duration_ms > ?", threshold_ms) }
        scope :within_timeframe, lambda { |start_time, end_time|
          where(start_time: start_time..end_time)
        }

        # Spans that recorded token usage, read from the native columns.
        #
        # This used to also match the payload, with two unanchored LIKEs over
        # +span_attributes::text+, because the columns were added late and no
        # backfill could be assumed. Each of those casts ~21 kB of conversation
        # to text and searches all of it, for every span in the window, and no
        # index can answer them: on production that read was 8.9s of a 9.9s
        # Agents page. Migration 006 fills the columns for every span already
        # written, so the question can be asked of the columns alone.
        scope :with_token_usage, lambda {
          where.not(input_tokens: nil).or(where.not(total_tokens: nil))
        }

        # Spans that recorded a per-call fee.
        scope :with_call_fee, -> { where.not(call_fee_cents: nil) }

        # Spans that plausibly put anything on a bill, in either unit. A page
        # that totals only the first of them omits every search a run made while
        # reporting itself as the whole spend.
        #
        # The unbilled kinds are excluded here rather than left to +billable?+ to
        # reject one row at a time. A job span brackets a run and buys nothing,
        # but the tracer copies its children's token counts onto it, so every one
        # of them matches the prefilter and gets loaded only to be discarded — on
        # a production window that was 815 of 3,401 rows fetched for nothing.
        #
        # A null kind is kept, because +billing_mode+ bills it by the token: the
        # column is nullable, and +where.not+ alone would answer NULL and drop
        # every such span from a total that is supposed to include it.
        scope :with_billable_usage, lambda {
          with_token_usage.or(with_call_fee)
                          .where("kind IS NULL OR kind NOT IN (?)",
                                 ::RAAF::Tracing::SpanUsage::UNBILLED_KINDS)
        }

        # Columns a billing or rollup answer reads, beside the narrowed payload
        # {for_billing} builds. Everything a caller of that scope touches has to
        # be named here: a column left out of the projection raises
        # +MissingAttributeError+ when something reaches for it, rather than
        # quietly answering nil.
        BILLING_COLUMNS = %w[span_id trace_id parent_id kind name status
                             duration_ms start_time input_tokens output_tokens
                             total_tokens agent_model call_fee_cents].freeze

        # Kinds whose billing answer is entirely in the columns.
        #
        # An agent, a pipeline and an llm span are billed by the token: the
        # count and the model are columns, a fee is a column, and none of them
        # is a search component, so nothing left in the payload changes what
        # they cost.
        SELF_DESCRIBING_KINDS = %w[agent pipeline llm].freeze

        # Spans loaded with only the attributes a bill is made of.
        #
        # +span_attributes+ carries the prompt, the messages and the model's
        # whole reply — ~21 kB a span on a production database. Totalling a
        # day's spend needs about a dozen scalars out of that, so this rebuilds
        # the payload from {SpanUsage::BILLING_KEYS} alone and leaves the
        # conversation in the database. Over a 24-hour window on production that
        # is 52 MB of JSON reduced to 302 kB — the difference between a page
        # that renders and one that walks a Puma worker into its memory limit
        # and is killed there.
        #
        # The rebuild is one pass over the payload rather than a key-by-key
        # projection because +span_attributes+ is +json+, not +jsonb+: it is
        # stored as text, so every +->+ reparses the whole document. Fourteen of
        # them measured 7.6s against 0.6s for the single +json_each+ below.
        #
        # Since migration 006 filled the billing columns for every span already
        # written, most rows do not need the rebuild at all: a span of a
        # {SELF_DESCRIBING_KINDS} kind that has a token count in a column has
        # its whole bill in columns, and gets an empty payload without the
        # parse. A row the backfill did not reach still has its payload read,
        # so a database that has not migrated loses speed rather than money.
        #
        # Records come back read-only in every practical sense — they are
        # missing most of their columns — so this is for reading totals, never
        # for writing.
        scope :for_billing, lambda {
          select(*BILLING_COLUMNS, SpanRecord.narrowed_attributes_sql)
        }

        # +span_attributes+ rebuilt from the billing keys alone, aliased back
        # over the column it replaces so {SpanUsage} reads it without knowing it
        # was narrowed.
        #
        # A payload that is not a JSON object — nothing writes one, but the
        # column permits it — becomes an empty one rather than raising out of
        # +json_each+ halfway through a page.
        def self.narrowed_attributes_sql
          @narrowed_attributes_sql ||= sanitize_sql_array(
            [<<~SQL.squish, SELF_DESCRIBING_KINDS, ::RAAF::Tracing::SpanUsage::BILLING_KEYS]
              CASE WHEN #{quoted_table_name}.kind IN (?)
                    AND (#{quoted_table_name}.input_tokens IS NOT NULL
                         OR #{quoted_table_name}.total_tokens IS NOT NULL)
                   THEN '{}'::json
                   ELSE COALESCE((SELECT json_object_agg(entry.key, entry.value)
                          FROM json_each(CASE
                                 WHEN json_typeof(#{quoted_table_name}.span_attributes) = 'object'
                                 THEN #{quoted_table_name}.span_attributes
                                 ELSE '{}'::json END) AS entry
                         WHERE entry.key IN (?)), '{}')::json
              END AS span_attributes
            SQL
          )
        end

        scope :root_spans, -> { where(parent_id: nil) }
        scope :child_spans, -> { where.not(parent_id: nil) }

        # The span kinds that name a unit of work somebody deploys and watches,
        # as opposed to an operation that happens inside one. This is what the
        # Agents screen means by "agent".
        AGENT_KINDS = %w[agent pipeline].freeze

        # The span kinds the Tools screen reports on: a call an agent or a job
        # made to something outside itself.
        #
        # "tool" is an LLM function call and "custom" a hand-instrumented one.
        # "component" is there because it is where the rest of them land:
        # +Traceable+ only infers :tool from a class name ending in "Tool", so an
        # application's search providers and API clients are recorded as
        # components unless they declare +trace_as :tool+. Excluding them left
        # the screen empty for applications whose agents call plain service
        # objects rather than registered tools.
        #
        # "decision" is a call to a decision model, which is something outside
        # the agent that charges per call, so it belongs on this screen beside
        # the search providers rather than on the Agents one.
        TOOL_KINDS = %w[tool custom component decision].freeze

        # JSON columns are natively serialized in Rails 8+
        # No need for explicit serialization

        # Class methods for analytics
        class << self
          # Get performance metrics for spans of a specific kind
          #
          # @param kind [String, nil] Span kind to analyze
          # @param timeframe [Range, nil] Time range to analyze
          # @return [Hash] Performance statistics
          def performance_metrics(kind: nil, timeframe: nil)
            query = reorder(nil)
            query = query.by_kind(kind) if kind
            query = query.within_timeframe(timeframe.begin, timeframe.end) if timeframe

            {
              total_spans: query.count,
              successful_spans: query.successful.count,
              error_spans: query.errors.count,
              avg_duration_ms: query.average(:duration_ms)&.round(2),
              # The median sits beside the average because a handful of very slow
              # spans drag a mean somewhere no actual span was.
              median_duration_ms: query.percentile_for(:duration_ms, 0.5)&.round(2),
              p95_duration_ms: query.percentile_for(:duration_ms, 0.95)&.round(2),
              p99_duration_ms: query.percentile_for(:duration_ms, 0.99)&.round(2),
              success_rate: query.any? ? (query.successful.count.to_f / query.count * 100).round(2) : 0
            }
          end

          # Calculate percentile for a given column
          # Note: This is PostgreSQL-specific. For other databases, you might need different syntax.
          #
          # Not named +percentile+: the descriptive_statistics gem reopens Enumerable
          # and defines +percentile+ there, so on a relation that module wins over
          # delegation to this class method and the call blows up on a Float.
          #
          # @param column [Symbol] Column to calculate percentile for
          # @param fraction [Float] Percentile to calculate (0.0 to 1.0)
          # @return [Float, nil] Percentile value
          def percentile_for(column, fraction)
            return nil if count.zero?

            fraction = Float(fraction)

            # PostgreSQL syntax - adjust for other databases as needed
            if connection.adapter_name.downcase.include?("postgresql")
              # Use unscope to remove any ordering/grouping that might conflict, and
              # pick rather than first so no ORDER BY id lands beside the aggregate.
              aggregate = "PERCENTILE_CONT(#{fraction}) WITHIN GROUP (ORDER BY #{connection.quote_column_name(column)})"
              unscope(:order, :group, :select).pick(Arel.sql(aggregate))
            else
              # Fallback for other databases
              ordered_values = order(column).pluck(column).compact
              return nil if ordered_values.empty?

              index = (fraction * (ordered_values.length - 1)).round
              ordered_values[index]
            end
          end

          # Get error analysis
          #
          # @param timeframe [Range, nil] Time range to analyze
          # @return [Hash] Error statistics
          def error_analysis(timeframe: nil)
            query = errors.reorder(nil)
            query = query.within_timeframe(timeframe.begin, timeframe.end) if timeframe

            error_spans = query

            # Get errors by workflow using a PostgreSQL-compatible approach
            errors_by_workflow = {}
            if error_spans.any?
              # Use pluck to get the raw data, then group and count in Ruby
              # Explicitly specify table names to avoid ambiguous column references
              workflow_data = error_spans.joins("INNER JOIN raaf_tracing_traces ON raaf_tracing_traces.trace_id = raaf_tracing_spans.trace_id")
                                         .pluck("raaf_tracing_traces.workflow_name", "raaf_tracing_spans.span_id")

              # Group by workflow name and count unique span IDs
              workflow_data.group_by(&:first).each do |workflow_name, entries|
                errors_by_workflow[workflow_name] = entries.map(&:last).uniq.count
              end
            end

            {
              total_errors: error_spans.count,
              errors_by_kind: error_spans.reorder(nil).group(:kind).count,
              errors_by_workflow: errors_by_workflow,
              recent_errors: error_spans.reorder(start_time: :desc).limit(10).map(&:error_summary)
            }
          end

          # Token and cost analysis across the matching spans.
          #
          # Reads the native token columns rather than the attributes payload, so
          # a span contributes whichever key shape its tracer happened to use.
          # Spans written before the columns existed are picked up from the
          # payload instead — see {token_usage} — so the answer does not silently
          # halve on a database that has not been backfilled.
          #
          # Not restricted to +kind: "llm"+: the DSL agent records its model and
          # token counts on the agent span, and filtering by kind reported an
          # empty bill for workloads that had spent real money.
          #
          # @param timeframe [Range, nil] Time range to analyze
          # @return [Hash] Cost analysis
          def cost_analysis(timeframe: nil)
            query = unscope(:order)
            query = query.within_timeframe(timeframe.begin, timeframe.end) if timeframe

            candidates = query.with_token_usage
                              .select(:span_id, :span_attributes, :input_tokens, :output_tokens,
                                      :total_tokens, :agent_model)
                              .to_a

            # The scope is deliberately loose, so the count of spans that really
            # recorded usage is settled here rather than by the SQL.
            usages = candidates.map(&:token_usage)
                               .select { |usage| ::RAAF::Tracing::SpanUsage.total_tokens(usage) }

            total_input_tokens = usages.sum { |usage| usage[:input].to_i }
            total_output_tokens = usages.sum { |usage| usage[:output].to_i }
            total_tokens = usages.sum { |usage| ::RAAF::Tracing::SpanUsage.total_tokens(usage).to_i }
            total_cost = usages.sum { |usage| ::RAAF::Tracing::SpanUsage.cost(usage).to_f }

            {
              total_llm_calls: usages.count,
              total_input_tokens: total_input_tokens,
              total_output_tokens: total_output_tokens,
              total_tokens: total_tokens,
              total_cost: total_cost.round(6),
              models_usage: usages.group_by { |usage| usage[:model] }.transform_values(&:count),
              avg_tokens_per_call: usages.any? ? (total_tokens.to_f / usages.count).round(2) : 0
            }
          end

          # Clean up old spans based on retention policy
          #
          # @param older_than [ActiveSupport::Duration] Delete spans older than this
          # @return [Integer] Number of spans deleted
          def cleanup_old_spans(older_than: 30.days)
            where(start_time: ...older_than.ago).delete_all
          end

          # One row per agent, for the Monitor › Agents table.
          #
          # Grouped by name *and* kind, because a pipeline and the agent it runs
          # are two different things to watch even where somebody gave them the
          # same name.
          #
          # @param timeframe [Range, nil] Window to roll up
          # @param kinds [Array<String>] Span kinds counted as agents
          # @return [Array<Hash>] :name, :kind, :model, :runs, :errors,
          #   :error_rate, :p95_ms, :spend — busiest agent first
          def agent_rollup(timeframe: nil, kinds: AGENT_KINDS)
            query = unscope(:order).where(kind: kinds)
            query = query.within_timeframe(timeframe.begin, timeframe.end) if timeframe

            spans = query.for_billing.to_a
            return [] if spans.empty?

            ids = spans.map(&:span_id)
            child_usage = llm_usage_by_parent(ids)
            child_fees = fees_by_parent(ids)

            spans.group_by { |span| [span.name, span.kind] }
                 .map { |(name, kind), group| agent_row(name, kind, group, child_usage, child_fees) }
                 .sort_by { |row| [-row[:runs], row[:name].to_s] }
          end

          # What the window cost and where it went, for the Monitor › Cost &
          # usage screen.
          #
          # Every figure on that screen comes from this one call, so the total,
          # the model breakdown and the agent breakdown cannot disagree with each
          # other — or with what the Agents screen bills the same agents.
          #
          # @param timeframe [Range, nil] Window to total
          # @param top [Integer] Rows to keep in each breakdown
          # @return [Hash] :total_cost, :total_tokens, :input_tokens,
          #   :output_tokens, :runs, :by_model, :by_agent, :preceding
          def cost_rollup(timeframe: nil, top: 8)
            billed = billable_spans(timeframe)

            {
              total_cost: billed.sum(0.0) { |span| span.cost_usd.to_f }.round(6),
              total_tokens: billed.sum { |span| span.total_token_count.to_i },
              input_tokens: billed.sum { |span| span.token_usage[:input].to_i },
              output_tokens: billed.sum { |span| span.token_usage[:output].to_i },
              runs: billed.map(&:trace_id).uniq.size,
              by_model: spend_by(billed, top) { |span| ::RAAF::Tracing::SpanUsage.billed_as(span) },
              by_agent: agent_spend(timeframe, top),
              last_billed_at: last_billed_at,
              preceding: preceding_totals(timeframe)
            }
          end

          # What each workflow spent in the window, for the Overview's agent
          # tiles.
          #
          # Keyed by the trace's workflow name rather than by the agent span's
          # name, which is what {agent_rollup} groups on. The Overview lists
          # workflows, so billing those tiles by agent would put a number on them
          # that belongs to a different grouping — a workflow running three
          # agents would show one agent's bill as if it were the whole run's.
          #
          # A workflow absent from the result recorded no usage at all, which is
          # a different fact from spending nothing: the caller decides how to say
          # so.
          #
          # @param timeframe [Range, nil] Window to total
          # @return [Hash] workflow name => cost in USD
          def spend_by_workflow(timeframe: nil)
            billed = billable_spans(timeframe)
            return {} if billed.empty?

            workflows = TraceRecord.where(trace_id: billed.map(&:trace_id).uniq)
                                   .pluck(:trace_id, :workflow_name).to_h

            billed.each_with_object(Hash.new(0.0)) do |span, totals|
              name = workflows[span.trace_id]
              totals[name] += span.cost_usd.to_f if name
            end
          end

          # The model each workflow mostly ran, for the Overview's agent tiles.
          #
          # One name per workflow rather than a list: a tile has room for one,
          # and a workflow that changed model mid-window is better described by
          # the one it used most than by "and two others". A workflow absent
          # from the result recorded no model at all, which the tile says by
          # printing the run count on its own.
          #
          # Keyed by the trace's workflow name for the same reason
          # {spend_by_workflow} is: the Overview lists workflows, and
          # {agent_rollup} groups by agent span name, so borrowing its model
          # would name one agent's model for a run that used three.
          #
          # @param timeframe [Range, nil] Window to read
          # @return [Hash] workflow name => model name
          def models_by_workflow(timeframe: nil)
            query = unscope(:order).with_token_usage
            query = query.within_timeframe(timeframe.begin, timeframe.end) if timeframe
            spans = query.for_billing.to_a
            return {} if spans.empty?

            workflows = TraceRecord.where(trace_id: spans.map(&:trace_id).uniq)
                                   .pluck(:trace_id, :workflow_name).to_h

            spans.group_by { |span| workflows[span.trace_id] }
                 .except(nil)
                 .filter_map do |name, group|
                   model = dominant_model(group)
                   [name, model] if model
                 end.to_h
          end

          # When anything was last billed, ignoring the window.
          #
          # A window with no spend in it is ambiguous on its own: the reader
          # cannot tell "nothing ran" from "everything ran before this window
          # starts". Carrying the most recent billed run lets the empty state
          # say which, instead of leaving a correct $0.00 looking like a fault.
          #
          # @return [Time, nil] Start of the most recent span that put anything
          #   on a bill, in either unit
          def last_billed_at
            unscope(:order).with_billable_usage.maximum(:start_time)
          end

          # One row per distinct failure, for the Monitor › Errors table.
          #
          # Grouped by exception class and message rather than listed span by
          # span: an agent retrying one broken tool 148 times is a single thing
          # to fix, and as a flat list it buries every other failure in the
          # window under its own repetitions.
          #
          # @param timeframe [Range, nil] Window to group
          # @param limit [Integer] Most frequent signatures to return
          # @return [Array<Hash>] :exception, :message, :agent, :kind, :count,
          #   :traces, :trend, :last_seen, :span_id — most frequent first
          def error_signatures(timeframe: nil, limit: 50)
            current = failures_within(timeframe)
            return [] if current.empty?

            before = preceding_signature_counts(timeframe)

            current.group_by { |span| signature_key(span) }
                   .map { |key, group| error_signature_row(key, group, before) }
                   .sort_by { |row| [-row[:count], row[:exception].to_s] }
                   .first(limit)
          end

          private

          def failures_within(timeframe)
            query = unscope(:order).errors.includes(:trace)
            query = query.within_timeframe(timeframe.begin, timeframe.end) if timeframe
            query.to_a
          end

          # How often each signature fired in the same length of time immediately
          # before the window, so a trend compares like with like. Without a
          # window there is nothing to compare against and every signature is
          # reported as new rather than as flat.
          def preceding_signature_counts(timeframe)
            return {} unless timeframe

            length = timeframe.end - timeframe.begin
            preceding = (timeframe.begin - length)..timeframe.begin

            failures_within(preceding).group_by { |span| signature_key(span) }
                                      .transform_values(&:size)
          end

          # What makes two failures the same failure. The message is part of it:
          # one Faraday::TimeoutError per upstream host is several problems, not
          # one, and collapsing them by class alone hides which host is down.
          def signature_key(span)
            details = span.error_details || {}
            message = details[:exception_message] || details[:status_description]

            [details[:exception_type].presence || "Error",
             message.to_s.strip.presence || "No message recorded"]
          end

          def error_signature_row((exception, message), spans, before)
            timed = spans.select(&:start_time)
            newest = timed.max_by(&:start_time) || spans.first
            previous = before[[exception, message]]

            {
              exception: exception,
              message: message,
              # The display name, not the raw span name: a job's span is called
              # "run.workflow.job.SomeJob.perform", which names the
              # instrumentation rather than the thing that broke.
              agent: most_common(spans.map(&:display_name)),
              kind: most_common(spans.map(&:kind)),
              count: spans.size,
              traces: spans.map(&:trace_id).uniq.size,
              trend: trend_percentage(spans.size, previous),
              # When it started as well as when it last fired: a signature that
              # began an hour ago and one that has been firing for a week read
              # identically from the newest occurrence alone.
              first_seen: timed.min_by(&:start_time)&.start_time,
              last_seen: newest.start_time,
              span_id: newest.span_id,
              # The trace as well as the span: a signature's row opens the span
              # inside its trace, which is where the design sends every span.
              trace_id: newest.trace_id
            }
          end

          # Percent change against the preceding window, or nil where the
          # signature did not fire in it at all — "new" is a different fact from
          # "up 100%", and the one worth reading differently.
          def trend_percentage(count, previous)
            return nil if previous.nil? || previous.zero?

            (((count - previous) / previous.to_f) * 100).round
          end

          def agent_row(name, kind, spans, child_usage, child_fees)
            errors = spans.count { |span| span.status == "error" }
            durations = spans.filter_map { |span| span.duration_ms&.to_f }.sort
            usage = spans.map { |span| span_usage(span, child_usage, child_fees) }

            {
              name: name,
              kind: kind,
              model: dominant_model(spans),
              runs: spans.size,
              errors: errors,
              error_rate: ((errors.to_f / spans.size) * 100).round(1),
              p95_ms: percentile_of(durations, 0.95),
              spend: usage.sum(0.0) { |one| one[:cost] }.round(6),
              tokens: usage.sum { |one| one[:tokens] }
            }
          end

          # What one agent span used: its own usage where it recorded any, and
          # its LLM children's where it did not, plus whatever its per-call
          # children were charged.
          #
          # The token half is deliberately one or the other rather than the sum —
          # a DSL agent writes the same token counts on the agent span that its
          # llm children carry, so adding them bills every such run twice. Fees
          # add, because nothing copies them upward: an agent that spends most of
          # its money on search reported almost none of it while they were left
          # out.
          def span_usage(span, child_usage, child_fees)
            tokens = span.total_token_count
            own = if tokens
                    { cost: span.cost_usd.to_f, tokens: tokens }
                  else
                    child_usage.fetch(span.span_id, { cost: 0.0, tokens: 0 })
                  end

            { cost: own[:cost] + child_fees[span.span_id].to_f, tokens: own[:tokens] }
          end

          # Cost and tokens of the LLM spans hanging directly off each of the
          # given spans.
          #
          # Not filtered by the timeframe: a child starts inside the run its
          # parent started, and clipping it at the window edge would drop the
          # tail of every run still in flight when the window opened.
          #
          # @return [Hash] parent span id => +{ cost:, tokens: }+
          # What each agent's per-call children were charged. Direct children
          # only, the same one level {llm_usage_by_parent} looks at.
          def fees_by_parent(parent_ids)
            unscope(:order).with_call_fee.where(parent_id: parent_ids).for_billing
                           .each_with_object(Hash.new(0.0)) do |span, totals|
              fee = span.call_fee_usd
              totals[span.parent_id] += fee if fee
            end
          end

          def llm_usage_by_parent(parent_ids)
            unscope(:order).by_kind("llm").where(parent_id: parent_ids).for_billing
                           .each_with_object({}) do |span, totals|
              running = totals[span.parent_id] ||= { cost: 0.0, tokens: 0 }
              running[:cost] += span.cost_usd.to_f
              running[:tokens] += span.total_token_count.to_i
            end
          end

          # Every span that was billed in the window, minus the ones whose parent
          # already accounts for it.
          #
          # Same rule as {span_usage}, applied across the whole window: an agent
          # span and its LLM children routinely carry the same counts, so summing
          # both bills the run twice. Counting the parent and dropping the
          # children keeps the total equal to what the Agents screen bills.
          #
          # The de-duplication is deliberately limited to spans billed by the
          # token, because that is the only thing an agent span copies. A search
          # fee is recorded once, on the span that paid it, so dropping it for
          # having an agent parent would delete the charge rather than avoid
          # counting it twice.
          def billable_spans(timeframe)
            query = unscope(:order).with_billable_usage
            query = query.within_timeframe(timeframe.begin, timeframe.end) if timeframe

            spans = query.for_billing.to_a.select(&:billable?)
            covered = spans.each_with_object({}) do |span, ids|
              ids[span.span_id] = true if AGENT_KINDS.include?(span.kind)
            end

            spans.reject { |span| span.billed_in_tokens? && covered.key?(span.parent_id) }
          end

          # What the same length of time immediately before the window cost, so
          # the screen's headline figures can say which way they are moving.
          #
          # Only the two totals a KPI compares against, not a second breakdown:
          # nothing on the screen puts last week's model split beside this
          # week's, and rolling the agents up twice doubles the cost of the page.
          #
          # Nil where there is nothing to compare with — no window, or a
          # preceding one that recorded no spend at all. A first week of traffic
          # is not "up 100%", and a percentage over zero is a division rather
          # than a fact about the bill.
          def preceding_totals(timeframe)
            return nil unless timeframe

            length = timeframe.end - timeframe.begin
            billed = billable_spans((timeframe.begin - length)..timeframe.begin)
            return nil if billed.empty?

            { total_cost: billed.sum(0.0) { |span| span.cost_usd.to_f }.round(6),
              runs: billed.map(&:trace_id).uniq.size }
          end

          # Cost and tokens grouped by whatever the block names, largest first.
          def spend_by(spans, top, &grouping)
            spans.group_by(&grouping)
                 .filter_map do |name, group|
                   next if name.blank?

                   { name: name,
                     cost: group.sum(0.0) { |span| span.cost_usd.to_f }.round(6),
                     tokens: group.sum { |span| span.total_token_count.to_i } }
                 end
                 .sort_by { |row| -row[:cost] }
                 .first(top)
          end

          # The agent breakdown reuses the Agents rollup rather than regrouping
          # the spans, so one agent's bill is the same number on both screens.
          def agent_spend(timeframe, top)
            agent_rollup(timeframe: timeframe)
              .map { |row| { name: row[:name], cost: row[:spend], tokens: row[:tokens] } }
              .reject { |row| row[:cost].zero? && row[:tokens].zero? }
              .sort_by { |row| -row[:cost] }
              .first(top)
          end

          # The model most of an agent's runs recorded, ignoring the runs that
          # recorded none — an agent that reports its model on three runs in ten
          # still ran on that model.
          def dominant_model(spans)
            most_common(spans.filter_map { |span| span.token_usage[:model] })
          end

          # The value a group agrees on most often. Used where a rollup has to
          # name one thing for a set of spans that need not all agree.
          def most_common(values)
            return nil if values.empty?

            values.tally.max_by { |_, count| count }.first
          end

          # Linear-interpolated percentile of an already sorted array.
          #
          # Separate from {percentile_for}, which asks PostgreSQL about a column:
          # here the durations are already in memory from the rollup, and asking
          # the database again would be one query per agent.
          def percentile_of(sorted, fraction)
            return nil if sorted.empty?
            return sorted.first if sorted.one?

            position = fraction * (sorted.length - 1)
            lower = sorted[position.floor]
            upper = sorted[position.ceil]

            lower + ((upper - lower) * (position - position.floor))
          end
        end

        # Instance methods

        # Check if span has errors
        #
        # @return [Boolean] True if span status is error
        def error?
          status == "error"
        end

        # Check if span completed successfully
        #
        # @return [Boolean] True if span status is ok
        def successful?
          status == "ok"
        end

        # Check if span was cancelled/skipped
        #
        # @return [Boolean] True if span status is cancelled or skipped
        def cancelled?
          %w[cancelled skipped].include?(status)
        end

        # Check if span was skipped
        #
        # @return [Boolean] True if span status is skipped
        def skipped?
          status == "skipped"
        end

        # Get span duration in seconds
        #
        # @return [Float, nil] Duration or nil if not available
        def duration_seconds
          duration_ms&./(1000.0)
        end

        # Check if this is a root span (no parent)
        #
        # @return [Boolean] True if no parent span
        def root_span?
          parent_id.nil?
        end

        # Get all child span IDs
        #
        # @return [Array<String>] Array of child span IDs
        def child_span_ids
          children.pluck(:span_id)
        end

        # Get span depth in the hierarchy
        #
        # @return [Integer] Depth level (0 for root spans)
        def depth
          return 0 if root_span?

          parent_span&.depth&.+(1) || 1
        end

        # Get error details if span failed
        #
        # Two writers record a failure and they disagree on where it goes.
        # {RAAF::Tracing::SpanTracer} adds an "exception" event. Traceable's
        # +fail_span+ — the path every agent, tool, pipeline and job takes —
        # writes flat +error.*+ attributes and no event at all. Reading only the
        # event left every failure from that path with no class and no message,
        # which is what the dashboards were rendering as "Unknown error".
        #
        # @return [Hash, nil] Error information
        def error_details
          return nil unless error?

          event = events&.find { |e| e["name"] == "exception" }&.dig("attributes") || {}
          attributes = span_attributes || {}

          {
            status_description: attributes.dig("status", "description"),
            exception_type: event["exception.type"] || attributes["error.type"],
            exception_message: event["exception.message"] || attributes["error.message"],
            exception_stacktrace: event["exception.stacktrace"] || attributes["error.backtrace"]
          }.compact
        end

        # Get skip reason if span was skipped
        #
        # @return [String, nil] Skip reason or nil if not skipped
        def skip_reason
          return nil unless skipped? || cancelled?

          span_attributes&.dig("agent.skip_reason") ||
            span_attributes&.dig("skip_reason") ||
            span_attributes&.dig("cancelled_reason") ||
            "No reason provided"
        end

        # Get summary of span for error reporting
        #
        # @return [Hash] Span summary
        def error_summary
          {
            span_id: span_id,
            trace_id: trace_id,
            name: name,
            kind: kind,
            start_time: start_time,
            duration_ms: duration_ms,
            error_details: error_details
          }
        end

        # Token usage and model this span recorded.
        #
        # Prefers the native columns and falls back to the attributes payload, so
        # a span written before the columns existed still reports its tokens.
        # {RAAF::Tracing::SpanUsage} owns the key shapes.
        #
        # @return [Hash] +{ input:, output:, total:, model: }+, nil where absent
        def token_usage
          ::RAAF::Tracing::SpanUsage.for_span(self)
        end

        # Tokens this span consumed, counted the way the provider bills.
        #
        # Uses the reported total in preference to input + output, because a
        # provider that charges for tokens it does not itemise — Gemini 2.5 and
        # its thinking tokens — only reveals them in the total.
        #
        # @return [Integer, nil] Token count, or nil when the span recorded none
        def total_token_count
          ::RAAF::Tracing::SpanUsage.total_tokens(token_usage)
        end

        # Cost in USD of what this span bought, in the unit it is billed in.
        #
        # A model charges per token; a search provider charges per query and
        # records a flat fee instead; a job buys nothing. Reading only the first
        # of those priced the other two at zero, which is how the Cost & usage
        # screen came to leave search spend out of a total it presented as
        # complete.
        #
        # @return [Float, nil] Cost, or nil when unbilled, unpriced or unrecorded
        def cost_usd
          ::RAAF::Tracing::SpanUsage.spend_for_span(self)
        end

        # The flat fee this span recorded for one call, in USD.
        #
        # @return [Float, nil] Fee, or nil when it recorded none
        def call_fee_usd
          ::RAAF::Tracing::SpanUsage.fee_for_span(self)
        end

        # Whether this span is billed by the token.
        #
        # @return [Boolean]
        def billed_in_tokens?
          ::RAAF::Tracing::SpanUsage.billed_in_tokens?(self)
        end

        # Whether this span put anything on a bill at all.
        #
        # A job answers false whatever it recorded. The tracer copies a child's
        # token counts onto the job span often enough that counting it would add
        # a run, and a token total, for money the child already reported.
        #
        # @return [Boolean]
        def billable?
          return false if ::RAAF::Tracing::SpanUsage.billing_mode(self) == :none

          !total_token_count.nil? || !call_fee_usd.nil?
        end

        # Get operation-specific details based on span kind
        #
        # @return [Hash] Kind-specific attributes
        def operation_details
          case kind
          when "llm"
            usage = token_usage
            {
              model: usage[:model],
              input_tokens: usage[:input],
              output_tokens: usage[:output],
              total_tokens: usage[:total],
              messages: span_attributes&.dig("llm", "request", "messages")
            }
          when "tool"
            {
              function_name: span_attributes&.dig("function", "name"),
              input: span_attributes&.dig("function", "input"),
              output: span_attributes&.dig("function", "output")
            }
          when "agent"
            usage = token_usage
            {
              agent_name: span_attributes&.dig("agent", "name"),
              tools: span_attributes&.dig("agent", "tools"),
              handoffs: span_attributes&.dig("agent", "handoffs"),
              model: usage[:model],
              input_tokens: usage[:input],
              output_tokens: usage[:output],
              total_tokens: usage[:total]
            }
          when "handoff"
            {
              from_agent: span_attributes&.dig("handoff", "from"),
              to_agent: span_attributes&.dig("handoff", "to")
            }
          else
            span_attributes&.slice("name", "data") || {}
          end.compact
        end

        # The attributes that say what one span was *about*, in the order a
        # reader wants them. A listing that names only the class is a column of
        # identical rows — three thousand of them reading
        # "Ai::SearchProviders::Google" — and the one line that tells them apart
        # is the query, the URL, or the record being worked on.
        #
        # Exact keys first, then the suffixes, so a vocabulary this list has
        # never seen still offers its own `*.query` or `*.company` rather than
        # nothing. Names the framework writes about itself are not subjects:
        # `component.name` is the class the label already shows.
        SUBJECT_KEYS = %w[query search.query search_query http.url tool_arguments
                          job.arguments arguments].freeze
        SUBJECT_SUFFIXES = %w[.query .url .path .company .target].freeze

        # Counts that belong beside the subject: 9 results, 12 edges. The unit is
        # the key's own word, so a vocabulary nobody anticipated still counts in
        # its own terms.
        SUBJECT_COUNT_SUFFIX = /(?:\A|\.)(?<unit>[a-z_]+)_count\z/

        # How much of a subject a row can carry. The cell truncates on its own,
        # but a 4KB argument blob has no business being measured by the browser.
        SUBJECT_LIMIT = 160

        # One line saying what this span was about, or nil when it recorded
        # nothing that answers that.
        #
        # @return [String, nil]
        def display_subject
          value = subject_value
          return nil if value.blank?

          [truncate_subject(value), subject_count].compact.join(" · ")
        end

        # Get display name for span, showing tool function names when available
        #
        # @return [String] Human-readable span name
        def display_name
          case kind
          when "tool"
            # Check multiple possible locations for tool name
            tool_name = span_attributes&.dig("function", "name") ||
                        span_attributes&.dig("tool_name") ||
                        span_attributes&.dig("tool", "name")
            tool_name.presence || extract_readable_name || "Tool Call"
          when "agent"
            agent_name = span_attributes&.dig("agent", "name")
            agent_name.presence || extract_agent_name || extract_readable_name || "Agent Execution"
          when "pipeline"
            extract_pipeline_name || extract_readable_name || "Pipeline Execution"
          when "llm"
            # New: Extract meaningful LLM operation name
            operation = extract_llm_operation
            model = span_attributes&.dig("model") || span_attributes&.dig("llm", "model")

            if model && operation
              "#{model} - #{operation.humanize}"
            elsif operation
              "LLM #{operation.humanize}"
            else
              "LLM Operation"
            end
          else
            extract_readable_name || "#{kind.to_s.capitalize} Operation"
          end
        end

        # Get timeline of events within this span
        #
        # @return [Array<Hash>] Chronological list of events
        def event_timeline
          (events || []).sort_by { |e| e["timestamp"] }
        end

        # Extract readable name from technical span names
        # The tracer writes span names as "run.workflow.<kind>.<Class>.<method>",
        # e.g. "run.workflow.custom.Ecosystem::TedClient.search". Strip that
        # framing and keep the whole constant path.
        #
        # Matching the first capitalised word instead — which is what this used
        # to do — cut "Ecosystem::TedClient.search" down to "Ecosystem", so every
        # tool sharing a namespace collapsed into a single row on the Tools
        # screen. Names that are not in the tracer's dotted form (a tool named
        # "Overture::CompanyMatchService/match") are already readable and are
        # returned whole.
        INTERNAL_SPAN_NAME = /\Arun\.workflow\.[a-z_]+\.(?<path>.+)\z/

        TRAILING_METHOD = /\.[a-z_][A-Za-z0-9_]*\z/

        # The same two rules in SQL, so a filter can compare against the name a
        # screen actually shows. Without it the Tools registry linked to
        # "Ai::SearchProviders::ScrapingBee" and landed on an empty list, since
        # the column holds
        # "run.workflow.component.Ai::SearchProviders::ScrapingBee.search".
        #
        # Kept beside the regexes it mirrors: the two have to move together.
        READABLE_NAME_SQL =
          "regexp_replace(regexp_replace(name, '^run\\.workflow\\.[a-z_]+\\.', ''), " \
          "'\\.[a-z_][A-Za-z0-9_]*$', '')"

        # An argument list that is not JSON — a job whose arguments were written
        # with `inspect` — arrives as `[{period_type: "daily"}]`. The brackets are
        # the container, not the subject, so a listing reads better without them:
        # `period_type: "daily"`.
        UNWRAPPED_SUBJECT = /\A\[(.*)\]\z|\A\{(.*)\}\z/m

        private

        def extract_readable_name
          return nil unless name

          match = name.match(INTERNAL_SPAN_NAME)
          return name unless match

          path = match[:path]
          path.sub(TRAILING_METHOD, "").presence || path
        end

        # The first subject-bearing attribute the span wrote.
        def subject_value
          attrs = span_attributes
          return nil unless attrs.is_a?(Hash)

          key = SUBJECT_KEYS.find { |candidate| attrs[candidate].present? } ||
                subject_key_by_suffix(attrs)
          return nil unless key

          stringify_subject(attrs[key])
        end

        # Suffixes in their own order, and the keys within one suffix sorted, so
        # a span with both `a.query` and `b.query` picks the same one every time
        # rather than whichever the hash happened to yield first.
        def subject_key_by_suffix(attrs)
          candidates = attrs.keys.select { |key| attrs[key].present? }.sort

          SUBJECT_SUFFIXES.each do |suffix|
            match = candidates.find { |key| key.to_s.end_with?(suffix) }
            return match if match
          end

          nil
        end

        # "9 results", "12 edges" — the unit taken from the counting key itself.
        # A zero count is still worth saying: a search that found nothing is the
        # interesting row in a listing of searches that found something.
        def subject_count
          attrs = span_attributes
          return nil unless attrs.is_a?(Hash)

          key = attrs.keys.find { |k| k.to_s.match?(SUBJECT_COUNT_SUFFIX) }
          return nil unless key

          count = attrs[key]
          return nil unless count.is_a?(Numeric) || count.to_s.match?(/\A\d+\z/)

          unit = key.to_s.match(SUBJECT_COUNT_SUFFIX)[:unit]
          "#{count.to_i} #{unit.tr('_', ' ').pluralize(count.to_i)}"
        end

        # An argument list is written as JSON, and its first element is the thing
        # being acted on — the service a job runs, the record it runs it for.
        # Anything else is printed as it stands.
        def stringify_subject(value)
          value = ::JSON.parse(value) if value.is_a?(String) && value.start_with?("[", "{")
          case value
          when Array then value.find { |item| item.is_a?(String) || item.is_a?(Numeric) }&.to_s
          when Hash then value.values.find { |item| item.is_a?(String) }&.to_s
          else value.to_s
          end
        rescue ::JSON::ParserError
          unwrap_subject(value.to_s)
        end

        def unwrap_subject(value)
          previous = nil

          while value != previous
            previous = value
            match = value.strip.match(UNWRAPPED_SUBJECT)
            value = (match[1] || match[2]).strip if match
          end

          value
        end

        def truncate_subject(value)
          value.length > SUBJECT_LIMIT ? "#{value[0, SUBJECT_LIMIT].rstrip}…" : value
        end

        # Extract agent name from span name
        def extract_agent_name
          return nil unless name

          return unless name.match(/\.agent\.([A-Za-z:]+)\./)

          class_name = ::Regexp.last_match(1).split("::").last
          # Handle special cases like "RAAF::Agent.llm_call"
          if class_name == "Agent"
            # Check for method name at the end
            if name.match(/\.([a-z_]+)$/)
              ::Regexp.last_match(1).gsub("_", " ").titleize
            else
              "LLM Call"
            end
          else
            class_name&.gsub("Agent", "")
          end
        end

        # Extract pipeline name from span name
        def extract_pipeline_name
          return nil unless name

          return unless name.match(/\.pipeline\.([A-Za-z:]+)/)

          class_name = ::Regexp.last_match(1).split("::").last
          class_name&.gsub("Pipeline", "")
        end

        # Extract LLM operation from span name
        def extract_llm_operation
          return nil unless name

          # Extract operation from patterns like "run.workflow.llm.completion"
          return unless name.match(/\.llm\.([a-z_]+)/)

          ::Regexp.last_match(1)
        end

        # Get all events of a specific type
        #
        # @param event_name [String] Name of event to filter by
        # @return [Array<Hash>] Matching events
        def events_by_name(event_name)
          (events || []).select { |e| e["name"] == event_name }
        end

        # Ensure span_id is set
        def ensure_span_id
          return if span_id.present?

          self.span_id = "span_#{SecureRandom.hex(12)}" # 24 character hex
        end

        # Set default values
        def set_defaults
          self.status = "ok" if status.blank?
          self.kind = "internal" if kind.blank?
          self.span_attributes = {} if span_attributes.blank?
          self.events = [] if events.blank?
        end

        # Update associated trace status after span changes
        def update_trace_status
          trace&.update_trace_status
        rescue StandardError => e
          ::Rails.logger.warn "[Ruby AI Agents Factory Tracing] Failed to update trace status: #{e.message}"
        end

        # Enqueue continuous evaluation for newly created spans
        # This hook runs after the span is committed to the database
        #
        # Note: This callback also exists in RAAF::Tracing::SpanRecord (tracing gem).
        # Both classes may be used to create spans depending on the context.
        # The callback is safe to run on both since it handles duplicates gracefully.
        def enqueue_continuous_evaluations
          # Return early if continuous evaluation is disabled
          return unless defined?(RAAF::Eval::Continuous)
          return unless RAAF::Eval::Continuous.enabled?
          return unless RAAF::Eval::Continuous.configuration.hook_enabled

          # Find matching policies and enqueue evaluation jobs
          begin
            matcher = RAAF::Eval::Continuous::PolicyMatcher.new(self)
            policies = matcher.policies_to_evaluate

            policies.each do |policy|
              RAAF::Rails::Continuous::EvaluationJob.perform_later(
                span_id: span_id,
                policy_id: policy.id
              )
            end
          rescue StandardError => e
            # Log errors but don't raise - we don't want to break span creation
            ::Rails.logger.warn "[Ruby AI Agents Factory Continuous Eval] Failed to enqueue evaluations: #{e.message}"
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class BaseComponent < Phlex::HTML
        include Phlex::Rails::Helpers::LinkTo
        include Phlex::Rails::Helpers::ButtonTo
        include Phlex::Rails::Helpers::TimeAgoInWords
        include Phlex::Rails::Helpers::Pluralize
        include Phlex::Rails::Helpers::Truncate
        include Phlex::Rails::Helpers::FormWith
        include Phlex::Rails::Helpers::ContentFor
        include Phlex::Rails::Helpers::OptionsForSelect
        include Phlex::Rails::Helpers::Routes
        include Phlex::Rails::Helpers::CSRFMetaTags
        include Phlex::Rails::Helpers::CSPMetaTag
        include Phlex::Rails::Helpers::FormAuthenticityToken
        include RAAF::Logging

        # Short names for the Glass Morph library, resolved through the
        # ancestry so every page component inherits them.
        Atoms = Ui::Atoms
        Molecules = Ui::Molecules
        Organisms = Ui::Organisms

        # Above this a score is healthy; below the lower bound it is failing.
        # The tiers every screen colours a score against — see {#score_tone}.
        GOOD_SCORE = 0.8
        POOR_SCORE = 0.5

        # What every id is prefixed with — see {#truncate_id}.
        ID_PREFIX = /\A(?:trace|span)_/

        private

        # Route helper methods for the RAAF Rails engine
        def tracing_spans_path(params = {})
          path = "/raaf/tracing/spans"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        # Where a span row goes.
        #
        # The design has no span screen: on Spans, in Search, in an error
        # group, every row calls `goScreen("trace")`. A span opens its trace
        # with itself selected, so it is always read beside the run it belongs
        # to — the waterfall says what ran before and after it, which a page
        # showing one span alone cannot.
        #
        # Nil for a span whose trace was never recorded, because there is now
        # nowhere to send it: the span page this used to fall back to is gone.
        # Every caller passes the result as an `href`, and both the row
        # components render a plain row rather than a link when it is absent.
        def trace_span_path(span_id, trace_id, tab: nil)
          return nil if trace_id.blank?

          "#{tracing_trace_path(trace_id)}?#{{ span: span_id, tab: tab }.compact.to_query}"
        end

        def tracing_traces_path(params = {})
          path = "/raaf/tracing/traces"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def tracing_trace_path(id)
          "/raaf/tracing/traces/#{id}"
        end

        def tools_tracing_spans_path(params = {})
          path = "/raaf/tracing/spans/tools"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def flows_tracing_spans_path(params = {})
          path = "/raaf/tracing/spans/flows"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def destroy_all_tracing_spans_path
          "/raaf/tracing/spans/destroy_all"
        end

        def destroy_all_tracing_traces_path
          "/raaf/tracing/traces/destroy_all"
        end

        def dashboard_path
          "/raaf/dashboard"
        end

        # @param digest [String] {RAAF::Rails::Ui::Stylesheet.digest}
        # @return [String] path to the console stylesheet for that content
        def console_stylesheet_path(digest)
          "/raaf/assets/console-#{digest}.css"
        end

        # @param digest [String] {RAAF::Rails::Ui::Javascript.digest}
        # @return [String] path to the console's Stimulus bundle for that content
        def console_javascript_path(digest)
          "/raaf/assets/console-#{digest}.js"
        end

        def dashboard_performance_path
          "/raaf/dashboard/performance"
        end

        def dashboard_agents_path(params = {})
          path = "/raaf/dashboard/agents"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def dashboard_costs_path
          "/raaf/dashboard/costs"
        end

        def dashboard_errors_path(params = {})
          path = "/raaf/dashboard/errors"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def tracing_search_path(params = {})
          path = "/raaf/tracing/search"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def evaluate_tracing_span_path(span_id, params = {})
          span_id_str = span_id.respond_to?(:span_id) ? span_id.span_id : span_id
          path = "/raaf/tracing/spans/#{span_id_str}/evaluate"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        # Continuous evaluation routes
        def continuous_policies_path(params = {})
          path = "/raaf/continuous/policies"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def continuous_policy_path(id)
          policy_id = id.respond_to?(:id) ? id.id : id
          "/raaf/continuous/policies/#{policy_id}"
        end

        def new_continuous_policy_path
          "/raaf/continuous/policies/new"
        end

        def edit_continuous_policy_path(id)
          policy_id = id.respond_to?(:id) ? id.id : id
          "/raaf/continuous/policies/#{policy_id}/edit"
        end

        def activate_continuous_policy_path(id)
          policy_id = id.respond_to?(:id) ? id.id : id
          "/raaf/continuous/policies/#{policy_id}/activate"
        end

        def deactivate_continuous_policy_path(id)
          policy_id = id.respond_to?(:id) ? id.id : id
          "/raaf/continuous/policies/#{policy_id}/deactivate"
        end

        def duplicate_continuous_policy_path(id)
          policy_id = id.respond_to?(:id) ? id.id : id
          "/raaf/continuous/policies/#{policy_id}/duplicate"
        end

        def continuous_evaluators_path(params = {})
          path = "/raaf/continuous/evaluators"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def continuous_evaluator_path(id)
          "/raaf/continuous/evaluators/#{id}"
        end

        def continuous_queue_index_path(params = {})
          path = "/raaf/continuous/queue"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        # Alias for consistency
        def continuous_queue_items_path(params = {})
          continuous_queue_index_path(params)
        end

        def continuous_queue_path(id)
          queue_id = id.respond_to?(:id) ? id.id : id
          "/raaf/continuous/queue/#{queue_id}"
        end

        # Alias for consistency
        def continuous_queue_item_path(id)
          continuous_queue_path(id)
        end

        def retry_failed_continuous_queue_index_path
          "/raaf/continuous/queue/retry_failed"
        end

        def discard_failed_continuous_queue_index_path
          "/raaf/continuous/queue/discard_failed"
        end

        def retry_continuous_queue_item_path(id)
          queue_id = id.respond_to?(:id) ? id.id : id
          "/raaf/continuous/queue/#{queue_id}/retry"
        end

        def cancel_continuous_queue_item_path(id)
          queue_id = id.respond_to?(:id) ? id.id : id
          "/raaf/continuous/queue/#{queue_id}/cancel"
        end

        def continuous_trends_path(params = {})
          path = "/raaf/continuous/trends"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def continuous_results_path(params = {})
          path = "/raaf/continuous/results"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def continuous_result_path(id)
          result_id = id.respond_to?(:id) ? id.id : id
          "/raaf/continuous/results/#{result_id}"
        end

        def continuous_analytics_path
          "/raaf/continuous/analytics"
        end

        def continuous_health_path(params = {})
          path = "/raaf/continuous/health"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        # System status: queue depth, backpressure and the configuration in
        # force. Reached from the sidebar since #1023; nothing linked it
        # before, which is why it raised NoMethodError for a long time
        # unnoticed.
        def dashboard_continuous_health_path
          "/raaf/continuous/health/dashboard"
        end

        # Eval feature routes (Opik-inspired: Datasets, Experiments, Feedback, Prompts)
        def eval_datasets_path(params = {})
          path = "/raaf/eval/datasets"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def eval_dataset_path(id)
          dataset_id = id.respond_to?(:id) ? id.id : id
          "/raaf/eval/datasets/#{dataset_id}"
        end

        def new_eval_dataset_path
          "#{eval_datasets_path}/new"
        end

        def new_version_eval_dataset_path(id)
          "#{eval_dataset_path(id)}/new_version"
        end

        def eval_dataset_item_path(dataset, item)
          item_id = item.respond_to?(:id) ? item.id : item
          "#{eval_dataset_path(dataset)}/items/#{item_id}"
        end

        def archive_eval_dataset_path(id)
          "#{eval_dataset_path(id)}/archive"
        end

        def eval_experiments_path(params = {})
          path = "/raaf/eval/experiments"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def eval_experiment_path(id)
          experiment_id = id.respond_to?(:id) ? id.id : id
          "/raaf/eval/experiments/#{experiment_id}"
        end

        def edit_eval_experiment_path(id)
          "#{eval_experiment_path(id)}/edit"
        end

        def compare_eval_experiment_path(id, params = {})
          path = "#{eval_experiment_path(id)}/compare"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def eval_experiment_results_path(experiment_id, params = {})
          path = "#{eval_experiment_path(experiment_id)}/results"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def eval_experiment_result_path(experiment_id, id)
          result_id = id.respond_to?(:id) ? id.id : id
          "#{eval_experiment_results_path(experiment_id)}/#{result_id}"
        end

        def eval_feedback_scores_path(params = {})
          path = "/raaf/eval/feedback_scores"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def eval_prompts_path(params = {})
          path = "/raaf/eval/prompts"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def eval_prompt_path(id)
          prompt_id = id.respond_to?(:id) ? id.id : id
          "/raaf/eval/prompts/#{prompt_id}"
        end

        # What an experiment run cost, priced from the tokens it recorded
        # against the model it ran.
        #
        # An experiment run is the most expensive thing the console starts, and
        # neither tokens nor spend appeared on the run, the list or the
        # comparison — though cost is the usual reason to prefer one run over
        # another when the scores are level, and it is the figure a reader
        # wants before pressing Run again.
        #
        # Computed rather than stored: nothing in the eval schema records a
        # cost, and pricing lives in SpanUsage, which is where every other
        # screen in the console gets a bill from. Nil where the run recorded no
        # tokens or the model has no published price — a dash, not $0.00.
        def experiment_spend(experiment)
          usage = experiment_usage(experiment)
          return nil unless usage[:total]

          ::RAAF::Tracing::SpanUsage.cost(usage)
        end

        # Tokens as SpanUsage wants them. `aggregate_metrics` is jsonb, so it
        # comes back string-keyed from the database and symbol-keyed from a
        # record still in memory.
        def experiment_usage(experiment)
          tokens = experiment.aggregate_metrics.is_a?(Hash) ? experiment.aggregate_metrics : {}
          tokens = tokens["tokens"] || tokens[:tokens] || {}

          { input: dig_either(tokens, :total_input_tokens),
            output: dig_either(tokens, :total_output_tokens),
            total: dig_either(tokens, :total_tokens),
            model: experiment.model.presence }
        end

        def dig_either(hash, key)
          value = hash[key.to_s].nil? ? hash[key] : hash[key.to_s]
          value&.to_i
        end

        def money(amount, places: 2)
          return "—" if amount.nil?

          # Kernel#format, not the `format` a Phlex component answers with.
          "$#{Kernel.format("%.#{places}f", amount.to_f)}"
        end

        def diff_eval_prompt_path(id, params = {})
          path = "#{eval_prompt_path(id)}/diff"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        # What can be done to a span, as arguments for Atoms::Button.
        #
        # A span is read on two screens -- its own page, and the inspector
        # beside the waterfall on its trace -- and in practice almost always
        # the second, because every span row links to its trace with itself
        # selected rather than to the span page. Both therefore carry these
        # controls, and both get them from here.
        #
        # Empty when the replayer could not rebuild the call from what the
        # span recorded, so the button never leads to a form that immediately
        # sends you back. Empty too when the replay table has not been
        # migrated in: a dashboard missing it should lose the button, not the
        # page.
        #
        # @param span [SpanRecord, nil]
        # @return [Array<Hash>]
        def span_replay_actions(span)
          return [] unless span && SpanReplay.table_exists? && SpanReplay.replayable?(span)

          actions = []
          count = SpanReplay.for_span(span.span_id).count

          if count.positive?
            actions << { label: pluralize(count, "replay"), icon: "clock-history",
                         variant: :secondary, href: tracing_span_replays_path(span.span_id) }
          end

          actions << { label: "Replay & debug", icon: "arrow-repeat",
                       href: new_tracing_span_replay_path(span.span_id) }
          actions
        rescue StandardError
          []
        end

        # Span replay routes
        def tracing_replays_path(params = {})
          path = "/raaf/tracing/replays"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def tracing_span_replays_path(span_id, params = {})
          span_id_str = span_id.respond_to?(:span_id) ? span_id.span_id : span_id
          path = "/raaf/tracing/spans/#{span_id_str}/replays"
          params.empty? ? path : "#{path}?#{params.to_query}"
        end

        def new_tracing_span_replay_path(span_id)
          span_id_str = span_id.respond_to?(:span_id) ? span_id.span_id : span_id
          "/raaf/tracing/spans/#{span_id_str}/replays/new"
        end

        def tracing_span_replay_path(span_id, replay_id)
          span_id_str = span_id.respond_to?(:span_id) ? span_id.span_id : span_id
          replay_id_str = replay_id.respond_to?(:id) ? replay_id.id : replay_id
          "/raaf/tracing/spans/#{span_id_str}/replays/#{replay_id_str}"
        end

        def render_status_badge(status, skip_reason: nil)
          render SkippedBadgeTooltip.new(status: status, skip_reason: skip_reason, style: :modern)
        end

        # Span kind as a coloured pill. The kind-to-colour mapping lives on the
        # Badge atom so every surface labels a kind identically.
        def render_kind_badge(kind)
          render Ui::Atoms::Badge.for_kind(kind.presence || "unknown")
        end

        # `time_ago_in_words` is localised, so on a Dutch host app it returns
        # "ongeveer 1 maand" and a hardcoded " ago" suffix produces
        # "ongeveer 1 maand ago". The dashboard's chrome is English throughout,
        # so the phrase is built in English rather than half-translated.
        def time_ago(time)
          return "—" unless time

          phrase = I18n.with_locale(:en) { time_ago_in_words(time) }

          # "less than a minute ago" is the one phrase long enough to wrap the
          # Started column onto a second line, and it is also the vaguest.
          return "just now" if phrase.start_with?("less than a minute")

          "#{phrase} ago"
        end

        def format_duration(ms)
          return "N/A" unless ms

          if ms < 1000
            "#{ms.round}ms"
          elsif ms < 60_000
            "#{(ms / 1000.0).round(1)}s"
          else
            minutes = (ms / 60_000).floor
            seconds = ((ms % 60_000) / 1000.0).round(1)
            "#{minutes}m #{seconds}s"
          end
        end

        # ── Scores ────────────────────────────────────────────────────────
        #
        # Every screen that prints a score — the experiment table, a case, a
        # continuous verdict, the feedback list, the trend strip — prints it
        # to two places and colours it against the same two thresholds. Each
        # of them used to carry its own copy with a comment promising it
        # matched the others, and the copies had already drifted: half
        # returned :muted for a missing score and half returned nil.

        def score_text(score)
          return "—" if score.nil?

          # `format` is not Kernel's here — Phlex's element methods take the
          # name, so the operator form is the one that survives.
          "%.2f" % score.to_f
        end

        # :muted for a score that does not exist, so an absent figure reads as
        # absent rather than as a normal one. Components that pass this to a
        # bar rather than to text get nothing, since Bar knows only ok/warn/
        # bad and drops what it does not recognise.
        def score_tone(score)
          return :muted if score.nil?

          case score.to_f
          when GOOD_SCORE.. then :ok
          when POOR_SCORE...GOOD_SCORE then :warn
          else :bad
          end
        end

        # Thousands separated. `number_with_delimiter` is an ActionView helper
        # Phlex does not carry, and a console reporting eighteen thousand
        # verdicts wants the separator.
        def delimited(number)
          number.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        end

        # A count and its noun, the count delimited.
        def counted(count, noun)
          "#{delimited(count)} #{noun.pluralize(count.to_i)}"
        end

        # A trace or span id, as a console prints it.
        #
        # Ids are `trace_` or `span_` and then 32 or 24 random characters. The
        # prefix is on every id in the column and says nothing; the leading
        # eight of what follows identify one in practice, and are what the
        # design prints. Seven components had written some version of this —
        # four called it `short_id` and three `truncate_id`, one of them
        # counting the prefix it never stripped, so a span read four ways
        # depending on the screen.
        def truncate_id(id)
          return "—" if id.blank?

          id.to_s.sub(ID_PREFIX, "").first(8)
        end

        # UTC throughout: the console is read by people in several places and
        # the spans it reads are stamped in UTC.
        def timestamp(time)
          return "—" if time.nil?

          time.utc.strftime("%Y-%m-%d %H:%M:%S UTC")
        end

        # The design's three health tiers, from an error rate in percent.
        #
        # Shared because the Overview's tiles and the Agents table draw the
        # same fleet against the same legend: an agent the Overview colours
        # red must not read as healthy one screen over.
        def health_for(error_rate)
          return :bad if error_rate.to_f > 3
          return :warn if error_rate.to_f > 1

          :ok
        end

        # Colours the old Tailwind palette names used across the dashboard onto
        # the design system's semantic tones.
        METRIC_TONES = {
          "green" => :success,
          "red" => :danger,
          "yellow" => :warning,
          "purple" => :accent,
          "indigo" => :accent,
          "blue" => nil
        }.freeze

        # The screens still calling this predate the design system and pass a
        # Tailwind colour name. They get the console's KPI tile, in the
        # icon-box presentation the tile they used to render always had.
        def render_stat_card(title:, value:, color: "blue", icon: nil, href: nil, note: nil)
          render Ui::Molecules::StatCard.new(
            label: title,
            value: value,
            icon: icon&.to_s&.delete_prefix("bi-"),
            tone: METRIC_TONES[color.to_s],
            layout: :leading,
            note: note,
            href: href
          )
        end

        # Maps the old Preline variant names onto Button's variants. "primary"
        # is the library's default, so it maps to nil.
        BUTTON_VARIANTS = {
          "primary" => nil,
          "success" => nil,
          "secondary" => :secondary,
          "danger" => :danger
        }.freeze

        # Retained under its original name because 33 components call it; the
        # body now renders the Button atom.
        def render_preline_button(text:, href: nil, variant: "primary", size: "sm", icon: nil,
                                  onclick: nil, **attrs)
          # onclick cannot be set directly (Phlex rejects inline handlers); the
          # layout's script wires up anything carrying data-onclick.
          attrs[:data_onclick] = onclick if onclick
          attrs.delete(:onclick)

          render Ui::Atoms::Button.new(
            label: text,
            href: href,
            icon: icon&.to_s&.delete_prefix("bi-"),
            variant: BUTTON_VARIANTS[variant.to_s],
            size: (size.to_s == "lg" ? :lg : :sm),
            **attrs
          )
        end

        # Wraps a table in a flush glass card. Kept for the components that
        # still call it; new code should render Organisms::DataGrid inside an
        # Organisms::Card directly.
        def render_preline_table(&block)
          render(Ui::Organisms::Card.new(flush: true)) do
            div(class: "raaf-table-wrap") { yield if block }
          end
        end
      end
    end
  end
end

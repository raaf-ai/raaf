# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Replay
        ##
        # What a replay produced, beside what the original span produced.
        #
        # Built from the library's detail vocabulary: `RecordHead` for the
        # identity, the metric tiles the dashboard uses for the four figures
        # worth comparing, and a card holding one of three views of the output.
        #
        # **The views are links, not panels.** They were client-side panels
        # driven by a `tabs` Stimulus controller that is not registered, so two
        # of the three could never be opened. A view is a query parameter now,
        # which costs a page load and works.
        #
        # The diff itself stays client-side -- diff2html renders it from the
        # two strings handed to the `diff` controller.
        #
        class ShowComponent < BaseComponent
          VIEWS = [
            { id: "diff", label: "Difference", icon: "file-diff" },
            { id: "config", label: "What changed", icon: "sliders" },
            { id: "sequential", label: "Both outputs", icon: "list-ul" }
          ].freeze

          # @param view [String, nil] which output view to open on
          def initialize(replay:, original_span:, view: nil)
            @replay = replay
            @original_span = original_span
            @replayed_span = replay.replayed_span
            @view = VIEWS.map { |item| item[:id] }.include?(view.to_s) ? view.to_s : "diff"
          end

          def view_template
            div(class: "raaf-page") do
              header

              if @replay.completed? && @replayed_span
                metrics
                output_card
              elsif @replay.failed?
                failure
              else
                waiting
              end
            end
          end

          private

          # ── Header ────────────────────────────────────────────────────────

          def header
            render Organisms::RecordHead.new(
              title: "Replay ##{@replay.id}",
              description: @replay.notes.presence || default_description,
              status: @replay.status,
              meta: header_meta,
              action: { label: "Replay again", icon: "arrow-repeat",
                        href: new_tracing_span_replay_path(@original_span.span_id) },
              stats: @replay.completed? && @replayed_span ? header_stats : []
            )
          end

          def default_description
            "Run from #{@original_span.display_name}, with no note recorded."
          end

          def header_meta
            [@original_span.display_name,
             "started #{time_ago(@replay.created_at)}"].join(" · ")
          end

          def header_stats
            [{ label: "Original", value: format_duration(@original_span.duration_ms) },
             { label: "Replayed", value: format_duration(@replayed_span.duration_ms),
               tone: duration_delta&.positive? ? :bad : :ok }]
          end

          # ── The four figures ──────────────────────────────────────────────

          def metrics
            render Organisms::StatGrid.new(layout: :leading, stats: [
                                             duration_metric,
                                             token_metric("Input tokens", "box-arrow-in-right", :input_tokens),
                                             token_metric("Output tokens", "box-arrow-right", :output_tokens),
                                             cost_metric,
                                             model_metric
                                           ])
          end

          # Cheaper is the good direction here, which is the opposite of every
          # other delta on the screen: a replay that halves the bill is the
          # result the reader was hoping for.
          def cost_metric
            original = cost_of(@original_span).to_f
            replayed = cost_of(@replayed_span).to_f
            delta = percentage_change(original, replayed)

            { label: "Cost", icon: "cash", value: money(replayed),
              tone: if delta.nil? || delta.zero?
                      nil
                    else
                      (delta.positive? ? :warning : :success)
                    end,
              note: comparison_note(money(original), delta) }
          end

          # Four decimals: a single span's bill is routinely under a cent, and
          # two figures would round both sides of the comparison to $0.00.
          def money(amount)
            "$#{'%.4f' % amount.to_f}"
          end

          def duration_metric
            { label: "Duration", icon: "stopwatch",
              value: format_duration(@replayed_span.duration_ms),
              tone: if duration_delta.nil?
                      nil
                    else
                      (duration_delta.positive? ? :danger : :success)
                    end,
              note: comparison_note(format_duration(@original_span.duration_ms), duration_delta) }
          end

          def token_metric(label, icon, key)
            original = usage(@original_span)[key].to_i
            replayed = usage(@replayed_span)[key].to_i
            delta = percentage_change(original, replayed)

            { label: label, icon: icon, value: replayed.to_s,
              tone: if delta.nil? || delta.zero?
                      nil
                    else
                      (delta.positive? ? :warning : :success)
                    end,
              note: comparison_note(original.to_s, delta) }
          end

          # The model is not a number, so it has no delta -- it either changed
          # or it did not, which is the only thing worth saying about it.
          def model_metric
            original = model_of(@original_span)
            replayed = model_of(@replayed_span)

            { label: "Model", icon: "cpu", value: replayed,
              tone: original == replayed ? nil : :accent,
              note: original == replayed ? "unchanged" : "was #{original}" }
          end

          def comparison_note(original, delta)
            return "was #{original}" if delta.nil? || delta.zero?

            "was #{original} · #{'+' if delta.positive?}#{delta.round(1)}%"
          end

          # ── Output ────────────────────────────────────────────────────────

          def output_card
            render(Organisms::Card.new(title: "Output", flush: true)) do |card|
              card.actions { view_tabs }

              div(class: "raaf-card-body") do
                case @view
                when "config" then config_view
                when "sequential" then sequential_view
                else diff_view
                end
              end
            end
          end

          def view_tabs
            render Molecules::Tabs.new(items: VIEWS.map { |item|
              { label: item[:label], icon: item[:icon], active: item[:id] == @view,
                href: view_path(item[:id]) }
            })
          end

          def view_path(id)
            "#{tracing_span_replay_path(@original_span.span_id, @replay.id)}?view=#{id}"
          end

          # ── Difference ────────────────────────────────────────────────────

          def diff_view
            div(data: { controller: "diff",
                        diff_original_value: original_output,
                        diff_replayed_value: replayed_output,
                        diff_output_style_value: "side-by-side" }) do
              div(class: "raaf-diff-toolbar") do
                nav(class: "raaf-tabs", role: "tablist") do
                  diff_style_tab("Side by side", "side-by-side", active: true)
                  diff_style_tab("Unified", "line-by-line", active: false)
                end
              end

              div(class: "raaf-diff-surface", data: { diff_target: "container" }) do
                render Atoms::Text.new("Rendering the difference…", tone: :muted)
              end
            end
          end

          def diff_style_tab(label, style, active:)
            button(type: "button", role: "tab",
                   class: "raaf-tab#{' is-active' if active}",
                   "aria-selected": active ? "true" : "false",
                   data: { action: "click->diff#toggleView", diff_output_style_param: style }) do
              span { label }
            end
          end

          # ── What changed ──────────────────────────────────────────────────

          def config_view
            div(class: "raaf-stack") do
              changed_settings
              changed_prompt if @replay.system_prompt.present?
            end
          end

          def changed_settings
            changes = @replay.configuration_changes || {}

            if changes.empty?
              render Molecules::EmptyState.new(
                icon: "sliders", title: "Nothing was changed",
                text: "The call was run again exactly as it was recorded, which is how you find " \
                      "out whether the agent is deterministic."
              )
            else
              changes.each { |key, value| setting_row(key, value) }
            end
          end

          def setting_row(key, value)
            div(class: "raaf-diff-row") do
              span(class: "raaf-diff-label") { key.to_s.tr("_", " ") }

              div(class: "raaf-diff-values") do
                span(class: "raaf-diff-from") { original_setting(key) }
                render Atoms::Icon.new("arrow-right", size: :sm, class: "raaf-diff-arrow")
                span(class: "raaf-diff-to") { value.to_s }
              end
            end
          end

          def original_setting(key)
            settings = @original_span.span_attributes&.dig("llm", "request") || {}
            settings[key.to_s].to_s.presence || "default"
          end

          def changed_prompt
            render(Molecules::Panel.new(title: "System prompt used", icon: "chat-left-text")) do
              render Atoms::CodeBlock.new(@replay.system_prompt.to_s, height: 320)
            end
          end

          # ── Both outputs ──────────────────────────────────────────────────

          def sequential_view
            div(class: "raaf-stack") do
              output_block("Original", @original_span, "clock-history")
              output_block("Replayed", @replayed_span, "arrow-repeat")
            end
          end

          def output_block(label, span, icon)
            render(Molecules::Panel.new(
                     title: "#{label} · #{started_at(span)}", icon: icon,
                     action: span && "Open in its trace",
                     action_href: span && trace_span_path(span.span_id, span.trace_id),
                     pad: true
                   )) do
              render Atoms::CodeBlock.new(output_of(span).presence || "No output recorded.",
                                          height: 240)
            end
          end

          def started_at(span)
            span&.start_time&.strftime("%Y-%m-%d %H:%M:%S") || "—"
          end

          # ── Not finished ──────────────────────────────────────────────────

          def failure
            render(Molecules::Alert.new(:error, title: "The replay did not finish")) do
              p(class: "raaf-alert-text") do
                @replay.error_message.presence || "It stopped without recording why."
              end

              div(class: "raaf-alert-actions") do
                render Atoms::Button.new(label: "Try again", icon: "arrow-repeat", size: :sm,
                                         variant: :secondary,
                                         href: new_tracing_span_replay_path(@original_span.span_id))
              end
            end
          end

          # The poll controller reloads the page when the replay reaches a
          # final state, so this block only ever has to describe waiting.
          def waiting
            div(id: "replay-status",
                data: { controller: "poll",
                        poll_url_value: tracing_span_replay_path(@original_span.span_id, @replay.id),
                        poll_interval_value: 2000 }) do
              render(Molecules::EmptyState.new(
                       icon: "hourglass-split",
                       title: @replay.running? ? "Running the call" : "Queued",
                       text: "This page updates itself when the replay finishes."
                     ))
            end
          end

          # ── Reading the two spans ─────────────────────────────────────────

          def duration_delta
            return @duration_delta if defined?(@duration_delta)

            @duration_delta = @replay.duration_comparison&.dig(:percentage_change)
          end

          def percentage_change(original, replayed)
            return nil if original.zero?

            ((replayed - original).to_f / original * 100).round(1)
          end

          # Through SpanUsage, which is how the rest of the console reads a
          # span's tokens: it knows the flat `llm.usage.*` keys, the `usage`
          # object and the native columns migration 006 filled. Reading the
          # nested `llm.usage` hash alone missed a DSL agent span entirely —
          # it records its counts elsewhere — so both token tiles read 0 with
          # a note of "was 0" on exactly the replays most worth running.
          #
          # The nested shape stays as a fallback rather than being swapped
          # out: SpanUsage does not read it, and dropping it here would fix
          # one span kind by breaking another.
          def usage(span)
            return { input_tokens: nil, output_tokens: nil } unless span

            recorded = ::RAAF::Tracing::SpanUsage.for_span(span)
            nested = nested_usage(span)

            { input_tokens: recorded[:input] || nested[:input_tokens],
              output_tokens: recorded[:output] || nested[:output_tokens] }
          end

          def nested_usage(span)
            recorded = (span.span_attributes || {}).dig("llm", "usage") || {}

            { input_tokens: recorded["input_tokens"] || recorded["prompt_tokens"],
              output_tokens: recorded["output_tokens"] || recorded["completion_tokens"] }
          end

          # What the two spans were billed.
          #
          # Whether the cheaper model was in fact cheaper is usually the reason
          # the replay was run, and the comparison reported duration, tokens
          # and model without ever saying so. Both spans are already in hand.
          def cost_of(span)
            return nil unless span

            ::RAAF::Tracing::SpanUsage.spend_for_span(span)
          end

          def model_of(span)
            attrs = span&.span_attributes || {}

            (attrs.dig("llm", "request", "model") ||
              attrs["llm.request.model"] ||
              attrs["agent.model"] ||
              attrs["model"]).to_s.presence || "unknown"
          end

          def original_output
            @original_output ||= output_of(@original_span)
          end

          def replayed_output
            @replayed_output ||= output_of(@replayed_span)
          end

          # An answer has been written under a different key in every
          # generation of the tracer, so all of them are tried before
          # concluding a span said nothing.
          OUTPUT_KEYS = [
            %w[agent.final_agent_response],
            %w[final_agent_response],
            %w[response.content],
            %w[llm.response.content],
            %w[llm response content],
            %w[llm response choices 0 message content],
            %w[agent final_agent_response]
          ].freeze

          def output_of(span)
            return "" unless span

            attrs = span.span_attributes || {}
            found = OUTPUT_KEYS.lazy.filter_map { |path| dig_path(attrs, path) }.first

            pretty(found)
          end

          def dig_path(attrs, path)
            path.reduce(attrs) do |value, key|
              step = key.match?(/\A\d+\z/) ? key.to_i : key
              break nil unless value.respond_to?(:dig)

              value.dig(step)
            end
          rescue TypeError
            nil
          end

          # Both sides are pretty-printed so the diff compares structure rather
          # than whitespace: the same object serialised two ways would
          # otherwise read as a wholesale rewrite.
          def pretty(content)
            return "" if content.blank?
            return JSON.pretty_generate(content) if content.is_a?(Hash) || content.is_a?(Array)

            text = content.to_s.strip
                          .sub(/\A```(?:json)?\s*\n?/, "")
                          .sub(/\n?\s*```\z/, "")

            JSON.pretty_generate(JSON.parse(text))
          rescue JSON::ParserError
            text
          end
        end
      end
    end
  end
end

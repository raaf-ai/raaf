# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Replay
        ##
        # The Replays screen -- every replay, or one span's.
        #
        # No canvas draws it, so it is built from the library the designed list
        # screens use: `DataGrid` for the table, the same status pill the trace
        # and span lists carry, and `RecordHead` when the list belongs to one
        # span, which is the shape every other record-scoped screen has.
        #
        # The two modes differ by one column. The console's list has to say
        # which span each replay came from; a span's own list already knows,
        # and would print the same value on every row.
        #
        class IndexComponent < BaseComponent
          # @param span [SpanRecord, nil] nil lists every replay
          # @param replays [Enumerable<SpanReplay>]
          def initialize(span: nil, replays: [])
            @span = span
            @replays = replays
          end

          def view_template
            div(class: "raaf-page") do
              @span ? span_header : console_intro
              table
            end
          end

          private

          # ── Header ────────────────────────────────────────────────────────

          def span_header
            render Organisms::RecordHead.new(
              title: @span.display_name,
              mono: true,
              description: "Every replay run from this span, newest first.",
              meta: [@span.kind.to_s, format_duration(@span.duration_ms)].join(" · "),
              status: @span.status,
              action: new_replay_action,
              stats: header_stats
            )
          end

          def new_replay_action
            return nil unless SpanReplay.replayable?(@span)

            { label: "New replay", icon: "arrow-repeat",
              href: new_tracing_span_replay_path(@span.span_id) }
          end

          def header_stats
            [{ label: "Replays", value: count.to_s },
             { label: "Completed", value: count_of("completed").to_s },
             { label: "Failed", value: count_of("failed").to_s }]
          end

          # The console's list needs no header -- the shell's topbar already
          # carries the title -- but it does need to say what it is looking at,
          # because "Replays" alone does not distinguish a replay from a run.
          def console_intro
            render Molecules::Alert.new(
              :info,
              title: "Every replay across every span",
              text: "A replay re-runs one recorded LLM call with the model settings or prompts " \
                    "changed, and keeps the result beside the original. Start one from a span's " \
                    "own page."
            )
          end

          # ── Table ─────────────────────────────────────────────────────────

          def table
            render(Molecules::Panel.new(title: "Replays", icon: "arrow-repeat")) do
              render(Organisms::DataGrid.new(columns: columns, empty: empty_state)) do |grid|
                @replays.each { |replay| row(grid, replay) }
              end
            end
          end

          def columns
            base = [{ label: "Replay", span: 1.2 }]
            base << { label: "Span", span: 1.6 } unless @span
            base + [{ label: "Status", span: 0.9 },
                    { label: "Changed", span: 1.8 },
                    { label: "Duration", span: 0.8, align: :right },
                    { label: "Change", span: 0.7, align: :right },
                    { label: "Started", span: 0.9, align: :right }]
          end

          def row(grid, replay)
            cells = [{ value: title_for(replay), primary: true }]
            cells << { value: Atoms::Mono.new(span_name(replay), tone: :muted), muted: true } unless @span
            cells += [
              { value: Atoms::StatusBadge.new(replay.status) },
              { value: Molecules::TagList.new(changed_in(replay), limit: 3) },
              { value: Atoms::Mono.new(replayed_duration(replay)), align: :right },
              { value: delta_mono(replay), align: :right },
              { value: Atoms::Mono.new(time_ago(replay.created_at), tone: :muted), align: :right }
            ]

            grid.row(href: tracing_span_replay_path(replay.original_span_id, replay.id), cells: cells)
          end

          def empty_state
            if @span
              { icon: "arrow-repeat", title: "No replays of this span yet",
                text: "Change the model, the settings or the prompt and run it again to see what " \
                      "the difference does." }
            else
              { icon: "arrow-repeat", title: "Nothing replayed yet",
                text: "Open a span, press Replay & debug, and the run will be listed here." }
            end
          end

          # ── Cells ─────────────────────────────────────────────────────────

          # A replay's own note is what tells one attempt from another; the id
          # is the fallback, and stays as the prefix so a note never hides
          # which row is which.
          def title_for(replay)
            return "##{replay.id}" if replay.notes.blank?

            "##{replay.id} · #{truncate(replay.notes, length: 60)}"
          end

          def span_name(replay)
            replay.original_span&.display_name || replay.original_span_id
          end

          # What the replay was asked to change, named the way the form names
          # it. An empty list means the same call was run again unchanged --
          # which is a legitimate thing to do, so it says so rather than
          # leaving the cell blank.
          def changed_in(replay)
            names = (replay.configuration_changes || {}).keys.map { |key| key.to_s.tr("_", " ") }
            names << "system prompt" if replay.system_prompt.present?
            names << "messages" if replay.user_messages.present?

            names.presence || ["nothing"]
          end

          def replayed_duration(replay)
            return "—" unless replay.replayed_span

            format_duration(replay.replayed_span.duration_ms)
          end

          # Slower is bad, faster is good, and a replay that has not finished
          # has no number at all.
          def delta_mono(replay)
            delta = replay.completed? ? replay.duration_comparison&.dig(:percentage_change) : nil
            return Atoms::Mono.new("—", tone: :muted) if delta.nil?

            Atoms::Mono.new(format_delta(delta), tone: delta.positive? ? :bad : :ok)
          end

          def format_delta(delta)
            "#{'+' if delta.positive?}#{delta.round(1)}%"
          end

          # ── Counts ────────────────────────────────────────────────────────

          def count
            @count ||= @replays.size
          end

          def count_of(status)
            @replays.count { |replay| replay.status == status }
          end
        end
      end
    end
  end
end

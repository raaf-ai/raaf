# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      ##
      # StyleGuide — every component in the library, on one page.
      #
      # Kept in the engine rather than in a static file so it always reflects
      # the components as they actually render. When a component changes, this
      # page changes with it, which is what makes it useful as a review surface.
      #
      class StyleGuide < Base
        def view_template
          render(Organisms::HeroHeader.new(
                   eyebrow: "Glass Morph",
                   title: "Component library",
                   subtitle: "Atoms, molecules and organisms as the dashboard renders them"
                 ))

          buttons
          badges
          text_and_code
          form_controls
          feedback
          navigation
          kpi_tiles
          data_display
          charts
          tracing
        end

        SAMPLE_TRACES = [
          { workflow: "research_pipeline", spans: 42, status: "ok", duration: "2.4s" },
          { workflow: "support_triage", spans: 18, status: "error", duration: "0.9s" },
          { workflow: "content_writer", spans: 7, status: "running", duration: "—" }
        ].freeze

        SAMPLE_SPANS = [
          { name: "Research Agent", kind: "agent", duration: "1,204ms", status: "ok" },
          { name: "web_search", kind: "tool", duration: "812ms", status: "ok" },
          { name: "gpt-4o completion", kind: "llm", duration: "392ms", status: "error" }
        ].freeze

        WATERFALL_SPANS = [
          { kind: "pipeline", name: "Discovery::Pipeline", start_ms: 0, duration_ms: 11_400,
            duration: "11.4s", level: 0, id: "a" },
          { kind: "agent", name: "Company::EnrichAgent#run", start_ms: 1_400, duration_ms: 9_600,
            duration: "9.6s", tokens: "8.1k", level: 1, id: "b" },
          { kind: "tool", name: "web_search", start_ms: 1_600, duration_ms: 2_400,
            duration: "2.4s", level: 2, id: "c" },
          { kind: "tool", name: "crm_upsert", start_ms: 7_100, duration_ms: 4_002,
            duration: "4.0s", level: 2, tone: :bad, id: "d" },
          { kind: "handoff", name: "→ Prospect::ScoringAgent", start_ms: 11_300, duration_ms: 100,
            duration: "—", level: 1, tone: :idle, id: "e" }
        ].freeze

        # Nine hours of a queue, one bar each, so the hover readouts on this
        # page are the real thing rather than a description of one.
        CHART_SERIES = [
          { at: "09:00", runs: 180, failed: 0 },
          { at: "10:00", runs: 240, failed: 0 },
          { at: "11:00", runs: 120, failed: 0 },
          { at: "12:00", runs: 60, failed: 4 },
          { at: "13:00", runs: 310, failed: 0 },
          { at: "14:00", runs: 290, failed: 0 },
          { at: "15:00", runs: 2, failed: 2 },
          { at: "16:00", runs: 260, failed: 0 },
          { at: "17:00", runs: 340, failed: 0 }
        ].freeze

        CHART_METERS = [
          { name: "gpt-4o", value: "$182.40", pct: 100, sub: "4.1M tokens",
            tip: "gpt-4o · $182.40 · 68% of the bill · 4.1M tokens" },
          { name: "gpt-4o-mini", value: "$61.80", pct: 34, sub: "9.7M tokens",
            tip: "gpt-4o-mini · $61.80 · 23% of the bill · 9.7M tokens" },
          { name: "claude-sonnet-4", value: "$24.10", pct: 13, sub: "1.2M tokens",
            tip: "claude-sonnet-4 · $24.10 · 9% of the bill · 1.2M tokens" }
        ].freeze

        PATH_NODES = [
          { kind: "pipeline", name: "Discovery::Pipeline", note: "6 steps",
            duration: "11.4s", level: 0, tone: :bad },
          { kind: "tool", name: "web_search", note: "12 results", duration: "2.4s", level: 2 },
          { kind: "tool", name: "crm_upsert", note: "timeout · 2 retries",
            duration: "4.0s", level: 2, tone: :bad },
          { kind: "handoff", name: "→ Prospect::ScoringAgent", note: "not reached",
            duration: "—", level: 1, tone: :idle }
        ].freeze

        private

        def section(title, meta = nil, &block)
          render Molecules::SectionHeader.new(title: title, meta: meta)
          div(class: "raaf-style-guide-row", &block)
        end

        def buttons
          section("Buttons", "atoms/button.css") do
            render Atoms::Button.new(label: "Primary")
            render Atoms::Button.new(label: "Secondary", variant: :secondary)
            render Atoms::Button.new(label: "Danger", variant: :danger)
            render Atoms::Button.new(label: "Light", variant: :light)
            render Atoms::Button.new(label: "Small", size: :sm, icon: "download")
            render Atoms::Button.new(label: "Large", size: :lg)
            render Atoms::Button.new(label: "Disabled", disabled: true)
            render Atoms::Button.new(variant: :icon, icon: "three-dots")
          end
        end

        def badges
          section("Badges", "atoms/badge.css") do
            %i[slate teal green amber red blue glass].each do |variant|
              render Atoms::Badge.new(variant.to_s.capitalize, variant: variant)
            end
          end

          div(class: "raaf-style-guide-row") do
            %w[ok running pending error timeout].each do |status|
              render Atoms::Badge.for_status(status)
            end
            %w[agent llm tool handoff guardrail].each do |kind|
              render Atoms::Badge.for_kind(kind)
            end
          end

          div(class: "raaf-style-guide-row") do
            render Atoms::BadgePill.new("Last 24 hours", icon: "clock")
            render Atoms::StepBadge.new(1, state: :completed)
            render Atoms::StepBadge.new(2, state: :active)
            render Atoms::StepBadge.new(3)
            render Atoms::Avatar.new("Research Agent", size: :md)
          end
        end

        def text_and_code
          section("Type", "atoms/text.css") do
            div do
              render Atoms::Eyebrow.new("Eyebrow")
              render Atoms::Text.new("Heading 4", as: :h2, size: :h4, weight: :bold)
              render Atoms::Text.new("Body copy sits at 14px on the secondary tone.", tone: :secondary)
              render Atoms::Text.new("Muted caption, 12px.", size: :sm, tone: :muted)
              render Atoms::Text.new("span_a1b2c3 · 1,204ms", size: :body_sm, mono: true)
            end
          end

          div(class: "raaf-style-guide-row") do
            render Atoms::Code.new("gpt-4o-2024-08-06")
          end

          render Atoms::CodeBlock.new({ "model" => "gpt-4o", "usage" => { "input_tokens" => 1204,
                                                                          "output_tokens" => 318 } })
        end

        def form_controls
          section("Form controls", "atoms/input.css · molecules/field.css") do
            div(class: "raaf-field-grid") do
              render(Molecules::Field.new(label: "Workflow name", hint: "Exact match")) do
                render Atoms::Input.new(name: "workflow", placeholder: "research_pipeline")
              end

              render(Molecules::Field.new(label: "Span kind", optional: true)) do
                render Atoms::Select.new(name: "kind", include_blank: "All kinds",
                                         options: [%w[Agent agent], %w[LLM llm], %w[Tool tool]])
              end

              render(Molecules::Field.new(label: "Sample rate", error: "Must be between 1 and 100")) do
                render Atoms::Input.new(name: "rate", type: "number", value: 250, invalid: true)
              end
            end
          end

          div(class: "raaf-style-guide-row") do
            render Atoms::Toggle.new(name: "active", checked: true, label: "Evaluate new spans")
            render Atoms::Toggle.new(name: "paused", label: "Pause on error")
          end
        end

        def feedback
          section("Feedback", "molecules/alert.css") do
            div(class: "raaf-style-guide-stack") do
              render Molecules::Alert.new(:success, title: "Replay finished",
                                                    text: "42 spans re-executed with no regressions.")
              render Molecules::Alert.new(:info, title: "Sampling active",
                                                 text: "10% of production spans are evaluated.")
              render Molecules::Alert.new(:warning, title: "Queue backlog",
                                                    text: "412 evaluations are waiting for a worker.")
              render Molecules::Alert.new(:error, title: "Provider error",
                                                  text: "Anthropic returned 529 for 3 consecutive calls.")
            end
          end

          div(class: "raaf-style-guide-row") do
            render Atoms::Spinner.new
            render Atoms::Spinner.new(size: :md)
            render Atoms::ProgressBar.new(value: 72, label: "Completion")
          end
        end

        def navigation
          section("Navigation", "molecules/tabs.css · molecules/nav_item.css") do
            div(class: "raaf-style-guide-stack") do
              render Molecules::Tabs.new(items: [
                                           { label: "Traces", href: "#", active: true },
                                           { label: "Spans", href: "#" },
                                           { label: "Flows", href: "#" }
                                         ])

              render Molecules::Tabs.new(variant: :underline, items: [
                                           { label: "Overview", href: "#", active: true },
                                           { label: "Payload", href: "#", count: 12 },
                                           { label: "Timeline", href: "#" }
                                         ])

              render Molecules::Breadcrumb.new(items: [
                                                 { label: "Traces", href: "#" },
                                                 { label: "research_pipeline", href: "#" },
                                                 { label: "span_a1b2c3" }
                                               ])

              render Molecules::Pagination.new(page: 4, total_pages: 42, total_count: 1_037,
                                               per_page: 25, href: ->(n) { "?page=#{n}" })
            end
          end
        end

        # One tile, two icon placements. They are here side by side because the
        # console used to have a separate component for each, and a reader met
        # a different KPI row every second screen with no change of subject to
        # justify it. The delta, the note and the sparkline belong to both.
        def kpi_tiles
          render Molecules::SectionHeader.new(
            title: "KPI tiles",
            meta: "molecules/stat_card.css · icon top right and icon box left"
          )

          render Organisms::StatGrid.new(stats: kpi_stats)
          render Organisms::StatGrid.new(
            stats: kpi_stats.map { |tile| tile.merge(layout: :leading) }
          )
        end

        # The four tones the tile speaks, one per card, and the sparkline on the
        # one that has something to say about a trend.
        def kpi_stats
          [
            { label: "Runs", value: "12,480", delta: "+8.2%", tone: :accent,
              note: "hover a bar for the hour it covers", icon: "diagram-3",
              series: CHART_SERIES.pluck(:runs),
              series_tips: CHART_SERIES.map { |bucket| chart_tip(bucket) } },
            { label: "Success rate", value: "98.2%", delta: "+0.4pt", tone: :success,
              note: "12,256 of 12,480 runs", icon: "check-circle" },
            { label: "Avg duration", value: "2.4s", delta: "+310ms", tone: :warning,
              note: "p95 is 7.1s", icon: "hourglass-split" },
            { label: "Failure rate", value: "1.8%", delta: "+0.6pt", tone: :danger,
              note: "225 failed · 23 error signatures", icon: "exclamation-octagon" }
          ]
        end

        def data_display
          render Molecules::SectionHeader.new(title: "Data display",
                                              meta: "organisms/data_table.css · data_row.css")

          render Organisms::HeroStats.new(
            title: "Tracing overview",
            subtitle: "1,204 spans across 87 traces in the last 24 hours",
            stats: [
              { value: 87, label: "Traces" },
              { value: "1,204", label: "Spans" },
              { value: "2.4s", label: "P95 duration", tone: :accent },
              { value: 17, label: "Errors", tone: :danger },
              { value: "$4.12", label: "Cost", delta: "+8%", direction: :up }
            ]
          )

          render Organisms::MetricGrid.new(metrics: [
                                             { label: "Traces", value: 87, icon: "diagram-3" },
                                             { label: "Spans", value: "1,204", icon: "list-nested" },
                                             { label: "Errors", value: 17, icon: "x-octagon",
                                               tone: :danger, hint: "1.4% of spans" },
                                             { label: "Cost", value: "$4.12", icon: "cash-coin",
                                               tone: :accent }
                                           ])

          render(Organisms::Card.new(title: "Traces", subtitle: "newest first", flush: true)) do |card|
            card.actions { render Atoms::Button.new(label: "Export", size: :sm, icon: "download") }
            sample_table
          end

          render(Organisms::Card.new(title: "Spans", flush: true)) { sample_rows }

          render(Organisms::Card.new(title: "Attributes")) do
            render Molecules::KeyValueList.new(layout: :rows, pairs: {
                                                 "Trace ID" => "trace_9f21c4",
                                                 "Model" => "gpt-4o",
                                                 "Duration" => "1,204ms",
                                                 "Parent span" => nil
                                               }, mono: true)
          end

          render(Organisms::Card.new) do
            render Molecules::EmptyState.new(
              icon: "inbox", title: "No spans recorded yet",
              text: "Runs appear here as soon as an agent is traced."
            ) { render Atoms::Button.new(label: "Read the setup guide", variant: :secondary) }
          end
        end

        # Every graph on the console is one of these two marks. Both carry a
        # readout on the mark itself, because a bar's height is a comparison
        # and comparisons do not say which hour, or a share of what.
        def charts
          section("Charts", "molecules/metric_triple.css · molecules/tooltip.css") do
            render Molecules::StatCard.new(
              label: "Runs", value: "1,802", delta: "+8.2%", tone: :bad,
              note: "hover a bar for the hour it covers", icon: "diagram-3",
              series: CHART_SERIES.map { |b| b[:runs] },
              series_tips: CHART_SERIES.map { |b| chart_tip(b) }
            )
          end

          render(Organisms::Card.new(title: "By model", subtitle: "hover a bar for its share",
                                     flush: true)) do
            CHART_METERS.each { |row| render Molecules::MeterRow.new(**row) }
          end
        end

        def chart_tip(bucket)
          [bucket[:at],
           "#{bucket[:runs]} runs",
           bucket[:failed].positive? ? "#{bucket[:failed]} failed" : nil].compact.join(" · ")
        end

        def sample_table
          render(Organisms::DataGrid.new(columns: [
                                           { label: "Workflow", span: 3 },
                                           { label: "Spans", span: 1, align: :right },
                                           { label: "Duration", span: 1, align: :right },
                                           { label: "Status", span: 1 }
                                         ])) do |grid|
            SAMPLE_TRACES.each do |trace|
              grid.row(href: "#", cells: [
                         { value: trace[:workflow], primary: true },
                         { value: Atoms::Mono.new(trace[:spans]), align: :right },
                         { value: Atoms::Mono.new(trace[:duration], tone: :muted), align: :right },
                         { value: Atoms::StatusBadge.new(trace[:status]) }
                       ])
            end
          end
        end

        def sample_rows
          render Organisms::LiveRunsPanel.new(traces: SAMPLE_SPANS.map do |span|
            { workflow: span[:name], spans: span[:kind], duration: span[:duration],
              tone: (span[:status] == "error" ? :bad : :ok), href: "#" }
          end)
        end

        # ── Tracing ───────────────────────────────────────────────────────
        #
        # The pieces the Tracing screens are built from. They are here because
        # they are the hardest ones to review in place: a redaction veil or a
        # failing topology needs the right span in the database to show up at
        # all, and this page needs none.

        def tracing
          section("Span waterfall", "molecules/waterfall.css") do
            render(Organisms::Card.new(flush: true, class: "raaf-style-guide-wide")) do
              render Organisms::SpanWaterfall.new(spans: WATERFALL_SPANS, total_ms: 11_400,
                                                  selected: "d")
            end
          end

          tracing_path
          tracing_payload
          tracing_results
          tracing_pipeline
          tracing_tools
        end

        def tracing_path
          section("Trace path", "molecules/path_node.css") do
            render(Organisms::Card.new(class: "raaf-style-guide-wide")) do
              render Organisms::TracePath.new(nodes: PATH_NODES)
            end
          end
        end

        def tracing_payload
          section("Payload and error", "molecules/payload.css") do
            render(Organisms::Card.new(class: "raaf-style-guide-wide")) do
              render Molecules::PayloadBlock.new(
                role: "system", tokens: "112 tok", tone: :pipeline,
                body: "You enrich a company record with firmographic data."
              )
              render Molecules::PayloadBlock.new(
                role: "tool arguments", tokens: "86 tok", tone: :tool, masked: true,
                id: "raaf-style-guide-reveal",
                body: %({\n  "company": "Vandelay Industries BV",\n  "crm_id": "0035g00000ABCDe"\n})
              )
              render Molecules::ErrorCallout.new(
                klass: "Faraday::TimeoutError",
                message: "execution expired — POST /v2/companies/upsert exceeded the 4000ms timeout.",
                backtrace: "raaf-tools/lib/raaf/tools/crm_upsert.rb:48 in `call'\n" \
                           "raaf-core/lib/raaf/runner.rb:214 in `run_turn'"
              )
            end
          end
        end

        SAMPLE_RESULTS = [
          { title: "Vandelay Industries acquires Kruger Latex",
            url: "https://example.com/news/vandelay-kruger",
            snippet: "The acquisition adds 140 staff and a second Rotterdam site.",
            score: 0.8213 },
          { title: "Vandelay Industries BV — company profile",
            url: "https://example.com/companies/vandelay",
            snippet: "Importer and exporter of latex goods, founded 1989.",
            score: 0.6041 },
          { title: nil, url: "https://example.com/filings/2024-vandelay.pdf" }
        ].freeze

        def tracing_results
          section("Search results", "molecules/result_list.css") do
            render(Organisms::Card.new(class: "raaf-style-guide-wide")) do
              render Molecules::ResultList.new(items: SAMPLE_RESULTS)
            end
          end
        end

        def tracing_pipeline
          section("Pipeline heat", "molecules/metric_triple.css") do
            render(Organisms::Card.new(class: "raaf-style-guide-wide")) do
              render Organisms::PipelineSteps.new(steps: [
                                                    { kind: "agent", name: "Search::TermBuilder", pct: 11,
                                                      duration: "1.2s", error_rate: 0.1 },
                                                    { kind: "tool", name: "crm_upsert", pct: 33,
                                                      duration: "4.0s", error_rate: 8.1, tone: :bad }
                                                  ])
            end
          end
        end

        def tracing_tools
          section("Tool registry", "organisms/tool_registry.css") do
            render Organisms::ToolRegistry.new(class: "raaf-style-guide-wide", tools: [
                                                 { name: "web_search", icon: "globe2", tag: "read",
                                                   description: "Search with a domain allow-list and an 8s budget.",
                                                   calls: "21.4k", error_rate: "0.3%", error_tone: :ok, p95: "2.4s" },
                                                 { name: "crm_upsert", icon: "database-add", tag: "write", tone: :warn,
                                                   description: "Upserts enriched company records into the CRM.",
                                                   calls: "8.1k", error_rate: "8.1%", error_tone: :bad, p95: "4.0s" },
                                                 { name: "pii_scrub", icon: "shield-check", tag: "guard", tone: :info,
                                                   description: "Strips emails and phone numbers before persistence.",
                                                   calls: "12.5k", error_rate: "0.0%", error_tone: :ok, p95: "0.01s" }
                                               ])
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # BaseLayout — the document every dashboard page is rendered into.
      #
      # The shell is Shell.dc.html from the RAAF Console design: a 238px
      # sidebar of collapsible nav groups beside a sticky header carrying the
      # breadcrumb, title, time range, live toggle and search.
      #
      # Navigation is declared once here as NAV_GROUPS. Every item routes: a
      # nav that offers a screen the engine does not have sends the reader
      # nowhere, and the one item that did — Chat, rendered as a "soon"
      # placeholder — outlived the stub pages it stood for. Replays moved into
      # Tracing when its group emptied, which is where a replay is found from
      # anyway.
      #
      class BaseLayout < BaseComponent
        # Which nav item is current is read off the request path. The adapter
        # is what phlex-rails offers in place of reaching for the view context
        # directly; `helpers` is the same thing with a deprecation on it.
        include Phlex::Rails::Helpers::Request

        # @param range_href [#call, nil] receives a range, returns its URL.
        #   Without it the header leaves the time range out entirely, which is
        #   how a screen that does not filter by time opts out.
        # Front-end libraries a page can ask for by name.
        #
        # The head used to load all of them on every screen, so the Overview
        # paid for a megabyte of diff renderer it never called and the policy
        # list paid for a syntax highlighter with nothing to highlight. None of
        # the tags carried +defer+, so all of it blocked the first paint.
        # Measured against the CDNs on 2026-09-07: diff2html-ui 1,024 kB, its
        # stylesheet 17 kB, jsdiff 17 kB, highlight.js 122 kB and its JSON
        # grammar 0.5 kB — 1.18 MB that most of the console has no use for.
        #
        # A page names what it needs and pays for nothing else. The Stimulus
        # controllers that drive these libraries stay registered everywhere:
        # they are defined inline, cost nothing until an element asks for one,
        # and only a page that asked for the bundle carries such an element.
        #
        # No page asks for +:syntax+ on its own. It exists because +:diff+
        # depends on it: the base diff2html build takes the highlighter as a
        # constructor argument rather than carrying one. The screens that used
        # to ask for it directly printed a highlighted payload from the old
        # per-kind span components, and those are gone —
        # +Ui::Organisms::SpanInspector+ renders a bare +pre+ instead.
        BUNDLES = %i[diff syntax].freeze

        # Bundles that pull in other bundles.
        #
        # diff2html ships three builds and they differ only in how much
        # highlighter they carry: the full one 1,024 kB, the slim one 291 kB,
        # the base one 92 kB. The base build takes an +hljs+ implementation as
        # its fourth constructor argument and +highlightCode+ throws without
        # one, so the console loads that and its own highlight.js rather than
        # a second copy welded into a megabyte bundle — 1,024 kB against the
        # 215 kB this pair costs, for the same diff.
        BUNDLE_DEPENDENCIES = { diff: %i[syntax] }.freeze

        # How long a live screen waits before reloading itself.
        REFRESH_INTERVAL_MS = 30_000

        # @param bundles [Array<Symbol>] any of {BUNDLES}; anything else is
        #   ignored rather than raised on, so a typo in a caller costs the page
        #   its highlighting instead of a 500.
        def initialize(title: "Overview", crumb: nil, current: nil, range: "24h",
                       range_href: nil, live: true, breadcrumb: nil, bundles: [])
          @title = title
          @crumb = crumb
          @current = current
          @range = range
          @range_href = range_href
          @live = live
          @breadcrumb = breadcrumb
          requested = Array(bundles).map(&:to_sym) & BUNDLES
          @bundles = requested.flat_map { |name| [ name, *BUNDLE_DEPENDENCIES[name] ] }.uniq
        end

        def view_template(&block)
          doctype
          html(lang: "en") do
            head { render_head }

            body(class: "raaf-root", data: body_data) do
              render(shell) { yield if block }
              render_scripts
            end
          end
        end

        private

        # The controllers on the document, and what the refresh one is to do.
        #
        # +enabled+ is what makes the header's Live / Paused control mean
        # something. Without it the controller took its own default of true and
        # every screen reloaded on the interval regardless, so a page asking for
        # +live: false+ printed "Paused" while reloading behind the badge — and
        # the forms under it threw away half-typed input every 30 seconds.
        #
        # A paused page still carries the controller and the interval, so the
        # reader can turn tailing on from the badge; it just does not start one.
        def body_data
          { controller: "auto-refresh tooltip",
            auto_refresh_interval_value: REFRESH_INTERVAL_MS,
            auto_refresh_enabled_value: @live }
        end

        def render_head
          meta(charset: "utf-8")
          meta(name: "viewport", content: "width=device-width, initial-scale=1")
          title { "RAAF Console — #{@title}" }

          link(rel: "preconnect", href: "https://fonts.googleapis.com")
          link(rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: "anonymous")
          link(rel: "stylesheet",
               href: "https://fonts.googleapis.com/css2?family=Figtree:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap")
          link(rel: "stylesheet",
               href: "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css")

          if bundle?(:diff)
            link(rel: "stylesheet",
                 href: "https://cdn.jsdelivr.net/npm/diff2html@3.4.52/bundles/css/diff2html.min.css")
          end

          # MIGRATION SCAFFOLDING — remove once every page component has been
          # converted to the UI library. Pages still carrying Tailwind utility
          # classes depend on this; converted pages do not touch it.
          script(src: "https://cdn.tailwindcss.com")

          # Linked rather than inlined: 156 kB of CSS in every document, on
          # every navigation, that the browser could never keep. The path
          # carries the stylesheet's content hash, so this is fetched once and
          # re-fetched exactly when the CSS changes.
          link(rel: "stylesheet", href: console_stylesheet_path(Ui::Stylesheet.digest))

          csrf_meta_tags
          csp_meta_tag
        end

        # @param name [Symbol]
        # @return [Boolean] whether this page asked for that bundle
        def bundle?(name)
          @bundles.include?(name)
        end

        # jsdiff and diff2html, for the replay comparison view.
        #
        # The base diff2html build, which expects the highlighter to be handed
        # to it — +:diff+ brings +:syntax+ along for exactly that, and
        # +DiffController+ passes +window.hljs+ when it constructs the UI.
        # Its stylesheet is linked from the head; these go at the end of the
        # body, where they no longer hold up the first paint. The controller
        # polls for both globals, so arriving late costs it one 50 ms tick.
        def render_diff_bundle
          script(src: "https://cdn.jsdelivr.net/npm/diff@5.2.0/dist/diff.min.js")
          script(src: "https://cdn.jsdelivr.net/npm/diff2html@3.4.52/bundles/js/diff2html-ui-base.min.js")
        end

        # highlight.js and its JSON grammar, for the diff.
        #
        # Nothing is highlighted on load. +hljs.highlightAll+ matches
        # +pre code+, and the screens that rendered that pair — the per-kind
        # span components — are gone; +DiffController+ handing +window.hljs+ to
        # diff2html is the only reader left.
        #
        # No stylesheet comes with it: +molecules/syntax.css+ themes the
        # +.hljs-*+ classes for the console's own dark surface, scoped under
        # +.raaf-root+, so the CDN's default theme was loaded only to be
        # overridden by the inline stylesheet that follows it.
        def render_syntax_bundle
          script(src: "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js")
          script(src: "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/json.min.js")
        end

        def shell
          Ui::Organisms::PageShell.new(
            sidebar: sidebar,
            title: @title,
            crumb: @crumb || crumb_from_nav,
            range: @range,
            range_href: @range_href,
            live: @live,
            search_href: tracing_search_path
          )
        end

        def sidebar
          Ui::Organisms::Sidebar.new(
            groups: nav_groups,
            current: @current || current_from_path,
            brand: "RAAF",
            subtitle: "Console",
            brand_href: dashboard_path,
            meta: "raaf-rails #{RAAF::Rails::VERSION} · #{::Rails.env}"
          )
        end

        # The console's navigation, straight from the design. Items without an
        # href are screens the engine does not route yet.
        def nav_groups
          [
            { id: :monitor, label: "Monitor", items: [
              { key: :overview, label: "Overview", icon: "grid-1x2", href: dashboard_path },
              { key: :agents, label: "Agents", icon: "cpu", href: dashboard_agents_path },
              { key: :performance, label: "Performance", icon: "speedometer2",
                href: dashboard_performance_path },
              { key: :errors, label: "Errors", icon: "exclamation-triangle", href: dashboard_errors_path },
              { key: :costs, label: "Cost & usage", icon: "cash-stack", href: dashboard_costs_path }
            ] },
            { id: :tracing, label: "Tracing", items: [
              { key: :traces, label: "Traces", icon: "diagram-3", href: tracing_traces_path },
              { key: :spans, label: "Spans", icon: "layers", href: tracing_spans_path },
              { key: :search, label: "Search", icon: "search", href: tracing_search_path },
              { key: :flows, label: "Flows", icon: "share", href: flows_tracing_spans_path },
              { key: :tools, label: "Tools", icon: "tools", href: tools_tracing_spans_path },
              { key: :replays, label: "Replays", icon: "arrow-repeat", href: tracing_replays_path }
            ] },
            { id: :evaluate, label: "Evaluate", items: [
              { key: :datasets, label: "Datasets", icon: "collection", href: eval_datasets_path },
              { key: :experiments, label: "Experiments", icon: "eyedropper", href: eval_experiments_path },
              { key: :prompts, label: "Prompts", icon: "file-text", href: eval_prompts_path },
              { key: :feedback, label: "Feedback scores", icon: "hand-thumbs-up", href: eval_feedback_scores_path }
            ] },
            # Evaluators, Analytics and System status render correctly and
            # were in no menu. Analytics is the only screen in the console
            # that reports what evaluation itself costs, which for an
            # LLM-judge policy is the figure that decides the sampling rate;
            # System status carries queue depth, backpressure and the
            # configuration in force, and its own comment records that it
            # raised NoMethodError for a long time and nobody noticed —
            # because nothing linked it.
            { id: :continuous, label: "Continuous", items: [
              { key: :policies, label: "Policies", icon: "clipboard-check", href: continuous_policies_path },
              { key: :evaluators, label: "Evaluators", icon: "puzzle",
                href: continuous_evaluators_path },
              { key: :queue, label: "Queue", icon: "hourglass-split",
                href: continuous_queue_index_path },
              { key: :results, label: "Results", icon: "list-check", href: continuous_results_path },
              { key: :trends, label: "Score trends", icon: "graph-up",
                href: continuous_trends_path },
              { key: :analytics, label: "Analytics", icon: "bar-chart-line",
                href: continuous_analytics_path },
              { key: :health, label: "Health", icon: "heart-pulse",
                href: continuous_health_path },
              { key: :system, label: "System status", icon: "hdd-stack",
                href: dashboard_continuous_health_path }
            ] }
          ]
        end

        # Every routed item, flattened — used to resolve the active key and
        # the breadcrumb from the request path.
        def nav_items
          nav_groups.flat_map { |group| group[:items].map { |item| item.merge(group: group[:label]) } }
                    .select { |item| item[:href] }
        end

        # Longest matching href wins, so "/spans/tools" stays on Tools rather
        # than falling back to Spans.
        def current_from_path
          path = request_path
          return nil if path.blank?

          nav_items
            .select { |item| path == item[:href] || path.start_with?("#{item[:href]}/") }
            .max_by { |item| item[:href].length }
            &.fetch(:key)
        end

        def crumb_from_nav
          key = @current || current_from_path
          nav_items.find { |item| item[:key] == key }&.fetch(:group)
        end

        # Nil when there is no request to read — a component spec, or a render
        # outside a view context. A layout with no path simply has no current
        # nav item, which is the same answer as a path matching nothing.
        def request_path
          request&.path
        rescue StandardError
          nil
        end

        def render_scripts
          # The controllers themselves live in app/assets/javascripts/RAAF/console
          # and are assembled by Ui::Javascript. They used to be a heredoc here,
          # which meant every document carried its own copy of 1,200 lines that
          # no linter, formatter or editor would treat as JavaScript.
          script(type: "module", src: console_javascript_path(Ui::Javascript.digest))

          # Syntax first: the base diff2html build is handed the highlighter
          # rather than carrying one.
          render_syntax_bundle if bundle?(:syntax)
          render_diff_bundle if bundle?(:diff)

          # Preline, for the tooltips. TooltipController waits for it.
          script(src: "https://preline.co/assets/js/preline.js")
        end
      end
    end
  end
end

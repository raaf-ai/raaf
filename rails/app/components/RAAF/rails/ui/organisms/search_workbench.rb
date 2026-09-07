# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # SearchWorkbench — the query bar, its facets and the hits.
        #
        # The facet column is a fixed 220px track against a fluid results
        # column; both minimums are zero so a long agent name truncates inside
        # its facet instead of widening the page.
        #
        # @example
        #   render Organisms::SearchWorkbench.new(
        #     query: params[:q], action: search_path, meta: "148 hits · 240ms",
        #     examples: ["kind:llm tokens>8000"],
        #     facets: [{ label: "Kind", values: [{ label: "tool", count: 148, active: true }] }],
        #     results: [{ kind: "tool", name: "crm_upsert", meta: "12s ago",
        #                 snippet: "…", tone: :bad, href: span_path(span) }]
        #   )
        #
        class SearchWorkbench < Base
          # @param query [String, nil] the current query
          # @param action [String, nil] form target; without it the bar is read-only
          # @param meta [String, nil] hit count and timing
          # @param examples [Array<String>] example queries offered under the bar
          # @param facets [Array<Hash>] :label and :values ({ :label, :count, :active, :href })
          # @param results [Array<Hash>] :kind, :name, :meta, :snippet, :tone, :href
          # @param empty [Hash, nil] arguments for Molecules::EmptyState
          def initialize(query: nil, action: nil, meta: nil, examples: [], facets: [],
                         results: [], empty: nil, name: "q", class: nil, **attrs)
            @query = query
            @action = action
            @meta = meta
            @examples = examples
            @facets = facets
            @results = results
            @empty = empty
            @name = name
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-workbench", @class), **@attrs) do
              query_bar

              # With no facets the split has one child, and a two-track grid
              # would drop it into the 220px facet column — which is what the
              # "search the trace store" prompt and every no-results message
              # used to render into.
              div(class: tokens("raaf-wb-split", { "raaf-wb-split--bare" => @facets.empty? })) do
                facet_column if @facets.any?
                results_column
              end
            end
          end

          private

          def query_bar
            div(class: "raaf-wb-bar") do
              if @action
                form(action: @action, method: "get", class: "raaf-wb-form", role: "search") do
                  render Atoms::Icon.new("search", tone: :accent)
                  render Atoms::Input.new(name: @name, value: @query, mono: true,
                                          placeholder: "kind:tool status:error \"execution expired\"",
                                          class: "raaf-wb-input", "aria-label": "Search traces and spans")
                  render Atoms::Mono.new(@meta, tone: :muted) if @meta
                end
              else
                render Atoms::Icon.new("search", tone: :accent)
                render Atoms::Mono.new(@query, class: "raaf-wb-input")
                render Atoms::Mono.new(@meta, tone: :muted) if @meta
              end
              examples if @examples.any?
            end
          end

          def examples
            div(class: "raaf-wb-examples") do
              render Atoms::Label.new("Try")
              @examples.each { |example| example_chip(example) }
            end
          end

          # An example is a link when the workbench knows where to submit, so
          # clicking one runs it rather than only showing the syntax.
          def example_chip(example)
            query = example.is_a?(Hash) ? example[:query] : example
            href = example.is_a?(Hash) ? example[:href] : example_href(query)

            if href
              a(href: href, class: "raaf-wb-example") { query }
            else
              span(class: "raaf-wb-example") { query }
            end
          end

          def example_href(query)
            return nil unless @action

            "#{@action}?#{{ @name => query }.to_query}"
          end

          def facet_column
            aside(class: "raaf-wb-facets", "aria-label": "Filters") do
              @facets.each { |facet| facet_group(facet) }
            end
          end

          def facet_group(facet)
            div(class: "raaf-facet") do
              render Atoms::Label.new(facet[:label])
              Array(facet[:values]).each { |value| facet_value(value) }
            end
          end

          def facet_value(value)
            tag = value[:href] ? :a : :div
            attributes = { class: tokens("raaf-facet-value", { "is-active" => value[:active] }) }
            attributes[:href] = value[:href] if value[:href]

            public_send(tag, **attributes) do
              span(class: "raaf-facet-box")
              span(class: "raaf-facet-label") { value[:label] }
              render Atoms::Mono.new(value[:count], tone: :muted)
            end
          end

          def results_column
            section(class: "raaf-wb-results", "aria-label": "Results") do
              if @results.empty? && @empty
                render Molecules::EmptyState.new(**@empty)
              else
                @results.each { |result| hit(result) }
              end
            end
          end

          def hit(result)
            tag = result[:href] ? :a : :div
            attributes = {
              class: tokens("raaf-hit", modifier("raaf-hit", result[:tone], %i[ok warn bad]))
            }
            attributes[:href] = result[:href] if result[:href]

            public_send(tag, **attributes) do
              div(class: "raaf-hit-head") do
                render Atoms::KindBadge.new(result[:kind])
                span(class: "raaf-hit-name") { result[:name] }
                render Atoms::Mono.new(result[:meta], tone: :muted) if result[:meta]
              end
              div(class: "raaf-hit-snippet") { result[:snippet] } if result[:snippet]
            end
          end
        end
      end
    end
  end
end

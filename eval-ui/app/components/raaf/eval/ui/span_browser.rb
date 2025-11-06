# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      ##
      # Phlex component for browsing and filtering production spans
      #
      # Displays a filterable, searchable, paginated table of spans
      # with expandable row details and selection for evaluation.
      #
      # @example Render in a view
      #   render RAAF::Eval::UI::SpanBrowser.new(spans: @spans, filters: @filters)
      #
      class SpanBrowser < Phlex::HTML
        def initialize(spans:, filters: {}, page: 1, per_page: 25)
          @spans = spans
          @filters = filters
          @page = page
          @per_page = per_page
        end

        def view_template
          div(class: "span-browser p-6") do
            render_header
            render_filters
            render_table
            render_pagination
          end
        end

        private

        def render_header
          div(class: "flex justify-between items-center mb-6") do
            h1(class: "text-2xl font-bold text-gray-900") { "Production Spans" }
            div(class: "flex gap-2") do
              render_search_bar
              button(
                class: "px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700",
                type: "button"
              ) do
                "Refresh"
              end
            end
          end
        end

        def render_search_bar
          div(class: "relative") do
            input(
              type: "text",
              placeholder: "Search spans...",
              class: "px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent",
              data_controller: "search",
              data_action: "input->search#query",
              data_search_url_value: "/eval/spans/search"
            )
          end
        end

        def render_filters
          div(class: "bg-white rounded-lg shadow-sm p-4 mb-4") do
            div(class: "grid grid-cols-1 md:grid-cols-4 gap-4") do
              render_filter_select("Agent", :agent_name, agent_options)
              render_filter_select("Model", :model, model_options)
              render_filter_select("Status", :status, status_options)
              render_date_range_filter
            end
          end
        end

        def render_filter_select(label, name, options)
          div do
            label(class: "block text-sm font-medium text-gray-700 mb-1") { label }
            select(
              name: name,
              class: "w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500",
              data_action: "change->filter#apply"
            ) do
              option(value: "") { "All" }
              options.each do |opt|
                option(value: opt, selected: @filters[name] == opt) { opt }
              end
            end
          end
        end

        def render_date_range_filter
          div do
            label(class: "block text-sm font-medium text-gray-700 mb-1") { "Date Range" }
            div(class: "flex gap-2") do
              input(
                type: "date",
                name: "start_date",
                class: "px-3 py-2 border border-gray-300 rounded-lg",
                value: @filters[:start_date]
              )
              span(class: "self-center") { "to" }
              input(
                type: "date",
                name: "end_date",
                class: "px-3 py-2 border border-gray-300 rounded-lg",
                value: @filters[:end_date]
              )
            end
          end
        end

        def render_table
          div(id: "spans_table", class: "bg-white rounded-lg shadow-sm overflow-hidden") do
            if @spans.empty?
              render_empty_state
            else
              table(class: "min-w-full divide-y divide-gray-200") do
                render_table_header
                tbody(class: "bg-white divide-y divide-gray-200") do
                  @spans.each { |span| render_table_row(span) }
                end
              end
            end
          end
        end

        def render_table_header
          thead(class: "bg-gray-50") do
            tr do
              th(class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Agent" }
              th(class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Model" }
              th(class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Status" }
              th(class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Created" }
              th(class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Tokens" }
              th(class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") { "Actions" }
            end
          end
        end

        def render_table_row(span)
          tr(class: "hover:bg-gray-50 cursor-pointer") do
            td(class: "px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900") { span.agent_name }
            td(class: "px-6 py-4 whitespace-nowrap text-sm text-gray-500") { span.model }
            td(class: "px-6 py-4 whitespace-nowrap") do
              span(class: status_badge_class(span.status)) { span.status }
            end
            td(class: "px-6 py-4 whitespace-nowrap text-sm text-gray-500") do
              span.created_at&.strftime("%Y-%m-%d %H:%M")
            end
            td(class: "px-6 py-4 whitespace-nowrap text-sm text-gray-500") { span.tokens || "N/A" }
            td(class: "px-6 py-4 whitespace-nowrap text-sm font-medium") do
              a(
                href: "/eval/evaluations/new?span_id=#{span.id}",
                class: "text-blue-600 hover:text-blue-900"
              ) { "Evaluate" }
            end
          end
        end

        def render_empty_state
          div(class: "text-center py-12") do
            p(class: "text-gray-500 text-lg") { "No spans found" }
            p(class: "text-gray-400 text-sm mt-2") { "Try adjusting your filters" }
          end
        end

        def render_pagination
          div(class: "flex justify-between items-center mt-4") do
            div(class: "text-sm text-gray-700") do
              "Showing #{(@page - 1) * @per_page + 1} to #{@page * @per_page} of #{@spans.count} results"
            end
            div(class: "flex gap-2") do
              button(class: "px-3 py-1 border border-gray-300 rounded", disabled: @page == 1) { "Previous" }
              button(class: "px-3 py-1 border border-gray-300 rounded") { "Next" }
            end
          end
        end

        def status_badge_class(status)
          base = "px-2 inline-flex text-xs leading-5 font-semibold rounded-full"
          case status.to_s
          when "completed"
            "#{base} bg-green-100 text-green-800"
          when "failed"
            "#{base} bg-red-100 text-red-800"
          when "running"
            "#{base} bg-yellow-100 text-yellow-800"
          else
            "#{base} bg-gray-100 text-gray-800"
          end
        end

        def agent_options
          ["GPTAgent", "ClaudeAgent", "ResearchAgent"]
        end

        def model_options
          ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo", "claude-3-opus", "claude-3-sonnet"]
        end

        def status_options
          ["completed", "failed", "running"]
        end
      end
    end
  end
end

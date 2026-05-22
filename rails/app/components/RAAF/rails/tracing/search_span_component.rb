# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class SearchSpanComponent < SpanDetailBase
        def view_template
          div(class: "space-y-6") do
            render_search_overview
            render_query_section
            render_search_params
            render_results_section
            render_raw_attributes
            render_error_handling
          end
        end

        private

        def provider_name
          @provider_name ||= extract_span_attribute("provider") ||
                             extract_span_attribute("component.name")&.demodulize&.underscore ||
                             "search"
        end

        def query
          @query ||= extract_span_attribute("query")
        end

        def result_count
          @result_count ||= extract_span_attribute("result_count") || 0
        end

        def cost_cents
          @cost_cents ||= extract_span_attribute("cost_cents")
        end

        def search_results
          @search_results ||= begin
            results = []
            i = 0
            loop do
              title = extract_span_attribute("result.#{i}.title")
              break unless title

              results << {
                title: title,
                url: extract_span_attribute("result.#{i}.url"),
                score: extract_span_attribute("result.#{i}.score"),
                snippet: extract_span_attribute("result.#{i}.snippet"),
                snippets: extract_span_attribute("result.#{i}.snippets")
              }
              i += 1
            end
            results
          end
        end

        def render_search_overview
          icon = case provider_name.to_s
                 when /brave/i then "bi bi-shield-check"
                 when /google/i then "bi bi-google"
                 when /perplexity/i then "bi bi-stars"
                 when /tavily/i then "bi bi-search"
                 else "bi bi-search"
                 end

          render_span_overview_header(
            icon,
            "#{provider_name.to_s.titleize} Search",
            "#{result_count} results#{cost_cents ? " · #{cost_cents}¢" : ""}"
          )
        end

        def render_query_section
          return unless query

          div(class: "bg-white overflow-hidden shadow rounded-lg border border-blue-200") do
            div(class: "px-4 py-3 border-b border-blue-200 bg-blue-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-search text-blue-600 text-lg")
                h3(class: "text-lg font-semibold text-blue-900") { "Query" }
              end
            end
            div(class: "px-4 py-4") do
              p(class: "text-base text-gray-900 font-medium") { query }
            end
          end
        end

        def render_search_params
          params = {}
          params["Context"] = extract_span_attribute("search.context") if extract_span_attribute("search.context")
          params["Max Results"] = extract_span_attribute("search.num") if extract_span_attribute("search.num")
          params["Start Offset"] = extract_span_attribute("search.start") if extract_span_attribute("search.start")
          params["Date Restrict"] = extract_span_attribute("search.date_restrict") if extract_span_attribute("search.date_restrict")
          params["Sort"] = extract_span_attribute("search.sort") if extract_span_attribute("search.sort")
          params["Duration"] = "#{@span.duration_ms}ms" if @span.duration_ms
          params["Cost"] = "#{cost_cents}¢" if cost_cents

          return if params.empty?

          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-3 border-b border-gray-200 bg-gray-50") do
              h3(class: "text-sm font-semibold text-gray-700") { "Search Parameters" }
            end
            div(class: "px-4 py-3") do
              div(class: "flex flex-wrap gap-3") do
                params.each do |label, value|
                  div(class: "inline-flex items-center gap-1.5 bg-gray-100 px-3 py-1.5 rounded-full") do
                    span(class: "text-xs font-medium text-gray-500") { label }
                    span(class: "text-xs font-semibold text-gray-900") { value.to_s }
                  end
                end
              end
            end
          end
        end

        def render_results_section
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-green-200") do
            div(class: "px-4 py-3 border-b border-green-200 bg-green-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-body-text text-green-600 text-lg")
                h3(class: "text-lg font-semibold text-green-900") { "Results (#{result_count})" }
              end
            end

            if search_results.any?
              div(class: "divide-y divide-gray-100") do
                search_results.each_with_index do |result, idx|
                  render_result_card(result, idx)
                end
              end
            else
              render_results_from_json
            end
          end
        end

        def render_result_card(result, idx)
          div(class: "px-4 py-4 hover:bg-gray-50") do
            div(class: "flex items-start gap-3") do
              span(class: "flex-shrink-0 w-6 h-6 rounded-full bg-green-100 text-green-700 text-xs font-bold flex items-center justify-center mt-0.5") do
                (idx + 1).to_s
              end

              div(class: "flex-1 min-w-0") do
                if result[:title]
                  h4(class: "text-sm font-semibold text-gray-900 mb-1") { result[:title] }
                end

                if result[:url]
                  a(
                    href: result[:url],
                    target: "_blank",
                    rel: "noopener noreferrer",
                    class: "text-xs text-blue-600 hover:text-blue-800 break-all block mb-2"
                  ) { result[:url] }
                end

                if result[:snippet]
                  p(class: "text-sm text-gray-700 mb-2") { result[:snippet] }
                end

                if result[:snippets].is_a?(Array) && result[:snippets].length > 1
                  div(class: "mt-2 space-y-1") do
                    result[:snippets][1..].each do |extra|
                      p(class: "text-xs text-gray-500 pl-3 border-l-2 border-gray-200") { extra }
                    end
                  end
                end

                if result[:score]
                  span(class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-800 mt-1") do
                    "Score: #{result[:score]}"
                  end
                end
              end
            end
          end
        end

        def render_results_from_json
          div(class: "px-4 py-4") do
            pre(
              class: "bg-gray-50 p-3 rounded border text-xs overflow-x-auto font-mono overflow-y-auto text-gray-900",
              data: { controller: "json-highlight", json_highlight_target: "json" }
            ) do
              format_json_display(result_attributes_hash)
            end
          end
        end

        def result_attributes_hash
          return {} unless @span.span_attributes

          @span.span_attributes.select { |k, _| k.to_s.start_with?("result") }
        end

        def render_raw_attributes
          return unless @span.span_attributes&.any?

          section_id = "raw-attrs-#{@span.span_id}"

          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            button(
              class: "w-full px-4 py-3 border-b border-gray-200 bg-gray-50 flex items-center justify-between hover:bg-gray-100",
              data: { action: "click->span-detail#toggleSection", target: section_id }
            ) do
              div(class: "flex items-center gap-2") do
                i(class: "bi bi-code-square text-gray-600")
                h3(class: "text-sm font-semibold text-gray-700") { "Raw Attributes JSON" }
              end
              i(class: "bi bi-chevron-right text-gray-400 toggle-icon")
            end

            div(id: section_id, class: "hidden") do
              div(class: "px-4 py-4") do
                pre(
                  class: "bg-gray-50 p-3 rounded border text-xs overflow-x-auto font-mono overflow-y-auto text-gray-900",
                  data: { controller: "json-highlight", json_highlight_target: "json" }
                ) do
                  format_json_display(@span.span_attributes)
                end
              end
            end
          end
        end
      end
    end
  end
end

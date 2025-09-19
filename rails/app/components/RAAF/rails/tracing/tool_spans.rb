# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class ToolSpans < BaseComponent
        def initialize(tool_spans:, total_tool_spans:, params: {}, page: 1, total_pages: 1, per_page: 20, total_count: 0)
          @tool_spans = tool_spans
          @total_tool_spans = total_tool_spans
          @params = params
          @page = page
          @total_pages = total_pages
          @per_page = per_page
          @total_count = total_count
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_tool_stats
            render_filters
            render_tool_spans_table
          end

          content_for :javascript do
            render_toggle_script
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6") do
            div(class: "min-w-0 flex-1") do
              h1(class: "text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate") { "Tool Spans" }
              p(class: "mt-1 text-sm text-gray-500") { "Monitor tool and custom function call executions" }
            end

            div(class: "mt-4 flex sm:mt-0 sm:ml-4") do
              render_preline_button(
                text: "Export Tool Data",
                href: tools_tracing_spans_path(format: :json),
                variant: "secondary",
                icon: "bi-download"
              )
            end
          end
        end

        def render_tool_stats
          stats = calculate_tool_stats

          div(class: "grid grid-cols-1 gap-5 sm:grid-cols-4 mb-6") do
            render_metric_card(
              title: "Total Tool Calls",
              value: stats[:total_calls],
              color: "blue",
              icon: "bi-wrench"
            )

            render_metric_card(
              title: "Unique Tools",
              value: stats[:unique_tools],
              color: "green",
              icon: "bi-collection"
            )

            render_metric_card(
              title: "Avg Duration",
              value: format_duration(stats[:avg_duration]),
              color: "yellow",
              icon: "bi-stopwatch"
            )

            render_metric_card(
              title: "Error Rate",
              value: "#{stats[:error_rate].round(1)}%",
              color: stats[:error_rate] > 5 ? "red" : "green",
              icon: "bi-exclamation-triangle"
            )
          end
        end

        def render_filters
          div(class: "bg-white p-6 rounded-lg shadow mb-6") do
            form_with(url: tools_tracing_spans_path, method: :get, local: true, class: "grid grid-cols-1 gap-4 sm:grid-cols-6") do |form|
              div(class: "sm:col-span-2") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Search" }
                form.text_field(
                  :search,
                  placeholder: "Search tool names, span IDs...",
                  value: @params[:search],
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div(class: "sm:col-span-1") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Function Name" }
                form.text_field(
                  :function_name,
                  placeholder: "Function name",
                  value: @params[:function_name],
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div(class: "sm:col-span-1") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Status" }
                form.select(
                  :status,
                  [
                    ["All Statuses", ""],
                    ["Completed", "completed"],
                    ["Failed", "failed"],
                    ["Error", "error"]
                  ],
                  { selected: @params[:status] },
                  { class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" }
                )
              end

              div(class: "sm:col-span-1") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Trace ID" }
                form.text_field(
                  :trace_id,
                  placeholder: "Trace ID",
                  value: @params[:trace_id],
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div(class: "sm:col-span-1 flex items-end") do
                form.submit("Filter", class: "w-full inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700")
              end
            end
          end
        end

        def render_tool_spans_table
          if @tool_spans.any?
            render_preline_table do
              table(class: "min-w-full divide-y divide-gray-200") do
                render_table_header
                render_table_body
              end
            end
            render_pagination if @total_pages > 1
          else
            render_empty_state
          end
        end

        def render_table_header
          thead(class: "bg-gray-50") do
            tr do
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Tool / Function"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Kind"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Status"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Duration"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Input/Output"
              end
              th(scope: "col", class: "px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider") do
                "Trace"
              end
            end
          end
        end

        def render_table_body
          tbody(class: "bg-white divide-y divide-gray-200") do
            @tool_spans.each do |span|
              render_tool_span_row(span)
            end
          end
        end

        def render_tool_span_row(span)
          tool_data = extract_tool_data(span)

          tr(class: "hover:bg-gray-50") do
            td(class: "px-6 py-4") do
              div(class: "flex flex-col") do
                div(class: "text-sm font-medium text-gray-900") do
                  link_to(
                    tool_data[:function_name] || span.name,
                    tracing_span_path(span.span_id),
                    class: "text-blue-600 hover:text-blue-900"
                  )
                end
                div(class: "text-sm text-gray-500 font-mono") { span.span_id }
                if tool_data[:function_name] != span.name
                  div(class: "text-xs text-gray-400") { "Span: #{span.name}" }
                end
              end
            end

            td(class: "px-6 py-4 whitespace-nowrap") do
              render_kind_badge(span.kind)
            end

            td(class: "px-6 py-4 whitespace-nowrap") do
              render_status_badge(span.status)
            end

            td(class: "px-6 py-4 whitespace-nowrap text-sm text-gray-900") do
              format_duration(span.duration_ms)
            end

            td(class: "px-6 py-4 max-w-md") do
              render_input_output_summary(tool_data)
            end

            td(class: "px-6 py-4 whitespace-nowrap text-sm") do
              if span.trace
                link_to(
                  span.trace.workflow_name || span.trace_id,
                  tracing_trace_path(span.trace_id),
                  class: "text-blue-600 hover:text-blue-500"
                )
              else
                span(class: "text-gray-500") { span.trace_id }
              end
            end

          end
        end

        def render_input_output_summary(tool_data)
          div(class: "text-sm space-y-2") do
            # Input parameters section
            if tool_data[:input]
              div(class: "border border-gray-200 rounded-md") do
                div(class: "bg-blue-50 px-3 py-2 border-b border-gray-200") do
                  div(class: "flex items-center justify-between") do
                    strong(class: "text-blue-900") { "Input Parameters" }
                    button(
                      class: "text-blue-600 hover:text-blue-800 text-xs",
                      onclick: "toggleDetails(this)",
                      data: { target: "input" }
                    ) { "Show Details" }
                  end
                end
                div(class: "p-3 bg-white hidden", data: { section: "input" }) do
                  pre(class: "text-xs text-gray-700 whitespace-pre-wrap bg-gray-50 p-2 rounded border overflow-x-auto") do
                    format_json_display(tool_data[:input])
                  end
                end
                # Preview line
                div(class: "px-3 py-2 text-xs text-gray-600 bg-gray-50", data: { section: "input-preview" }) do
                  truncate_json(tool_data[:input])
                end
              end
            end

            # Output results section
            if tool_data[:output]
              div(class: "border border-gray-200 rounded-md") do
                div(class: "bg-green-50 px-3 py-2 border-b border-gray-200") do
                  div(class: "flex items-center justify-between") do
                    strong(class: "text-green-900") { "Output Results" }
                    button(
                      class: "text-green-600 hover:text-green-800 text-xs",
                      onclick: "toggleDetails(this)",
                      data: { target: "output" }
                    ) { "Show Details" }
                  end
                end
                div(class: "p-3 bg-white hidden", data: { section: "output" }) do
                  pre(class: "text-xs text-gray-700 whitespace-pre-wrap bg-gray-50 p-2 rounded border overflow-x-auto") do
                    format_json_display(tool_data[:output])
                  end
                end
                # Preview line
                div(class: "px-3 py-2 text-xs text-gray-600 bg-gray-50", data: { section: "output-preview" }) do
                  truncate_json(tool_data[:output])
                end
              end
            end

            if !tool_data[:input] && !tool_data[:output]
              div(class: "text-center py-4 text-gray-400 border border-gray-200 rounded-md bg-gray-50") do
                "No input/output data available"
              end
            end
          end
        end

        def render_pagination
          nav(class: "bg-white px-4 py-3 flex items-center justify-between border-t border-gray-200 sm:px-6") do
            div(class: "hidden sm:block") do
              p(class: "text-sm text-gray-700") do
                plain "Showing "
                span(class: "font-medium") { ((@page - 1) * @per_page + 1).to_s }
                plain " to "
                span(class: "font-medium") { [@page * @per_page, @total_count].min.to_s }
                plain " of "
                span(class: "font-medium") { @total_count.to_s }
                plain " tool spans"
              end
            end

            div(class: "flex-1 flex justify-between sm:justify-end") do
              if @page > 1
                link_to(
                  "Previous",
                  tools_tracing_spans_path(@params.merge(page: @page - 1)),
                  class: "relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                )
              end

              if @page < @total_pages
                link_to(
                  "Next",
                  tools_tracing_spans_path(@params.merge(page: @page + 1)),
                  class: "ml-3 relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
                )
              end
            end
          end
        end

        def render_empty_state
          div(class: "text-center py-12") do
            i(class: "bi bi-wrench text-6xl text-gray-400 mb-4")
            h3(class: "text-lg font-medium text-gray-900 mb-2") { "No tool spans found" }
            p(class: "text-gray-500 mb-6") { "No tool or custom function calls match your current filters." }
            render_preline_button(
              text: "Clear Filters",
              href: tools_tracing_spans_path,
              variant: "secondary"
            )
          end
        end

        private

        def calculate_tool_stats
          return { total_calls: 0, unique_tools: 0, avg_duration: 0, error_rate: 0 } unless @tool_spans.respond_to?(:count)

          total_calls = @total_tool_spans.count
          return { total_calls: 0, unique_tools: 0, avg_duration: 0, error_rate: 0 } if total_calls.zero?

          error_count = @total_tool_spans.where(status: "error").count
          durations = @tool_spans.filter_map(&:duration_ms)
          avg_duration = durations.any? ? durations.sum.to_f / durations.size : 0

          # Calculate unique tools
          unique_tools = Set.new
          @tool_spans.each do |span|
            tool_data = extract_tool_data(span)
            unique_tools.add(tool_data[:function_name]) if tool_data[:function_name]
          end

          {
            total_calls: total_calls,
            unique_tools: unique_tools.size,
            avg_duration: avg_duration,
            error_rate: (error_count.to_f / total_calls) * 100
          }
        end

        def extract_tool_data(span)
          if span.kind == "tool"
            function_data = span.span_attributes&.dig("function") || {}
            {
              function_name: function_data["name"],
              input: function_data["input"],
              output: function_data["output"]
            }
          else # custom
            {
              function_name: span.span_attributes&.dig("custom", "name") || span.name,
              input: span.span_attributes&.dig("custom", "data") || {},
              output: span.span_attributes&.dig("output") || span.span_attributes&.dig("result")
            }
          end
        end

        def format_json_display(data)
          return "N/A" if data.nil?

          case data
          when String
            # Try to parse as JSON for pretty formatting, fallback to string
            begin
              JSON.pretty_generate(JSON.parse(data))
            rescue JSON::ParserError
              data
            end
          when Hash, Array
            JSON.pretty_generate(data)
          else
            data.to_s
          end
        end

        def truncate_json(data)
          return "N/A" if data.nil?

          json_str = case data
                     when String
                       data
                     when Hash, Array
                       data.to_json
                     else
                       data.to_s
                     end

          truncate(json_str, length: 100)
        end

        def render_toggle_script
          script do
            plain <<~JAVASCRIPT
              function toggleDetails(button) {
                const target = button.getAttribute('data-target');
                const row = button.closest('tr');
                const detailsSection = row.querySelector(`[data-section="${target}"]`);
                const previewSection = row.querySelector(`[data-section="${target}-preview"]`);

                if (detailsSection && previewSection) {
                  if (detailsSection.classList.contains('hidden')) {
                    // Show details, hide preview
                    detailsSection.classList.remove('hidden');
                    previewSection.classList.add('hidden');
                    button.textContent = 'Hide Details';
                  } else {
                    // Hide details, show preview
                    detailsSection.classList.add('hidden');
                    previewSection.classList.remove('hidden');
                    button.textContent = 'Show Details';
                  }
                }
              }
            JAVASCRIPT
          end
        end
      end
    end
  end
end
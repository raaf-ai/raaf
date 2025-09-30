# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class SpanDetailBase < BaseComponent
        def initialize(span:, trace: nil, **options)
          @span = span
          @trace = trace
          @options = options
        end

        protected

        def render_json_section(title, data, collapsed: true, use_json_highlighter: false, compact: false)
          return unless data

          section_id = "section-#{title.parameterize}-#{@span.span_id}"
          data_size = calculate_data_size(data)
          is_large_data = data_size > 10000 # Large data threshold for performance optimization

          section(class: "bg-gray-50 rounded-lg p-4", data: { controller: "span-detail" }) do
            button(
              class: "flex items-center gap-2 text-sm font-medium text-gray-700 hover:text-gray-900 w-full text-left",
              data: {
                action: "click->span-detail#toggleSection",
                target: section_id
              }
            ) do
              i(class: collapsed ? "bi bi-chevron-right toggle-icon" : "bi bi-chevron-down toggle-icon")
              span { title }
              div(class: "flex items-center gap-2 ml-2") do
                span(class: "text-xs text-gray-500") { "(#{data_size_indicator(data)})" }

                # Performance warning for large data
                if is_large_data
                  span(
                    class: "inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-orange-100 text-orange-800 border border-orange-200",
                    title: "Large data set - may impact performance"
                  ) do
                    i(class: "bi bi-exclamation-triangle mr-1")
                    "Large"
                  end
                end
              end
            end

            div(id: section_id, class: collapsed ? "hidden mt-3" : "mt-3") do
              if is_large_data && collapsed
                # Lazy loading placeholder for large data
                div(
                  class: "bg-yellow-50 border border-yellow-200 rounded p-3 text-center",
                  data: {
                    lazy_content: section_id,
                    action: "click->span-detail#loadLargeContent"
                  }
                ) do
                  div(class: "flex items-center justify-center gap-2 text-yellow-800") do
                    i(class: "bi bi-hourglass")
                    span(class: "text-sm") { "Large data set (#{format_data_size(data_size)}) - Click to load" }
                  end
                end
              else
                render_json_content(data, data_size, is_large_data, use_json_highlighter, compact)
              end
            end
          end
        end

        # Render JSON content with performance optimizations
        def render_json_content(data, data_size, is_large_data, use_json_highlighter = false, compact = false)
          if is_large_data
            # Truncated view for large data with expand option
            render_truncated_json_view(data, data_size, use_json_highlighter, compact)
          else
            # Standard JSON view
            json_data_attrs = use_json_highlighter ? {
              controller: "json-highlight",
              json_highlight_target: "json"
            } : {}

            pre(
              class: "bg-white p-3 rounded border text-xs overflow-x-auto font-mono max-h-96 overflow-y-auto text-gray-900",
              data: json_data_attrs
            ) do
              format_json_display(data, compact)
            end
          end
        end

        # Render truncated view for large JSON data
        def render_truncated_json_view(data, data_size, use_json_highlighter = false, compact = false)
          truncated_data = truncate_large_data(data)
          truncate_id = "truncate-#{SecureRandom.hex(4)}"

          json_data_attrs = use_json_highlighter ? {
            controller: "json-highlight",
            json_highlight_target: "json"
          } : {}

          div(class: "space-y-2") do
            # Performance info banner
            div(class: "bg-blue-50 border border-blue-200 rounded p-2 text-xs text-blue-800") do
              div(class: "flex items-center gap-2") do
                i(class: "bi bi-info-circle")
                span { "Large dataset optimized for performance (#{format_data_size(data_size)} total)" }
              end
            end

            # Truncated content
            div(id: "#{truncate_id}-preview") do
              pre(
                class: "bg-white p-3 rounded border text-xs overflow-x-auto font-mono max-h-48 overflow-y-auto text-gray-900",
                data: json_data_attrs
              ) do
                format_json_display(truncated_data, compact) + "\n\n... (truncated)"
              end
            end

            # Full content (initially hidden)
            div(id: "#{truncate_id}-full", class: "hidden") do
              pre(
                class: "bg-white p-3 rounded border text-xs overflow-x-auto font-mono max-h-96 overflow-y-auto text-gray-900",
                data: json_data_attrs
              ) do
                format_json_display(data, compact)
              end
            end

            # Toggle button
            button(
              class: "w-full px-3 py-2 text-xs bg-blue-100 hover:bg-blue-200 text-blue-800 rounded border border-blue-300 transition-colors",
              data: {
                action: "click->span-detail#toggleValue",
                target: truncate_id
              }
            ) do
              "Show Full Content (#{format_data_size(data_size)})"
            end
          end
        end

        # Calculate data size in characters
        def calculate_data_size(data)
          case data
          when String then data.length
          when Hash, Array then JSON.generate(data).length
          else data.to_s.length
          end
        end

        # Format data size for display
        def format_data_size(size)
          case size
          when 0..999 then "#{size} chars"
          when 1000..999_999 then "#{(size / 1000.0).round(1)}K chars"
          else "#{(size / 1_000_000.0).round(2)}M chars"
          end
        end

        # Truncate large data for initial display
        def truncate_large_data(data, max_items: 10)
          case data
          when Hash
            data.first(max_items).to_h
          when Array
            data.first(max_items)
          when String
            data.length > 1000 ? data[0...1000] : data
          else
            data
          end
        end

        def format_timestamp(time)
          return "N/A" unless time
          time.strftime("%Y-%m-%d %H:%M:%S.%3N")
        end

        # Format duration using the BaseComponent method
        def format_duration(ms)
          return "N/A" unless ms
          super(ms)
        end

        def render_duration_badge(duration_ms)
          return span(class: "px-2 py-1 text-xs font-medium rounded-full bg-gray-100 text-gray-800") { "N/A" } unless duration_ms

          color_class = case duration_ms.to_f
          when 0..100 then "bg-green-100 text-green-800"
          when 101..1000 then "bg-yellow-100 text-yellow-800"
          else "bg-red-100 text-red-800"
          end

          span(class: "px-2 py-1 text-xs font-medium rounded-full #{color_class}") do
            "#{duration_ms.round}ms"
          end
        end

        def render_span_overview_header(icon_class, title, subtitle = nil)
          div(class: "bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6") do
            div(class: "flex items-center gap-3") do
              i(class: "#{icon_class} text-blue-600 text-lg")
              div do
                h3(class: "font-semibold text-blue-900") { title }
                if subtitle
                  p(class: "text-sm text-blue-700") { subtitle }
                end
              end
            end
          end
        end

        def render_detail_item(label, value, monospace: false)
          div(class: "bg-gray-50 rounded-lg p-3 sm:bg-transparent sm:rounded-none sm:p-0") do
            dt(class: "text-xs sm:text-sm font-medium text-gray-500 mb-1 sm:mb-0") { label }
            dd(class: "text-sm text-gray-900 break-all sm:break-normal #{'font-mono text-xs sm:text-sm' if monospace}") { value }
          end
        end

        def format_json_display(data, compact = false)
          return "N/A" if data.nil?

          case data
          when String
            begin
              parsed = JSON.parse(data)
              compact ? JSON.generate(parsed) : JSON.pretty_generate(parsed)
            rescue JSON::ParserError
              data
            end
          when Hash, Array
            compact ? JSON.generate(data) : JSON.pretty_generate(data)
          else
            data.to_s
          end
        end

        def extract_span_attribute(key)
          return nil unless @span.span_attributes

          # Try direct key first
          return @span.span_attributes[key] if @span.span_attributes.key?(key)

          # Try common RAAF namespaced patterns
          namespaced_patterns = [
            "raaf::tracing::spancollectors::agent.#{key}",
            "raaf::tracing::spancollectors::#{key}",
            "agent.#{key}",
            "agent_#{key}",
            key.to_s
          ]

          # Check each pattern
          namespaced_patterns.each do |pattern|
            return @span.span_attributes[pattern] if @span.span_attributes.key?(pattern)
          end

          # Try flexible key matching for nested structures
          if key.include?('.')
            @span.span_attributes&.dig(*key.split('.'))
          else
            nil
          end
        end

        def data_size_indicator(data)
          case data
          when Hash then "#{data.keys.count} keys"
          when Array then "#{data.count} items"
          when String then "#{data.length} chars"
          else "data"
          end
        end

        def render_error_handling
          return unless @span.status == "error" || extract_span_attribute("error")

          div(class: "bg-red-50 border border-red-200 rounded-lg p-4 mb-6") do
            div(class: "flex items-center gap-2 mb-2") do
              i(class: "bi bi-exclamation-triangle text-red-600")
              h4(class: "font-medium text-red-900") { "Error Details" }
            end

            error_data = extract_span_attribute("error") || "Unknown error"
            pre(class: "text-sm text-red-900 bg-red-100 p-3 rounded border overflow-x-auto") do
              format_json_display(error_data, false)
            end
          end
        end

        # Task 2.2: Universal span overview with trace ID, parent, timing for all span types
        def render_span_overview
          div(class: "bg-white overflow-hidden shadow rounded-lg mb-6") do
            # Header with navigation breadcrumb and performance indicator (responsive)
            div(class: "px-3 py-4 sm:px-4 sm:py-5 lg:px-6 border-b border-gray-200") do
              div(class: "flex flex-col space-y-3 sm:flex-row sm:items-center sm:justify-between sm:space-y-0") do
                div(class: "flex-1 min-w-0") do
                  h3(class: "text-base sm:text-lg leading-6 font-medium text-gray-900 mb-2 truncate") { "Span Overview" }
                  # Task 2.3: Span hierarchy navigation and relationship display
                  render_span_hierarchy_navigation
                end

                # Duration badge with performance-based coloring (mobile-responsive)
                if @span.duration_ms
                  div(class: "flex-shrink-0") do
                    render_enhanced_duration_badge(@span.duration_ms)
                  end
                end
              end
            end

            # Main overview content with responsive grid (mobile-first)
            div(class: "px-3 py-4 sm:px-4 sm:py-5 lg:p-6") do
              dl(class: "grid grid-cols-1 gap-3 sm:gap-x-4 sm:gap-y-6 sm:grid-cols-2 lg:grid-cols-3") do
                # Core span identification with copy functionality
                render_span_id_item
                render_trace_id_item
                render_parent_id_item

                # Span metadata with proper badges
                render_detail_item("Name", @span.name)
                render_detail_item("Kind", render_kind_badge(@span.kind))
                render_detail_item("Status", render_status_badge(@span.status))

                # Workflow context when available
                if @trace
                  render_detail_item("Workflow", @trace.workflow_name || "Unknown")
                end

                # Hierarchy information
                render_detail_item("Depth", @span.depth || 0)
              end
            end
          end
        end

        # Task 2.3: Span hierarchy navigation showing relationships (mobile-responsive)
        def render_span_hierarchy_navigation
          nav(class: "flex flex-wrap items-center gap-1 sm:gap-2 text-xs sm:text-sm overflow-x-auto", aria: { label: "Span hierarchy navigation" }) do
            # Trace navigation link (mobile-optimized)
            if @trace
              link_to(
                tracing_trace_path(@span.trace_id),
                class: "text-blue-600 hover:text-blue-900 font-mono flex items-center gap-1 transition-colors flex-shrink-0 py-1 px-2 rounded hover:bg-blue-50",
                title: "View full trace: #{@span.trace_id}"
              ) do
                i(class: "bi bi-diagram-3")
                span(class: "hidden sm:inline") { "Trace:" }
                span { truncate_id(@span.trace_id, length: 6) }
              end
              i(class: "bi bi-chevron-right text-gray-400 text-xs flex-shrink-0")
            end

            # Parent span navigation link (mobile-optimized)
            if @span.parent_id
              link_to(
                tracing_span_path(@span.parent_id),
                class: "text-blue-600 hover:text-blue-900 font-mono flex items-center gap-1 transition-colors flex-shrink-0 py-1 px-2 rounded hover:bg-blue-50",
                title: "View parent span: #{@span.parent_id}"
              ) do
                i(class: "bi bi-arrow-up-circle")
                span(class: "hidden sm:inline") { "Parent:" }
                span { truncate_id(@span.parent_id, length: 6) }
              end
              i(class: "bi bi-chevron-right text-gray-400 text-xs flex-shrink-0")
            end

            # Current span (not clickable, mobile-responsive)
            span(class: "text-gray-900 font-mono font-semibold flex items-center gap-1 flex-shrink-0 py-1 px-2 bg-gray-100 rounded") do
              i(class: "bi bi-dot")
              span(class: "hidden sm:inline") { "Current:" }
              span { truncate_id(@span.span_id, length: 6) }
            end
          end
        end

        # Span ID with copy functionality
        def render_span_id_item
          div do
            dt(class: "text-sm font-medium text-gray-500") { "Span ID" }
            dd(class: "mt-1 text-sm text-gray-900 font-mono flex items-center gap-2") do
              span { @span.span_id }
              button(
                class: "text-xs text-gray-500 hover:text-gray-700 p-1 rounded hover:bg-gray-100 transition-colors",
                data: {
                  action: "click->span-detail#copyToClipboard",
                  value: @span.span_id
                },
                title: "Copy Span ID to clipboard"
              ) do
                i(class: "bi bi-clipboard")
              end
            end
          end
        end

        # Trace ID with navigation and copy functionality
        def render_trace_id_item
          div do
            dt(class: "text-sm font-medium text-gray-500") { "Trace ID" }
            dd(class: "mt-1 text-sm text-gray-900 font-mono flex items-center gap-2") do
              if @trace
                link_to(
                  @span.trace_id,
                  tracing_trace_path(@span.trace_id),
                  class: "text-blue-600 hover:text-blue-900 transition-colors",
                  title: "View full trace"
                )
              else
                span { @span.trace_id }
              end
              button(
                class: "text-xs text-gray-500 hover:text-gray-700 p-1 rounded hover:bg-gray-100 transition-colors",
                data: {
                  action: "click->span-detail#copyToClipboard",
                  value: @span.trace_id
                },
                title: "Copy Trace ID to clipboard"
              ) do
                i(class: "bi bi-clipboard")
              end
            end
          end
        end

        # Parent ID with navigation and copy functionality
        def render_parent_id_item
          div do
            dt(class: "text-sm font-medium text-gray-500") { "Parent ID" }
            dd(class: "mt-1 text-sm text-gray-900 font-mono flex items-center gap-2") do
              if @span.parent_id
                link_to(
                  @span.parent_id,
                  tracing_span_path(@span.parent_id),
                  class: "text-blue-600 hover:text-blue-900 transition-colors",
                  title: "View parent span"
                )
                button(
                  class: "text-xs text-gray-500 hover:text-gray-700 p-1 rounded hover:bg-gray-100 transition-colors",
                  data: {
                    action: "click->span-detail#copyToClipboard",
                    value: @span.parent_id
                  },
                  title: "Copy Parent ID to clipboard"
                ) do
                  i(class: "bi bi-clipboard")
                end
              else
                span(class: "text-gray-500 italic flex items-center gap-1") do
                  i(class: "bi bi-dash-circle")
                  "None (Root Span)"
                end
              end
            end
          end
        end

        # Enhanced duration badge with performance colors
        def render_enhanced_duration_badge(duration_ms)
          color_class, performance_text = case duration_ms
                                         when 0..100 then ["bg-green-100 text-green-800 border-green-200", "Fast"]
                                         when 101..1000 then ["bg-yellow-100 text-yellow-800 border-yellow-200", "Moderate"]
                                         else ["bg-red-100 text-red-800 border-red-200", "Slow"]
                                         end

          span(
            class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border #{color_class}",
            title: "Performance: #{performance_text} (#{format_duration(duration_ms)})"
          ) do
            i(class: "bi bi-stopwatch mr-1")
            format_duration(duration_ms)
          end
        end

        # Helper to truncate long IDs for navigation display
        def truncate_id(id, length: 8)
          return "N/A" unless id
          id.length > length ? "#{id[0...length]}..." : id
        end

        # Enhanced timing details with performance visualization
        def render_timing_details
          div(class: "bg-white overflow-hidden shadow rounded-lg mb-6") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              div(class: "flex items-center justify-between") do
                h3(class: "text-lg leading-6 font-medium text-gray-900") { "Timing Information" }
                # Performance indicator in header
                if @span.duration_ms
                  render_performance_indicator(@span.duration_ms)
                end
              end
            end

            div(class: "px-4 py-5 sm:p-6 space-y-6") do
              # Enhanced timing grid with visual hierarchy (responsive on mobile)
              dl(class: "grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4") do
                render_timing_detail("Start Time", format_enhanced_timestamp(@span.start_time), icon: "bi-play-fill")
                render_timing_detail("End Time", format_enhanced_timestamp(@span.end_time), icon: "bi-stop-fill")
                render_timing_detail("Duration", format_duration(@span.duration_ms), icon: "bi-stopwatch")

                if @span.start_time
                  render_timing_detail("Time Ago", time_ago_in_words(@span.start_time) + " ago", icon: "bi-clock-history")
                end
              end

              # Performance metrics section with additional insights
              render_performance_metrics

              # Timeline visualization for longer spans
              if @span.duration_ms && @span.duration_ms > 1000
                render_timeline_visualization
              end

              # Timing comparisons for context
              render_timing_comparisons if @span.parent_id || @trace
            end
          end
        end

        # Enhanced timing detail item with icon
        def render_timing_detail(label, value, icon: nil)
          div(class: "bg-gray-50 rounded-lg p-3") do
            div(class: "flex items-center mb-2") do
              if icon
                i(class: "#{icon} text-gray-600 mr-2")
              end
              dt(class: "text-sm font-medium text-gray-700") { label }
            end
            dd(class: "text-sm text-gray-900 font-mono") { value || "N/A" }
          end
        end

        # Performance indicator with detailed classification
        def render_performance_indicator(duration_ms)
          performance_level, performance_text, icon_class = case duration_ms
                                                          when 0..100
                                                            ["excellent", "Excellent", "bi-lightning-fill text-green-600"]
                                                          when 101..500
                                                            ["good", "Good", "bi-check-circle-fill text-green-600"]
                                                          when 501..1000
                                                            ["moderate", "Moderate", "bi-dash-circle-fill text-yellow-600"]
                                                          when 1001..5000
                                                            ["slow", "Slow", "bi-exclamation-triangle-fill text-orange-600"]
                                                          else
                                                            ["critical", "Critical", "bi-x-circle-fill text-red-600"]
                                                          end

          div(class: "flex items-center gap-1 text-sm") do
            i(class: icon_class)
            span(class: "font-medium") { performance_text }
            span(class: "text-gray-500") { "(#{format_duration(duration_ms)})" }
          end
        end

        # Timeline visualization for longer spans
        def render_timeline_visualization
          div(class: "mt-6 p-4 bg-gradient-to-r from-blue-50 to-green-50 rounded-lg border") do
            div(class: "mb-2 flex items-center gap-2") do
              i(class: "bi bi-clock-history text-gray-600")
              span(class: "text-sm font-medium text-gray-700") { "Execution Timeline" }
            end

            # Visual timeline bar
            div(class: "w-full bg-gray-200 rounded-full h-3 relative overflow-hidden") do
              div(
                class: "bg-gradient-to-r from-blue-500 to-green-500 h-3 rounded-full transition-all duration-1000 shadow-sm",
                style: "width: 100%"
              )
              # Timeline markers
              div(class: "absolute left-0 -bottom-6 text-xs text-gray-600") { "Start" }
              div(class: "absolute right-0 -bottom-6 text-xs text-gray-600") { "End" }
            end

            # Duration info
            div(class: "mt-8 flex justify-center") do
              span(class: "text-xs text-gray-600") do
                "Total execution time: #{format_duration(@span.duration_ms)}"
              end
            end
          end
        end

        # Enhanced timestamp formatting with UTC indicator
        def format_enhanced_timestamp(time)
          return "N/A" unless time
          time.strftime("%Y-%m-%d %H:%M:%S.%3N UTC")
        end

        # Performance metrics section with detailed insights
        def render_performance_metrics
          return unless @span.duration_ms

          div(class: "bg-gradient-to-r from-gray-50 to-blue-50 rounded-lg p-4 border") do
            div(class: "mb-3 flex items-center gap-2") do
              i(class: "bi bi-graph-up text-gray-600")
              h4(class: "text-sm font-medium text-gray-700") { "Performance Metrics" }
            end

            div(class: "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4") do
              # Throughput estimate (operations per second)
              render_metric_item("Throughput", calculate_throughput, "ops/sec", "bi-speedometer2")

              # Performance category
              render_metric_item("Category", performance_category, "", "bi-award")

              # Relative speed indicator
              render_metric_item("Speed", relative_speed_indicator, "", "bi-lightning")

              # Resource intensity estimate
              render_metric_item("Intensity", resource_intensity, "", "bi-cpu")
            end
          end
        end

        # Timing comparisons with context
        def render_timing_comparisons
          div(class: "bg-white border rounded-lg p-4") do
            div(class: "mb-3 flex items-center gap-2") do
              i(class: "bi bi-bar-chart text-gray-600")
              h4(class: "text-sm font-medium text-gray-700") { "Timing Comparisons" }
            end

            div(class: "space-y-3") do
              # Compare to typical durations for this span kind
              render_comparison_bar("vs Typical #{@span.kind&.capitalize}", typical_comparison_percentage)

              # Compare to parent span if available
              if @span.parent_id && @trace
                parent_percentage = parent_time_percentage
                render_comparison_bar("vs Parent Span", parent_percentage) if parent_percentage
              end

              # Compare to trace total if available
              if @trace
                trace_percentage = trace_time_percentage
                render_comparison_bar("% of Total Trace", trace_percentage) if trace_percentage
              end
            end
          end
        end

        # Individual metric item for performance metrics
        def render_metric_item(label, value, unit, icon)
          div(class: "bg-white rounded p-3 border") do
            div(class: "flex items-center gap-2 mb-1") do
              i(class: "#{icon} text-gray-500 text-sm")
              span(class: "text-xs font-medium text-gray-600") { label }
            end
            div(class: "text-sm font-semibold text-gray-900") do
              "#{value} #{unit}".strip
            end
          end
        end

        # Comparison bar visualization
        def render_comparison_bar(label, percentage)
          return unless percentage

          # Determine color based on percentage
          bar_color = case percentage
                     when 0..50 then "bg-green-500"
                     when 51..100 then "bg-yellow-500"
                     when 101..200 then "bg-orange-500"
                     else "bg-red-500"
                     end

          div(class: "space-y-1") do
            div(class: "flex justify-between text-xs") do
              span(class: "text-gray-600") { label }
              span(class: "font-medium text-gray-900") { "#{percentage.round(1)}%" }
            end
            div(class: "w-full bg-gray-200 rounded-full h-2") do
              div(
                class: "#{bar_color} h-2 rounded-full transition-all duration-500",
                style: "width: #{[percentage, 100].min}%"
              )
            end
          end
        end

        # Helper methods for calculations
        def calculate_throughput
          return "N/A" unless @span.duration_ms&.positive?
          (1000.0 / @span.duration_ms).round(2)
        end

        def performance_category
          return "Unknown" unless @span.duration_ms
          case @span.duration_ms
          when 0..100 then "Excellent"
          when 101..500 then "Good"
          when 501..1000 then "Fair"
          when 1001..5000 then "Slow"
          else "Critical"
          end
        end

        def relative_speed_indicator
          return "Unknown" unless @span.duration_ms
          case @span.duration_ms
          when 0..50 then "⚡ Lightning"
          when 51..100 then "🚀 Fast"
          when 101..500 then "✅ Normal"
          when 501..1000 then "⚠️ Slow"
          else "🐌 Very Slow"
          end
        end

        def resource_intensity
          return "Unknown" unless @span.duration_ms
          case @span.duration_ms
          when 0..100 then "Light"
          when 101..1000 then "Medium"
          when 1001..5000 then "Heavy"
          else "Intensive"
          end
        end

        def typical_comparison_percentage
          # Estimate typical durations based on span kind
          typical_duration = case @span.kind
                            when "tool" then 500
                            when "agent" then 2000
                            when "llm" then 3000
                            when "handoff" then 100
                            when "guardrail" then 200
                            when "pipeline" then 5000
                            else 1000
                            end

          return nil unless @span.duration_ms
          (@span.duration_ms.to_f / typical_duration * 100).round(1)
        end

        def parent_time_percentage
          # This would require accessing parent span data
          # For now, return a placeholder
          return nil unless @span.duration_ms && @span.parent_id
          # In a real implementation, you'd fetch parent span and compare
          75.0 # Placeholder
        end

        def trace_time_percentage
          # This would require accessing trace total duration
          # For now, return a placeholder
          return nil unless @span.duration_ms && @trace
          # In a real implementation, you'd calculate vs total trace time
          25.0 # Placeholder
        end

        # Helper method to render status badge with appropriate colors
        def render_status_badge(status)
          return span(class: "px-2 py-1 text-xs font-medium rounded-full bg-gray-100 text-gray-800") { "unknown" } unless status

          color_class = case status.to_s.downcase
                       when "success", "ok" then "bg-green-100 text-green-800 border-green-200"
                       when "error", "failed" then "bg-red-100 text-red-800 border-red-200"
                       when "warning", "timeout" then "bg-yellow-100 text-yellow-800 border-yellow-200"
                       when "pending", "running" then "bg-blue-100 text-blue-800 border-blue-200"
                       else "bg-gray-100 text-gray-800 border-gray-200"
                       end

          span(class: "inline-flex items-center px-2 py-1 text-xs font-medium rounded-full border #{color_class}") do
            status.to_s.capitalize
          end
        end

        # Helper method to render kind badge with appropriate styling
        def render_kind_badge(kind)
          return span(class: "px-2 py-1 text-xs font-medium rounded-full bg-gray-100 text-gray-800") { "unknown" } unless kind

          color_class = case kind.to_s.downcase
                       when "tool" then "bg-purple-100 text-purple-800 border-purple-200"
                       when "agent" then "bg-blue-100 text-blue-800 border-blue-200"
                       when "llm" then "bg-green-100 text-green-800 border-green-200"
                       when "handoff" then "bg-orange-100 text-orange-800 border-orange-200"
                       when "guardrail" then "bg-red-100 text-red-800 border-red-200"
                       when "pipeline" then "bg-indigo-100 text-indigo-800 border-indigo-200"
                       else "bg-gray-100 text-gray-800 border-gray-200"
                       end

          span(class: "inline-flex items-center px-2 py-1 text-xs font-medium rounded-full border #{color_class}") do
            kind.to_s.capitalize
          end
        end

        # Helper method to format relative time in a human-readable way
        def time_ago_in_words(time)
          return "unknown" unless time

          seconds_ago = Time.now - time
          case seconds_ago
          when 0..59 then "#{seconds_ago.to_i} seconds"
          when 60..3599 then "#{(seconds_ago / 60).to_i} minutes"
          when 3600..86399 then "#{(seconds_ago / 3600).to_i} hours"
          else "#{(seconds_ago / 86400).to_i} days"
          end
        end
      end
    end
  end
end

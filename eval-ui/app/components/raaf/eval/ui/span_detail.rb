# frozen_string_literal: true

module RAAF
  module Eval
    module UI
      # SpanDetail component displays comprehensive span information with three-section layout,
      # syntax-highlighted JSON, expandable tool calls and handoffs, timeline visualization,
      # and token/cost breakdown with copy-to-clipboard buttons.
      class SpanDetail < Phlex::HTML
        attr_reader :span, :show_timeline, :expanded

        def initialize(span:, show_timeline: true, expanded: false)
          @span = span
          @show_timeline = show_timeline
          @expanded = expanded
        end

        def template
          div(class: "span-detail bg-white rounded-lg shadow-lg overflow-hidden") do
            # Header with span metadata
            render_header

            # Three-section layout
            div(class: "grid grid-cols-1 lg:grid-cols-3 gap-6 p-6") do
              # Input section
              render_input_section

              # Output section
              render_output_section

              # Metadata section
              render_metadata_section
            end

            # Timeline visualization (if multi-turn)
            render_timeline if show_timeline && multi_turn_conversation?

            # Tool calls and handoffs (expandable)
            render_expandable_sections
          end
        end

        private

        def render_header
          div(class: "bg-gray-50 border-b border-gray-200 px-6 py-4") do
            div(class: "flex items-center justify-between") do
              div do
                h3(class: "text-lg font-semibold text-gray-900") do
                  text "Span Details: #{span.span_id}"
                end
                p(class: "mt-1 text-sm text-gray-600") do
                  text "#{span_type_label} • #{span.agent_name} • #{span.model}"
                end
              end

              div(class: "flex items-center space-x-2") do
                # Status badge
                span(class: status_badge_class) do
                  text status_label
                end

                # Copy span ID button
                button(
                  type: "button",
                  class: "px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700",
                  data: {
                    action: "click->clipboard#copy",
                    clipboard_text_value: span.span_id
                  }
                ) do
                  text "Copy ID"
                end
              end
            end
          end
        end

        def render_input_section
          div(class: "space-y-3") do
            h4(class: "text-sm font-semibold text-gray-700 uppercase tracking-wide") do
              text "Input"
            end

            div(class: "bg-gray-50 rounded-lg p-4 relative") do
              # Copy button
              button(
                type: "button",
                class: "absolute top-2 right-2 px-2 py-1 text-xs bg-white border border-gray-300 rounded hover:bg-gray-50",
                data: {
                  action: "click->clipboard#copy",
                  clipboard_text_value: input_content
                }
              ) do
                text "Copy"
              end

              # Syntax-highlighted input
              pre(class: "text-sm overflow-x-auto") do
                code(class: "language-json") do
                  text formatted_input
                end
              end
            end

            # Token count
            p(class: "text-xs text-gray-500") do
              text "#{input_token_count} tokens"
            end
          end
        end

        def render_output_section
          div(class: "space-y-3") do
            h4(class: "text-sm font-semibold text-gray-700 uppercase tracking-wide") do
              text "Output"
            end

            div(class: "bg-gray-50 rounded-lg p-4 relative") do
              # Copy button
              button(
                type: "button",
                class: "absolute top-2 right-2 px-2 py-1 text-xs bg-white border border-gray-300 rounded hover:bg-gray-50",
                data: {
                  action: "click->clipboard#copy",
                  clipboard_text_value: output_content
                }
              ) do
                text "Copy"
              end

              # Syntax-highlighted output
              pre(class: "text-sm overflow-x-auto") do
                code(class: "language-json") do
                  text formatted_output
                end
              end
            end

            # Token count
            p(class: "text-xs text-gray-500") do
              text "#{output_token_count} tokens"
            end
          end
        end

        def render_metadata_section
          div(class: "space-y-3") do
            h4(class: "text-sm font-semibold text-gray-700 uppercase tracking-wide") do
              text "Metadata"
            end

            div(class: "bg-gray-50 rounded-lg p-4 space-y-3") do
              # Token breakdown
              render_token_breakdown

              # Cost breakdown
              render_cost_breakdown

              # Performance metrics
              render_performance_metrics

              # Additional metadata
              render_additional_metadata
            end
          end
        end

        def render_token_breakdown
          div(class: "space-y-1") do
            p(class: "text-xs font-semibold text-gray-700") do
              text "Token Usage"
            end

            dl(class: "grid grid-cols-2 gap-2 text-xs") do
              dt(class: "text-gray-600") { text "Input:" }
              dd(class: "text-right text-gray-900 font-medium") { text input_token_count.to_s }

              dt(class: "text-gray-600") { text "Output:" }
              dd(class: "text-right text-gray-900 font-medium") { text output_token_count.to_s }

              dt(class: "text-gray-600 font-semibold") { text "Total:" }
              dd(class: "text-right text-gray-900 font-bold") { text total_token_count.to_s }
            end
          end
        end

        def render_cost_breakdown
          div(class: "space-y-1 pt-3 border-t border-gray-200") do
            p(class: "text-xs font-semibold text-gray-700") do
              text "Cost"
            end

            dl(class: "grid grid-cols-2 gap-2 text-xs") do
              dt(class: "text-gray-600") { text "Input:" }
              dd(class: "text-right text-gray-900 font-medium") { text "$#{format('%.4f', input_cost)}" }

              dt(class: "text-gray-600") { text "Output:" }
              dd(class: "text-right text-gray-900 font-medium") { text "$#{format('%.4f', output_cost)}" }

              dt(class: "text-gray-600 font-semibold") { text "Total:" }
              dd(class: "text-right text-gray-900 font-bold") { text "$#{format('%.4f', total_cost)}" }
            end
          end
        end

        def render_performance_metrics
          div(class: "space-y-1 pt-3 border-t border-gray-200") do
            p(class: "text-xs font-semibold text-gray-700") do
              text "Performance"
            end

            dl(class: "grid grid-cols-2 gap-2 text-xs") do
              dt(class: "text-gray-600") { text "Latency:" }
              dd(class: "text-right text-gray-900 font-medium") { text "#{latency_ms}ms" }

              dt(class: "text-gray-600") { text "TTFT:" }
              dd(class: "text-right text-gray-900 font-medium") { text "#{ttft_ms}ms" }
            end
          end
        end

        def render_additional_metadata
          div(class: "space-y-1 pt-3 border-t border-gray-200") do
            p(class: "text-xs font-semibold text-gray-700") do
              text "Additional Info"
            end

            dl(class: "space-y-1 text-xs") do
              dt(class: "text-gray-600") do
                text "Trace ID:"
              end
              dd(class: "text-gray-900 font-mono text-[10px] break-all") do
                text span.trace_id
              end

              dt(class: "text-gray-600 mt-2") do
                text "Created:"
              end
              dd(class: "text-gray-900") do
                text formatted_timestamp
              end
            end
          end
        end

        def render_timeline
          return unless messages.length > 2

          div(class: "border-t border-gray-200 px-6 py-4") do
            h4(class: "text-sm font-semibold text-gray-700 mb-4") do
              text "Conversation Timeline"
            end

            div(class: "space-y-3") do
              messages.each_with_index do |msg, idx|
                render_timeline_message(msg, idx)
              end
            end
          end
        end

        def render_timeline_message(msg, idx)
          role_class = msg[:role] == 'user' ? 'bg-blue-50 border-blue-200' : 'bg-green-50 border-green-200'

          div(class: "flex items-start space-x-3") do
            # Timeline indicator
            div(class: "flex flex-col items-center") do
              div(class: "w-3 h-3 rounded-full #{role_class.split.first.gsub('bg-', 'bg-')}") { }

              unless idx == messages.length - 1
                div(class: "w-0.5 h-full bg-gray-200 mt-2") { }
              end
            end

            # Message content
            div(class: "flex-1 #{role_class} border rounded-lg p-3") do
              p(class: "text-xs font-semibold text-gray-700 uppercase mb-1") do
                text msg[:role].capitalize
              end

              p(class: "text-sm text-gray-900") do
                text msg[:content].to_s[0..200]
                text "..." if msg[:content].to_s.length > 200
              end
            end
          end
        end

        def render_expandable_sections
          div(class: "border-t border-gray-200") do
            # Tool calls section
            render_tool_calls_section if tool_calls.any?

            # Handoffs section
            render_handoffs_section if handoffs.any?
          end
        end

        def render_tool_calls_section
          details(class: "border-b border-gray-200", open: expanded) do
            summary(class: "px-6 py-4 cursor-pointer hover:bg-gray-50 font-semibold text-sm text-gray-700") do
              text "Tool Calls (#{tool_calls.length})"
            end

            div(class: "px-6 py-4 bg-gray-50 space-y-3") do
              tool_calls.each do |tool_call|
                render_tool_call(tool_call)
              end
            end
          end
        end

        def render_tool_call(tool_call)
          div(class: "bg-white rounded-lg p-4 border border-gray-200") do
            div(class: "flex items-center justify-between mb-2") do
              p(class: "font-semibold text-sm text-gray-900") do
                text tool_call[:name] || 'Unknown Tool'
              end

              span(class: "text-xs px-2 py-1 bg-blue-100 text-blue-800 rounded") do
                text "Tool Call"
              end
            end

            # Arguments
            if tool_call[:arguments]
              p(class: "text-xs text-gray-600 mb-1") { text "Arguments:" }
              pre(class: "text-xs bg-gray-50 rounded p-2 overflow-x-auto") do
                code(class: "language-json") do
                  text JSON.pretty_generate(tool_call[:arguments])
                end
              end
            end

            # Result
            if tool_call[:result]
              p(class: "text-xs text-gray-600 mb-1 mt-2") { text "Result:" }
              pre(class: "text-xs bg-gray-50 rounded p-2 overflow-x-auto") do
                code do
                  text tool_call[:result].to_s[0..200]
                  text "..." if tool_call[:result].to_s.length > 200
                end
              end
            end
          end
        end

        def render_handoffs_section
          details(class: "border-b border-gray-200", open: expanded) do
            summary(class: "px-6 py-4 cursor-pointer hover:bg-gray-50 font-semibold text-sm text-gray-700") do
              text "Handoffs (#{handoffs.length})"
            end

            div(class: "px-6 py-4 bg-gray-50 space-y-3") do
              handoffs.each do |handoff|
                render_handoff(handoff)
              end
            end
          end
        end

        def render_handoff(handoff)
          div(class: "bg-white rounded-lg p-4 border border-gray-200") do
            div(class: "flex items-center justify-between mb-2") do
              p(class: "font-semibold text-sm text-gray-900") do
                text "→ #{handoff[:to_agent] || 'Unknown Agent'}"
              end

              span(class: "text-xs px-2 py-1 bg-purple-100 text-purple-800 rounded") do
                text "Handoff"
              end
            end

            if handoff[:context]
              p(class: "text-xs text-gray-600 mb-1") { text "Context:" }
              pre(class: "text-xs bg-gray-50 rounded p-2 overflow-x-auto") do
                code(class: "language-json") do
                  text JSON.pretty_generate(handoff[:context])
                end
              end
            end
          end
        end

        # Helper methods

        def span_type_label
          span.span_type&.capitalize || 'Unknown'
        end

        def status_label
          span_data.dig('status') || 'Completed'
        end

        def status_badge_class
          base = "px-3 py-1 text-xs font-semibold rounded-full"
          case status_label.downcase
          when 'completed', 'success'
            "#{base} bg-green-100 text-green-800"
          when 'failed', 'error'
            "#{base} bg-red-100 text-red-800"
          else
            "#{base} bg-gray-100 text-gray-800"
          end
        end

        def span_data
          @span_data ||= span.span_data || {}
        end

        def messages
          @messages ||= span_data['output_messages'] || span_data['input_messages'] || []
        end

        def tool_calls
          @tool_calls ||= span_data['tool_calls'] || []
        end

        def handoffs
          @handoffs ||= span_data['handoffs'] || []
        end

        def input_content
          if span_data['input_messages']
            JSON.pretty_generate(span_data['input_messages'])
          else
            span_data['input']&.to_s || ''
          end
        end

        def output_content
          if span_data['output_messages']
            JSON.pretty_generate(span_data['output_messages'])
          else
            span_data['output']&.to_s || ''
          end
        end

        def formatted_input
          input_content
        end

        def formatted_output
          output_content
        end

        def input_token_count
          span_data.dig('metadata', 'tokens', 'input') || 0
        end

        def output_token_count
          span_data.dig('metadata', 'tokens', 'output') || 0
        end

        def total_token_count
          span_data.dig('metadata', 'tokens', 'total') || (input_token_count + output_token_count)
        end

        def input_cost
          span_data.dig('metadata', 'cost', 'input') || 0.0
        end

        def output_cost
          span_data.dig('metadata', 'cost', 'output') || 0.0
        end

        def total_cost
          span_data.dig('metadata', 'cost', 'total') || span_data.dig('metadata', 'cost') || 0.0
        end

        def latency_ms
          span_data.dig('metadata', 'latency_ms') || 0
        end

        def ttft_ms
          span_data.dig('metadata', 'ttft_ms') || 0
        end

        def formatted_timestamp
          span.created_at&.strftime('%Y-%m-%d %H:%M:%S UTC') || 'Unknown'
        end

        def multi_turn_conversation?
          messages.length > 2
        end
      end
    end
  end
end

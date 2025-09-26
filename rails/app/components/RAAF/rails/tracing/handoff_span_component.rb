# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class HandoffSpanComponent < SpanDetailBase
        def view_template
          div(class: "space-y-6") do
            render_handoff_overview
            render_agent_transfer_flow
            render_context_transfer if context_transfer_data.present?
            render_handoff_reason if handoff_reason.present?
            render_error_handling
          end
        end

        private

        def source_agent
          @source_agent ||= extract_span_attribute("handoff.source_agent") ||
                           extract_span_attribute("source_agent") ||
                           extract_span_attribute("from_agent") ||
                           "Unknown Source Agent"
        end

        def target_agent
          @target_agent ||= extract_span_attribute("handoff.target_agent") ||
                           extract_span_attribute("target_agent") ||
                           extract_span_attribute("to_agent") ||
                           "Unknown Target Agent"
        end

        def handoff_reason
          @handoff_reason ||= extract_span_attribute("handoff.reason") ||
                             extract_span_attribute("reason") ||
                             extract_span_attribute("transfer_reason")
        end

        def context_transfer_data
          @context_transfer_data ||= extract_span_attribute("handoff.context") ||
                                    extract_span_attribute("context_transfer") ||
                                    extract_span_attribute("transferred_context")
        end

        def handoff_metadata
          @handoff_metadata ||= {
            "handoff_type" => extract_span_attribute("handoff.type") || extract_span_attribute("handoff_type"),
            "timestamp" => extract_span_attribute("handoff.timestamp") || @span.start_time,
            "success" => extract_span_attribute("handoff.success") || (@span.status == "success"),
            "conversation_id" => extract_span_attribute("handoff.conversation_id") || extract_span_attribute("conversation_id")
          }.compact
        end

        def render_handoff_overview
          render_span_overview_header(
            "bi bi-arrow-left-right", 
            "Agent Handoff", 
            "#{source_agent} → #{target_agent}"
          )
        end

        def render_agent_transfer_flow
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg font-semibold text-gray-900") { "Transfer Details" }
            end
            div(class: "px-4 py-5 sm:p-6") do
              # Visual flow representation
              div(class: "flex items-center justify-center mb-6 p-4 bg-gray-50 rounded-lg") do
                # Source agent
                div(class: "flex flex-col items-center text-center") do
                  div(class: "w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center mb-2") do
                    i(class: "bi bi-robot text-blue-600 text-lg")
                  end
                  div(class: "text-sm font-medium text-gray-900") { source_agent }
                  div(class: "text-xs text-gray-500") { "Source" }
                end
                
                # Arrow
                div(class: "mx-6 flex flex-col items-center") do
                  i(class: "bi bi-arrow-right text-gray-400 text-2xl")
                  if handoff_metadata["success"]
                    div(class: "text-xs text-green-600 mt-1") { "Success" }
                  else
                    div(class: "text-xs text-red-600 mt-1") { "Failed" }
                  end
                end
                
                # Target agent
                div(class: "flex flex-col items-center text-center") do
                  div(class: "w-12 h-12 bg-green-100 rounded-full flex items-center justify-center mb-2") do
                    i(class: "bi bi-robot text-green-600 text-lg")
                  end
                  div(class: "text-sm font-medium text-gray-900") { target_agent }
                  div(class: "text-xs text-gray-500") { "Target" }
                end
              end
              
              # Handoff metadata
              dl(class: "grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2") do
                render_detail_item("Source Agent", source_agent)
                render_detail_item("Target Agent", target_agent)
                render_detail_item("Handoff Status", render_status_badge(@span.status))
                render_detail_item("Duration", render_duration_badge(@span.duration_ms))
                
                if handoff_metadata["handoff_type"]
                  render_detail_item("Handoff Type", handoff_metadata["handoff_type"].to_s.humanize)
                end
                
                if handoff_metadata["conversation_id"]
                  render_detail_item("Conversation ID", handoff_metadata["conversation_id"], monospace: true)
                end
                
                if handoff_metadata["timestamp"]
                  render_detail_item("Transfer Time", format_timestamp(handoff_metadata["timestamp"]))
                end
              end
            end
          end
        end

        def render_context_transfer
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-purple-200 bg-purple-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-database text-purple-600 text-lg")
                h3(class: "text-lg font-semibold text-purple-900") { "Context Transfer" }
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              case context_transfer_data
              when Hash
                # Show context keys/summary first
                div(class: "mb-4 p-3 bg-purple-50 rounded-lg") do
                  div(class: "text-sm font-medium text-purple-900 mb-2") { "Transferred Context Summary" }
                  div(class: "flex flex-wrap gap-2") do
                    context_transfer_data.keys.each do |key|
                      span(class: "px-2 py-1 text-xs bg-purple-100 text-purple-700 rounded") { key.to_s.humanize }
                    end
                  end
                end
                
                # Full context data (collapsible)
                render_json_section("Full Context Data", context_transfer_data, collapsed: true)
              else
                render_json_section("Context Data", context_transfer_data, collapsed: false)
              end
            end
          end
        end

        def render_handoff_reason
          div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
            div(class: "px-4 py-5 sm:px-6 border-b border-orange-200 bg-orange-50") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-chat-square-text text-orange-600 text-lg")
                h3(class: "text-lg font-semibold text-orange-900") { "Handoff Reason" }
              end
            end
            div(class: "px-4 py-5 sm:p-6") do
              case handoff_reason
              when String
                if handoff_reason.length > 200
                  render_expandable_text(handoff_reason, "reason")
                else
                  div(class: "bg-orange-50 p-3 rounded border text-sm") do
                    plain handoff_reason
                  end
                end
              when Hash, Array
                render_json_section("Reason Data", handoff_reason, collapsed: false)
              else
                div(class: "bg-orange-50 p-3 rounded border text-sm") do
                  plain handoff_reason.to_s
                end
              end
            end
          end
        end

        def render_expandable_text(text, prefix)
          text_id = "#{prefix}-#{@span.span_id}"
          preview_text = text[0..200] + "..."
          
          div(data: { controller: "span-detail" }) do
            div(id: "#{text_id}-preview", class: "bg-orange-50 p-3 rounded border text-sm") do
              plain preview_text
            end
            div(id: text_id, class: "hidden bg-orange-50 p-3 rounded border text-sm") do
              plain text
            end
            button(
              class: "mt-2 text-sm text-orange-600 hover:text-orange-800 px-2 py-1 hover:bg-orange-50 rounded transition-colors",
              data: {
                action: "click->span-detail#toggleSection",
                target: text_id
              }
            ) { "Show Full Text" }
          end
        end
      end
    end
  end
end

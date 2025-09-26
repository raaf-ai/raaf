# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module SpanDetail
        # GuardrailSpanComponent displays security filter results and reasoning
        # for guardrail spans, showing blocked content, security policies,
        # and filter decision details.
        class GuardrailSpanComponent < RAAF::Rails::Tracing::SpanDetailBase
          def initialize(span:, **options)
            @span = span
            super(**options)
          end

          def view_template
            div(class: "space-y-6", data: { controller: "span-detail" }) do
              render_guardrail_overview
              render_filter_results if filter_results.present?
              render_security_reasoning if security_reasoning.present?
              render_policy_details if policy_applied.present?
              render_blocked_content if blocked_content.present?
              render_raw_attributes if debug_mode?
            end
          end

          private

          def render_guardrail_overview
            div(class: "bg-orange-50 border border-orange-200 rounded-lg p-4") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-shield-exclamation text-orange-600 text-xl")
                div(class: "flex-1") do
                  h3(class: "text-lg font-semibold text-orange-900") { "Security Guardrail" }
                  p(class: "text-sm text-orange-700") do
                    "Filter: #{filter_name} | Status: #{filter_status} | Policy: #{policy_applied || 'Default'}"
                  end
                end
                render_security_status_badge
              end
            end
          end

          def render_security_status_badge
            color_classes = case filter_status.to_s.downcase
                           when "blocked", "denied" then "bg-red-100 text-red-800 border-red-200"
                           when "allowed", "passed" then "bg-green-100 text-green-800 border-green-200"
                           when "flagged", "warning" then "bg-yellow-100 text-yellow-800 border-yellow-200"
                           else "bg-gray-100 text-gray-800 border-gray-200"
                           end

            span(class: "px-3 py-1 text-sm font-medium rounded-full border #{color_classes}") do
              filter_status.to_s.titleize
            end
          end

          def render_filter_results
            div(class: "bg-white border border-gray-200 rounded-lg shadow") do
              render_collapsible_header("Filter Results", "filter-results", "bi-funnel")
              div(id: "filter-results-content", class: "p-4 border-t border-gray-200") do
                if filter_results.is_a?(Hash)
                  render_filter_results_table
                else
                  render_json_content(filter_results, "filter-results-data")
                end
              end
            end
          end

          def render_filter_results_table
            div(class: "overflow-x-auto") do
              table(class: "min-w-full divide-y divide-gray-200") do
                thead(class: "bg-gray-50") do
                  tr do
                    th(class: "px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase") { "Check" }
                    th(class: "px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase") { "Result" }
                    th(class: "px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase") { "Score" }
                    th(class: "px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase") { "Details" }
                  end
                end
                tbody(class: "bg-white divide-y divide-gray-200") do
                  filter_results.each do |check, result|
                    render_filter_result_row(check, result)
                  end
                end
              end
            end
          end

          def render_filter_result_row(check, result)
            tr(class: "hover:bg-gray-50") do
              td(class: "px-3 py-2 text-sm font-medium text-gray-900") { check.to_s.humanize }
              td(class: "px-3 py-2 text-sm") do
                if result.is_a?(Hash)
                  render_filter_status_badge(result["status"] || result[:status])
                else
                  span(class: "text-gray-900") { result.to_s }
                end
              end
              td(class: "px-3 py-2 text-sm") do
                if result.is_a?(Hash) && (result["score"] || result[:score])
                  score = result["score"] || result[:score]
                  render_confidence_score(score)
                else
                  span(class: "text-gray-400") { "—" }
                end
              end
              td(class: "px-3 py-2 text-sm text-gray-600") do
                if result.is_a?(Hash) && (result["details"] || result[:details])
                  truncate(result["details"] || result[:details], length: 60)
                else
                  span(class: "text-gray-400") { "—" }
                end
              end
            end
          end

          def render_filter_status_badge(status)
            return unless status

            color_classes = case status.to_s.downcase
                           when "pass", "allowed" then "bg-green-100 text-green-800"
                           when "fail", "blocked" then "bg-red-100 text-red-800"
                           when "warn", "flagged" then "bg-yellow-100 text-yellow-800"
                           else "bg-gray-100 text-gray-800"
                           end

            span(class: "px-2 py-1 text-xs font-medium rounded #{color_classes}") do
              status.to_s.upcase
            end
          end

          def render_confidence_score(score)
            score_val = score.is_a?(Numeric) ? score : score.to_f
            color_classes = case score_val
                           when 0.0..0.3 then "text-green-700"
                           when 0.3..0.7 then "text-yellow-700"
                           else "text-red-700"
                           end

            span(class: "font-mono text-sm #{color_classes}") do
              "#{(score_val * 100).round(1)}%"
            end
          end

          def render_security_reasoning
            div(class: "bg-white border border-gray-200 rounded-lg shadow") do
              render_collapsible_header("Security Reasoning", "security-reasoning", "bi-brain")
              div(id: "security-reasoning-content", class: "p-4 border-t border-gray-200") do
                if security_reasoning.is_a?(String)
                  div(class: "prose prose-sm max-w-none text-gray-700") do
                    simple_format(security_reasoning)
                  end
                else
                  render_json_content(security_reasoning, "security-reasoning-data")
                end
              end
            end
          end

          def render_policy_details
            div(class: "bg-white border border-gray-200 rounded-lg shadow") do
              render_collapsible_header("Policy Applied", "policy-details", "bi-file-earmark-text")
              div(id: "policy-details-content", class: "p-4 border-t border-gray-200") do
                if policy_applied.is_a?(Hash)
                  render_policy_details_table
                else
                  div(class: "text-sm text-gray-700") do
                    policy_applied.to_s
                  end
                end
              end
            end
          end

          def render_policy_details_table
            dl(class: "space-y-3") do
              policy_applied.each do |key, value|
                render_detail_item(key.to_s.humanize, value)
              end
            end
          end

          def render_blocked_content
            div(class: "bg-red-50 border border-red-200 rounded-lg shadow") do
              render_collapsible_header("Blocked Content", "blocked-content", "bi-exclamation-triangle", expanded: false)
              div(id: "blocked-content-content", class: "p-4 border-t border-red-200 hidden") do
                div(class: "bg-red-100 p-3 rounded border border-red-200 mb-3") do
                  p(class: "text-xs text-red-700 font-medium mb-2") { "⚠️ SENSITIVE CONTENT - Handle with care" }
                  if blocked_content.is_a?(Hash) && blocked_content["sanitized"]
                    p(class: "text-sm text-red-800") { "Content has been sanitized for display." }
                  end
                end
                render_json_content(blocked_content, "blocked-content-data")
              end
            end
          end

          def render_raw_attributes
            return unless @span.span_attributes&.any?

            div(class: "bg-gray-50 border border-gray-200 rounded-lg shadow") do
              render_collapsible_header("Debug: Raw Attributes", "raw-attributes", "bi-code-square", expanded: false)
              div(id: "raw-attributes-content", class: "p-4 border-t border-gray-200 hidden") do
                render_json_content(@span.span_attributes, "raw-attributes-data")
              end
            end
          end

          def render_collapsible_header(title, section_id, icon_class, expanded: true)
            button(
              class: "w-full flex items-center justify-between p-4 text-left hover:bg-gray-50 focus:outline-none focus:bg-gray-50",
              data: {
                action: "click->span-detail#toggleSection",
                target: section_id
              }
            ) do
              div(class: "flex items-center gap-3") do
                i(class: "#{icon_class} text-gray-600 text-lg")
                h4(class: "text-md font-semibold text-gray-900") { title }
              end
              i(class: "bi #{expanded ? 'bi-chevron-down' : 'bi-chevron-right'} text-gray-400")
            end
          end

          def render_json_content(data, element_id)
            div(class: "bg-gray-50 border border-gray-200 rounded", data: { controller: "json-highlight" }) do
              div(class: "flex items-center justify-between p-2 bg-gray-100 border-b border-gray-200") do
                span(class: "text-xs font-medium text-gray-600") { "JSON Data" }
                button(
                  class: "text-xs text-blue-600 hover:text-blue-800 px-2 py-1 hover:bg-blue-50 rounded",
                  data: { action: "click->span-detail#copyJson", target: element_id }
                ) { "Copy" }
              end
              pre(
                id: element_id,
                class: "p-3 text-xs text-gray-700 overflow-x-auto whitespace-pre-wrap",
                data: { json_highlight_target: "json" }
              ) do
                format_json_display(data)
              end
            end
          end

          def render_detail_item(label, value)
            div(class: "flex items-start justify-between py-2 border-b border-gray-200 last:border-b-0") do
              dt(class: "text-sm font-medium text-gray-600 w-1/3") { label }
              dd(class: "text-sm text-gray-900 w-2/3 break-words") do
                case value
                when String
                  value.length > 100 ? truncate(value, length: 100) : value
                when Numeric
                  span(class: "font-mono") { value.to_s }
                when TrueClass, FalseClass
                  span(class: "font-mono px-1 py-0.5 text-xs rounded #{value ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}") { value.to_s }
                when Array
                  span(class: "text-gray-500 italic") { "Array (#{value.length} items)" }
                when Hash
                  span(class: "text-gray-500 italic") { "Object (#{value.keys.length} keys)" }
                else
                  value.to_s
                end
              end
            end
          end

          # Data extraction methods
          def filter_name
            @filter_name ||= @span.span_attributes&.dig("guardrail", "filter_name") ||
                            @span.span_attributes&.dig("filter", "name") ||
                            @span.name ||
                            "Unknown Filter"
          end

          def filter_status
            @filter_status ||= @span.span_attributes&.dig("guardrail", "status") ||
                              @span.span_attributes&.dig("filter", "status") ||
                              @span.status ||
                              "unknown"
          end

          def filter_results
            @filter_results ||= @span.span_attributes&.dig("guardrail", "results") ||
                               @span.span_attributes&.dig("filter", "results") ||
                               @span.span_attributes&.dig("results") ||
                               {}
          end

          def security_reasoning
            @security_reasoning ||= @span.span_attributes&.dig("guardrail", "reasoning") ||
                                   @span.span_attributes&.dig("filter", "reasoning") ||
                                   @span.span_attributes&.dig("security_reasoning") ||
                                   @span.span_attributes&.dig("reasoning")
          end

          def policy_applied
            @policy_applied ||= @span.span_attributes&.dig("guardrail", "policy") ||
                               @span.span_attributes&.dig("policy") ||
                               @span.span_attributes&.dig("security_policy")
          end

          def blocked_content
            @blocked_content ||= @span.span_attributes&.dig("guardrail", "blocked_content") ||
                                @span.span_attributes&.dig("blocked_content") ||
                                @span.span_attributes&.dig("filtered_content")
          end

          def debug_mode?
            @span.span_attributes&.dig("debug") == true ||
            ENV["RAAF_DEBUG"] == "true" ||
            ::Rails.env.development?
          end

          def format_json_display(data)
            return "N/A" if data.nil? || data.empty?

            case data
            when String
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
          rescue StandardError => e
            "Error formatting data: #{e.message}"
          end

          def truncate(text, length: 100)
            return text unless text.is_a?(String) && text.length > length
            "#{text[0, length]}..."
          end

          def simple_format(text)
            return "" unless text.is_a?(String)
            text.gsub(/\n/, "<br>").html_safe
          end
        end
      end
    end
  end
end
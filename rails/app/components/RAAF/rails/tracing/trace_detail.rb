# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class TraceDetail < Phlex::HTML
        include Phlex::Rails::Helpers::LinkTo
        include Phlex::Rails::Helpers::TimeAgoInWords
        include Phlex::Rails::Helpers::Pluralize
        include Phlex::Rails::Helpers::Routes

      def initialize(trace:)
        @trace = trace
      end

      def view_template
        div(class: "min-h-screen bg-gray-50") do
          div(class: "p-6 space-y-8") do
            render_header
            render_trace_overview
            render_performance_insights
            render_agent_configuration
            render_spans_hierarchy
          end
        end
      end

      private

      def render_header
        div(class: "bg-white rounded-lg shadow-sm border border-gray-200") do
          div(class: "p-6") do
            div(class: "flex justify-between items-start") do
              div(class: "flex-1") do
                div(class: "flex items-center gap-3 mb-3") do
                  div(class: "p-2 bg-gray-100 rounded-lg") do
                    i(class: "bi bi-diagram-3 text-gray-600 text-lg")
                  end
                  div do
                    h1(class: "text-2xl font-semibold text-gray-900 mb-1") { @trace.workflow_name }

                    # Get skip reasons summary for traces that have skipped spans
                    skip_reason = if @trace.respond_to?(:skip_reasons_summary)
                                    begin
                                      @trace.skip_reasons_summary
                                    rescue StandardError => e
                                      Rails.logger.warn "Failed to get skip_reasons_summary for trace #{@trace.trace_id}: #{e.message}"
                                      nil
                                    end
                                  end

                    render_status_badge(@trace.status, skip_reason: skip_reason)
                  end
                end

                div(class: "flex items-center gap-6 text-sm text-gray-600") do
                  div(class: "flex items-center gap-2") do
                    i(class: "bi bi-fingerprint text-gray-400")
                    span(class: "font-mono") { @trace.trace_id }
                  end
                  div(class: "flex items-center gap-2") do
                    i(class: "bi bi-clock text-gray-400")
                    span { "#{time_ago_in_words(@trace.started_at)} ago" }
                  end
                  div(class: "flex items-center gap-2") do
                    i(class: "bi bi-calendar text-gray-400")
                    span { @trace.started_at.strftime("%B %d, %Y at %I:%M %p") }
                  end
                end
              end

              div(class: "flex gap-3") do
                div(
                  class: "px-3 py-2 bg-gray-50 hover:bg-gray-100 text-gray-700 rounded border border-gray-200 transition-colors duration-200 flex items-center gap-2 cursor-pointer select-all",
                  title: "Click to select trace ID"
                ) do
                  i(class: "bi bi-fingerprint text-sm")
                  span(class: "font-mono text-sm") { @trace.trace_id }
                end

                link_to(
                  "/raaf/tracing/traces",
                  class: "px-3 py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded border border-gray-200 transition-colors duration-200 flex items-center gap-2"
                ) do
                  i(class: "bi bi-arrow-left text-sm")
                  span { "Back to Traces" }
                end
              end
            end
          end
        end
      end

      def render_trace_overview
        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4") do
          # Duration Card
          div(class: "bg-white rounded-lg p-4 shadow-sm border border-gray-200") do
            div(class: "flex items-center justify-between mb-3") do
              div(class: "p-2 bg-gray-100 rounded") do
                i(class: "bi bi-stopwatch text-gray-600")
              end
              span(class: "text-xs text-gray-500 font-medium") { "DURATION" }
            end
            div(class: "text-xl font-semibold text-gray-900 mb-1") { format_duration(@trace.duration_ms) }
            div(class: "text-sm text-gray-500") { "Total execution time" }
          end

          # Spans Card
          div(class: "bg-white rounded-lg p-4 shadow-sm border border-gray-200") do
            div(class: "flex items-center justify-between mb-3") do
              div(class: "p-2 bg-gray-100 rounded") do
                i(class: "bi bi-collection text-gray-600")
              end
              span(class: "text-xs text-gray-500 font-medium") { "SPANS" }
            end
            div(class: "text-xl font-semibold text-gray-900 mb-1") { @trace.spans.count.to_s }
            div(class: "text-sm text-gray-500") do
              "#{@trace.spans.errors.count} errors" if @trace.spans.errors.any?
              "All successful" if @trace.spans.errors.empty?
            end
          end

          # Performance Card
          div(class: "bg-white rounded-lg p-4 shadow-sm border border-gray-200") do
            div(class: "flex items-center justify-between mb-3") do
              div(class: "p-2 bg-gray-100 rounded") do
                i(class: "bi bi-speedometer2 text-gray-600")
              end
              span(class: "text-xs text-gray-500 font-medium") { "PERFORMANCE" }
            end
            div(class: "text-xl font-semibold text-gray-900 mb-1") do
              if @trace.duration_ms && @trace.duration_ms < 1000
                "Fast"
              elsif @trace.duration_ms && @trace.duration_ms < 5000
                "Good"
              else
                "Slow"
              end
            end
            div(class: "text-sm text-gray-500") { "Execution speed" }
          end

          # Success Rate Card
          div(class: "bg-white rounded-lg p-4 shadow-sm border border-gray-200") do
            div(class: "flex items-center justify-between mb-3") do
              div(class: "p-2 bg-gray-100 rounded") do
                i(class: "bi bi-graph-up text-gray-600")
              end
              span(class: "text-xs text-gray-500 font-medium") { "SUCCESS RATE" }
            end
            div(class: "text-xl font-semibold text-gray-900 mb-1") do
              if @trace.spans.any?
                success_rate = ((@trace.spans.count - @trace.spans.errors.count).to_f / @trace.spans.count * 100).round(1)
                "#{success_rate}%"
              else
                "N/A"
              end
            end
            div(class: "text-sm text-gray-500") { "Operations completed" }
          end
        end

        if @trace.metadata.present?
          div(class: "mt-6 bg-white rounded-lg shadow-sm border border-gray-200") do
            div(class: "p-4 border-b border-gray-200") do
              div(class: "flex items-center gap-3") do
                div(class: "p-2 bg-gray-100 rounded") do
                  i(class: "bi bi-code-square text-gray-600")
                end
                h3(class: "text-lg font-semibold text-gray-900") { "Trace Metadata" }
              end
            end
            div(class: "p-4") do
              pre(class: "text-sm text-gray-700 bg-gray-50 rounded p-3 overflow-auto border border-gray-200") do
                code { JSON.pretty_generate(@trace.metadata) }
              end
            end
          end
        end
      end

      def render_performance_insights
        return unless @trace.spans.any?

        div(class: "bg-white rounded-lg shadow-sm border border-gray-200") do
          div(class: "p-4 border-b border-gray-200") do
            div(class: "flex items-center gap-3") do
              div(class: "p-2 bg-gray-100 rounded") do
                i(class: "bi bi-lightning text-gray-600")
              end
              h3(class: "text-lg font-semibold text-gray-900") { "Performance Insights" }
            end
          end

          div(class: "p-4") do
            div(class: "grid grid-cols-1 md:grid-cols-3 gap-4") do
              # Slowest span
              slowest = @trace.spans.max_by(&:duration_ms)
              if slowest
                div(class: "p-3 bg-gray-50 rounded border border-gray-200") do
                  div(class: "flex items-center gap-2 mb-2") do
                    i(class: "bi bi-clock-history text-gray-600")
                    span(class: "text-sm font-medium text-gray-800") { "Slowest Operation" }
                  end
                  div(class: "text-sm text-gray-700 mb-1 font-medium") { slowest.name }
                  div(class: "text-xs text-gray-600") { format_duration(slowest.duration_ms) }
                end
              end

              # Most common span type
              span_types = @trace.spans.group_by(&:kind).transform_values(&:count)
              most_common = span_types.max_by { |_, count| count }
              if most_common
                div(class: "p-3 bg-gray-50 rounded border border-gray-200") do
                  div(class: "flex items-center gap-2 mb-2") do
                    i(class: "bi bi-pie-chart text-gray-600")
                    span(class: "text-sm font-medium text-gray-800") { "Most Common Type" }
                  end
                  div(class: "text-sm text-gray-700 mb-1 font-medium") { most_common[0].capitalize }
                  div(class: "text-xs text-gray-600") { "#{most_common[1]} operations" }
                end
              end

              # Average duration
              avg_duration = @trace.spans.filter_map(&:duration_ms).sum.to_f / @trace.spans.count if @trace.spans.any?
              if avg_duration
                div(class: "p-3 bg-gray-50 rounded border border-gray-200") do
                  div(class: "flex items-center gap-2 mb-2") do
                    i(class: "bi bi-speedometer text-gray-600")
                    span(class: "text-sm font-medium text-gray-800") { "Average Duration" }
                  end
                  div(class: "text-sm text-gray-700 mb-1 font-medium") { format_duration(avg_duration) }
                  div(class: "text-xs text-gray-600") { "Per operation" }
                end
              end
            end
          end
        end
      end

      def render_agent_configuration
        # Agent configuration is now shown only in the Execution Timeline
        # This method intentionally does nothing to avoid duplication
      end

      def render_spans_hierarchy
        div(class: "bg-white rounded-lg shadow-sm border border-gray-200") do
          div(class: "p-4 border-b border-gray-200") do
            div(class: "flex items-center justify-between") do
              div(class: "flex items-center gap-3") do
                div(class: "p-2 bg-gray-100 rounded") do
                  i(class: "bi bi-diagram-2 text-gray-600")
                end
                div do
                  h3(class: "text-lg font-semibold text-gray-900") { "Execution Timeline" }
                  p(class: "text-sm text-gray-500") { "Hierarchical view of all operations and their relationships" }
                end
              end

              div(class: "flex gap-2") do
                span(class: "px-2 py-1 bg-gray-100 text-gray-600 text-xs rounded font-medium") { "#{@trace.spans.count} spans" }
                if @trace.spans.errors.any?
                  span(class: "px-2 py-1 bg-gray-200 text-gray-700 text-xs rounded font-medium") { "#{@trace.spans.errors.count} errors" }
                end
              end
            end
          end

          div(class: "p-4") do
            if @trace.spans.any?
              div(id: "span-hierarchy", class: "space-y-3") do
                render_span_tree(@trace.spans)
              end
            else
              div(class: "text-center py-12") do
                div(class: "p-4 bg-gray-100 rounded-full w-16 h-16 mx-auto mb-4 flex items-center justify-center") do
                  i(class: "bi bi-clock text-gray-400 text-2xl")
                end
                h4(class: "text-lg font-medium text-gray-900 mb-2") { "No spans found" }
                p(class: "text-gray-500") { "This trace doesn't contain any execution spans." }
              end
            end
          end
        end
      end

      def render_agent_details_section(agent_span)
        return unless agent_span&.span_attributes

        div(class: "bg-white rounded-lg shadow-sm border border-gray-200 mt-6") do
          div(class: "p-4 border-b border-gray-200") do
            div(class: "flex items-center gap-3") do
              div(class: "p-2 bg-gray-100 rounded") do
                i(class: "bi bi-robot text-gray-600")
              end
              div do
                h3(class: "text-lg font-semibold text-gray-900") { "Agent Configuration" }
                p(class: "text-sm text-gray-500") { "Detailed configuration and capabilities" }
              end
            end
          end

          div(class: "p-4") do
            render_enhanced_agent_details(agent_span.span_attributes)
          end
        end
      end

      def render_enhanced_agent_details(attributes)
        # Main agent information
        div(class: "space-y-4") do
          # Core Configuration
          div do
            h4(class: "text-sm font-semibold text-gray-900 mb-2 flex items-center gap-2") do
              i(class: "bi bi-gear-fill text-gray-600")
              span { "Core Configuration" }
            end

            div(class: "grid grid-cols-1 md:grid-cols-3 lg:grid-cols-6 gap-3") do
              render_config_card("Agent Name", attributes["agent.name"], "bi-tag-fill", "blue")
              render_config_card("Model", attributes["agent.model"], "bi-cpu-fill", "purple")
              render_config_card("Max Turns", attributes["agent.max_turns"], "bi-arrow-repeat", "green")
              render_config_card("Retry Policy", format_retry_config(attributes["agent.retry_config"]), "bi-arrow-clockwise", "orange")
              render_boolean_card("Circuit Breaker", attributes["agent.circuit_breaker_enabled"], "bi-shield-fill-check")
              render_boolean_card("Auto Merge", attributes["agent.auto_merge_enabled"], "bi-diagram-3-fill")
              render_config_card("Schema Mode", attributes["agent.schema_mode"], "bi-check2-square", "indigo")
            end
          end

          # Agent Fields Configuration
          if has_agent_fields?(attributes)
            div do
              h4(class: "text-sm font-semibold text-gray-900 mb-2 flex items-center gap-2") do
                i(class: "bi bi-list-ul text-gray-600")
                span { "Agent Fields" }
              end

              div(class: "grid grid-cols-1 md:grid-cols-2 gap-3") do
                if attributes["agent.required_fields"]
                  div(class: "bg-gray-50 border border-gray-200 rounded p-3") do
                    div(class: "flex items-center gap-2 mb-2") do
                      i(class: "bi bi-asterisk text-gray-600 text-sm")
                      span(class: "text-xs font-medium text-gray-700") { "REQUIRED FIELDS" }
                    end
                    div(class: "text-sm text-gray-900") do
                      span { format_field_list(attributes["agent.required_fields"]) }
                    end
                  end
                end

                if attributes["agent.optional_fields"]
                  div(class: "bg-gray-50 border border-gray-200 rounded p-3") do
                    div(class: "flex items-center gap-2 mb-2") do
                      i(class: "bi bi-question-circle text-gray-600 text-sm")
                      span(class: "text-xs font-medium text-gray-700") { "OPTIONAL FIELDS" }
                    end
                    div(class: "text-sm text-gray-900") do
                      span { format_field_list(attributes["agent.optional_fields"]) }
                    end
                  end
                end
              end
            end
          end

          # Advanced Features
          if has_advanced_features?(attributes)
            div do
              h4(class: "text-sm font-semibold text-gray-900 mb-2 flex items-center gap-2") do
                i(class: "bi bi-magic text-gray-600")
                span { "Advanced Features" }
              end

              div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3") do
                render_boolean_card("Schema Validation", attributes["agent.has_schema"], "bi-check-square-fill")
                render_boolean_card("Static Instructions", attributes["agent.has_static_instructions"], "bi-file-text-fill")
                render_boolean_card("Instruction Template", attributes["agent.has_instruction_template"], "bi-layout-text-sidebar")
                render_config_card("Schema Repair", attributes["agent.schema_repair_attempts"]&.to_s || "0", "bi-tools", "red")
              end
            end
          end

          # Tools & Capabilities
          if attributes["agent.tools"]&.any? || attributes["agent.tool_count"].to_i > 0
            div do
              h4(class: "text-sm font-semibold text-gray-900 mb-2 flex items-center gap-2") do
                i(class: "bi bi-wrench text-gray-600")
                span { "Tools & Capabilities" }
              end

              div(class: "bg-gray-50 rounded p-3") do
                div(class: "flex items-center justify-between mb-2") do
                  span(class: "text-sm font-medium text-gray-700") { "Available Tools" }
                  span(class: "px-2 py-1 bg-gray-200 text-gray-700 text-xs rounded font-medium") do
                    "#{attributes['agent.tool_count'] || 0} tools"
                  end
                end

                if attributes["agent.tools"].is_a?(Array)
                  div(class: "space-y-2") do
                    attributes["agent.tools"].each do |tool|
                      render_tool_card(tool)
                    end
                  end
                else
                  render_tools_summary(attributes["agent.tools"])
                end
              end
            end
          end

          # Timeout & Configuration
          if has_timeout_config?(attributes)
            div do
              h4(class: "text-sm font-semibold text-gray-900 mb-2 flex items-center gap-2") do
                i(class: "bi bi-clock-fill text-gray-600")
                span { "Timeout & Execution" }
              end

              div(class: "grid grid-cols-1 md:grid-cols-3 gap-3") do
                render_config_card("Execution Time", format_duration(attributes["duration_ms"]), "bi-stopwatch", "blue")
                render_config_card("Workflow Status", attributes["agent.workflow_status"]&.capitalize, "bi-check-circle", "green")
                render_boolean_card("Success", attributes["agent.success"], "bi-check-shield-fill")
              end
            end
          end

          # JSON Schema
          if has_json_schema?(attributes)
            div do
              h4(class: "text-sm font-semibold text-gray-900 mb-2 flex items-center gap-2") do
                i(class: "bi bi-braces text-gray-600")
                span { "JSON Schema" }
              end

              div(class: "bg-gray-50 border border-gray-200 rounded p-3") do
                details(class: "group/schema") do
                  summary(class: "cursor-pointer text-xs text-gray-600 hover:text-gray-800 flex items-center gap-1 select-none") do
                    i(class: "bi bi-chevron-right group-open/schema:rotate-90 transition-transform duration-200")
                    span { "View JSON Schema" }
                  end
                  div(class: "mt-2 p-3 bg-gray-100 rounded overflow-hidden") do
                    pre(class: "text-xs text-gray-800 font-mono overflow-x-auto") do
                      code { format_json_schema(attributes) }
                    end
                  end
                end
              end
            end
          end

          # Conversation Details
          if has_conversation_data?(attributes)
            div do
              h4(class: "text-sm font-semibold text-gray-900 mb-2 flex items-center gap-2") do
                i(class: "bi bi-chat-dots-fill text-gray-600")
                span { "Conversation Details" }
              end

              div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3 mb-4") do
                render_config_card("Message Count", attributes["dialog.message_count"], "bi-chat-square-dots", "blue")
                render_config_card("Context Size", attributes["dialog.context_size"], "bi-layers", "purple")
                render_config_card("System Prompt", "#{attributes['dialog.system_prompt_length']} chars", "bi-file-text", "green")
                render_config_card("User Prompt", "#{attributes['dialog.user_prompt_length']} chars", "bi-person-fill", "orange")
              end

              # Dialog Final Result
              if attributes["dialog.final_result"]
                div(class: "mb-3") do
                  details(class: "group/final-result") do
                    summary(class: "cursor-pointer text-sm text-gray-600 hover:text-gray-800 flex items-center gap-2 select-none font-medium p-3 bg-gray-50 rounded border border-gray-200") do
                      i(class: "bi bi-chevron-right group-open/final-result:rotate-90 transition-transform duration-200")
                      span { "View Final Result" }
                    end
                    div(class: "mt-3 p-3 bg-gray-100 rounded overflow-hidden") do
                      pre(class: "text-sm text-gray-800 font-mono overflow-x-auto whitespace-pre-wrap") do
                        code { format_dialog_content(attributes["dialog.final_result"]) }
                      end
                    end
                  end
                end
              end

              # Dialog Messages
              if attributes["dialog.messages"]
                div(class: "mb-3") do
                  details(class: "group/messages") do
                    summary(class: "cursor-pointer text-sm text-gray-600 hover:text-gray-800 flex items-center gap-2 select-none font-medium p-3 bg-gray-50 rounded border border-gray-200") do
                      i(class: "bi bi-chevron-right group-open/messages:rotate-90 transition-transform duration-200")
                      span { "View Dialog Messages" }
                    end
                    div(class: "mt-3 p-3 bg-gray-100 rounded overflow-hidden") do
                      pre(class: "text-sm text-gray-800 font-mono overflow-x-auto whitespace-pre-wrap") do
                        code { format_dialog_content(attributes["dialog.messages"]) }
                      end
                    end
                  end
                end
              end

              # Initial Context
              if attributes["dialog.initial_context"]
                div(class: "mb-3") do
                  details(class: "group/initial-context") do
                    summary(class: "cursor-pointer text-sm text-gray-600 hover:text-gray-800 flex items-center gap-2 select-none font-medium p-3 bg-gray-50 rounded border border-gray-200") do
                      i(class: "bi bi-chevron-right group-open/initial-context:rotate-90 transition-transform duration-200")
                      span { "View Initial Context" }
                    end
                    div(class: "mt-3 p-3 bg-gray-100 rounded overflow-hidden") do
                      pre(class: "text-sm text-gray-800 font-mono overflow-x-auto whitespace-pre-wrap") do
                        code { format_dialog_content(attributes["dialog.initial_context"]) }
                      end
                    end
                  end
                end
              end

              # Context Keys
              if attributes["dialog.context_keys"]
                div(class: "mb-3") do
                  details(class: "group/context-keys") do
                    summary(class: "cursor-pointer text-sm text-gray-600 hover:text-gray-800 flex items-center gap-2 select-none font-medium p-3 bg-gray-50 rounded border border-gray-200") do
                      i(class: "bi bi-chevron-right group-open/context-keys:rotate-90 transition-transform duration-200")
                      span { "View Context Keys" }
                    end
                    div(class: "mt-3 p-3 bg-gray-100 rounded overflow-hidden") do
                      pre(class: "text-sm text-gray-800 font-mono overflow-x-auto whitespace-pre-wrap") do
                        code { format_dialog_content(attributes["dialog.context_keys"]) }
                      end
                    end
                  end
                end
              end

              # System Prompt Section
              if attributes["dialog.system_prompt"]
                details(class: "group/system-prompt mb-3") do
                  summary(class: "cursor-pointer text-sm text-gray-600 hover:text-gray-800 flex items-center gap-2 select-none font-medium p-3 bg-gray-50 rounded border border-gray-200") do
                    i(class: "bi bi-chevron-right group-open/system-prompt:rotate-90 transition-transform duration-200")
                    span { "View System Prompt (#{attributes['dialog.system_prompt_length']} characters)" }
                  end
                  div(class: "mt-3 p-3 bg-gray-100 rounded overflow-hidden") do
                    pre(class: "text-sm text-gray-800 font-mono overflow-x-auto whitespace-pre-wrap") do
                      code { attributes["dialog.system_prompt"].to_s[0..2000] + (attributes["dialog.system_prompt"].to_s.length > 2000 ? "\n\n... (truncated)" : "") }
                    end
                  end
                end
              end

              # User Prompt Section
              if attributes["dialog.user_prompt"]
                details(class: "group/user-prompt mb-3") do
                  summary(class: "cursor-pointer text-sm text-gray-600 hover:text-gray-800 flex items-center gap-2 select-none font-medium p-3 bg-gray-50 rounded border border-gray-200") do
                    i(class: "bi bi-chevron-right group-open/user-prompt:rotate-90 transition-transform duration-200")
                    span { "View User Prompt (#{attributes['dialog.user_prompt_length']} characters)" }
                  end
                  div(class: "mt-3 p-3 bg-gray-100 rounded overflow-hidden") do
                    pre(class: "text-sm text-gray-800 font-mono overflow-x-auto whitespace-pre-wrap") do
                      code { attributes["dialog.user_prompt"].to_s[0..2000] + (attributes["dialog.user_prompt"].to_s.length > 2000 ? "\n\n... (truncated)" : "") }
                    end
                  end
                end
              end

              # Context Variables
              if attributes["dialog.context_keys"]
                details(class: "group/context mb-3") do
                  summary(class: "cursor-pointer text-sm text-gray-700 hover:text-gray-900 flex items-center gap-2 select-none font-medium p-3 bg-gray-50 rounded border border-gray-200") do
                    i(class: "bi bi-chevron-right group-open/context:rotate-90 transition-transform duration-200")
                    span { "View Context Variables (#{attributes['dialog.context_size']} items)" }
                  end
                  div(class: "mt-3") do
                    render_context_variables(attributes)
                  end
                end
              end
            end
          end

          # Raw Attributes (collapsible)
          details(class: "group/raw-attrs") do
            summary(class: "cursor-pointer text-sm text-gray-700 hover:text-gray-900 flex items-center gap-2 p-3 bg-gray-50 rounded border border-gray-200 select-none") do
              i(class: "bi bi-chevron-right group-open/raw-attrs:rotate-90 transition-transform duration-200")
              span(class: "font-medium") { "View All Raw Attributes" }
              span(class: "text-xs text-gray-500") { "(#{attributes.keys.count} total)" }
            end

            div(class: "mt-3 p-3 bg-gray-100 rounded overflow-hidden") do
              pre(class: "text-sm text-gray-800 font-mono overflow-x-auto") do
                code { JSON.pretty_generate(attributes.to_h) }
              end
            end
          end
        end
      end

      def render_config_card(title, value, icon, color)
        div(class: "bg-gray-50 border border-gray-200 rounded p-2") do
          div(class: "flex items-start gap-2") do
            div(class: "flex-shrink-0") do
              i(class: "bi #{icon} text-gray-600 text-sm")
            end
            div(class: "min-w-0 flex-1") do
              p(class: "text-xs font-medium text-gray-600 uppercase tracking-wide mb-1") { title }
              p(class: "text-sm font-semibold text-gray-900 break-words") { value || "Not set" }
            end
          end
        end
      end

      def render_boolean_card(title, value, icon)
        is_enabled = value.to_s.downcase == "true"

        div(class: "bg-gray-50 border border-gray-200 rounded p-2") do
          div(class: "flex items-start gap-2") do
            div(class: "flex-shrink-0") do
              i(class: "bi #{icon} text-gray-600 text-sm")
            end
            div(class: "min-w-0 flex-1") do
              p(class: "text-xs font-medium text-gray-600 uppercase tracking-wide mb-1") { title }
              div(class: "flex items-center gap-2") do
                span(class: "text-sm font-semibold text-gray-900") { is_enabled ? "Enabled" : "Disabled" }
                div(class: "w-2 h-2 rounded-full #{is_enabled ? 'bg-gray-600' : 'bg-gray-400'}")
              end
            end
          end
        end
      end

      def render_tool_card(tool)
        if tool.is_a?(Hash)
          div(class: "bg-white rounded-lg border border-gray-200 p-4 hover:border-gray-300 transition-colors") do
            div(class: "flex items-start gap-3") do
              div(class: "flex-shrink-0 p-2 bg-green-100 rounded-lg") do
                i(class: "bi bi-wrench text-green-600")
              end
              div(class: "flex-1 min-w-0") do
                h5(class: "text-sm font-semibold text-gray-900 mb-1") { tool["name"] || "Tool" }
                if tool["tool_class"]
                  p(class: "text-xs text-gray-600 font-mono mb-2") { tool["tool_class"] }
                end
                if tool["options"]&.any?
                  div(class: "text-xs text-gray-500") do
                    span { "#{tool['options'].keys.count} options configured" }
                  end
                end
              end
              div(class: "text-xs text-green-600 font-medium") do
                span { tool["tool_type"]&.upcase || "TOOL" }
              end
            end
          end
        else
          div(class: "bg-white rounded-lg border border-gray-200 p-3 text-sm text-gray-700") do
            span { tool.to_s }
          end
        end
      end

      def render_tools_summary(tools_data)
        div(class: "bg-white rounded-lg border border-gray-200 p-4") do
          div(class: "flex items-center gap-2 text-sm text-gray-700") do
            i(class: "bi bi-info-circle text-blue-600")
            span { "Tools data available in raw attributes section" }
          end
        end
      end

      def has_advanced_features?(attributes)
        attributes["agent.has_schema"] == "true" ||
        attributes["agent.has_static_instructions"] == "true" ||
        attributes["agent.has_instruction_template"] == "true" ||
        (attributes["agent.schema_repair_attempts"].to_i > 0)
      end

      def has_agent_attributes?(attributes)
        # Check if this span contains agent configuration attributes (lowercase or capitalized)
        attributes.keys.any? { |key| key.to_s.downcase.start_with?("agent.") }
      end

      def has_timeout_config?(attributes)
        attributes["duration_ms"] || attributes["agent.workflow_status"] || attributes["agent.success"]
      end

      def has_conversation_data?(attributes)
        attributes.keys.any? { |key| key.to_s.start_with?("dialog.") }
      end

      def render_context_variables(attributes)
        context_keys = attributes["dialog.context_keys"]
        context_data = attributes["dialog.initial_context"]

        # Try to extract context variables from various possible formats
        context_vars = extract_context_variables(attributes)

        if context_vars && context_vars.any?
          div(class: "grid grid-cols-1 gap-3") do
            div(class: "bg-white rounded border border-gray-200 p-3") do
              h5(class: "text-sm font-semibold text-gray-900 mb-2") { "Context Variables (#{context_vars.count})" }
              div(class: "space-y-2") do
                context_vars.each do |key, value|
                  div(class: "flex flex-col gap-1") do
                    span(class: "text-xs font-medium text-gray-700") { key.to_s }
                    div(class: "text-xs text-gray-600 bg-gray-50 px-2 py-1 rounded font-mono border") do
                      span { format_context_value(value) }
                    end
                  end
                end
              end
            end

            # Show raw context data if available
            if context_data.present?
              div(class: "bg-white rounded border border-gray-200 p-3") do
                h5(class: "text-sm font-semibold text-gray-900 mb-2") { "Raw Context Data" }
                details(class: "group/context-data") do
                  summary(class: "cursor-pointer text-xs text-gray-600 hover:text-gray-800 flex items-center gap-1 select-none") do
                    i(class: "bi bi-chevron-right group-open/context-data:rotate-90 transition-transform duration-200")
                    span { "View Raw Data" }
                  end
                  div(class: "mt-2 p-2 bg-gray-100 rounded overflow-hidden") do
                    pre(class: "text-xs text-gray-800 font-mono overflow-x-auto") do
                      code { context_data.to_s[0..1000] + (context_data.to_s.length > 1000 ? "\n\n... (truncated)" : "") }
                    end
                  end
                end
              end
            end
          end
        else
          div(class: "bg-white rounded border border-gray-200 p-3") do
            div(class: "flex items-center gap-2 text-sm text-gray-700") do
              i(class: "bi bi-info-circle text-gray-600")
              span { "No context variables found" }
            end
          end
        end
      end

      def extract_context_variables(attributes)
        # Try different possible keys for context variables
        context_vars = {}

        # Method 1: Check for dialog.context_keys array
        if attributes["dialog.context_keys"].is_a?(Array)
          attributes["dialog.context_keys"].each do |key|
            # Try to find the value in various formats
            value = attributes["dialog.context_#{key}"] ||
                   attributes["context.#{key}"] ||
                   attributes[key.to_s] ||
                   "Present (value not found)"
            context_vars[key] = value
          end
        end

        # Method 2: Check for direct context keys in attributes
        context_keys = attributes.keys.select { |k| k.to_s.start_with?("context.") }
        context_keys.each do |key|
          clean_key = key.to_s.sub("context.", "")
          context_vars[clean_key] = attributes[key]
        end

        # Method 3: Check for dialog.context_* keys
        dialog_context_keys = attributes.keys.select { |k| k.to_s.start_with?("dialog.context_") && k.to_s != "dialog.context_keys" && k.to_s != "dialog.context_size" }
        dialog_context_keys.each do |key|
          clean_key = key.to_s.sub("dialog.context_", "")
          context_vars[clean_key] = attributes[key]
        end

        context_vars.empty? ? nil : context_vars
      end

      def format_context_value(value)
        case value
        when Hash, Array
          JSON.pretty_generate(value).truncate(200)
        when String
          value.truncate(200)
        else
          value.to_s.truncate(200)
        end
      rescue
        value.to_s.truncate(200)
      end

      def has_agent_fields?(attributes)
        attributes["agent.required_fields"] || attributes["agent.optional_fields"]
      end

      def has_json_schema?(attributes)
        attributes["agent.schema"] || attributes["agent.json_schema"] || attributes["schema"]
      end

      def format_field_list(fields)
        case fields
        when Array
          fields.join(", ")
        when String
          fields
        when Hash
          fields.keys.join(", ")
        else
          fields.to_s
        end
      rescue
        fields.to_s
      end

      def format_json_schema(attributes)
        schema = attributes["agent.schema"] || attributes["agent.json_schema"] || attributes["schema"]
        case schema
        when Hash
          JSON.pretty_generate(schema)
        when String
          # Try to parse if it's a JSON string
          begin
            parsed = JSON.parse(schema)
            JSON.pretty_generate(parsed)
          rescue
            schema
          end
        else
          schema.to_s
        end
      rescue
        schema.to_s
      end

      def format_dialog_content(content)
        case content
        when Hash, Array
          JSON.pretty_generate(content)
        when String
          # Try to parse if it's a JSON string
          begin
            parsed = JSON.parse(content)
            JSON.pretty_generate(parsed)
          rescue
            content
          end
        else
          content.to_s
        end
      rescue
        content.to_s
      end

      def format_retry_config(config)
        return "Not configured" unless config

        if config.is_a?(String)
          # Parse the string that looks like: {rate_limit: {max_attempts: 5, backoff: :exponential, delay: 1}, timeout: {max_attempts: 3, backoff...
          if config.include?("max_attempts")
            attempts = config.match(/max_attempts:\s*(\d+)/)&.captures&.first
            return "#{attempts} attempts" if attempts
          end
        end

        "Configured"
      end

      def render_span_tree(spans, depth = 0)
        # Group spans by parent_id
        spans_by_parent = spans.group_by(&:parent_id)
        root_spans = spans_by_parent[nil] || []

        root_spans.each do |span|
          render_span_item(span, depth)

          # Render children recursively
          children = spans_by_parent[span.span_id] || []
          next unless children.any?

          div(class: "ml-6 mt-2 space-y-2") do
            render_span_tree(children, depth + 1)
          end
        end
      end

      def render_span_item(span, depth = 0)
        div(class: "group relative bg-gray-50/50 hover:bg-white border border-gray-200/60 hover:border-gray-300 rounded-lg transition-all duration-200 hover:shadow-sm") do
          div(class: "p-4") do
            div(class: "flex items-start justify-between") do
              div(class: "flex-1") do
                div(class: "flex items-center gap-3 mb-2") do
                  render_modern_kind_badge(span.kind)
                  h4(class: "font-medium text-gray-900 text-sm") { span.name }
                  render_modern_status_badge(span.status) if span.status != "ok"
                end

                div(class: "flex items-center gap-4 text-xs text-gray-500 mb-3") do
                  div(class: "flex items-center gap-1") do
                    i(class: "bi bi-stopwatch")
                    span { format_duration(span.duration_ms) }
                  end
                  div(class: "flex items-center gap-1") do
                    i(class: "bi bi-clock")
                    span { span.start_time.strftime("%H:%M:%S.%L") }
                  end
                  if span.span_attributes && span.span_attributes.any?
                    div(class: "flex items-center gap-1") do
                      i(class: "bi bi-info-circle")
                      span { "#{span.span_attributes.keys.count} attributes" }
                    end
                  end
                end

                # Duration visualization
                if span.duration_ms&.positive?
                  div(class: "mb-3") do
                    div(class: "flex items-center justify-between text-xs text-gray-500 mb-1") do
                      span { "Execution time" }
                      span { "#{calculate_span_percentage(span).round(1)}% of trace" }
                    end
                    div(class: "w-full bg-gray-200 rounded-full h-1.5") do
                      div(
                        class: "h-1.5 rounded-full transition-all duration-300 #{span.status == 'error' ? 'bg-gray-600' : 'bg-gray-500'}",
                        style: "width: #{[calculate_span_percentage(span), 100].min}%"
                      )
                    end
                  end
                end

                # Attributes (collapsible) - Enhanced for Agent spans, standard for others
                if span.span_attributes && span.span_attributes.any?
                  if span.kind == "agent" && has_agent_attributes?(span.span_attributes)
                    # Enhanced agent configuration UI
                    details(class: "group/details") do
                      summary(class: "cursor-pointer text-sm text-gray-600 hover:text-gray-800 flex items-center gap-2 select-none font-medium") do
                        i(class: "bi bi-chevron-right group-open/details:rotate-90 transition-transform duration-200")
                        span { "View Agent Configuration (#{span.span_attributes.keys.count})" }
                      end
                      div(class: "mt-4") do
                        render_enhanced_agent_details(span.span_attributes)
                      end
                    end
                  else
                    # Standard attributes view for non-agent spans
                    details(class: "group/details") do
                      summary(class: "cursor-pointer text-xs text-gray-600 hover:text-gray-800 flex items-center gap-1 select-none") do
                        i(class: "bi bi-chevron-right group-open/details:rotate-90 transition-transform duration-200")
                        span { "View attributes (#{span.span_attributes.keys.count})" }
                      end
                      div(class: "mt-2 p-3 bg-gray-50 rounded border") do
                        div(class: "grid grid-cols-1 gap-2") do
                          span.span_attributes.each do |key, value|
                            next if %w[span_id trace_id parent_id].include?(key)

                            div(class: "flex flex-col gap-1") do
                              span(class: "text-xs font-medium text-gray-700") { key.humanize }
                              span(class: "text-xs text-gray-600 font-mono bg-white px-2 py-1 rounded border") { value.to_s.truncate(100) }
                            end
                          end
                        end
                      end
                    end
                  end
                end

                # Error details
                if span.error_details.present?
                  div(class: "mt-3 p-3 bg-red-50 border border-red-200 rounded-lg") do
                    div(class: "flex items-center gap-2 mb-2") do
                      i(class: "bi bi-exclamation-triangle text-red-600")
                      span(class: "text-sm font-medium text-red-800") { "Error Details" }
                    end
                    if span.error_details["exception_message"]
                      p(class: "text-sm text-red-700 mb-1") { span.error_details["exception_message"] }
                    end
                    if span.error_details["exception_type"]
                      p(class: "text-xs text-red-600") { "Type: #{span.error_details['exception_type']}" }
                    end
                  end
                end
              end

              # Quick stats sidebar
              div(class: "text-right flex flex-col items-end gap-1") do
                div(class: "px-2 py-1 bg-white rounded border text-xs font-medium text-gray-700") do
                  format_duration(span.duration_ms)
                end
                div(class: "text-xs text-gray-500") do
                  span.start_time.strftime("%H:%M:%S")
                end
              end
            end
          end
        end
      end

      def render_status_badge(status, skip_reason: nil)
        render RAAF::Rails::Tracing::SkippedBadgeTooltip.new(status: status, skip_reason: skip_reason, style: :detailed)
      end

      def render_modern_status_badge(status)
        render_status_badge(status)
      end

      def render_kind_badge(kind)
        icon = case kind
               when "agent" then "robot"
               when "llm" then "cpu"
               when "tool" then "wrench"
               when "handoff" then "arrow-left-right"
               else "gear"
               end

        span(class: "px-2 py-1 bg-gray-100 text-gray-700 border border-gray-200 rounded text-xs font-medium flex items-center gap-1") do
          i(class: "bi bi-#{icon}")
          span { kind.capitalize }
        end
      end

      def render_modern_kind_badge(kind)
        render_kind_badge(kind)
      end

      def calculate_span_percentage(span)
        return 0 unless span.duration_ms && @trace.duration_ms

        max_duration = @trace.duration_ms || 1
        [(span.duration_ms.to_f / max_duration * 100).round(2), 100].min
      end

      def format_duration(ms)
        return "N/A" unless ms

        if ms < 1000
          "#{ms.round}ms"
        elsif ms < 60_000
          "#{(ms / 1000.0).round(1)}s"
        else
          minutes = (ms / 60_000).floor
          seconds = ((ms % 60_000) / 1000.0).round(1)
          "#{minutes}m #{seconds}s"
        end
      end
    end
    end
  end
end

# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module SpanDetail
        # PipelineSpanComponent displays pipeline execution stages and data flow
        # for pipeline spans, showing step results, stage execution, and
        # data transformation between pipeline steps.
        class PipelineSpanComponent < RAAF::Rails::Tracing::SpanDetailBase
          def initialize(span:, **options)
            @span = span
            super(span: span, **options)
          end

          def view_template
            div(class: "space-y-6", data: { controller: "span-detail" }) do
              render_pipeline_overview
              render_stage_execution if pipeline_stages.present?
              render_data_flow if data_flow.present?
              render_pipeline_metadata if pipeline_metadata.present?
              render_step_results if step_results.present?
              render_raw_attributes if debug_mode?
            end
          end

          private

          def render_pipeline_overview
            div(class: "bg-purple-50 border border-purple-200 rounded-lg p-4") do
              div(class: "flex items-center gap-3") do
                i(class: "bi bi-diagram-3 text-purple-600 text-xl")
                div(class: "flex-1") do
                  h3(class: "text-lg font-semibold text-purple-900") { "Pipeline Execution" }
                  p(class: "text-sm text-purple-700") do
                    "Pipeline: #{pipeline_name} | Stages: #{total_stages} | Status: #{pipeline_status}"
                  end
                end
                render_pipeline_status_badge
              end
            end
          end

          def render_pipeline_status_badge
            color_classes = case pipeline_status.to_s.downcase
                           when "success", "completed" then "bg-green-100 text-green-800 border-green-200"
                           when "failed", "error" then "bg-red-100 text-red-800 border-red-200"
                           when "running", "in_progress" then "bg-blue-100 text-blue-800 border-blue-200"
                           when "paused", "waiting" then "bg-yellow-100 text-yellow-800 border-yellow-200"
                           else "bg-gray-100 text-gray-800 border-gray-200"
                           end

            span(class: "px-3 py-1 text-sm font-medium rounded-full border #{color_classes}") do
              pipeline_status.to_s.titleize
            end
          end

          def render_stage_execution
            div(class: "bg-white border border-gray-200 rounded-lg shadow") do
              render_collapsible_header("Stage Execution", "stage-execution", "bi-list-task")
              div(id: "stage-execution-content", class: "border-t border-gray-200") do
                render_pipeline_stages_timeline
              end
            end
          end

          def render_pipeline_stages_timeline
            div(class: "p-4") do
              div(class: "space-y-4") do
                pipeline_stages.each_with_index do |stage, index|
                  render_pipeline_stage(stage, index)
                end
              end
            end
          end

          def render_pipeline_stage(stage, index)
            stage_name = stage.is_a?(Hash) ? (stage["name"] || stage[:name] || "Stage #{index + 1}") : stage.to_s
            stage_status = stage.is_a?(Hash) ? (stage["status"] || stage[:status] || "unknown") : "completed"
            stage_duration = stage.is_a?(Hash) ? (stage["duration_ms"] || stage[:duration_ms]) : nil

            div(class: "flex items-start gap-4 p-3 bg-gray-50 rounded-lg") do
              # Stage indicator
              div(class: "flex-shrink-0 mt-1") do
                render_stage_indicator(stage_status, index + 1)
              end

              # Stage content
              div(class: "flex-1 min-w-0") do
                div(class: "flex items-center justify-between mb-2") do
                  h5(class: "text-sm font-medium text-gray-900") { stage_name }
                  div(class: "flex items-center gap-2") do
                    render_stage_status_badge(stage_status)
                    if stage_duration
                      render_duration_badge(stage_duration)
                    end
                  end
                end

                # Stage details
                if stage.is_a?(Hash)
                  render_stage_details(stage, index)
                end
              end
            end
          end

          def render_stage_indicator(status, number)
            base_classes = "w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold"
            color_classes = case status.to_s.downcase
                           when "success", "completed" then "bg-green-500 text-white"
                           when "failed", "error" then "bg-red-500 text-white"
                           when "running", "in_progress" then "bg-blue-500 text-white animate-pulse"
                           when "pending", "waiting" then "bg-gray-300 text-gray-600"
                           else "bg-yellow-500 text-white"
                           end

            div(class: "#{base_classes} #{color_classes}") do
              if status.to_s.downcase == "running"
                i(class: "bi bi-arrow-right")
              else
                number.to_s
              end
            end
          end

          def render_stage_status_badge(status)
            color_classes = case status.to_s.downcase
                           when "success", "completed" then "bg-green-100 text-green-800"
                           when "failed", "error" then "bg-red-100 text-red-800"
                           when "running", "in_progress" then "bg-blue-100 text-blue-800"
                           when "pending", "waiting" then "bg-gray-100 text-gray-800"
                           else "bg-yellow-100 text-yellow-800"
                           end

            span(class: "px-2 py-1 text-xs font-medium rounded #{color_classes}") do
              status.to_s.upcase
            end
          end

          def render_stage_details(stage, index)
            stage_id = "stage-#{index}-details"
            details = stage.except("name", :name, "status", :status, "duration_ms", :duration_ms)

            return unless details.any?

            div(class: "mt-2") do
              button(
                class: "text-xs text-blue-600 hover:text-blue-800 flex items-center gap-1 px-2 py-1 hover:bg-blue-50 rounded transition-colors",
                data: {
                  action: "click->span-detail#toggleSection",
                  target: stage_id
                }
              ) do
                i(class: "bi bi-chevron-right toggle-icon")
                span(class: "button-text") { "View Details" }
              end

              div(id: stage_id, class: "mt-2 hidden") do
                render_json_content(details, "stage-#{index}-data")
              end
            end
          end

          def render_data_flow
            div(class: "bg-white border border-gray-200 rounded-lg shadow") do
              render_collapsible_header("Data Flow", "data-flow", "bi-arrow-left-right")
              div(id: "data-flow-content", class: "p-4 border-t border-gray-200") do
                if data_flow.is_a?(Array)
                  render_data_flow_sequence
                else
                  render_json_content(data_flow, "data-flow-data")
                end
              end
            end
          end

          def render_data_flow_sequence
            div(class: "space-y-3") do
              data_flow.each_with_index do |flow_step, index|
                render_data_flow_step(flow_step, index)
              end
            end
          end

          def render_data_flow_step(step, index)
            div(class: "flex items-center gap-4 p-3 bg-blue-50 rounded-lg border border-blue-200") do
              # Flow step indicator
              div(class: "flex-shrink-0") do
                div(class: "w-6 h-6 bg-blue-500 text-white rounded-full flex items-center justify-center text-xs font-bold") do
                  (index + 1).to_s
                end
              end

              # Flow content
              div(class: "flex-1") do
                if step.is_a?(Hash)
                  div(class: "text-sm text-blue-900 font-medium mb-1") do
                    step["description"] || step[:description] || "Step #{index + 1}"
                  end
                  if step["input"] || step[:input]
                    div(class: "text-xs text-blue-700") do
                      "Input: #{truncate_data(step["input"] || step[:input])}"
                    end
                  end
                  if step["output"] || step[:output]
                    div(class: "text-xs text-blue-700") do
                      "Output: #{truncate_data(step["output"] || step[:output])}"
                    end
                  end
                else
                  div(class: "text-sm text-blue-900") { step.to_s }
                end
              end

              # Arrow to next step
              unless index == data_flow.length - 1
                div(class: "flex-shrink-0") do
                  i(class: "bi bi-arrow-right text-blue-400")
                end
              end
            end
          end

          def render_pipeline_metadata
            div(class: "bg-white border border-gray-200 rounded-lg shadow") do
              render_collapsible_header("Pipeline Metadata", "pipeline-metadata", "bi-info-circle")
              div(id: "pipeline-metadata-content", class: "p-4 border-t border-gray-200") do
                dl(class: "space-y-3") do
                  pipeline_metadata.each do |key, value|
                    render_detail_item(key.to_s.humanize, value)
                  end
                end
              end
            end
          end

          def render_step_results
            div(class: "bg-white border border-gray-200 rounded-lg shadow") do
              render_collapsible_header("Step Results", "step-results", "bi-check-circle", expanded: false)
              div(id: "step-results-content", class: "p-4 border-t border-gray-200 hidden") do
                render_json_content(step_results, "step-results-data")
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
              i(class: "bi #{expanded ? 'bi-chevron-down' : 'bi-chevron-right'} text-gray-400 toggle-icon")
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
          def pipeline_name
            @pipeline_name ||= @span.span_attributes&.dig("pipeline", "name") ||
                              @span.span_attributes&.dig("pipeline_name") ||
                              @span.name ||
                              "Unknown Pipeline"
          end

          def pipeline_status
            @pipeline_status ||= @span.span_attributes&.dig("pipeline", "status") ||
                                @span.span_attributes&.dig("status") ||
                                @span.status ||
                                "unknown"
          end

          def pipeline_stages
            @pipeline_stages ||= @span.span_attributes&.dig("pipeline", "stages") ||
                                @span.span_attributes&.dig("stages") ||
                                @span.span_attributes&.dig("steps") ||
                                []
          end

          def total_stages
            pipeline_stages.length
          end

          def data_flow
            @data_flow ||= @span.span_attributes&.dig("pipeline", "data_flow") ||
                          @span.span_attributes&.dig("data_flow") ||
                          @span.span_attributes&.dig("flow")
          end

          def pipeline_metadata
            @pipeline_metadata ||= begin
              metadata = @span.span_attributes&.dig("pipeline", "metadata") ||
                        @span.span_attributes&.dig("metadata") ||
                        {}
              
              # Add computed metadata
              metadata = metadata.merge({
                "total_duration_ms" => @span.duration_ms,
                "start_time" => format_timestamp(@span.start_time),
                "end_time" => format_timestamp(@span.end_time),
                "trace_id" => @span.trace_id
              }.compact)
              
              metadata
            end
          end

          def step_results
            @step_results ||= @span.span_attributes&.dig("pipeline", "results") ||
                             @span.span_attributes&.dig("results") ||
                             @span.span_attributes&.dig("step_results")
          end

          def debug_mode?
            @span.span_attributes&.dig("debug") == true ||
            ENV["RAAF_DEBUG"] == "true" ||
            ::Rails.env.development?
          end

          def truncate_data(data)
            return "" if data.nil?
            
            str = data.is_a?(String) ? data : data.to_s
            str.length > 50 ? "#{str[0, 50]}..." : str
          end

          def truncate(text, length: 100)
            return text unless text.is_a?(String) && text.length > length
            "#{text[0, length]}..."
          end
        end
      end
    end
  end
end
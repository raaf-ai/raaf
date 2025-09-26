# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class ToolSpanComponent < SpanDetailBase
        def view_template
          div(class: "space-y-6") do
            render_tool_overview
            render_function_execution_flow if tool_data.present?
            render_error_handling
          end
        end

        private

        def tool_data
          @tool_data ||= begin
            # Try both common patterns for tool data storage
            function_data = extract_span_attribute("function") ||
                           extract_span_attribute("tool") ||
                           extract_span_attribute("tool_call")

            # Handle different tool data formats
            case function_data
            when Hash
              function_data
            when String
              begin
                JSON.parse(function_data)
              rescue JSON::ParserError
                { "name" => function_data }
              end
            else
              # Fallback: extract from span name and attributes
              {
                "name" => @span.name&.gsub(/^(tool|function)[\.\:]\s*/, '') || "Unknown Tool",
                "input" => extract_span_attribute("input") || extract_span_attribute("arguments") || extract_span_attribute("tool_arguments"),
                "output" => extract_span_attribute("output") || extract_span_attribute("result") || extract_span_attribute("result.tool_result")
              }
            end
          end
        end

        def render_tool_overview
          tool_name = tool_data.dig("name") || @span.name || "Unknown Tool"
          
          render_span_overview_header(
            "bi bi-tools", 
            "Tool Execution", 
            tool_name
          )
        end

        def render_function_execution_flow
          div(class: "space-y-6") do
            # Function details section
            if tool_data.dig("name")
              div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
                div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
                  h3(class: "text-lg font-semibold text-gray-900") { "Function Details" }
                end
                div(class: "px-4 py-5 sm:p-6") do
                  dl(class: "grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2") do
                    render_detail_item("Function Name", tool_data["name"], monospace: true)
                    render_detail_item("Execution Status", render_status_badge(@span.status))
                    render_detail_item("Duration", render_duration_badge(@span.duration_ms))
                    
                    if tool_data.dig("description")
                      render_detail_item("Description", tool_data["description"])
                    end
                  end
                end
              end
            end

            # Input/Output flow visualization
            render_io_flow
          end
        end

        def render_io_flow
          div(class: "grid grid-cols-1 lg:grid-cols-2 gap-6") do
            # Input Parameters
            input_data = tool_data.dig("input") || tool_data.dig("arguments") || extract_span_attribute("tool_arguments")
            if input_data
              div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
                div(class: "px-4 py-5 sm:px-6 border-b border-blue-200 bg-blue-50") do
                  div(class: "flex items-center gap-3") do
                    i(class: "bi bi-arrow-right text-blue-600 text-lg")
                    h3(class: "text-lg font-semibold text-blue-900") { "Input Parameters" }
                  end
                end
                div(class: "px-4 py-5 sm:p-6") do
                  render_json_section("Input Data", input_data, collapsed: false, use_json_highlighter: true)
                end
              end
            else
              # Empty state for inputs
              div(class: "bg-white overflow-hidden shadow rounded-lg border-2 border-dashed border-gray-200") do
                div(class: "px-4 py-8 text-center") do
                  i(class: "bi bi-arrow-right text-gray-400 text-2xl mb-2")
                  p(class: "text-sm text-gray-500") { "No input parameters" }
                end
              end
            end

            # Output Results
            output_data = tool_data.dig("output") || tool_data.dig("result") || tool_data.dig("return_value") ||
                         extract_span_attribute("result.tool_result")
            result_metadata = extract_result_metadata

            if output_data
              div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
                div(class: "px-4 py-5 sm:px-6 border-b border-green-200 bg-green-50") do
                  div(class: "flex items-center gap-3") do
                    i(class: "bi bi-arrow-left text-green-600 text-lg")
                    h3(class: "text-lg font-semibold text-green-900") { "Output Results" }
                  end
                end
                div(class: "px-4 py-5 sm:p-6") do
                  render_json_section("Output Data", output_data, collapsed: false, use_json_highlighter: true)
                end
              end
            elsif result_metadata.any?
              # Show metadata when actual output isn't captured
              div(class: "bg-white overflow-hidden shadow rounded-lg border border-gray-200") do
                div(class: "px-4 py-5 sm:px-6 border-b border-yellow-200 bg-yellow-50") do
                  div(class: "flex items-center gap-3") do
                    i(class: "bi bi-info-circle text-yellow-600 text-lg")
                    h3(class: "text-lg font-semibold text-yellow-900") { "Execution Metadata" }
                  end
                end
                div(class: "px-4 py-5 sm:p-6") do
                  dl(class: "space-y-2") do
                    result_metadata.each do |key, value|
                      div(class: "flex items-center justify-between py-1") do
                        dt(class: "text-sm font-medium text-gray-600") { key.humanize }
                        dd(class: "text-sm text-gray-900 font-mono") { value.to_s }
                      end
                    end
                  end
                  p(class: "text-xs text-yellow-700 mt-3") { "Tool output data was not captured, showing execution metadata instead." }
                end
              end
            else
              # Empty state for outputs
              div(class: "bg-white overflow-hidden shadow rounded-lg border-2 border-dashed border-gray-200") do
                div(class: "px-4 py-8 text-center") do
                  i(class: "bi bi-arrow-left text-gray-400 text-2xl mb-2")
                  p(class: "text-sm text-gray-500") { "No output results" }
                end
              end
            end
          end
        end

        def extract_result_metadata
          metadata = {}

          # Look for result-related attributes
          %w[result.type result.success success duration_ms].each do |key|
            value = extract_span_attribute(key)
            metadata[key] = value if value
          end

          metadata
        end
      end
    end
  end
end

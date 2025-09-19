# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class FlowsVisualization < BaseComponent
        def initialize(flow_data:, agents:, traces:, params: {})
          @flow_data = flow_data
          @agents = agents
          @traces = traces
          @params = params
        end

        def view_template
          div(class: "p-6") do
            render_header
            render_filters
            render_stats_overview
            render_flow_visualization
            render_flow_data_tables
          end

          content_for :javascript do
            render_visualization_script
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6") do
            div(class: "min-w-0 flex-1") do
              h1(class: "text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate") { "Flow Visualization" }
              p(class: "mt-1 text-sm text-gray-500") { "Agent and tool interaction flows" }
            end

            div(class: "mt-4 flex sm:mt-0 sm:ml-4") do
              render_preline_button(
                text: "Export Flow Data",
                href: "/raaf/tracing/spans/flows.json",
                variant: "secondary",
                icon: "bi-download"
              )
            end
          end
        end

        def render_filters
          div(class: "bg-white p-6 rounded-lg shadow mb-6") do
            form_with(url: "/raaf/tracing/spans/flows", method: :get, local: true, class: "grid grid-cols-1 gap-4 sm:grid-cols-5") do |form|
              div do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Agent Name" }
                form.select(
                  :agent_name,
                  [["All Agents", ""]] + @agents.map { |a| [a, a] },
                  { selected: @params[:agent_name] },
                  { class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" }
                )
              end

              div do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Trace ID" }
                form.select(
                  :trace_id,
                  [["All Traces", ""]] + @traces.map { |t| [t[1] || t[0], t[0]] },
                  { selected: @params[:trace_id] },
                  { class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" }
                )
              end

              div do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Start Time" }
                form.datetime_local_field(
                  :start_time,
                  value: @params[:start_time],
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "End Time" }
                form.datetime_local_field(
                  :end_time,
                  value: @params[:end_time],
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div(class: "flex items-end") do
                form.submit(
                  "Apply Filters",
                  class: "w-full inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
                )
              end
            end
          end
        end

        def render_stats_overview
          return unless @flow_data[:stats]

          div(class: "grid grid-cols-1 gap-5 sm:grid-cols-4 mb-6") do
            render_metric_card(
              title: "Total Agents",
              value: @flow_data[:stats][:total_agents],
              color: "blue",
              icon: "bi-person-gear"
            )

            render_metric_card(
              title: "Total Tools",
              value: @flow_data[:stats][:total_tools],
              color: "green",
              icon: "bi-tools"
            )

            render_metric_card(
              title: "Total Calls",
              value: @flow_data[:stats][:total_calls],
              color: "purple",
              icon: "bi-arrow-right-circle"
            )

            render_metric_card(
              title: "Time Range",
              value: format_time_range,
              color: "yellow",
              icon: "bi-clock"
            )
          end
        end

        def render_flow_visualization
          div(class: "bg-white p-6 rounded-lg shadow mb-6") do
            h3(class: "text-lg font-medium text-gray-900 mb-4") { "Flow Diagram" }

            if @flow_data[:nodes].any?
              div(id: "flow-diagram", class: "border border-gray-200 rounded-lg p-4 min-h-96 bg-gray-50") do
                # SVG visualization will be rendered by JavaScript
                svg(
                  id: "flow-svg",
                  class: "w-full h-96",
                  viewBox: "0 0 800 600"
                ) do
                  # Placeholder - actual visualization will be rendered by D3.js or similar
                  text(
                    x: "400",
                    y: "300",
                    text_anchor: "middle",
                    class: "text-gray-500 text-sm",
                    fill: "currentColor"
                  ) { "Flow diagram will render here" }
                end
              end

              # Legend
              div(class: "mt-4 flex flex-wrap gap-4") do
                div(class: "flex items-center") do
                  div(class: "w-4 h-4 bg-blue-500 rounded mr-2")
                  span(class: "text-sm text-gray-600") { "Agents" }
                end
                div(class: "flex items-center") do
                  div(class: "w-4 h-4 bg-green-500 rounded mr-2")
                  span(class: "text-sm text-gray-600") { "Tools" }
                end
                div(class: "flex items-center") do
                  div(class: "w-4 h-4 border-2 border-gray-400 rounded mr-2")
                  span(class: "text-sm text-gray-600") { "Calls" }
                end
                div(class: "flex items-center") do
                  div(class: "w-4 h-4 border-2 border-orange-400 rounded mr-2")
                  span(class: "text-sm text-gray-600") { "Handoffs" }
                end
              end
            else
              div(class: "text-center py-12") do
                i(class: "bi bi-diagram-3 text-6xl text-gray-400 mb-4")
                h3(class: "text-lg font-medium text-gray-900 mb-2") { "No flow data found" }
                p(class: "text-gray-500") { "No agent or tool interactions found for the selected filters." }
              end
            end
          end
        end

        def render_flow_data_tables
          div(class: "grid grid-cols-1 gap-6 lg:grid-cols-2") do
            render_nodes_table
            render_edges_table
          end
        end

        def render_nodes_table
          div(class: "bg-white overflow-hidden shadow rounded-lg") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg leading-6 font-medium text-gray-900") { "Nodes (Agents & Tools)" }
            end

            div(class: "overflow-x-auto") do
              table(class: "min-w-full divide-y divide-gray-200") do
                thead(class: "bg-gray-50") do
                  tr do
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Name" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Type" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Calls" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Avg Duration" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Success Rate" }
                  end
                end

                tbody(class: "bg-white divide-y divide-gray-200") do
                  @flow_data[:nodes].each do |node|
                    tr(class: "hover:bg-gray-50") do
                      td(class: "px-4 py-3 text-sm font-medium text-gray-900") { node[:name] }
                      td(class: "px-4 py-3 text-sm") do
                        render_node_type_badge(node[:type], node[:kind])
                      end
                      td(class: "px-4 py-3 text-sm text-gray-900") { node[:count] }
                      td(class: "px-4 py-3 text-sm text-gray-900") do
                        format_duration(node[:avg_duration])
                      end
                      td(class: "px-4 py-3 text-sm") do
                        render_success_rate_badge(node[:success_rate])
                      end
                    end
                  end
                end
              end
            end
          end
        end

        def render_edges_table
          div(class: "bg-white overflow-hidden shadow rounded-lg") do
            div(class: "px-4 py-5 sm:px-6 border-b border-gray-200") do
              h3(class: "text-lg leading-6 font-medium text-gray-900") { "Connections" }
            end

            div(class: "overflow-x-auto") do
              table(class: "min-w-full divide-y divide-gray-200") do
                thead(class: "bg-gray-50") do
                  tr do
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "From" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "To" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Type" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Count" }
                    th(class: "px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase") { "Avg Duration" }
                  end
                end

                tbody(class: "bg-white divide-y divide-gray-200") do
                  @flow_data[:edges].each do |edge|
                    tr(class: "hover:bg-gray-50") do
                      td(class: "px-4 py-3 text-sm text-gray-900") { format_node_name(edge[:source]) }
                      td(class: "px-4 py-3 text-sm text-gray-900") { format_node_name(edge[:target]) }
                      td(class: "px-4 py-3 text-sm") do
                        render_edge_type_badge(edge[:type])
                      end
                      td(class: "px-4 py-3 text-sm text-gray-900") { edge[:count] }
                      td(class: "px-4 py-3 text-sm text-gray-900") do
                        format_duration(edge[:avg_duration])
                      end
                    end
                  end
                end
              end
            end
          end
        end

        def render_node_type_badge(type, kind = nil)
          case type
          when "agent"
            span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800") do
              "Agent"
            end
          when "tool"
            color = kind == "custom" ? "purple" : "green"
            span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-#{color}-100 text-#{color}-800") do
              kind&.capitalize || "Tool"
            end
          else
            span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800") do
              type.to_s.capitalize
            end
          end
        end

        def render_edge_type_badge(type)
          case type
          when "call"
            span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800") do
              "Call"
            end
          when "handoff"
            span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-800") do
              "Handoff"
            end
          else
            span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800") do
              type.to_s.capitalize
            end
          end
        end

        def render_success_rate_badge(rate)
          return span(class: "text-gray-500") { "N/A" } unless rate

          color = if rate >= 95
                    "green"
                  elsif rate >= 80
                    "yellow"
                  else
                    "red"
                  end

          span(class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-#{color}-100 text-#{color}-800") do
            "#{rate}%"
          end
        end

        def format_node_name(node_id)
          # Remove prefix and format nicely
          node_id.gsub(/^(agent_|tool_)/, '').humanize
        end

        def format_time_range
          return "N/A" unless @flow_data[:stats][:time_range]

          start_time = @flow_data[:stats][:time_range][:start]
          end_time = @flow_data[:stats][:time_range][:end]

          if start_time && end_time
            duration = ((end_time - start_time) / 1.hour).round(1)
            "#{duration}h"
          else
            "N/A"
          end
        end

        def render_visualization_script
          script do
            plain <<~JAVASCRIPT
              document.addEventListener('DOMContentLoaded', function() {
                // Flow data from the server
                const flowData = #{@flow_data.to_json};

                // Simple network visualization using SVG
                const svg = document.getElementById('flow-svg');
                const width = 800;
                const height = 600;

                if (!flowData.nodes || flowData.nodes.length === 0) {
                  return;
                }

                // Clear existing content
                svg.innerHTML = '';

                // Position nodes in a circle for simple layout
                const centerX = width / 2;
                const centerY = height / 2;
                const radius = Math.min(width, height) / 3;

                const nodes = flowData.nodes.map((node, i) => {
                  const angle = (i / flowData.nodes.length) * 2 * Math.PI;
                  return {
                    ...node,
                    x: centerX + radius * Math.cos(angle),
                    y: centerY + radius * Math.sin(angle)
                  };
                });

                // Draw edges first (so they appear behind nodes)
                flowData.edges.forEach(edge => {
                  const sourceNode = nodes.find(n => n.id === edge.source);
                  const targetNode = nodes.find(n => n.id === edge.target);

                  if (sourceNode && targetNode) {
                    const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
                    line.setAttribute('x1', sourceNode.x);
                    line.setAttribute('y1', sourceNode.y);
                    line.setAttribute('x2', targetNode.x);
                    line.setAttribute('y2', targetNode.y);
                    line.setAttribute('stroke', edge.type === 'handoff' ? '#f59e0b' : '#6b7280');
                    line.setAttribute('stroke-width', Math.max(1, Math.log(edge.count + 1)));
                    line.setAttribute('opacity', '0.6');
                    svg.appendChild(line);

                    // Add edge label
                    const textX = (sourceNode.x + targetNode.x) / 2;
                    const textY = (sourceNode.y + targetNode.y) / 2;
                    const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
                    text.setAttribute('x', textX);
                    text.setAttribute('y', textY);
                    text.setAttribute('text-anchor', 'middle');
                    text.setAttribute('font-size', '10');
                    text.setAttribute('fill', '#374151');
                    text.textContent = edge.count;
                    svg.appendChild(text);
                  }
                });

                // Draw nodes
                nodes.forEach(node => {
                  const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
                  circle.setAttribute('cx', node.x);
                  circle.setAttribute('cy', node.y);
                  circle.setAttribute('r', Math.max(15, Math.log(node.count + 1) * 5));
                  circle.setAttribute('fill', node.type === 'agent' ? '#3b82f6' : '#10b981');
                  circle.setAttribute('opacity', '0.8');
                  circle.setAttribute('stroke', '#ffffff');
                  circle.setAttribute('stroke-width', '2');
                  svg.appendChild(circle);

                  // Add node label
                  const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
                  text.setAttribute('x', node.x);
                  text.setAttribute('y', node.y + 25);
                  text.setAttribute('text-anchor', 'middle');
                  text.setAttribute('font-size', '12');
                  text.setAttribute('font-weight', 'bold');
                  text.setAttribute('fill', '#374151');
                  text.textContent = node.name;
                  svg.appendChild(text);
                });
              });
            JAVASCRIPT
          end
        end
      end
    end
  end
end
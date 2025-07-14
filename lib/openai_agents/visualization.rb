# frozen_string_literal: true

require "json"
require "erb"

# base64 was moved to a bundled gem in Ruby 3.4+
begin
  require "base64"
rescue LoadError
  # If base64 gem is not available, provide basic fallback
  module Base64
    def self.encode64(data)
      [data].pack("m0")
    end

    def self.decode64(data)
      data.unpack1("m0")
    end
  end
end

module OpenAIAgents
  ##
  # Visualization System for OpenAI Agents
  #
  # This module provides comprehensive visualization capabilities for agent traces,
  # workflows, performance metrics, and execution flows. It supports multiple output
  # formats including ASCII art, HTML reports, and Mermaid diagrams.
  #
  # == Visualization Types
  #
  # * **TraceVisualizer**: ASCII and Mermaid trace visualization
  # * **HTMLVisualizer**: Web-based interactive trace reports
  # * **WorkflowVisualizer**: Agent workflow and handoff diagrams
  # * **MetricsChart**: Performance and usage charts
  #
  # == Output Formats
  #
  # * **ASCII**: Terminal-friendly text-based visualizations
  # * **HTML**: Rich web-based reports with interactive elements
  # * **Mermaid**: Diagram markup for integration with documentation
  # * **Timeline**: Chronological execution flow visualization
  #
  # @example Basic trace visualization
  #   visualizer = OpenAIAgents::Visualization::TraceVisualizer.new(spans)
  #   puts visualizer.render_ascii
  #   puts visualizer.render_timeline
  #
  # @example HTML report generation
  #   html_report = OpenAIAgents::Visualization::HTMLVisualizer.generate(spans)
  #   File.write("trace_report.html", html_report)
  #
  # @example Workflow visualization
  #   workflow_viz = OpenAIAgents::Visualization::WorkflowVisualizer.new(agents)
  #   puts workflow_viz.render_ascii
  #   mermaid_diagram = workflow_viz.generate_mermaid
  #
  # @example Performance charts
  #   performance_data = { "agent_run" => 150, "tool_call" => 75, "llm_call" => 200 }
  #   chart = OpenAIAgents::Visualization::MetricsChart.generate_performance_chart(performance_data)
  #   puts chart
  #
  # @author OpenAI Agents Ruby Team
  # @since 0.1.0
  # @see OpenAIAgents::Tracing::SpanTracer For trace data collection
  module Visualization
    ##
    # ASCII-based trace visualizer
    #
    # Provides text-based visualization of agent execution traces, including
    # hierarchical span trees, timeline views, and Mermaid diagram generation.
    # Designed for terminal output and text-based reports.
    #
    # @example Basic trace visualization
    #   visualizer = TraceVisualizer.new(spans)
    #   puts visualizer.render_ascii     # Tree view
    #   puts visualizer.render_timeline  # Timeline view
    #   puts visualizer.generate_mermaid # Diagram markup
    class TraceVisualizer
      def initialize(spans)
        @spans = spans.is_a?(Array) ? spans : [spans]
        @trace_tree = build_trace_tree
      end

      def render_ascii
        output = []
        output << "Trace Visualization"
        output << ("=" * 50)
        output << ""

        render_spans_ascii(@trace_tree, output, 0)

        output.join("\n")
      end

      def render_timeline
        return "No spans to visualize" if @spans.empty?

        # Sort spans by start time  
        sorted_spans = @spans.sort_by do |s|
          start_time = s.is_a?(Hash) ? s[:start_time] : s.start_time
          start_time.is_a?(String) ? start_time : start_time.iso8601
        end

        output = []
        output << "Timeline View"
        output << ("=" * 80)
        output << ""

        # Find time range
        start_times = sorted_spans.map do |s|
          start_time = s.is_a?(Hash) ? s[:start_time] : s.start_time
          start_time.is_a?(String) ? Time.parse(start_time) : start_time
        end
        end_times = sorted_spans.map do |s|
          end_time = s.is_a?(Hash) ? s[:end_time] : s.end_time
          if end_time
            end_time.is_a?(String) ? Time.parse(end_time) : end_time
          else
            start_times.last
          end
        end

        min_time = start_times.min
        max_time = end_times.max
        total_duration = max_time - min_time

        sorted_spans.each do |span|
          start_time_val = span.is_a?(Hash) ? span[:start_time] : span.start_time
          start_time = start_time_val.is_a?(String) ? Time.parse(start_time_val) : start_time_val
          
          end_time_val = span.is_a?(Hash) ? span[:end_time] : span.end_time
          end_time = if end_time_val
                       end_time_val.is_a?(String) ? Time.parse(end_time_val) : end_time_val
                     else
                       start_time
                     end

          # Calculate relative position and width
          rel_start = ((start_time - min_time) / total_duration * 60).to_i
          duration = end_time - start_time
          rel_width = [1, (duration / total_duration * 60).to_i].max

          # Create timeline bar
          timeline = " " * 60
          (rel_start...[rel_start + rel_width, 60].min).each do |i|
            timeline[i] = "█"
          end

          span_name = span.is_a?(Hash) ? span[:name] : span.name
          duration_ms = span.is_a?(Hash) ? span[:duration_ms] : (duration * 1000).round(2)

          output << "#{span_name.ljust(20)} |#{timeline}| #{duration_ms}ms"
        end

        output << ""
        output << "Total duration: #{(total_duration * 1000).round(2)}ms"

        output.join("\n")
      end

      def generate_mermaid
        return "graph TD\n  A[No spans to visualize]" if @spans.empty?

        mermaid = ["graph TD"]
        node_id = 0

        @spans.each do |span|
          span_name = span.is_a?(Hash) ? span[:name] : span.name
          status = span.is_a?(Hash) ? span[:status] : span.status
          duration = span.is_a?(Hash) ? span[:duration_ms] : (span.respond_to?(:duration_ms) ? span.duration_ms : "unknown")

          node_label = "#{span_name}\\n#{duration}ms"
          node_style = status == :error ? "fill:#ffebee" : "fill:#e8f5e8"

          mermaid << "  #{node_id}[\"#{node_label}\"]"
          mermaid << "  style #{node_id} #{node_style}"

          # Add parent-child relationships
          parent_id = span.is_a?(Hash) ? span[:parent_id] : span.parent_id
          if parent_id
            parent_node = @spans.find_index do |s|
              span_id = s.is_a?(Hash) ? s[:span_id] : s.span_id
              span_id == parent_id
            end
            mermaid << "  #{parent_node} --> #{node_id}" if parent_node
          end

          node_id += 1
        end

        mermaid.join("\n")
      end

      private

      def build_trace_tree
        # Group spans by parent_id
        spans_by_parent = {}
        root_spans = []

        @spans.each do |span|
          parent_id = span.is_a?(Hash) ? span[:parent_id] : span.parent_id
          if parent_id
            spans_by_parent[parent_id] ||= []
            spans_by_parent[parent_id] << span
          else
            root_spans << span
          end
        end

        # Build tree structure
        # rubocop:disable Lint/NestedMethodDefinition
        def build_children(span, spans_by_parent)
          span_id = span.is_a?(Hash) ? span[:span_id] : span.span_id
          children = spans_by_parent[span_id] || []
          {
            span: span,
            children: children.map { |child| build_children(child, spans_by_parent) }
          }
        end
        # rubocop:enable Lint/NestedMethodDefinition

        root_spans.map { |span| build_children(span, spans_by_parent) }
      end

      def render_spans_ascii(tree_nodes, output, depth)
        tree_nodes.each_with_index do |node, index|
          span = node[:span]
          is_last = index == tree_nodes.length - 1

          # Create indentation
          prefix = "  " * depth
          connector = is_last ? "└─ " : "├─ "

          # Span info
          span_name = span.is_a?(Hash) ? span[:name] : span.name
          status = span.is_a?(Hash) ? span[:status] : span.status
          duration = span.is_a?(Hash) ? span[:duration_ms] : (span.respond_to?(:duration_ms) ? span.duration_ms : "unknown")

          status_icon = case status
                        when :error then "❌"
                        when :ok then "✅"
                        else "⏸️"
                        end

          output << "#{prefix}#{connector}#{status_icon} #{span_name} (#{duration}ms)"

          # Add span details if available
          attributes = span.is_a?(Hash) ? (span[:attributes] || {}) : (span.respond_to?(:attributes) ? span.attributes : {})
          if attributes.any?
            detail_prefix = "  " * (depth + 1)
            detail_connector = is_last ? "   " : "│  "

            attributes.each do |key, value|
              next if key == "duration_ms" # Already shown

              output << "#{detail_prefix}#{detail_connector}#{key}: #{value}"
            end
          end

          # Render children
          next unless node[:children].any?

          # rubocop:disable Lint/Void
          is_last ? "  " : "│ "
          # rubocop:enable Lint/Void
          render_spans_ascii(node[:children], output, depth + 1)
        end
      end
    end

    ##
    # HTML-based visualizer for web display
    #
    # The HTMLVisualizer generates rich, interactive HTML reports from trace data,
    # providing a comprehensive web-based view of agent execution. It includes
    # timeline visualizations, span details, and flow diagrams using Mermaid.
    #
    # == Generated Report Features
    #
    # * **Summary Section**: Trace overview with key metrics
    # * **Interactive Timeline**: Visual timeline bars showing span execution
    # * **Detailed Span View**: Expandable span information with attributes
    # * **Flow Diagram**: Mermaid-based visual flow representation
    # * **Responsive Design**: Works on desktop and mobile devices
    #
    # == HTML Structure
    #
    # The generated HTML includes:
    # - Embedded CSS for styling
    # - Mermaid.js for diagram rendering
    # - ERB template processing for dynamic content
    # - Responsive layout with proper semantic structure
    #
    # @example Generate HTML report
    #   html_content = HTMLVisualizer.generate(spans)
    #   File.write("trace_report.html", html_content)
    #
    # @example With trace summary
    #   summary = { trace_id: "abc123", status: "success" }
    #   html_content = HTMLVisualizer.generate(spans, summary)
    #
    # @author OpenAI Agents Ruby Team
    # @since 0.1.0
    # @see TraceVisualizer For ASCII-based visualization
    class HTMLVisualizer
      TEMPLATE = <<~HTML.freeze
        <!DOCTYPE html>
        <html>
        <head>
          <title>Agent Trace Visualization</title>
          <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .trace-container { max-width: 1200px; margin: 0 auto; }
            .span {#{" "}
              border: 1px solid #ddd;#{" "}
              margin: 5px 0;#{" "}
              padding: 10px;#{" "}
              border-radius: 5px;
              background: #f9f9f9;
            }
            .span.error { background: #ffebee; border-color: #f44336; }
            .span.success { background: #e8f5e8; border-color: #4caf50; }
            .span-header { font-weight: bold; margin-bottom: 5px; }
            .span-details { font-size: 0.9em; color: #666; }
            .timeline { margin: 20px 0; }
            .timeline-bar {
              height: 30px;
              background: linear-gradient(90deg, #4caf50, #2196f3);
              border-radius: 15px;
              position: relative;
              margin: 10px 0;
            }
            .timeline-label { text-align: center; padding: 5px; color: white; }
            .agents-list { display: flex; flex-wrap: wrap; gap: 20px; margin: 20px 0; }
            .agent-card {
              border: 1px solid #ddd;
              padding: 15px;
              border-radius: 8px;
              background: #f5f5f5;
              min-width: 250px;
            }
            .mermaid { text-align: center; margin: 20px 0; }
          </style>
          <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
        </head>
        <body>
          <div class="trace-container">
            <h1>Agent Trace Visualization</h1>
        #{"    "}
            <h2>Summary</h2>
            <div class="summary">
              <p><strong>Trace ID:</strong> <%= trace_id %></p>
              <p><strong>Total Spans:</strong> <%= total_spans %></p>
              <p><strong>Total Duration:</strong> <%= total_duration %>ms</p>
              <p><strong>Status:</strong> <%= status %></p>
            </div>
        #{"    "}
            <h2>Timeline</h2>
            <div class="timeline">
              <% timeline_spans.each do |span| %>
                <div class="timeline-bar" style="width: <%= span[:width] %>%; margin-left: <%= span[:offset] %>%;">
                  <div class="timeline-label"><%= span[:name] %> (<%= span[:duration] %>ms)</div>
                </div>
              <% end %>
            </div>
        #{"    "}
            <h2>Spans</h2>
            <div class="spans">
              <% spans.each do |span| %>
                <div class="span <%= span[:status] %>">
                  <div class="span-header">
                    <%= span[:name] %>#{" "}
                    <span style="float: right;"><%= span[:duration] %>ms</span>
                  </div>
                  <div class="span-details">
                    <p><strong>Span ID:</strong> <%= span[:span_id] %></p>
                    <% if span[:parent_id] %>
                      <p><strong>Parent ID:</strong> <%= span[:parent_id] %></p>
                    <% end %>
                    <p><strong>Start:</strong> <%= span[:start_time] %></p>
                    <% if span[:end_time] %>
                      <p><strong>End:</strong> <%= span[:end_time] %></p>
                    <% end %>
        #{"            "}
                    <% if span[:attributes].any? %>
                      <h4>Attributes:</h4>
                      <ul>
                        <% span[:attributes].each do |key, value| %>
                          <li><strong><%= key %>:</strong> <%= value %></li>
                        <% end %>
                      </ul>
                    <% end %>
        #{"            "}
                    <% if span[:events].any? %>
                      <h4>Events:</h4>
                      <ul>
                        <% span[:events].each do |event| %>
                          <li><strong><%= event['name'] %>:</strong> <%= event['timestamp'] %></li>
                        <% end %>
                      </ul>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
        #{"    "}
            <h2>Flow Diagram</h2>
            <div class="mermaid">
              <%= mermaid_diagram %>
            </div>
        #{"    "}
            <script>
              mermaid.initialize({ startOnLoad: true });
            </script>
          </div>
        </body>
        </html>
      HTML

      ##
      # Generate complete HTML report from spans data
      #
      # Creates a comprehensive HTML document with embedded CSS, JavaScript,
      # and interactive elements for visualizing trace execution. The report
      # includes summary statistics, timeline visualization, and detailed
      # span information.
      #
      # @param spans [Array<Hash, Span>] span data to visualize
      # @param trace_summary [Hash, nil] optional trace summary information
      # @return [String] complete HTML document
      #
      # @example Basic usage
      #   spans = tracer.export_spans
      #   html = HTMLVisualizer.generate(spans)
      #   File.write("report.html", html)
      #
      # @example With custom summary
      #   summary = { trace_id: "trace_123", status: "success", custom_field: "value" }
      #   html = HTMLVisualizer.generate(spans, summary)
      def self.generate(spans, trace_summary = nil)
        spans_data = prepare_spans_data(spans)
        timeline_spans = prepare_timeline_data(spans_data)
        mermaid_diagram = TraceVisualizer.new(spans).generate_mermaid

        # Define variables for ERB template
        trace_id = spans_data.first&.dig(:trace_id) || "unknown"
        total_spans = spans_data.length
        total_duration = spans_data.sum { |s| s[:duration] || 0 }
        status = spans_data.any? { |s| s[:status] == :error } ? "error" : "success"
        spans = spans_data

        template = ERB.new(TEMPLATE)
        template.result(binding)
      end

      ##
      # Prepare span data for HTML template processing
      #
      # Normalizes span data from various formats (Hash or Span objects) into
      # a consistent structure suitable for ERB template processing. Handles
      # time conversion, attribute extraction, and event formatting.
      #
      # @param spans [Array<Hash, Span>] raw span data
      # @return [Array<Hash>] normalized span data with consistent fields
      #
      # @api private
      def self.prepare_spans_data(spans)
        spans.map do |span|
          {
            span_id: span.is_a?(Hash) ? span[:span_id] : span.span_id,
            trace_id: span.is_a?(Hash) ? span[:trace_id] : (span.respond_to?(:trace_id) ? span.trace_id : nil),
            parent_id: span.is_a?(Hash) ? span[:parent_id] : span.parent_id,
            name: span.is_a?(Hash) ? span[:name] : span.name,
            start_time: span.is_a?(Hash) ? span[:start_time] : span.start_time&.iso8601,
            end_time: span.is_a?(Hash) ? span[:end_time] : span.end_time&.iso8601,
            duration: span.is_a?(Hash) ? span[:duration_ms] : (span.respond_to?(:duration) && span.duration ? (span.duration * 1000).round(2) : 0),
            status: span.is_a?(Hash) ? span[:status] : (span.respond_to?(:status) ? span.status : nil),
            attributes: span.is_a?(Hash) ? (span[:attributes] || {}) : (span.respond_to?(:attributes) ? span.attributes : {}),
            events: span.is_a?(Hash) ? (span[:events] || []) : (span.respond_to?(:events) ? span.events : [])
          }
        end
      end

      ##
      # Prepare timeline visualization data for HTML rendering
      #
      # Calculates relative positioning and sizing for timeline bars based on
      # span start times and durations. Creates percentage-based positioning
      # data suitable for CSS styling.
      #
      # @param spans_data [Array<Hash>] normalized span data
      # @return [Array<Hash>] timeline data with offset and width percentages
      #
      # @api private
      def self.prepare_timeline_data(spans_data)
        return [] if spans_data.empty?

        # Find time range
        start_times = spans_data.map do |s|
          start_time = s[:start_time]
          start_time.is_a?(String) ? Time.parse(start_time) : start_time
        end
        end_times = spans_data.map do |s|
          end_time = s[:end_time]
          if end_time
            end_time.is_a?(String) ? Time.parse(end_time) : end_time
          else
            start_times.last
          end
        end

        min_time = start_times.min
        max_time = end_times.max
        total_duration = max_time - min_time

        spans_data.map do |span|
          start_time_val = span[:start_time]
          start_time = start_time_val.is_a?(String) ? Time.parse(start_time_val) : start_time_val
          
          end_time_val = span[:end_time]
          end_time = if end_time_val
                       end_time_val.is_a?(String) ? Time.parse(end_time_val) : end_time_val
                     else
                       start_time
                     end

          offset = ((start_time - min_time) / total_duration * 100)
          width = [1, ((end_time - start_time) / total_duration * 100)].max

          {
            name: span[:name],
            duration: span[:duration],
            offset: offset.round(2),
            width: width.round(2)
          }
        end
      end
    end

    ##
    # Agent workflow visualizer
    #
    # The WorkflowVisualizer creates visual representations of agent workflows,
    # showing agent relationships, tool usage, and handoff patterns. It supports
    # both ASCII text output for terminal display and Mermaid diagram generation
    # for documentation and web display.
    #
    # == Visualization Types
    #
    # * **ASCII Workflow**: Text-based agent and tool listing
    # * **Mermaid Diagram**: Graph-based visual workflow representation
    # * **Tool Mapping**: Shows which tools each agent can use
    # * **Handoff Visualization**: Displays agent-to-agent delegation patterns
    #
    # == Diagram Elements
    #
    # * **Agent Nodes**: Blue boxes representing individual agents
    # * **Tool Nodes**: Orange boxes representing available tools
    # * **Handoff Arrows**: Dashed lines showing delegation paths
    # * **Tool Connections**: Solid lines showing tool accessibility
    #
    # @example Basic workflow visualization
    #   agents = [agent1, agent2, agent3]
    #   visualizer = WorkflowVisualizer.new(agents)
    #   puts visualizer.render_ascii
    #
    # @example Generate Mermaid diagram
    #   visualizer = WorkflowVisualizer.new(agents)
    #   mermaid_code = visualizer.generate_mermaid
    #   # Use in documentation or web pages
    #
    # @author OpenAI Agents Ruby Team
    # @since 0.1.0
    # @see OpenAIAgents::Agent For agent configuration
    class WorkflowVisualizer
      ##
      # Initialize visualizer with agent collection
      #
      # @param agents [Array<Agent>, Agent] single agent or array of agents to visualize
      def initialize(agents)
        @agents = agents.is_a?(Array) ? agents : [agents]
      end

      ##
      # Generate Mermaid diagram code for agent workflow
      #
      # Creates a Mermaid graph definition showing agents, their tools, and
      # handoff relationships. The diagram uses different node styles and
      # connection types to distinguish between agents, tools, and relationships.
      #
      # @return [String] Mermaid diagram code
      #
      # @example Generate and save diagram
      #   mermaid_code = visualizer.generate_mermaid
      #   File.write("workflow.mmd", mermaid_code)
      def generate_mermaid
        mermaid = ["graph TD"]

        @agents.each_with_index do |agent, index|
          agent_name = agent.is_a?(Hash) ? agent[:name] : agent.name

          # Add agent node
          mermaid << "  A#{index}[\"#{agent_name}\"]"

          # Add tool nodes
          tools = agent.is_a?(Hash) ? agent[:tools] : agent.tools
          if tools.is_a?(Array) && tools.any?
            tools.each_with_index do |tool, tool_index|
              tool_name = tool.is_a?(Hash) ? tool[:name] : tool.name
              tool_id = "T#{index}_#{tool_index}"

              mermaid << "  #{tool_id}[\"🔧 #{tool_name}\"]"
              mermaid << "  A#{index} --> #{tool_id}"
              mermaid << "  style #{tool_id} fill:#fff3e0"
            end
          end

          # Add handoff connections
          handoffs = agent.is_a?(Hash) ? agent[:handoffs] : agent.handoffs
          if handoffs.is_a?(Array) && handoffs.any?
            handoffs.each do |handoff|
              handoff_name = handoff.is_a?(Hash) ? handoff[:name] : handoff.name
              target_index = @agents.find_index do |a|
                target_name = a.is_a?(Hash) ? a[:name] : a.name
                target_name == handoff_name
              end

              mermaid << "  A#{index} -.->|handoff| A#{target_index}" if target_index
            end
          end

          # Style agent nodes
          mermaid << "  style A#{index} fill:#e3f2fd"
        end

        mermaid.join("\n")
      end

      ##
      # Render ASCII text representation of agent workflow
      #
      # Creates a terminal-friendly text visualization showing each agent's
      # name, available tools, and possible handoff targets. Useful for
      # debugging and console output.
      #
      # @return [String] formatted ASCII representation
      #
      # @example Display workflow in console
      #   puts visualizer.render_ascii
      def render_ascii
        output = []
        output << "Agent Workflow"
        output << ("=" * 40)
        output << ""

        @agents.each do |agent|
          agent_name = agent.is_a?(Hash) ? agent[:name] : agent.name
          output << "Agent: #{agent_name}"

          # Show tools
          tools = agent.is_a?(Hash) ? agent[:tools] : agent.tools
          if tools.is_a?(Array) && tools.any?
            output << "  Tools:"
            tools.each do |tool|
              tool_name = tool.is_a?(Hash) ? tool[:name] : tool.name
              output << "    🔧 #{tool_name}"
            end
          else
            output << "  Tools: None"
          end

          # Show handoffs
          handoffs = agent.is_a?(Hash) ? agent[:handoffs] : agent.handoffs
          if handoffs.is_a?(Array) && handoffs.any?
            output << "  Can handoff to:"
            handoffs.each do |handoff|
              handoff_name = handoff.is_a?(Hash) ? handoff[:name] : handoff.name
              output << "    ➤ #{handoff_name}"
            end
          else
            output << "  Handoffs: None"
          end

          output << ""
        end

        output.join("\n")
      end
    end

    ##
    # Chart generator for metrics and performance data
    #
    # The MetricsChart class provides ASCII-based chart generation for
    # performance metrics, usage statistics, and other quantitative data.
    # Designed for terminal output and text-based reporting.
    #
    # == Chart Types
    #
    # * **Performance Charts**: Execution time and duration metrics
    # * **Usage Charts**: Agent utilization and call frequency
    # * **Bar Charts**: Horizontal bar representations with scaling
    # * **Percentage Charts**: Usage distribution with percentages
    #
    # == Features
    #
    # * **Auto-scaling**: Charts automatically scale to fit data ranges
    # * **Unicode Blocks**: Uses block characters for visual appeal
    # * **Label Alignment**: Consistent formatting with proper spacing
    # * **Summary Statistics**: Includes totals and calculated metrics
    #
    # @example Performance metrics
    #   performance_data = {
    #     "agent_run" => 150,
    #     "tool_call" => 75,
    #     "llm_call" => 200
    #   }
    #   chart = MetricsChart.generate_performance_chart(performance_data)
    #   puts chart
    #
    # @example Usage statistics
    #   usage_data = { "Agent1" => 45, "Agent2" => 30, "Agent3" => 25 }
    #   chart = MetricsChart.generate_usage_chart(usage_data)
    #   puts chart
    #
    # @author OpenAI Agents Ruby Team
    # @since 0.1.0
    class MetricsChart
      ##
      # Generate ASCII bar chart for performance metrics
      #
      # Creates a horizontal bar chart showing performance data with automatic
      # scaling and consistent formatting. Each bar represents a metric value
      # relative to the maximum value in the dataset.
      #
      # @param data [Hash<String, Numeric>] performance data with labels and values
      # @return [String] formatted ASCII bar chart
      #
      # @example Timing metrics
      #   timings = {
      #     "Database Query" => 250,
      #     "API Call" => 180,
      #     "Processing" => 95
      #   }
      #   puts MetricsChart.generate_performance_chart(timings)
      #   
      #   # Output:
      #   # Performance Metrics
      #   # ========================================
      #   # 
      #   # Database Query  |█████████████████████████████| 250
      #   # API Call        |█████████████████████         | 180
      #   # Processing      |███████████                   | 95
      def self.generate_performance_chart(data)
        # Simple ASCII bar chart
        output = []
        output << "Performance Metrics"
        output << ("=" * 40)
        output << ""

        max_value = data.values.max.to_f

        data.each do |label, value|
          bar_length = (value / max_value * 30).to_i
          bar = "█" * bar_length
          output << "#{label.ljust(15)} |#{bar.ljust(30)}| #{value}"
        end

        output.join("\n")
      end

      ##
      # Generate ASCII bar chart for agent usage statistics
      #
      # Creates a horizontal bar chart showing agent usage distribution with
      # percentages and total counts. Includes summary statistics and
      # percentage calculations for each agent.
      #
      # @param agents_usage [Hash<String, Integer>] agent usage data with names and call counts
      # @return [String] formatted ASCII chart with usage statistics
      #
      # @example Agent call frequency
      #   usage_stats = {
      #     "SearchAgent" => 45,
      #     "AnalysisAgent" => 30,
      #     "ReportAgent" => 25
      #   }
      #   puts MetricsChart.generate_usage_chart(usage_stats)
      #   
      #   # Output:
      #   # Agent Usage Statistics
      #   # ========================================
      #   # 
      #   # SearchAgent     |████████████████████████████████████████| 45 (45.0%)
      #   # AnalysisAgent   |███████████████████████████             | 30 (30.0%)
      #   # ReportAgent     |█████████████████████                   | 25 (25.0%)
      #   # 
      #   # Total calls: 100
      def self.generate_usage_chart(agents_usage)
        output = []
        output << "Agent Usage Statistics"
        output << ("=" * 40)
        output << ""

        total_calls = agents_usage.values.sum
        return "No usage data available" if total_calls.zero?

        agents_usage.each do |agent, calls|
          percentage = (calls.to_f / total_calls * 100).round(1)
          bar_length = (percentage / 100 * 40).to_i
          bar = "▓" * bar_length

          output << "#{agent.ljust(15)} |#{bar.ljust(40)}| #{calls} (#{percentage}%)"
        end

        output << ""
        output << "Total calls: #{total_calls}"

        output.join("\n")
      end
    end
  end
end

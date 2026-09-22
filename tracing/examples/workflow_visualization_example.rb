#!/usr/bin/env ruby
# frozen_string_literal: true

# Workflow Visualization Example
#
# This example demonstrates the comprehensive visualization tools built into
# the RAAF (Ruby AI Agents Factory) gem. The visualization system provides:
#
# - ASCII trace visualization for console output
# - Interactive HTML reports with charts and graphs
# - Mermaid diagram generation for workflow documentation
# - Timeline views for execution analysis
# - Performance metrics visualization
# - Agent usage statistics and patterns
# - Workflow topology mapping
#
# This is essential for:
# - Understanding complex multi-agent workflows
# - Performance analysis and optimization
# - Documentation and knowledge sharing
# - Debugging and troubleshooting
# - Stakeholder reporting and communication
# - Workflow optimization and improvement

require "raaf"

# ============================================================================
# ENVIRONMENT VALIDATION
# ============================================================================

unless ENV["OPENAI_API_KEY"]
  puts "🚨 OPENAI_API_KEY environment variable is required"
  puts "Please set it with: export OPENAI_API_KEY='your-api-key'"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  puts
  puts "=== Demo Mode ==="
  puts "This example will demonstrate visualization tools without making API calls"
  puts
end

# ============================================================================
# VISUALIZATION TOOLS SETUP
# ============================================================================

puts "=== Workflow Visualization Example ==="
puts "Demonstrates comprehensive workflow visualization and reporting tools"
puts "-" * 70

# Example 1: Basic Visualization Setup
puts "\n=== Example 1: Visualization Tool Configuration ==="

# Create visualization tools using available classes
nil # Will be created with sample data
nil # Will be created with agent data

puts "✅ Visualizer components available:"
puts "  - TraceVisualizer: ASCII and timeline traces"
puts "  - HTMLVisualizer: Interactive HTML reports"
puts "  - WorkflowVisualizer: Agent workflow diagrams"
puts "  - MetricsChart: Performance and usage charts"

# Example 2: Sample Workflow Data Generation
puts "\n=== Example 2: Sample Workflow Data Generation ==="

# Generate comprehensive sample trace data for visualization
sample_workflow = {
  workflow_id: "wf_#{Time.now.to_i}",
  name: "Multi-Agent Data Processing Pipeline",
  start_time: Time.now - 300,  # 5 minutes ago
  end_time: Time.now,
  total_duration: 300_000,     # 5 minutes in milliseconds

  agents: [
    {
      name: "DataIngester",
      model: "gpt-4o",
      instructions: "Process and validate incoming data",
      total_runtime: 45_000,
      tool_calls: 8,
      handoffs: 2
    },
    {
      name: "DataAnalyzer",
      model: "gpt-4o",
      instructions: "Analyze data patterns and generate insights",
      total_runtime: 120_000,
      tool_calls: 15,
      handoffs: 1
    },
    {
      name: "ReportGenerator",
      model: "gpt-4o",
      instructions: "Generate comprehensive reports from analysis",
      total_runtime: 75_000,
      tool_calls: 6,
      handoffs: 0
    }
  ],

  spans: [
    {
      span_id: "span_001",
      name: "workflow.start",
      agent: "DataIngester",
      start_time: Time.now - 300,
      end_time: Time.now - 255,
      duration: 45_000,
      type: "agent",
      metadata: {
        input_size: 1024,
        processing_mode: "batch",
        validation_rules: 5
      }
    },
    {
      span_id: "span_002",
      parent_id: "span_001",
      name: "tool.validate_data",
      agent: "DataIngester",
      start_time: Time.now - 290,
      end_time: Time.now - 285,
      duration: 5_000,
      type: "tool",
      metadata: {
        tool_name: "validate_data",
        records_processed: 150,
        validation_errors: 3
      }
    },
    {
      span_id: "span_003",
      parent_id: "span_001",
      name: "handoff.to_analyzer",
      agent: "DataIngester",
      start_time: Time.now - 260,
      end_time: Time.now - 255,
      duration: 5_000,
      type: "handoff",
      metadata: {
        target_agent: "DataAnalyzer",
        handoff_reason: "data_validation_complete",
        data_size: 1024
      }
    },
    {
      span_id: "span_004",
      name: "workflow.analyze",
      agent: "DataAnalyzer",
      start_time: Time.now - 255,
      end_time: Time.now - 135,
      duration: 120_000,
      type: "agent",
      metadata: {
        analysis_type: "pattern_detection",
        algorithms_used: %w[clustering regression anomaly_detection]
      }
    },
    {
      span_id: "span_005",
      parent_id: "span_004",
      name: "tool.pattern_analysis",
      agent: "DataAnalyzer",
      start_time: Time.now - 240,
      end_time: Time.now - 200,
      duration: 40_000,
      type: "tool",
      metadata: {
        tool_name: "pattern_analysis",
        patterns_found: 12,
        confidence_score: 0.87
      }
    },
    {
      span_id: "span_006",
      name: "workflow.report",
      agent: "ReportGenerator",
      start_time: Time.now - 135,
      end_time: Time.now - 60,
      duration: 75_000,
      type: "agent",
      metadata: {
        report_format: "comprehensive",
        sections: %w[summary detailed_analysis recommendations]
      }
    }
  ],

  performance_metrics: {
    total_tokens: 15_750,
    total_cost: 0.24,
    average_response_time: 2.3,
    error_rate: 0.02,
    throughput: 52.5 # operations per minute
  }
}

puts "📊 Generated sample workflow:"
puts "  - Workflow: #{sample_workflow[:name]}"
puts "  - Duration: #{sample_workflow[:total_duration] / 1000}s"
puts "  - Agents: #{sample_workflow[:agents].length}"
puts "  - Spans: #{sample_workflow[:spans].length}"
puts "  - Total cost: $#{sample_workflow[:performance_metrics][:total_cost]}"

# Example 3: ASCII Trace Visualization
puts "\n=== Example 3: ASCII Trace Visualization ==="

# Create trace visualizer with sample spans
trace_visualizer = RAAF::Visualization::TraceVisualizer.new(sample_workflow[:spans])
ascii_chart = trace_visualizer.render_ascii
puts "📈 ASCII Tree Visualization:"
puts ascii_chart

puts "\n📊 ASCII Timeline Visualization:"
timeline_chart = trace_visualizer.render_timeline
puts timeline_chart

# Example 4: Mermaid Diagram Generation
puts "\n=== Example 4: Mermaid Workflow Diagram ==="

# Generate Mermaid diagram for traces
mermaid_trace_diagram = trace_visualizer.generate_mermaid
puts "🔄 Mermaid Trace Diagram:"
puts mermaid_trace_diagram

# Generate Mermaid diagram for agent workflow
workflow_visualizer = RAAF::Visualization::WorkflowVisualizer.new(sample_workflow[:agents])
mermaid_workflow_diagram = workflow_visualizer.generate_mermaid
puts "\n🤖 Mermaid Agent Workflow:"
puts mermaid_workflow_diagram

puts "\n💡 To view these diagrams:"
puts "   1. Copy the code above"
puts "   2. Visit https://mermaid.live/"
puts "   3. Paste and render the diagram"

# Example 5: Performance Metrics Visualization
puts "\n=== Example 5: Performance Metrics Visualization ==="

# Generate performance charts using MetricsChart
performance_chart_data = {}
sample_workflow[:agents].each do |agent|
  performance_chart_data[agent[:name]] = agent[:total_runtime] / 1000.0 # Convert to seconds
end

puts "⚡ Performance Analysis:"
performance_chart = RAAF::Visualization::MetricsChart.generate_performance_chart(performance_chart_data)
puts performance_chart

puts "\n  Tool Call Distribution:"
tool_usage_data = {}
sample_workflow[:agents].each do |agent|
  tool_usage_data[agent[:name]] = agent[:tool_calls]
end
usage_chart = RAAF::Visualization::MetricsChart.generate_usage_chart(tool_usage_data)
puts usage_chart

puts "\n  Cost Breakdown:"
puts "    Total Cost: $#{sample_workflow[:performance_metrics][:total_cost]}"
puts "    Cost per Agent (estimated):"
sample_workflow[:agents].each do |agent|
  cost_ratio = agent[:total_runtime].to_f / sample_workflow[:total_duration]
  agent_cost = (sample_workflow[:performance_metrics][:total_cost] * cost_ratio).round(4)
  puts "      #{agent[:name]}: $#{agent_cost}"
end

# Example 6: Workflow ASCII Visualization
puts "\n=== Example 6: Workflow ASCII Visualization ==="

workflow_ascii = workflow_visualizer.render_ascii
puts "🗺️  Agent Workflow:"
puts workflow_ascii

# Example 7: HTML Report Generation
puts "\n=== Example 7: HTML Report Generation ==="

# Generate HTML report using HTMLVisualizer
html_content = RAAF::Visualization::HTMLVisualizer.generate(sample_workflow[:spans])
report_filename = "workflow_report_#{Time.now.to_i}.html"

# Write HTML report to file
File.write(report_filename, html_content)

puts "📄 HTML Report Generated:"
puts "  - Filename: #{report_filename}"
puts "  - Size: #{File.size(report_filename)} bytes"
puts "  - Features: Interactive trace visualization with Mermaid diagrams"

# Example 8: Agent Statistics Summary
puts "\n=== Example 8: Agent Statistics Summary ==="

puts "🤖 Agent Usage Analysis:"
most_active = sample_workflow[:agents].max_by { |a| a[:tool_calls] }
puts "  Most Active Agent: #{most_active[:name]} (#{most_active[:tool_calls]} tool calls)"

most_runtime = sample_workflow[:agents].max_by { |a| a[:total_runtime] }
puts "  Longest Runtime Agent: #{most_runtime[:name]} (#{most_runtime[:total_runtime] / 1000.0}s)"

puts "\n📊 Summary:"
puts "  - HTML report generated: #{report_filename}"
puts "  - ASCII visualizations: trace tree, timeline, workflow"
puts "  - Mermaid diagrams: trace flow, agent workflow"
puts "  - Performance charts: runtime and usage statistics"

# ============================================================================
# CONFIGURATION AND BEST PRACTICES
# ============================================================================

puts "\n=== Configuration ==="
config_info = {
  trace_visualizer: trace_visualizer.class.name,
  workflow_visualizer: workflow_visualizer.class.name,
  html_visualizer: "RAAF::Visualization::HTMLVisualizer",
  metrics_chart: "RAAF::Visualization::MetricsChart",
  features_enabled: %w[ascii_charts mermaid_diagrams html_reports performance_analysis timeline_view],
  export_formats: %w[html ascii mermaid]
}

config_info.each do |key, value|
  puts "#{key}: #{value}"
end

puts "\n=== Best Practices ==="
puts "✅ Use ASCII visualization for quick debugging and console output"
puts "✅ Generate HTML reports for detailed analysis and sharing"
puts "✅ Create Mermaid diagrams for workflow documentation"
puts "✅ Monitor performance metrics to identify optimization opportunities"
puts "✅ Export in multiple formats for different stakeholder needs"
puts "✅ Use custom templates for standardized reporting"
puts "✅ Include timeline views for temporal analysis"
puts "✅ Analyze agent efficiency to improve workflow design"

puts "\n=== Advanced Visualization Techniques ==="
puts "📊 Real-time dashboards: visualizer.create_live_dashboard(workflow_id)"
puts "🔄 Animated timelines: visualizer.generate_animated_timeline(workflow)"
puts "🎯 Focus views: visualizer.focus_on_agent('AgentName')"
puts "📈 Trend analysis: visualizer.analyze_trends(historical_data)"
puts "🖼️  Custom charts: visualizer.create_custom_chart(data, chart_type)"
puts "📱 Mobile-optimized: visualizer.generate_mobile_report(workflow)"

# Clean up generated files
FileUtils.rm_f(report_filename)

puts "\n✅ Visualization example completed and files cleaned up"

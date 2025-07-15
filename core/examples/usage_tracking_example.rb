#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates comprehensive usage tracking for OpenAI Agents Ruby.
# The usage tracking system provides detailed monitoring of API calls, token consumption,
# costs, agent interactions, tool usage, and custom business metrics. It includes
# real-time monitoring, alerting, analytics, and reporting capabilities essential
# for production deployments and business intelligence.

require_relative "../lib/openai_agents"

puts "=== Usage Tracking Example ==="
puts

# ============================================================================
# EXAMPLE 1: BASIC USAGE TRACKING SETUP
# ============================================================================
# Initialize the usage tracking system with storage and real-time monitoring.
# This provides the foundation for comprehensive usage analytics.

puts "Example 1: Basic Usage Tracking Setup"
puts "-" * 50

# Create usage tracker with default settings
usage_tracker = OpenAIAgents::UsageTracking::UsageTracker.new(
  enable_real_time: true,      # Enable real-time monitoring
  retention_days: 90           # Keep data for 90 days
)

puts "Usage Tracker initialized with real-time monitoring"
puts "Data retention: #{usage_tracker.instance_variable_get(:@retention_days)} days"
puts "Storage type: #{usage_tracker.storage.class.name}"
puts

# ============================================================================
# EXAMPLE 2: TRACKING API CALLS AND COSTS
# ============================================================================
# Track API usage with detailed metrics including tokens, costs, and metadata.
# This enables comprehensive cost analysis and optimization.

puts "Example 2: Tracking API Calls and Costs"
puts "-" * 50

# Track different types of API calls
api_calls = [
  {
    provider: "openai",
    model: "gpt-4o",
    tokens_used: { prompt_tokens: 150, completion_tokens: 75, total_tokens: 225 },
    cost: 0.0135,
    duration: 2.3,
    metadata: { agent: "CustomerSupport", user_id: "user123", session_id: "cs_456" }
  },
  {
    provider: "openai", 
    model: "gpt-4o-mini",
    tokens_used: { prompt_tokens: 200, completion_tokens: 100, total_tokens: 300 },
    cost: 0.0018,
    duration: 1.8,
    metadata: { agent: "ContentGenerator", user_id: "user456", session_id: "cg_789" }
  },
  {
    provider: "anthropic",
    model: "claude-3-sonnet-20240229",
    tokens_used: { prompt_tokens: 180, completion_tokens: 90, total_tokens: 270 },
    cost: 0.0081,
    duration: 2.1,
    metadata: { agent: "CodeReviewer", user_id: "user789", session_id: "cr_321" }
  }
]

puts "Tracking API calls..."
api_calls.each_with_index do |call, index|
  event_id = usage_tracker.track_api_call(**call)
  puts "  #{index + 1}. #{call[:provider]}/#{call[:model]} - Cost: $#{call[:cost]} (ID: #{event_id})"
end

puts "API calls tracked successfully"
puts

# ============================================================================
# EXAMPLE 3: TRACKING AGENT INTERACTIONS
# ============================================================================
# Track agent interactions with users including satisfaction scores and outcomes.
# This provides insights into agent performance and user experience.

puts "Example 3: Tracking Agent Interactions"
puts "-" * 50

# Track different agent interaction scenarios
interactions = [
  {
    agent_name: "CustomerSupport",
    user_id: "user123",
    session_id: "cs_456", 
    duration: 180.5,
    message_count: 8,
    satisfaction_score: 4.2,
    outcome: :resolved,
    custom_metrics: {
      issue_category: "billing",
      resolution_time: 120,
      escalation_count: 0,
      first_contact_resolution: true
    }
  },
  {
    agent_name: "TechnicalSupport",
    user_id: "user456",
    session_id: "ts_789",
    duration: 420.0,
    message_count: 15,
    satisfaction_score: 3.8,
    outcome: :escalated,
    custom_metrics: {
      issue_category: "technical",
      resolution_time: 300,
      escalation_count: 1,
      first_contact_resolution: false
    }
  },
  {
    agent_name: "SalesAssistant",
    user_id: "user789",
    session_id: "sa_321",
    duration: 95.2,
    message_count: 5,
    satisfaction_score: 4.8,
    outcome: :resolved,
    custom_metrics: {
      issue_category: "sales",
      conversion_probability: 0.85,
      products_discussed: 3
    }
  }
]

puts "Tracking agent interactions..."
interactions.each_with_index do |interaction, index|
  event_id = usage_tracker.track_agent_interaction(**interaction)
  puts "  #{index + 1}. #{interaction[:agent_name]} - #{interaction[:outcome]} " \
       "(#{interaction[:satisfaction_score]}/5.0) - ID: #{event_id}"
end

puts "Agent interactions tracked successfully"
puts

# ============================================================================
# EXAMPLE 4: TRACKING TOOL USAGE
# ============================================================================
# Track tool usage including execution time, success rates, and data sizes.
# This helps optimize tool performance and identify bottlenecks.

puts "Example 4: Tracking Tool Usage"
puts "-" * 50

# Track various tool usage scenarios
tool_usage = [
  {
    tool_name: "web_search",
    agent_name: "ResearchAssistant",
    execution_time: 3.2,
    success: true,
    input_size: 128,
    output_size: 2048,
    metadata: { search_query: "AI trends 2024", results_count: 10 }
  },
  {
    tool_name: "code_interpreter",
    agent_name: "DeveloperAssistant",
    execution_time: 8.5,
    success: true,
    input_size: 1024,
    output_size: 512,
    metadata: { language: "python", lines_of_code: 45 }
  },
  {
    tool_name: "file_search",
    agent_name: "DocumentAssistant",
    execution_time: 1.8,
    success: true,
    input_size: 64,
    output_size: 1536,
    metadata: { search_pattern: "*.pdf", files_found: 12 }
  },
  {
    tool_name: "image_generator",
    agent_name: "CreativeAssistant",
    execution_time: 12.3,
    success: false,
    input_size: 256,
    output_size: 0,
    metadata: { prompt: "abstract art", error: "rate_limit_exceeded" }
  }
]

puts "Tracking tool usage..."
tool_usage.each_with_index do |tool, index|
  event_id = usage_tracker.track_tool_usage(**tool)
  status = tool[:success] ? "✓" : "✗"
  puts "  #{index + 1}. #{status} #{tool[:tool_name]} - #{tool[:execution_time]}s - ID: #{event_id}"
end

puts "Tool usage tracked successfully"
puts

# ============================================================================
# EXAMPLE 5: CUSTOM EVENT TRACKING
# ============================================================================
# Track custom business events and metrics specific to your application.
# This enables comprehensive business intelligence and KPI monitoring.

puts "Example 5: Custom Event Tracking"
puts "-" * 50

# Track custom business events
custom_events = [
  {
    event_type: :user_signup,
    data: {
      user_id: "user999",
      plan: "premium",
      referral_source: "google_ads",
      trial_length: 14
    },
    metadata: { campaign_id: "camp_123", conversion_value: 99.99 }
  },
  {
    event_type: :feature_usage,
    data: {
      feature: "advanced_analytics",
      user_id: "user123",
      usage_count: 5,
      session_duration: 450
    },
    metadata: { user_tier: "enterprise", feature_adoption: true }
  },
  {
    event_type: :error_occurred,
    data: {
      error_type: "api_timeout",
      agent_name: "CustomerSupport",
      user_id: "user456",
      retry_count: 3
    },
    metadata: { severity: "high", resolution_time: 120 }
  }
]

puts "Tracking custom events..."
custom_events.each_with_index do |event, index|
  event_id = usage_tracker.track_custom_event(event[:event_type], event[:data], 
                                              metadata: event[:metadata])
  puts "  #{index + 1}. #{event[:event_type]} - ID: #{event_id}"
end

puts "Custom events tracked successfully"
puts

# ============================================================================
# EXAMPLE 6: USAGE ANALYTICS AND INSIGHTS
# ============================================================================
# Generate comprehensive analytics from tracked usage data.
# This provides insights for optimization and business decisions.

puts "Example 6: Usage Analytics and Insights"
puts "-" * 50

# Get analytics for different time periods
periods = [:today, :week, :month, :all]

periods.each do |period|
  puts "Analytics for #{period}:"
  analytics = usage_tracker.analytics(period)
  
  puts "  Total events: #{analytics[:total_events]}"
  puts "  API calls: #{analytics[:api_calls][:count]}"
  puts "  Total tokens: #{analytics[:api_calls][:total_tokens]}"
  puts "  Total cost: $#{analytics[:costs][:total].round(4)}"
  puts "  Agent interactions: #{analytics[:agent_interactions][:count]}"
  puts "  Tool usage: #{analytics[:tool_usage][:count]}"
  puts "  Tool success rate: #{analytics[:tool_usage][:success_rate]}%"
  puts
end

# Get analytics grouped by different dimensions
puts "Analytics grouped by provider:"
provider_analytics = usage_tracker.analytics(:all, group_by: :provider)
provider_analytics[:grouped_data].each do |provider, stats|
  puts "  #{provider}: #{stats[:api_calls]} calls, $#{stats[:total_cost].round(4)} cost"
end
puts

puts "Analytics grouped by agent:"
agent_analytics = usage_tracker.analytics(:all, group_by: :agent)
agent_analytics[:grouped_data].each do |agent, stats|
  puts "  #{agent}: #{stats[:interactions]} interactions, #{stats[:total_tokens]} tokens"
end
puts

# ============================================================================
# EXAMPLE 7: REAL-TIME DASHBOARD DATA
# ============================================================================
# Get real-time dashboard data for monitoring current system status.
# This provides live insights for operational monitoring.

puts "Example 7: Real-Time Dashboard Data"
puts "-" * 50

dashboard = usage_tracker.dashboard_data
puts "Real-time dashboard data:"
puts "  Timestamp: #{dashboard[:timestamp]}"
puts "  Current API rate: #{dashboard[:current_api_rate]} calls/min"
puts "  Active sessions: #{dashboard[:active_sessions]}"
puts "  Today's cost: $#{dashboard[:total_cost_today].round(4)}"
puts "  Today's tokens: #{dashboard[:tokens_used_today]}"
puts "  Error rate: #{dashboard[:error_rate]}%"
puts "  Avg response time: #{dashboard[:average_response_time].round(2)}s"
puts "  Alert status: #{dashboard[:alert_status][:active_alerts]}/#{dashboard[:alert_status][:total_alerts]} active"
puts

if dashboard[:top_agents].any?
  puts "  Top agents by usage:"
  dashboard[:top_agents].each do |agent, count|
    puts "    #{agent}: #{count} interactions"
  end
end
puts

# ============================================================================
# EXAMPLE 8: USAGE ALERTS AND MONITORING
# ============================================================================
# Set up real-time alerts for usage thresholds and anomalies.
# This enables proactive monitoring and cost control.

puts "Example 8: Usage Alerts and Monitoring"
puts "-" * 50

puts "Setting up usage alerts..."

# Cost monitoring alerts
usage_tracker.add_alert(:daily_cost_limit) do |data|
  data[:total_cost_today] > 10.0  # Alert if daily cost exceeds $10
end

usage_tracker.add_alert(:high_api_rate) do |data|
  data[:current_api_rate] > 50  # Alert if API rate exceeds 50 calls/min
end

# Performance monitoring alerts
usage_tracker.add_alert(:slow_response_time) do |data|
  data[:average_response_time] > 5.0  # Alert if response time > 5 seconds
end

usage_tracker.add_alert(:high_error_rate) do |data|
  data[:error_rate] > 10.0  # Alert if error rate > 10%
end

# Token usage alerts
usage_tracker.add_alert(:token_usage_spike) do |data|
  data[:tokens_used_today] > 100_000  # Alert if daily tokens > 100k
end

puts "Configured #{usage_tracker.alerts.size} usage alerts:"
usage_tracker.alerts.each do |name, alert|
  puts "  - #{name}: #{alert[:triggered] ? 'TRIGGERED' : 'OK'}"
end
puts

# Simulate checking alerts
puts "Checking alerts..."
# In real usage, alerts are checked automatically when events are tracked
current_dashboard = usage_tracker.dashboard_data
puts "Alert check completed. Status: #{current_dashboard[:alert_status][:active_alerts]} active alerts"
puts

# ============================================================================
# EXAMPLE 9: DATA EXPORT AND REPORTING
# ============================================================================
# Export usage data in various formats for analysis and reporting.
# This enables integration with external analytics tools.

puts "Example 9: Data Export and Reporting"
puts "-" * 50

puts "Available export formats: JSON, CSV, Excel"
puts "Available periods: today, week, month, all"
puts

# Export data in different formats
export_formats = [:json, :csv]
export_formats.each do |format|
  puts "Exporting #{format.upcase} data..."
  
  # Export sample data
  file_path = usage_tracker.export_data(format, :all)
  puts "  Exported to: #{file_path}"
  
  # Check file size
  if File.exist?(file_path)
    file_size = File.size(file_path)
    puts "  File size: #{file_size} bytes"
    
    # Clean up demo files
    File.delete(file_path)
    puts "  Demo file cleaned up"
  end
  puts
end

# Generate comprehensive usage report
puts "Generating usage report..."
report = usage_tracker.generate_report(:all, include_charts: true)
puts "Report generated:"
puts report.summary
puts

# Save report to file
report_file = "usage_report_#{Time.now.strftime('%Y%m%d_%H%M%S')}.html"
report.save_to_file(report_file)
puts "Report saved to: #{report_file}"

# Clean up demo file
File.delete(report_file) if File.exist?(report_file)
puts "Demo report file cleaned up"
puts

# ============================================================================
# EXAMPLE 10: ADVANCED ANALYTICS AND INSIGHTS
# ============================================================================
# Perform advanced analytics to identify patterns and optimization opportunities.
# This provides actionable insights for business decisions.

puts "Example 10: Advanced Analytics and Insights"
puts "-" * 50

# Create advanced analytics class
class AdvancedAnalytics
  def initialize(usage_tracker)
    @usage_tracker = usage_tracker
  end
  
  def cost_optimization_insights
    analytics = @usage_tracker.analytics(:all)
    
    insights = {
      total_cost: analytics[:costs][:total],
      cost_by_provider: analytics[:costs][:by_provider],
      cost_by_model: analytics[:costs][:by_model],
      recommendations: []
    }
    
    # Analyze cost distribution
    if analytics[:costs][:by_model].any?
      most_expensive_model = analytics[:costs][:by_model].max_by { |_, cost| cost }
      insights[:most_expensive_model] = {
        model: most_expensive_model[0],
        cost: most_expensive_model[1],
        percentage: (most_expensive_model[1] / analytics[:costs][:total] * 100).round(2)
      }
      
      # Generate recommendations
      if insights[:most_expensive_model][:percentage] > 50
        insights[:recommendations] << {
          type: "cost_optimization",
          priority: "high",
          description: "Consider using cheaper models for non-critical tasks",
          potential_savings: (insights[:most_expensive_model][:cost] * 0.3).round(4)
        }
      end
    end
    
    insights
  end
  
  def performance_insights
    analytics = @usage_tracker.analytics(:all)
    dashboard = @usage_tracker.dashboard_data
    
    insights = {
      api_performance: {
        total_calls: analytics[:api_calls][:count],
        average_duration: analytics[:api_calls][:average_duration],
        current_rate: dashboard[:current_api_rate]
      },
      agent_performance: {
        total_interactions: analytics[:agent_interactions][:count],
        average_satisfaction: analytics[:agent_interactions][:average_satisfaction],
        average_duration: analytics[:agent_interactions][:average_duration]
      },
      tool_performance: {
        total_usage: analytics[:tool_usage][:count],
        success_rate: analytics[:tool_usage][:success_rate],
        average_execution_time: analytics[:tool_usage][:average_execution_time]
      },
      recommendations: []
    }
    
    # Generate performance recommendations
    if insights[:tool_performance][:success_rate] < 90
      insights[:recommendations] << {
        type: "reliability",
        priority: "medium",
        description: "Improve tool reliability - success rate below 90%",
        current_rate: insights[:tool_performance][:success_rate]
      }
    end
    
    if insights[:agent_performance][:average_satisfaction] && 
       insights[:agent_performance][:average_satisfaction] < 4.0
      insights[:recommendations] << {
        type: "user_experience",
        priority: "high", 
        description: "Improve agent interactions - satisfaction below 4.0/5.0",
        current_score: insights[:agent_performance][:average_satisfaction]
      }
    end
    
    insights
  end
  
  def usage_patterns
    analytics = @usage_tracker.analytics(:all)
    
    patterns = {
      peak_usage_times: analytics[:performance][:peak_hour],
      usage_distribution: {
        by_provider: analytics[:api_calls][:by_provider],
        by_model: analytics[:api_calls][:by_model]
      },
      interaction_patterns: {
        by_agent: analytics[:agent_interactions][:by_agent],
        by_outcome: analytics[:agent_interactions][:by_outcome]
      },
      tool_patterns: {
        by_tool: analytics[:tool_usage][:by_tool],
        by_agent: analytics[:tool_usage][:by_agent]
      }
    }
    
    patterns
  end
end

# Generate advanced insights
advanced_analytics = AdvancedAnalytics.new(usage_tracker)

puts "Cost Optimization Insights:"
cost_insights = advanced_analytics.cost_optimization_insights
puts "  Total cost: $#{cost_insights[:total_cost].round(4)}"
if cost_insights[:most_expensive_model]
  puts "  Most expensive model: #{cost_insights[:most_expensive_model][:model]} " \
       "(#{cost_insights[:most_expensive_model][:percentage]}% of total cost)"
end
puts "  Recommendations: #{cost_insights[:recommendations].size}"
cost_insights[:recommendations].each do |rec|
  puts "    • #{rec[:description]} (#{rec[:priority]} priority)"
  puts "      Potential savings: $#{rec[:potential_savings]}" if rec[:potential_savings]
end
puts

puts "Performance Insights:"
perf_insights = advanced_analytics.performance_insights
puts "  API Performance:"
puts "    Total calls: #{perf_insights[:api_performance][:total_calls]}"
puts "    Average duration: #{perf_insights[:api_performance][:average_duration]&.round(2) || 'N/A'}s"
puts "    Current rate: #{perf_insights[:api_performance][:current_rate]} calls/min"
puts "  Agent Performance:"
puts "    Total interactions: #{perf_insights[:agent_performance][:total_interactions]}"
puts "    Average satisfaction: #{perf_insights[:agent_performance][:average_satisfaction]&.round(2) || 'N/A'}/5.0"
puts "    Average duration: #{perf_insights[:agent_performance][:average_duration]&.round(1) || 'N/A'}s"
puts "  Tool Performance:"
puts "    Success rate: #{perf_insights[:tool_performance][:success_rate]}%"
puts "    Average execution time: #{perf_insights[:tool_performance][:average_execution_time]&.round(2) || 'N/A'}s"
puts "  Recommendations: #{perf_insights[:recommendations].size}"
perf_insights[:recommendations].each do |rec|
  puts "    • #{rec[:description]} (#{rec[:priority]} priority)"
end
puts

puts "Usage Patterns:"
patterns = advanced_analytics.usage_patterns
puts "  Peak usage time: #{patterns[:peak_usage_times][:hour]}:00 " \
     "(#{patterns[:peak_usage_times][:count]} events)" if patterns[:peak_usage_times]
puts "  Provider distribution: #{patterns[:usage_distribution][:by_provider]}"
puts "  Model distribution: #{patterns[:usage_distribution][:by_model]}"
puts

# ============================================================================
# EXAMPLE 11: INTEGRATION WITH EXTERNAL SYSTEMS
# ============================================================================
# Show how to integrate usage tracking with external monitoring and analytics systems.

puts "Example 11: Integration with External Systems"
puts "-" * 50

# Custom storage adapter for database integration
class CustomDatabaseStorage
  def initialize(database_connection)
    @db = database_connection
  end
  
  def store_event(event)
    # In real implementation, store to database
    puts "Storing event to database: #{event[:type]} - #{event[:id]}"
  end
  
  def get_events(since: nil)
    # In real implementation, query database
    puts "Querying events from database since: #{since || 'all time'}"
    []
  end
  
  def delete_events_before(cutoff_date)
    # In real implementation, delete old events
    puts "Deleting events before: #{cutoff_date}"
    0
  end
end

# Custom alert handler for external notifications
class CustomAlertHandler
  def initialize(webhook_url)
    @webhook_url = webhook_url
  end
  
  def handle_alert(alert_name, data)
    # In real implementation, send to webhook
    puts "Sending alert to webhook: #{alert_name}"
    puts "  Alert data: #{data}"
    puts "  Webhook URL: #{@webhook_url}"
  end
end

puts "Example integrations:"
puts "  Database Storage: Store events in PostgreSQL, MySQL, or MongoDB"
puts "  Webhook Notifications: Send alerts to Slack, Discord, or custom endpoints"
puts "  Analytics Platforms: Export data to Datadog, New Relic, or custom dashboards"
puts "  Business Intelligence: Connect to Tableau, Power BI, or custom reporting tools"
puts "  Cost Management: Integrate with AWS Cost Explorer, Azure Cost Management"
puts

# ============================================================================
# BEST PRACTICES SUMMARY
# ============================================================================

puts "=== Usage Tracking Best Practices ==="
puts "=" * 50
puts <<~PRACTICES
  1. Data Collection Strategy:
     - Track all relevant metrics (API calls, costs, performance)
     - Include sufficient metadata for analysis
     - Balance detail with storage efficiency
     - Implement proper data retention policies
  
  2. Real-Time Monitoring:
     - Set up appropriate alert thresholds
     - Monitor critical metrics continuously
     - Implement automated responses where possible
     - Provide real-time dashboards for operators
  
  3. Cost Management:
     - Track costs at granular level (per user, per feature)
     - Set up budget alerts and limits
     - Analyze cost optimization opportunities
     - Implement cost allocation for multi-tenant systems
  
  4. Performance Optimization:
     - Monitor response times and error rates
     - Track tool usage and success rates
     - Identify bottlenecks and optimization opportunities
     - Implement performance baselines and SLAs
  
  5. Business Intelligence:
     - Track custom business metrics
     - Analyze user behavior and satisfaction
     - Generate actionable insights
     - Support data-driven decision making
  
  6. Data Security and Privacy:
     - Implement proper access controls
     - Anonymize sensitive data
     - Comply with data protection regulations
     - Secure data in transit and at rest
  
  7. Scalability Considerations:
     - Use appropriate storage solutions
     - Implement data archiving strategies
     - Consider sampling for high-volume systems
     - Optimize query performance for analytics
  
  8. Integration and Automation:
     - Integrate with existing monitoring systems
     - Automate report generation and distribution
     - Implement CI/CD for tracking configuration
     - Use APIs for external system integration
PRACTICES

puts "\nUsage tracking example completed!"
puts "This demonstrates comprehensive usage monitoring for AI applications."
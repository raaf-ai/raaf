#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates advanced tracing capabilities in OpenAI Agents Ruby.
# Beyond basic tracing, the library provides enterprise-grade features including
# cost management, real-time alerting, anomaly detection, and performance monitoring.
# These features are essential for production deployments where you need comprehensive
# observability, cost control, and proactive issue detection.

require_relative "../lib/openai_agents"

puts "=== Advanced Tracing Example ==="
puts

# ============================================================================
# EXAMPLE 1: COST MANAGEMENT SYSTEM
# ============================================================================
# The CostManager provides comprehensive cost tracking with multi-tenant support,
# budgeting, forecasting, and optimization recommendations. Essential for managing
# AI costs in production environments with multiple tenants or projects.

puts "Example 1: Cost Management System"
puts "-" * 50

# Create a cost manager with custom configuration
cost_manager = OpenAIAgents::Tracing::CostManager.new(
  # Custom pricing for different models
  pricing: {
    "gpt-4o" => { input: 0.000005, output: 0.000015 },
    "gpt-4o-mini" => { input: 0.00000015, output: 0.0000006 },
    "gpt-4" => { input: 0.00003, output: 0.00006 },
    "gpt-3.5-turbo" => { input: 0.0000015, output: 0.000002 }
  },
  
  # Multi-tenant configuration
  tenant_field: "tenant_id",
  project_field: "project_id", 
  user_field: "user_id",
  
  # Budget management
  enable_budgets: true,
  budget_alert_thresholds: [50, 75, 90, 95],
  budget_enforcement: false,
  
  # Cost optimization
  enable_optimization: true,
  optimization_recommendations: true
)

puts "Cost Manager initialized with multi-tenant support"
puts "Supported models: #{cost_manager.instance_variable_get(:@config)[:pricing].keys.join(', ')}"
puts

# Set budgets for different entities
puts "Setting budgets..."

# Department budget
cost_manager.set_budget(
  amount: 1000.0,
  tenant_id: "dept_engineering",
  period: :monthly,
  currency: "USD"
)

# Project budget
cost_manager.set_budget(
  amount: 250.0,
  tenant_id: "dept_engineering",
  project_id: "project_chatbot",
  period: :monthly,
  currency: "USD"
)

# User budget  
cost_manager.set_budget(
  amount: 50.0,
  tenant_id: "dept_engineering",
  project_id: "project_chatbot",
  user_id: "user_123",
  period: :monthly,
  currency: "USD"
)

puts "Budgets set for department, project, and user levels"
puts

# Simulate cost calculation for a mock span
puts "Calculating costs for sample usage..."
mock_span = OpenStruct.new(
  kind: "llm",
  span_id: "span_123",
  span_attributes: {
    "llm" => {
      "request" => { "model" => "gpt-4o" },
      "usage" => {
        "input_tokens" => 1000,
        "output_tokens" => 500
      }
    }
  }
)

cost_result = cost_manager.calculate_span_cost(mock_span)
puts "Cost calculation result:"
puts "  Model: #{cost_result[:model]}"
puts "  Input tokens: #{cost_result[:input_tokens]}"
puts "  Output tokens: #{cost_result[:output_tokens]}"
puts "  Input cost: $#{cost_result[:input_cost].round(6)}"
puts "  Output cost: $#{cost_result[:output_cost].round(6)}"
puts "  Total cost: $#{cost_result[:total_cost].round(6)}"
puts

# Get cost optimization recommendations
puts "Getting cost optimization recommendations..."
recommendations = cost_manager.get_cost_optimization_recommendations(
  timeframe: 7.days,
  tenant_id: "dept_engineering"
)

puts "Optimization recommendations:"
recommendations.each do |rec|
  puts "  • #{rec[:title]} (#{rec[:type]})"
  puts "    #{rec[:description]}"
  puts "    Potential savings: $#{rec[:potential_savings]}, Impact: #{rec[:impact]}, Effort: #{rec[:effort]}"
end
puts

# ============================================================================
# EXAMPLE 2: REAL-TIME ALERTING SYSTEM
# ============================================================================
# The AlertEngine provides real-time monitoring with configurable rules and
# multiple notification channels. Essential for proactive issue detection
# and rapid response to performance or reliability problems.

puts "Example 2: Real-Time Alerting System"
puts "-" * 50

# Create alert engine with custom rules
alert_engine = OpenAIAgents::Tracing::AlertEngine.new(
  rules: [
    # Custom rule for high API costs
    {
      name: "high_api_cost_per_hour",
      description: "Triggers when API costs exceed $50/hour",
      condition: "cost_per_hour > threshold",
      threshold: 50.0,
      severity: "critical",
      window_minutes: 60,
      enabled: true
    },
    
    # Custom rule for specific workflow failures
    {
      name: "chatbot_workflow_failures",
      description: "Triggers when chatbot workflow error rate exceeds 15%",
      condition: "workflow_error_rate > threshold",
      threshold: 15.0,
      severity: "warning",
      window_minutes: 30,
      enabled: true
    }
  ]
)

puts "Alert Engine initialized with #{alert_engine.list_rules.size} rules"

# Add custom alert handlers
puts "Adding custom alert handlers..."

# Webhook handler for external systems
webhook_handler = OpenAIAgents::Tracing::AlertEngine::WebhookHandler.new(
  "https://api.example.com/alerts",
  "webhook_secret_key"
)
alert_engine.add_alert_handler(webhook_handler)

# Slack handler for team notifications
slack_handler = OpenAIAgents::Tracing::AlertEngine::SlackHandler.new(
  "https://hooks.slack.com/services/your/slack/webhook",
  "#engineering-alerts"
)
alert_engine.add_alert_handler(slack_handler)

puts "Added webhook and Slack alert handlers"
puts

# Display current alert rules
puts "Current alert rules:"
alert_engine.list_rules.each do |rule|
  status = rule[:enabled] ? "✓" : "✗"
  puts "  #{status} #{rule[:name]} (#{rule[:severity]})"
  puts "    #{rule[:description]}"
  puts "    Threshold: #{rule[:threshold]}, Window: #{rule[:window_minutes]}min"
end
puts

# Simulate checking all rules
puts "Checking all alert rules..."
alert_results = alert_engine.check_all_rules

triggered_alerts = alert_results.select { |result| result[:triggered] }
puts "Alert check completed: #{triggered_alerts.size} alerts triggered"

if triggered_alerts.any?
  triggered_alerts.each do |alert|
    puts "  🚨 #{alert[:rule_name]} (#{alert[:severity]})"
    puts "     #{alert[:message]}"
  end
else
  puts "  ✅ No alerts triggered - all systems operating normally"
end
puts

# ============================================================================
# EXAMPLE 3: ANOMALY DETECTION SYSTEM
# ============================================================================
# The AnomalyDetector uses statistical methods to automatically identify
# unusual patterns in performance, errors, costs, and usage. Provides
# early warning of potential issues before they impact users.

puts "Example 3: Anomaly Detection System"
puts "-" * 50

# Create anomaly detector with custom sensitivity
anomaly_detector = OpenAIAgents::Tracing::AnomalyDetector.new(
  # Statistical thresholds
  z_score_threshold: 2.5,        # More sensitive than default (3.0)
  min_samples: 15,               # Minimum data points for analysis
  
  # Baseline comparison
  baseline_days: 7,              # Compare against last 7 days
  
  # Change detection
  change_point_sensitivity: 0.6,  # Detect 60% changes
  
  # Seasonal patterns
  seasonal_adjustment: true,      # Account for day/hour patterns
  
  # Performance optimization
  cache_results: true,
  cache_ttl: 300                 # 5 minutes
)

puts "Anomaly Detector initialized with custom sensitivity settings"
puts

# Detect performance anomalies
puts "Detecting performance anomalies..."
performance_anomalies = anomaly_detector.detect_performance_anomalies(24.hours)

puts "Performance anomaly analysis:"
puts "  Timeframe: #{performance_anomalies[:timeframe] / 3600} hours"
puts "  Total anomalies: #{performance_anomalies[:anomalies].size}"
puts "  Summary: #{performance_anomalies[:summary]}"

if performance_anomalies[:anomalies].any?
  puts "\n  Detected anomalies:"
  performance_anomalies[:anomalies].each do |anomaly|
    puts "    • #{anomaly[:type]} (#{anomaly[:severity]})"
    puts "      #{anomaly[:description]}"
    puts "      Metric: #{anomaly[:metric]}, Value: #{anomaly[:value]}"
  end
else
  puts "  ✅ No performance anomalies detected"
end
puts

# Detect cost anomalies
puts "Detecting cost anomalies..."
cost_anomalies = anomaly_detector.detect_cost_anomalies(24.hours)

puts "Cost anomaly analysis:"
puts "  Total anomalies: #{cost_anomalies[:anomalies].size}"
puts "  Summary: #{cost_anomalies[:summary]}"

if cost_anomalies[:anomalies].any?
  puts "\n  Detected anomalies:"
  cost_anomalies[:anomalies].each do |anomaly|
    puts "    • #{anomaly[:type]} (#{anomaly[:severity]})"
    puts "      #{anomaly[:description]}"
    puts "      Value: #{anomaly[:value]}, Baseline: #{anomaly[:baseline]}"
  end
else
  puts "  ✅ No cost anomalies detected"
end
puts

# Custom pattern analysis
puts "Analyzing custom data patterns..."
sample_data = [10, 12, 11, 13, 15, 45, 14, 12, 11, 13, 10, 12, 11, 15, 16, 14, 13, 12, 11, 10]
baseline_data = [10, 11, 12, 13, 14, 15, 12, 11, 10, 13, 14, 15, 12, 11, 10, 13, 14, 15]

pattern_anomalies = anomaly_detector.detect_pattern_changes(
  "custom_metric",
  sample_data,
  baseline_data
)

puts "Custom pattern analysis:"
puts "  Data points: #{sample_data.size}"
puts "  Baseline points: #{baseline_data.size}"
puts "  Detected patterns: #{pattern_anomalies.size}"

pattern_anomalies.each do |anomaly|
  puts "    • #{anomaly[:type]}: #{anomaly[:description] || 'Pattern detected'}"
  puts "      Value: #{anomaly[:value]}, Z-score: #{anomaly[:z_score]}" if anomaly[:z_score]
end
puts

# ============================================================================
# EXAMPLE 4: INTEGRATED MONITORING DASHBOARD
# ============================================================================
# Combining all advanced tracing components for a comprehensive monitoring
# solution. This integration provides complete observability for production
# AI applications.

puts "Example 4: Integrated Monitoring Dashboard"
puts "-" * 50

# Create integrated monitoring system
class AdvancedMonitoringDashboard
  def initialize
    @cost_manager = OpenAIAgents::Tracing::CostManager.new
    @alert_engine = OpenAIAgents::Tracing::AlertEngine.new
    @anomaly_detector = OpenAIAgents::Tracing::AnomalyDetector.new
  end
  
  def generate_health_report
    puts "Generating comprehensive health report..."
    
    report = {
      timestamp: Time.now,
      system_status: "operational",
      components: {},
      recommendations: [],
      action_items: []
    }
    
    # Cost analysis
    cost_breakdown = @cost_manager.get_cost_breakdown(timeframe: 24.hours)
    report[:components][:cost_management] = {
      status: "healthy",
      total_cost: cost_breakdown[:totals][:total_cost],
      traces_analyzed: cost_breakdown[:totals][:total_traces],
      avg_cost_per_trace: cost_breakdown[:totals][:avg_cost_per_trace]
    }
    
    # Alert status
    alert_status = @alert_engine.check_all_rules
    active_alerts = alert_status.select { |a| a[:triggered] }
    report[:components][:alerting] = {
      status: active_alerts.any? ? "alerts_active" : "healthy",
      active_alerts: active_alerts.size,
      total_rules: @alert_engine.list_rules.size
    }
    
    # Anomaly detection
    anomalies = @anomaly_detector.detect_performance_anomalies(24.hours)
    report[:components][:anomaly_detection] = {
      status: anomalies[:anomalies].any? ? "anomalies_detected" : "healthy",
      anomalies_found: anomalies[:anomalies].size,
      analysis_timeframe: "24 hours"
    }
    
    # Generate recommendations
    if active_alerts.any?
      report[:action_items] << "Review and respond to #{active_alerts.size} active alerts"
    end
    
    if anomalies[:anomalies].any?
      report[:action_items] << "Investigate #{anomalies[:anomalies].size} detected anomalies"
    end
    
    high_cost_traces = cost_breakdown[:totals][:avg_cost_per_trace] > 0.01
    if high_cost_traces
      report[:recommendations] << "Consider cost optimization - average cost per trace is high"
    end
    
    report
  end
  
  def display_report(report)
    puts "📊 System Health Report"
    puts "Generated at: #{report[:timestamp]}"
    puts "Overall Status: #{report[:system_status].upcase}"
    puts
    
    puts "Component Status:"
    report[:components].each do |component, data|
      status_icon = case data[:status]
                    when "healthy" then "✅"
                    when "alerts_active" then "⚠️"
                    when "anomalies_detected" then "🔍"
                    else "❓"
                    end
      
      puts "  #{status_icon} #{component.to_s.humanize}: #{data[:status]}"
      data.each do |key, value|
        next if key == :status
        puts "     #{key.to_s.humanize}: #{value}"
      end
    end
    puts
    
    if report[:action_items].any?
      puts "🚨 Action Items:"
      report[:action_items].each { |item| puts "  • #{item}" }
      puts
    end
    
    if report[:recommendations].any?
      puts "💡 Recommendations:"
      report[:recommendations].each { |rec| puts "  • #{rec}" }
      puts
    end
  end
  
  def start_monitoring_loop
    puts "Starting continuous monitoring loop..."
    puts "(In production, this would run as a background process)"
    
    3.times do |i|
      puts "\n--- Monitoring Cycle #{i + 1} ---"
      report = generate_health_report
      display_report(report)
      
      puts "Sleeping for 30 seconds..."
      sleep(1) # Shortened for demo
    end
    
    puts "Monitoring loop completed"
  end
end

# Create and run monitoring dashboard
dashboard = AdvancedMonitoringDashboard.new
dashboard.start_monitoring_loop
puts

# ============================================================================
# EXAMPLE 5: DISTRIBUTED TRACING CORRELATION
# ============================================================================
# Advanced tracing across distributed systems with correlation IDs and
# cross-service trace aggregation. Essential for microservices architectures.

puts "Example 5: Distributed Tracing Correlation"
puts "-" * 50

# Create distributed tracer
distributed_tracer = OpenAIAgents::Tracing::DistributedTracer.new(
  service_name: "ai-agent-service",
  service_version: "1.0.0",
  correlation_header: "X-Correlation-ID",
  trace_propagation: true
)

puts "Distributed Tracer initialized"
puts "Service: #{distributed_tracer.instance_variable_get(:@config)[:service_name]}"
puts "Version: #{distributed_tracer.instance_variable_get(:@config)[:service_version]}"
puts

# Simulate distributed trace with correlation
correlation_id = SecureRandom.uuid
puts "Starting distributed trace with correlation ID: #{correlation_id}"

# Simulate multiple service calls
services = [
  { name: "auth-service", duration: 0.05 },
  { name: "user-service", duration: 0.12 },
  { name: "ai-agent-service", duration: 1.23 },
  { name: "response-service", duration: 0.08 }
]

services.each do |service|
  puts "  📡 Calling #{service[:name]} (#{service[:duration]}s)"
  
  # In real implementation, this would create actual spans
  # and propagate correlation IDs across service boundaries
  span_data = {
    service_name: service[:name],
    correlation_id: correlation_id,
    duration_ms: service[:duration] * 1000,
    timestamp: Time.now
  }
  
  puts "     Span created: #{span_data[:service_name]} (#{span_data[:duration_ms]}ms)"
end

puts "Distributed trace completed"
puts "Total services involved: #{services.size}"
puts

# ============================================================================
# EXAMPLE 6: PERFORMANCE PROFILING AND OPTIMIZATION
# ============================================================================
# Advanced performance analysis with detailed profiling and optimization
# recommendations based on trace data analysis.

puts "Example 6: Performance Profiling and Optimization"
puts "-" * 50

# Create performance profiler
class PerformanceProfiler
  def initialize
    @profiles = {}
    @optimization_engine = OptimizationEngine.new
  end
  
  def profile_workflow(workflow_name, duration_samples)
    puts "Profiling workflow: #{workflow_name}"
    puts "Sample count: #{duration_samples.size}"
    
    profile = {
      workflow_name: workflow_name,
      sample_count: duration_samples.size,
      statistics: calculate_statistics(duration_samples),
      percentiles: calculate_percentiles(duration_samples),
      optimization_opportunities: identify_optimization_opportunities(duration_samples)
    }
    
    @profiles[workflow_name] = profile
    profile
  end
  
  private
  
  def calculate_statistics(samples)
    return {} if samples.empty?
    
    {
      min: samples.min,
      max: samples.max,
      mean: samples.sum.to_f / samples.size,
      median: samples.sort[samples.size / 2],
      std_dev: Math.sqrt(samples.map { |x| (x - samples.sum.to_f / samples.size) ** 2 }.sum / samples.size)
    }
  end
  
  def calculate_percentiles(samples)
    return {} if samples.empty?
    
    sorted = samples.sort
    {
      p50: percentile(sorted, 50),
      p75: percentile(sorted, 75),
      p90: percentile(sorted, 90),
      p95: percentile(sorted, 95),
      p99: percentile(sorted, 99)
    }
  end
  
  def percentile(sorted_array, percentile)
    index = (percentile / 100.0 * (sorted_array.length - 1)).round
    sorted_array[index]
  end
  
  def identify_optimization_opportunities(samples)
    opportunities = []
    
    stats = calculate_statistics(samples)
    
    # High variability
    if stats[:std_dev] > stats[:mean] * 0.5
      opportunities << {
        type: "high_variability",
        description: "High performance variability detected",
        impact: "medium",
        recommendation: "Investigate inconsistent performance patterns"
      }
    end
    
    # Long tail latency
    percentiles = calculate_percentiles(samples)
    if percentiles[:p95] > percentiles[:p50] * 3
      opportunities << {
        type: "long_tail_latency",
        description: "Long tail latency detected",
        impact: "high",
        recommendation: "Optimize slow requests - P95 is 3x median"
      }
    end
    
    # Generally slow performance
    if stats[:mean] > 5000 # 5 seconds
      opportunities << {
        type: "slow_performance",
        description: "Generally slow performance",
        impact: "high",
        recommendation: "Overall performance optimization needed"
      }
    end
    
    opportunities
  end
  
  class OptimizationEngine
    def generate_recommendations(profiles)
      recommendations = []
      
      profiles.each do |workflow_name, profile|
        profile[:optimization_opportunities].each do |opportunity|
          recommendations << {
            workflow: workflow_name,
            type: opportunity[:type],
            description: opportunity[:description],
            impact: opportunity[:impact],
            recommendation: opportunity[:recommendation],
            priority: calculate_priority(opportunity[:impact], profile[:sample_count])
          }
        end
      end
      
      recommendations.sort_by { |r| priority_score(r[:priority]) }.reverse
    end
    
    private
    
    def calculate_priority(impact, sample_count)
      base_priority = case impact
                      when "high" then 3
                      when "medium" then 2
                      when "low" then 1
                      else 1
                      end
      
      # Boost priority for high-volume workflows
      volume_multiplier = sample_count > 1000 ? 1.5 : 1.0
      
      case (base_priority * volume_multiplier).round
      when 4..5 then "critical"
      when 3 then "high"
      when 2 then "medium"
      else "low"
      end
    end
    
    def priority_score(priority)
      case priority
      when "critical" then 4
      when "high" then 3
      when "medium" then 2
      when "low" then 1
      else 0
      end
    end
  end
end

# Create performance profiler and analyze sample data
profiler = PerformanceProfiler.new

# Simulate performance data for different workflows
workflows = {
  "chat_completion" => [1200, 1500, 1800, 1100, 1400, 1600, 1300, 1700, 1200, 1500, 2200, 1100, 1400, 1800, 1200],
  "image_generation" => [5000, 5500, 6000, 4800, 5200, 7500, 5100, 5400, 5000, 5300, 8000, 4900, 5100, 5600, 5200],
  "document_analysis" => [800, 900, 1100, 750, 850, 950, 800, 1000, 900, 850, 1200, 800, 900, 1000, 850]
}

puts "Profiling #{workflows.size} workflows..."

profiles = {}
workflows.each do |workflow_name, duration_samples|
  profile = profiler.profile_workflow(workflow_name, duration_samples)
  profiles[workflow_name] = profile
  
  puts "\n  #{workflow_name} Profile:"
  puts "    Mean: #{profile[:statistics][:mean]&.round(2)}ms"
  puts "    P95: #{profile[:percentiles][:p95]}ms"
  puts "    Std Dev: #{profile[:statistics][:std_dev]&.round(2)}ms"
  puts "    Optimization opportunities: #{profile[:optimization_opportunities].size}"
end

puts "\n" + "="*50
puts "\n📈 Performance Analysis Summary"
puts "=" * 50

total_samples = profiles.values.sum { |p| p[:sample_count] }
puts "Total samples analyzed: #{total_samples}"
puts "Workflows profiled: #{profiles.size}"

# Generate optimization recommendations
optimization_engine = PerformanceProfiler::OptimizationEngine.new
recommendations = optimization_engine.generate_recommendations(profiles)

puts "\n🔧 Optimization Recommendations (#{recommendations.size} total):"
recommendations.each_with_index do |rec, index|
  priority_icon = case rec[:priority]
                  when "critical" then "🚨"
                  when "high" then "⚠️"
                  when "medium" then "💡"
                  when "low" then "ℹ️"
                  else "📝"
                  end
  
  puts "  #{index + 1}. #{priority_icon} #{rec[:workflow]} - #{rec[:type]} (#{rec[:priority]})"
  puts "     #{rec[:description]}"
  puts "     Recommendation: #{rec[:recommendation]}"
  puts
end

# ============================================================================
# BEST PRACTICES SUMMARY
# ============================================================================

puts "=== Advanced Tracing Best Practices ==="
puts "=" * 50
puts <<~PRACTICES
  1. Cost Management:
     - Set budgets at multiple levels (tenant, project, user)
     - Monitor cost per request and optimize expensive operations
     - Use cost forecasting to predict future spending
     - Implement cost allocation for accurate billing
  
  2. Alerting Strategy:
     - Configure alerts for critical metrics (error rate, latency, cost)
     - Use multiple notification channels (Slack, email, webhooks)
     - Set appropriate thresholds to avoid alert fatigue
     - Implement alert suppression for maintenance windows
  
  3. Anomaly Detection:
     - Use statistical methods to detect unusual patterns
     - Account for seasonal variations in usage
     - Combine multiple detection algorithms for accuracy
     - Focus on actionable anomalies that require investigation
  
  4. Performance Monitoring:
     - Profile workflows to identify optimization opportunities
     - Monitor percentiles (P95, P99) not just averages
     - Track long tail latency and performance variability
     - Set up automated performance regression detection
  
  5. Distributed Tracing:
     - Use correlation IDs to trace requests across services
     - Implement trace propagation for complete visibility
     - Aggregate traces from multiple services for analysis
     - Monitor cross-service dependencies and bottlenecks
  
  6. Operational Excellence:
     - Implement health checks and status dashboards
     - Set up automated monitoring loops
     - Create runbooks for common issues
     - Regularly review and tune monitoring configurations
  
  7. Data Retention:
     - Define appropriate retention policies for traces
     - Archive historical data for long-term analysis
     - Implement data compression and optimization
     - Balance storage costs with analytical needs
  
  8. Security and Compliance:
     - Ensure sensitive data is not logged in traces
     - Implement proper access controls for trace data
     - Comply with data protection regulations
     - Use encryption for trace data in transit and at rest
PRACTICES

puts "\nAdvanced tracing example completed!"
puts "This demonstrates enterprise-grade observability for AI applications."
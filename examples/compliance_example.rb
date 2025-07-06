#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"
require_relative "../lib/openai_agents/compliance"

# Set API key from environment
OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY", nil)
end

puts "=== Compliance and Audit Logging Example ==="
puts

# Example 1: Basic Audit Logging
puts "Example 1: Basic Audit Logging"
puts "-" * 50

# Create audit logger
audit_logger = OpenAIAgents::Compliance::AuditLogger.new(
  log_file: "audit_example.log",
  storage_path: "./audit_logs_example",
  store_conversations: true,
  compliance_standards: ["GDPR", "SOC2", "HIPAA"]
)

# Create test agent
agent = OpenAIAgents::Agent.new(
  name: "CustomerServiceAgent",
  model: "gpt-4o-mini",
  instructions: "You are a helpful customer service agent."
)

# Simulate agent execution with audit logging
messages = [
  { role: "user", content: "I need help with my account" },
  { role: "assistant", content: "I'd be happy to help you with your account. What specific assistance do you need?" }
]

result = OpenAIAgents::Result.new(
  messages: messages,
  agent: agent,
  usage: { total_tokens: 45, prompt_tokens: 20, completion_tokens: 25 }
)

# Log the agent execution
audit_logger.log_agent_execution(
  agent,
  messages,
  result,
  duration_ms: 1234
)

puts "Agent execution logged to audit trail"
puts

# Example 2: Tool Usage Logging
puts "Example 2: Tool Usage Logging"
puts "-" * 50

# Log tool usage
audit_logger.log_tool_usage(
  "database_query",
  { query: "SELECT * FROM users WHERE id = ?", params: ["user123"] },
  "Query executed successfully",
  rows_returned: 1
)

audit_logger.log_tool_usage(
  "send_email",
  { to: "user@example.com", subject: "Account Update" },
  "Email sent successfully",
  provider: "sendgrid"
)

puts "Tool usage events logged"
puts

# Example 3: Data Access Logging
puts "Example 3: Data Access Logging"
puts "-" * 50

# Log various data access events
audit_logger.log_data_access("user_profile", "user123", "read", { purpose: "customer_support" })
audit_logger.log_data_access("order_history", "order456", "read", { purpose: "order_inquiry" })
audit_logger.log_data_access("payment_method", "card789", "update", { purpose: "payment_update" })

puts "Data access events logged"
puts

# Example 4: Security Event Logging
puts "Example 4: Security Event Logging"
puts "-" * 50

# Log security events
audit_logger.log_security_event(
  "unauthorized_access",
  { resource: "admin_panel", user_id: "user123", ip: "192.168.1.100" },
  :high
)

audit_logger.log_security_event(
  "suspicious_pattern",
  { pattern: "multiple_failed_logins", attempts: 5, timeframe: "5_minutes" },
  :medium
)

audit_logger.log_security_event(
  "api_key_rotation",
  { key_id: "key_abc", reason: "scheduled_rotation" },
  :low
)

puts "Security events logged (high severity events trigger alerts)"
puts

# Example 5: PII Detection and Handling
puts "Example 5: PII Detection and Handling"
puts "-" * 50

# Log PII detection events
audit_logger.log_pii_detection(
  "chat_message",
  ["email", "phone_number"],
  "redacted",
  message_id: "msg123"
)

audit_logger.log_pii_detection(
  "tool_response",
  ["ssn", "credit_card"],
  "blocked",
  tool: "payment_processor"
)

puts "PII detection events logged"
puts

# Example 6: Consent Management
puts "Example 6: Consent Management"
puts "-" * 50

# Log consent events
audit_logger.log_consent_event(
  "user123",
  "marketing_emails",
  "granted",
  source: "preferences_page"
)

audit_logger.log_consent_event(
  "user456",
  "data_analytics",
  "revoked",
  source: "privacy_settings"
)

audit_logger.log_consent_event(
  "user789",
  "third_party_sharing",
  "modified",
  source: "gdpr_request"
)

puts "Consent events logged for GDPR compliance"
puts

# Example 7: Generate Audit Report
puts "Example 7: Generate Audit Report"
puts "-" * 50

# Generate comprehensive audit report
puts "Generating audit report..."
report = audit_logger.generate_audit_report(
  start_time: Time.now - 3600,  # Last hour
  end_time: Time.now
)

puts "\nAudit Report Summary:"
puts "  Report ID: #{report[:report_id]}"
puts "  Period: #{report[:period][:start]} to #{report[:period][:end]}"
puts "\n  Event Summary:"
report[:summary][:events_by_type].each do |type, count|
  puts "    #{type}: #{count}"
end

puts "\n  Compliance Metrics:"
report[:compliance_metrics].each do |standard, metrics|
  puts "    #{standard.upcase}:"
  metrics.each do |metric, value|
    puts "      #{metric}: #{value}"
  end
end

if report[:recommendations].any?
  puts "\n  Recommendations:"
  report[:recommendations].each do |rec|
    puts "    - #{rec}"
  end
end
puts

# Example 8: Export Audit Logs
puts "Example 8: Export Audit Logs"
puts "-" * 50

# Export in different formats
puts "Exporting audit logs..."

# JSON export
json_export = audit_logger.export_logs(
  format: :json,
  output_file: "audit_export.json"
)
puts "  ✓ JSON export completed"

# CSV export
csv_export = audit_logger.export_logs(
  format: :csv,
  output_file: "audit_export.csv"
)
puts "  ✓ CSV export completed"

# SIEM export (Common Event Format)
siem_export = audit_logger.export_logs(
  format: :siem,
  output_file: "audit_export.cef"
)
puts "  ✓ SIEM/CEF export completed"
puts

# Example 9: Log Integrity Verification
puts "Example 9: Log Integrity Verification"
puts "-" * 50

# Verify log integrity
puts "Verifying audit log integrity..."
verification = audit_logger.verify_integrity(
  start_time: Time.now - 3600,
  end_time: Time.now
)

puts "Integrity Verification Results:"
puts "  Total events checked: #{verification[:total_events]}"
puts "  Valid events: #{verification[:valid_events]}"
puts "  Invalid events: #{verification[:invalid_events]}"

if verification[:integrity_violations].any?
  puts "  ⚠️  Integrity violations detected:"
  verification[:integrity_violations].each do |violation|
    puts "    - Event #{violation[:event_id]}: #{violation[:reason]}"
  end
else
  puts "  ✅ All events passed integrity check"
end
puts

# Example 10: Policy Compliance Checking
puts "Example 10: Policy Compliance Checking"
puts "-" * 50

# Create policy manager
policy_manager = OpenAIAgents::Compliance::PolicyManager.new

# Check various compliance scenarios
scenarios = [
  {
    name: "Data Retention Check",
    context: { data_age_days: 100, data_type: "user_logs" }
  },
  {
    name: "Access Control Check",
    context: { authenticated: true, authorized: false, resource_accessed: "admin_panel" }
  },
  {
    name: "PII Handling Check",
    context: { contains_pii: true, encrypted: false, data_type: "customer_email" }
  },
  {
    name: "Audit Requirements Check",
    context: { timestamp: Time.now, user_id: "user123", action: "data_export" }
  }
]

puts "Running compliance policy checks:\n\n"

scenarios.each do |scenario|
  result = policy_manager.check_compliance(scenario[:context])
  
  puts "#{scenario[:name]}:"
  if result.compliant?
    puts "  ✅ Compliant"
  else
    puts "  ❌ Non-compliant"
    puts "  Violations:"
    result.violations.each do |violation|
      puts "    - #{violation}"
    end
  end
  puts
end

# Example 11: Real-time Compliance Monitoring
puts "Example 11: Real-time Compliance Monitoring"
puts "-" * 50

# Create compliance monitor
monitor = OpenAIAgents::Compliance::ComplianceMonitor.new(audit_logger, policy_manager)

puts "Starting compliance monitoring..."
monitor.start_monitoring

puts "Compliance monitor is now running in background threads:"
puts "  - Agent execution monitoring (60s intervals)"
puts "  - Data access monitoring (30s intervals)"
puts "  - Security event monitoring (10s intervals)"
puts

# Simulate some activity
sleep 1

# Stop monitoring
monitor.stop_monitoring
puts "Compliance monitoring stopped"
puts

# Example 12: Compliance Dashboard Data
puts "Example 12: Compliance Dashboard Data"
puts "-" * 50

# Generate dashboard metrics
dashboard_data = {
  compliance_score: 94.5,
  last_audit: Time.now - 86400,
  active_policies: 12,
  recent_violations: 3,
  data_subjects: 1542,
  consent_records: 1234,
  security_events_24h: 7,
  api_calls_24h: 15420,
  average_response_time: 234,
  encryption_coverage: 98.2
}

puts "Compliance Dashboard Metrics:"
dashboard_data.each do |metric, value|
  formatted_key = metric.to_s.split('_').map(&:capitalize).join(' ')
  puts "  #{formatted_key}: #{value}"
end
puts

# Clean up example files
puts "Cleaning up example files..."
["audit_example.log", "audit_export.json", "audit_export.csv", "audit_export.cef"].each do |file|
  File.delete(file) if File.exist?(file)
end
FileUtils.rm_rf("./audit_logs_example") if Dir.exist?("./audit_logs_example")

# Best practices
puts "\n=== Compliance and Audit Best Practices ==="
puts "-" * 50
puts <<~PRACTICES
  1. Audit Logging:
     - Log all significant events and decisions
     - Include sufficient context for investigation
     - Ensure logs are tamper-resistant
     - Implement log rotation and retention policies
  
  2. PII Handling:
     - Detect and redact PII automatically
     - Log PII access with justification
     - Implement data minimization
     - Honor data subject rights (GDPR)
  
  3. Security Monitoring:
     - Set up alerts for high-severity events
     - Monitor for suspicious patterns
     - Track failed authentication attempts
     - Log all administrative actions
  
  4. Compliance Standards:
     - Map requirements to policies
     - Automate compliance checks
     - Generate regular compliance reports
     - Maintain evidence for audits
  
  5. Data Governance:
     - Track consent and preferences
     - Implement data retention policies
     - Monitor data access patterns
     - Ensure data portability
  
  6. Performance Considerations:
     - Use asynchronous logging where possible
     - Implement log aggregation
     - Monitor logging overhead
     - Use appropriate log levels
  
  7. Integration:
     - Export to SIEM systems
     - Integrate with monitoring tools
     - Automate compliance workflows
     - Enable audit trail queries
PRACTICES

puts "\nCompliance and audit logging example completed!"
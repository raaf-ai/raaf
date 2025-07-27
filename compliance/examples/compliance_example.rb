#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates compliance and audit logging capabilities for enterprise deployments.
# In regulated industries (finance, healthcare, government), comprehensive audit trails are
# mandatory for compliance with standards like GDPR, HIPAA, SOC2, and PCI-DSS. This example
# shows how to implement audit logging, PII detection, consent management, and compliance
# monitoring to meet regulatory requirements and enable forensic analysis.

require "raaf"
require_relative "../lib/openai_agents/compliance"

# Set API key from environment
# In production, use secure credential management systems
OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY", nil)
end

puts "=== Compliance and Audit Logging Example ==="
puts

# Example 1: Basic Audit Logging
# Audit logging creates an immutable record of all system activities.
# This is essential for security investigations, compliance audits, and
# understanding system behavior. The logger captures who did what, when,
# and why, providing complete traceability.
puts "Example 1: Basic Audit Logging"
puts "-" * 50

# Create audit logger with comprehensive configuration
# The logger supports multiple storage backends and compliance standards
audit_logger = RAAF::Compliance::AuditLogger.new(
  log_file: "audit_example.log",  # Primary log file for quick access
  storage_path: "./audit_logs_example",  # Directory for archived logs
  store_conversations: true,  # Store full conversation history for context
  compliance_standards: %w[GDPR SOC2 HIPAA]  # Standards to enforce
)

# Create test agent
agent = RAAF::Agent.new(
  name: "CustomerServiceAgent",
  model: "gpt-4o-mini",
  instructions: "You are a helpful customer service agent."
)

# Simulate agent execution with audit logging
messages = [
  { role: "user", content: "I need help with my account" },
  { role: "assistant", content: "I'd be happy to help you with your account. What specific assistance do you need?" }
]

result = RAAF::Result.new(
  messages: messages,
  agent: agent,
  usage: { total_tokens: 45, prompt_tokens: 20, completion_tokens: 25 }
)

# Log the agent execution with full context
# Every agent interaction is logged with metadata for compliance
# This creates an audit trail showing AI decision-making processes
audit_logger.log_agent_execution(
  agent,
  messages,
  result,
  duration_ms: 1234  # Performance metrics for SLA monitoring
)

puts "Agent execution logged to audit trail"
puts

# Example 2: Tool Usage Logging
# Tools represent external system access points that need careful monitoring.
# Logging tool usage helps track data access patterns, detect anomalies,
# and provide evidence for security audits. Each tool call is logged with
# inputs, outputs, and metadata for complete visibility.
puts "Example 2: Tool Usage Logging"
puts "-" * 50

# Log database access for data governance
# SQL queries are logged with parameters for forensic analysis
# Sensitive data in parameters should be tokenized or hashed
audit_logger.log_tool_usage(
  "database_query",
  { query: "SELECT * FROM users WHERE id = ?", params: ["user123"] },
  "Query executed successfully",
  rows_returned: 1  # Helps detect data exfiltration attempts
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
# Data access logging is crucial for GDPR compliance and data governance.
# Every access to personal or sensitive data must be logged with a valid
# business purpose. This enables data subject access requests and helps
# demonstrate lawful basis for data processing.
puts "Example 3: Data Access Logging"
puts "-" * 50

# Log various data access events with business justification
# The purpose field is mandatory for compliance reporting
audit_logger.log_data_access("user_profile", "user123", "read", { purpose: "customer_support" })
audit_logger.log_data_access("order_history", "order456", "read", { purpose: "order_inquiry" })
audit_logger.log_data_access("payment_method", "card789", "update", { purpose: "payment_update" })

puts "Data access events logged"
puts

# Example 4: Security Event Logging
# Security events require immediate attention and detailed logging.
# The system categorizes events by severity (high/medium/low) to enable
# appropriate response workflows. High-severity events can trigger
# real-time alerts to security teams.
puts "Example 4: Security Event Logging"
puts "-" * 50

# Log unauthorized access attempt - high severity
# This would trigger immediate security team notification
audit_logger.log_security_event(
  "unauthorized_access",
  { resource: "admin_panel", user_id: "user123", ip: "192.168.1.100" },
  :high  # Severity determines alerting and response procedures
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
# PII (Personally Identifiable Information) must be carefully controlled.
# The system automatically detects common PII patterns (emails, phone numbers,
# SSNs, credit cards) and can redact, block, or tokenize them. All PII
# handling is logged for compliance with privacy regulations.
puts "Example 5: PII Detection and Handling"
puts "-" * 50

# Log PII detection events with action taken
# Common actions: redacted (hidden), blocked (rejected), tokenized (replaced)
audit_logger.log_pii_detection(
  "chat_message",
  %w[email phone_number],  # Types of PII detected
  "redacted",  # Action taken to protect the data
  message_id: "msg123"  # Reference for investigation
)

audit_logger.log_pii_detection(
  "tool_response",
  %w[ssn credit_card],
  "blocked",
  tool: "payment_processor"
)

puts "PII detection events logged"
puts

# Example 6: Consent Management
# GDPR and similar regulations require explicit consent tracking.
# Every consent grant, revocation, or modification must be logged with
# timestamp and source. This creates a legal record of user permissions
# that can be audited and used to enforce data processing boundaries.
puts "Example 6: Consent Management"
puts "-" * 50

# Log consent events for GDPR Article 7 compliance
# The source field tracks where consent was obtained
audit_logger.log_consent_event(
  "user123",
  "marketing_emails",  # Specific purpose requiring consent
  "granted",  # Status: granted, revoked, modified
  source: "preferences_page"  # UI location or API endpoint
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
# Audit reports summarize system activity for compliance officers,
# security teams, and external auditors. Reports include event counts,
# compliance metrics, anomalies, and recommendations. They can be
# generated on-demand or scheduled for regular compliance reviews.
puts "Example 7: Generate Audit Report"
puts "-" * 50

# Generate comprehensive audit report for specified time range
# Reports can cover any period: hourly, daily, monthly, or custom
puts "Generating audit report..."
report = audit_logger.generate_audit_report(
  start_time: Time.now - 3600, # Last hour
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
# Audit logs must be exportable for external analysis, long-term storage,
# and integration with SIEM (Security Information and Event Management)
# systems. Multiple formats ensure compatibility with various tools and
# compliance requirements.
puts "Example 8: Export Audit Logs"
puts "-" * 50

# Export in different formats for different use cases
puts "Exporting audit logs..."

# JSON export for programmatic analysis and archival
# JSON preserves full structure and metadata
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
# Audit logs must be tamper-evident to be legally admissible.
# The system uses cryptographic hashing to detect any modifications
# to log entries. Regular integrity checks ensure the audit trail
# remains trustworthy for compliance and forensic purposes.
puts "Example 9: Log Integrity Verification"
puts "-" * 50

# Verify log integrity using cryptographic checksums
# Each log entry includes a hash chain for tamper detection
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
# Automated policy checking ensures consistent enforcement of compliance
# rules. The policy manager evaluates contexts against configured policies
# for data retention, access control, PII handling, and audit requirements.
# This proactive approach prevents violations before they occur.
puts "Example 10: Policy Compliance Checking"
puts "-" * 50

# Create policy manager with default enterprise policies
# Policies can be customized per organization requirements
policy_manager = RAAF::Compliance::PolicyManager.new

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
# Real-time monitoring detects compliance violations as they happen,
# enabling immediate response. The monitor runs background threads that
# continuously check for policy violations, anomalies, and security events.
# This proactive approach minimizes risk and regulatory exposure.
puts "Example 11: Real-time Compliance Monitoring"
puts "-" * 50

# Create compliance monitor combining audit logs and policies
# The monitor correlates events with policies for real-time enforcement
monitor = RAAF::Compliance::ComplianceMonitor.new(audit_logger, policy_manager)

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
# Executive dashboards provide at-a-glance compliance status for
# leadership and compliance officers. Key metrics include compliance
# scores, violation trends, and coverage percentages. This data
# drives continuous improvement and risk management decisions.
puts "Example 12: Compliance Dashboard Data"
puts "-" * 50

# Generate dashboard metrics for compliance visibility
# These metrics would typically come from aggregated audit logs
dashboard_data = {
  compliance_score: 94.5,  # Overall compliance percentage
  last_audit: Time.now - 86_400,  # Time since last audit
  active_policies: 12,  # Number of enforced policies
  recent_violations: 3,  # Violations in last 24 hours
  data_subjects: 1542,  # GDPR data subjects tracked
  consent_records: 1234,  # Active consent records
  security_events_24h: 7,  # Security events today
  api_calls_24h: 15_420,  # System usage volume
  average_response_time: 234,  # Performance metric (ms)
  encryption_coverage: 98.2  # Percentage of encrypted data
}

puts "Compliance Dashboard Metrics:"
dashboard_data.each do |metric, value|
  formatted_key = metric.to_s.split("_").map(&:capitalize).join(" ")
  puts "  #{formatted_key}: #{value}"
end
puts

# Clean up example files
# In production, audit logs would be archived, not deleted
# This cleanup is only for the example to avoid leaving test files
puts "Cleaning up example files..."
["audit_example.log", "audit_export.json", "audit_export.csv", "audit_export.cef"].each do |file|
  FileUtils.rm_f(file)
end
FileUtils.rm_rf("./audit_logs_example")

# Best practices section provides actionable guidance for implementing
# compliance systems in production. These recommendations come from
# real-world deployments in regulated industries and align with
# industry standards and regulatory requirements.
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

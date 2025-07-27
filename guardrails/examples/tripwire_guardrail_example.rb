#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates tripwire guardrails for RAAF (Ruby AI Agents Factory).
# Tripwires provide an immediate-stop security mechanism that halts execution
# when dangerous patterns are detected. Unlike other guardrails that may
# modify or redirect behavior, tripwires act as circuit breakers - they
# throw exceptions to completely stop potentially harmful operations.
# This is essential for preventing security breaches, data loss, and
# maintaining compliance in production AI applications.

require "raaf"
require_relative "../lib/openai_agents/guardrails/tripwire"

# Example demonstrating Guardrail Tripwire functionality

unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY environment variable is required"
  puts "Please set it with: export OPENAI_API_KEY='your-api-key'"
  exit 1
end

puts "=== Guardrail Tripwire Example ==="
puts
puts "This example shows how tripwire guardrails can immediately stop dangerous operations."
puts

# ============================================================================
# EXAMPLE 1: BASIC TRIPWIRE WITH PATTERNS AND KEYWORDS
# ============================================================================
# Tripwires can detect threats using regex patterns and keyword lists.
# Patterns allow complex matching (case-insensitive SQL commands, shell commands)
# while keywords provide simple string matching for known dangerous terms.
# When either triggers, execution stops immediately with an exception.

puts "1. Basic tripwire with patterns and keywords:"

# Create tripwire with common dangerous patterns
# These patterns catch SQL injection, filesystem destruction, and malicious terms
tripwire = RAAF::Guardrails::TripwireGuardrail.new(
  patterns: [
    /DROP TABLE/i,      # SQL table deletion
    /DELETE FROM/i,     # SQL data deletion
    /rm -rf/i          # Unix recursive force delete
  ],
  keywords: %w[hack exploit virus malware]  # Security threat indicators
)

# Test various inputs to demonstrate tripwire behavior
# Some are safe, others contain dangerous patterns/keywords
test_contents = [
  "Please help me optimize my database query",    # Safe database question
  "How do I DROP TABLE users?",                   # Dangerous SQL command
  "I want to learn about computer security",      # Safe security education
  "Tell me how to hack into systems"             # Malicious intent keyword
]

# Check each input and handle tripwire exceptions
# The begin/rescue pattern allows continued testing after blocks
test_contents.each do |content|
  tripwire.check_input(content)
  puts "✓ Safe: #{content[0..50]}..."
rescue RAAF::Guardrails::TripwireGuardrail::TripwireException => e
  # TripwireException provides detailed blocking information
  puts "✗ BLOCKED: #{content[0..50]}..."
  puts "  Reason: #{e.message}"
  puts "  Triggered by: #{e.triggered_by}"  # Shows which pattern/keyword matched
end
puts

# ============================================================================
# EXAMPLE 2: CUSTOM DETECTOR FOR DOMAIN-SPECIFIC THREATS
# ============================================================================
# Custom detectors allow implementing complex business logic for threat detection.
# This example shows financial fraud detection using multiple indicators.
# The block receives content and returns true to trigger the tripwire.
# This flexibility enables domain-specific security rules beyond simple patterns.

puts "2. Tripwire with custom detector for financial fraud:"

# Create tripwire with custom detection logic
# Block evaluates content and returns boolean
fraud_tripwire = RAAF::Guardrails::TripwireGuardrail.new do |content|
  # Multi-factor fraud detection logic
  # Combines urgency, money mentions, and suspicious payment methods
  urgent = content.match?(/urgent|immediately|asap|right now/i)
  money = content.match?(/\$\d+|transfer|wire|payment/i)
  suspicious = content.match?(/bitcoin|crypto|western union/i)

  # Trigger if urgent + money OR any suspicious payment method
  (urgent && money) || suspicious
end

fraud_tests = [
  "Can you help me understand Bitcoin?",
  "URGENT: Transfer $5000 immediately!",
  "How do wire transfers work?",
  "Send payment ASAP to this crypto wallet"
]

fraud_tests.each do |content|
  fraud_tripwire.check_input(content)
  puts "✓ Safe: #{content}"
rescue RAAF::Guardrails::TripwireGuardrail::TripwireException
  puts "✗ FRAUD ALERT: #{content}"
end
puts

# ============================================================================
# EXAMPLE 3: TOOL CALL PROTECTION
# ============================================================================
# Tools can perform dangerous operations like database queries or system commands.
# Tripwires can inspect tool names and arguments before execution.
# This prevents AI agents from being tricked into executing harmful commands
# through prompt injection or other attack vectors.

puts "3. Protecting dangerous tool calls:"

# Create tripwire for tool protection
# Will use default dangerous command patterns
tool_tripwire = RAAF::Guardrails::TripwireGuardrail.new

# Test various tool calls - some safe, some dangerous
# Tool protection is crucial for agents with system access
dangerous_tools = [
  { name: "execute_sql", args: { query: "SELECT * FROM users" } },      # Safe query
  { name: "execute_sql", args: { query: "DROP TABLE customers" } },     # Destructive SQL
  { name: "run_command", args: { command: "ls -la" } },                # Safe listing
  { name: "run_command", args: { command: "rm -rf /important" } }      # Dangerous delete
]

# Check each tool call for dangerous patterns in arguments
dangerous_tools.each do |tool|
  tool_tripwire.check_tool_call(tool[:name], tool[:args])
  puts "✓ Allowed: #{tool[:name]}(#{tool[:args]})"
rescue RAAF::Guardrails::TripwireGuardrail::TripwireException => e
  puts "✗ BLOCKED: #{tool[:name]}(#{tool[:args]})"
  puts "  Reason: #{e.message}"
end
puts

# ============================================================================
# EXAMPLE 4: PRE-CONFIGURED SECURITY TRIPWIRES
# ============================================================================
# Common attack patterns are pre-configured for immediate use.
# These tripwires are battle-tested against known security vulnerabilities
# and follow OWASP guidelines for web application security.
# Using pre-configured tripwires ensures consistent security across applications.

puts "4. Using pre-configured security tripwires:"

# SQL injection tripwire with comprehensive pattern matching
# Detects UNION attacks, comment injection, boolean blinds, etc.
sql_tripwire = RAAF::Guardrails::CommonTripwires.sql_injection

sql_tests = [
  "SELECT * FROM products WHERE id = 123",
  "SELECT * FROM users WHERE name = 'admin' OR 1=1",
  "'; DROP TABLE users; --",
  "UNION SELECT password FROM admins"
]

puts "\nSQL Injection Detection:"
sql_tests.each do |query|
  sql_tripwire.check_input(query)
  puts "✓ Safe SQL: #{query[0..40]}..."
rescue StandardError
  puts "✗ SQL INJECTION: #{query[0..40]}..."
end

# Path traversal tripwire prevents directory traversal attacks
# Detects ../, encoded traversal sequences, and absolute path escapes
path_tripwire = RAAF::Guardrails::CommonTripwires.path_traversal

# Test paths including safe paths and various traversal attempts
path_tests = [
  "/home/user/documents/file.txt",         # Safe absolute path
  "../../etc/passwd",                      # Classic traversal attack
  "files/%2e%2e%2f%2e%2e%2fconfig",       # URL-encoded traversal
  "C:\\Users\\Public\\Documents\\report.pdf"  # Safe Windows path
]

puts "\nPath Traversal Detection:"
path_tests.each do |path|
  path_tripwire.check_input(path)
  puts "✓ Safe path: #{path}"
rescue StandardError
  puts "✗ PATH TRAVERSAL: #{path}"
end
puts

# ============================================================================
# EXAMPLE 5: AGENT INTEGRATION WITH TRIPWIRE PROTECTION
# ============================================================================
# This demonstrates protecting an AI agent's tools with tripwires.
# By wrapping tool execution, we ensure the agent cannot be tricked
# into running dangerous code through prompt injection or confusion.
# This pattern is essential for agents with system-level capabilities.

puts "5. Agent with tripwire guardrails:"

# Mock code execution tool (would be sandboxed in production)
# Real implementation would use containers or VMs for isolation
def execute_code(language:, code:)
  # Simulated code execution
  "Executed #{language} code: #{code[0..30]}..."
end

# Create agent
code_agent = RAAF::Agent.new(
  name: "CodeAssistant",
  instructions: "You help users write and execute code safely.",
  model: "gpt-4o"
)

code_agent.add_tool(
  RAAF::FunctionTool.new(
    method(:execute_code),
    name: "execute_code",
    description: "Execute code in various languages"
  )
)

# Create comprehensive code execution tripwire
# Detects various code injection and system access attempts
# Patterns cover multiple languages (Ruby, Python, JavaScript)
code_tripwire = RAAF::Guardrails::TripwireGuardrail.new(
  patterns: [
    /system\s*\(/i,     # System calls in various languages
    /exec\s*\(/i,       # Process execution
    /eval\s*\(/i,       # Dynamic code evaluation
    /__import__/,       # Python dynamic imports
    /os\.system/,       # Python OS commands
    /subprocess/        # Python subprocess module
  ],
  keywords: %w[rm delete format drop]  # Dangerous command keywords
)

# Monkey-patch tool execution to add tripwire protection
# This technique intercepts tool calls before execution
# In production, use proper middleware or decorator patterns
original_execute = code_agent.method(:execute_tool)
code_agent.define_singleton_method(:execute_tool) do |name, **kwargs|
  # Check only code execution tools (other tools may be safe)
  code_tripwire.check_tool_call(name, kwargs) if name == "execute_code"
  # Call original method if tripwire doesn't trigger
  original_execute.call(name, **kwargs)
end

# Test the protected agent
test_codes = [
  { language: "python", code: "print('Hello, World!')" },
  { language: "python", code: "import os; os.system('rm -rf /')" },
  { language: "ruby", code: "puts 'Safe code'" },
  { language: "ruby", code: "eval('system(\"dangerous\")')" }
]

puts "\nProtected code execution:"
test_codes.each do |test|
  code_agent.execute_tool("execute_code", **test)
  puts "✓ Executed: #{test[:code][0..40]}..."
rescue RAAF::Guardrails::TripwireGuardrail::TripwireException => e
  puts "✗ BLOCKED: #{test[:code][0..40]}..."
  puts "  Security violation: #{e.triggered_by}"
end
puts

# ============================================================================
# EXAMPLE 6: COMPOSITE TRIPWIRE FOR COMPREHENSIVE SECURITY
# ============================================================================
# Composite tripwires combine multiple security checks in one guardrail.
# This provides defense-in-depth by checking for SQL injection, command injection,
# path traversal, and other attacks simultaneously. One tripwire to rule them all.

puts "6. Comprehensive security with composite tripwire:"

# Create composite tripwire with all security patterns
# Includes: SQL injection, command injection, path traversal, XSS, etc.
security_tripwire = RAAF::Guardrails::CommonTripwires.all_security

security_tests = [
  "Normal conversation about programming",
  "'; DROP TABLE users; --",
  "../../etc/shadow",
  "My email is test@example.com",
  "rm -rf / && echo 'done'"
]

puts "\nComprehensive security scan:"
security_tests.each do |content|
  security_tripwire.check_input(content)
  puts "✓ Passed all checks: #{content[0..40]}..."
rescue StandardError
  puts "✗ SECURITY VIOLATION: #{content[0..40]}..."
end
puts

# ============================================================================
# EXAMPLE 7: MONITORING AND STATISTICS
# ============================================================================
# Tripwires collect statistics about triggers for security monitoring.
# This data helps identify attack patterns, tune sensitivity, and
# provide audit trails for compliance. Regular analysis of tripwire
# statistics can reveal emerging threats.

puts "7. Tripwire statistics and logging:"

# Create tripwire with simple keywords for demonstration
stats_tripwire = RAAF::Guardrails::TripwireGuardrail.new(
  keywords: %w[danger risk]
)

# Trigger it a few times
["safe content", "danger zone", "risky business", "all good"].each do |content|
  stats_tripwire.check_input(content)
rescue StandardError
  # Ignore exceptions for stats demo
end

stats = stats_tripwire.stats
puts "Tripwire Statistics:"
puts "- Triggered count: #{stats[:triggered_count]}"
puts "- Patterns configured: #{stats[:patterns]}"
puts "- Keywords configured: #{stats[:keywords]}"
puts "- Recent triggers: #{stats[:trigger_log].size}"
stats[:trigger_log].each do |log|
  puts "  - #{log[:timestamp].strftime("%H:%M:%S")}: #{log[:message]}"
end

# ============================================================================
# SUMMARY AND BEST PRACTICES
# ============================================================================

puts "\n=== Example Complete ==="
puts
puts "Key takeaways:"
puts "- Tripwires immediately stop execution when threats are detected"
puts "- Can protect against SQL injection, command injection, path traversal"
puts "- Custom detectors allow domain-specific security rules"
puts "- Pre-configured tripwires available for common security concerns"
puts "- Composite tripwires combine multiple security checks"
puts "- Statistics help monitor security events"
puts
puts "Best Practices:"
puts "1. Layer tripwires - use multiple checks for defense in depth"
puts "2. Log all triggers - maintain audit trails for security reviews"
puts "3. Test thoroughly - ensure legitimate use cases aren't blocked"
puts "4. Update patterns - adapt to new attack vectors"
puts "5. Monitor statistics - identify trends and tune sensitivity"

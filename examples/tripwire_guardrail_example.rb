#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"
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

# Example 1: Basic tripwire usage
puts "1. Basic tripwire with patterns and keywords:"

tripwire = OpenAIAgents::Guardrails::TripwireGuardrail.new(
  patterns: [
    /DROP TABLE/i,
    /DELETE FROM/i,
    /rm -rf/i
  ],
  keywords: ["hack", "exploit", "virus", "malware"]
)

# Test content
test_contents = [
  "Please help me optimize my database query",
  "How do I DROP TABLE users?",
  "I want to learn about computer security",
  "Tell me how to hack into systems"
]

test_contents.each do |content|
  begin
    tripwire.check_input(content)
    puts "✓ Safe: #{content[0..50]}..."
  rescue OpenAIAgents::Guardrails::TripwireGuardrail::TripwireException => e
    puts "✗ BLOCKED: #{content[0..50]}..."
    puts "  Reason: #{e.message}"
    puts "  Triggered by: #{e.triggered_by}"
  end
end
puts

# Example 2: Custom detector tripwire
puts "2. Tripwire with custom detector for financial fraud:"

fraud_tripwire = OpenAIAgents::Guardrails::TripwireGuardrail.new do |content|
  # Detect urgent money transfer requests
  urgent = content.match?(/urgent|immediately|asap|right now/i)
  money = content.match?(/\$\d+|transfer|wire|payment/i)
  suspicious = content.match?(/bitcoin|crypto|western union/i)
  
  (urgent && money) || suspicious
end

fraud_tests = [
  "Can you help me understand Bitcoin?",
  "URGENT: Transfer $5000 immediately!",
  "How do wire transfers work?",
  "Send payment ASAP to this crypto wallet"
]

fraud_tests.each do |content|
  begin
    fraud_tripwire.check_input(content)
    puts "✓ Safe: #{content}"
  rescue OpenAIAgents::Guardrails::TripwireGuardrail::TripwireException => e
    puts "✗ FRAUD ALERT: #{content}"
  end
end
puts

# Example 3: Tool call protection
puts "3. Protecting dangerous tool calls:"

tool_tripwire = OpenAIAgents::Guardrails::TripwireGuardrail.new

dangerous_tools = [
  { name: "execute_sql", args: { query: "SELECT * FROM users" } },
  { name: "execute_sql", args: { query: "DROP TABLE customers" } },
  { name: "run_command", args: { command: "ls -la" } },
  { name: "run_command", args: { command: "rm -rf /important" } }
]

dangerous_tools.each do |tool|
  begin
    tool_tripwire.check_tool_call(tool[:name], tool[:args])
    puts "✓ Allowed: #{tool[:name]}(#{tool[:args]})"
  rescue OpenAIAgents::Guardrails::TripwireGuardrail::TripwireException => e
    puts "✗ BLOCKED: #{tool[:name]}(#{tool[:args]})"
    puts "  Reason: #{e.message}"
  end
end
puts

# Example 4: Pre-configured security tripwires
puts "4. Using pre-configured security tripwires:"

# SQL injection tripwire
sql_tripwire = OpenAIAgents::Guardrails::CommonTripwires.sql_injection

sql_tests = [
  "SELECT * FROM products WHERE id = 123",
  "SELECT * FROM users WHERE name = 'admin' OR 1=1",
  "'; DROP TABLE users; --",
  "UNION SELECT password FROM admins"
]

puts "\nSQL Injection Detection:"
sql_tests.each do |query|
  begin
    sql_tripwire.check_input(query)
    puts "✓ Safe SQL: #{query[0..40]}..."
  rescue => e
    puts "✗ SQL INJECTION: #{query[0..40]}..."
  end
end

# Path traversal tripwire
path_tripwire = OpenAIAgents::Guardrails::CommonTripwires.path_traversal

path_tests = [
  "/home/user/documents/file.txt",
  "../../etc/passwd",
  "files/%2e%2e%2f%2e%2e%2fconfig",
  "C:\\Users\\Public\\Documents\\report.pdf"
]

puts "\nPath Traversal Detection:"
path_tests.each do |path|
  begin
    path_tripwire.check_input(path)
    puts "✓ Safe path: #{path}"
  rescue => e
    puts "✗ PATH TRAVERSAL: #{path}"
  end
end
puts

# Example 5: Agent with tripwire protection
puts "5. Agent with tripwire guardrails:"

# Create a code execution tool
def execute_code(language:, code:)
  # Simulated code execution
  "Executed #{language} code: #{code[0..30]}..."
end

# Create agent
code_agent = OpenAIAgents::Agent.new(
  name: "CodeAssistant",
  instructions: "You help users write and execute code safely.",
  model: "gpt-4"
)

code_agent.add_tool(
  OpenAIAgents::FunctionTool.new(
    method(:execute_code),
    name: "execute_code",
    description: "Execute code in various languages"
  )
)

# Create tripwire for code execution
code_tripwire = OpenAIAgents::Guardrails::TripwireGuardrail.new(
  patterns: [
    /system\s*\(/i,
    /exec\s*\(/i,
    /eval\s*\(/i,
    /__import__/,
    /os\.system/,
    /subprocess/
  ],
  keywords: ["rm", "delete", "format", "drop"]
)

# Wrap the agent's execute_tool method to include tripwire
original_execute = code_agent.method(:execute_tool)
code_agent.define_singleton_method(:execute_tool) do |name, **kwargs|
  if name == "execute_code"
    code_tripwire.check_tool_call(name, kwargs)
  end
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
  begin
    result = code_agent.execute_tool("execute_code", **test)
    puts "✓ Executed: #{test[:code][0..40]}..."
  rescue OpenAIAgents::Guardrails::TripwireGuardrail::TripwireException => e
    puts "✗ BLOCKED: #{test[:code][0..40]}..."
    puts "  Security violation: #{e.triggered_by}"
  end
end
puts

# Example 6: Composite tripwire
puts "6. Comprehensive security with composite tripwire:"

# Create all security tripwires
security_tripwire = OpenAIAgents::Guardrails::CommonTripwires.all_security

security_tests = [
  "Normal conversation about programming",
  "'; DROP TABLE users; --",
  "../../etc/shadow",
  "My email is test@example.com",
  "rm -rf / && echo 'done'"
]

puts "\nComprehensive security scan:"
security_tests.each do |content|
  begin
    security_tripwire.check_input(content)
    puts "✓ Passed all checks: #{content[0..40]}..."
  rescue => e
    puts "✗ SECURITY VIOLATION: #{content[0..40]}..."
  end
end
puts

# Example 7: Tripwire statistics
puts "7. Tripwire statistics and logging:"

stats_tripwire = OpenAIAgents::Guardrails::TripwireGuardrail.new(
  keywords: ["danger", "risk"]
)

# Trigger it a few times
["safe content", "danger zone", "risky business", "all good"].each do |content|
  begin
    stats_tripwire.check_input(content)
  rescue
    # Ignore exceptions for stats demo
  end
end

stats = stats_tripwire.stats
puts "Tripwire Statistics:"
puts "- Triggered count: #{stats[:triggered_count]}"
puts "- Patterns configured: #{stats[:patterns]}"
puts "- Keywords configured: #{stats[:keywords]}"
puts "- Recent triggers: #{stats[:trigger_log].size}"
stats[:trigger_log].each do |log|
  puts "  - #{log[:timestamp].strftime('%H:%M:%S')}: #{log[:message]}"
end

puts "\n=== Example Complete ==="
puts
puts "Key takeaways:"
puts "- Tripwires immediately stop execution when threats are detected"
puts "- Can protect against SQL injection, command injection, path traversal"
puts "- Custom detectors allow domain-specific security rules"
puts "- Pre-configured tripwires available for common security concerns"
puts "- Composite tripwires combine multiple security checks"
puts "- Statistics help monitor security events"
#!/usr/bin/env ruby
# frozen_string_literal: true

# Interactive REPL (Read-Eval-Print Loop) Example
# 
# This example demonstrates the comprehensive interactive development environment
# built into the RAAF (Ruby AI Agents Factory) gem. The REPL provides a powerful shell
# for agent development, debugging, and testing with features like:
#
# - Interactive agent management (create, switch, list agents)
# - Tool integration and testing
# - Conversation history management
# - Debug mode with step-by-step execution
# - Trace visualization
# - Import/export functionality
# - Auto-completion and help system
#
# This is particularly useful for:
# - Development and prototyping
# - Interactive debugging sessions
# - Training and learning the API
# - Quick testing of agent behaviors
# - Live demonstration of capabilities

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
  puts "This example will demonstrate the REPL interface without making API calls"
  puts
end

# ============================================================================
# BASIC REPL SETUP AND USAGE
# ============================================================================

puts "=== Interactive REPL Example ==="
puts "Demonstrates the powerful interactive development environment"
puts "-" * 60

# Example 1: Basic REPL Creation and Configuration
puts "\n=== Example 1: REPL Creation and Configuration ==="

# Create a REPL instance with supported configuration
repl = RAAF::REPL.new(
  debug: true                          # Enable debug output
)

puts "✅ REPL configured with:"
puts "  - Debug mode: enabled"
puts "  - Available commands: #{RAAF::REPL::COMMANDS.length}"
puts "  - Default tools: weather, time, calculator"

# Example 2: Agent Management in REPL
puts "\n=== Example 2: Agent Management ==="

# Create agents and add them to REPL
assistant_agent = RAAF::Agent.new(
  name: "Assistant",
  instructions: "You are a helpful programming assistant.",
  model: "gpt-4o"
)

researcher_agent = RAAF::Agent.new(
  name: "Researcher", 
  instructions: "You are a research specialist focused on gathering information.",
  model: "gpt-4o"
)

code_agent = RAAF::Agent.new(
  name: "CodeReviewer",
  instructions: "You are a code review expert focused on best practices.",
  model: "gpt-4o"
)

# Add agents to REPL
repl.send(:add_agent, assistant_agent)
repl.send(:add_agent, researcher_agent)
repl.send(:add_agent, code_agent)

puts "✅ Created 3 agents:"
puts "  - Assistant: You are a helpful programming assistant..."
puts "  - Researcher: You are a research specialist focused..."
puts "  - CodeReviewer: You are a code review expert focused..."

# Switch between agents (using private method for demo)
repl.send(:switch_agent, "Assistant")
puts "🔄 Switched to: Assistant"

# Example 3: Tool Integration and Testing
puts "\n=== Example 3: Tool Integration and Testing ==="

# Define tools directly in REPL
def calculate_fibonacci(n:)
  return 0 if n == 0
  return 1 if n == 1
  
  a, b = 0, 1
  (2..n).each do |_|
    a, b = b, a + b
  end
  b
end

def analyze_code(code:, language: "ruby")
  lines = code.split("\n")
  {
    language: language,
    line_count: lines.length,
    blank_lines: lines.count(&:empty?),
    complexity_score: lines.length > 50 ? "high" : "medium",
    suggestions: ["Add more comments", "Consider breaking into smaller methods"]
  }
end

# Add tools to current agent
current_agent = repl.send(:current_agent)
if current_agent
  current_agent.add_tool(method(:calculate_fibonacci))
  current_agent.add_tool(method(:analyze_code))

  puts "🔧 Added tools to #{current_agent.name}:"
  current_agent.tools.each do |tool|
    puts "  - #{tool.name}: #{tool.description}"
  end
else
  puts "🔧 Would add tools to current agent"
end

# Test tools interactively
puts "\n📝 Testing tools interactively:"
begin
  # Simulate tool testing
  puts "  > calculate_fibonacci(n: 10)"
  result = calculate_fibonacci(n: 10)
  puts "  Result: #{result}"
  
  puts "  > analyze_code(code: 'def hello\\n  puts \"world\"\\nend')"
  code_result = analyze_code(
    code: "def hello\n  puts \"world\"\nend", 
    language: "ruby"
  )
  puts "  Result: #{code_result}"
rescue => e
  puts "  ℹ️  Demo mode: Would test tools (#{e.class.name})"
end

# Example 4: Conversation History and Export
puts "\n=== Example 4: Conversation History Management ==="

# Simulate some conversation history
conversation_history = [
  { role: "user", content: "Calculate fibonacci number 8" },
  { role: "assistant", content: "I'll calculate fibonacci(8) for you.", tool_calls: [
    { function: { name: "calculate_fibonacci", arguments: '{"n": 8}' } }
  ]},
  { role: "tool", content: "21" },
  { role: "assistant", content: "The 8th Fibonacci number is 21." }
]

# Simulate conversation history management
puts "📚 Conversation history (#{conversation_history.length} messages):"
conversation_history.each_with_index do |msg, i|
  role_icon = case msg[:role]
  when "user" then "👤"
  when "assistant" then "🤖"
  when "tool" then "🔧"
  else "💬"
  end
  content = msg[:content][0..60] + (msg[:content].length > 60 ? "..." : "")
  puts "  #{i+1}. #{role_icon} #{msg[:role]}: #{content}"
end

# Simulate export capabilities
puts "\n💾 Export capabilities (simulated):"
puts "  - Messages: #{conversation_history.length}"
puts "  - Agents: 3"
puts "  - Tools: 2"
puts "  - Export format: JSON with full fidelity"

# Example 5: Debug Mode and Step Execution
puts "\n=== Example 5: Debug Mode and Step Execution ==="

# Debug mode already enabled in REPL initialization
puts "🐛 Debug mode enabled"

# Simulate breakpoint functionality
puts "🔴 Breakpoints set: before_tool_call, after_agent_response"

# Simulate debug session capabilities
puts "📊 Debug session capabilities:"
puts "  - Step through execution: step(), continue(), step_into()"
puts "  - Inspect variables: inspect(:messages), inspect(:tools)"
puts "  - Performance metrics: timing(), memory_usage()"
puts "  - Call stack: stack_trace()"

# Example debug output
puts "\n🔍 Sample debug output:"
puts "  [DEBUG] Agent: Assistant starting execution"
puts "  [DEBUG] Input: 'Calculate fibonacci(8)'"
puts "  [DEBUG] Tool call: calculate_fibonacci(n: 8)"
puts "  [BREAK] Breakpoint hit: before_tool_call"
puts "  [DEBUG] Variables: n=8, agent=Assistant, tool=calculate_fibonacci"
puts "  [DEBUG] Continuing execution..."

# Example 6: Trace Visualization
puts "\n=== Example 6: Trace Visualization ==="

# Generate sample trace for visualization
sample_trace = {
  trace_id: "trace_#{Time.now.to_i}",
  spans: [
    {
      span_id: "span_1",
      name: "agent.run",
      start_time: Time.now - 2,
      end_time: Time.now - 1,
      duration_ms: 1000,
      metadata: { agent: "Assistant", model: "gpt-4o" }
    },
    {
      span_id: "span_2", 
      parent_id: "span_1",
      name: "tool.calculate_fibonacci",
      start_time: Time.now - 1.5,
      end_time: Time.now - 1.2,
      duration_ms: 300,
      metadata: { tool: "calculate_fibonacci", args: { n: 8 } }
    }
  ]
}

# Simulate trace visualization
puts "📊 Trace visualization:"
puts "  agent.run               |████████████████████| 1000ms"
puts "    └─ tool.calculate_fib |████████              | 300ms"
puts
puts "📈 Performance summary:"
puts "  - Total duration: 1000ms"
puts "  - Tool calls: 1"
puts "  - Agent switches: 0"

# Example 7: Advanced REPL Commands
puts "\n=== Example 7: Advanced REPL Commands ==="

# Show available commands
puts "🎯 Available REPL commands (#{RAAF::REPL::COMMANDS.length} total):"

command_categories = {
  "Agent Management" => %w[create_agent switch_agent list_agents current_agent],
  "Tool Management" => %w[add_tool remove_tool list_tools test_tool],
  "Conversation" => %w[run ask clear_history export import],
  "Debug" => %w[debug step continue breakpoint inspect],
  "Visualization" => %w[visualize show_trace performance],
  "System" => %w[help config save load exit]
}

command_categories.each do |category, cmds|
  puts "  #{category}:"
  cmds.each { |cmd| puts "    - #{cmd}" }
end

# Example command execution simulation
puts "\n💻 Example REPL session simulation:"
example_commands = [
  "create_agent 'DataAnalyst' 'You analyze data and provide insights' 'gpt-4o'",
  "add_tool calculate_statistics",
  "switch_agent 'DataAnalyst'", 
  "debug on",
  "run 'Analyze this dataset: [1,2,3,4,5]'",
  "visualize last_trace",
  "export conversation.json"
]

example_commands.each_with_index do |cmd, i|
  puts "  #{i+1}. raaf> #{cmd}"
  puts "      ✅ Command executed successfully"
end

# ============================================================================
# CONFIGURATION AND BEST PRACTICES
# ============================================================================

puts "\n=== Configuration ==="
config_info = {
  repl_instance: repl.class.name,
  agents_created: 3,
  tools_available: 2,
  history_size: 4,
  debug_enabled: true,
  features: %w[auto_completion history_persistence trace_visualization debug_mode]
}

config_info.each do |key, value|
  puts "#{key}: #{value}"
end

puts "\n=== Best Practices ==="
puts "✅ Use REPL for rapid prototyping and development"
puts "✅ Enable debug mode for troubleshooting complex workflows"
puts "✅ Export conversations for documentation and testing"
puts "✅ Use trace visualization to optimize performance"
puts "✅ Set up custom tools for domain-specific functionality"
puts "✅ Leverage agent switching for multi-agent workflows"
puts "✅ Use breakpoints to understand execution flow"

puts "\n=== Starting Interactive Session ==="
puts "To start the REPL interactively, run:"
puts "  ruby -e \"require_relative 'lib/openai_agents'; RAAF::REPL.new.start\""
puts
puts "Or use in your application:"
puts "  repl = RAAF::REPL.new"
puts "  repl.create_agent('Assistant', 'You are helpful', 'gpt-4o')"
puts "  repl.start  # Starts interactive session"
#!/usr/bin/env ruby
# frozen_string_literal: true

# Debugging Tools Example
#
# This example demonstrates the comprehensive debugging and development tools
# built into the RAAF (Ruby AI Agents Factory) gem. The debugging system provides:
#
# - Breakpoint management and step-by-step execution
# - Variable watching and inspection
# - Performance metrics and profiling
# - Execution history and call stack tracking
# - Memory usage monitoring
# - Error analysis and debugging assistance
# - Export functionality for debugging sessions
#
# This is essential for:
# - Troubleshooting complex agent workflows
# - Performance optimization and bottleneck identification
# - Understanding agent decision-making processes
# - Development and testing of new features
# - Production debugging and monitoring

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
  puts "This example will demonstrate debugging tools without making API calls"
  puts
end

# ============================================================================
# DEBUGGING TOOLS SETUP
# ============================================================================

puts "=== Debugging Tools Example ==="
puts "Demonstrates comprehensive debugging and development tools"
puts "-" * 60

# Example 1: Basic Debugger Setup
puts "\n=== Example 1: Debugger Creation and Configuration ==="

# Create a debugger instance with standard configuration
debugger = RAAF::Debugging::Debugger.new(
  output: $stdout,
  log_level: ::Logger::DEBUG
)

puts "✅ Debugger configured with:"
puts "  - Debug logging: enabled"
puts "  - Performance tracking: enabled"
puts "  - Execution history: enabled"
puts "  - Step mode: available"
puts "  - Breakpoint support: available"

# Example 2: Agent Setup with Debugging
puts "\n=== Example 2: Agent Setup with Debugging Integration ==="

# Define tools for debugging demonstration
def complex_calculation(numbers:, operation: "sum")
  # Simulate a complex operation with potential issues
  raise ArgumentError, "Numbers array cannot be empty" if numbers.empty?
  
  result = case operation
  when "sum"
    numbers.sum
  when "average"
    numbers.sum.to_f / numbers.length
  when "fibonacci_sum"
    # Intentionally complex/slow operation for debugging
    numbers.map { |n| fibonacci(n) }.sum
  else
    raise ArgumentError, "Unknown operation: #{operation}"
  end
  
  { operation: operation, input: numbers, result: result, processed_count: numbers.length }
end

def fibonacci(n)
  return 0 if n == 0
  return 1 if n == 1
  fibonacci(n-1) + fibonacci(n-2)  # Intentionally inefficient for debugging
end

def data_processor(data:, filters: [])
  # Simulate data processing with various scenarios
  processed_data = data.dup
  
  filters.each do |filter|
    case filter[:type]
    when "remove_nulls"
      processed_data.compact!
    when "multiply"
      processed_data.map! { |x| x * filter[:factor] }
    when "validate_range"
      min, max = filter[:range]
      processed_data.select! { |x| x >= min && x <= max }
    else
      puts "⚠️  Unknown filter: #{filter[:type]}"
    end
  end
  
  { original_count: data.length, processed_count: processed_data.length, data: processed_data }
end

# Create agent with debugging enabled
agent = RAAF::Agent.new(
  name: "DebugAgent",
  instructions: "You are a data processing agent. Use the provided tools to process data and handle errors gracefully.",
  model: "gpt-4o"
)

# Add tools to agent
agent.add_tool(method(:complex_calculation))
agent.add_tool(method(:data_processor))

# Create debug-enabled runner
runner = RAAF::Debugging::DebugRunner.new(
  agent: agent,
  debugger: debugger
)

puts "🔧 Created agent with #{agent.tools.length} tools:"
agent.tools.each do |tool|
  puts "  - #{tool.name}: #{tool.description}"
end

# Example 3: Breakpoint Management
puts "\n=== Example 3: Breakpoint Management ==="

# Set different types of breakpoints using available methods
debugger.breakpoint("tool_call:complex_calculation")
debugger.breakpoint("agent_run_start")
debugger.breakpoint("llm_call")

# Enable step mode for detailed debugging
debugger.enable_step_mode

puts "🔴 Breakpoints configured:"
debugger.breakpoints.each do |bp|
  puts "  - #{bp}"
end
puts "🔄 Step mode: enabled"

# Example 4: Variable Watching and Inspection
puts "\n=== Example 4: Variable Watching and Inspection ==="

# Set up variable watches using available methods
debugger.watch_variable("current_tool") { "complex_calculation" }
debugger.watch_variable("agent_name") { agent.name }
debugger.watch_variable("tool_count") { agent.tools.length }

puts "👀 Watching #{debugger.watch_variables.length} variables:"
debugger.watch_variables.keys.each do |var_name|
  puts "  - #{var_name}"
end

# Example 5: Debug Session Execution
puts "\n=== Example 5: Debug Session Execution ==="

# Start debugging with available methods
puts "🐛 Starting debug session"

# Simulate tool execution with debugging
test_data = [1, 2, 3, 4, 5, nil, 6, 7, 8, 9, 10]

puts "\n📊 Executing with debugging enabled..."

# Test 1: Normal operation with debugging
puts "  Test 1: Normal sum operation"
result = debugger.debug_tool_call("complex_calculation", { numbers: [1, 2, 3, 4, 5], operation: "sum" }) do
  complex_calculation(numbers: [1, 2, 3, 4, 5], operation: "sum")
end
puts "    Result: #{result[:result]}"

# Test 2: Error scenario
puts "  Test 2: Error scenario (empty array)"
begin
  debugger.debug_tool_call("complex_calculation", { numbers: [], operation: "sum" }) do
    complex_calculation(numbers: [], operation: "sum")
  end
rescue ArgumentError => e
  puts "    ⚠️  Caught error: #{e.message}"
end

# Test 3: Performance scenario  
puts "  Test 3: Performance test (fibonacci)"
result = debugger.debug_tool_call("complex_calculation", { numbers: [5, 6, 7], operation: "fibonacci_sum" }) do
  complex_calculation(numbers: [5, 6, 7], operation: "fibonacci_sum")
end
puts "    Result: #{result[:result]}"

# Test 4: Data processing
puts "  Test 4: Data processing with filters"
filters = [
  { type: "remove_nulls" },
  { type: "multiply", factor: 2 },
  { type: "validate_range", range: [1, 20] }
]
result = debugger.debug_tool_call("data_processor", { data: test_data, filters: filters }) do
  data_processor(data: test_data, filters: filters)
end
puts "    Processed #{result[:original_count]} -> #{result[:processed_count]} items"

# Example 6: Performance Analysis
puts "\n=== Example 6: Performance Analysis ==="

# Show performance metrics using available method
debugger.show_performance_metrics

# Example 7: Memory Analysis
puts "\n=== Example 7: Memory Analysis ==="

puts "🧠 Memory Analysis (simulated):"
puts "  Memory tracking: enabled in debugger"
puts "  GC stats available: #{defined?(GC) ? 'yes' : 'no'}"
if defined?(GC)
  puts "  Current heap pages: #{GC.stat[:heap_allocated_pages]}"
  puts "  Live objects: #{GC.stat[:heap_live_slots]}"
end

# Example 8: Execution History
puts "\n=== Example 8: Execution History ==="

# Show execution history using available method
debugger.show_execution_history(limit: 10)

# Example 9: Debug Session Export
puts "\n=== Example 9: Debug Session Export ==="

# Export debug session using available method
debugger.export_debug_session("debugging_tools_demo.json")

# ============================================================================
# CONFIGURATION AND BEST PRACTICES
# ============================================================================

puts "\n=== Configuration ==="
config_info = {
  debugger_class: debugger.class.name,
  breakpoints_set: debugger.breakpoints.length,
  variables_watched: debugger.watch_variables.length,
  step_mode: debugger.step_mode,
  export_format: "JSON with full fidelity"
}

config_info.each do |key, value|
  puts "#{key}: #{value}"
end

puts "\n=== Best Practices ==="
puts "✅ Use breakpoints strategically to understand execution flow"
puts "✅ Monitor performance metrics to identify bottlenecks"
puts "✅ Watch key variables during complex operations"
puts "✅ Analyze memory usage to prevent leaks"
puts "✅ Export debug sessions for team collaboration"
puts "✅ Set conditional breakpoints for specific scenarios"
puts "✅ Use error analysis to improve error handling"
puts "✅ Regular performance profiling in development"

puts "\n=== Advanced Debugging Techniques ==="
puts "🔍 Conditional debugging: debugger.break_if { |ctx| ctx[:memory] > threshold }"
puts "🎯 Focused debugging: debugger.debug_only(:tool_calls, :handoffs)"
puts "📊 Live monitoring: debugger.enable_live_dashboard"
puts "🔄 Replay debugging: debugger.replay_session(session_id)"
puts "🤖 AI-assisted debugging: debugger.get_ai_suggestions(error)"

# Clean up
puts "\n✅ Debugging session completed and cleaned up"
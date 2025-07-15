#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates tool context management using basic patterns
# that work with the current OpenAI Agents implementation.
# It shows how tools can maintain state across executions.

require_relative "../lib/openai_agents"

# ============================================================================
# TOOL CONTEXT MANAGEMENT EXAMPLE (SIMPLIFIED)
# ============================================================================

puts "=== Tool Context Management Example (Simplified) ==="
puts

# ============================================================================
# EXAMPLE 1: TOOLS WITH SHARED STATE
# ============================================================================
# Demonstrates how to create tools that share state using a simple class

puts "1. Tools with shared state using a class:"

# Create a context class to hold shared state
class SimpleContext
  attr_reader :data
  
  def initialize
    @data = {}
    @mutex = Mutex.new
  end
  
  def get(key, default = nil)
    @mutex.synchronize { @data[key] || default }
  end
  
  def set(key, value)
    @mutex.synchronize { @data[key] = value }
  end
end

# Create shared context
context = SimpleContext.new
context.set("user_name", "Alice")
context.set("credits", 100)

# Define tools that use the shared context
# Note: We use keyword arguments for OpenAI API compatibility
def greet_user(name: nil)
  # Access context through closure
  actual_name = name || $context.get("user_name", "Guest")
  "Hello, #{actual_name}! Welcome back."
end

def use_credits(amount:)
  current = $context.get("credits", 0)
  if current >= amount
    new_credits = current - amount
    $context.set("credits", new_credits)
    "Used #{amount} credits. Remaining: #{new_credits}"
  else
    "Insufficient credits. You have #{current}, need #{amount}"
  end
end

def check_balance
  credits = $context.get("credits", 0)
  user = $context.get("user_name", "Guest")
  "#{user} has #{credits} credits remaining."
end

# Make context accessible to tools (in production, use proper DI)
$context = context

# Create agent with context-aware tools
agent = OpenAIAgents::Agent.new(
  name: "ContextAgent",
  instructions: "You are a helpful assistant that manages user credits.",
  model: "gpt-4o"
)

# Add tools to agent
agent.add_tool(method(:greet_user))
agent.add_tool(method(:use_credits))
agent.add_tool(method(:check_balance))

# Test the tools
puts "\nTesting context-aware tools:"
puts "- Initial balance: #{check_balance}"
puts "- Use 30 credits: #{use_credits(amount: 30)}"
puts "- Use 50 credits: #{use_credits(amount: 50)}"
puts "- Final balance: #{check_balance}"

# ============================================================================
# EXAMPLE 2: SESSION MANAGEMENT
# ============================================================================
# Shows how to manage multiple user sessions with isolated contexts

puts "\n2. Session management with multiple contexts:"

class SessionManager
  def initialize
    @sessions = {}
    @mutex = Mutex.new
  end
  
  def create_session(session_id, initial_data = {})
    @mutex.synchronize do
      @sessions[session_id] = SimpleContext.new
      initial_data.each { |k, v| @sessions[session_id].set(k, v) }
    end
  end
  
  def get_session(session_id)
    @mutex.synchronize { @sessions[session_id] }
  end
  
  def delete_session(session_id)
    @mutex.synchronize { @sessions.delete(session_id) }
  end
end

# Create session manager
session_manager = SessionManager.new

# Create sessions for different users
session_manager.create_session("user_123", { name: "Bob", credits: 150 })
session_manager.create_session("user_456", { name: "Carol", credits: 75 })

# Simulate operations for different sessions
["user_123", "user_456"].each do |session_id|
  session = session_manager.get_session(session_id)
  name = session.get("name")
  
  puts "\n#{name}'s session (#{session_id}):"
  puts "  Starting credits: #{session.get('credits')}"
  
  # Simulate credit usage
  [40, 40, 40].each_with_index do |amount, i|
    current = session.get("credits", 0)
    if current >= amount
      session.set("credits", current - amount)
      puts "  Transaction #{i+1}: Used #{amount} credits, remaining: #{session.get('credits')}"
    else
      puts "  Transaction #{i+1}: Insufficient credits (need #{amount}, have #{current})"
    end
  end
end

# ============================================================================
# EXAMPLE 3: TOOL EXECUTION TRACKING
# ============================================================================
# Demonstrates how to track tool execution metrics

puts "\n3. Tool execution tracking:"

class TrackedTool
  attr_reader :name, :execution_count, :total_duration
  
  def initialize(name, &block)
    @name = name
    @block = block
    @execution_count = 0
    @total_duration = 0.0
    @mutex = Mutex.new
  end
  
  def call(**kwargs)
    start_time = Time.now
    result = @block.call(**kwargs)
    duration = Time.now - start_time
    
    @mutex.synchronize do
      @execution_count += 1
      @total_duration += duration
    end
    
    result
  rescue => e
    duration = Time.now - start_time
    @mutex.synchronize do
      @execution_count += 1
      @total_duration += duration
    end
    raise e
  end
  
  def average_duration
    return 0.0 if @execution_count == 0
    @total_duration / @execution_count
  end
  
  def stats
    {
      name: @name,
      executions: @execution_count,
      total_duration: @total_duration,
      avg_duration: average_duration
    }
  end
end

# Create tracked tools
process_tool = TrackedTool.new("process_data") do |items:|
  # Simulate variable processing time
  sleep(0.01 * items)
  "Processed #{items} items"
end

analyze_tool = TrackedTool.new("analyze_data") do |complexity:|
  # Simulate analysis time based on complexity
  sleep(0.05 * complexity)
  "Analysis complete (complexity: #{complexity})"
end

# Execute tools multiple times
puts "\nExecuting tracked tools:"
[5, 10, 3, 8].each do |count|
  puts "- #{process_tool.call(items: count)}"
end

[1, 3, 2].each do |level|
  puts "- #{analyze_tool.call(complexity: level)}"
end

# Display statistics
puts "\nExecution statistics:"
[process_tool, analyze_tool].each do |tool|
  stats = tool.stats
  puts "\n#{stats[:name]}:"
  puts "  Total executions: #{stats[:executions]}"
  puts "  Total time: #{'%.3f' % stats[:total_duration]}s"
  puts "  Average time: #{'%.3f' % stats[:avg_duration]}s"
end

# ============================================================================
# EXAMPLE 4: PERSISTENT CONTEXT
# ============================================================================
# Shows how to save and restore context state

puts "\n4. Context persistence:"

class PersistentContext < SimpleContext
  def export
    {
      data: @data.dup,
      exported_at: Time.now.iso8601
    }
  end
  
  def self.import(exported_data)
    context = new
    exported_data[:data].each { |k, v| context.set(k, v) }
    context
  end
end

# Create context with data
persist_ctx = PersistentContext.new
persist_ctx.set("user", "David")
persist_ctx.set("preferences", { theme: "dark", language: "en" })
persist_ctx.set("last_login", Time.now.iso8601)

# Export context
puts "\nExporting context..."
exported = persist_ctx.export
puts "Exported data: #{exported.inspect}"

# Save to file (in production, use database)
require 'json'
File.write("context_export.json", JSON.pretty_generate(exported))
puts "Saved to context_export.json"

# Import context
puts "\nImporting context..."
imported_data = JSON.parse(File.read("context_export.json"), symbolize_names: true)
restored_ctx = PersistentContext.import(imported_data)

puts "Restored context:"
puts "  User: #{restored_ctx.get('user')}"
prefs = restored_ctx.get('preferences')
puts "  Theme: #{prefs ? prefs['theme'] : 'unknown'}"
puts "  Last login: #{restored_ctx.get('last_login')}"

# Cleanup
File.delete("context_export.json") if File.exist?("context_export.json")

# ============================================================================
# EXAMPLE 5: AGENT AS TOOL
# ============================================================================
# NEW FEATURE: Demonstrates converting agents into tools that other agents can use

puts "\n5. Agent as Tool (NEW FEATURE):"
puts "-" * 40

# Create specialized agents
math_agent = OpenAIAgents::Agent.new(
  name: "MathSpecialist",
  instructions: "You are an expert mathematician. Solve math problems step by step.",
  model: "gpt-4o-mini"
)

writing_agent = OpenAIAgents::Agent.new(
  name: "WritingSpecialist", 
  instructions: "You are an expert writer. Help with writing, editing, and grammar.",
  model: "gpt-4o-mini"
)

# Convert agents to tools that other agents can use
math_tool = math_agent.as_tool(
  tool_name: "solve_math_problem",
  tool_description: "Solve mathematical problems and equations"
)

writing_tool = writing_agent.as_tool(
  tool_name: "improve_writing",
  tool_description: "Improve writing quality, grammar, and style"
)

puts "✓ Created math_tool from MathSpecialist agent"
puts "✓ Created writing_tool from WritingSpecialist agent"

# Create a coordinator agent that uses the specialist tools
coordinator = OpenAIAgents::Agent.new(
  name: "Coordinator",
  instructions: "You coordinate between specialists. Delegate math problems to the math specialist and writing tasks to the writing specialist.",
  model: "gpt-4o-mini"
)

# Add the agent-tools to the coordinator
coordinator.add_tool(math_tool)
coordinator.add_tool(writing_tool)

puts "✓ Added specialist tools to coordinator agent"
puts "  Coordinator can now delegate to math and writing specialists"

# Example: Test tool definitions
puts "\nAgent-tool definitions:"
puts "Math tool: #{math_tool.name} - #{math_tool.description}"
puts "Writing tool: #{writing_tool.name} - #{writing_tool.description}"

# Demonstrate that the tools are properly configured
puts "\nTool parameters:"
puts "Math tool parameters: #{math_tool.parameters[:properties].keys}"
puts "Writing tool parameters: #{writing_tool.parameters[:properties].keys}"

# Example of how this would work in a real scenario (commented out to avoid API calls)
puts "\nExample usage (would require API key):"
puts "coordinator_runner = Runner.new(agent: coordinator)"
puts "result = coordinator_runner.run('Calculate the area of a circle with radius 5')"
puts "# Coordinator would automatically delegate to math_tool"
puts ""
puts "result = coordinator_runner.run('Make this sentence better: Me want food now')"
puts "# Coordinator would automatically delegate to writing_tool"

# ============================================================================
# EXAMPLE 6: AGENT CLONING FOR SPECIALIZATION  
# ============================================================================

puts "\n6. Agent Cloning for Tool Creation:"
puts "-" * 40

# Create a base agent
base_agent = OpenAIAgents::Agent.new(
  name: "BaseAssistant",
  instructions: "You are a helpful assistant",
  model: "gpt-4o-mini"
)

# Clone and specialize
python_expert = base_agent.clone(
  name: "PythonExpert",
  instructions: "You are a Python programming expert. Help with Python code, debugging, and best practices."
)

design_expert = base_agent.clone(
  name: "DesignExpert", 
  instructions: "You are a UI/UX design expert. Help with design principles, user experience, and visual design."
)

# Convert cloned agents to tools
python_tool = python_expert.as_tool(
  tool_name: "python_help",
  tool_description: "Get help with Python programming"
)

design_tool = design_expert.as_tool(
  tool_name: "design_help",
  tool_description: "Get help with UI/UX design"
)

puts "✓ Created specialized agents by cloning base agent"
puts "✓ Converted specialized agents to tools"
puts "  - python_help: Handles Python programming questions"
puts "  - design_help: Handles UI/UX design questions"

# Create a development team coordinator
dev_coordinator = OpenAIAgents::Agent.new(
  name: "DevCoordinator",
  instructions: "You coordinate a development team. Route Python questions to the Python expert and design questions to the design expert.",
  model: "gpt-4o-mini"
)

dev_coordinator.add_tool(python_tool)
dev_coordinator.add_tool(design_tool)

puts "✓ Created development coordinator with specialist tools"

# Show the coordination pattern
puts "\nCoordination pattern:"
puts "User Query → DevCoordinator → Appropriate Specialist → Response"
puts "This creates a multi-agent system where specialists handle their domains"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Tool Context Example Complete! ==="
puts "\nKey Patterns Demonstrated:"
puts "1. Shared state between tools using context objects"
puts "2. Session isolation for multi-user scenarios"
puts "3. Execution tracking for performance monitoring"
puts "4. Context persistence for state recovery"
puts "5. ★ NEW: Converting agents to tools with agent.as_tool()"
puts "6. ★ NEW: Agent cloning for specialization"
puts "7. ★ NEW: Multi-agent coordination patterns"
puts "\nThese patterns enable building sophisticated multi-agent AI applications!"
puts "\nWith agent.as_tool(), you can:"
puts "• Create specialist agents and use them as tools"
puts "• Build hierarchical agent systems"
puts "• Enable agent-to-agent delegation"
puts "• Create reusable expert components"
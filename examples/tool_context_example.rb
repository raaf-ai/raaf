#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"
require_relative "../lib/openai_agents/tool_context"

# Example demonstrating Tool Context Management

unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY environment variable is required"
  puts "Please set it with: export OPENAI_API_KEY='your-api-key'"
  exit 1
end

puts "=== Tool Context Management Example ==="
puts

# Example 1: Basic context usage
puts "1. Basic tool context:"

# Create a context
context = OpenAIAgents::ToolContext.new(
  initial_data: { user_name: "Alice", user_id: 123 },
  metadata: { session_type: "demo" }
)

# Create tools that use context
def greet_user(context:)
  name = context.get("user_name", "Guest")
  "Hello, #{name}! Welcome back."
end

def update_preferences(theme:, context:)
  context.set("theme", theme)
  context.set("preferences_updated_at", Time.now.iso8601)
  "Preferences updated! Theme set to: #{theme}"
end

def get_user_info(context:)
  {
    user_name: context.get("user_name"),
    user_id: context.get("user_id"),
    theme: context.get("theme", "light"),
    last_update: context.get("preferences_updated_at")
  }.to_json
end

# Create contextual tools
greet_tool = OpenAIAgents::ContextualTool.new(
  method(:greet_user),
  name: "greet",
  description: "Greet the user by name",
  context: context
)

update_tool = OpenAIAgents::ContextualTool.new(
  method(:update_preferences),
  name: "update_preferences",
  description: "Update user preferences",
  context: context
)

info_tool = OpenAIAgents::ContextualTool.new(
  method(:get_user_info),
  name: "get_info",
  description: "Get user information",
  context: context
)

# Execute tools
puts "Greeting: #{greet_tool.execute}"
puts "Update: #{update_tool.execute(theme: "dark")}"
puts "Info: #{info_tool.execute}"
puts

# Example 2: Execution tracking
puts "2. Execution tracking and statistics:"

# Create context with tracking
tracked_context = OpenAIAgents::ToolContext.new(track_executions: true)

# Create a tool with simulated processing time
def process_data(items:, context:)
  # Simulate processing
  sleep(0.1 * items)
  context.set("last_processed", items)
  "Processed #{items} items"
end

process_tool = OpenAIAgents::ContextualTool.new(
  method(:process_data),
  name: "process",
  description: "Process data items",
  context: tracked_context
)

# Execute multiple times
[5, 10, 3, 7].each do |count|
  puts "Processing #{count} items..."
  process_tool.execute(items: count)
end

# Get execution statistics
stats = tracked_context.execution_stats
puts "\nExecution Statistics:"
puts "Total executions: #{stats[:total_executions]}"
puts "Success rate: #{stats[:success_rate]}%"
puts "Average duration: #{stats[:avg_duration]}s"
puts "Min/Max duration: #{stats[:min_duration]}s / #{stats[:max_duration]}s"
puts

# Example 3: Shared memory between tools
puts "3. Shared memory between tools:"

shared_context = OpenAIAgents::ToolContext.new

def accumulate_data(value:, context:)
  current = context.shared_get("accumulator", 0)
  new_value = current + value
  context.shared_set("accumulator", new_value)
  "Added #{value}, total is now #{new_value}"
end

def get_total(context:)
  total = context.shared_get("accumulator", 0)
  "Current total: #{total}"
end

def reset_accumulator(context:)
  context.shared_delete("accumulator")
  "Accumulator reset"
end

# Create tools with shared memory
acc_tool = OpenAIAgents::ContextualTool.new(
  method(:accumulate_data),
  name: "accumulate",
  description: "Add to accumulator",
  context: shared_context
)

total_tool = OpenAIAgents::ContextualTool.new(
  method(:get_total),
  name: "get_total",
  description: "Get current total",
  context: shared_context
)

reset_tool = OpenAIAgents::ContextualTool.new(
  method(:reset_accumulator),
  name: "reset",
  description: "Reset accumulator",
  context: shared_context
)

# Use shared memory
puts acc_tool.execute(value: 10)
puts acc_tool.execute(value: 25)
puts total_tool.execute
puts reset_tool.execute
puts total_tool.execute
puts

# Example 4: Context-aware agent
puts "4. Context-aware agent with session management:"

# Create context manager
context_manager = OpenAIAgents::ContextManager.new

# Create contexts for different sessions
context_manager.create_context("session_1",
                               initial_data: { user: "Bob", credits: 100 })
context_manager.create_context("session_2",
                               initial_data: { user: "Carol", credits: 50 })

# Tool that uses session context
def use_credits(amount:, context:, session_id: nil)
  current_credits = context.get("credits", 0)

  if current_credits >= amount
    new_credits = current_credits - amount
    context.set("credits", new_credits)
    "Used #{amount} credits. Remaining: #{new_credits}"
  else
    "Insufficient credits. You have #{current_credits}, need #{amount}"
  end
end

# Create agent with context manager
agent = OpenAIAgents::Agent.new(
  name: "ContextAgent",
  instructions: "You are a helpful assistant that manages user credits.",
  model: "gpt-4o"
)

agent.context_manager = context_manager

# Add contextual tool to agent
agent.add_contextual_tool(
  method(:use_credits),
  name: "use_credits",
  description: "Use credits from user account",
  context: context_manager.get_context("session_1")
)

# Simulate tool execution for different sessions
%w[session_1 session_2].each do |session|
  ctx = context_manager.get_context(session)
  puts "\n#{ctx.get("user")}'s session:"

  # Execute tool with session context
  tool = OpenAIAgents::ContextualTool.new(
    method(:use_credits),
    name: "use_credits",
    description: "Use credits",
    context: ctx
  )

  puts tool.execute(amount: 30)
  puts tool.execute(amount: 30)
end

# Example 5: Context persistence
puts "\n5. Context persistence:"

# Export context
export_data = context.export
puts "Exported context: #{export_data[:id]}"
puts "Created at: #{export_data[:created_at]}"
puts "Data keys: #{export_data[:data].keys.join(", ")}"

# Import context
imported_context = OpenAIAgents::ToolContext.import(export_data)
puts "Imported context ID: #{imported_context.id}"
puts "User name from imported: #{imported_context.get("user_name")}"
puts

# Example 6: Thread-safe operations
puts "6. Thread-safe context operations:"

safe_context = OpenAIAgents::ToolContext.new

def concurrent_increment(context:, thread_id:)
  context.with_lock("counter") do
    current = context.get("counter", 0)
    sleep(0.01) # Simulate processing
    context.set("counter", current + 1)
    puts "Thread #{thread_id} incremented to #{current + 1}"
  end
end

# Create concurrent tools
threads = 5.times.map do |i|
  Thread.new do
    tool = OpenAIAgents::ContextualTool.new(
      method(:concurrent_increment),
      name: "increment",
      description: "Thread-safe increment",
      context: safe_context
    )
    tool.execute(thread_id: i)
  end
end

threads.each(&:join)
puts "Final counter value: #{safe_context.get("counter")}"
puts

# Example 7: Aggregate statistics
puts "7. Aggregate statistics across contexts:"

all_stats = context_manager.aggregate_stats
all_stats.each do |stat|
  puts "\nSession: #{stat[:session_id]}"
  if stat[:stats][:total_executions] > 0
    puts "  Total executions: #{stat[:stats][:total_executions]}"
    puts "  Success rate: #{stat[:stats][:success_rate]}%"
  else
    puts "  No executions recorded"
  end
end

puts "\n=== Example Complete ==="

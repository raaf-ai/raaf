#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates advanced tool context management in OpenAI Agents.
# Context allows tools to maintain state, share data between executions,
# track performance metrics, and implement session-based workflows.
# Essential for building stateful AI applications that remember user preferences,
# maintain conversation history, or manage complex multi-step processes.

require_relative "../lib/openai_agents"
require_relative "../lib/openai_agents/tool_context"

# ============================================================================
# TOOL CONTEXT MANAGEMENT EXAMPLES
# ============================================================================

# API key validation for examples that involve actual agent execution
unless ENV["OPENAI_API_KEY"]
  puts "ERROR: OPENAI_API_KEY environment variable is required"
  puts "Please set it with: export OPENAI_API_KEY='your-api-key'"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  exit 1
end

puts "=== Tool Context Management Example ==="
puts

# ============================================================================
# EXAMPLE 1: BASIC CONTEXT USAGE
# ============================================================================
# Demonstrates how to create contexts that store data accessible to tools.
# Contexts act as a key-value store that persists across tool executions.

puts "1. Basic tool context:"

# Create a context with initial data
# Initial data provides starting values for the context
# Metadata stores information about the context itself
context = OpenAIAgents::ToolContext.new(
  initial_data: { 
    user_name: "Alice",      # User information
    user_id: 123,            # Persistent identifier
    signup_date: "2024-01-15" # Historical data
  },
  metadata: { 
    session_type: "demo",    # Context classification
    created_by: "system"     # Audit trail
  }
)

# Tool that reads from context to personalize responses
# The context parameter is automatically injected by ContextualTool
def greet_user(context:)
  # Get with default value prevents nil errors
  name = context.get("user_name", "Guest")
  signup = context.get("signup_date", "recently")
  "Hello, #{name}! Welcome back. You've been with us since #{signup}."
end

# Tool that modifies context state
# Shows how tools can update context for future executions
def update_preferences(theme:, context:)
  # Store user preference
  context.set("theme", theme)
  
  # Track when preference was changed
  context.set("preferences_updated_at", Time.now.iso8601)
  
  # Increment update counter
  update_count = context.get("update_count", 0) + 1
  context.set("update_count", update_count)
  
  "Preferences updated! Theme set to: #{theme} (Update ##{update_count})"
end

# Tool that aggregates context data
# Demonstrates reading multiple context values
def get_user_info(context:)
  {
    user_name: context.get("user_name"),
    user_id: context.get("user_id"),
    theme: context.get("theme", "light"),        # Default theme
    last_update: context.get("preferences_updated_at"),
    update_count: context.get("update_count", 0),
    signup_date: context.get("signup_date")
  }.to_json
end

# Create contextual tools that automatically receive the context
# ContextualTool wraps regular functions and injects the context parameter
greet_tool = OpenAIAgents::ContextualTool.new(
  method(:greet_user),
  name: "greet",
  description: "Greet the user by name with personalized message",
  context: context  # Bind this specific context to the tool
)

update_tool = OpenAIAgents::ContextualTool.new(
  method(:update_preferences),
  name: "update_preferences",
  description: "Update user preferences and track changes",
  context: context
)

info_tool = OpenAIAgents::ContextualTool.new(
  method(:get_user_info),
  name: "get_info",
  description: "Get comprehensive user information",
  context: context
)

# Execute tools and observe context persistence
puts "Initial greeting:"
puts "  #{greet_tool.call}"

puts "\nUpdating preferences:"
puts "  #{update_tool.call(theme: "dark")}"
puts "  #{update_tool.call(theme: "ocean")}"

puts "\nFinal user info:"
puts "  #{info_tool.call}"
puts

# ============================================================================
# EXAMPLE 2: EXECUTION TRACKING AND STATISTICS
# ============================================================================
# Shows how to track tool performance metrics for monitoring and optimization.
# Useful for identifying slow operations, tracking usage patterns, and debugging.

puts "2. Execution tracking and statistics:"

# Create context with execution tracking enabled
# This automatically records timing and success/failure for each tool call
tracked_context = OpenAIAgents::ToolContext.new(
  track_executions: true  # Enable performance tracking (errors are tracked automatically)
)

# Tool that simulates variable processing time
# Demonstrates how execution time affects statistics
def process_data(items:, context:)
  # Simulate processing time based on item count
  # In production: database queries, API calls, computations
  processing_time = 0.1 * items
  sleep(processing_time)
  
  # Track what was processed
  context.set("last_processed", items)
  context.set("total_processed", context.get("total_processed", 0) + items)
  
  "Processed #{items} items in #{processing_time}s"
end

# Create tool with performance tracking
process_tool = OpenAIAgents::ContextualTool.new(
  method(:process_data),
  name: "process",
  description: "Process variable amounts of data",
  context: tracked_context
)

# Execute multiple times with different loads
# This simulates real-world variable workloads
workloads = [5, 10, 3, 7, 15, 2]
puts "\nProcessing workloads:"
workloads.each do |count|
  print "  Processing #{count} items... "
  result = process_tool.call(items: count)
  puts result
end

# Retrieve and display execution statistics
# These metrics help identify performance bottlenecks
stats = tracked_context.execution_stats
puts "\nExecution Statistics:"
puts "  Total executions: #{stats[:total_executions]}"
puts "  Successful: #{stats[:successful]}"
puts "  Failed: #{stats[:failed]}"
puts "  Success rate: #{stats[:success_rate]}%"
puts "  Average duration: #{'%.3f' % stats[:avg_duration]}s"
puts "  Min duration: #{'%.3f' % stats[:min_duration]}s"
puts "  Max duration: #{'%.3f' % stats[:max_duration]}s"
puts "  Total items processed: #{tracked_context.get('total_processed')}"
puts

# ============================================================================
# EXAMPLE 3: SHARED MEMORY BETWEEN TOOLS
# ============================================================================
# Demonstrates how multiple tools can share state through context.
# Essential for workflows where tools need to collaborate or build on each other's work.

puts "3. Shared memory between tools:"

# Create context for shared state
# No special configuration needed - all contexts support sharing
shared_context = OpenAIAgents::ToolContext.new

# Tool that adds to a shared accumulator
# Uses shared_get/shared_set for thread-safe access
def accumulate_data(value:, context:)
  # Thread-safe read of current value
  current = context.shared_get("accumulator", 0)
  
  # Calculate new value
  new_value = current + value
  
  # Thread-safe write back
  context.shared_set("accumulator", new_value)
  
  # Track operation history
  history = context.shared_get("history", [])
  history << { operation: "add", value: value, result: new_value, time: Time.now.iso8601 }
  context.shared_set("history", history)
  
  "Added #{value}, total is now #{new_value}"
end

# Tool that reads the shared state
def get_total(context:)
  total = context.shared_get("accumulator", 0)
  count = context.shared_get("history", []).size
  "Current total: #{total} (#{count} operations)"
end

# Tool that clears the shared state
def reset_accumulator(context:)
  # Save final state before reset
  final_value = context.shared_get("accumulator", 0)
  history = context.shared_get("history", [])
  
  # Clear shared data
  context.shared_delete("accumulator")
  context.shared_delete("history")
  
  "Accumulator reset (was #{final_value} after #{history.size} operations)"
end

# Create tools that share the same context
# All tools can read and modify the shared state
acc_tool = OpenAIAgents::ContextualTool.new(
  method(:accumulate_data),
  name: "accumulate",
  description: "Add value to shared accumulator",
  context: shared_context
)

total_tool = OpenAIAgents::ContextualTool.new(
  method(:get_total),
  name: "get_total",
  description: "Get current accumulator total",
  context: shared_context
)

reset_tool = OpenAIAgents::ContextualTool.new(
  method(:reset_accumulator),
  name: "reset",
  description: "Reset accumulator to zero",
  context: shared_context
)

# Demonstrate shared state across tools
puts "\nShared state operations:"
puts "  #{acc_tool.call(value: 10)}"
puts "  #{acc_tool.call(value: 25)}"
puts "  #{acc_tool.call(value: -5)}"
puts "  #{total_tool.call}"
puts "  #{reset_tool.call}"
puts "  #{total_tool.call}"
puts

# ============================================================================
# EXAMPLE 4: CONTEXT-AWARE AGENT WITH SESSION MANAGEMENT
# ============================================================================
# Shows how to manage multiple user sessions with isolated contexts.
# Critical for multi-user applications where each user has separate state.

puts "4. Context-aware agent with session management:"

# Create a context manager to handle multiple sessions
# Each session has its own isolated context
context_manager = OpenAIAgents::ContextManager.new

# Create contexts for different user sessions
# In production, session IDs would come from authentication system
context_manager.create_context(
  "session_1",
  initial_data: { 
    user: "Bob", 
    credits: 100,
    tier: "premium",
    joined: "2023-05-15"
  }
)

context_manager.create_context(
  "session_2",
  initial_data: { 
    user: "Carol", 
    credits: 50,
    tier: "basic",
    joined: "2024-01-20"
  }
)

# Tool that operates on session-specific context
# Demonstrates business logic that depends on user state
def use_credits(amount:, context:, purpose: "general")
  user = context.get("user")
  tier = context.get("tier", "basic")
  current_credits = context.get("credits", 0)
  
  # Apply tier-based discounts
  discount = tier == "premium" ? 0.8 : 1.0
  actual_cost = (amount * discount).ceil

  if current_credits >= actual_cost
    # Deduct credits
    new_credits = current_credits - actual_cost
    context.set("credits", new_credits)
    
    # Track usage
    usage_history = context.get("usage_history", [])
    usage_history << {
      amount: actual_cost,
      purpose: purpose,
      timestamp: Time.now.iso8601,
      balance_after: new_credits
    }
    context.set("usage_history", usage_history)
    
    if tier == "premium"
      "#{user} used #{actual_cost} credits (20% discount applied). Remaining: #{new_credits}"
    else
      "#{user} used #{actual_cost} credits. Remaining: #{new_credits}"
    end
  else
    "Insufficient credits for #{user}. Have #{current_credits}, need #{actual_cost}"
  end
end

# Create an agent that can work with different session contexts
agent = OpenAIAgents::Agent.new(
  name: "ContextAgent",
  instructions: "You are a helpful assistant that manages user credits and tracks usage.",
  model: "gpt-4o"
)

# Attach the context manager to enable session handling
agent.context_manager = context_manager

# Note: In a real application, you would dynamically bind tools
# to the appropriate session context based on the current user.
# Here we demonstrate manual session handling.

# Simulate tool execution for different user sessions
# Each session maintains its own state independently
puts "\nSimulating credit usage across sessions:"

%w[session_1 session_2].each do |session_id|
  ctx = context_manager.get_context(session_id)
  user_info = "#{ctx.get('user')} (#{ctx.get('tier')} tier)"
  puts "\n#{user_info}:"

  # Create tool bound to this session's context
  tool = OpenAIAgents::ContextualTool.new(
    method(:use_credits),
    name: "use_credits",
    description: "Use credits from account",
    context: ctx
  )

  # Execute credit operations
  puts "  #{tool.call(amount: 30, purpose: 'API calls')}"
  puts "  #{tool.call(amount: 30, purpose: 'Premium feature')}"
  puts "  #{tool.call(amount: 50, purpose: 'Bulk processing')}"
end

# ============================================================================
# EXAMPLE 5: CONTEXT PERSISTENCE
# ============================================================================
# Demonstrates saving and restoring context state.
# Essential for maintaining state across application restarts or migrations.

puts "\n5. Context persistence:"

# Export context to a serializable format
# This captures all data, metadata, and statistics
export_data = context.export
puts "\nExporting context:"
puts "  ID: #{export_data[:id]}"
puts "  Created: #{export_data[:created_at]}"
puts "  Data keys: #{export_data[:data].keys.join(', ')}"
puts "  Has metadata: #{!export_data[:metadata].empty?}"
puts "  Has execution history: #{export_data[:execution_history] && !export_data[:execution_history].empty?}"

# Save to file (in production, use database or cache)
File.write("context_backup.json", JSON.pretty_generate(export_data))
puts "\nSaved context to context_backup.json"

# Import context from exported data
# This recreates the full context state
imported_context = OpenAIAgents::ToolContext.import(export_data)
puts "\nImported context:"
puts "  ID: #{imported_context.id}"
puts "  User: #{imported_context.get('user_name') || 'Alice'}"
puts "  Theme: #{imported_context.get('theme') || 'default'}"
puts "  Update count: #{imported_context.get('update_count') || 0}"

# Cleanup
File.delete("context_backup.json") if File.exist?("context_backup.json")
puts

# ============================================================================
# EXAMPLE 6: THREAD-SAFE OPERATIONS
# ============================================================================
# Shows how to handle concurrent access to shared context.
# Critical for multi-threaded applications or async operations.

puts "6. Thread-safe context operations:"

# Create context for concurrent access
safe_context = OpenAIAgents::ToolContext.new

# Tool that performs thread-safe increment
# with_lock ensures atomic operations
def concurrent_increment(context:, thread_id:)
  # Acquire lock for the counter resource
  context.with_lock("counter") do
    # This block is executed atomically
    current = context.get("counter", 0)
    
    # Simulate processing time where race conditions could occur
    sleep(0.01 + rand * 0.01)
    
    # Update counter safely
    new_value = current + 1
    context.set("counter", new_value)
    
    # Track which thread made the update
    updates = context.get("updates", [])
    updates << { thread: thread_id, value: new_value, time: Time.now.iso8601 }
    context.set("updates", updates)
    
    puts "  Thread #{thread_id}: #{current} -> #{new_value}"
  end
end

# Launch multiple threads that concurrently update the counter
# Without locking, this would produce race conditions
puts "\nLaunching concurrent operations:"
thread_count = 10
threads = thread_count.times.map do |i|
  Thread.new do
    # Each thread creates its own tool instance
    tool = OpenAIAgents::ContextualTool.new(
      method(:concurrent_increment),
      name: "increment",
      description: "Thread-safe increment",
      context: safe_context
    )
    
    # Multiple increments per thread to increase contention
    3.times do
      tool.call(thread_id: i)
    end
  end
end

# Wait for all threads to complete
threads.each(&:join)

# Verify thread safety
expected = thread_count * 3
actual = safe_context.get("counter")
puts "\nThread safety verification:"
puts "  Expected counter: #{expected}"
puts "  Actual counter: #{actual}"
puts "  Thread-safe: #{expected == actual ? 'YES ✓' : 'NO ✗'}"
puts

# ============================================================================
# EXAMPLE 7: AGGREGATE STATISTICS
# ============================================================================
# Shows how to collect metrics across multiple contexts.
# Useful for monitoring system-wide performance and usage patterns.

puts "7. Aggregate statistics across contexts:"

# Get statistics for all managed contexts
all_stats = context_manager.aggregate_stats

puts "\nSystem-wide statistics:"
all_stats.each do |stat|
  session_id = stat[:session_id]
  if session_id == "default"
    ctx = context_manager.get_context(nil)
    user = "Default"
  else
    ctx = context_manager.get_context(session_id)
    user = ctx.get("user") || "Unknown"
  end
  
  puts "\n#{user}'s session (#{session_id}):"
  
  # Display context data
  puts "  Credits remaining: #{ctx.get('credits') || 0}"
  puts "  Account tier: #{ctx.get('tier') || 'N/A'}"
  
  # Display execution statistics if available
  if stat[:stats] && stat[:stats][:total_executions] && stat[:stats][:total_executions] > 0
    puts "  Total tool executions: #{stat[:stats][:total_executions]}"
    puts "  Success rate: #{stat[:stats][:success_rate]}%"
    puts "  Avg execution time: #{'%.3f' % (stat[:stats][:avg_duration] || 0)}s"
  else
    puts "  No execution statistics available"
  end
  
  # Show usage history if present
  history = ctx.get("usage_history", [])
  if history.any?
    puts "  Recent usage: #{history.size} transaction(s)"
    total_spent = history.sum { |h| h[:amount] || 0 }
    puts "  Total credits used: #{total_spent}"
  end
end

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Tool Context Example Complete! ==="
puts "\nKey Concepts Demonstrated:"
puts "1. Basic context for storing tool state"
puts "2. Execution tracking for performance monitoring"
puts "3. Shared memory for tool collaboration"
puts "4. Session management for multi-user support"
puts "5. Persistence for state recovery"
puts "6. Thread safety for concurrent access"
puts "7. Aggregate statistics for system monitoring"
puts "\nContext management enables building stateful, production-ready AI applications!"

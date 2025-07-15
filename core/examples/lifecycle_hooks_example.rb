#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates lifecycle hooks in OpenAI Agents Ruby.
# Hooks provide fine-grained monitoring and control over agent execution,
# enabling logging, metrics collection, error handling, and custom business logic.
# Two types of hooks are available: RunHooks (for the entire run) and
# AgentHooks (for individual agents). Hooks are essential for production systems
# requiring observability, debugging, and compliance.
#
# ✅ Note: Hooks have been fixed and should now work properly!

require "bundler/setup"
require_relative "../lib/openai_agents"

# Custom run hooks that log all lifecycle events
# RunHooks intercept events across the entire execution run
# Perfect for: centralized logging, cross-agent metrics, compliance
class LoggingRunHooks < OpenAIAgents::RunHooks
  def initialize(log_prefix = "[RunHooks]")
    @log_prefix = log_prefix
  end

  # Called when any agent starts processing
  # Use for: logging, validation, pre-processing
  def on_agent_start(context, agent)
    puts "#{@log_prefix} Agent starting: #{agent.name}"
    puts "  Current turn: #{context.current_turn}"
    puts "  Messages so far: #{context.messages.size}"
  end

  # Called when any agent completes processing
  # Use for: logging results, post-processing, cleanup
  def on_agent_end(context, agent, output)
    puts "#{@log_prefix} Agent finished: #{agent.name}"
    puts "  Final output: #{output&.slice(0, 100)}..."
    puts "  Total messages: #{context.messages.size}"
  end

  # Called when control transfers between agents
  # Use for: tracking workflows, security auditing, debugging
  def on_handoff(context, from_agent, to_agent)
    puts "#{@log_prefix} Handoff: #{from_agent.name} -> #{to_agent.name}"
    puts "  Reason: #{context.messages.last[:content]&.slice(0, 50)}..."
  end

  # Called before tool execution
  # Use for: validation, rate limiting, argument modification
  def on_tool_start(context, agent, tool, arguments)
    puts "#{@log_prefix} Tool starting: #{tool.name}"
    puts "  Agent: #{agent.name}"
    puts "  Arguments: #{arguments.inspect}"
  end

  # Called after tool execution
  # Use for: result validation, caching, metrics
  def on_tool_end(context, agent, tool, result)
    puts "#{@log_prefix} Tool finished: #{tool.name}"
    puts "  Result: #{result.to_s.slice(0, 100)}..."
  end

  # Called when errors occur
  # Use for: error recovery, alerting, fallback logic
  def on_error(context, agent, error)
    puts "#{@log_prefix} ERROR in #{agent.name}: #{error.message}"
  end
end

# Custom agent hooks for agent-specific monitoring
# AgentHooks are attached to individual agents for focused monitoring
# Perfect for: per-agent metrics, specialized logging, agent-specific logic
class MetricsAgentHooks < OpenAIAgents::AgentHooks
  def initialize
    @start_time = nil
    @tool_count = 0
  end

  # Called when this specific agent starts
  # Use for: timing, initialization, agent-specific setup
  def on_start(context, agent)
    @start_time = Time.now
    puts "[AgentHooks] #{agent.name} started at #{@start_time}"
    
    # Store custom data in context for later retrieval
    # Context persists across the entire run
    context.store("#{agent.name}_start_time", @start_time)
  end

  # Called when this specific agent completes
  # Use for: performance metrics, cleanup, reporting
  def on_end(context, agent, output)
    duration = Time.now - @start_time
    puts "[AgentHooks] #{agent.name} completed in #{duration.round(2)} seconds"
    puts "[AgentHooks] Tools used: #{@tool_count}"
    
    # Retrieve shared data from context
    # Access information from across the run
    all_tools = context.tool_calls
    puts "[AgentHooks] All tool calls in this run: #{all_tools.size}"
  end

  # Called before this agent uses a tool
  # Use for: tool usage tracking, cost accounting
  def on_tool_start(context, agent, tool, arguments)
    @tool_count += 1
    puts "[AgentHooks] #{agent.name} tool ##{@tool_count}: #{tool.name}"
  end

  # Called when this agent receives a handoff
  # Use for: tracking agent interactions, workflow analysis
  def on_handoff(context, agent, source)
    puts "[AgentHooks] #{agent.name} received handoff from #{source.name}"
    puts "[AgentHooks] Handoff history: #{context.handoffs.map { |h| "#{h[:from]}->#{h[:to]}" }.join(", ")}"
  end
end

# Create agents with hooks attached
# Each agent can have its own hooks instance for isolated monitoring
weather_agent = OpenAIAgents::Agent.new(
  name: "WeatherBot",
  instructions: "You provide weather information. If asked about anything else, say 'HANDOFF: GeneralBot'",
  model: "gpt-4o-mini",
  hooks: MetricsAgentHooks.new  # Agent-specific hooks
)

# Add a weather tool that simulates external API
# Hooks will track tool usage automatically
weather_agent.add_tool(
  lambda { |location:|
    puts "[Weather API] Fetching weather for #{location}..."
    sleep(0.5) # Simulate API call latency
    "The weather in #{location} is sunny and 72°F with light winds."
  }
)

# Create second agent with its own hooks
# Each agent's hooks track metrics independently
general_agent = OpenAIAgents::Agent.new(
  name: "GeneralBot",
  instructions: "You are a helpful general assistant. For weather questions, say 'HANDOFF: WeatherBot'",
  model: "gpt-4o-mini",
  hooks: MetricsAgentHooks.new  # Separate instance for this agent
)

# Add a search tool to demonstrate multi-tool scenarios
# Hooks will track each tool call separately
general_agent.add_tool(
  lambda { |query:|
    puts "[Search API] Searching for: #{query}..."
    sleep(0.3) # Simulate API call
    "Found 5 results for '#{query}': Latest news, tutorials, and documentation."
  }
)

# Set up bidirectional handoffs for seamless routing
# Hooks will track all handoff events
weather_agent.add_handoff(general_agent)
general_agent.add_handoff(weather_agent)

# Create runner - can add run-level hooks at execution time
# Run hooks complement agent hooks for comprehensive monitoring
runner = OpenAIAgents::Runner.new(agent: general_agent)

# Example 1: Simple execution with hooks
# Demonstrates basic hook functionality with handoff and tool usage
puts "=== Example 1: Simple Execution with Hooks ==="
puts "Question: What's the weather in Paris?"
puts "-" * 50

# Run with logging hooks to see all lifecycle events
# Both run hooks and agent hooks will be active
result = runner.run(
  "What's the weather in Paris?",
  hooks: LoggingRunHooks.new  # Run-level hooks for this execution
)

puts "\nFinal response: #{result.messages.last[:content]}"
puts "=" * 50

# Example 2: Multiple handoffs with context tracking
# Shows how hooks can build comprehensive execution history
puts "\n=== Example 2: Multiple Handoffs with Context ==="
puts "Question: Tell me about Ruby programming and the weather in Tokyo"
puts "-" * 50

# Custom hooks that use context for state management
# Context provides persistent storage across the run
class ContextTrackingHooks < OpenAIAgents::RunHooks
  def on_agent_start(context, agent)
    # Track all agent activations in context
    # Build execution timeline for analysis
    activations = context.fetch(:agent_activations, [])
    activations << { agent: agent.name, turn: context.current_turn, time: Time.now }
    context.store(:agent_activations, activations)
    
    puts "[Context] Agent #{agent.name} activated (#{activations.size} total activations)"
  end

  def on_tool_end(context, agent, tool, result)
    # Track tool results for audit trail
    # Context maintains tool call history automatically
    context.add_tool_call(tool.name, {}, result)
  end

  def on_handoff(context, from_agent, to_agent)
    # Access built-in handoff tracking
    # Context provides handoff history out of the box
    puts "[Context] Handoff #{context.handoffs.size}: #{from_agent.name} -> #{to_agent.name}"
  end
end

# Execute with context tracking hooks
# Multiple handoffs will occur as agents collaborate
result = runner.run(
  "Tell me about Ruby programming and the weather in Tokyo",
  hooks: ContextTrackingHooks.new
)

puts "\nFinal response: #{result.messages.last[:content]}"
puts "=" * 50

# Example 3: Error handling with hooks
# Demonstrates how hooks enable robust error recovery
puts "\n=== Example 3: Error Handling with Hooks ==="

# Create agent for testing error scenarios
error_agent = OpenAIAgents::Agent.new(
  name: "ErrorBot",
  instructions: "You help test error handling",
  model: "gpt-4o-mini"
)

# Add a tool that can fail on demand
# Simulates real-world error conditions
error_agent.add_tool(
  lambda { |should_fail:|
    raise "Simulated tool failure!" if should_fail
      
    # Success path
    "Tool executed successfully"
    
  }
)

# Hooks that implement error recovery strategies
# Production systems need graceful error handling
class ErrorHandlingHooks < OpenAIAgents::RunHooks
  def on_error(context, agent, error)
    puts "[ErrorHook] Caught error in #{agent.name}: #{error.message}"
    puts "[ErrorHook] Current context: #{context.messages.size} messages"
    
    # Store error for potential recovery
    # Could implement retry logic, fallback agents, or alerts
    context.store(:last_error, { agent: agent.name, error: error.message, time: Time.now })
    
    # In production: could notify monitoring systems,
    # attempt recovery, or gracefully degrade functionality
  end
end

runner = OpenAIAgents::Runner.new(agent: error_agent)

# Test error handling with recovery
begin
  result = runner.run(
    "Please test the error_tool with should_fail: true",
    hooks: ErrorHandlingHooks.new
  )
  puts "\nResult: #{result.messages.last[:content]}"
rescue StandardError => e
  puts "\nExecution failed with: #{e.message}"
end

puts "\n=== Lifecycle Hooks Examples Complete ==="
puts "\nKey Takeaways:"
puts "1. RunHooks monitor entire execution across all agents"
puts "2. AgentHooks provide per-agent monitoring and metrics"
puts "3. Context enables state sharing between hooks"
puts "4. Hooks enable logging, metrics, error handling, and more"
puts "5. Production systems should implement comprehensive hooks"

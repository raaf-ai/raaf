#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "openai_agents"

# Example demonstrating lifecycle hooks for monitoring agent execution

# Custom run hooks that log all lifecycle events
class LoggingRunHooks < OpenAIAgents::RunHooks
  def initialize(log_prefix = "[RunHooks]")
    @log_prefix = log_prefix
  end

  def on_agent_start(context, agent)
    puts "#{@log_prefix} Agent starting: #{agent.name}"
    puts "  Current turn: #{context.current_turn}"
    puts "  Messages so far: #{context.messages.size}"
  end

  def on_agent_end(context, agent, output)
    puts "#{@log_prefix} Agent finished: #{agent.name}"
    puts "  Final output: #{output&.slice(0, 100)}..."
    puts "  Total messages: #{context.messages.size}"
  end

  def on_handoff(context, from_agent, to_agent)
    puts "#{@log_prefix} Handoff: #{from_agent.name} -> #{to_agent.name}"
    puts "  Reason: #{context.messages.last[:content]&.slice(0, 50)}..."
  end

  def on_tool_start(context, agent, tool, arguments)
    puts "#{@log_prefix} Tool starting: #{tool.name}"
    puts "  Agent: #{agent.name}"
    puts "  Arguments: #{arguments.inspect}"
  end

  def on_tool_end(context, agent, tool, result)
    puts "#{@log_prefix} Tool finished: #{tool.name}"
    puts "  Result: #{result.to_s.slice(0, 100)}..."
  end

  def on_error(context, agent, error)
    puts "#{@log_prefix} ERROR in #{agent.name}: #{error.message}"
  end
end

# Custom agent hooks for agent-specific monitoring
class MetricsAgentHooks < OpenAIAgents::AgentHooks
  def initialize
    @start_time = nil
    @tool_count = 0
  end

  def on_start(context, agent)
    @start_time = Time.now
    puts "[AgentHooks] #{agent.name} started at #{@start_time}"
    
    # Store custom data in context
    context.store("#{agent.name}_start_time", @start_time)
  end

  def on_end(context, agent, output)
    duration = Time.now - @start_time
    puts "[AgentHooks] #{agent.name} completed in #{duration.round(2)} seconds"
    puts "[AgentHooks] Tools used: #{@tool_count}"
    
    # Retrieve custom data from context
    all_tools = context.tool_calls
    puts "[AgentHooks] All tool calls in this run: #{all_tools.size}"
  end

  def on_tool_start(context, agent, tool, arguments)
    @tool_count += 1
    puts "[AgentHooks] #{agent.name} tool ##{@tool_count}: #{tool.name}"
  end

  def on_handoff(context, agent, source)
    puts "[AgentHooks] #{agent.name} received handoff from #{source.name}"
    puts "[AgentHooks] Handoff history: #{context.handoffs.map { |h| "#{h[:from]}->#{h[:to]}" }.join(", ")}"
  end
end

# Create agents with hooks
weather_agent = OpenAIAgents::Agent.new(
  name: "WeatherBot",
  instructions: "You provide weather information. If asked about anything else, say 'HANDOFF: GeneralBot'",
  model: "gpt-4o-mini",
  hooks: MetricsAgentHooks.new
)

# Add a weather tool
weather_agent.add_tool(
  lambda { |location:|
    puts "[Weather API] Fetching weather for #{location}..."
    sleep(0.5) # Simulate API call
    "The weather in #{location} is sunny and 72°F with light winds."
  }
)

general_agent = OpenAIAgents::Agent.new(
  name: "GeneralBot",
  instructions: "You are a helpful general assistant. For weather questions, say 'HANDOFF: WeatherBot'",
  model: "gpt-4o-mini",
  hooks: MetricsAgentHooks.new
)

# Add a search tool to general agent
general_agent.add_tool(
  lambda { |query:|
    puts "[Search API] Searching for: #{query}..."
    sleep(0.3) # Simulate API call
    "Found 5 results for '#{query}': Latest news, tutorials, and documentation."
  }
)

# Set up handoffs
weather_agent.add_handoff(general_agent)
general_agent.add_handoff(weather_agent)

# Create runner with run-level hooks
runner = OpenAIAgents::Runner.new(agent: general_agent)

# Example 1: Simple execution with hooks
puts "=== Example 1: Simple Execution with Hooks ==="
puts "Question: What's the weather in Paris?"
puts "-" * 50

result = runner.run(
  "What's the weather in Paris?",
  hooks: LoggingRunHooks.new
)

puts "\nFinal response: #{result.messages.last[:content]}"
puts "=" * 50

# Example 2: Multiple handoffs with context tracking
puts "\n=== Example 2: Multiple Handoffs with Context ==="
puts "Question: Tell me about Ruby programming and the weather in Tokyo"
puts "-" * 50

# Custom hooks that track context
class ContextTrackingHooks < OpenAIAgents::RunHooks
  def on_agent_start(context, agent)
    # Track agent activations
    activations = context.fetch(:agent_activations, [])
    activations << { agent: agent.name, turn: context.current_turn, time: Time.now }
    context.store(:agent_activations, activations)
    
    puts "[Context] Agent #{agent.name} activated (#{activations.size} total activations)"
  end

  def on_tool_end(context, agent, tool, result)
    # Track tool results
    context.add_tool_call(tool.name, {}, result)
  end

  def on_handoff(context, from_agent, to_agent)
    # The context wrapper already tracks handoffs
    puts "[Context] Handoff #{context.handoffs.size}: #{from_agent.name} -> #{to_agent.name}"
  end
end

result = runner.run(
  "Tell me about Ruby programming and the weather in Tokyo",
  hooks: ContextTrackingHooks.new
)

puts "\nFinal response: #{result.messages.last[:content]}"
puts "=" * 50

# Example 3: Error handling with hooks
puts "\n=== Example 3: Error Handling with Hooks ==="

error_agent = OpenAIAgents::Agent.new(
  name: "ErrorBot",
  instructions: "You help test error handling",
  model: "gpt-4o-mini"
)

# Add a tool that sometimes fails
error_agent.add_tool(
  lambda { |should_fail:|
    raise "Simulated tool failure!" if should_fail
      
    
    "Tool executed successfully"
    
  }
)

class ErrorHandlingHooks < OpenAIAgents::RunHooks
  def on_error(context, agent, error)
    puts "[ErrorHook] Caught error in #{agent.name}: #{error.message}"
    puts "[ErrorHook] Current context: #{context.messages.size} messages"
    
    # Could implement recovery logic here
    context.store(:last_error, { agent: agent.name, error: error.message, time: Time.now })
  end
end

runner = OpenAIAgents::Runner.new(agent: error_agent)

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

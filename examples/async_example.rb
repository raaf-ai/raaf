#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "openai_agents/async"
require "benchmark"

# Example demonstrating async agent execution with parallel tool calls

# Create an async agent
agent = OpenAIAgents::Async.agent(
  name: "AsyncAssistant",
  instructions: "You are a helpful assistant that can search for information and perform calculations.",
  model: "gpt-4o-mini"
)

# Add async tools that simulate API calls
agent.add_tool(
  -> (query:) {
    puts "[Search] Starting search for: #{query}"
    sleep(1) # Simulate API latency
    puts "[Search] Completed search for: #{query}"
    "Search results for '#{query}': Found 10 relevant articles about #{query}."
  }
)

agent.add_tool(
  -> (expression:) {
    puts "[Calculate] Starting calculation: #{expression}"
    sleep(0.5) # Simulate computation time
    result = eval(expression) rescue "Invalid expression"
    puts "[Calculate] Completed calculation: #{expression} = #{result}"
    "Result: #{result}"
  }
)

agent.add_tool(
  -> (location:) {
    puts "[Weather] Fetching weather for: #{location}"
    sleep(1.5) # Simulate API call
    puts "[Weather] Completed weather fetch for: #{location}"
    "The weather in #{location} is sunny and 72°F."
  }
)

# Example 1: Simple async execution
puts "=== Example 1: Simple Async Execution ==="
puts "Running agent asynchronously..."

Async do
  result = OpenAIAgents::Async.run(
    agent,
    "What's the weather in New York and search for Ruby async patterns?"
  ).wait

  puts "\nAgent response:"
  puts result.messages.last[:content]
end

puts "\n" + "="*50 + "\n"

# Example 2: Parallel agent execution
puts "=== Example 2: Parallel Agent Execution ==="
puts "Running multiple agents in parallel..."

# Create multiple agents for different tasks
weather_agent = OpenAIAgents::Async.agent(
  name: "WeatherAgent",
  instructions: "You provide weather information.",
  model: "gpt-4o-mini"
)

math_agent = OpenAIAgents::Async.agent(
  name: "MathAgent", 
  instructions: "You solve math problems.",
  model: "gpt-4o-mini"
)

# Run agents in parallel
Async do |task|
  time = Benchmark.measure do
    # Launch multiple async tasks
    weather_task = task.async do
      OpenAIAgents::Async.run(
        weather_agent,
        "What's the weather forecast for next week?"
      ).wait
    end

    math_task = task.async do
      OpenAIAgents::Async.run(
        math_agent,
        "Calculate the factorial of 10"
      ).wait
    end

    search_task = task.async do
      OpenAIAgents::Async.run(
        agent,
        "Search for information about async programming in Ruby"
      ).wait
    end

    # Wait for all tasks to complete
    results = [weather_task, math_task, search_task].map(&:wait)

    puts "\nParallel execution results:"
    results.each_with_index do |result, i|
      puts "\nTask #{i + 1}:"
      puts result.messages.last[:content]
    end
  end

  puts "\nTotal execution time: #{time.real.round(2)} seconds"
  puts "(Note: Tasks ran in parallel, so total time is less than sum of individual tasks)"
end

puts "\n" + "="*50 + "\n"

# Example 3: Async tool execution
puts "=== Example 3: Direct Async Tool Execution ==="
puts "Executing tools directly in parallel..."

Async do
  agent_instance = OpenAIAgents::Async.agent(
    name: "ToolAgent",
    instructions: "Execute tools as requested",
    model: "gpt-4o-mini"
  )

  # Add the same tools
  agent_instance.add_tool(agent.tools[0]) # search
  agent_instance.add_tool(agent.tools[1]) # calculate
  agent_instance.add_tool(agent.tools[2]) # weather

  time = Benchmark.measure do
    # Execute multiple tools in parallel
    results = agent_instance.execute_tools_async([
      { name: "search", arguments: { query: "Ruby concurrency" } },
      { name: "calculate", arguments: { expression: "100 * 50 + 25" } },
      { name: "weather", arguments: { location: "San Francisco" } }
    ]).wait

    puts "\nTool execution results:"
    results.each do |result|
      if result[:error]
        puts "#{result[:name]}: ERROR - #{result[:error]}"
      else
        puts "#{result[:name]}: #{result[:result]}"
      end
    end
  end

  puts "\nParallel tool execution time: #{time.real.round(2)} seconds"
end

puts "\n=== Async Examples Complete ==="
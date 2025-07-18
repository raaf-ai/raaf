#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates concurrent agent execution in RAAF (Ruby AI Agents Factory).
# Concurrent operations enable parallel processing, improved performance, and better
# resource utilization when dealing with multiple agents or time-consuming tools.
# The concurrency functionality uses Ruby's Concurrent Ruby gem and built-in
# threading capabilities to provide efficient parallel execution.

require "bundler/setup"
require_relative "../lib/raaf"
require "benchmark"
require "concurrent-ruby"

# ============================================================================
# CONCURRENT AGENT EXAMPLES
# ============================================================================
# NOTE: This example requires the 'concurrent-ruby' gem to be installed:
# gem install concurrent-ruby

# ============================================================================
# AGENT SETUP
# ============================================================================
# Create an agent that will be used with concurrent execution patterns.
# While the agent itself isn't inherently async, we can execute multiple
# agents concurrently for parallel processing.

agent = RAAF::Agent.new(
  name: "ConcurrentAssistant",
  
  # Instructions guide the agent's behavior
  instructions: "You are a helpful assistant that can search for information and perform calculations.",
  
  # Using smaller model for faster responses in examples
  model: "gpt-4o-mini"
)

# ============================================================================
# CONCURRENT TOOLS
# ============================================================================
# Define tools that simulate time-consuming operations like API calls.
# While individual tool calls aren't async, we can execute multiple agents
# concurrently to achieve parallel processing.

# Tool 1: Search function simulating external API call
# In production: would call search APIs, databases, or web services
def search_tool(query:)
  puts "[Search] Starting search for: #{query}"
  sleep(1) # Simulate API latency (would be actual API call)
  puts "[Search] Completed search for: #{query}"
  "Search results for '#{query}': Found 10 relevant articles about #{query}."
end

agent.add_tool(method(:search_tool))

# Tool 2: Calculator simulating complex computation
# Shows how concurrency allows other operations while calculating
def calculate_tool(expression:)
  puts "[Calculate] Starting calculation: #{expression}"
  sleep(0.5) # Simulate computation time
  
  # Safe evaluation with error handling
  result = begin
    # In production: use a proper expression parser
    eval(expression)
  rescue StandardError
    "Invalid expression"
  end
  
  puts "[Calculate] Completed calculation: #{expression} = #{result}"
  "Result: #{result}"
end

agent.add_tool(method(:calculate_tool))

# Tool 3: Weather service with highest latency
# Demonstrates benefit of concurrency when dealing with slow services
def weather_tool(location:)
  puts "[Weather] Fetching weather for: #{location}"
  sleep(1.5) # Simulate slow weather API
  puts "[Weather] Completed weather fetch for: #{location}"
  "The weather in #{location} is sunny and 72°F."
end

agent.add_tool(method(:weather_tool))

# ============================================================================
# EXAMPLE 1: SIMPLE AGENT EXECUTION
# ============================================================================
# Shows basic agent execution with tool calls.
# While individual tool calls are sequential, we can run multiple agents
# concurrently in the next examples.

puts "=== Example 1: Simple Agent Execution ==="
puts "Running agent with multiple tools..."

# Create a runner for the agent
runner = RAAF::Runner.new(agent: agent)

# Run the agent with a query that triggers multiple tools
result = runner.run(
  "What's the weather in New York and search for Ruby async patterns?"
)

puts "\nAgent response:"
puts result.messages.last[:content]

puts "\n" + ("=" * 50) + "\n"

# ============================================================================
# EXAMPLE 2: PARALLEL MULTI-AGENT EXECUTION
# ============================================================================
# Demonstrates running multiple specialized agents concurrently using threads.
# This pattern is powerful for decomposing complex tasks.

puts "=== Example 2: Parallel Agent Execution ==="
puts "Running multiple agents in parallel..."

# Create specialized agents for different domains
# Each agent has focused expertise and instructions

# Weather specialist agent
weather_agent = RAAF::Agent.new(
  name: "WeatherAgent",
  instructions: "You provide weather information.",
  model: "gpt-4o-mini"
)

# Mathematics specialist agent
math_agent = RAAF::Agent.new(
  name: "MathAgent", 
  instructions: "You solve math problems.",
  model: "gpt-4o-mini"
)

# Create runners for each agent
weather_runner = RAAF::Runner.new(agent: weather_agent)
math_runner = RAAF::Runner.new(agent: math_agent)
search_runner = RAAF::Runner.new(agent: agent)

# Measure execution time to demonstrate parallelism benefits
time = Benchmark.measure do
  # Launch multiple threads simultaneously
  # Each runs in its own thread, allowing concurrent execution
  
  # Task 1: Weather forecast
  weather_thread = Thread.new do
    weather_runner.run("What's the weather forecast for next week?")
  end

  # Task 2: Mathematical computation
  math_thread = Thread.new do
    math_runner.run("Calculate the factorial of 10")
  end

  # Task 3: Information search
  search_thread = Thread.new do
    search_runner.run("Search for information about concurrent programming in Ruby")
  end

  # Collect results from all parallel threads
  # This waits for all threads to complete
  results = [weather_thread, math_thread, search_thread].map(&:value)

  # Display results from each agent
  puts "\nParallel execution results:"
  results.each_with_index do |result, i|
    puts "\nTask #{i + 1}:"
    puts result.messages.last[:content]
  end
end

# Show performance benefit of parallelism
puts "\nTotal execution time: #{time.real.round(2)} seconds"
puts "(Note: Tasks ran in parallel, so total time is less than sum of individual tasks)"

puts "\n" + ("=" * 50) + "\n"

# ============================================================================
# EXAMPLE 3: CONCURRENT BATCH PROCESSING
# ============================================================================
# Shows concurrent processing of multiple queries using thread pools.
# Useful for processing multiple independent requests simultaneously.

puts "=== Example 3: Concurrent Batch Processing ==="
puts "Processing multiple queries concurrently..."

# Create multiple queries that can be processed in parallel
queries = [
  "What's the weather in San Francisco?",
  "Calculate 100 * 50 + 25",
  "Search for Ruby concurrency patterns",
  "What's the weather in Tokyo?",
  "Calculate the square root of 144"
]

# Create a thread pool using concurrent-ruby for efficient processing
thread_pool = Concurrent::ThreadPoolExecutor.new(
  min_threads: 2,
  max_threads: 5,
  max_queue: 10,
  fallback_policy: :caller_runs
)

time = Benchmark.measure do
  # Submit all queries to the thread pool for concurrent execution
  futures = queries.map do |query|
    Concurrent::Future.execute(executor: thread_pool) do
      runner = RAAF::Runner.new(agent: agent)
      result = runner.run(query)
      {
        query: query,
        response: result.messages.last[:content],
        thread_id: Thread.current.object_id
      }
    end
  end

  # Wait for all futures to complete and collect results
  results = futures.map(&:value!)

  # Display results with thread information
  puts "\nConcurrent batch processing results:"
  results.each_with_index do |result, i|
    puts "\nQuery #{i + 1} (Thread #{result[:thread_id]}):"
    puts "Q: #{result[:query]}"
    puts "A: #{result[:response]}"
  end
end

# Clean up the thread pool
thread_pool.shutdown
thread_pool.wait_for_termination(30)

# Demonstrate time savings from parallelization
puts "\nConcurrent processing time: #{time.real.round(2)} seconds"
puts "Sequential processing would take much longer"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Concurrent Examples Complete ==="
puts "\nKey Benefits of Concurrent Agents:"
puts "1. Parallel agent execution reduces total runtime"
puts "2. Multiple agents can work concurrently using threads"
puts "3. Better resource utilization for I/O-bound operations"
puts "4. Thread pools provide controlled concurrent execution"
puts "5. Scales better with multiple concurrent requests"

puts "\nBest Practices:"
puts "- Use concurrency for I/O-bound operations (API calls, file access)"
puts "- Group independent operations for parallel execution"
puts "- Monitor memory usage with many concurrent operations"
puts "- Handle errors gracefully in concurrent contexts"
puts "- Consider rate limits when parallelizing external API calls"
puts "- Use thread pools to control resource usage"
puts "- Be mindful of thread safety when sharing data"

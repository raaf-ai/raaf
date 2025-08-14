#!/usr/bin/env ruby
# frozen_string_literal: true

##
# Basic Agent Example using RAAF DSL
#
# This example demonstrates how to create a simple conversational agent
# using the RAAF DSL with modern best practices.
#
# @author RAAF Team
# @since 0.1.0
# @example Run this example
#   ruby examples/basic_agent_example.rb

require "raaf-core"
require "raaf-dsl"

##
# Create a basic conversational agent using the RAAF DSL
# The DSL provides a clean, declarative way to configure agents
# with proper validation and type safety.
agent = RAAF::DSL::AgentBuilder.build do
  name "HelpfulAssistant"
  instructions "You are a helpful assistant that provides clear, concise, and accurate answers."
  model "gpt-4o"  # Uses ResponsesProvider by default for Python SDK compatibility

  # Configure agent behavior
  config do
    temperature 0.7    # Balance creativity with consistency
    max_turns 3        # Limit conversation length for this example
  end
end

# Display agent configuration
puts "✅ Created agent: #{agent.name}"
puts "   Model: #{agent.model}"
puts "   Instructions: #{agent.instructions[0..80]}..."

# Create a runner to execute the agent (uses ResponsesProvider by default)
runner = RAAF::Runner.new(agent: agent)

puts "\n--- Starting conversation ---"

begin
  # Run a simple conversation with error handling
  result = runner.run("What are the three primary colors?")

  # Display the conversation history
  puts "\n📝 Conversation:"
  result.messages.each_with_index do |message, index|
    role_emoji = message[:role] == "user" ? "👤" : "🤖"
    puts "#{role_emoji} #{message[:role].upcase}: #{message[:content]}"
  end

  # Show execution summary
  puts "\n📊 Execution Summary:"
  puts "   Turns taken: #{result.messages.count { |m| m[:role] == "assistant" }}"
  puts "   Final agent: #{result.last_agent&.name || agent.name}"

rescue RAAF::Error => e
  puts "\n❌ RAAF Error: #{e.message}"
  puts "   This example requires an OpenAI API key to run fully."
  puts "   Set OPENAI_API_KEY environment variable and try again."
rescue StandardError => e
  puts "\n❌ Unexpected error: #{e.message}"
  puts "   Please check your configuration and try again."
end

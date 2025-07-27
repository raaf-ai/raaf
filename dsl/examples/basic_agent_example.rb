#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic Agent Example
#
# This example demonstrates how to create a simple conversational agent
# using the RAAF DSL.

require "raaf-core"
require "raaf-dsl"

# Create a basic conversational agent
agent = RAAF::DSL::AgentBuilder.build do
  name "Assistant"
  instructions "You are a helpful assistant that provides clear and concise answers."
  model "gpt-4o"

  # Configure temperature and max turns
  config do
    temperature 0.7
    max_turns 3
  end
end

puts "Created agent: #{agent.name}"
puts "Model: #{agent.model}"
puts "Instructions: #{agent.instructions}"
# NOTE: Agent configuration is internal and not directly accessible

# Create a runner to execute the agent
runner = RAAF::Runner.new(agent: agent)

# Run a simple conversation
puts "\n--- Starting conversation ---"
result = runner.run("What are the three primary colors?")

# Display the conversation
puts "\nConversation:"
result.messages.each do |message|
  puts "#{message[:role].upcase}: #{message[:content]}"
end

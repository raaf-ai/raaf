#!/usr/bin/env ruby
# frozen_string_literal: true

require "raaf-core"
require "raaf-dsl"

# Create a simple prompt class
class DemoPrompt < RAAF::DSL::Prompts::Base
  def system
    "You are a helpful assistant."
  end

  def user
    "Hello there!"
  end
end

# Create an agent that uses the prompt class
class DemoAgent < RAAF::DSL::Agent

  agent_name "demo_agent"
  prompt_class DemoPrompt

  def agent_name
    "Demo Agent"
  end

  def build_schema
    {
      type: "object",
      properties: {
        response: { type: "string" }
      },
      required: ["response"],
      additionalProperties: false
    }
  end
end

# Demonstrate the implementation
puts "=== AI Agent DSL - Strict Prompt Implementation ==="
puts

# Create agent instance
context = { demo: true }
processing_params = { test: true }
agent = DemoAgent.new(context: context, processing_params: processing_params)

# Show that build_user_prompt works
puts "✓ Agent configured with prompt class: #{agent.class.prompt_class}"
puts "✓ User prompt from prompt class: '#{agent.build_user_prompt}'"
puts "✓ System prompt from prompt class: '#{agent.build_instructions}'"
puts

# Show that the run method exists
puts "✓ Agent has run method: #{agent.respond_to?(:run)}"
puts

# Demonstrate error when no prompt class
puts "=== Error Demonstration ==="

class BadAgent < RAAF::DSL::Agent

  agent_name "bad_agent"

  def agent_name
    "Bad Agent"
  end

  def build_schema
    { type: "object", properties: {}, additionalProperties: false }
  end
end

bad_agent = BadAgent.new(context: context, processing_params: processing_params)

begin
  bad_agent.build_user_prompt
rescue RAAF::DSL::Error => e
  puts "✓ Expected error when no prompt class: #{e.message}"
end

puts
puts "=== Implementation Summary ==="
puts "• User prompt ALWAYS comes from the prompt class"
puts "• No DSL method to override the user prompt"
puts "• System FAILS if no prompt class is configured"
puts "• System FAILS if prompt class lacks user/system methods"
puts "• agent.run() uses the prompt class user method"

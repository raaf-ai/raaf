# frozen_string_literal: true

require_relative "../lib/ai_agent_dsl"
require_relative "web_search_agent"

puts "=== Running WebSearchAgent with prompt from prompt class ==="

# Create agent with context and processing params
context = { user: { name: "Test User" } }
processing_params = { max_results: 5 }

agent = WebSearchAgent.new(context: context, processing_params: processing_params)

# Run with the user prompt from the WebSearchPrompt class
# This will use the prompt defined in the user method of WebSearchPrompt
begin
  result = agent.run
  puts "Agent result: #{result}"
rescue StandardError => e
  puts "Note: This example requires OpenAI API setup. Error: #{e.message}"
end

puts "\n=== Demonstrating error when no prompt class is configured ==="

# Example of what happens when no prompt class is configured
class BadAgent < AiAgentDsl::Agents::Base
  include AiAgentDsl::AgentDsl

  agent_name "bad_agent"
  uses_tool :web_search

  def agent_name
    "Bad Agent"
  end

  def build_schema
    { type: "object", properties: {}, additionalProperties: false }
  end
end

bad_agent = BadAgent.new(context: context, processing_params: processing_params)

begin
  bad_agent.run
rescue AiAgentDsl::Error => e
  puts "Expected error: #{e.message}"
end

puts "\n=== Example usage patterns ==="
puts <<~USAGE
  # 1. Create a prompt class (REQUIRED):
  class MyPrompt < AiAgentDsl::Prompts::Base
    def system
      "You are a helpful assistant."
    end
  #{'  '}
    def user
      "Hello there!"
    end
  end

  # 2. Configure the agent to use the prompt class:
  class MyAgent < AiAgentDsl::Agents::Base
    include AiAgentDsl::AgentDsl
  #{'  '}
    prompt_class MyPrompt
  end

  # 3. Run the agent (uses prompt from prompt class):
  agent = MyAgent.new(context: {}, processing_params: {})
  result = agent.run  # Uses MyPrompt#user for the user prompt

  # 4. The system will FAIL if:
  #    - No prompt class is configured
  #    - The prompt class doesn't have a user method
  #    - The prompt class doesn't have a system method
USAGE

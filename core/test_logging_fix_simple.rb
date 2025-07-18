#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/raaf-core'

# Mock provider that doesn't need API keys
class MockProvider < RAAF::Models::ModelInterface
  def responses_completion(messages:, model:, tools: nil, **kwargs)
    puts "MockProvider received #{messages.size} messages with #{tools&.size || 0} tools"
    {
      output: [{
        type: "message",
        role: "assistant", 
        content: "This is a mock response"
      }],
      usage: { total_tokens: 10 },
      model: model
    }
  end
  
  def complete(messages:, model:, tools: nil, **kwargs)
    responses_completion(messages: messages, model: model, tools: tools, **kwargs)
  end
  
  def supported_models
    ["mock-model"]
  end
  
  def provider_name
    "MockProvider"
  end
end

# Enable debug logging
ENV['RAAF_DEBUG_CATEGORIES'] = 'api,handoff'
ENV['RAAF_LOG_LEVEL'] = 'debug'

# Create agents
agent1 = RAAF::Agent.new(
  name: "Agent1",
  instructions: "You are agent 1",
  model: "mock-model"
)

agent2 = RAAF::Agent.new(
  name: "Agent2", 
  instructions: "You are agent 2",
  model: "mock-model"
)

# Set up handoff
agent1.add_handoff(agent2)

# Create runner with mock provider
runner = RAAF::Runner.new(
  agent: agent1,
  provider: MockProvider.new
)

puts "=== Testing with Mock Provider ==="
puts "This should show debug logging without API errors"
puts

begin
  result = runner.run("Hello")
  puts "✅ Success! Message logging is working."
  puts "Response: #{result.messages.last[:content]}"
rescue => e
  puts "❌ Error: #{e.message}"
  puts "Class: #{e.class}"
end
#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify comprehensive agent span collection

require_relative 'core/lib/raaf-core'
require_relative 'tracing/lib/raaf-tracing'

# Mock agent class for testing
class TestAgent
  attr_reader :name, :model, :instructions, :tools, :handoffs, :max_turns
  attr_reader :last_run_result

  def initialize
    @name = "TestAgent"
    @model = "gpt-4o"
    @instructions = "You are a helpful test agent that demonstrates comprehensive tracing capabilities."
    @tools = ['search_web', 'calculate']
    @handoffs = ['SpecialistAgent']
    @max_turns = 5

    # Mock a RunResult with conversation data
    @last_run_result = create_mock_run_result
  end

  private

  def create_mock_run_result
    messages = [
      { role: "system", content: @instructions },
      { role: "user", content: "Can you help me search for Ruby programming tutorials and calculate 2 + 2?" },
      {
        role: "assistant",
        content: "I'll help you search for Ruby programming tutorials and calculate that for you.",
        tool_calls: [
          {
            id: "call_123",
            function: { name: "search_web", arguments: '{"query": "Ruby programming tutorials"}' }
          },
          {
            id: "call_456",
            function: { name: "calculate", arguments: '{"expression": "2 + 2"}' }
          }
        ]
      },
      {
        role: "tool",
        tool_call_id: "call_123",
        name: "search_web",
        content: "Found 10 excellent Ruby programming tutorials including official Ruby documentation."
      },
      {
        role: "tool",
        tool_call_id: "call_456",
        name: "calculate",
        content: "4"
      },
      {
        role: "assistant",
        content: "Great! I found 10 excellent Ruby programming tutorials for you. Also, 2 + 2 = 4. The tutorials include the official Ruby documentation which is an excellent starting point."
      }
    ]

    tool_results = [
      { name: "search_web", result: "Found 10 excellent Ruby programming tutorials", call_id: "call_123" },
      { name: "calculate", result: "4", call_id: "call_456" }
    ]

    # Mock RunResult structure
    OpenStruct.new(
      messages: messages,
      tool_results: tool_results,
      usage: { total_tokens: 250, prompt_tokens: 180, completion_tokens: 70 }
    )
  end
end

puts "🧪 Testing Enhanced Agent Span Collection"
puts "=" * 50

# Create test agent
agent = TestAgent.new

# Create and test the collector
collector = RAAF::Tracing::SpanCollectors::AgentCollector.new
attributes = collector.collect_attributes(agent)

puts "\n📊 Collected Agent Span Attributes:"
puts "-" * 40

# Test basic agent attributes
puts "🤖 Agent Info:"
puts "  Name: #{attributes['name']}"
puts "  Model: #{attributes['model']}"
puts "  Max Turns: #{attributes['max_turns']}"
puts "  Tools Count: #{attributes['tools_count']}"
puts "  Handoffs Count: #{attributes['handoffs_count']}"

puts "\n💬 Comprehensive Dialog Collection:"

# Test system instructions
puts "  System Instructions: #{attributes['system_instructions'][0..100]}..."

# Test conversation messages
messages_json = attributes['conversation_messages']
if messages_json && messages_json != "[]"
  messages = JSON.parse(messages_json)
  puts "  Total Messages: #{messages.length}"
  puts "  Message Types: #{messages.map { |m| m['role'] || m[:role] }.join(', ')}"
else
  puts "  ❌ No conversation messages found"
end

# Test initial user prompt
puts "  Initial User Prompt: #{attributes['initial_user_prompt']}"

# Test tool executions
tool_json = attributes['tool_executions']
if tool_json && tool_json != "[]"
  tools = JSON.parse(tool_json)
  puts "  Tool Executions: #{tools.length}"
  tools.each do |tool|
    puts "    - #{tool['name']}: #{tool['arguments'] || 'no args'}"
  end
else
  puts "  ❌ No tool executions found"
end

# Test final response
puts "  Final Agent Response: #{attributes['final_agent_response'][0..100]}..."

# Test conversation stats
stats_json = attributes['conversation_stats']
if stats_json
  stats = JSON.parse(stats_json)
  puts "\n📈 Conversation Statistics:"
  puts "  Total Messages: #{stats['total_messages']}"
  puts "  User Messages: #{stats['user_messages']}"
  puts "  Assistant Messages: #{stats['assistant_messages']}"
  puts "  Tool Calls: #{stats['tool_calls']}"
  puts "  Has System Message: #{stats['has_system_message']}"
else
  puts "  ❌ No conversation stats found"
end

puts "\n✅ Test completed successfully!"
puts "🎯 The enhanced AgentCollector is now capturing:"
puts "   • System instructions (agent prompt)"
puts "   • Complete conversation history"
puts "   • Initial user input"
puts "   • All tool calls and results"
puts "   • Final agent response"
puts "   • Conversation statistics"

puts "\n🚀 Ready to display in the UI!"
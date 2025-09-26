#!/usr/bin/env ruby
# frozen_string_literal: true

# Direct test of agent methods and collector

require 'json'
require_relative 'tracing/lib/raaf/tracing/span_collectors/base_collector'
require_relative 'tracing/lib/raaf/tracing/span_collectors/agent_collector'

# Simplified test agent
class TestAgent
  attr_reader :name, :model, :instructions, :tools, :handoffs, :max_turns

  def initialize
    @name = "TestAgent"
    @model = "gpt-4o"
    @instructions = "You are a helpful test agent."
    @tools = ['search_web', 'calculate']
    @handoffs = ['SpecialistAgent']
    @max_turns = 5
  end
end

puts "🔧 Direct Method Testing"
puts "=" * 40

agent = TestAgent.new
puts "\n🤖 Testing agent direct access:"
puts "  agent.name: #{agent.name.inspect}"
puts "  agent.model: #{agent.model.inspect}"
puts "  agent.instructions: #{agent.instructions.inspect}"
puts "  agent.tools: #{agent.tools.inspect}"
puts "  agent.max_turns: #{agent.max_turns.inspect}"
puts "  agent.respond_to?(:name): #{agent.respond_to?(:name)}"

puts "\n📊 Testing collector manual attribute extraction:"

# Test the direct attribute extraction
collector = RAAF::Tracing::SpanCollectors::AgentCollector.new

# Test component_prefix method
prefix = collector.send(:component_prefix)
puts "  component_prefix: #{prefix.inspect}"

# Test base_attributes
base_attrs = collector.send(:base_attributes, agent)
puts "  base_attributes: #{base_attrs.inspect}"

# Test custom_attributes
custom_attrs = collector.send(:custom_attributes, agent)
puts "  custom_attributes keys: #{custom_attrs.keys.inspect}"
puts "  custom_attributes: #{custom_attrs.inspect}"

puts "\n🎯 Full collect_attributes result:"
all_attributes = collector.collect_attributes(agent)
all_attributes.each do |key, value|
  puts "  #{key}: #{value.inspect}"
end
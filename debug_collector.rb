#!/usr/bin/env ruby
# frozen_string_literal: true

# Debug script to understand collector class variables

require_relative 'tracing/lib/raaf/tracing/span_collectors/base_collector'
require_relative 'tracing/lib/raaf/tracing/span_collectors/agent_collector'

puts "🔍 Debug: Collector Class Variables"
puts "=" * 50

puts "\n📊 AgentCollector class variables:"
agent_collector_class = RAAF::Tracing::SpanCollectors::AgentCollector

span_attrs = agent_collector_class.instance_variable_get(:@span_attrs)
span_custom = agent_collector_class.instance_variable_get(:@span_custom)

puts "  @span_attrs: #{span_attrs.inspect}"
puts "  @span_custom keys: #{span_custom.keys.inspect if span_custom}"
puts "  @span_custom count: #{span_custom.size if span_custom}"

puts "\n🧪 Testing a simple collector:"

class TestCollector < RAAF::Tracing::SpanCollectors::BaseCollector
  span :name, :model
  span test_attribute: ->(comp) { "test_value" }
end

test_span_attrs = TestCollector.instance_variable_get(:@span_attrs)
test_span_custom = TestCollector.instance_variable_get(:@span_custom)

puts "  TestCollector @span_attrs: #{test_span_attrs.inspect}"
puts "  TestCollector @span_custom: #{test_span_custom.inspect}"

# Test the collector
class SimpleAgent
  attr_reader :name, :model
  def initialize
    @name = "TestAgent"
    @model = "gpt-4o"
  end
end

agent = SimpleAgent.new
collector = TestCollector.new
attributes = collector.collect_attributes(agent)

puts "\n🎯 Collected attributes:"
attributes.each do |key, value|
  puts "  #{key}: #{value.inspect}"
end

puts "\n✅ Debug complete"
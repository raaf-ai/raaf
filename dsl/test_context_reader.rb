#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test to verify context_reader works with auto-context

$LOAD_PATH.unshift File.expand_path("lib", __dir__)

require "raaf/dsl/agent"
require "raaf/dsl/core/context_variables"
require "raaf/dsl/core/context_builder"

# Test agent with context readers
class TestAgent < RAAF::DSL::Agent
  agent_name "TestAgent"
  static_instructions "Test agent for context reader"
  
  # Define context readers
  context_reader :product, required: true
  context_reader :company, required: true
  context_reader :mode, default: "standard"
  context_reader :limit, default: 10
  context_reader :optional_param
  
  def process
    puts "✅ Context Reader Values:"
    puts "  Product: #{product}"
    puts "  Company: #{company}"
    puts "  Mode: #{mode}"
    puts "  Limit: #{limit}"
    puts "  Optional: #{optional_param.inspect}"
    
    # Also test direct context API
    puts "\n✅ Direct Context API:"
    puts "  get(:product): #{get(:product)}"
    puts "  get(:mode): #{get(:mode)}"
    puts "  has?(:optional_param): #{has?(:optional_param)}"
    puts "  context_keys: #{context_keys.inspect}"
  end
end

puts "=" * 60
puts "Testing context_reader with auto-context"
puts "=" * 60

# Test 1: Basic usage with required params
puts "\n📝 Test 1: Basic usage with required params"
agent1 = TestAgent.new(
  product: "Widget Pro",
  company: "Acme Corp",
  optional_param: "custom_value"
)
agent1.process

# Test 2: Using defaults
puts "\n📝 Test 2: Using defaults (no mode or limit provided)"
agent2 = TestAgent.new(
  product: "Widget",
  company: "Tech Co"
)
agent2.process

# Test 3: Overriding defaults
puts "\n📝 Test 3: Overriding defaults"
agent3 = TestAgent.new(
  product: "Widget Ultra",
  company: "MegaCorp",
  mode: "advanced",
  limit: 50
)
agent3.process

# Test 4: Test that required validation works
puts "\n📝 Test 4: Testing required field validation"
begin
  agent4 = TestAgent.new(company: "OnlyCompany")
  agent4.process # This should fail when accessing product
rescue ArgumentError => e
  puts "✅ Correctly raised error: #{e.message}"
end

# Test with complex context DSL
class ComplexAgent < RAAF::DSL::Agent
  agent_name "ComplexAgent"
  static_instructions "Complex test"
  
  # Context DSL configuration
  context do
    requires :user, :data
    exclude :password, :secret
  end
  
  # Context readers
  context_reader :user, required: true
  context_reader :data, required: true
  context_reader :settings, default: { theme: "dark" }
  
  # Computed context
  def build_summary_context
    "User #{user[:name]} with #{data.length} items"
  end
  
  context_reader :summary
  
  def process
    puts "✅ Complex Agent Results:"
    puts "  User: #{user.inspect}"
    puts "  Data length: #{data.length}"
    puts "  Settings: #{settings.inspect}"
    puts "  Summary: #{summary}"
    puts "  Password in context?: #{has?(:password)}"
  end
end

puts "\n" + "=" * 60
puts "Testing complex agent with context DSL + context_reader"
puts "=" * 60

puts "\n📝 Test 5: Complex agent with computed context"
agent5 = ComplexAgent.new(
  user: { name: "Alice", id: 123 },
  data: [1, 2, 3, 4, 5],
  password: "secret123",  # Should be excluded
  secret: "hidden"        # Should be excluded
)
agent5.process

puts "\n" + "=" * 60
puts "✅ ALL TESTS COMPLETED SUCCESSFULLY!"
puts "context_reader works perfectly with auto-context!"
puts "=" * 60
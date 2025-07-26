#!/usr/bin/env ruby
# frozen_string_literal: true

# Multi-Agent Example
#
# This example demonstrates how to create multiple agents that can
# hand off conversations to each other using the RAAF DSL.

require_relative "../lib/raaf-dsl"

# Create a customer support agent
support_agent = RAAF::DSL::AgentBuilder.build do
  name "SupportAgent"
  instructions <<~INSTRUCTIONS
    You are a friendly customer support representative.
    You help with general inquiries, order status, and basic troubleshooting.
    If a customer has technical issues beyond basic troubleshooting,
    transfer them to the technical support specialist.
  INSTRUCTIONS
  model "gpt-4o"
  
  # Add support-specific tools
  tool :check_order_status do |order_id|
    # Simulate order lookup
    {
      order_id: order_id,
      status: ["shipped", "processing", "delivered"].sample,
      tracking_number: "TRK#{rand(100000..999999)}",
      estimated_delivery: (Date.today + rand(1..5)).to_s
    }
  end
  
  tool :create_ticket do |issue_description|
    {
      ticket_id: "TICKET-#{rand(1000..9999)}",
      priority: ["low", "medium", "high"].sample,
      assigned_to: "Support Team",
      status: "open"
    }
  end
end

# Create a technical support specialist agent
tech_agent = RAAF::DSL::AgentBuilder.build do
  name "TechAgent"
  instructions <<~INSTRUCTIONS
    You are a technical support specialist with deep expertise in troubleshooting.
    You handle complex technical issues, system errors, and configuration problems.
    You can access system logs and run diagnostics.
  INSTRUCTIONS
  model "gpt-4o"
  
  # Add technical tools
  tool :check_system_logs do |user_id|
    {
      user_id: user_id,
      last_error: ["Connection timeout", "Authentication failed", "Service unavailable", nil].sample,
      error_count: rand(0..10),
      last_login: (Time.now - rand(0..72) * 3600).to_s
    }
  end
  
  tool :run_diagnostics do |issue_type|
    diagnostics = {
      network: { status: "OK", latency: "#{rand(10..100)}ms", packet_loss: "#{rand(0..5)}%" },
      authentication: { status: ["OK", "FAILED"].sample, last_attempt: Time.now.to_s },
      services: { api: "running", database: "running", cache: ["running", "degraded"].sample }
    }
    
    { issue_type: issue_type, results: diagnostics[issue_type.to_sym] || diagnostics }
  end
end

# Create a sales agent
sales_agent = RAAF::DSL::AgentBuilder.build do
  name "SalesAgent"
  instructions <<~INSTRUCTIONS
    You are a knowledgeable sales representative.
    You help customers with product information, pricing, and special offers.
    You can check inventory and provide quotes.
  INSTRUCTIONS
  model "gpt-4o"
  
  tool :check_inventory do |product_name|
    {
      product: product_name,
      in_stock: [true, false].sample,
      quantity: rand(0..100),
      warehouses: ["East", "West", "Central"].sample(rand(1..3))
    }
  end
  
  tool :generate_quote do |products, quantity|
    base_price = rand(50..500)
    discount = quantity > 10 ? 0.1 : 0
    
    {
      products: products,
      quantity: quantity,
      unit_price: base_price,
      discount: "#{(discount * 100).to_i}%",
      total: (base_price * quantity * (1 - discount)).round(2)
    }
  end
end

# Enable handoffs between agents
support_agent.add_handoff(tech_agent)
support_agent.add_handoff(sales_agent)
tech_agent.add_handoff(support_agent)  # Can transfer back
sales_agent.add_handoff(support_agent)

puts "=== Multi-Agent System Created ==="
puts "\nAgents:"
[support_agent, tech_agent, sales_agent].each do |agent|
  puts "\n#{agent.name}:"
  puts "  Tools: #{agent.tools.map(&:name).join(', ')}"
end

# Create a multi-agent runner
runner = RAAF::Runner.new(
  agent: support_agent,  # Start with support agent
  agents: [support_agent, tech_agent, sales_agent]
)

# Example conversations that might trigger handoffs
puts "\n=== Example 1: Technical Issue ===

result = runner.run(\"My application keeps crashing with error code 500\")

puts \"Conversation flow:\"
result.messages.each do |msg|
  if msg[:role] == \"assistant\" && msg[:content].include?(\"transfer\")
    puts \"  → Handoff detected\"
  end
  puts \"#{msg[:role].upcase}: #{msg[:content]}\"
end

puts "\n=== Example 2: Sales Inquiry ===

result = runner.run(\"I'd like to know the price for 50 units of your premium widgets\")

puts \"Conversation flow:\"
result.messages.each do |msg|
  puts \"#{msg[:role].upcase}: #{msg[:content]}\"
end

# Test direct tool usage
puts "\n=== Direct Tool Testing ==="

puts "\nOrder Status Check:"
order_result = support_agent.tools.find { |t| t.name == "check_order_status" }.call("ORD-12345")
puts "  #{order_result.inspect}"

puts "\nSystem Diagnostics:"
diag_result = tech_agent.tools.find { |t| t.name == "run_diagnostics" }.call("network")
puts "  #{diag_result.inspect}"

puts "\nInventory Check:"
inv_result = sales_agent.tools.find { |t| t.name == "check_inventory" }.call("Premium Widget")
puts "  #{inv_result.inspect}"
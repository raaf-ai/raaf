#!/usr/bin/env ruby
# frozen_string_literal: true

# Multi-Agent Example
#
# This example demonstrates how to create multiple agents that can
# hand off conversations to each other using the RAAF DSL.

require_relative "../../core/lib/raaf-core"
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
  tool :check_order_status do
    parameter :order_id, type: :string, required: true

    execute do |order_id:|
      # Simulate order lookup
      {
        order_id: order_id,
        status: %w[shipped processing delivered].sample,
        tracking_number: "TRK#{rand(100_000..999_999)}",
        estimated_delivery: (Date.today + rand(1..5)).to_s
      }
    end
  end

  tool :create_ticket do
    parameter :issue_description, type: :string, required: true

    execute do |issue_description:|
      {
        ticket_id: "TICKET-#{rand(1000..9999)}",
        priority: %w[low medium high].sample,
        assigned_to: "Support Team",
        status: "open",
        description: issue_description
      }
    end
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
  tool :check_system_logs do
    parameter :user_id, type: :string, required: true

    execute do |user_id:|
      {
        user_id: user_id,
        last_error: ["Connection timeout", "Authentication failed", "Service unavailable", nil].sample,
        error_count: rand(0..10),
        last_login: (Time.now - (rand(0..72) * 3600)).to_s
      }
    end
  end

  tool :run_diagnostics do
    parameter :issue_type, type: :string, required: true

    execute do |issue_type:|
      diagnostics = {
        network: { status: "OK", latency: "#{rand(10..100)}ms", packet_loss: "#{rand(0..5)}%" },
        authentication: { status: %w[OK FAILED].sample, last_attempt: Time.now.to_s },
        services: { api: "running", database: "running", cache: %w[running degraded].sample }
      }

      { issue_type: issue_type, results: diagnostics[issue_type.to_sym] || diagnostics }
    end
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

  tool :check_inventory do
    parameter :product_name, type: :string, required: true

    execute do |product_name:|
      {
        product: product_name,
        in_stock: [true, false].sample,
        quantity: rand(0..100),
        warehouses: %w[East West Central].sample(rand(1..3))
      }
    end
  end

  tool :generate_quote do
    parameter :products, type: :string, required: true
    parameter :quantity, type: :integer, required: true

    execute do |products:, quantity:|
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
end

# Enable handoffs between agents
support_agent.add_handoff(tech_agent)
support_agent.add_handoff(sales_agent)
tech_agent.add_handoff(support_agent) # Can transfer back
sales_agent.add_handoff(support_agent)

puts "=== Multi-Agent System Created ==="
puts "\nAgents:"
[support_agent, tech_agent, sales_agent].each do |agent|
  puts "\n#{agent.name}:"
  puts "  Tools: #{agent.tools.map(&:name).join(', ')}"
end

# Create a runner with the starting agent
# Note: Multi-agent support with handoffs is handled through the agent's add_handoff method
runner = RAAF::Runner.new(agent: support_agent)

# Example conversations that might trigger handoffs
puts "\n=== Example 1: Technical Issue ==="

result = runner.run("My application keeps crashing with error code 500")

puts "\nConversation flow:"
result.messages.each do |msg|
  puts "  → Handoff detected" if msg[:role] == "assistant" && msg[:content].include?("transfer")
  puts "#{msg[:role].upcase}: #{msg[:content]}"
end

puts "\n=== Example 2: Sales Inquiry ==="

result = runner.run("I'd like to know the price for 50 units of your premium widgets")

puts "\nConversation flow:"
result.messages.each do |msg|
  puts "#{msg[:role].upcase}: #{msg[:content]}"
end

# Test direct tool usage
puts "\n=== Direct Tool Testing ==="

# Debug: Show available tools
puts "\nAvailable tools on support_agent:"
support_agent.tools.each { |t| puts "  - #{t.name}" }

puts "\nOrder Status Check:"
order_tool = support_agent.tools.find { |t| t.name == "check_order_status" }
if order_tool
  order_result = order_tool.call(order_id: "ORD-12345")
  puts "  #{order_result.inspect}"
else
  puts "  Tool 'check_order_status' not found"
end

puts "\nSystem Diagnostics:"
diag_tool = tech_agent.tools.find { |t| t.name == "run_diagnostics" }
if diag_tool
  diag_result = diag_tool.call(issue_type: "network")
  puts "  #{diag_result.inspect}"
else
  puts "  Tool 'run_diagnostics' not found"
end

puts "\nInventory Check:"
inv_tool = sales_agent.tools.find { |t| t.name == "check_inventory" }
if inv_tool
  inv_result = inv_tool.call(product_name: "Premium Widget")
  puts "  #{inv_result.inspect}"
else
  puts "  Tool 'check_inventory' not found"
end

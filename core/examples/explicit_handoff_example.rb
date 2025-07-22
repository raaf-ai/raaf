#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating the new explicit handoff system
# This replaces the hook-based handoff with direct function calling

require_relative "../lib/raaf"

# Example 1: Basic Explicit Handoff
puts "=== Example 1: Basic Explicit Handoff ==="

# Create handoff context
handoff_context = RAAF::HandoffContext.new(current_agent: "SearchAgent")

# Create search agent with handoff capability
search_agent = RAAF::Agent.new(
  name: "SearchAgent",
  instructions: <<~INSTRUCTIONS,
    You are a SearchAgent. When you complete your research,#{" "}
    call the handoff_to_companydiscoveryagent function with your findings.
  INSTRUCTIONS
  model: "gpt-4o"
)

# Add handoff tool
handoff_tool = RAAF::HandoffTool.create_handoff_tool(
  target_agent: "CompanyDiscoveryAgent",
  handoff_context: handoff_context,
  data_contract: RAAF::HandoffTool.search_strategies_contract
)
search_agent.add_tool(handoff_tool)

# Create company discovery agent
discovery_agent = RAAF::Agent.new(
  name: "CompanyDiscoveryAgent",
  instructions: <<~INSTRUCTIONS,
    You are a CompanyDiscoveryAgent. When you complete your work,
    call the complete_workflow function with your results.
  INSTRUCTIONS
  model: "gpt-4o"
)

# Add completion tool
completion_tool = RAAF::HandoffTool.create_completion_tool(
  handoff_context: handoff_context,
  data_contract: RAAF::HandoffTool.company_discovery_contract
)
discovery_agent.add_tool(completion_tool)

puts "✅ Created agents with explicit handoff tools"

# Example 2: Using Agent Orchestrator
puts "\n=== Example 2: Agent Orchestrator ==="

# Define agents configuration
agents = {
  "SearchAgent" => {
    name: "SearchAgent",
    class: RAAF::Agent,
    instructions: <<~INSTRUCTIONS,
      You are a SearchAgent specializing in market research.
      When you complete your research, call the handoff function.
    INSTRUCTIONS
    model: "gpt-4o",
    tools: [],
    handoff_tools: [
      {
        target_agent: "CompanyDiscoveryAgent",
        data_contract: RAAF::HandoffTool.search_strategies_contract
      }
    ]
  },
  "CompanyDiscoveryAgent" => {
    name: "CompanyDiscoveryAgent",
    class: RAAF::Agent,
    instructions: <<~INSTRUCTIONS,
      You are a CompanyDiscoveryAgent that finds companies.
      When you complete your work, call the complete_workflow function.
    INSTRUCTIONS
    model: "gpt-4o",
    tools: [],
    terminal: true,
    completion_contract: RAAF::HandoffTool.company_discovery_contract
  }
}

# Create orchestrator
RAAF::AgentOrchestrator.new(agents: agents)

puts "✅ Created orchestrator with #{agents.size} agents"

# Example 3: Simulate Workflow (without actual API calls)
puts "\n=== Example 3: Simulated Workflow ==="

# Simulate handoff context usage
handoff_context = RAAF::HandoffContext.new(current_agent: "SearchAgent")

# Simulate setting handoff
success = handoff_context.set_handoff(
  target_agent: "CompanyDiscoveryAgent",
  data: {
    search_strategies: [
      {
        name: "Industry Leaders",
        queries: ["fintech companies", "payment processors"],
        priority: 1
      },
      {
        name: "Emerging Players",
        queries: ["startup fintech", "new payment companies"],
        priority: 2
      }
    ],
    market_insights: {
      trends: ["digital payments", "crypto adoption"],
      key_players: %w[PayPal Stripe Square],
      market_size: "$100B",
      growth_rate: "15% annually"
    }
  },
  reason: "Search strategies completed"
)

puts "✅ Handoff prepared: #{success}"
puts "   Current agent: #{handoff_context.current_agent}"
puts "   Target agent: #{handoff_context.target_agent}"
puts "   Handoff pending: #{handoff_context.handoff_pending?}"

# Execute handoff
handoff_result = handoff_context.execute_handoff
puts "✅ Handoff executed: #{handoff_result[:success]}"
puts "   New current agent: #{handoff_result[:current_agent]}"
puts "   Previous agent: #{handoff_result[:previous_agent]}"

# Build handoff message
handoff_message = handoff_context.build_handoff_message
puts "✅ Handoff message built (#{handoff_message.length} characters)"
puts "   Preview: #{handoff_message[0..100]}..."

# Example 4: Structured Data Contracts
puts "\n=== Example 4: Structured Data Contracts ==="

# Show search strategies contract
search_contract = RAAF::HandoffTool.search_strategies_contract
puts "✅ Search strategies contract:"
puts "   Required fields: #{search_contract[:required]}"
puts "   Properties: #{search_contract[:properties].keys}"

# Show company discovery contract
company_contract = RAAF::HandoffTool.company_discovery_contract
puts "✅ Company discovery contract:"
puts "   Required fields: #{company_contract[:required]}"
puts "   Properties: #{company_contract[:properties].keys}"

# Example 5: Tool Creation
puts "\n=== Example 5: Tool Creation ==="

context = RAAF::HandoffContext.new

# Create handoff tool
handoff_tool = RAAF::HandoffTool.create_handoff_tool(
  target_agent: "AnalysisAgent",
  handoff_context: context,
  data_contract: {
    type: "object",
    properties: {
      data: { type: "object" },
      summary: { type: "string" }
    },
    required: ["data"]
  }
)

puts "✅ Created handoff tool:"
puts "   Name: #{handoff_tool.name}"
puts "   Description: #{handoff_tool.description}"
puts "   Parameters: #{handoff_tool.parameters[:properties].keys}"

# Create completion tool
completion_tool = RAAF::HandoffTool.create_completion_tool(
  handoff_context: context
)

puts "✅ Created completion tool:"
puts "   Name: #{completion_tool.name}"
puts "   Description: #{completion_tool.description}"
puts "   Parameters: #{completion_tool.parameters[:properties].keys}"

puts "\n🎉 Explicit handoff system examples completed!"
puts "\nKey Benefits:"
puts "- ✅ Direct function calling instead of conversation parsing"
puts "- ✅ Structured data contracts for type safety"
puts "- ✅ Explicit orchestration with clear control flow"
puts "- ✅ Immediate feedback and error handling"
puts "- ✅ No hook dependencies or global state"

puts "\nNext Steps:"
puts "1. Replace existing handoff usage with explicit handoff system"
puts "2. Define data contracts for your specific use cases"
puts "3. Create orchestrator configurations for your workflows"
puts "4. Test with actual API calls using your agents"

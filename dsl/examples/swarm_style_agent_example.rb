#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../../core/lib/raaf-core"
require_relative "../lib/raaf-dsl"

# Example demonstrating OpenAI Swarm-style context variables and debugging
# This example shows how to:
# 1. Create agents with Swarm-style context variables
# 2. Use comprehensive debugging features
# 3. Handle context updates from tools
# 4. Visualize multi-agent workflows

puts "🔄 AI Agent DSL - OpenAI Swarm-Style Context Variables Demo"
puts "=" * 70
puts

# ========================================
# EXAMPLE TOOLS WITH CONTEXT SUPPORT
# ========================================

# Example tool that analyzes requests and updates context
class AnalyzeRequestTool < RAAF::DSL::Tools::Base
  def tool_name
    "analyze_request"
  end

  def build_tool_definition
    {
      type: "function",
      function: {
        name: tool_name,
        description: "Analyze a customer request and determine priority and category",
        parameters: {
          type: "object",
          properties: {
            request: {
              type: "string",
              description: "The customer request to analyze"
            }
          },
          required: ["request"],
          additionalProperties: false
        }
      }
    }
  end

  # NEW: Swarm-style tool implementation with context variables
  def execute_tool_implementation_with_context(params, context_variables)
    request = params["request"]

    # Access context variables (Swarm-style)
    context_variables&.get(:session_id)
    context_variables&.get(:customer_tier, "standard")

    # Simulate request analysis
    priority = case request.downcase
               when /urgent|emergency|critical/
                 "high"
               when /important|asap/
                 "medium"
               else
                 "low"
               end

    category = case request.downcase
               when /refund|money|charge|payment/
                 "billing"
               when /error|bug|broken|crash/
                 "technical"
               when /account|login|password/
                 "account"
               else
                 "general"
               end

    # Return result with context updates (Swarm-style)
    {
      analysis: {
        priority: priority,
        category: category,
        request_length: request.length,
        keywords: extract_keywords(request)
      },
      # Context updates that will be merged automatically
      context_updates: {
        request_analyzed: true,
        analysis_priority: priority,
        analysis_category: category,
        analyzed_at: Time.current.iso8601,
        analysis_count: (context_variables&.get(:analysis_count, 0) || 0) + 1
      }
    }
  end

  private

  def extract_keywords(request)
    # Simple keyword extraction
    words = request.downcase.split(/\W+/)
    important_words = words.select { |w| w.length > 4 }
    important_words.first(5)
  end
end

# Example tool that routes to appropriate specialist
class RouteToSpecialistTool < RAAF::DSL::Tools::Base
  def tool_name
    "route_to_specialist"
  end

  def build_tool_definition
    {
      type: "function",
      function: {
        name: tool_name,
        description: "Route customer to appropriate specialist based on analysis",
        parameters: {
          type: "object",
          properties: {},
          additionalProperties: false
        }
      }
    }
  end

  def execute_tool_implementation_with_context(_params, context_variables)
    category = context_variables&.get(:analysis_category, "general")
    priority = context_variables&.get(:analysis_priority, "low")

    # Determine routing
    specialist = case category
                 when "billing"
                   "BillingSpecialist"
                 when "technical"
                   "TechnicalSupport"
                 when "account"
                   "AccountSpecialist"
                 else
                   "GeneralSupport"
                 end

    # Return routing decision with context updates
    {
      routing: {
        specialist: specialist,
        category: category,
        priority: priority,
        escalated: priority == "high"
      },
      context_updates: {
        routed_to: specialist,
        routing_decision_made: true,
        routed_at: Time.current.iso8601,
        escalated: priority == "high"
      }
    }
  end
end

# ========================================
# EXAMPLE AGENTS WITH SWARM SUPPORT
# ========================================

# Triage agent that analyzes requests and routes them
class TriageAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::Agents::AgentDsl

  agent_name "TriageAgent"
  model "gpt-4o-mini" # Use cheaper model for triage
  max_turns 3

  uses_tool :analyze_request
  uses_tool :route_to_specialist

  def build_instructions
    <<~INSTRUCTIONS
      You are a customer service triage agent. Your job is to:

      1. Analyze incoming customer requests using the analyze_request tool
      2. Route customers to appropriate specialists using the route_to_specialist tool

      Always use both tools in sequence for every request.
      Be helpful and professional in your responses.
    INSTRUCTIONS
  end

  def build_user_prompt
    # Access context variables in prompt building
    session_id = @context_variables.get(:session_id)
    customer_name = @context_variables.get(:customer_name, "Customer")

    <<~PROMPT
      New customer request for session #{session_id}:
      Customer: #{customer_name}

      Please analyze this request and route the customer appropriately.
    PROMPT
  end
end

# Specialist agent that handles routed requests
class SpecialistAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::Agents::AgentDsl

  agent_name "SpecialistAgent"
  model "gpt-4o-mini"
  max_turns 2

  def build_instructions
    specialist_type = @context_variables.get(:routed_to, "GeneralSupport")

    <<~INSTRUCTIONS
      You are a #{specialist_type} handling customer requests.

      Based on the triage analysis, provide appropriate assistance.
      Be specific and helpful based on your specialization.
    INSTRUCTIONS
  end

  def build_user_prompt
    category = @context_variables.get(:analysis_category, "general")
    priority = @context_variables.get(:analysis_priority, "low")

    <<~PROMPT
      Handle this #{category} request with #{priority} priority.
      Provide appropriate assistance based on the triage analysis.
    PROMPT
  end
end

# ========================================
# DEMO EXECUTION
# ========================================

def run_swarm_demo
  puts "🚀 Starting Swarm-style multi-agent workflow demo..."
  puts

  # Create SwarmDebugger for comprehensive debugging
  debugger = RAAF::DSL::SwarmDebugger.new(enabled: true)

  # Start debugging session
  initial_context = RAAF::DSL::ContextVariables.new({
                                                      session_id: "demo-#{Time.current.strftime('%H%M%S')}",
                                                      customer_name: "Alice Johnson",
                                                      customer_tier: "premium",
                                                      workflow_step: "triage"
                                                    }, debug: true)

  debugger.start_workflow_session(
    "Customer Support Triage",
    initial_context: initial_context,
    metadata: { demo: true, version: "1.0" }
  )

  begin
    # Step 1: Triage Agent
    puts "📋 STEP 1: TRIAGE AGENT"
    puts "-" * 40

    triage_agent = TriageAgent.new(
      context: {
        document: { name: "customer_request", description: "Support ticket" },
        customer_request: "URGENT: My payment failed and I can't access my account!"
      },
      processing_params: {
        content_type: "customer_support",
        priority: "auto-detect"
      },
      context_variables: initial_context,
      debug: true
    )

    # Execute triage with debugging
    triage_result = debugger.debug_agent_execution(triage_agent, initial_context) do
      triage_agent.run(input_context_variables: initial_context)
    end

    updated_context = triage_result[:context_variables]

    # Step 2: Context Evolution Tracking
    debugger.debug_context_evolution(
      "After Triage Analysis",
      before_context: initial_context,
      after_context: updated_context,
      operation: "Request analysis and routing"
    )

    # Step 3: Handoff Decision
    specialist_context = updated_context.update(workflow_step: "specialist_handling")

    specialist_agent = SpecialistAgent.new(
      context: {
        document: { name: "analyzed_request", description: "Triaged support ticket" }
      },
      processing_params: {
        content_type: "specialist_support"
      },
      context_variables: specialist_context,
      debug: true
    )

    # Debug handoff decision
    debugger.debug_handoff_decision(
      from_agent: triage_agent,
      to_agent: specialist_agent,
      context_variables: specialist_context,
      reason: "Request analysis complete, routing to #{specialist_context.get(:routed_to)}"
    )

    # Step 4: Specialist Agent
    puts "\n📋 STEP 2: SPECIALIST AGENT"
    puts "-" * 40

    specialist_result = debugger.debug_agent_execution(specialist_agent, specialist_context) do
      specialist_agent.run(input_context_variables: specialist_context)
    end

    final_context = specialist_result[:context_variables]

    # Step 5: Final Context Evolution
    debugger.debug_context_evolution(
      "Workflow Complete",
      before_context: specialist_context,
      after_context: final_context,
      operation: "Specialist handling complete"
    )

    puts "\n🎉 WORKFLOW COMPLETED SUCCESSFULLY!"
    puts "=" * 40
    puts "Final Context Variables:"
    puts final_context.debug_info(include_history: true)
  rescue StandardError => e
    puts "\n❌ DEMO ERROR: #{e.message}"
    puts "Backtrace: #{e.backtrace.first(3).join(', ')}"
  ensure
    # End debugging session
    debugger.end_workflow_session

    puts "\n📊 FINAL DEBUG REPORT:"
    puts debugger.generate_debug_report(include_trace: true)
  end
end

def run_interactive_demo
  puts "\n🐛 Starting Interactive Debug Session..."
  puts "(This would start an interactive session in a real environment)"

  # Create example agent for interactive debugging
  agent = TriageAgent.new(
    context: { document: { name: "test" } },
    processing_params: { content_type: "demo" },
    context_variables: RAAF::DSL::ContextVariables.new(session_id: "interactive-demo"),
    debug: true
  )

  RAAF::DSL::SwarmDebugger.new(enabled: true)

  puts "In a real environment, you would now have an interactive session with commands like:"
  puts "  - context: Show current context variables"
  puts "  - prompt: Show agent prompts"
  puts "  - run: Execute agent"
  puts "  - trace: Show execution trace"
  puts "  - quit: Exit"
  puts
  puts "For this demo, we'll just show the debug info:"
  puts agent.context_variables.debug_info
end

def show_context_features_demo
  puts "\n🔍 CONTEXT VARIABLES FEATURES DEMO"
  puts "=" * 50

  # Create initial context
  context = RAAF::DSL::ContextVariables.new({
                                              session_id: "demo-123",
                                              user: "alice",
                                              tier: "premium"
                                            }, debug: true)

  puts "1. Initial Context:"
  puts context.debug_info
  puts

  # Update context (immutable)
  updated = context.update(step: "analysis", priority: "high")
  puts "2. After Update (original unchanged):"
  puts "Original has :step? #{context.has?(:step)}"
  puts "Updated has :step? #{updated.has?(:step)} (value: #{updated.get(:step)})"
  puts

  # Show context diff
  puts "3. Context Diff:"
  diff = context.diff(updated)
  puts "Changes: #{diff[:summary]}"
  puts "Added: #{diff[:added]}"
  puts

  # Context serialization
  puts "4. JSON Serialization:"
  json = updated.to_json
  puts "JSON: #{json}"

  restored = RAAF::DSL::ContextVariables.from_json(json, debug: true)
  puts "Restored identical? #{updated.to_h == restored.to_h}"
  puts
end

# ========================================
# MAIN DEMO
# ========================================

if __FILE__ == $PROGRAM_NAME
  begin
    puts "Choose demo to run:"
    puts "1. Full Swarm-style workflow with debugging"
    puts "2. Interactive debug session (simulated)"
    puts "3. Context variables features"
    puts "4. All demos"
    print "Enter choice (1-4): "

    choice = gets.chomp

    case choice
    when "1"
      run_swarm_demo
    when "2"
      run_interactive_demo
    when "3"
      show_context_features_demo
    when "4"
      run_swarm_demo
      puts "\n#{'=' * 70}"
      run_interactive_demo
      puts "\n#{'=' * 70}"
      show_context_features_demo
    else
      puts "Invalid choice, running full demo..."
      run_swarm_demo
    end
  rescue Interrupt
    puts "\n\n👋 Demo interrupted by user"
  rescue StandardError => e
    puts "\n❌ Demo failed: #{e.message}"
    puts "Backtrace:"
    puts e.backtrace.first(5).join("\n")
  end

  puts "\n🎉 Demo complete! Check the output above for debugging information."
end

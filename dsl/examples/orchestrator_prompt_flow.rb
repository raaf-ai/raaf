#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/raaf-dsl"

# Example showing how Orchestrator < ApplicationAgent uses prompt classes

# 1. Define the base ApplicationAgent class
class ApplicationAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::Agents::AgentDsl
end

# 2. Define the Orchestrator that inherits from ApplicationAgent
class Orchestrator < ApplicationAgent
  agent_name "orchestrator"

  def agent_name
    "Workflow Orchestrator"
  end
end

# 3. Define the corresponding prompt class (auto-inferred by naming convention)
module RAAF
  module DSL
    module Prompts
      class Orchestrator < RAAF::DSL::Prompts::Base
        def system
          <<~SYSTEM
            You are a workflow orchestrator responsible for coordinating multiple AI agents.

            Your role is to:
            - Analyze incoming requests and break them down into subtasks
            - Determine which agents should handle each subtask
            - Coordinate the execution sequence
            - Combine results from multiple agents into a cohesive response

            Agent Name: #{agent_name}
            Processing Context: #{@context.inspect}
          SYSTEM
        end

        def user
          <<~USER
            Please orchestrate the following workflow:

            Request: #{@context[:request] || 'No specific request provided'}

            Available agents: #{@processing_params[:available_agents]&.join(', ') || 'None specified'}

            Provide a step-by-step execution plan with agent assignments.
          USER
        end
      end
    end
  end
end

# 4. Demonstration of the complete flow
puts "🔄 ORCHESTRATOR PROMPT FLOW DEMONSTRATION"
puts "=" * 60
puts

# Create orchestrator instance
context = {
  request: "Analyze market trends and generate a report",
  user_id: 123,
  project: "Market Analysis Q4"
}

processing_params = {
  available_agents: %w[MarketResearchAgent DataAnalysisAgent ReportGeneratorAgent],
  priority: "high"
}

orchestrator = Orchestrator.new(
  context: context,
  processing_params: processing_params
)

puts "📋 INHERITANCE CHAIN:"
puts "  #{orchestrator.class.name}"
orchestrator.class.ancestors.each_with_index do |ancestor, index|
  next if ancestor == orchestrator.class

  puts "  #{'  ' * (index + 1)}< #{ancestor.name}" if ancestor.is_a?(Class)
  break if ancestor == RAAF::DSL::Agents::Base
end
puts

puts "🔍 PROMPT RESOLUTION ANALYSIS:"
orchestrator.debug_prompt_flow

puts "\n#{'=' * 60}"
puts "📤 ACTUAL PROMPT OUTPUT:"
puts "=" * 60

begin
  puts "\n🤖 SYSTEM PROMPT:"
  puts "-" * 40
  system_prompt = orchestrator.build_instructions
  puts system_prompt

  puts "\n👤 USER PROMPT:"
  puts "-" * 40
  user_prompt = orchestrator.build_user_prompt
  puts user_prompt
rescue RAAF::DSL::Error => e
  puts "❌ CONFIGURATION ERROR: #{e.message}"
end

puts "\n#{'=' * 60}"
puts "✅ DEMONSTRATION COMPLETE"
puts "=" * 60

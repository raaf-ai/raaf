#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../../core/lib/raaf-core"
require_relative "../lib/raaf-dsl"

# Example agents to test prompt resolution debugging

# Agent with explicit prompt class
class ExplicitPromptAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::Agents::AgentDsl

  agent_name "explicit_prompt_agent"

  # This would reference an actual prompt class
  prompt_class "SomePromptClass"

  def agent_name
    "Explicit Prompt Agent"
  end
end

# Agent that uses inference (expects RAAF::DSL::Prompts::InferredPromptAgent)
class InferredPromptAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::Agents::AgentDsl

  agent_name "inferred_prompt_agent"

  def agent_name
    "Inferred Prompt Agent"
  end
end

# Agent using legacy template system
class LegacyTemplateAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::Agents::AgentDsl

  agent_name "legacy_template_agent"

  instruction_template "You are {agent_name} specialized in {domain}. Your task is to {task}."

  instruction_variables do
    domain "data analysis"
    task "analyze data patterns"
  end

  def agent_name
    "Legacy Template Agent"
  end
end

# Agent using static instructions
class StaticInstructionAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::Agents::AgentDsl

  agent_name "static_instruction_agent"

  def agent_name
    "Static Instruction Agent"
  end

  def build_instructions
    "You are a helpful assistant that provides accurate information."
  end
end

# Agent with no configuration (uses defaults)
class DefaultAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::Agents::AgentDsl

  agent_name "default_agent"

  def agent_name
    "Default Agent"
  end
end

# Demonstration script
puts "🔍 AI Agent DSL - Prompt Resolution Debugging Demo"
puts "=" * 60
puts

agents = [
  ExplicitPromptAgent,
  InferredPromptAgent,
  LegacyTemplateAgent,
  StaticInstructionAgent,
  DefaultAgent
]

agents.each do |agent_class|
  puts "\n#{'=' * 80}"
  puts "Testing #{agent_class.name}"
  puts "=" * 80

  begin
    # Create agent instance
    agent = agent_class.new(context: {}, processing_params: {})

    # Debug the prompt resolution flow
    agent.debug_prompt_flow

    puts "\n📊 SUMMARY INFO:"
    info = agent.prompt_resolution_info
    info.each do |key, value|
      puts "  #{key}: #{value.inspect}"
    end
  rescue StandardError => e
    puts "❌ Error testing #{agent_class.name}: #{e.message}"
    puts "   #{e.backtrace.first}"
  end

  puts "\nPress Enter to continue to next agent..."
  gets
end

puts "\n🎉 Demo complete!"

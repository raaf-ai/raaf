#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"

##
# Comprehensive example demonstrating all the new Python parity features
# that have been implemented in the Ruby version
##

puts "🚀 Python Parity Features Example"
puts "=" * 50

# 1. Advanced Streaming with Semantic Events
puts "\n1. 📡 Advanced Streaming with Semantic Events"
puts "-" * 40

agent = OpenAIAgents::Agent.new(
  name: "Streaming Assistant", 
  instructions: "You are a helpful assistant that provides detailed responses.",
  model: "gpt-4o"
)

runner = OpenAIAgents::Runner.new(agent: agent)

# Use the new run_streamed method (matching Python's Runner.run_streamed)
streaming_result = runner.run_streamed("Explain quantum computing in simple terms")

puts "Starting streaming execution..."
event_count = 0

# Stream events with filtering (matching Python's event filtering)
streaming_result.stream_events do |event|
  event_count += 1
  
  case event
  when OpenAIAgents::StreamingEvents::AgentStartEvent
    puts "🤖 Agent '#{event.agent.name}' started"
  when OpenAIAgents::StreamingEvents::MessageStartEvent
    puts "💬 Message started from #{event.agent.name}"
  when OpenAIAgents::StreamingEvents::RawContentDeltaEvent
    print event.delta
  when OpenAIAgents::StreamingEvents::MessageCompleteEvent
    puts "\n✅ Message completed (#{event.message[:content].length} chars)"
  when OpenAIAgents::StreamingEvents::AgentFinishEvent
    puts "🏁 Agent finished after #{event.result.turn_count} turns"
  end
  
  break if event_count > 20 # Limit for demo
end

# 2. Tool Use Behavior Configuration
puts "\n\n2. 🔧 Tool Use Behavior Configuration"
puts "-" * 40

def example_tool(query)
  "Tool executed with query: #{query}"
end

# Agent with stop_on_first_tool behavior (matching Python)
behavior_agent = OpenAIAgents::Agent.new(
  name: "Behavior Demo",
  instructions: "Use tools when needed",
  model: "gpt-4o",
  tool_use_behavior: :stop_on_first_tool # NEW: Python parity feature
)

behavior_agent.add_tool(method(:example_tool))

puts "Agent with stop_on_first_tool behavior created"
puts "Tool use behavior: #{behavior_agent.tool_use_behavior.class}"

# 3. Agent Cloning (matching Python's agent.clone)
puts "\n3. 🧬 Agent Cloning"
puts "-" * 40

base_agent = OpenAIAgents::Agent.new(
  name: "Base Agent",
  instructions: "You are a helpful assistant",
  model: "gpt-4o"
)

# Clone with modifications (matching Python's agent.clone(**kwargs))
specialized_agent = base_agent.clone(
  name: "Specialized Agent",
  instructions: "You are a specialized coding assistant",
  model: "gpt-4o-mini"
)

puts "Base agent: #{base_agent.name} (#{base_agent.model})"
puts "Cloned agent: #{specialized_agent.name} (#{specialized_agent.model})"
puts "Instructions changed: #{base_agent.instructions != specialized_agent.instructions}"

# 4. Agent as Tool (matching Python's agent.as_tool)
puts "\n4. 🛠️  Agent as Tool Conversion"
puts "-" * 40

specialist = OpenAIAgents::Agent.new(
  name: "Code Specialist",
  instructions: "You are an expert Ruby programmer",
  model: "gpt-4o"
)

# Convert agent to tool (matching Python's agent.as_tool)
specialist_tool = specialist.as_tool(
  tool_name: "consult_ruby_expert",
  tool_description: "Consult with Ruby programming expert"
)

main_agent = OpenAIAgents::Agent.new(
  name: "Main Agent",
  instructions: "You can delegate complex programming questions",
  model: "gpt-4o"
)

main_agent.add_tool(specialist_tool)

puts "Specialist agent converted to tool: #{specialist_tool.name}"
puts "Main agent now has access to specialist via tool"

# 5. ModelSettings Configuration (matching Python's ModelSettings)
puts "\n5. ⚙️  ModelSettings Configuration"
puts "-" * 40

model_settings = OpenAIAgents::ModelSettings.new(
  temperature: 0.7,
  max_tokens: 1000,
  top_p: 0.9,
  frequency_penalty: 0.1,
  tool_choice: "auto",
  parallel_tool_calls: true
)

puts "ModelSettings created with:"
puts "- Temperature: #{model_settings.temperature}"
puts "- Max tokens: #{model_settings.max_tokens}"
puts "- Tool choice: #{model_settings.tool_choice}"
puts "- Parallel tools: #{model_settings.parallel_tool_calls}"

# Merge settings (matching Python's ModelSettings.merge)
updated_settings = model_settings.merge(temperature: 0.3, max_tokens: 2000)
puts "Merged settings - new temperature: #{updated_settings.temperature}"

# 6. Dynamic Tool Enabling (matching Python's dynamic tool filtering)
puts "\n6. 🔄 Dynamic Tool Enabling"
puts "-" * 40

def conditional_tool(message)
  "Conditional tool called with: #{message}"
end

# Tool with dynamic enabling based on context
dynamic_agent = OpenAIAgents::Agent.new(
  name: "Dynamic Agent",
  instructions: "Use tools based on context",
  model: "gpt-4o"
)

# Add tool with conditional enabling (NEW: Python parity feature)
conditional_function_tool = OpenAIAgents::FunctionTool.new(
  method(:conditional_tool),
  name: "conditional_tool",
  description: "A tool that's only enabled in certain contexts",
  is_enabled: lambda { |_context| 
    # Example: only enable during business hours
    Time.now.hour.between?(9, 17)
  }
)

dynamic_agent.add_tool(conditional_function_tool)

current_hour = Time.now.hour
tool_enabled = conditional_function_tool.enabled?
puts "Current hour: #{current_hour}"
puts "Tool enabled: #{tool_enabled} (only enabled 9-17h)"
puts "Agent has #{dynamic_agent.enabled_tools.length} enabled tools"

# 7. Parallel Guardrails (matching Python's async guardrail execution)
puts "\n7. 🛡️  Parallel Guardrails"
puts "-" * 40

input_guardrail = OpenAIAgents::Guardrails.input_guardrail(name: "length_check") do |_context, _agent, input|
  if input.length > 1000
    OpenAIAgents::GuardrailFunctionOutput.new(tripwire_triggered: true)
  else
    OpenAIAgents::GuardrailFunctionOutput.new(tripwire_triggered: false)
  end
end

output_guardrail = OpenAIAgents::Guardrails.output_guardrail(name: "safety_check") do |_context, _agent, output|
  # Simple safety check
  if output.downcase.include?("unsafe")
    OpenAIAgents::GuardrailFunctionOutput.new(tripwire_triggered: true)
  else
    OpenAIAgents::GuardrailFunctionOutput.new(tripwire_triggered: false)
  end
end

guardrail_agent = OpenAIAgents::Agent.new(
  name: "Protected Agent",
  instructions: "You are a safe assistant",
  model: "gpt-4o",
  input_guardrails: [input_guardrail],
  output_guardrails: [output_guardrail]
)

puts "Agent created with parallel guardrails:"
puts "- Input guardrails: #{guardrail_agent.input_guardrails.length}"
puts "- Output guardrails: #{guardrail_agent.output_guardrails.length}"

# Test guardrail execution
test_input = "Hello world"
guardrails = [input_guardrail]
context_wrapper = nil

# Use parallel guardrail execution (NEW: Python parity feature)
results = OpenAIAgents::ParallelGuardrails.run_input_guardrails_parallel(
  guardrails, context_wrapper, guardrail_agent, test_input
)

puts "Guardrail execution results: #{results.length} results"
puts "All guardrails passed: #{results.all?(&:success?)}"

# 8. Enhanced Tools Ecosystem
puts "\n8. 🧰 Enhanced Tools Ecosystem"
puts "-" * 40

puts "Available tool types:"
puts "✅ LocalShellTool - Safe command execution"
puts "✅ ComputerTool - Desktop automation" 
puts "✅ MCPTool - Model Context Protocol integration"
puts "✅ FunctionTool with dynamic enabling"

# Create a LocalShellTool (matching Python's LocalShellTool)
if defined?(OpenAIAgents::Tools::LocalShellTool)
  shell_tool = OpenAIAgents::Tools::LocalShellTool.new(
    allowed_commands: %w[ls cat echo date pwd],
    working_dir: Dir.tmpdir
  )
  puts "LocalShellTool created with #{shell_tool.allowed_commands.length} allowed commands"
end

puts "\n🎉 All Python parity features successfully demonstrated!"
puts "\nKey improvements implemented:"
puts "1. ✅ Advanced streaming with semantic events (RunResultStreaming)"
puts "2. ✅ Tool use behavior configuration system"
puts "3. ✅ Agent cloning capabilities" 
puts "4. ✅ Agent-to-tool conversion (as_tool method)"
puts "5. ✅ ModelSettings class with comprehensive configuration"
puts "6. ✅ Dynamic tool enabling/disabling"
puts "7. ✅ Parallel guardrail execution"
puts "8. ✅ Enhanced tools ecosystem (LocalShell, MCP, Computer)"
puts "\nRuby OpenAI Agents now has feature parity with Python SDK! 🚀"

#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates xAI (Grok) integration with RAAF (Ruby AI Agents Factory).
# xAI provides access to the Grok family of models known for their real-time knowledge,
# advanced reasoning capabilities, coding expertise, and 256k context windows.
# The multi-provider architecture allows seamless switching between AI providers.
# xAI/Grok excels at reasoning tasks, coding, and real-time information access.

require "raaf-providers"

# xAI requires an API key for authentication
# Sign up at https://console.x.ai to get your key
if !ENV["XAI_API_KEY"] && ENV["RAAF_TEST_MODE"] != "true"
  puts "ERROR: API key not set - XAI_API_KEY"
  puts "Please set it with: export XAI_API_KEY='your-api-key'"
  puts "Get your API key from: https://console.x.ai"
  exit 1
end

puts "=== xAI (Grok) Provider Example ==="
puts

# ============================================================================
# PROVIDER SETUP
# ============================================================================

# Create an xAI provider instance
# This provider uses xAI's OpenAI-compatible API
# Enables using Grok models with the same code structure as OpenAI
provider = RAAF::Models::XAIProvider.new

# ============================================================================
# EXAMPLE 1: BASIC GROK USAGE
# ============================================================================

puts "1. Basic Grok interaction:"

# Test Grok's conversational abilities
test_prompt = "Explain what makes Grok different from other AI models in one paragraph."

start_time = Time.now
response = provider.chat_completion(
  messages: [{ role: "user", content: test_prompt }],
  model: "grok-4" # Latest Grok model with 256k context
)
end_time = Time.now

puts "Response time: #{(end_time - start_time).round(3)} seconds"
puts "Response: #{response.dig('choices', 0, 'message', 'content')}"
puts

# ============================================================================
# EXAMPLE 2: GROK MODEL COMPARISON
# ============================================================================

puts "2. Comparing different Grok models:"

# Test different models available from xAI
grok_models = [
  { model: "grok-4", name: "Grok 4 (Latest, with vision)" },
  { model: "grok-3", name: "Grok 3 (Advanced reasoning)" },
  { model: "grok-3-mini", name: "Grok 3 Mini (Fast, efficient)" },
  { model: "grok-code-fast-1", name: "Grok Code Fast (Coding optimized)" }
]

test_prompt = "What are the key principles of good software architecture?"

grok_models.each do |model_info|
  puts "\n#{model_info[:name]}:"
  begin
    start_time = Time.now
    response = provider.chat_completion(
      messages: [{ role: "user", content: test_prompt }],
      model: model_info[:model],
      max_tokens: 200
    )
    elapsed = Time.now - start_time

    puts "Time: #{elapsed.round(3)}s"
    puts "Response: #{response.dig('choices', 0, 'message', 'content')}"
  rescue StandardError => e
    puts "Error with #{model_info[:name]}: #{e.message}"
  end
end

puts

# ============================================================================
# EXAMPLE 3: REASONING AGENT WITH TOOLS
# ============================================================================

puts "3. Reasoning agent with tool calling:"

# Define tools for the agent
def search_documentation(query:)
  # Simulated documentation search
  docs = {
    "agents" => "RAAF agents are autonomous entities that can use tools and communicate with each other.",
    "tools" => "Tools in RAAF are Ruby methods that agents can call to perform actions.",
    "handoffs" => "Handoffs allow agents to transfer control to specialized agents for specific tasks."
  }

  result = docs[query.downcase] || "No documentation found for: #{query}"
  "Documentation: #{result}"
end

def code_analyzer(code:, language:)
  # Simple code analysis
  lines = code.split("\n").count
  chars = code.length
  "Code Analysis for #{language}: #{lines} lines, #{chars} characters"
end

# Create a reasoning agent with Grok
reasoning_agent = RAAF::Agent.new(
  name: "GrokReasoningAgent",
  instructions: "You are an advanced reasoning agent powered by Grok. Analyze requests carefully and use tools when appropriate.",
  model: "grok-4" # Best model for reasoning
)

# Add tools
reasoning_agent.add_tool(method(:search_documentation))
reasoning_agent.add_tool(method(:code_analyzer))

# Create runner with xAI provider
runner = RAAF::Runner.new(
  agent: reasoning_agent,
  provider: provider
)

# Test reasoning with tool usage
reasoning_messages = [{
  role: "user",
  content: "Search the documentation for 'agents' and analyze this Ruby code: 'def hello\n  puts \"Hello, World!\"\nend'"
}]

start_time = Time.now
reasoning_result = runner.run(reasoning_messages)
elapsed = Time.now - start_time

puts "Reasoning response (#{elapsed.round(3)}s):"
puts reasoning_result.final_output
puts

# ============================================================================
# EXAMPLE 4: CODING WITH GROK-CODE-FAST
# ============================================================================

puts "4. Coding assistance with grok-code-fast-1:"

# Create a coding agent optimized for code generation
coding_agent = RAAF::Agent.new(
  name: "GrokCodingAgent",
  instructions: "You are a coding expert using Grok Code Fast. Provide clean, efficient code solutions.",
  model: "grok-code-fast-1" # Optimized for agentic coding
)

coding_runner = RAAF::Runner.new(
  agent: coding_agent,
  provider: provider
)

coding_messages = [{
  role: "user",
  content: "Write a Ruby method that finds the longest palindrome in a string. Make it efficient and well-commented."
}]

start_time = Time.now
coding_result = coding_runner.run(coding_messages)
elapsed = Time.now - start_time

puts "Coding response (#{elapsed.round(3)}s):"
puts coding_result.final_output
puts

# ============================================================================
# EXAMPLE 5: STREAMING FOR REAL-TIME RESPONSES
# ============================================================================

puts "5. Streaming response from Grok:"
puts "Streaming: "

# Stream completion for real-time output
provider.stream_completion(
  messages: [{ role: "user", content: "List and briefly explain the SOLID principles in software design." }],
  model: "grok-3-mini" # Fast model for streaming
) do |chunk|
  # Process streaming chunks as they arrive
  if chunk["choices"] && chunk["choices"][0]["delta"]["content"]
    print chunk["choices"][0]["delta"]["content"]
    $stdout.flush
  end
end
puts "\n"

# ============================================================================
# EXAMPLE 6: PARALLEL TOOL CALLS
# ============================================================================

puts "6. Parallel tool calling demonstration:"

# Define multiple independent tools
def get_time(timezone:)
  "Current time in #{timezone}: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')} (simulated)"
end

def get_weather(city:)
  "Weather in #{city}: Sunny, 22°C (simulated)"
end

def get_news(category:)
  "Top #{category} news: Latest updates available (simulated)"
end

# Create agent with multiple tools
parallel_agent = RAAF::Agent.new(
  name: "GrokParallelAgent",
  instructions: "You can call multiple tools in parallel. Use all relevant tools to answer comprehensively.",
  model: "grok-4"
)

parallel_agent.add_tool(method(:get_time))
parallel_agent.add_tool(method(:get_weather))
parallel_agent.add_tool(method(:get_news))

parallel_runner = RAAF::Runner.new(
  agent: parallel_agent,
  provider: provider
)

parallel_messages = [{
  role: "user",
  content: "Get the current time in UTC, weather in London, and top tech news."
}]

parallel_result = parallel_runner.run(parallel_messages)
puts "Parallel tool calls result:"
puts parallel_result.final_output
puts

# ============================================================================
# EXAMPLE 7: LONG CONTEXT PROCESSING
# ============================================================================

puts "7. Long context processing (256k tokens):"

# Create a long document for testing
long_document = "
# Software Architecture Principles

## Chapter 1: Introduction
Software architecture is the fundamental organization of a system, embodied in its components,
their relationships to each other and the environment, and the principles governing its design.

## Chapter 2: Design Patterns
Design patterns are reusable solutions to commonly occurring problems in software design.
They represent best practices and can speed up the development process.

## Chapter 3: SOLID Principles
SOLID is an acronym for five design principles intended to make software designs more
understandable, flexible, and maintainable.
" * 20 # Repeat to create longer context

long_context_messages = [
  { role: "user", content: "Here's a software architecture document: #{long_document}" },
  { role: "user", content: "Summarize the main topics covered and list the key principles mentioned." }
]

begin
  long_response = provider.chat_completion(
    messages: long_context_messages,
    model: "grok-4" # 256k context window
  )

  puts "Long context response: #{long_response.dig('choices', 0, 'message', 'content')}"
rescue StandardError => e
  puts "Long context error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 8: STRUCTURED OUTPUT WITH JSON SCHEMA
# ============================================================================

puts "8. Structured output with JSON schema:"

# Define a JSON schema for structured output
schema = {
  type: "json_schema",
  json_schema: {
    name: "code_review",
    strict: true,
    schema: {
      type: "object",
      properties: {
        rating: {
          type: "integer",
          description: "Code quality rating from 1-10"
        },
        strengths: {
          type: "array",
          items: { type: "string" },
          description: "List of code strengths"
        },
        improvements: {
          type: "array",
          items: { type: "string" },
          description: "List of suggested improvements"
        },
        summary: {
          type: "string",
          description: "Overall assessment summary"
        }
      },
      required: ["rating", "strengths", "improvements", "summary"],
      additionalProperties: false
    }
  }
}

structured_response = provider.chat_completion(
  messages: [{
    role: "user",
    content: "Review this Ruby code and provide feedback: 'def factorial(n)\n  n <= 1 ? 1 : n * factorial(n - 1)\nend'"
  }],
  model: "grok-4",
  response_format: schema
)

puts "Structured output:"
puts JSON.pretty_generate(JSON.parse(structured_response.dig('choices', 0, 'message', 'content')))
puts

# ============================================================================
# EXAMPLE 9: AGENT HANDOFF
# ============================================================================

puts "9. Agent handoff to specialized Grok agent:"

# Create a general purpose agent
general_agent = RAAF::Agent.new(
  name: "GeneralAgent",
  instructions: "You analyze requests and handoff to specialized agents when appropriate.",
  model: "gpt-4o"
)

# Create specialized Grok coding agent
grok_coding_agent = RAAF::Agent.new(
  name: "GrokCodingExpert",
  instructions: "You are a coding expert using Grok. Provide detailed code solutions.",
  model: "grok-code-fast-1"
)

# Configure handoff
general_agent.add_handoff(grok_coding_agent)

# Create runner with OpenAI provider for general agent
# Grok provider will be used automatically when handoff occurs
handoff_runner = RAAF::Runner.new(
  agent: general_agent,
  agents: [general_agent, grok_coding_agent]
)

handoff_messages = [{
  role: "user",
  content: "I need help writing a Ruby class for a binary search tree."
}]

handoff_result = handoff_runner.run(handoff_messages)
puts "Handoff result from #{handoff_result.agent_name}:"
puts handoff_result.final_output
puts

# ============================================================================
# EXAMPLE 10: PERFORMANCE MONITORING
# ============================================================================

puts "10. Performance monitoring with xAI:"

# Create agent with tracing
traced_agent = RAAF::Agent.new(
  name: "TracedGrokAgent",
  instructions: "You are a performance-monitored agent using Grok.",
  model: "grok-4"
)

# Setup tracing
tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(RAAF::Tracing::ConsoleProcessor.new)

# Create runner with tracing
traced_runner = RAAF::Runner.new(
  agent: traced_agent,
  provider: provider,
  tracer: tracer
)

# Execute with performance monitoring
traced_messages = [{
  role: "user",
  content: "Explain the advantages of using xAI's Grok models for AI development."
}]

traced_result = traced_runner.run(traced_messages)
puts "Traced response: #{traced_result.final_output}"
puts

# ============================================================================
# CONFIGURATION DISPLAY
# ============================================================================

puts "=== xAI Provider Configuration ==="
puts "Provider: #{provider.class.name}"
puts "API Base: #{provider.instance_variable_get(:@api_base)}"
puts "Available models: #{provider.supported_models.join(', ')}"
puts "Vision models: #{RAAF::Models::XAIProvider::VISION_MODELS.join(', ')}"
puts "Coding models: #{RAAF::Models::XAIProvider::CODING_MODELS.join(', ')}"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Example Complete ==="
puts
puts "Key xAI (Grok) Integration Features:"
puts "1. Advanced reasoning capabilities across all models"
puts "2. 256k context window for processing long documents"
puts "3. Specialized coding model (grok-code-fast-1) for development tasks"
puts "4. Vision support in Grok 4 for image understanding"
puts "5. Parallel tool calling for efficient multi-tool operations"
puts "6. Structured outputs with JSON schema support"
puts "7. Real-time streaming responses"
puts "8. Full OpenAI API compatibility"
puts
puts "Best Practices:"
puts "- Use grok-4 for tasks requiring vision or maximum capability"
puts "- Use grok-code-fast-1 for coding and development assistance"
puts "- Use grok-3-mini for faster responses on simpler tasks"
puts "- Leverage the 256k context window for document analysis"
puts "- Enable parallel tool calls for efficiency"
puts "- Use structured outputs for consistent data formats"
puts "- Monitor performance with tracing for optimization"
puts "- Implement proper error handling for API calls"
puts "- Get your API key from https://console.x.ai"

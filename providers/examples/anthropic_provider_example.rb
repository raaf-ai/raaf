#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates Anthropic Claude integration with RAAF (Ruby AI Agents Factory).
# Anthropic provides powerful Claude models renowned for safety, helpfulness, and honesty.
# The multi-provider architecture allows seamless switching between AI providers,
# enabling cost optimization, feature comparison, and provider redundancy.
# Claude models excel at reasoning, analysis, and following complex instructions.

require "raaf-providers"

# Anthropic requires an API key for authentication
# Sign up at https://console.anthropic.com to get your key
unless ENV["ANTHROPIC_API_KEY"]
  puts "ERROR: API key not set - ANTHROPIC_API_KEY"
  puts "Please set it with: export ANTHROPIC_API_KEY='your-api-key'"
  puts "Get your API key from: https://console.anthropic.com/account/keys"
  exit 1
end

puts "=== Anthropic Provider Example ==="
puts

# ============================================================================
# PROVIDER SETUP
# ============================================================================

# Create an Anthropic provider instance
# This provider translates between OpenAI's interface and Anthropic's API
# Enables using Claude models with the same code structure as OpenAI
provider = RAAF::Models::AnthropicProvider.new

# ============================================================================
# EXAMPLE 1: BASIC CHAT COMPLETION
# ============================================================================

puts "1. Basic chat completion with Claude:"

# Standard chat completion request using OpenAI's format
# The provider handles translation to Anthropic's API structure
response = provider.chat_completion(
  messages: [
    { role: "user",
      content: "Explain the concept of entropy in thermodynamics and information theory, highlighting the key differences." }
  ],
  model: "claude-3-opus-20240229" # Anthropic's most capable model
)

# Extract response using OpenAI's response structure
# Anthropic's response is normalized to match OpenAI's format
puts "Claude's response: #{response.dig('choices', 0, 'message', 'content')}"
puts

# ============================================================================
# EXAMPLE 2: CLAUDE MODEL COMPARISON
# ============================================================================

puts "2. Comparing different Claude models:"

# Test the same prompt across different Claude models
test_prompt = "Write a haiku about artificial intelligence."

claude_models = [
  { model: "claude-3-haiku-20240307", name: "Claude 3 Haiku (Fast, Cost-effective)" },
  { model: "claude-3-sonnet-20240229", name: "Claude 3 Sonnet (Balanced)" },
  { model: "claude-3-opus-20240229", name: "Claude 3 Opus (Most Capable)" }
]

claude_models.each do |model_info|
  puts "\n#{model_info[:name]}:"
  begin
    response = provider.chat_completion(
      messages: [{ role: "user", content: test_prompt }],
      model: model_info[:model]
    )
    puts response.dig("choices", 0, "message", "content")
  rescue StandardError => e
    puts "Error with #{model_info[:name]}: #{e.message}"
  end
end

puts

# ============================================================================
# EXAMPLE 3: AGENT WITH CLAUDE AND TOOLS
# ============================================================================

puts "3. Using Claude agent with tools:"

# Define analytical tools that leverage Claude's reasoning capabilities
def analyze_text(text:, analysis_type: "sentiment")
  # Simulate text analysis - in production this would use actual NLP services
  case analysis_type.downcase
  when "sentiment"
    sentiments = %w[positive negative neutral]
    "Sentiment analysis of '#{text}': #{sentiments.sample}"
  when "complexity"
    complexity = %w[simple moderate complex]
    "Complexity analysis of '#{text}': #{complexity.sample}"
  when "readability"
    levels = %w[elementary intermediate advanced]
    "Readability analysis of '#{text}': #{levels.sample}"
  else
    "Analysis type '#{analysis_type}' not supported"
  end
end

def research_topic(topic:, depth: "overview")
  # Simulate research - in production this would query databases or APIs
  depth_info = {
    "overview" => "Brief overview with key points",
    "detailed" => "Comprehensive analysis with examples",
    "expert" => "Expert-level analysis with citations"
  }

  "Research on '#{topic}' (#{depth} level): #{depth_info[depth] || 'Standard analysis'}"
end

# Create a Claude-powered research agent
# Claude excels at analytical and research tasks
research_agent = RAAF::Agent.new(
  name: "ClaudeResearcher",
  instructions: "You are a research assistant powered by Claude. Use the available tools to provide thorough, well-researched responses. Always cite your analysis methods.",
  model: "claude-3-sonnet-20240229" # Balanced model for research tasks
)

# Add research and analysis tools
research_agent.add_tool(method(:analyze_text))
research_agent.add_tool(method(:research_topic))

# Create runner with Anthropic provider
runner = RAAF::Runner.new(
  agent: research_agent,
  provider: provider
)

# Test complex research query
messages = [{
  role: "user",
  content: "I need help analyzing the impact of artificial intelligence on creative writing. Please research this topic and analyze the complexity of the discussion."
}]

result = runner.run(messages)
puts "Research response: #{result.final_output}"
puts

# ============================================================================
# EXAMPLE 4: CLAUDE'S SAFETY AND REASONING
# ============================================================================

puts "4. Demonstrating Claude's safety and reasoning:"

# Create a safety-focused agent
safety_agent = RAAF::Agent.new(
  name: "SafetyExpert",
  instructions: "You are a safety expert. Provide balanced, thoughtful responses about sensitive topics. Always prioritize safety and ethical considerations.",
  model: "claude-3-opus-20240229" # Most capable model for nuanced responses
)

safety_runner = RAAF::Runner.new(
  agent: safety_agent,
  provider: provider
)

# Test Claude's approach to sensitive topics
safety_messages = [{
  role: "user",
  content: "What are the ethical considerations around AI development that we should be most concerned about?"
}]

safety_result = safety_runner.run(safety_messages)
puts "Safety analysis: #{safety_result.final_output}"
puts

# ============================================================================
# EXAMPLE 5: STREAMING WITH CLAUDE
# ============================================================================

puts "5. Streaming response from Claude:"
puts "Streaming: "

# Stream completion for real-time output
provider.stream_completion(
  messages: [{ role: "user", content: "Explain quantum computing in simple terms, step by step." }],
  model: "claude-3-sonnet-20240229"
) do |chunk|
  # Process streaming chunks as they arrive
  if chunk["choices"] && chunk["choices"][0]["delta"]["content"]
    print chunk["choices"][0]["delta"]["content"]
    $stdout.flush
  end
end
puts "\n"

# ============================================================================
# EXAMPLE 6: MULTI-PROVIDER HANDOFF
# ============================================================================

puts "6. Multi-provider handoff (Claude to OpenAI):"

# Create Claude agent for initial analysis
claude_agent = RAAF::Agent.new(
  name: "ClaudeAnalyst",
  instructions: "You are an analytical agent using Claude. When asked about creative tasks, handoff to CreativeGPT.",
  model: "claude-3-sonnet-20240229"
)

# Create OpenAI agent for creative tasks
openai_agent = RAAF::Agent.new(
  name: "CreativeGPT",
  instructions: "You are a creative assistant using GPT-4. Generate creative content and stories.",
  model: "gpt-4o"
)

# Configure handoff
claude_agent.add_handoff(openai_agent)

# Create runner starting with Claude
handoff_runner = RAAF::Runner.new(
  agent: claude_agent,
  provider: provider
)

# Request that triggers handoff
handoff_messages = [{
  role: "user",
  content: "First analyze why storytelling is important for humans, then write a short creative story about a robot learning to dream."
}]

handoff_result = handoff_runner.run(handoff_messages)
puts "Handoff result from #{handoff_result.agent_name}: #{handoff_result.final_output}"
puts

# ============================================================================
# EXAMPLE 7: CLAUDE WITH SYSTEM PROMPTS
# ============================================================================

puts "7. Using Claude with detailed system prompts:"

# Claude excels with detailed, structured instructions
detailed_agent = RAAF::Agent.new(
  name: "DetailedClaudeAgent",
  instructions: "
You are a Claude-powered assistant with the following characteristics:
- Provide thorough, well-structured responses
- Always explain your reasoning process
- Consider multiple perspectives on complex topics
- Acknowledge uncertainty when appropriate
- Prioritize accuracy over speed
- Use clear, logical organization in your responses

When answering questions:
1. First, acknowledge the question
2. Outline your approach
3. Provide the detailed response
4. Summarize key points
5. Offer to clarify or expand on any aspect
",
  model: "claude-3-opus-20240229"
)

detailed_runner = RAAF::Runner.new(
  agent: detailed_agent,
  provider: provider
)

detailed_messages = [{
  role: "user",
  content: "What are the key differences between machine learning and artificial intelligence?"
}]

detailed_result = detailed_runner.run(detailed_messages)
puts "Detailed response: #{detailed_result.final_output}"
puts

# ============================================================================
# CONFIGURATION DISPLAY
# ============================================================================

puts "=== Claude Provider Configuration ==="
puts "Provider: #{provider.class.name}"
puts "Available models: #{provider.supported_models.join(', ')}"
puts "Agent configuration: #{research_agent.to_h.inspect}"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Example Complete ==="
puts
puts "Key Anthropic Integration Features:"
puts "1. Drop-in replacement for OpenAI with same API"
puts "2. Access to Claude 3 models (Haiku, Sonnet, Opus)"
puts "3. Superior reasoning and analytical capabilities"
puts "4. Enhanced safety and ethical considerations"
puts "5. Excellent instruction following and structured responses"
puts "6. Seamless multi-provider handoffs"
puts "7. Streaming responses for real-time output"
puts
puts "Best Practices:"
puts "- Use Claude for complex reasoning and analysis tasks"
puts "- Leverage detailed system prompts for best results"
puts "- Consider Haiku for speed, Sonnet for balance, Opus for capability"
puts "- Implement proper error handling for API calls"
puts "- Monitor usage and costs across different models"
puts "- Test provider-specific capabilities and limitations"

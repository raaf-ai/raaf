#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates Groq integration with RAAF (Ruby AI Agents Factory).
# Groq provides ultra-fast inference for open-source models like Llama, Mixtral, and Gemma.
# The multi-provider architecture allows seamless switching between AI providers,
# enabling cost optimization, speed optimization, and provider redundancy.
# Groq excels at high-throughput, low-latency applications requiring fast responses.

require "raaf-providers"

# Groq requires an API key for authentication
# Sign up at https://console.groq.com to get your key
unless ENV["GROQ_API_KEY"]
  puts "ERROR: GROQ_API_KEY environment variable is required"
  puts "Please set it with: export GROQ_API_KEY='your-api-key'"
  puts "Get your API key from: https://console.groq.com/keys"
  exit 1
end

puts "=== Groq Provider Example ==="
puts

# ============================================================================
# PROVIDER SETUP
# ============================================================================

# Create a Groq provider instance
# This provider translates between OpenAI's interface and Groq's API
# Enables using Groq models with the same code structure as OpenAI
provider = RAAF::Models::GroqProvider.new

# ============================================================================
# EXAMPLE 1: SPEED DEMONSTRATION
# ============================================================================

puts "1. Speed demonstration with Groq:"

# Test Groq's ultra-fast inference
test_prompt = "Explain what makes Groq different from other AI providers in one paragraph."

start_time = Time.now
response = provider.chat_completion(
  messages: [{ role: "user", content: test_prompt }],
  model: "llama3-8b-8192" # Groq's optimized Llama 3 model
)
end_time = Time.now

puts "Response time: #{(end_time - start_time).round(3)} seconds"
puts "Response: #{response.dig('choices', 0, 'message', 'content')}"
puts

# ============================================================================
# EXAMPLE 2: GROQ MODEL COMPARISON
# ============================================================================

puts "2. Comparing different Groq models:"

# Test different models available on Groq
groq_models = [
  { model: "llama3-8b-8192", name: "Llama 3 8B (Fast, General Purpose)" },
  { model: "llama3-70b-8192", name: "Llama 3 70B (Most Capable)" },
  { model: "mixtral-8x7b-32768", name: "Mixtral 8x7B (Long Context)" },
  { model: "gemma-7b-it", name: "Gemma 7B (Google's Model)" }
]

test_prompt = "What are the key benefits of using open-source AI models?"

groq_models.each do |model_info|
  puts "\n#{model_info[:name]}:"
  begin
    start_time = Time.now
    response = provider.chat_completion(
      messages: [{ role: "user", content: test_prompt }],
      model: model_info[:model]
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
# EXAMPLE 3: HIGH-THROUGHPUT AGENT
# ============================================================================

puts "3. High-throughput agent for rapid responses:"

# Define fast utility tools for quick operations
def quick_calculation(expression:)
  # Simple calculator optimized for speed

  # Security check
  return "Invalid expression" unless expression.match?(%r{^[\d\s+\-*/().]+$})

  # Safe evaluation
  result = eval(expression)
  "#{expression} = #{result}"
rescue StandardError => e
  "Error: #{e.message}"
end

def quick_word_count(text:)
  # Fast word counting utility
  words = text.split(/\s+/).size
  chars = text.length
  "Text statistics: #{words} words, #{chars} characters"
end

# Create a high-speed agent for utility tasks
speed_agent = RAAF::Agent.new(
  name: "GroqSpeedAgent",
  instructions: "You are a high-speed utility assistant. Provide quick, concise responses. Use tools for calculations and analysis.",
  model: "llama3-8b-8192" # Fast model for utility tasks
)

# Add utility tools
speed_agent.add_tool(method(:quick_calculation))
speed_agent.add_tool(method(:quick_word_count))

# Create runner with Groq provider
runner = RAAF::Runner.new(
  agent: speed_agent,
  provider: provider
)

# Test rapid utility operations
utility_messages = [{
  role: "user",
  content: "Calculate 23 * 45 + 17 and count the words in this sentence: 'The quick brown fox jumps over the lazy dog.'"
}]

start_time = Time.now
utility_result = runner.run(utility_messages)
elapsed = Time.now - start_time

puts "Utility response (#{elapsed.round(3)}s): #{utility_result.final_output}"
puts

# ============================================================================
# EXAMPLE 4: STREAMING FOR REAL-TIME APPLICATIONS
# ============================================================================

puts "4. Streaming response from Groq:"
puts "Streaming: "

# Stream completion for ultra-fast real-time output
provider.stream_completion(
  messages: [{ role: "user", content: "List the top 5 programming languages and briefly explain each." }],
  model: "llama3-8b-8192"
) do |chunk|
  # Process streaming chunks as they arrive
  if chunk["choices"] && chunk["choices"][0]["delta"]["content"]
    print chunk["choices"][0]["delta"]["content"]
    $stdout.flush
  end
end
puts "\n"

# ============================================================================
# EXAMPLE 5: BATCH PROCESSING WITH GROQ
# ============================================================================

puts "5. Batch processing demonstration:"

# Simulate batch processing multiple requests
batch_requests = [
  "Summarize machine learning in one sentence.",
  "What is the capital of France?",
  "Explain photosynthesis briefly.",
  "Name three benefits of exercise.",
  "What is 42 * 13?"
]

puts "Processing #{batch_requests.size} requests..."
batch_start = Time.now

batch_responses = []
batch_requests.each_with_index do |request, index|
  start_time = Time.now
  response = provider.chat_completion(
    messages: [{ role: "user", content: request }],
    model: "llama3-8b-8192"
  )
  elapsed = Time.now - start_time

  result = response.dig("choices", 0, "message", "content")
  batch_responses << { request: request, response: result, time: elapsed }

  puts "#{index + 1}. #{request} (#{elapsed.round(3)}s)"
  puts "   #{result}"
end

batch_total = Time.now - batch_start
puts "\nTotal batch time: #{batch_total.round(3)}s"
puts "Average per request: #{(batch_total / batch_requests.size).round(3)}s"
puts

# ============================================================================
# EXAMPLE 6: LONG CONTEXT WITH MIXTRAL
# ============================================================================

puts "6. Long context demonstration with Mixtral:"

# Create a long context for testing
long_context = "
This is a comprehensive document about artificial intelligence systems.
It covers various aspects including machine learning, natural language processing,
computer vision, robotics, and ethical considerations. The document discusses
how AI systems are trained using large datasets and how they can be applied
to solve real-world problems. It also covers the challenges and limitations
of current AI technology, including issues with bias, interpretability, and
safety. The document concludes with recommendations for responsible AI development
and deployment practices.
"

# Add more context to test the model's ability to handle long inputs
extended_context = long_context * 10 # Repeat to create longer context

long_context_messages = [
  { role: "user", content: "Here's a document about AI: #{extended_context}" },
  { role: "user", content: "Based on this document, what are the three main challenges mentioned for AI technology?" }
]

begin
  long_response = provider.chat_completion(
    messages: long_context_messages,
    model: "mixtral-8x7b-32768" # Model with large context window
  )

  puts "Long context response: #{long_response.dig('choices', 0, 'message', 'content')}"
rescue StandardError => e
  puts "Long context error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 7: AGENT HANDOFF TO GROQ
# ============================================================================

puts "7. Agent handoff to Groq for speed:"

# Create an analysis agent that hands off to Groq for speed
analysis_agent = RAAF::Agent.new(
  name: "AnalysisAgent",
  instructions: "You analyze requests and handoff to GroqSpeedAgent for tasks requiring fast responses.",
  model: "gpt-4o"
)

# Create Groq agent for fast responses
groq_agent = RAAF::Agent.new(
  name: "GroqSpeedAgent",
  instructions: "You provide ultra-fast responses using Groq. Be concise and quick.",
  model: "llama3-8b-8192"
)

# Configure handoff
analysis_agent.add_handoff(groq_agent)

# Create runner starting with analysis agent
handoff_runner = RAAF::Runner.new(
  agent: analysis_agent,
  provider: RAAF::Models::OpenAIProvider.new # Start with OpenAI
)

# Request that triggers handoff to Groq
handoff_messages = [{
  role: "user",
  content: "I need a quick answer: What are the top 3 programming languages for web development?"
}]

handoff_result = handoff_runner.run(handoff_messages)
puts "Handoff result from #{handoff_result.agent_name}: #{handoff_result.final_output}"
puts

# ============================================================================
# EXAMPLE 8: PERFORMANCE MONITORING
# ============================================================================

puts "8. Performance monitoring with Groq:"

# Create agent with tracing for performance monitoring
traced_agent = RAAF::Agent.new(
  name: "TracedGroqAgent",
  instructions: "You are a performance-monitored agent using Groq.",
  model: "llama3-8b-8192"
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
  content: "Explain the benefits of using Groq for AI inference."
}]

traced_result = traced_runner.run(traced_messages)
puts "Traced response: #{traced_result.final_output}"
puts

# ============================================================================
# CONFIGURATION DISPLAY
# ============================================================================

puts "=== Groq Provider Configuration ==="
puts "Provider: #{provider.class.name}"
puts "Available models: #{provider.supported_models.join(', ')}"
puts "Agent configuration: #{speed_agent.to_h.inspect}"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Example Complete ==="
puts
puts "Key Groq Integration Features:"
puts "1. Ultra-fast inference with sub-second response times"
puts "2. Access to optimized open-source models (Llama, Mixtral, Gemma)"
puts "3. High-throughput batch processing capabilities"
puts "4. Long context support with Mixtral (32k tokens)"
puts "5. Excellent for real-time applications and chatbots"
puts "6. Seamless multi-provider handoffs"
puts "7. Streaming responses for immediate output"
puts "8. Cost-effective for high-volume applications"
puts
puts "Best Practices:"
puts "- Use Groq for applications requiring fast response times"
puts "- Leverage batch processing for high-throughput scenarios"
puts "- Consider Llama 3 8B for speed, 70B for capability"
puts "- Use Mixtral for long context requirements"
puts "- Monitor performance with tracing for optimization"
puts "- Implement proper error handling for API calls"
puts "- Consider rate limits for production deployments"

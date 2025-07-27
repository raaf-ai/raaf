#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates Together AI integration with RAAF (Ruby AI Agents Factory).
# Together AI provides access to a vast selection of open-source models
# including Llama, Mistral, CodeLlama, and many others at competitive prices.
# The multi-provider architecture allows seamless switching between AI providers,
# enabling model diversity, cost optimization, and specialized capabilities.

require "raaf-providers"

# Together AI requires an API key for authentication
# Sign up at https://together.ai to get your key
unless ENV["TOGETHER_API_KEY"]
  puts "ERROR: TOGETHER_API_KEY environment variable is required"
  puts "Please set it with: export TOGETHER_API_KEY='your-api-key'"
  puts "Get your API key from: https://together.ai/api-keys"
  exit 1
end

puts "=== Together AI Provider Example ==="
puts

# ============================================================================
# PROVIDER SETUP
# ============================================================================

# Create a Together AI provider instance
# This provider translates between OpenAI's interface and Together's API
# Enables using Together's diverse model catalog with unified interface
provider = RAAF::Models::TogetherProvider.new

# ============================================================================
# EXAMPLE 1: MODEL DIVERSITY SHOWCASE
# ============================================================================

puts "1. Model diversity showcase:"

# Together AI offers many different model families
together_models = [
  {
    model: "meta-llama/Llama-3-8b-chat-hf",
    name: "Llama 3 8B Chat",
    specialty: "General conversation and reasoning"
  },
  {
    model: "mistralai/Mixtral-8x7B-Instruct-v0.1",
    name: "Mixtral 8x7B",
    specialty: "Mixture of experts, strong reasoning"
  },
  {
    model: "codellama/CodeLlama-34b-Instruct-hf",
    name: "CodeLlama 34B",
    specialty: "Code generation and programming"
  },
  {
    model: "togethercomputer/RedPajama-INCITE-Chat-3B-v1",
    name: "RedPajama 3B",
    specialty: "Fast, lightweight chat model"
  }
]

test_prompt = "Explain the concept of machine learning in simple terms."

together_models.each do |model_info|
  puts "\n#{model_info[:name]} (#{model_info[:specialty]}):"
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
# EXAMPLE 2: CODE GENERATION SPECIALIST
# ============================================================================

puts "2. Code generation with CodeLlama:"

# Define coding tools that leverage specialized models
def generate_function(language:, description:, function_name:)
  # Code generation tool - in production this would use the model
  "Generated #{language} function '#{function_name}' for: #{description}"
end

def review_code(code:, language:, focus: "general")
  # Code review tool
  "Code review for #{language} code focusing on: #{focus}"
end

def optimize_code(code:, language:, optimization_type: "performance")
  # Code optimization tool
  "Optimized #{language} code for: #{optimization_type}"
end

# Create a specialized coding agent using CodeLlama
coding_agent = RAAF::Agent.new(
  name: "CodeLlamaAgent",
  instructions: "You are a programming assistant using CodeLlama. Help with code generation, review, and optimization. Always provide clear, well-commented code.",
  model: "codellama/CodeLlama-34b-Instruct-hf"
)

# Add coding tools
coding_agent.add_tool(method(:generate_function))
coding_agent.add_tool(method(:review_code))
coding_agent.add_tool(method(:optimize_code))

# Create runner with Together provider
coding_runner = RAAF::Runner.new(
  agent: coding_agent,
  provider: provider
)

# Test code generation capabilities
coding_messages = [{
  role: "user",
  content: "I need a Python function that calculates the factorial of a number recursively. Please generate it, then review it for optimization opportunities."
}]

coding_result = coding_runner.run(coding_messages)
puts "CodeLlama response: #{coding_result.final_output}"
puts

# ============================================================================
# EXAMPLE 3: MULTILINGUAL CAPABILITIES
# ============================================================================

puts "3. Multilingual capabilities:"

# Test multilingual understanding with different models
multilingual_tests = [
  { text: "Bonjour, comment allez-vous?", language: "French" },
  { text: "Hola, ¿cómo estás?", language: "Spanish" },
  { text: "こんにちは、元気ですか？", language: "Japanese" },
  { text: "Hallo, wie geht es dir?", language: "German" }
]

multilingual_tests.each do |test|
  puts "\n#{test[:language]}: #{test[:text]}"
  begin
    response = provider.chat_completion(
      messages: [
        { role: "user", content: "Translate this to English and explain what it means: #{test[:text]}" }
      ],
      model: "meta-llama/Llama-3-8b-chat-hf"
    )
    puts "Translation: #{response.dig('choices', 0, 'message', 'content')}"
  rescue StandardError => e
    puts "Error: #{e.message}"
  end
end

puts

# ============================================================================
# EXAMPLE 4: STREAMING WITH TOGETHER
# ============================================================================

puts "4. Streaming response from Together AI:"
puts "Streaming: "

# Stream completion for real-time output
provider.stream_completion(
  messages: [{ role: "user", content: "Explain the benefits of open-source AI models in 3 detailed points." }],
  model: "meta-llama/Llama-3-8b-chat-hf"
) do |chunk|
  # Process streaming chunks as they arrive
  if chunk["choices"] && chunk["choices"][0]["delta"]["content"]
    print chunk["choices"][0]["delta"]["content"]
    $stdout.flush
  end
end
puts "\n"

# ============================================================================
# EXAMPLE 5: COST-EFFECTIVE BATCH PROCESSING
# ============================================================================

puts "5. Cost-effective batch processing:"

# Together AI offers competitive pricing for batch processing
batch_tasks = [
  "Summarize the benefits of renewable energy.",
  "Explain quantum computing in simple terms.",
  "List 5 programming best practices.",
  "Describe the water cycle process.",
  "What are the advantages of cloud computing?"
]

puts "Processing #{batch_tasks.size} tasks with Together AI..."
batch_start = Time.now
total_tokens = 0

batch_tasks.each_with_index do |task, index|
  start_time = Time.now
  response = provider.chat_completion(
    messages: [{ role: "user", content: task }],
    model: "togethercomputer/RedPajama-INCITE-Chat-3B-v1" # Fast, cost-effective model
  )
  elapsed = Time.now - start_time

  result = response.dig("choices", 0, "message", "content")
  tokens = response.dig("usage", "total_tokens") || 0
  total_tokens += tokens

  puts "#{index + 1}. #{task} (#{elapsed.round(3)}s, #{tokens} tokens)"
  puts "   #{result[0..100]}#{'...' if result.length > 100}"
end

batch_total = Time.now - batch_start
puts "\nBatch processing complete:"
puts "Total time: #{batch_total.round(3)}s"
puts "Average per task: #{(batch_total / batch_tasks.size).round(3)}s"
puts "Total tokens: #{total_tokens}"
puts "Average tokens per task: #{(total_tokens / batch_tasks.size).round(0)}"
puts

# ============================================================================
# EXAMPLE 6: SPECIALIZED MODEL SELECTION
# ============================================================================

puts "6. Specialized model selection:"

# Demonstrate using different models for different tasks
specialized_tasks = [
  {
    task: "Generate a complex algorithm",
    model: "codellama/CodeLlama-34b-Instruct-hf",
    reason: "CodeLlama excels at programming tasks"
  },
  {
    task: "Write a creative short story",
    model: "meta-llama/Llama-3-8b-chat-hf",
    reason: "Llama 3 is good at creative writing"
  },
  {
    task: "Solve a complex reasoning problem",
    model: "mistralai/Mixtral-8x7B-Instruct-v0.1",
    reason: "Mixtral has strong reasoning capabilities"
  },
  {
    task: "Provide a quick factual answer",
    model: "togethercomputer/RedPajama-INCITE-Chat-3B-v1",
    reason: "RedPajama is fast and efficient"
  }
]

specialized_tasks.each do |task_info|
  puts "\nTask: #{task_info[:task]}"
  puts "Selected model: #{task_info[:model]}"
  puts "Reason: #{task_info[:reason]}"

  begin
    response = provider.chat_completion(
      messages: [{ role: "user", content: task_info[:task] }],
      model: task_info[:model]
    )
    puts "Response: #{response.dig('choices', 0, 'message', 'content')[0..200]}..."
  rescue StandardError => e
    puts "Error: #{e.message}"
  end
end

puts

# ============================================================================
# EXAMPLE 7: MULTI-PROVIDER HANDOFF
# ============================================================================

puts "7. Multi-provider handoff (Together to OpenAI):"

# Create Together agent for cost-effective initial processing
together_agent = RAAF::Agent.new(
  name: "TogetherAgent",
  instructions: "You are a cost-effective agent using Together AI. For very complex tasks requiring advanced reasoning, handoff to OpenAIAgent.",
  model: "meta-llama/Llama-3-8b-chat-hf"
)

# Create OpenAI agent for complex tasks (if API key available)
if ENV["OPENAI_API_KEY"]
  openai_agent = RAAF::Agent.new(
    name: "OpenAIAgent",
    instructions: "You are an advanced reasoning agent using GPT-4. Handle complex analytical tasks.",
    model: "gpt-4o"
  )

  # Configure handoff
  together_agent.add_handoff(openai_agent)

  # Create runner starting with Together
  handoff_runner = RAAF::Runner.new(
    agent: together_agent,
    provider: provider
  )

  # Request that might trigger handoff
  handoff_messages = [{
    role: "user",
    content: "I need help with a complex business strategy analysis involving multiple stakeholders and market dynamics."
  }]

  handoff_result = handoff_runner.run(handoff_messages)
  puts "Handoff result from #{handoff_result.agent_name}: #{handoff_result.final_output}"
else
  puts "Skipping handoff example - no OpenAI API key available"
end

puts

# ============================================================================
# EXAMPLE 8: PERFORMANCE AND COST MONITORING
# ============================================================================

puts "8. Performance and cost monitoring:"

# Monitor performance across different Together models
performance_test = "What are the key principles of software architecture?"

models_to_test = [
  { model: "togethercomputer/RedPajama-INCITE-Chat-3B-v1", name: "RedPajama 3B" },
  { model: "meta-llama/Llama-3-8b-chat-hf", name: "Llama 3 8B" },
  { model: "mistralai/Mixtral-8x7B-Instruct-v0.1", name: "Mixtral 8x7B" }
]

puts "Performance comparison:"
models_to_test.each do |model_info|
  puts "\n#{model_info[:name]}:"
  begin
    start_time = Time.now
    response = provider.chat_completion(
      messages: [{ role: "user", content: performance_test }],
      model: model_info[:model]
    )
    elapsed = Time.now - start_time

    content = response.dig("choices", 0, "message", "content")
    tokens = response.dig("usage", "total_tokens") || 0

    puts "  Time: #{elapsed.round(3)}s"
    puts "  Tokens: #{tokens}"
    puts "  Response length: #{content.length} chars"
    puts "  Tokens per second: #{(tokens / elapsed).round(1)}"
  rescue StandardError => e
    puts "  Error: #{e.message}"
  end
end

puts

# ============================================================================
# CONFIGURATION DISPLAY
# ============================================================================

puts "=== Together AI Provider Configuration ==="
puts "Provider: #{provider.class.name}"
puts "Base URL: #{provider.base_url}"
puts "Supported model families: Llama, Mistral, CodeLlama, RedPajama, and more"
puts "Key features: Diverse models, competitive pricing, fast inference"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Example Complete ==="
puts
puts "Key Together AI Integration Features:"
puts "1. Access to 50+ open-source models"
puts "2. Competitive pricing with transparent costs"
puts "3. Specialized models for different tasks"
puts "4. Fast inference with global infrastructure"
puts "5. Code generation specialists (CodeLlama)"
puts "6. Multilingual capabilities"
puts "7. Streaming responses for real-time output"
puts "8. Cost-effective batch processing"
puts
puts "Best Practices:"
puts "- Choose models based on task requirements"
puts "- Use smaller models for simple tasks to save costs"
puts "- Leverage CodeLlama for programming tasks"
puts "- Monitor token usage for cost optimization"
puts "- Implement proper error handling for API calls"
puts "- Consider batch processing for high-volume tasks"
puts "- Test different models to find optimal performance/cost balance"
puts
puts "Model Recommendations:"
puts "- General chat: Llama 3 8B"
puts "- Code generation: CodeLlama 34B"
puts "- Complex reasoning: Mixtral 8x7B"
puts "- Fast/cheap tasks: RedPajama 3B"
puts "- Specialized tasks: Explore Together's model catalog"

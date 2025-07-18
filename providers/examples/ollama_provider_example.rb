#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates Ollama integration with RAAF (Ruby AI Agents Factory).
# Ollama enables running large language models locally on your machine,
# providing privacy, control, and cost-effectiveness for AI applications.
# The multi-provider architecture allows seamless switching between cloud and local models,
# enabling hybrid deployments and offline capabilities.

require_relative "../lib/raaf"

puts "=== Ollama Provider Example ==="
puts

# ============================================================================
# PROVIDER SETUP
# ============================================================================

# Create an Ollama provider instance
# This provider connects to your local Ollama installation
# Enables using local models with the same code structure as cloud providers
provider = RAAF::Models::OllamaProvider.new

# ============================================================================
# EXAMPLE 1: OLLAMA CONNECTION CHECK
# ============================================================================

puts "1. Checking Ollama connection and available models:"

begin
  # Check if Ollama is running and accessible
  models = provider.list_models
  
  if models.empty?
    puts "⚠️  Ollama is running but no models are installed."
    puts "   Install a model with: ollama pull llama3.2"
    puts "   Or try: ollama pull codellama, ollama pull mistral"
  else
    puts "✅ Ollama is running with #{models.size} models:"
    models.each do |model|
      puts "   - #{model[:name]} (#{model[:size] || 'unknown size'})"
    end
  end
  
  puts
  
rescue RAAF::Models::ConnectionError => e
  puts "❌ Ollama connection failed: #{e.message}"
  puts
  puts "To use Ollama:"
  puts "1. Install Ollama: https://ollama.ai/download"
  puts "2. Start Ollama: ollama serve"
  puts "3. Pull a model: ollama pull llama3.2"
  puts "4. Run this example again"
  puts
  puts "Continuing with demo mode..."
  
  # Demo mode - show what would happen with Ollama
  puts "\n=== Demo Mode (Ollama not available) ==="
  puts "Here's what this example would demonstrate with Ollama running:"
  puts "- Local model inference with complete privacy"
  puts "- Offline AI capabilities"
  puts "- Custom model management"
  puts "- Cost-free inference after initial setup"
  puts "- Full control over model behavior and data"
  exit 0
end

# ============================================================================
# EXAMPLE 2: BASIC LOCAL INFERENCE
# ============================================================================

puts "2. Basic local inference:"

# Use the first available model for testing
available_models = provider.list_models
if available_models.any?
  test_model = available_models.first[:name]
  puts "Using model: #{test_model}"
  
  # Standard chat completion using local model
  response = provider.chat_completion(
    messages: [
      { role: "user", content: "Explain the benefits of running AI models locally." }
    ],
    model: test_model
  )
  
  puts "Local model response: #{response.dig("choices", 0, "message", "content")}"
else
  puts "No models available. Please install a model first."
end

puts

# ============================================================================
# EXAMPLE 3: PRIVACY-FOCUSED AGENT
# ============================================================================

puts "3. Privacy-focused agent with local processing:"

if available_models.any?
  # Define privacy-sensitive tools that benefit from local processing
  def analyze_sensitive_data(data:, analysis_type: "summary")
    # Simulate sensitive data analysis - all processing stays local
    case analysis_type.downcase
    when "summary"
      "Summary analysis of sensitive data completed locally. Data never left your machine."
    when "classification"
      "Classification analysis completed. Categories: [confidential, internal, public]"
    when "sentiment"
      "Sentiment analysis completed locally. Results: [positive, negative, neutral]"
    else
      "Unknown analysis type: #{analysis_type}"
    end
  end
  
  def secure_calculation(expression:)
    # Secure calculation that doesn't send data to cloud
    begin
      return "Invalid expression" unless expression.match?(/^[\d\s+\-*\/().]+$/)
      result = eval(expression)
      "Secure calculation result: #{expression} = #{result} (processed locally)"
    rescue StandardError => e
      "Calculation error: #{e.message}"
    end
  end
  
  # Create privacy-focused agent using local model
  privacy_agent = RAAF::Agent.new(
    name: "PrivacyAgent",
    instructions: "You are a privacy-focused assistant. All processing happens locally. Emphasize data security and privacy in your responses.",
    model: test_model
  )
  
  # Add privacy-sensitive tools
  privacy_agent.add_tool(method(:analyze_sensitive_data))
  privacy_agent.add_tool(method(:secure_calculation))
  
  # Create runner with Ollama provider
  privacy_runner = RAAF::Runner.new(
    agent: privacy_agent,
    provider: provider
  )
  
  # Test privacy-focused operations
  privacy_messages = [{
    role: "user",
    content: "I need to analyze some confidential financial data and calculate 2024 budget projections. Can you help while ensuring data privacy?"
  }]
  
  privacy_result = privacy_runner.run(privacy_messages)
  puts "Privacy agent response: #{privacy_result.final_output}"
else
  puts "Skipping privacy example - no models available"
end

puts

# ============================================================================
# EXAMPLE 4: OFFLINE DEVELOPMENT WORKFLOW
# ============================================================================

puts "4. Offline development workflow:"

if available_models.any?
  # Define development tools that work offline
  def generate_code(language:, task:)
    # Code generation using local model
    "Generated #{language} code for: #{task}\n(This would be actual code generated by the local model)"
  end
  
  def review_code(code:, focus: "general")
    # Local code review
    "Code review completed locally focusing on: #{focus}\n(Review comments would be generated by local model)"
  end
  
  # Create development agent using local model
  dev_agent = RAAF::Agent.new(
    name: "OfflineDevAgent",
    instructions: "You are a development assistant that works completely offline. Help with coding, debugging, and development tasks using only local resources.",
    model: test_model
  )
  
  # Add development tools
  dev_agent.add_tool(method(:generate_code))
  dev_agent.add_tool(method(:review_code))
  
  # Create runner for development workflow
  dev_runner = RAAF::Runner.new(
    agent: dev_agent,
    provider: provider
  )
  
  # Test offline development
  dev_messages = [{
    role: "user",
    content: "I'm working offline and need help generating a Python function to calculate Fibonacci numbers and then reviewing it for optimization."
  }]
  
  dev_result = dev_runner.run(dev_messages)
  puts "Development agent response: #{dev_result.final_output}"
else
  puts "Skipping development example - no models available"
end

puts

# ============================================================================
# EXAMPLE 5: STREAMING WITH LOCAL MODELS
# ============================================================================

puts "5. Streaming response from local model:"

if available_models.any?
  puts "Streaming: "
  
  # Stream completion for real-time output from local model
  provider.stream_completion(
    messages: [{ role: "user", content: "Explain the advantages of local AI models in 3 bullet points." }],
    model: test_model
  ) do |chunk|
    # Process streaming chunks as they arrive
    if chunk["choices"] && chunk["choices"][0]["delta"]["content"]
      print chunk["choices"][0]["delta"]["content"]
      $stdout.flush
    end
  end
  puts "\n"
else
  puts "Skipping streaming example - no models available"
end

# ============================================================================
# EXAMPLE 6: MODEL MANAGEMENT
# ============================================================================

puts "6. Model management operations:"

begin
  # List all available models with details
  models = provider.list_models
  puts "Model inventory:"
  models.each do |model|
    puts "- Name: #{model[:name]}"
    puts "  Size: #{model[:size] || 'unknown'}"
    puts "  Modified: #{model[:modified_at] || 'unknown'}"
    puts "  Digest: #{model[:digest] || 'unknown'}"
    puts
  end
  
  # Check model capabilities
  if models.any?
    puts "Model capabilities check:"
    test_model = models.first[:name]
    
    # Test different types of requests
    tests = [
      { name: "Simple Q&A", prompt: "What is 2+2?" },
      { name: "Creative Writing", prompt: "Write a haiku about technology." },
      { name: "Code Generation", prompt: "Write a Python function to reverse a string." },
      { name: "Analysis", prompt: "List 3 benefits of renewable energy." }
    ]
    
    tests.each do |test|
      puts "\n#{test[:name]}:"
      begin
        response = provider.chat_completion(
          messages: [{ role: "user", content: test[:prompt] }],
          model: test_model
        )
        puts "✅ #{response.dig("choices", 0, "message", "content")}"
      rescue StandardError => e
        puts "❌ Error: #{e.message}"
      end
    end
  end
  
rescue StandardError => e
  puts "Model management error: #{e.message}"
end

puts

# ============================================================================
# EXAMPLE 7: HYBRID CLOUD-LOCAL SETUP
# ============================================================================

puts "7. Hybrid cloud-local agent setup:"

if available_models.any?
  # Create local agent for privacy-sensitive tasks
  local_agent = RAAF::Agent.new(
    name: "LocalAgent",
    instructions: "You handle privacy-sensitive tasks locally. For complex reasoning that requires more capability, handoff to CloudAgent.",
    model: test_model
  )
  
  # Create cloud agent for complex tasks (if API key available)
  if ENV["OPENAI_API_KEY"]
    cloud_agent = RAAF::Agent.new(
      name: "CloudAgent",
      instructions: "You handle complex reasoning tasks using cloud resources. You have access to more advanced capabilities.",
      model: "gpt-4o"
    )
    
    # Configure handoff from local to cloud
    local_agent.add_handoff(cloud_agent)
    
    # Create runner starting with local agent
    hybrid_runner = RAAF::Runner.new(
      agent: local_agent,
      provider: provider
    )
    
    # Test hybrid workflow
    hybrid_messages = [{
      role: "user",
      content: "I need to analyze some personal data locally first, then if needed, get help with complex strategic planning."
    }]
    
    hybrid_result = hybrid_runner.run(hybrid_messages)
    puts "Hybrid workflow result: #{hybrid_result.final_output}"
  else
    puts "Skipping hybrid example - no cloud API key available"
  end
else
  puts "Skipping hybrid example - no local models available"
end

puts

# ============================================================================
# EXAMPLE 8: PERFORMANCE COMPARISON
# ============================================================================

puts "8. Performance comparison (local vs cloud):"

if available_models.any?
  test_prompt = "Explain artificial intelligence in one paragraph."
  
  # Test local performance
  puts "Local model performance:"
  local_start = Time.now
  local_response = provider.chat_completion(
    messages: [{ role: "user", content: test_prompt }],
    model: test_model
  )
  local_time = Time.now - local_start
  
  puts "Time: #{local_time.round(3)}s"
  puts "Response length: #{local_response.dig("choices", 0, "message", "content").length} chars"
  
  # Test cloud performance if available
  if ENV["OPENAI_API_KEY"]
    puts "\nCloud model performance:"
    cloud_provider = RAAF::Models::OpenAIProvider.new
    
    cloud_start = Time.now
    cloud_response = cloud_provider.chat_completion(
      messages: [{ role: "user", content: test_prompt }],
      model: "gpt-3.5-turbo"
    )
    cloud_time = Time.now - cloud_start
    
    puts "Time: #{cloud_time.round(3)}s"
    puts "Response length: #{cloud_response.dig("choices", 0, "message", "content").length} chars"
    
    # Compare performance
    puts "\nPerformance comparison:"
    puts "Local model: #{local_time.round(3)}s"
    puts "Cloud model: #{cloud_time.round(3)}s"
    puts "Difference: #{(cloud_time - local_time).round(3)}s"
  end
else
  puts "Skipping performance comparison - no models available"
end

puts

# ============================================================================
# CONFIGURATION DISPLAY
# ============================================================================

puts "=== Ollama Provider Configuration ==="
puts "Provider: #{provider.class.name}"
puts "Base URL: #{provider.base_url}"
puts "Available models: #{provider.list_models.map { |m| m[:name] }.join(", ")}"
puts "Connection status: #{provider.connected? ? "Connected" : "Disconnected"}"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Example Complete ==="
puts
puts "Key Ollama Integration Features:"
puts "1. Complete privacy - all processing happens locally"
puts "2. No ongoing costs after initial setup"
puts "3. Offline capabilities for air-gapped environments"
puts "4. Full control over models and data"
puts "5. Seamless integration with cloud providers"
puts "6. Support for multiple open-source models"
puts "7. Real-time streaming responses"
puts "8. Custom model management and deployment"
puts
puts "Best Practices:"
puts "- Use local models for privacy-sensitive data"
puts "- Implement hybrid workflows for optimal performance"
puts "- Monitor resource usage (CPU, memory, disk)"
puts "- Keep models updated for best performance"
puts "- Consider model size vs. capability trade-offs"
puts "- Implement proper error handling for model operations"
puts "- Use appropriate hardware for model requirements"
puts
puts "Getting Started:"
puts "1. Install Ollama: https://ollama.ai/download"
puts "2. Start Ollama: ollama serve"
puts "3. Pull models: ollama pull llama3.2"
puts "4. Run this example again"
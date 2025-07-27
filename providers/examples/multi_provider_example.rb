#!/usr/bin/env ruby
# frozen_string_literal: true

require "raaf-providers"

# Example demonstrating multiple AI providers

# Multi-provider architecture enables flexibility and optimization
puts "=== Multi-Provider Example ==="
puts
puts "This example shows how to use different AI providers with RAAF."
puts

# Check for required API keys
providers_config = {
  openai: { key: ENV.fetch("OPENAI_API_KEY", nil), required: true },
  anthropic: { key: ENV.fetch("ANTHROPIC_API_KEY", nil), required: false },
  cohere: { key: ENV.fetch("COHERE_API_KEY", nil), required: false },
  groq: { key: ENV.fetch("GROQ_API_KEY", nil), required: false },
  together: { key: ENV.fetch("TOGETHER_API_KEY", nil), required: false }
}

# Check which providers are available
available_providers = []
providers_config.each do |provider, config|
  if config[:key]
    available_providers << provider
  elsif config[:required]
    puts "ERROR: #{provider.to_s.upcase}_API_KEY is required"
    exit 1
  else
    puts "Note: #{provider.to_s.upcase}_API_KEY not set, skipping #{provider} examples"
  end
end

puts "\nAvailable providers: #{available_providers.join(', ')}"
puts

# Example 1: Using different providers directly
puts "1. Direct provider usage:"

if available_providers.include?(:openai)
  puts "\n- OpenAI GPT-4:"
  openai = RAAF::Models::OpenAIProvider.new
  response = openai.chat_completion(
    messages: [{ role: "user", content: "Say hello in one sentence." }],
    model: "gpt-4o"
  )
  puts "Response: #{response.dig('choices', 0, 'message', 'content')}"
end

if available_providers.include?(:anthropic)
  puts "\n- Anthropic Claude:"
  anthropic = RAAF::Models::AnthropicProvider.new
  response = anthropic.chat_completion(
    messages: [{ role: "user", content: "Say hello in one sentence." }],
    model: "claude-3-opus-20240229"
  )
  puts "Response: #{response.dig('choices', 0, 'message', 'content')}"
end

if available_providers.include?(:groq)
  puts "\n- Groq Llama 3:"
  groq = RAAF::Models::GroqProvider.new
  response = groq.chat_completion(
    messages: [{ role: "user", content: "Say hello in one sentence." }],
    model: "llama3-8b-8192"
  )
  puts "Response: #{response.dig('choices', 0, 'message', 'content')}"
end

# Example 2: Together for open-source models
puts "\n2. Open-source models with Together:"
if ENV["TOGETHER_API_KEY"]
  together = RAAF::Models::TogetherProvider.new
  response = together.chat_completion(
    messages: [{ role: "user", content: "Say hello in one sentence." }],
    model: "meta-llama/Llama-2-7b-chat-hf"
  )
  puts "Together response: #{response.dig('choices', 0, 'message', 'content')}"
else
  puts "Set TOGETHER_API_KEY to use Together models"
end

# Example 3: Multi-provider agents
puts "\n3. Multi-provider agent setup:"

# Create agents with different providers for different tasks
agents = []

# Fast inference agent (Groq)
if available_providers.include?(:groq)
  fast_agent = RAAF::Agent.new(
    name: "FastResponder",
    instructions: "You provide quick, concise responses. Be brief.",
    model: "llama3-8b-8192"
  )
  agents << { agent: fast_agent, provider: :groq }
end

# Creative writing agent (OpenAI)
if available_providers.include?(:openai)
  creative_agent = RAAF::Agent.new(
    name: "CreativeWriter",
    instructions: "You are a creative writer. Write engaging, imaginative content.",
    model: "gpt-4o"
  )
  agents << { agent: creative_agent, provider: :openai }
end

# Code assistant (Together AI with CodeLlama)
if available_providers.include?(:together)
  code_agent = RAAF::Agent.new(
    name: "CodeAssistant",
    instructions: "You are a coding assistant. Provide clear, well-commented code.",
    model: "codellama/CodeLlama-34b-Instruct-hf"
  )
  agents << { agent: code_agent, provider: :together }
end

# Example 4: Provider comparison
puts "\n4. Provider speed comparison:"

test_message = [{
  role: "user",
  content: "What is 2+2? Answer in exactly one word."
}]

provider_times = {}

available_providers.each do |provider_name|
  # All providers support tool calling now

  provider = case provider_name
             when :openai
               RAAF::Models::OpenAIProvider.new
             when :anthropic
               RAAF::Models::AnthropicProvider.new
             when :cohere
               RAAF::Models::CohereProvider.new
             when :groq
               RAAF::Models::GroqProvider.new
             when :together
               RAAF::Models::TogetherProvider.new
             end

  model = case provider_name
          when :openai then "gpt-3.5-turbo"
          when :anthropic then "claude-3-haiku-20240307"
          when :cohere then "command-r"
          when :groq then "llama3-8b-8192"
          when :together then "meta-llama/Llama-3-8b-chat-hf"
          end

  begin
    start_time = Time.now
    response = provider.chat_completion(messages: test_message, model: model)
    elapsed = Time.now - start_time

    answer = response.dig("choices", 0, "message", "content")
    provider_times[provider_name] = { time: elapsed, answer: answer }

    puts "#{provider_name}: #{elapsed.round(3)}s - Answer: #{answer}"
  rescue StandardError => e
    puts "#{provider_name}: Error - #{e.message}"
  end
end

# Example 5: Streaming comparison
puts "\n5. Streaming capabilities:"

streaming_message = [{
  role: "user",
  content: "Count from 1 to 5, one number per line."
}]

available_providers.each do |provider_name|
  next unless %i[openai groq together].include?(provider_name)

  provider = case provider_name
             when :openai
               RAAF::Models::OpenAIProvider.new
             when :groq
               RAAF::Models::GroqProvider.new
             when :together
               RAAF::Models::TogetherProvider.new
             end

  model = case provider_name
          when :openai then "gpt-3.5-turbo"
          when :groq then "llama3-8b-8192"
          when :together then "meta-llama/Llama-3-8b-chat-hf"
          end

  puts "\n#{provider_name} streaming:"
  begin
    provider.stream_completion(messages: streaming_message, model: model) do |chunk|
      print chunk[:content] if chunk[:type] == "content"
      $stdout.flush
    end
    puts
  rescue StandardError => e
    puts "Streaming error: #{e.message}"
  end
end

# Example 6: Auto provider selection
puts "\n6. Automatic provider selection:"

models_to_test = [
  "gpt-4o",
  "claude-3-opus-20240229",
  "command-r",
  "llama3-70b-8192",
  "mistralai/Mixtral-8x7B-Instruct-v0.1"
]

models_to_test.each do |model|
  provider_name = RAAF::Models::MultiProvider.get_provider_for_model(model)
  puts "Model '#{model}' -> Provider: #{provider_name}"
end

# Example 7: Retry logic demonstration
puts "\n7. Retry logic with providers:"

if available_providers.include?(:groq)
  # Groq has strict rate limits, good for testing retry
  retry_provider = RAAF::Models::RetryableProviderWrapper.new(
    RAAF::Models::GroqProvider.new,
    max_attempts: 3,
    base_delay: 1.0,
    logger: Logger.new($stdout) # Log retry attempts
  )

  puts "Testing retry logic with rapid requests..."
  3.times do |i|
    response = retry_provider.chat_completion(
      messages: [{ role: "user", content: "Test #{i}" }],
      model: "llama3-8b-8192"
    )
    puts "Request #{i + 1}: Success"
  rescue StandardError => e
    puts "Request #{i + 1}: Failed - #{e.message}"
  end
end

puts "\n=== Example Complete ==="
puts
puts "Summary:"
puts "- Demonstrated #{available_providers.size} different providers"
puts "- Showed direct usage, streaming, and auto-selection"
puts "- Compared performance across providers"
puts
puts "To use more providers, set their respective API keys:"
puts "- ANTHROPIC_API_KEY for Claude models"
puts "- COHERE_API_KEY for Command models"
puts "- GROQ_API_KEY for fast open-source models"
puts "- TOGETHER_API_KEY for diverse open-source models"

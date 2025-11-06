# frozen_string_literal: true

# Common Usage Patterns for RAAF Eval
#
# This example demonstrates common usage patterns for evaluating AI agents
# with different configurations, metrics, and workflows.

require "raaf/eval"

puts "=== RAAF Eval Common Usage Patterns ===\n\n"

# Pattern 1: Simple Model Comparison
# Compare the same agent execution with different models
puts "Pattern 1: Simple Model Comparison"
puts "-" * 50

baseline_span = {
  span_id: "span_001",
  trace_id: "trace_001",
  agent_name: "HelpfulAssistant",
  metadata: {
    model: "gpt-4o",
    instructions: "You are a helpful assistant.",
    messages: [
      { role: "user", content: "What is the capital of France?" }
    ],
    output: "The capital of France is Paris.",
    usage: { total_tokens: 50, input_tokens: 20, output_tokens: 30 }
  }
}

# Evaluate with different models
engine_gpt4 = RAAF::Eval::Engine.new(
  span: baseline_span,
  configuration_overrides: { model: "gpt-4o" }
)

engine_claude = RAAF::Eval::Engine.new(
  span: baseline_span,
  configuration_overrides: { model: "claude-3-5-sonnet-20241022" }
)

puts "Running GPT-4 evaluation..."
result_gpt4 = engine_gpt4.execute

puts "Running Claude evaluation..."
result_claude = engine_claude.execute

puts "GPT-4 Output: #{result_gpt4[:output]}"
puts "Claude Output: #{result_claude[:output]}"
puts "\n"

# Pattern 2: Parameter Sweep
# Test different temperature values to find optimal setting
puts "Pattern 2: Parameter Sweep (Temperature)"
puts "-" * 50

temperatures = [0.0, 0.3, 0.7, 1.0]
results = {}

temperatures.each do |temp|
  engine = RAAF::Eval::Engine.new(
    span: baseline_span,
    configuration_overrides: { temperature: temp }
  )

  puts "Testing temperature: #{temp}"
  results[temp] = engine.execute
end

puts "Results by temperature:"
results.each do |temp, result|
  puts "  #{temp}: #{result[:output]}"
end
puts "\n"

# Pattern 3: A/B Testing Prompts
# Compare different instruction variations
puts "Pattern 3: A/B Testing Prompts"
puts "-" * 50

prompts = {
  "formal" => "You are a professional assistant. Provide formal, concise answers.",
  "friendly" => "You are a friendly assistant. Provide warm, helpful answers.",
  "technical" => "You are a technical assistant. Provide detailed, technical answers."
}

prompt_results = {}

prompts.each do |style, instruction|
  engine = RAAF::Eval::Engine.new(
    span: baseline_span,
    configuration_overrides: { instructions: instruction }
  )

  puts "Testing #{style} style..."
  prompt_results[style] = engine.execute
end

puts "Results by prompt style:"
prompt_results.each do |style, result|
  puts "  #{style}: #{result[:output][0..100]}..."
end
puts "\n"

# Pattern 4: Batch Evaluation
# Evaluate multiple spans with the same configuration
puts "Pattern 4: Batch Evaluation"
puts "-" * 50

test_spans = [
  {
    span_id: "span_001",
    trace_id: "trace_001",
    agent_name: "Assistant",
    metadata: {
      model: "gpt-4o",
      messages: [{ role: "user", content: "What is 2+2?" }],
      output: "2+2 equals 4."
    }
  },
  {
    span_id: "span_002",
    trace_id: "trace_002",
    agent_name: "Assistant",
    metadata: {
      model: "gpt-4o",
      messages: [{ role: "user", content: "What is the speed of light?" }],
      output: "The speed of light is approximately 299,792,458 meters per second."
    }
  }
]

batch_config = { model: "claude-3-5-sonnet-20241022" }
batch_results = []

test_spans.each_with_index do |span, idx|
  puts "Evaluating span #{idx + 1}/#{test_spans.length}..."
  engine = RAAF::Eval::Engine.new(
    span: span,
    configuration_overrides: batch_config
  )
  batch_results << engine.execute
end

puts "Batch evaluation complete: #{batch_results.length} results"
successful = batch_results.count { |r| r[:success] }
puts "Success rate: #{successful}/#{batch_results.length}"
puts "\n"

# Pattern 5: Provider Comparison
# Compare the same execution across different providers
puts "Pattern 5: Provider Comparison"
puts "-" * 50

provider_configs = [
  { model: "gpt-4o", provider: "openai" },
  { model: "claude-3-5-sonnet-20241022", provider: "anthropic" },
  { model: "gemini-1.5-pro", provider: "gemini" }
]

provider_results = {}

provider_configs.each do |config|
  provider_name = config[:provider]
  puts "Testing #{provider_name}..."

  engine = RAAF::Eval::Engine.new(
    span: baseline_span,
    configuration_overrides: config
  )

  provider_results[provider_name] = engine.execute
end

puts "Results by provider:"
provider_results.each do |provider, result|
  if result[:success]
    tokens = result[:usage][:total_tokens] || 0
    puts "  #{provider}: Success (#{tokens} tokens)"
  else
    puts "  #{provider}: Failed - #{result[:error]}"
  end
end
puts "\n"

# Pattern 6: Metric-Focused Evaluation
# Focus on specific metrics during evaluation
puts "Pattern 6: Metric-Focused Evaluation"
puts "-" * 50

# Simulate running evaluation with metrics collection
engine = RAAF::Eval::Engine.new(
  span: baseline_span,
  configuration_overrides: { model: "gpt-4o", temperature: 0.7 }
)

result = engine.execute

if result[:success]
  # Calculate custom metrics
  output_length = result[:output].length
  token_efficiency = result[:output].length.to_f / (result[:usage][:total_tokens] || 1)

  puts "Output Metrics:"
  puts "  Output length: #{output_length} characters"
  puts "  Total tokens: #{result[:usage][:total_tokens]}"
  puts "  Token efficiency: #{token_efficiency.round(2)} chars/token"

  # Compare to baseline
  baseline_length = baseline_span[:metadata][:output].length
  baseline_tokens = baseline_span[:metadata][:usage][:total_tokens]

  puts "\nComparison to Baseline:"
  puts "  Length change: #{output_length - baseline_length} chars"
  puts "  Token change: #{result[:usage][:total_tokens] - baseline_tokens} tokens"
end
puts "\n"

# Pattern 7: Progressive Optimization
# Iteratively improve configuration based on results
puts "Pattern 7: Progressive Optimization"
puts "-" * 50

best_result = nil
best_score = -Float::INFINITY

# Start with baseline configuration
configs = [
  { model: "gpt-4o", temperature: 0.5 },
  { model: "gpt-4o", temperature: 0.7 },
  { model: "gpt-4o", temperature: 0.9 }
]

configs.each_with_index do |config, idx|
  puts "Testing configuration #{idx + 1}/#{configs.length}: temp=#{config[:temperature]}"

  engine = RAAF::Eval::Engine.new(
    span: baseline_span,
    configuration_overrides: config
  )

  result = engine.execute

  # Simple scoring: prefer shorter outputs with fewer tokens
  if result[:success]
    score = 1000.0 / (result[:usage][:total_tokens] || 100)
    puts "  Score: #{score.round(2)}"

    if score > best_score
      best_score = score
      best_result = result
      puts "  ✓ New best configuration!"
    end
  end
end

puts "\nBest Configuration:"
puts "  Score: #{best_score.round(2)}"
puts "  Output: #{best_result[:output][0..100]}..."
puts "\n"

puts "=== All patterns demonstrated successfully! ==="

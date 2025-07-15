#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates token estimation and usage tracking for cost management.
# Token counting is critical for production AI applications to control costs,
# stay within API limits, and optimize performance. This example shows both
# estimation techniques and actual usage tracking across different providers.

require_relative "../lib/openai_agents"

# ============================================================================
# TOKEN ESTIMATION SETUP
# ============================================================================

puts "=== Token Estimation and Usage Tracking Example ==="
puts "=" * 60

# Check for tiktoken_ruby availability for accurate token counting
begin
  require 'tiktoken_ruby'
  TIKTOKEN_AVAILABLE = true
  puts "✅ tiktoken_ruby available for accurate token counting"
rescue LoadError
  TIKTOKEN_AVAILABLE = false
  puts "⚠️  tiktoken_ruby not available, using estimation"
  puts "   Install with: gem install tiktoken_ruby"
end

# ============================================================================
# TOKEN ESTIMATION UTILITIES
# ============================================================================

# Simple token estimation for when tiktoken_ruby is not available.
# Provides rough estimates based on character counts and typical ratios.
#
# Note: This is less accurate than tiktoken but useful for quick estimates.
def estimate_tokens_simple(text)
  return 0 if text.nil? || text.empty?
  
  # Rough estimation: ~4 characters per token for English text
  # This accounts for spaces, punctuation, and typical word lengths
  char_count = text.length
  estimated_tokens = (char_count / 4.0).ceil
  
  # Adjust for common patterns
  word_count = text.split.length
  
  # Technical text tends to have more tokens per character
  if text.match?(/[{}()\[\]<>]/) || text.include?('```')
    estimated_tokens = (estimated_tokens * 1.3).ceil
  end
  
  estimated_tokens
end

# Accurate token counting using tiktoken_ruby when available.
# This matches OpenAI's actual tokenization for precise cost calculations.
def count_tokens_accurate(text, model = "gpt-4o")
  return estimate_tokens_simple(text) unless TIKTOKEN_AVAILABLE
  
  begin
    # Get the appropriate encoding for the model
    encoding = case model
              when /gpt-4o/, /gpt-4-turbo/
                Tiktoken.encoding_for_model("gpt-4")
              when /gpt-3.5/
                Tiktoken.encoding_for_model("gpt-3.5-turbo")
              else
                Tiktoken.encoding_for_model("gpt-4")
              end
    
    encoding.encode(text).length
  rescue => e
    puts "   ⚠️  Tiktoken error: #{e.message}, falling back to estimation"
    estimate_tokens_simple(text)
  end
end

# Calculate estimated costs based on token counts and model pricing.
# Prices are approximate and may change - always check current OpenAI pricing.
def estimate_cost(input_tokens:, output_tokens:, model: "gpt-4o")
  # Pricing per 1M tokens (as of 2024, check OpenAI pricing for current rates)
  pricing = {
    "gpt-4o" => { input: 2.50, output: 10.00 },
    "gpt-4o-mini" => { input: 0.15, output: 0.60 },
    "gpt-4-turbo" => { input: 10.00, output: 30.00 },
    "gpt-4" => { input: 30.00, output: 60.00 },
    "gpt-3.5-turbo" => { input: 0.50, output: 1.50 }
  }
  
  model_pricing = pricing[model] || pricing["gpt-4o"]
  
  input_cost = (input_tokens / 1_000_000.0) * model_pricing[:input]
  output_cost = (output_tokens / 1_000_000.0) * model_pricing[:output]
  
  {
    input_cost: input_cost,
    output_cost: output_cost,
    total_cost: input_cost + output_cost,
    input_tokens: input_tokens,
    output_tokens: output_tokens,
    total_tokens: input_tokens + output_tokens
  }
end

puts "✅ Token estimation utilities loaded"

# ============================================================================
# TOKEN COUNTING DEMONSTRATION
# ============================================================================

puts "\n=== Token Counting Methods Comparison ==="
puts "-" * 50

# Test different types of content for token counting accuracy
test_texts = {
  "Simple English" => "Hello, how are you today? I hope you're doing well.",
  "Technical Content" => "def calculate_tokens(text, model='gpt-4'): return len(encoding.encode(text))",
  "JSON Structure" => '{"name": "John", "age": 30, "city": "New York", "skills": ["Ruby", "Python"]}',
  "Mixed Content" => "The API returned a 200 status code with the following JSON response: {'success': true, 'data': [1, 2, 3]}",
  "Long Text" => "Artificial intelligence (AI) has revolutionized numerous industries by providing automated solutions to complex problems. Machine learning algorithms can analyze vast amounts of data to identify patterns and make predictions with remarkable accuracy. Natural language processing enables computers to understand and generate human-like text, while computer vision allows machines to interpret visual information."
}

puts "Comparing token counting methods:"
puts

test_texts.each do |type, text|
  simple_count = estimate_tokens_simple(text)
  accurate_count = count_tokens_accurate(text, "gpt-4o")
  
  puts "#{type}:"
  puts "   Text: \"#{text[0..60]}#{text.length > 60 ? "..." : ""}\""
  puts "   Characters: #{text.length}"
  puts "   Simple estimate: #{simple_count} tokens"
  puts "   Accurate count: #{accurate_count} tokens"
  
  if TIKTOKEN_AVAILABLE
    difference = ((simple_count - accurate_count).abs / accurate_count.to_f * 100).round(1)
    puts "   Accuracy: #{difference}% difference"
  end
  puts
end

# ============================================================================
# USAGE TRACKING WITH DIFFERENT PROVIDERS
# ============================================================================

puts "=== Usage Tracking with Different Providers ==="
puts "-" * 50

# Environment check
unless ENV["OPENAI_API_KEY"]
  puts "NOTE: OPENAI_API_KEY not set. Running in demo mode."
  puts "For actual usage tracking, set your API key."
  puts
end

# Create agent for testing
usage_agent = OpenAIAgents::Agent.new(
  name: "UsageTracker",
  instructions: "You provide helpful responses while we track token usage. Be concise but informative.",
  model: "gpt-4o-mini"  # Using mini model for cost efficiency in examples
)

# Test query for usage tracking
test_query = "Explain the benefits of token estimation in AI applications"

puts "Testing usage tracking with different providers:"
puts

# Test with OpenAIProvider (returns usage data)
puts "1. OpenAI Provider (Chat Completions API - with usage data):"
begin
  openai_provider = OpenAIAgents::Models::OpenAIProvider.new
  openai_runner = OpenAIAgents::Runner.new(agent: usage_agent, provider: openai_provider)
  
  # Estimate tokens before API call
  estimated_input = count_tokens_accurate(test_query, "gpt-4o-mini")
  puts "   Pre-call token estimate: #{estimated_input} input tokens"
  
  start_time = Time.now
  result = openai_runner.run(test_query)
  end_time = Time.now
  
  # Extract actual usage from response
  if result.respond_to?(:usage) && result.usage
    usage = result.usage
    puts "   ✅ Actual usage received:"
    puts "      Input tokens: #{usage[:prompt_tokens] || usage["prompt_tokens"]}"
    puts "      Output tokens: #{usage[:completion_tokens] || usage["completion_tokens"]}" 
    puts "      Total tokens: #{usage[:total_tokens] || usage["total_tokens"]}"
    
    # Calculate costs
    cost_breakdown = estimate_cost(
      input_tokens: usage[:prompt_tokens] || usage["prompt_tokens"] || 0,
      output_tokens: usage[:completion_tokens] || usage["completion_tokens"] || 0,
      model: "gpt-4o-mini"
    )
    
    puts "      Estimated cost: $#{cost_breakdown[:total_cost].round(6)}"
    puts "      Response time: #{((end_time - start_time) * 1000).round(1)}ms"
  else
    puts "   ⚠️  No usage data returned (unexpected)"
  end
  
rescue OpenAIAgents::Error => e
  puts "   ✗ API call failed: #{e.message}"
  
  # Demo mode with estimated values
  puts "   📋 Demo mode - estimated usage:"
  estimated_input = count_tokens_accurate(test_query, "gpt-4o-mini")
  estimated_output = count_tokens_accurate("Token estimation helps control costs and optimize performance in AI applications by providing insights into usage patterns.", "gpt-4o-mini")
  
  puts "      Input tokens: ~#{estimated_input}"
  puts "      Output tokens: ~#{estimated_output}"
  puts "      Total tokens: ~#{estimated_input + estimated_output}"
  
  cost_breakdown = estimate_cost(
    input_tokens: estimated_input,
    output_tokens: estimated_output,
    model: "gpt-4o-mini"
  )
  puts "      Estimated cost: $#{cost_breakdown[:total_cost].round(6)}"
end

puts

# Test with ResponsesProvider (no usage data returned)
puts "2. Responses Provider (Responses API - no usage data):"
begin
  responses_provider = OpenAIAgents::Models::ResponsesProvider.new
  responses_runner = OpenAIAgents::Runner.new(agent: usage_agent, provider: responses_provider)
  
  start_time = Time.now
  result = responses_runner.run(test_query)
  end_time = Time.now
  
  puts "   ✅ Response received (no usage data in Responses API)"
  puts "      Response time: #{((end_time - start_time) * 1000).round(1)}ms"
  
  # Manual token estimation
  if result.respond_to?(:final_output) && result.final_output
    estimated_input = count_tokens_accurate(test_query, "gpt-4o")
    estimated_output = count_tokens_accurate(result.final_output, "gpt-4o")
    
    puts "   📊 Manual token estimation:"
    puts "      Input tokens: ~#{estimated_input}"
    puts "      Output tokens: ~#{estimated_output}"
    puts "      Total tokens: ~#{estimated_input + estimated_output}"
    
    cost_breakdown = estimate_cost(
      input_tokens: estimated_input,
      output_tokens: estimated_output,
      model: "gpt-4o"
    )
    puts "      Estimated cost: $#{cost_breakdown[:total_cost].round(6)}"
  end
  
rescue OpenAIAgents::Error => e
  puts "   ✗ API call failed: #{e.message}"
  puts "   📋 Demo mode - estimated for Responses API:"
  puts "      No usage data available in Responses API"
  puts "      Manual estimation required for cost tracking"
end

# ============================================================================
# CONVERSATION TOKEN TRACKING
# ============================================================================

puts "\n=== Conversation Token Tracking ==="
puts "-" * 50

# Track tokens across a multi-turn conversation
class ConversationTracker
  def initialize(model = "gpt-4o-mini")
    @model = model
    @total_input_tokens = 0
    @total_output_tokens = 0
    @turn_count = 0
    @conversation_history = []
  end
  
  def track_turn(input_text, output_text)
    input_tokens = count_tokens_accurate(input_text, @model)
    output_tokens = count_tokens_accurate(output_text, @model)
    
    @total_input_tokens += input_tokens
    @total_output_tokens += output_tokens
    @turn_count += 1
    
    turn_data = {
      turn: @turn_count,
      input: input_text,
      output: output_text,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cumulative_input: @total_input_tokens,
      cumulative_output: @total_output_tokens
    }
    
    @conversation_history << turn_data
    turn_data
  end
  
  def summary
    total_tokens = @total_input_tokens + @total_output_tokens
    cost_breakdown = estimate_cost(
      input_tokens: @total_input_tokens,
      output_tokens: @total_output_tokens,
      model: @model
    )
    
    {
      turns: @turn_count,
      total_input_tokens: @total_input_tokens,
      total_output_tokens: @total_output_tokens,
      total_tokens: total_tokens,
      estimated_cost: cost_breakdown[:total_cost],
      average_tokens_per_turn: @turn_count > 0 ? (total_tokens / @turn_count).round(1) : 0,
      conversation_history: @conversation_history
    }
  end
end

# Simulate a conversation for tracking
tracker = ConversationTracker.new("gpt-4o-mini")

simulated_conversation = [
  {
    input: "What is machine learning?",
    output: "Machine learning is a subset of artificial intelligence that enables computers to learn and improve from experience without being explicitly programmed."
  },
  {
    input: "How does it differ from traditional programming?",
    output: "Traditional programming involves writing explicit instructions, while machine learning allows systems to automatically learn patterns from data and make decisions based on those patterns."
  },
  {
    input: "Can you give me a practical example?",
    output: "A practical example is email spam detection. Instead of writing rules for every type of spam, a machine learning system learns from thousands of spam and non-spam emails to automatically identify spam patterns."
  }
]

puts "Tracking simulated conversation:"
puts

simulated_conversation.each_with_index do |turn_data, index|
  turn_result = tracker.track_turn(turn_data[:input], turn_data[:output])
  
  puts "Turn #{turn_result[:turn]}:"
  puts "   Input: \"#{turn_data[:input]}\""
  puts "   Output: \"#{turn_data[:output][0..80]}#{turn_data[:output].length > 80 ? "..." : ""}\""
  puts "   Tokens: #{turn_result[:input_tokens]} in + #{turn_result[:output_tokens]} out = #{turn_result[:input_tokens] + turn_result[:output_tokens]} total"
  puts "   Cumulative: #{turn_result[:cumulative_input] + turn_result[:cumulative_output]} tokens"
  puts
end

# Conversation summary
summary = tracker.summary
puts "=== Conversation Summary ==="
puts "Total turns: #{summary[:turns]}"
puts "Total tokens: #{summary[:total_tokens]} (#{summary[:total_input_tokens]} input + #{summary[:total_output_tokens]} output)"
puts "Average per turn: #{summary[:average_tokens_per_turn]} tokens"
puts "Estimated cost: $#{summary[:estimated_cost].round(6)}"

# ============================================================================
# COST OPTIMIZATION STRATEGIES
# ============================================================================

puts "\n=== Cost Optimization Strategies ==="
puts "-" * 50

puts "✅ Model Selection Impact:"

# Compare costs across different models for the same task
test_content = "Explain the concept of microservices architecture and its benefits"
estimated_output = "Microservices architecture is a software development approach where applications are built as a collection of small, independent services..."

models_to_compare = ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]

models_to_compare.each do |model|
  input_tokens = count_tokens_accurate(test_content, model)
  output_tokens = count_tokens_accurate(estimated_output, model)
  
  cost_data = estimate_cost(
    input_tokens: input_tokens,
    output_tokens: output_tokens,
    model: model
  )
  
  puts "   #{model}:"
  puts "      Cost: $#{cost_data[:total_cost].round(6)}"
  puts "      Tokens: #{cost_data[:total_tokens]}"
end

puts "\n✅ Optimization Techniques:"
puts "   • Use gpt-4o-mini for simple tasks (75% cost reduction)"
puts "   • Implement response caching for repeated queries"
puts "   • Optimize prompts to reduce input tokens"
puts "   • Use streaming to allow early termination"
puts "   • Set max_tokens limits for controlled output length"
puts "   • Batch similar requests when possible"

puts "\n✅ Monitoring Best Practices:"
puts "   • Track tokens per user/session for usage limits"
puts "   • Set up cost alerts for budget management"
puts "   • Monitor token efficiency trends over time"
puts "   • Log high-token conversations for analysis"
puts "   • Implement progressive cost controls"

# ============================================================================
# PRODUCTION USAGE TRACKING EXAMPLE
# ============================================================================

puts "\n=== Production Usage Tracking Pattern ==="
puts "-" * 50

# Example production usage tracking class
class ProductionUsageTracker
  def initialize
    @daily_usage = Hash.new(0)
    @user_usage = Hash.new { |h, k| h[k] = Hash.new(0) }
    @cost_tracking = Hash.new(0.0)
  end
  
  def track_request(user_id:, model:, input_tokens:, output_tokens:, cost:)
    today = Date.today.to_s
    
    # Daily totals
    @daily_usage["#{today}_tokens"] += (input_tokens + output_tokens)
    @daily_usage["#{today}_requests"] += 1
    @cost_tracking[today] += cost
    
    # User totals
    @user_usage[user_id]["tokens"] += (input_tokens + output_tokens)
    @user_usage[user_id]["requests"] += 1
    @user_usage[user_id]["cost"] += cost
    
    # Check limits
    check_usage_limits(user_id, today)
  end
  
  def check_usage_limits(user_id, date)
    daily_limit_tokens = 100_000
    user_limit_tokens = 10_000
    daily_limit_cost = 50.0
    
    # Daily limits
    if @daily_usage["#{date}_tokens"] > daily_limit_tokens
      puts "   ⚠️  Daily token limit exceeded: #{@daily_usage["#{date}_tokens"]}"
    end
    
    if @cost_tracking[date] > daily_limit_cost
      puts "   ⚠️  Daily cost limit exceeded: $#{@cost_tracking[date].round(2)}"
    end
    
    # User limits
    if @user_usage[user_id]["tokens"] > user_limit_tokens
      puts "   ⚠️  User #{user_id} token limit exceeded: #{@user_usage[user_id]["tokens"]}"
    end
  end
  
  def daily_report(date = Date.today.to_s)
    {
      date: date,
      total_tokens: @daily_usage["#{date}_tokens"],
      total_requests: @daily_usage["#{date}_requests"],
      total_cost: @cost_tracking[date],
      average_tokens_per_request: @daily_usage["#{date}_requests"] > 0 ? 
        (@daily_usage["#{date}_tokens"] / @daily_usage["#{date}_requests"]).round(1) : 0
    }
  end
end

# Demonstrate production tracking
production_tracker = ProductionUsageTracker.new

# Simulate some requests
sample_requests = [
  { user_id: "user_1", model: "gpt-4o-mini", input_tokens: 120, output_tokens: 250 },
  { user_id: "user_2", model: "gpt-4o", input_tokens: 200, output_tokens: 400 },
  { user_id: "user_1", model: "gpt-4o-mini", input_tokens: 80, output_tokens: 150 },
  { user_id: "user_3", model: "gpt-4o-mini", input_tokens: 300, output_tokens: 500 }
]

puts "Simulating production usage tracking:"

sample_requests.each_with_index do |req, index|
  cost_data = estimate_cost(
    input_tokens: req[:input_tokens],
    output_tokens: req[:output_tokens],
    model: req[:model]
  )
  
  production_tracker.track_request(
    user_id: req[:user_id],
    model: req[:model],
    input_tokens: req[:input_tokens],
    output_tokens: req[:output_tokens],
    cost: cost_data[:total_cost]
  )
  
  puts "   Request #{index + 1}: #{req[:user_id]} - #{req[:model]} - #{req[:input_tokens] + req[:output_tokens]} tokens - $#{cost_data[:total_cost].round(6)}"
end

# Daily report
report = production_tracker.daily_report
puts "\n📊 Daily Usage Report:"
puts "   Total tokens: #{report[:total_tokens]}"
puts "   Total requests: #{report[:total_requests]}"
puts "   Total cost: $#{report[:total_cost].round(4)}"
puts "   Average tokens/request: #{report[:average_tokens_per_request]}"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Token Estimation and Usage Tracking Complete! ==="
puts "\nKey Features Demonstrated:"
puts "• Simple and accurate token counting methods"
puts "• Usage tracking across different provider APIs"
puts "• Multi-turn conversation token accumulation"
puts "• Cost estimation and model comparison"
puts "• Production usage tracking and limit monitoring"

puts "\nCost Management Best Practices:"
puts "• Use accurate token counting for precise cost calculation"
puts "• Choose appropriate models based on task complexity"
puts "• Implement usage limits and monitoring"
puts "• Track trends and optimize over time"
puts "• Set up automated alerts for budget control"

puts "\nProduction Implementation:"
puts "• OpenAIProvider returns actual usage data"
puts "• ResponsesProvider requires manual token estimation"
puts "• Implement conversation-level tracking"
puts "• Monitor per-user and daily usage limits"
puts "• Use tiktoken_ruby for accurate OpenAI token counting"
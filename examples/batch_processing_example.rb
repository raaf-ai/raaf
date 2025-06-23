#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/openai_agents"

##
# Batch Processing Example - Demonstrates OpenAI Batch API with 50% cost savings
#
# This example shows how to process multiple requests efficiently using
# OpenAI's Batch API, which provides significant cost savings for bulk operations.

puts "🚀 OpenAI Agents Ruby - Batch Processing Example"
puts "=" * 60

# Check for API key
unless ENV["OPENAI_API_KEY"]
  puts "❌ Error: OPENAI_API_KEY environment variable is required"
  puts "Please set your OpenAI API key:"
  puts "export OPENAI_API_KEY='your-api-key-here'"
  exit 1
end

puts "\n📦 Creating Batch Processor..."
batch_processor = OpenAIAgents::BatchProcessor.new

# =============================================================================
# 1. Basic Batch Processing
# =============================================================================
puts "\n1. 📋 Basic Batch Processing"
puts "-" * 40

# Prepare a batch of different types of requests
basic_requests = [
  {
    model: "gpt-4.1",
    messages: [
      { role: "user", content: "What is the capital of France?" }
    ],
    max_tokens: 50
  },
  {
    model: "gpt-4.1-mini",
    messages: [
      { role: "user", content: "Explain photosynthesis in simple terms." }
    ],
    max_tokens: 100
  },
  {
    model: "gpt-4.1",
    messages: [
      { role: "user", content: "Write a haiku about programming." }
    ],
    max_tokens: 75
  }
]

puts "✅ Prepared #{basic_requests.length} requests"
puts "  Models: gpt-4.1, gpt-4.1-mini"
puts "  Cost savings: 50% compared to individual calls"

# Submit the batch (uncomment to actually run)
# puts "\n📤 Submitting batch..."
# batch = batch_processor.submit_batch(
#   basic_requests,
#   description: "Basic batch processing example",
#   completion_window: "24h"
# )
# puts "  Batch ID: #{batch["id"]}"
# puts "  Status: #{batch["status"]}"

# =============================================================================
# 2. Customer Support Batch Processing
# =============================================================================
puts "\n2. 🎧 Customer Support Batch Processing"
puts "-" * 40

# Simulate processing customer inquiries in batch
customer_inquiries = [
  "I forgot my password and can't log into my account. Can you help me reset it?",
  "My subscription was charged twice this month. Can you check my billing history?",
  "The mobile app keeps crashing when I try to upload photos. What should I do?",
  "I want to upgrade my plan but don't see the option in my dashboard.",
  "How do I cancel my subscription and get a refund for this month?"
]

customer_batch_requests = customer_inquiries.map.with_index do |inquiry, index|
  {
    model: "gpt-4.1",
    messages: [
      {
        role: "system",
        content: "You are a helpful customer support agent. Provide clear, empathetic responses to customer inquiries."
      },
      {
        role: "user",
        content: inquiry
      }
    ],
    max_tokens: 200,
    temperature: 0.7
  }
end

puts "✅ Prepared customer support batch:"
puts "  Inquiries: #{customer_inquiries.length}"
puts "  Model: gpt-4.1 (latest with improved instruction following)"
puts "  Estimated cost savings: $#{(customer_inquiries.length * 0.01 * 0.5).round(2)} compared to individual calls"

# =============================================================================
# 3. Data Analysis Batch Processing
# =============================================================================
puts "\n3. 📊 Data Analysis Batch Processing"
puts "-" * 40

# Simulate analyzing different datasets
analysis_tasks = [
  "Analyze this sales data and identify trends: Q1: $50k, Q2: $75k, Q3: $90k, Q4: $120k",
  "Summarize customer feedback: 'Great product!', 'Needs improvement', 'Love the interface', 'Too expensive'",
  "Extract key insights from survey: 85% satisfaction, 60% would recommend, main complaint: slow loading",
  "Categorize these support tickets: Login issues (40%), Billing questions (25%), Feature requests (35%)",
  "Forecast next quarter based on: User growth 15%, Revenue increase 12%, New features planned: 3"
]

analysis_batch_requests = analysis_tasks.map do |task|
  {
    model: "gpt-4.1",
    messages: [
      {
        role: "system",
        content: "You are a data analyst. Provide clear, actionable insights from the given data."
      },
      {
        role: "user",
        content: task
      }
    ],
    max_tokens: 300,
    temperature: 0.3
  }
end

puts "✅ Prepared data analysis batch:"
puts "  Analysis tasks: #{analysis_tasks.length}"
puts "  Model: gpt-4.1 (enhanced analytical capabilities)"
puts "  Perfect for: Regular reporting, trend analysis, bulk data processing"

# =============================================================================
# 4. Code Review Batch Processing
# =============================================================================
puts "\n4. 💻 Code Review Batch Processing"
puts "-" * 40

code_snippets = [
  {
    language: "Ruby",
    code: "def fibonacci(n)\n  return n if n <= 1\n  fibonacci(n-1) + fibonacci(n-2)\nend"
  },
  {
    language: "Python", 
    code: "def quicksort(arr):\n    if len(arr) <= 1:\n        return arr\n    pivot = arr[0]\n    return quicksort([x for x in arr[1:] if x < pivot]) + [pivot] + quicksort([x for x in arr[1:] if x >= pivot])"
  },
  {
    language: "JavaScript",
    code: "function debounce(func, delay) {\n  let timeoutId;\n  return function(...args) {\n    clearTimeout(timeoutId);\n    timeoutId = setTimeout(() => func.apply(this, args), delay);\n  };\n}"
  }
]

code_review_requests = code_snippets.map do |snippet|
  {
    model: "gpt-4.1", # Excellent for code analysis
    messages: [
      {
        role: "system",
        content: "You are a senior software engineer conducting code reviews. Analyze code for quality, efficiency, and best practices."
      },
      {
        role: "user",
        content: "Please review this #{snippet[:language]} code:\n\n```#{snippet[:language].downcase}\n#{snippet[:code]}\n```\n\nProvide feedback on code quality, efficiency, and potential improvements."
      }
    ],
    max_tokens: 400,
    temperature: 0.2
  }
end

puts "✅ Prepared code review batch:"
puts "  Code snippets: #{code_snippets.length}"
puts "  Languages: Ruby, Python, JavaScript"
puts "  Model: gpt-4.1 (54.6% improvement in coding tasks vs gpt-4o)"

# =============================================================================
# 5. Batch Monitoring and Management
# =============================================================================
puts "\n5. 📈 Batch Monitoring and Management"
puts "-" * 40

puts "✅ Batch management features:"
puts "  📊 Status monitoring: check_status(batch_id)"
puts "  ⏳ Wait for completion: wait_for_completion(batch_id)"
puts "  📋 List all batches: list_batches(limit: 20)"
puts "  ❌ Cancel batch: cancel_batch(batch_id)"
puts "  📥 Retrieve results: retrieve_results(output_file_id)"

# Example monitoring workflow
puts "\n📋 Example monitoring workflow:"
puts "  # Submit batch"
puts "  batch = batch_processor.submit_batch(requests)"
puts ""
puts "  # Monitor progress"
puts "  batch_processor.check_status(batch['id']) do |status|"
puts "    progress = status['request_counts']"
puts "    puts \"Progress: #{progress['completed']}/#{progress['total']}\""
puts "  end"
puts ""
puts "  # Wait for completion with custom settings"
puts "  results = batch_processor.wait_for_completion("
puts "    batch['id'],"
puts "    poll_interval: 60,  # Check every minute"
puts "    max_wait_time: 7200 # Wait up to 2 hours"
puts "  )"

# =============================================================================
# 6. Cost Analysis and Benefits
# =============================================================================
puts "\n6. 💰 Cost Analysis and Benefits"
puts "-" * 40

# Calculate potential savings
individual_cost_per_request = 0.03  # Example cost per request
batch_discount = 0.5  # 50% discount
total_requests = basic_requests.length + customer_batch_requests.length + analysis_batch_requests.length + code_review_requests.length

individual_total_cost = total_requests * individual_cost_per_request
batch_total_cost = individual_total_cost * batch_discount
savings = individual_total_cost - batch_total_cost

puts "💡 Cost Comparison Example:"
puts "  Total requests: #{total_requests}"
puts "  Individual API calls: $#{individual_total_cost.round(2)}"
puts "  Batch API calls: $#{batch_total_cost.round(2)}"
puts "  💰 Total savings: $#{savings.round(2)} (50% discount)"

puts "\n🎯 When to Use Batch Processing:"
puts "  ✅ Processing large datasets (hundreds to thousands of requests)"
puts "  ✅ Regular reporting and analytics workflows"
puts "  ✅ Bulk content generation or analysis"
puts "  ✅ Evaluation and testing of models"
puts "  ✅ Customer support ticket processing"
puts "  ✅ Code review and analysis at scale"
puts "  ✅ Any scenario where immediate results aren't required"

puts "\n⚠️  Batch Processing Considerations:"
puts "  📅 24-hour completion window (not real-time)"
puts "  📦 Maximum 50,000 requests per batch"
puts "  🔄 Asynchronous processing (polling required)"
puts "  📊 Best for bulk operations, not interactive use cases"

# =============================================================================
# Summary
# =============================================================================
puts "\n#{"=" * 60}"
puts "🎉 BATCH PROCESSING EXAMPLE COMPLETE!"
puts "=" * 60

puts "\n✅ FEATURES DEMONSTRATED:"
puts "   📦 Basic batch submission and processing"
puts "   🎧 Customer support automation at scale"
puts "   📊 Bulk data analysis and insights"
puts "   💻 Code review automation"
puts "   📈 Progress monitoring and management"
puts "   💰 Cost optimization with 50% savings"

puts "\n🚀 NEXT STEPS:"
puts "   1. Set up your OpenAI API key"
puts "   2. Prepare your batch requests"
puts "   3. Submit batches during off-peak hours"
puts "   4. Monitor progress and retrieve results"
puts "   5. Enjoy 50% cost savings on bulk operations!"

puts "\n#{"=" * 60}"
puts "Happy batch processing with OpenAI Agents Ruby! 📦"
puts "=" * 60
#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates real-time streaming of agent responses.
# Streaming provides immediate feedback to users as responses are generated,
# creating more engaging and responsive AI applications. This is especially
# important for long responses, complex reasoning, or when using tools that
# may take time to execute.

require_relative "../../lib/raaf-core"

# ============================================================================
# STREAMING SETUP AND CONFIGURATION
# ============================================================================

puts "=== Real-Time Response Streaming Example ==="
puts "=" * 50

# Environment validation
unless ENV["OPENAI_API_KEY"]
  puts "NOTE: OPENAI_API_KEY not set. Running in demo mode."
  puts "For live streaming, set: export OPENAI_API_KEY='your-api-key'"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  puts ""
end

# ============================================================================
# TOOL DEFINITIONS FOR STREAMING DEMO
# ============================================================================

# Simulates a long-running operation to demonstrate streaming with tools.
# In production, this might be a database query, API call, or complex calculation.
#
# The delay parameter allows us to simulate variable processing time.
def analyze_data(query:, complexity: "medium")
  puts "🔧 Tool executing: analyze_data(query: #{query}, complexity: #{complexity})"

  # Simulate processing time based on complexity
  case complexity.downcase
  when "low"
    sleep(0.5)
    result = "Quick analysis complete"
  when "medium"
    sleep(1.0)
    result = "Detailed analysis with #{rand(5..10)} data points"
  when "high"
    sleep(2.0)
    result = "Comprehensive analysis with machine learning insights"
  else
    result = "Standard analysis complete"
  end

  puts "✅ Tool completed: #{result}"
  result
rescue StandardError => e
  "Error in analysis: #{e.message}"
end

# Quick response tool to demonstrate immediate streaming.
# Shows how simple tools respond quickly while maintaining streaming context.
def get_current_time(timezone: "UTC")
  puts "🔧 Tool executing: get_current_time(timezone: #{timezone})"

  time = case timezone.upcase
         when "UTC"
           Time.now.utc.strftime("%H:%M:%S UTC")
         when "EST", "ET"
           (Time.now - (5 * 3600)).strftime("%H:%M:%S EST")
         when "PST", "PT"
           (Time.now - (8 * 3600)).strftime("%H:%M:%S PST")
         else
           Time.now.strftime("%H:%M:%S (local)")
         end

  puts "✅ Tool completed: Current time is #{time}"
  "Current time: #{time}"
rescue StandardError => e
  "Error getting time: #{e.message}"
end

# ============================================================================
# AGENT SETUP FOR STREAMING
# ============================================================================

# Create agent optimized for streaming responses.
# The model choice affects streaming quality - gpt-4o provides excellent
# streaming performance with natural response chunking.
streaming_agent = RAAF::Agent.new(
  # Clear name for identification in streaming logs
  name: "StreamingAssistant",

  # Instructions emphasize responsive communication style
  instructions: "You are a helpful assistant that provides detailed responses. " \
                "Explain your reasoning step-by-step and use tools when appropriate. " \
                "Be conversational and engaging in your responses.",

  # gpt-4o provides optimal streaming performance
  model: "gpt-4o"
)

# Add streaming-compatible tools
streaming_agent.add_tool(method(:analyze_data))
streaming_agent.add_tool(method(:get_current_time))

puts "✅ Created streaming agent with #{streaming_agent.tools.length} tools"
puts "   Model: #{streaming_agent.model}"
puts "   Tools: #{streaming_agent.tools.map(&:name).join(", ")}"

# ============================================================================
# BASIC STREAMING EXAMPLE
# ============================================================================

puts "\n=== Basic Streaming Response ==="
puts "-" * 40

# Create runner for streaming
runner = RAAF::Runner.new(agent: streaming_agent)

begin
  puts "User: Tell me about the benefits of streaming AI responses"
  puts "Assistant (streaming): "

  # Stream the response character by character
  response_buffer = ""

  # Execute with streaming enabled
  result = runner.run(
    "Tell me about the benefits of streaming AI responses in user interfaces",
    stream: true
  ) do |chunk|
    # Process each streaming chunk
    if chunk.respond_to?(:content) && chunk.content
      print chunk.content
      response_buffer += chunk.content
      $stdout.flush # Ensure immediate output
    elsif chunk.is_a?(String)
      print chunk
      response_buffer += chunk
      $stdout.flush
    end
  end

  puts "\n\n✅ Streaming complete!"
  puts "   Total characters streamed: #{response_buffer.length}"
  puts "   Final turns: #{result&.turns || "N/A"}"
rescue RAAF::Error => e
  puts "\n✗ Streaming failed: #{e.message}"
  puts "\n=== Demo Mode (Simulated Streaming) ==="
  demo_response = "Streaming AI responses provides several key benefits:\n\n" \
                  "1. **Immediate Feedback** - Users see responses as they're generated\n" \
                  "2. **Improved Perceived Performance** - Applications feel more responsive\n" \
                  "3. **Better User Experience** - Reduces waiting time anxiety\n" \
                  "4. **Progressive Disclosure** - Complex responses build gradually\n" \
                  "5. **Early Termination** - Users can stop if they have enough information"

  # Simulate streaming by printing character by character
  demo_response.each_char do |char|
    print char
    $stdout.flush
    sleep(0.02) # 20ms delay per character
  end
  puts "\n\n✅ Demo streaming complete!"
end

# ============================================================================
# STREAMING WITH TOOL CALLS
# ============================================================================

puts "\n=== Streaming with Tool Execution ==="
puts "-" * 40

begin
  puts "User: What time is it and can you analyze the keyword 'productivity'?"
  puts "Assistant (streaming): "

  # Track tool calls during streaming
  tool_calls_made = []
  response_parts = []

  runner.run(
    "What time is it in EST timezone? Also, please analyze the keyword 'productivity' with medium complexity.",
    stream: true
  ) do |chunk|
    # Handle different types of streaming events
    case chunk
    when String
      print chunk
      response_parts << chunk
      $stdout.flush
    else
      # Check if this is a tool call event
      if chunk.respond_to?(:tool_calls) && chunk.tool_calls
        tool_calls_made.concat(chunk.tool_calls)
        puts "\n🔧 [Tool called during streaming]"
      elsif chunk.respond_to?(:content) && chunk.content
        print chunk.content
        response_parts << chunk.content
        $stdout.flush
      end
    end
  end

  puts "\n\n✅ Streaming with tools complete!"
  puts "   Response parts: #{response_parts.length}"
  puts "   Tool calls made: #{tool_calls_made.length}"
rescue RAAF::Error => e
  puts "\n✗ Streaming with tools failed: #{e.message}"
  puts "\n=== Demo Mode (Tool Execution) ==="

  # Demonstrate tools directly
  puts "Executing tools directly:"
  time_result = get_current_time(timezone: "EST")
  analysis_result = analyze_data(query: "productivity", complexity: "medium")

  puts "\nCombined response:"
  puts "I'll help you with both requests. #{time_result}"
  puts "Now analyzing productivity: #{analysis_result}"
  puts "Productivity analysis shows this is a valuable keyword for time management applications."
end

# ============================================================================
# STREAMING PERFORMANCE COMPARISON
# ============================================================================

puts "\n=== Streaming vs Non-Streaming Performance ==="
puts "-" * 40

# Compare response times for streaming vs non-streaming
test_query = "Explain the concept of microservices architecture"

begin
  # Test streaming response time
  puts "Testing streaming response time..."
  streaming_start = Time.now

  chars_received = 0
  first_chunk_time = nil

  runner.run(test_query, stream: true) do |chunk|
    first_chunk_time ||= Time.now
    if chunk.respond_to?(:content) && chunk.content
      chars_received += chunk.content.length
    elsif chunk.is_a?(String)
      chars_received += chunk.length
    end
  end

  streaming_total = Time.now - streaming_start
  first_chunk_delay = first_chunk_time ? (first_chunk_time - streaming_start) : 0

  puts "✅ Streaming results:"
  puts "   Time to first chunk: #{(first_chunk_delay * 1000).round(1)}ms"
  puts "   Total streaming time: #{(streaming_total * 1000).round(1)}ms"
  puts "   Characters received: #{chars_received}"

  # Test non-streaming response time
  puts "\nTesting non-streaming response time..."
  non_streaming_start = Time.now

  result = runner.run(test_query, stream: false)
  non_streaming_total = Time.now - non_streaming_start

  puts "✅ Non-streaming results:"
  puts "   Total response time: #{(non_streaming_total * 1000).round(1)}ms"
  puts "   Response length: #{result&.final_output&.length || 0} characters"

  # Performance analysis
  puts "\n=== Performance Analysis ==="
  if first_chunk_delay.positive?
    puts "Time to first content: #{(first_chunk_delay * 1000).round(1)}ms (streaming advantage)"
    puts "Perceived responsiveness: #{first_chunk_delay < non_streaming_total ? "Better" : "Similar"}"
  end
rescue RAAF::Error => e
  puts "✗ Performance test failed: #{e.message}"
  puts "\n=== Demo Mode (Performance Simulation) ==="
  puts "✅ Streaming results:"
  puts "   Time to first chunk: 150ms"
  puts "   Total streaming time: 2,340ms"
  puts "   Characters received: 1,247"
  puts "\n✅ Non-streaming results:"
  puts "   Total response time: 2,500ms"
  puts "   Response length: 1,247 characters"
  puts "\n=== Performance Analysis ==="
  puts "Time to first content: 150ms (streaming advantage)"
  puts "Perceived responsiveness: Better"
end

# ============================================================================
# STREAMING BEST PRACTICES
# ============================================================================

puts "\n=== Streaming Best Practices ==="
puts "-" * 40

puts "✅ When to use streaming:"
puts "   • Long responses (>500 characters)"
puts "   • Complex reasoning or multi-step processes"
puts "   • Tool-heavy workflows"
puts "   • Interactive user interfaces"
puts "   • Real-time applications"

puts "\n✅ Implementation considerations:"
puts "   • Buffer management for partial responses"
puts "   • Error handling during streaming"
puts "   • Tool call interruption support"
puts "   • Client-side rendering optimization"
puts "   • Network failure recovery"

puts "\n✅ User experience tips:"
puts "   • Show typing indicators"
puts "   • Enable streaming interruption"
puts "   • Provide progress feedback for tools"
puts "   • Handle partial responses gracefully"
puts "   • Implement proper error recovery"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n=== Real-Time Streaming Example Complete! ==="
puts "\nKey Features Demonstrated:"
puts "• Basic response streaming with immediate user feedback"
puts "• Streaming with tool execution and real-time progress"
puts "• Performance comparison between streaming and non-streaming"
puts "• Production patterns for streaming implementation"
puts "• Best practices for streaming user experiences"

puts "\nStreaming Benefits:"
puts "• Improved perceived performance and responsiveness"
puts "• Early feedback for tool execution progress"
puts "• Reduced user anxiety during AI processing"

puts "\nProduction Considerations:"
puts "• Implement proper error handling for interrupted streams"
puts "• Consider bandwidth and connection quality"
puts "• Buffer management for smooth UI updates"
puts "• Graceful degradation when streaming fails"

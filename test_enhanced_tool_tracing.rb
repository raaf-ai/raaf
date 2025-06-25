#!/usr/bin/env ruby
# Test script for enhanced tool tracing
# This demonstrates how to capture more detailed information from tool calls

require_relative 'lib/openai_agents'

# Configure environment with enhanced tracing
ENV['OPENAI_API_KEY'] ||= 'your-api-key-here'
ENV['OPENAI_AGENTS_TRACE_DEBUG'] = 'true'

# Create configuration with detailed tool tracing enabled
config = OpenAIAgents::Configuration.new
config.set("tracing.detailed_tool_tracing", true)
config.set("tracing.capture_openai_tool_results", true)
config.set("tracing.trace_include_sensitive_data", true)

puts "=== Enhanced Tool Tracing Test ==="
puts "This test will create an agent that uses the web_search tool"
puts "and capture detailed information about the tool calls."
puts

# Create a research agent with web_search tool
research_agent = OpenAIAgents::Agent.new(
  name: "ResearchAgent",
  instructions: <<~INSTRUCTIONS,
    You are a research assistant that helps find information on the web.
    When asked about a topic, use the web_search tool to find relevant information.
    Provide a comprehensive summary based on the search results.
  INSTRUCTIONS
  model: "gpt-4o",
  tools: [{ type: "web_search" }]
)

# Set up enhanced tracing
tracer = OpenAIAgents::Tracing::SpanTracer.new

# Add console processor for debugging
tracer.add_processor(OpenAIAgents::Tracing::ConsoleSpanProcessor.new)

# Add Rails processor if available
if defined?(OpenAIAgents::Tracing::RailsProcessor)
  tracer.add_processor(OpenAIAgents::Tracing::RailsProcessor.new)
end

# Add a custom processor to capture tool details
class DetailedToolProcessor
  def on_span_start(span)
    if span.kind == :tool
      puts "\n[TOOL START] #{span.name}"
      puts "  Span ID: #{span.span_id}"
      puts "  Attributes: #{span.attributes.inspect}"
    end
  end
  
  def on_span_end(span)
    if span.kind == :tool
      puts "\n[TOOL END] #{span.name}"
      puts "  Duration: #{(span.duration * 1000).round(2)}ms" if span.duration
      
      # Show detailed attributes
      if span.attributes["function.name"]
        puts "  Function: #{span.attributes["function.name"]}"
      end
      
      if span.attributes["function.input"]
        puts "  Input: #{span.attributes["function.input"].inspect}"
      end
      
      if span.attributes["function.output"]
        output = span.attributes["function.output"]
        if output.is_a?(String) && output.length > 200
          puts "  Output: #{output[0..200]}..."
        else
          puts "  Output: #{output.inspect}"
        end
      end
      
      if span.attributes["function.has_results"]
        puts "  Has Results: #{span.attributes["function.has_results"]}"
      end
      
      if span.attributes["web_search.query"]
        puts "  Search Query: #{span.attributes["web_search.query"]}"
      end
      
      puts "  Status: #{span.status}"
    end
  end
end

tracer.add_processor(DetailedToolProcessor.new)

# Create runner with enhanced tracing
runner = OpenAIAgents::Runner.new(
  agent: research_agent,
  tracer: tracer
)

# Test queries that will trigger web_search
test_queries = [
  "What are the latest developments in quantum computing as of 2024?",
  "Find information about OpenAI's newest models and their capabilities",
  "Search for best practices in Ruby on Rails API development"
]

test_queries.each_with_index do |query, index|
  puts "\n" + "="*60
  puts "Test #{index + 1}: #{query}"
  puts "="*60
  
  begin
    result = runner.run(query)
    
    puts "\n--- Agent Response ---"
    puts result.messages.last[:content]
    
    # Export trace data for analysis
    trace_data = tracer.export_spans(format: :json)
    
    # Save trace to file for detailed analysis
    File.write("trace_#{index + 1}_enhanced.json", trace_data)
    puts "\nTrace saved to: trace_#{index + 1}_enhanced.json"
    
    # Clear spans for next test
    tracer.clear
    
  rescue => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(5)
  end
  
  # Small delay between tests
  sleep 2
end

puts "\n" + "="*60
puts "Enhanced Tool Tracing Test Complete!"
puts "="*60

# Summary of what to look for in the traces:
puts <<~SUMMARY

  What to look for in the enhanced traces:
  
  1. Tool Span Details:
     - function.name: The tool being called (e.g., "web_search")
     - function.input: The parameters passed to the tool
     - function.output: The results from the tool (if captured)
     - function.has_results: Whether results were captured
     
  2. Web Search Specific:
     - web_search.query: The search query used
     - Results may be embedded in the assistant's response
     
  3. Span Hierarchy:
     - Agent spans as parents
     - Tool spans as children
     - LLM spans for API calls
     
  4. Timing Information:
     - Duration of each tool call
     - Start and end times
     
  To view the flow visualization:
  1. Visit /tracing/flows in your Rails app
  2. Filter by the trace IDs from the JSON files
  3. See the visual representation of agent-tool interactions
SUMMARY
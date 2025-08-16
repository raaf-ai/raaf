#!/usr/bin/env ruby
# frozen_string_literal: true

# Agent with Tools Example
#
# This example demonstrates how to create agents that use the new unified Tool DSL,
# showcasing auto-discovery, mixed tool types, and real agent conversations.

require "raaf-core"
require "raaf-dsl"

# Define a simple calculator tool
class CalculatorTool < RAAF::DSL::Tools::Tool
  # Auto-generates name: "calculator", description, and parameters
  def call(operation:, a:, b:)
    case operation.downcase
    when "add", "+"
      { result: a + b, operation: "addition" }
    when "subtract", "-"
      { result: a - b, operation: "subtraction" }
    when "multiply", "*"
      { result: a * b, operation: "multiplication" }
    when "divide", "/"
      if b.zero?
        { error: "Division by zero is not allowed" }
      else
        { result: a.to_f / b, operation: "division" }
      end
    else
      { error: "Unknown operation: #{operation}. Supported: add, subtract, multiply, divide" }
    end
  end
end

# Define a text analyzer tool
class TextAnalyzerTool < RAAF::DSL::Tools::Tool
  configure description: "Analyze text for various properties like word count, sentiment, and readability"
  
  def call(text:, analysis_type: "basic")
    return { error: "Text cannot be empty" } if text.strip.empty?
    
    case analysis_type.downcase
    when "basic"
      basic_analysis(text)
    when "detailed"
      detailed_analysis(text)
    when "sentiment"
      sentiment_analysis(text)
    else
      { error: "Unknown analysis type: #{analysis_type}. Supported: basic, detailed, sentiment" }
    end
  end
  
  private
  
  def basic_analysis(text)
    words = text.split(/\s+/)
    {
      word_count: words.length,
      character_count: text.length,
      character_count_no_spaces: text.gsub(/\s/, '').length,
      sentence_count: text.split(/[.!?]+/).reject(&:empty?).length,
      paragraph_count: text.split(/\n\s*\n/).reject(&:empty?).length
    }
  end
  
  def detailed_analysis(text)
    basic = basic_analysis(text)
    words = text.downcase.split(/\s+/).map { |w| w.gsub(/[^\w]/, '') }.reject(&:empty?)
    
    basic.merge({
      unique_words: words.uniq.length,
      average_word_length: words.empty? ? 0 : (words.map(&:length).sum.to_f / words.length).round(2),
      longest_word: words.max_by(&:length) || "",
      shortest_word: words.min_by(&:length) || "",
      word_frequency: words.tally.sort_by { |_, count| -count }.first(10).to_h
    })
  end
  
  def sentiment_analysis(text)
    # Simple sentiment analysis (in real app, you'd use a proper sentiment API)
    positive_words = %w[good great excellent amazing wonderful fantastic love like happy joy]
    negative_words = %w[bad terrible awful horrible hate dislike sad angry disappointed]
    
    words = text.downcase.split(/\s+/).map { |w| w.gsub(/[^\w]/, '') }
    
    positive_count = words.count { |word| positive_words.include?(word) }
    negative_count = words.count { |word| negative_words.include?(word) }
    
    sentiment = if positive_count > negative_count
                  "positive"
                elsif negative_count > positive_count
                  "negative"
                else
                  "neutral"
                end
    
    {
      sentiment: sentiment,
      positive_words_found: positive_count,
      negative_words_found: negative_count,
      confidence: ((positive_count + negative_count).to_f / words.length * 100).round(2)
    }
  end
end

# Define a time utility tool
class TimeUtilityTool < RAAF::DSL::Tools::Tool
  configure name: "time_helper",
            description: "Utility tool for time-related operations including timezone conversions and formatting"
  
  def call(operation:, **params)
    case operation.downcase
    when "current_time"
      current_time(params[:timezone] || "UTC", params[:format])
    when "convert_timezone"
      convert_timezone(params[:time], params[:from_zone], params[:to_zone])
    when "time_difference"
      time_difference(params[:start_time], params[:end_time])
    when "format_time"
      format_time(params[:time], params[:format])
    else
      { error: "Unknown operation: #{operation}. Supported: current_time, convert_timezone, time_difference, format_time" }
    end
  end
  
  private
  
  def current_time(timezone = "UTC", format = nil)
    time = case timezone.upcase
           when "UTC" then Time.now.utc
           when "EST" then Time.now.utc - 5 * 3600
           when "PST" then Time.now.utc - 8 * 3600
           when "CET" then Time.now.utc + 1 * 3600
           when "JST" then Time.now.utc + 9 * 3600
           else Time.now.utc
           end
    
    formatted_time = format ? time.strftime(format) : time.to_s
    
    {
      timezone: timezone,
      timestamp: time.to_i,
      iso_format: time.iso8601,
      formatted: formatted_time,
      human_readable: time.strftime("%Y-%m-%d %H:%M:%S %Z")
    }
  end
  
  def convert_timezone(time_str, from_zone, to_zone)
    # Simplified timezone conversion
    { 
      original_time: time_str,
      from_timezone: from_zone,
      to_timezone: to_zone,
      converted_time: "Conversion simulation: #{time_str} from #{from_zone} to #{to_zone}"
    }
  end
  
  def time_difference(start_time, end_time)
    {
      start_time: start_time,
      end_time: end_time,
      difference: "Time difference calculation simulation"
    }
  end
  
  def format_time(time_str, format)
    {
      original_time: time_str,
      format: format,
      formatted_time: "Formatted time simulation"
    }
  end
end

# Example weather API tool (simplified for demo)
class WeatherTool < RAAF::DSL::Tools::Tool::API
  endpoint "https://api.example-weather.com/v1"  # Demo endpoint
  timeout 10
  
  def call(city:, country: "US", units: "metric")
    # Since this is a demo, we'll simulate the API response
    simulate_weather_response(city, country, units)
  end
  
  private
  
  def simulate_weather_response(city, country, units)
    # Simulate a weather API response
    temp = rand(10..30)
    temp = ((temp * 9.0 / 5) + 32).round if units == "imperial"
    
    {
      location: "#{city}, #{country}",
      temperature: temp,
      units: units == "metric" ? "°C" : "°F",
      conditions: ["sunny", "cloudy", "partly cloudy", "rainy"].sample,
      humidity: rand(40..80),
      wind_speed: rand(5..25),
      description: "Simulated weather data for demonstration"
    }
  end
end

# Native code interpreter tool
class CodeExecutorTool < RAAF::DSL::Tools::Tool::Native
  tool_type "code_interpreter"
  
  configure name: "code_executor",
            description: "Execute Python code for data analysis and computation"
end

# Create an agent that uses all these tools
def create_multi_tool_agent
  RAAF::DSL::AgentBuilder.build do
    name "MultiTool Assistant"
    instructions <<~INSTRUCTIONS
      You are a helpful assistant with access to multiple tools for various tasks:
      
      1. Calculator - for mathematical operations
      2. Text Analyzer - for analyzing text content
      3. Time Helper - for time-related operations  
      4. Weather Tool - for weather information
      5. Code Executor - for running Python code
      
      Use these tools to help users with their requests. Be thorough and provide 
      detailed explanations of the results you get from the tools.
    INSTRUCTIONS
    
    model "gpt-4o"
    
    # Add tools using auto-discovery
    use_tool :calculator
    use_tool :text_analyzer
    use_tool :time_helper
    use_tool :weather
    use_tool :code_executor
  end
end

# Register tools in a namespace for better organization
module ToolsExample
  module Tools
    # Tools can be organized in namespaces
    CalculatorTool = ::CalculatorTool
    TextAnalyzerTool = ::TextAnalyzerTool
    TimeUtilityTool = ::TimeUtilityTool
    WeatherTool = ::WeatherTool
    CodeExecutorTool = ::CodeExecutorTool
  end
end

# Demonstration
if __FILE__ == $0
  puts "=== Agent with Tools Example ==="
  puts
  
  # Register our namespace for auto-discovery
  RAAF::DSL::Tools::ToolRegistry.register_namespace("ToolsExample::Tools")
  
  # Create instances of our tools to trigger auto-registration
  tools = [
    CalculatorTool.new,
    TextAnalyzerTool.new,
    TimeUtilityTool.new,
    WeatherTool.new,
    CodeExecutorTool.new
  ]
  
  puts "Created #{tools.length} tools:"
  tools.each_with_index do |tool, i|
    puts "  #{i + 1}. #{tool.name}: #{tool.description}"
    puts "     Type: #{tool.class.name}"
    puts "     Native: #{tool.respond_to?(:native?) && tool.native?}"
    puts "     Enabled: #{tool.enabled?}"
  end
  puts
  
  # Show auto-discovery in action
  puts "=== Auto-Discovery Test ==="
  tool_names = [:calculator, :text_analyzer, :time_helper, :weather, :code_executor]
  
  tool_names.each do |tool_name|
    begin
      found_tool = RAAF::DSL::Tools::ToolRegistry.get(tool_name, strict: false)
      if found_tool
        puts "✓ #{tool_name} -> #{found_tool.name}"
      else
        puts "✗ #{tool_name} not found"
      end
    rescue => e
      puts "✗ #{tool_name} error: #{e.message}"
    end
  end
  puts
  
  # Test individual tools
  puts "=== Tool Testing ==="
  puts
  
  # Test calculator
  puts "1. Testing Calculator Tool:"
  calc_tool = CalculatorTool.new
  result = calc_tool.call(operation: "multiply", a: 7, b: 8)
  puts "   7 × 8 = #{result[:result]} (#{result[:operation]})"
  
  # Test text analyzer
  puts "\n2. Testing Text Analyzer Tool:"
  text_tool = TextAnalyzerTool.new
  sample_text = "This is a great example of text analysis. It's wonderful how we can analyze text automatically!"
  result = text_tool.call(text: sample_text, analysis_type: "sentiment")
  puts "   Text: \"#{sample_text}\""
  puts "   Sentiment: #{result[:sentiment]} (confidence: #{result[:confidence]}%)"
  
  # Test time utility
  puts "\n3. Testing Time Utility Tool:"
  time_tool = TimeUtilityTool.new
  result = time_tool.call(operation: "current_time", timezone: "UTC")
  puts "   Current UTC time: #{result[:human_readable]}"
  
  # Test weather tool (simulated)
  puts "\n4. Testing Weather Tool:"
  weather_tool = WeatherTool.new
  result = weather_tool.call(city: "Tokyo", country: "JP", units: "metric")
  puts "   Weather in #{result[:location]}: #{result[:temperature]}#{result[:units]}, #{result[:conditions]}"
  
  # Test native tool (configuration only)
  puts "\n5. Testing Native Code Executor Tool:"
  code_tool = CodeExecutorTool.new
  puts "   Tool name: #{code_tool.name}"
  puts "   Native tool: #{code_tool.native?}"
  puts "   Tool definition: #{code_tool.to_tool_definition}"
  
  puts
  
  # Create and show agent configuration
  puts "=== Agent Configuration ==="
  begin
    agent = create_multi_tool_agent
    puts "Agent created successfully:"
    puts "  Name: #{agent.name}"
    puts "  Model: #{agent.model}"
    puts "  Tools available: #{agent.tools.length}"
    
    agent.tools.each_with_index do |tool, i|
      puts "    #{i + 1}. #{tool.name} (#{tool.class.name})"
    end
    
    puts
    
    # Show tool definitions for OpenAI
    puts "=== Tool Definitions for OpenAI API ==="
    agent.tools.each do |tool|
      definition = tool.to_tool_definition
      puts "Tool: #{tool.name}"
      puts "  Type: #{definition[:type]}"
      if definition[:function]
        puts "  Function: #{definition[:function][:name]}"
        puts "  Parameters: #{definition[:function][:parameters][:properties].keys.join(', ')}"
      end
      puts
    end
    
  rescue => e
    puts "Error creating agent: #{e.message}"
    puts "This might be expected if RAAF::DSL::AgentBuilder is not available"
  end
  
  # Performance test
  puts "=== Performance Test ==="
  require 'benchmark'
  
  calc_tool = CalculatorTool.new
  iterations = 1000
  
  time = Benchmark.measure do
    iterations.times do
      calc_tool.call(operation: "add", a: 5, b: 3)
    end
  end
  
  puts "Calculator tool performance:"
  puts "  #{iterations} calls in #{time.real.round(4)}s"
  puts "  Average: #{(time.real / iterations * 1000).round(2)}ms per call"
  
  puts
  
  # Registry statistics
  puts "=== Registry Statistics ==="
  begin
    stats = RAAF::DSL::Tools::ToolRegistry.statistics
    puts "Registry performance:"
    puts "  Registered tools: #{stats[:registered_tools]}"
    puts "  Total lookups: #{stats[:lookups]}"
    puts "  Cache hits: #{stats[:cache_hits]}"
    puts "  Cache hit ratio: #{(stats[:cache_hit_ratio] * 100).round(1)}%"
    puts "  Auto-discoveries: #{stats[:discoveries]}"
  rescue => e
    puts "Registry statistics not available: #{e.message}"
  end
  
  puts
  puts "=== Example Usage Scenarios ==="
  puts
  puts "This agent can handle requests like:"
  puts '• "What is 25 times 37?"'
  puts '• "Analyze the sentiment of this text: I love this new feature!"'
  puts '• "What time is it in Tokyo?"'
  puts '• "What\'s the weather like in London?"'
  puts '• "Execute this Python code: print(sum(range(100)))"'
  puts
  puts "All tools are automatically discovered and integrated into the agent,"
  puts "providing a seamless experience for both developers and users."
  
  puts "\nAgent with tools example completed successfully!"
end
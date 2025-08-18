#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating the new unified tool architecture
#
# This shows how to create tools using the new system with:
# - Convention over configuration
# - Automatic registration
# - Single unified interface
# - User tool override capability

require "bundler/setup"
require "raaf"
require "raaf/tool"
require "raaf/tool/api"
require "raaf/tool/native"
require "raaf/tool_registry"

puts "=== RAAF Unified Tool Architecture Example ==="
puts

# Example 1: Simple function tool with conventions
class CalculatorTool < RAAF::Tool
  # Name automatically generated as "calculator"
  # Description automatically generated as "Tool for calculator operations"
  
  def call(expression:)
    puts "  Evaluating: #{expression}"
    result = eval(expression)
    puts "  Result: #{result}"
    result
  rescue => e
    { error: e.message }
  end
end

# Example 2: API tool with configuration
class WeatherTool < RAAF::Tool::API
  endpoint "https://api.openweathermap.org/data/2.5"
  api_key_env "OPENWEATHER_API_KEY"
  timeout 10
  
  configure name: "weather",
           description: "Get current weather for a city"
  
  def call(city:, units: "metric")
    get("/weather", params: {
      q: city,
      units: units,
      appid: api_key
    })
  end
end

# Example 3: Native OpenAI tool
class WebSearchTool < RAAF::Tool::Native
  configure name: "web_search",
           description: "Search the web using OpenAI's web search"
  
  native_config do
    web_search true
  end
end

# Example 4: Tool with explicit parameters
class TextAnalyzerTool < RAAF::Tool
  configure description: "Analyze text for sentiment and key phrases"
  
  parameters do
    property :text, type: "string", description: "Text to analyze"
    property :language, type: "string", enum: ["en", "es", "fr"], description: "Language of text"
    property :detail_level, type: "string", enum: ["basic", "detailed"], description: "Level of analysis detail"
    required :text
  end
  
  def call(text:, language: "en", detail_level: "basic")
    # Simulate analysis
    {
      sentiment: text.include?("good") ? "positive" : "neutral",
      language: language,
      word_count: text.split.length,
      detail_level: detail_level
    }
  end
end

# Example 5: User-defined tool that overrides RAAF tool
module Ai
  module Tools
    class WebSearchTool < RAAF::Tool
      # This will override RAAF::Tools::WebSearchTool in discovery
      configure description: "Custom web search implementation"
      
      def call(query:, max_results: 5)
        puts "  Using custom web search for: #{query}"
        {
          source: "custom",
          query: query,
          results: ["Custom result 1", "Custom result 2"]
        }
      end
    end
  end
end

puts "1. Tool Registration & Discovery"
puts "=" * 50

# Tools are automatically registered when defined
puts "Registered tools:"
RAAF::ToolRegistry.list.each do |tool_name|
  puts "  - #{tool_name}"
end
puts

puts "2. Tool Resolution"
puts "=" * 50

# Different ways to resolve tools
calculator = RAAF::ToolRegistry.lookup(:calculator)
puts "Lookup :calculator => #{calculator}"

weather = RAAF::ToolRegistry.resolve("weather")
puts "Resolve 'weather' => #{weather}"

# User tool overrides RAAF tool
web_search = RAAF::ToolRegistry.lookup(:web_search)
puts "Lookup :web_search => #{web_search} (user override)"
puts

puts "3. Tool Instantiation & Usage"
puts "=" * 50

# Create and use calculator tool
calc = CalculatorTool.new
puts "Calculator tool:"
calc.call(expression: "2 + 2 * 3")
puts

# Create text analyzer with options
analyzer = TextAnalyzerTool.new
puts "Text analyzer tool:"
result = analyzer.call(text: "This is a good example", language: "en")
puts "  Analysis result: #{result}"
puts

puts "4. Tool Definitions (OpenAI Format)"
puts "=" * 50

# Show how tools generate OpenAI-compatible definitions
calc_def = calc.to_tool_definition
puts "Calculator definition:"
puts "  Type: #{calc_def[:type]}"
puts "  Name: #{calc_def[:function][:name]}"
puts "  Parameters: #{calc_def[:function][:parameters][:properties].keys}"
puts

# Native tool has different format
native_search = WebSearchTool.new
native_def = native_search.to_tool_definition
puts "Native web search definition:"
puts "  Type: #{native_def[:type]}"
puts "  Config: #{native_def[:web_search]}"
puts

puts "5. Backward Compatibility"
puts "=" * 50

# Convert to FunctionTool for compatibility
function_tool = calc.to_function_tool
puts "Converted to FunctionTool: #{function_tool.class}"
puts "  Name: #{function_tool.name}"
puts "  Can call: #{function_tool.callable?}"
puts

puts "6. DSL Integration Example"
puts "=" * 50

# Show how tools work in agent DSL
example_code = <<~RUBY
  class ResearchAgent < RAAF::DSL::Agent
    # All these forms work:
    tool :calculator                    # Auto-discovery by name
    tool CalculatorTool                 # Direct class reference
    tool :weather, timeout: 5           # With options
    tool :text_analyzer do              # With block config
      detail_level "detailed"
    end
    
    # User tools automatically override RAAF tools
    tool :web_search  # Will use Ai::Tools::WebSearchTool
  end
RUBY

puts "Agent DSL usage:"
puts example_code
puts

puts "7. Key Features Demonstrated"
puts "=" * 50
puts "✅ Convention over configuration - minimal code needed"
puts "✅ Automatic tool registration via inherited hook"
puts "✅ Name-based discovery with auto-generated names"
puts "✅ User tools (Ai::Tools::*) override RAAF tools"
puts "✅ Single unified interface via Tool base class"
puts "✅ Support for API, Native, and Function tool types"
puts "✅ Backward compatibility with FunctionTool"
puts "✅ Thread-safe registry operations"
puts

puts "Example completed successfully!"
#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic API Tool Example
#
# This example demonstrates how to create a simple external API tool
# using the Tool::API class with automatic parameter generation.

require "raaf-core"
require "raaf-dsl"

# Simple weather API tool that demonstrates basic API integration
class WeatherTool < RAAF::DSL::Tools::Tool::API
  # Configure the API endpoint
  endpoint "https://api.openweathermap.org/data/2.5/weather"
  
  # Set API key from environment
  api_key ENV.fetch('OPENWEATHER_API_KEY', 'demo_key')
  
  # Configure timeout (optional)
  timeout 10
  
  # Set default headers (optional)
  headers({
    "User-Agent" => "RAAF-Weather-Tool/1.0"
  })
  
  # The call method defines the tool's functionality
  # Parameters are automatically inferred from the method signature
  def call(city:, country: "US", units: "metric")
    # Validate inputs
    return { error: "City cannot be empty" } if city.strip.empty?
    
    # Build location string
    location = country ? "#{city},#{country}" : city
    
    # Make the API request using the built-in get method
    response = get(params: {
      q: location,
      units: units,
      appid: api_key
    })
    
    # Handle API errors
    return response if response[:error]
    
    # Format the response for better usability
    format_weather_response(response)
  end
  
  private
  
  def format_weather_response(response)
    {
      location: "#{response['name']}, #{response.dig('sys', 'country')}",
      temperature: response.dig('main', 'temp'),
      feels_like: response.dig('main', 'feels_like'),
      humidity: response.dig('main', 'humidity'),
      pressure: response.dig('main', 'pressure'),
      description: response.dig('weather', 0, 'description'),
      wind_speed: response.dig('wind', 'speed'),
      visibility: response['visibility'],
      timestamp: Time.at(response['dt']).to_s
    }
  end
end

# Demonstration of the tool
if __FILE__ == $0
  puts "=== Basic API Tool Example ==="
  puts
  
  # Create an instance of the tool
  weather_tool = WeatherTool.new
  
  # Show auto-generated metadata
  puts "Tool Name: #{weather_tool.name}"
  puts "Description: #{weather_tool.description}"
  puts "Enabled: #{weather_tool.enabled?}"
  puts
  
  # Show the auto-generated tool definition
  puts "Tool Definition:"
  definition = weather_tool.to_tool_definition
  puts "  Type: #{definition[:type]}"
  puts "  Function Name: #{definition[:function][:name]}"
  puts "  Function Description: #{definition[:function][:description]}"
  puts "  Parameters:"
  definition[:function][:parameters][:properties].each do |param, schema|
    required = definition[:function][:parameters][:required].include?(param)
    puts "    #{param}: #{schema[:type]}#{required ? ' (required)' : ' (optional)'}"
    puts "      Description: #{schema[:description]}" if schema[:description]
  end
  puts
  
  # Test the tool with sample data
  puts "Testing tool with sample data..."
  
  # Test 1: Valid city
  puts "\n1. Testing with valid city (London):"
  result = weather_tool.call(city: "London", country: "UK", units: "metric")
  if result[:error]
    puts "   Error: #{result[:error]}"
    puts "   Message: #{result[:message]}" if result[:message]
  else
    puts "   Location: #{result[:location]}"
    puts "   Temperature: #{result[:temperature]}°C"
    puts "   Description: #{result[:description]}"
    puts "   Humidity: #{result[:humidity]}%"
  end
  
  # Test 2: Invalid city  
  puts "\n2. Testing with empty city:"
  result = weather_tool.call(city: "", country: "US")
  puts "   Result: #{result}"
  
  # Test 3: Different units
  puts "\n3. Testing with Fahrenheit units:"
  result = weather_tool.call(city: "New York", units: "imperial")
  if result[:error]
    puts "   Error: #{result[:error]}"
  else
    puts "   Location: #{result[:location]}"
    puts "   Temperature: #{result[:temperature]}°F"
    puts "   Description: #{result[:description]}"
  end
  
  puts "\n=== Tool Configuration ==="
  config = weather_tool.tool_configuration
  puts "Enabled: #{config[:enabled]}"
  puts "Class: #{config[:metadata][:class]}"
  puts "Native: #{config[:native] || false}"
  
  puts "\n=== Auto-Discovery Test ==="
  # Test auto-discovery (if registry is available)
  begin
    registry_tool = RAAF::DSL::Tools::ToolRegistry.get(:weather, strict: false)
    if registry_tool
      puts "Tool auto-discovered in registry: #{registry_tool}"
    else
      puts "Tool not found in registry (manual registration may be needed)"
    end
  rescue => e
    puts "Registry not available: #{e.message}"
  end
  
  puts "\nExample completed successfully!"
end
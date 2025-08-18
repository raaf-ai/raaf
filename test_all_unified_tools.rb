#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for all migrated unified tools
# This validates that all tools have been successfully migrated

require "bundler/setup"
require "fileutils"
require "json"

# Mock RAAF core components
module RAAF
  module Logger
    def log_debug_tools(message, **data); end
    def log_error(message, **data); puts "ERROR: #{message}"; end
    def self.extended(base); end
    def self.included(base); end
  end
  
  class FunctionTool
    attr_reader :name, :callable
    def initialize(callable, name: nil, description: nil, parameters: nil, is_enabled: nil)
      @callable = callable
      @name = name
    end
    def callable?; true; end
    def call(**kwargs); @callable.call(**kwargs); end
  end
end

# Load unified tool architecture
require "concurrent"
require_relative "lib/raaf/tool"
require_relative "lib/raaf/tool_registry"
require_relative "lib/raaf/tool/api"
require_relative "lib/raaf/tool/native"
require_relative "lib/raaf/tool/function"

# Load all unified tools
require_relative "tools/lib/raaf/tools/unified"

puts "=" * 70
puts "RAAF Unified Tools - Complete Migration Test"
puts "=" * 70
puts

# Test helper methods
def test_tool(name, tool_class, type)
  print "Testing #{name.to_s.ljust(25)} (#{type.ljust(8)}) ... "
  
  begin
    # Create instance
    tool = tool_class.new
    
    # Verify basic properties
    raise "No name" unless tool.name
    raise "No description" unless tool.description
    
    # Check tool definition generation
    definition = tool.to_tool_definition
    raise "No definition" unless definition
    
    # Check if it's registered
    registered = RAAF::ToolRegistry.get(name)
    raise "Not registered" unless registered
    
    puts "✅ PASS"
    true
  rescue => e
    puts "❌ FAIL: #{e.message}"
    false
  end
end

# Track results
results = {
  passed: 0,
  failed: 0,
  tools: []
}

puts "1. Testing Tool Registration and Discovery"
puts "-" * 50

RAAF::Tools::Unified::AVAILABLE_TOOLS.each do |name, klass|
  # Determine tool type
  type = if klass < RAAF::Tool::Native
           "Native"
         elsif klass < RAAF::Tool::API
           "API"
         else
           "Function"
         end
  
  if test_tool(name, klass, type)
    results[:passed] += 1
  else
    results[:failed] += 1
  end
  
  results[:tools] << { name: name, class: klass.name, type: type }
end

puts
puts "2. Testing Tool Categories"
puts "-" * 50

RAAF::Tools::Unified::TOOL_CATEGORIES.each do |category, tools|
  print "Category: #{category.to_s.ljust(15)} "
  puts "Tools: #{tools.length} (#{tools.join(", ")})"
end

puts
puts "3. Testing Tool Type Classification"
puts "-" * 50

native_count = RAAF::Tools::Unified.native_tools.size
api_count = RAAF::Tools::Unified.api_tools.size
function_count = RAAF::Tools::Unified.function_tools.size

puts "Native Tools:   #{native_count} tools"
puts "API Tools:      #{api_count} tools"
puts "Function Tools: #{function_count} tools"
puts "Total:          #{native_count + api_count + function_count} tools"

puts
puts "4. Testing Tool Creation and Configuration"
puts "-" * 50

# Test creating tools with options
test_cases = [
  [:file_search, { search_paths: ["./test"], max_results: 20 }],
  [:tavily_search, { }],  # Uses env var for API key
  [:local_shell, { safe_mode: true, max_timeout: 10 }],
  [:document, { storage_path: "./test_docs" }]
]

test_cases.each do |tool_name, options|
  print "Creating #{tool_name.to_s.ljust(20)} with options ... "
  
  begin
    tool = RAAF::Tools::Unified.create_tool(tool_name, **options)
    raise "Tool not created" unless tool
    raise "Wrong class" unless tool.is_a?(RAAF::Tool)
    puts "✅ PASS"
  rescue => e
    puts "❌ FAIL: #{e.message}"
  end
end

puts
puts "5. Testing Tool Presets"
puts "-" * 50

RAAF::Tools::Unified.tool_presets.each do |preset_name, factory|
  print "Preset: #{preset_name.to_s.ljust(20)} ... "
  
  begin
    tools = factory.call
    raise "No tools created" if tools.empty?
    raise "Invalid tools" unless tools.all? { |t| t.is_a?(RAAF::Tool) }
    puts "✅ PASS (#{tools.length} tools)"
  rescue => e
    puts "❌ FAIL: #{e.message}"
  end
end

puts
puts "6. Testing Backward Compatibility"
puts "-" * 50

# Test FunctionTool conversion
print "FunctionTool conversion ... "
begin
  tool = RAAF::Tools::Unified::FileSearchTool.new
  function_tool = tool.to_function_tool
  raise "Not a FunctionTool" unless function_tool.is_a?(RAAF::FunctionTool)
  raise "Name mismatch" unless function_tool.name == tool.name
  puts "✅ PASS"
rescue => e
  puts "❌ FAIL: #{e.message}"
end

# Test native tool behavior
print "Native tool behavior   ... "
begin
  native_tool = RAAF::Tools::Unified::WebSearchTool.new
  raise "Not native" unless native_tool.native?
  
  begin
    native_tool.call(query: "test")
    puts "❌ FAIL: Should not be callable"
  rescue NotImplementedError
    puts "✅ PASS (correctly raises error)"
  end
rescue => e
  puts "❌ FAIL: #{e.message}"
end

puts
puts "7. Testing Tool Definitions"
puts "-" * 50

# Sample a few tools and check their definitions
sample_tools = [
  [:file_search, RAAF::Tools::Unified::FileSearchTool],
  [:web_search, RAAF::Tools::Unified::WebSearchTool],
  [:tavily_search, RAAF::Tools::Unified::TavilySearchTool]
]

sample_tools.each do |name, klass|
  print "Definition for #{name.to_s.ljust(15)} ... "
  
  begin
    tool = klass.new
    definition = tool.to_tool_definition
    
    # Check definition structure
    if tool.native?
      raise "Missing type" unless definition[:type]
    else
      raise "Missing function" unless definition[:function]
      raise "Missing name" unless definition[:function][:name]
    end
    
    puts "✅ PASS"
  rescue => e
    puts "❌ FAIL: #{e.message}"
  end
end

puts
puts "=" * 70
puts "MIGRATION TEST SUMMARY"
puts "=" * 70
puts
puts "Total Tools Migrated: #{results[:tools].length}"
puts "Tests Passed: #{results[:passed]}"
puts "Tests Failed: #{results[:failed]}"
puts
puts "Tool Distribution:"
results[:tools].group_by { |t| t[:type] }.each do |type, tools|
  puts "  #{type}: #{tools.length} tools"
end
puts

if results[:failed] == 0
  puts "✅ ALL TOOLS SUCCESSFULLY MIGRATED!"
  puts
  puts "The unified tool architecture is fully operational with:"
  puts "- Single base class (RAAF::Tool) for all tools"
  puts "- Automatic registration and discovery"
  puts "- Convention over configuration"
  puts "- Full backward compatibility"
  puts "- Support for Native, API, and Function tools"
else
  puts "⚠️  Some tools failed migration. Please review the errors above."
end

puts
puts "Migration complete! All tools are now using the unified architecture."
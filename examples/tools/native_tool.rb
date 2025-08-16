#!/usr/bin/env ruby
# frozen_string_literal: true

# Native Tool Example
#
# This example demonstrates how to create OpenAI native tools that are
# executed by OpenAI's infrastructure rather than locally.

require "raaf-core"
require "raaf-dsl"

# Code Interpreter Tool - executes Python code in OpenAI's environment
class CodeInterpreterTool < RAAF::DSL::Tools::Tool::Native
  # Set the tool type to OpenAI's code_interpreter
  tool_type "code_interpreter"
  
  # Configure basic metadata
  configure name: "code_interpreter",
            description: "Execute Python code in a secure sandboxed environment with data analysis capabilities"
end

# File Search Tool - searches through uploaded files
class FileSearchTool < RAAF::DSL::Tools::Tool::Native
  # Set the tool type to OpenAI's file_search
  tool_type "file_search"
  
  # Configure metadata and options
  configure name: "file_search",
            description: "Search through uploaded files and documents using semantic search"
  
  # Configure file search specific options
  def initialize(options = {})
    super(options.merge({
      max_results: 20,
      ranking_options: { score_threshold: 0.7 }
    }))
  end
end

# Custom Function Tool - a function that OpenAI should execute
class DataAnalysisTool < RAAF::DSL::Tools::Tool::Native
  # Function type for custom native functions
  tool_type "function"
  
  # Configure the tool
  configure name: "advanced_data_analysis",
            description: "Perform complex statistical and predictive analysis on datasets"
  
  # Define parameters for the function
  parameter :dataset_description, type: :string, required: true,
            description: "Description of the dataset to analyze"
  
  parameter :analysis_types, type: :array, required: true,
            items: { type: :string, enum: ["descriptive", "predictive", "exploratory", "diagnostic"] },
            description: "Types of analysis to perform"
  
  parameter :output_format, type: :string, default: "comprehensive",
            enum: ["summary", "comprehensive", "technical"],
            description: "Level of detail in the analysis output"
  
  parameter :include_visualizations, type: :boolean, default: true,
            description: "Whether to include charts and graphs in the analysis"
  
  parameter :confidence_threshold, type: :number, default: 0.85,
            minimum: 0.0, maximum: 1.0,
            description: "Minimum confidence threshold for predictions and insights"
  
  parameter :max_execution_time, type: :integer, default: 300,
            minimum: 30, maximum: 3600,
            description: "Maximum execution time in seconds"
end

# Mathematical Computation Tool
class MathComputationTool < RAAF::DSL::Tools::Tool::Native
  tool_type "function"
  
  configure name: "advanced_math",
            description: "Perform complex mathematical computations including calculus, linear algebra, and statistics"
  
  # Define a complex parameter schema
  parameter :operation_type, type: :string, required: true,
            enum: ["calculus", "linear_algebra", "statistics", "optimization"],
            description: "Category of mathematical operation"
  
  parameter :problem_description, type: :string, required: true,
            description: "Detailed description of the mathematical problem"
  
  parameter :input_data, type: :object, required: false,
            description: "Input data for the computation",
            properties: {
              matrices: { type: :array, items: { type: :array } },
              vectors: { type: :array, items: { type: :number } },
              functions: { type: :array, items: { type: :string } },
              constraints: { type: :array, items: { type: :string } }
            }
  
  parameter :precision, type: :integer, default: 10,
            minimum: 1, maximum: 50,
            description: "Number of decimal places for results"
  
  parameter :step_by_step, type: :boolean, default: false,
            description: "Whether to show detailed solution steps"
end

# Demonstration of native tools
if __FILE__ == $0
  puts "=== Native Tool Examples ==="
  puts
  
  tools = [
    CodeInterpreterTool.new,
    FileSearchTool.new,
    DataAnalysisTool.new,
    MathComputationTool.new
  ]
  
  tools.each_with_index do |tool, i|
    puts "#{i + 1}. #{tool.class.name}"
    puts "   Name: #{tool.name}"
    puts "   Description: #{tool.description}"
    puts "   Native: #{tool.native?}"
    puts "   Enabled: #{tool.enabled?}"
    
    # Show tool definition
    definition = tool.to_tool_definition
    puts "   Tool Definition:"
    puts "     Type: #{definition[:type]}"
    
    if definition[:function]
      func = definition[:function]
      puts "     Function Name: #{func[:name]}"
      puts "     Function Description: #{func[:description]}"
      
      if func[:parameters] && func[:parameters][:properties]
        puts "     Parameters:"
        func[:parameters][:properties].each do |param_name, param_def|
          required = func[:parameters][:required]&.include?(param_name.to_s)
          puts "       #{param_name}: #{param_def[:type]}#{required ? ' (required)' : ''}"
          puts "         Description: #{param_def[:description]}" if param_def[:description]
          puts "         Default: #{param_def[:default]}" if param_def.key?(:default)
          puts "         Enum: #{param_def[:enum]}" if param_def[:enum]
          puts "         Range: #{param_def[:minimum]} - #{param_def[:maximum]}" if param_def[:minimum] || param_def[:maximum]
        end
      end
    end
    
    # Show tool configuration
    config = tool.tool_configuration
    puts "   Configuration:"
    puts "     Native: #{config[:native]}"
    puts "     Metadata: #{config[:metadata]}"
    
    puts
  end
  
  puts "=== Testing Native Tool Behavior ==="
  puts
  
  # Test that native tools cannot be called locally
  code_tool = CodeInterpreterTool.new
  puts "Testing CodeInterpreterTool.call (should raise NotImplementedError):"
  begin
    code_tool.call(code: "print('Hello World')")
    puts "  Unexpected: Tool executed locally!"
  rescue NotImplementedError => e
    puts "  Expected: #{e.message}"
  end
  
  puts
  
  # Show how to use native tools with OpenAI API format
  puts "=== OpenAI API Integration Example ==="
  puts
  
  analysis_tool = DataAnalysisTool.new
  openai_format = analysis_tool.to_tool_definition
  
  puts "Tool definition for OpenAI API:"
  puts "```json"
  puts JSON.pretty_generate(openai_format)
  puts "```"
  
  puts
  puts "This definition can be passed directly to OpenAI's API:"
  puts "```ruby"
  puts "client = OpenAI::Client.new"
  puts "response = client.chat("
  puts "  parameters: {"
  puts "    model: 'gpt-4',"
  puts "    messages: [{ role: 'user', content: 'Analyze this data...' }],"
  puts "    tools: [analysis_tool.to_tool_definition]"
  puts "  }"
  puts ")"
  puts "```"
  
  puts
  
  # Test auto-discovery
  puts "=== Auto-Discovery Test ==="
  begin
    registry_tools = []
    tools.each do |tool|
      tool_name = tool.name.to_sym
      found_tool = RAAF::DSL::Tools::ToolRegistry.get(tool_name, strict: false)
      if found_tool
        registry_tools << "#{tool_name} -> #{found_tool}"
      end
    end
    
    if registry_tools.any?
      puts "Tools found in registry:"
      registry_tools.each { |t| puts "  #{t}" }
    else
      puts "No tools found in registry (may need manual registration)"
    end
  rescue => e
    puts "Registry not available: #{e.message}"
  end
  
  puts "\nNative tool examples completed successfully!"
  puts
  puts "Note: Native tools are designed to be used with OpenAI's API and"
  puts "cannot be executed locally. They provide configuration and metadata"
  puts "for OpenAI's built-in tools like code_interpreter and file_search."
end
# RAAF DSL - Claude Code Guide

This gem provides a Ruby DSL for building agents with a more declarative syntax, comprehensive debugging tools, flexible prompt resolution, and **automatic hash indifferent access** for seamless data handling.

## Important: Prompt Format Preference

**PREFER RUBY PROMPTS**: When creating prompts for RAAF agents, prefer using Ruby Phlex-style prompt classes over Markdown files. Ruby prompts provide:
- Type safety and validation
- IDE support and autocomplete
- Testability with RSpec
- Dynamic behavior with Ruby logic
- Better integration with the DSL

## Quick Start

```ruby
require 'raaf-dsl'

# Define agent using DSL
agent = RAAF::DSL::AgentBuilder.build do
  name "WebSearchAgent"
  instructions "You help users search the web"
  model "gpt-4o"
  
  # Add a custom web search tool
  tool :web_search do
    description "Search the web for information"
    parameter :query, type: :string, required: true
    
    execute do |query:|
      # Web search implementation
      { results: ["Result 1", "Result 2"] }
    end
  end
end

# Run the agent with a runner
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Search for Ruby programming tutorials")
```

## Core Components

- **AgentBuilder** - DSL for defining agents
- **ToolBuilder** - DSL for creating tools
- **ContextVariables** - Dynamic context management with **indifferent hash access**
- **Prompt Resolution** - Flexible prompt loading system
- **WebSearch** - Built-in web search tool
- **DebugUtils** - Enhanced debugging capabilities
- **Indifferent Access** - All data structures support both string and symbol keys seamlessly

## Agent DSL

```ruby
agent = RAAF::DSL::AgentBuilder.build do
  name "ResearchAgent"
  instructions "Research and analyze topics"
  model "gpt-4o"
  
  # Add built-in tools
  use_web_search
  use_file_search
  
  # Custom tool
  tool :analyze_sentiment do |text|
    # Sentiment analysis logic
    { sentiment: "positive", confidence: 0.85 }
  end
  
  # Configuration
  config do
    max_tokens 1000
    temperature 0.7
  end
end
```

## Tool DSL

```ruby
# Define reusable tools
calculator = RAAF::DSL::ToolBuilder.build do
  name "calculator"
  description "Perform mathematical calculations"
  
  parameter :expression, type: :string, required: true
  
  execute do |expression:|
    # Use a safe math evaluator instead of eval
    # Example: Dentaku.evaluate(expression)
    raise "Calculator not implemented - use a safe math library"
  end
end

# Create an agent and add the tool
agent = RAAF::DSL::AgentBuilder.build do
  name "MathAgent"
  instructions "You help with mathematical calculations"
  model "gpt-4o"
end

agent.add_tool(calculator)
```

## Prompt Resolution System

The DSL includes a powerful prompt resolution framework:

```ruby
# Configure prompt resolution
RAAF::DSL.configure_prompts do |config|
  config.add_path "prompts"        # Add search paths
  config.add_path "app/prompts"    # Rails-style paths
  
  # File resolver handles .md and .md.erb automatically
  config.enable_resolver :file, priority: 100
  config.enable_resolver :phlex, priority: 50
end

# PREFERRED: Ruby prompt classes (Phlex-style)
class ResearchPrompt < RAAF::DSL::Prompts::Base
  def system
    <<~SYSTEM
      You are a research assistant specializing in #{topic}.
      Provide #{depth} analysis in #{language || 'English'}.
    SYSTEM
  end
  
  def user
    "Research the latest developments in #{topic}."
  end
end

# Use prompts in agents via a custom agent class
class ResearchAgent < RAAF::DSL::Agent
  
  agent_name "researcher"
  prompt_class ResearchPrompt  # Preferred: Ruby class
  # prompt_class "research.md"  # Alternative: Markdown file
  # prompt_class "analysis.md.erb"  # Alternative: ERB template
end

# Or with simple instructions
agent = RAAF::DSL::AgentBuilder.build do
  name "Researcher"
  instructions "You are a research assistant"
  model "gpt-4o"
end
```

### Prompt Formats Supported

1. **Ruby Classes (PREFERRED)** - Type-safe, testable, dynamic
2. **Markdown Files** - Simple with `{{variable}}` interpolation
3. **ERB Templates** - Full Ruby logic with helper methods

### Why Prefer Ruby Prompts?

- **Automatic Context**: Variables are automatically accessible via method_missing
- **Testing**: Easy to test with RSpec
- **IDE Support**: Autocomplete and refactoring support
- **Dynamic**: Can use Ruby logic and conditionals
- **Clean Errors**: Clear Ruby NameError messages for missing variables
- **Reusable**: Inherit from base classes

## Context Variables with Indifferent Access

Context variables in RAAF DSL use `ActiveSupport::HashWithIndifferentAccess` for seamless key handling:

```ruby
# Context variables support both string and symbol key access
result = agent.run("Research AI trends") do
  # Set context variables for this run
  context_variable :search_depth, "deep"
  context_variable :sources, ["academic", "industry"] 
  context_variable :time_range, "2024"
end

# Access with either key type - both work identically
puts result.context[:search_depth]   # ✅ Works  
puts result.context["search_depth"]  # ✅ Also works
puts result.context[:sources]        # ✅ Works
puts result.context["sources"]       # ✅ Also works

# No more dual access patterns needed:
# OLD: result.context[:key] || result.context["key"]  ❌ Error-prone
# NEW: result.context[:key]                           ✅ Always works
```

## Web Search Tool

```ruby
# Built-in web search with Tavily
agent = RAAF::DSL::AgentBuilder.build do
  name "SearchAgent"
  instructions "Search and summarize web content"
  
  use_web_search do
    api_key ENV['TAVILY_API_KEY']
    max_results 5
    include_raw_content true
  end
end
```

## Debug Tools

```ruby
# Enhanced debugging
RAAF::DSL::DebugUtils.inspect_agent(agent) do
  show_tools true
  show_context true
  show_configuration true
end

# Prompt inspection
RAAF::DSL::DebugUtils.inspect_prompts(result) do
  show_system_prompt true
  show_tool_calls true
  highlight_handoffs true
end
```

## RSpec Integration

```ruby
# Example RSpec test file (e.g., spec/agent_spec.rb)
# This shows how to use RAAF DSL in RSpec tests

# require 'spec_helper'
# require 'raaf-testing' # For RSpec matchers
# 
# RSpec.describe "Agent behavior" do
#   it "should handle web search" do
#     agent = RAAF::DSL::AgentBuilder.build do
#       name "TestAgent"
#       instructions "You search the web"
#       model "gpt-4o"
#       
#       tool :web_search do
#         description "Search the web"
#         parameter :query, type: :string, required: true
#         execute { |query:| { results: ["Result 1", "Result 2"] } }
#       end
#     end
#     
#     runner = RAAF::Runner.new(agent: agent)
#     # Test agent behavior here
#   end
# end
```

### Schema Validation with Smart Key Mapping

RAAF DSL includes powerful schema validation that automatically handles LLM field name variations:

```ruby
# Define agents with flexible schema validation
class CompanyAnalyzer < RAAF::DSL::Agent
  agent_name "CompanyAnalyzer"
  model "gpt-4o"
  
  # Define schema with Ruby naming conventions
  schema do
    field :company_name, type: :string, required: true
    field :market_sector, type: :string, required: true
    field :employee_count, type: :integer
    field :annual_revenue, type: :number
    field :headquarters_location, type: :string
    
    # Choose validation mode
    validate_mode :tolerant  # :strict, :tolerant, or :partial
  end
  
  instructions "Analyze company information and extract key details"
end

# LLMs can use natural language field names - they get automatically mapped
agent = CompanyAnalyzer.new
result = agent.run("Tesla Inc is an automotive company with 127,000 employees...")

# Even if LLM returns:
# {
#   "Company Name": "Tesla Inc",
#   "Market Sector": "automotive", 
#   "Employee Count": 127000,
#   "HQ Location": "Austin, Texas"
# }
#
# You get normalized output with indifferent access:
puts result[:company_name]           # "Tesla Inc"
puts result["company_name"]          # "Tesla Inc" (same result)
puts result[:market_sector]          # "automotive"  
puts result["market_sector"]         # "automotive" (same result)
puts result[:employee_count]         # 127000
puts result["employee_count"]        # 127000 (same result)
puts result[:headquarters_location]  # "Austin, Texas"
puts result["headquarters_location"] # "Austin, Texas" (same result)
```

### JSON Repair and Error Handling

```ruby
# RAAF automatically handles malformed JSON from LLMs
class DataExtractor < RAAF::DSL::Agent
  agent_name "DataExtractor"
  model "gpt-4o"
  
  schema do
    field :extracted_data, type: :object
    field :confidence, type: :number
    validate_mode :partial  # Most forgiving mode
  end
end

# These problematic responses are automatically fixed:
# 1. '{"name": "John",}' → {"name": "John"}  (trailing comma removed)
# 2. '```json\n{"valid": true}\n```' → {"valid": true}  (markdown extracted)
# 3. "{'key': 'value'}" → {"key": "value"}  (single quotes fixed)
# 4. Mixed text with embedded JSON gets extracted automatically

agent = DataExtractor.new
result = agent.run("Extract the user data from this messy text...")

# Always get clean, parsed data with indifferent key access regardless of LLM output quality
puts result[:extracted_data]    # ✅ Works
puts result["extracted_data"]   # ✅ Also works  
puts result[:confidence]        # ✅ Works
puts result["confidence"]       # ✅ Also works
```

### Validation Mode Comparison

```ruby
# :strict mode (default) - All fields must match exactly
schema do
  field :name, type: :string, required: true
  validate_mode :strict
end
# LLM must return exactly {"name": "value"} or validation fails

# :tolerant mode (recommended) - Required fields strict, others flexible  
schema do
  field :name, type: :string, required: true
  field :age, type: :integer
  validate_mode :tolerant
end
# LLM can return {"Name": "John", "Age": 25, "ExtraField": "ignored"}
# Gets normalized with indifferent access: both result[:name] and result["name"] work

# :partial mode - Use whatever validates, ignore the rest
schema do
  field :name, type: :string, required: true
  field :age, type: :integer  
  validate_mode :partial
end
# Even {"Name": "John", "InvalidAge": "not a number"} gets normalized with indifferent access
# Both result[:name] and result["name"] return "John"
```

## Environment Variables

```bash
export TAVILY_API_KEY="your-tavily-key"
export OPENAI_API_KEY="your-openai-key"
export RAAF_DEBUG_TOOLS="true"
```
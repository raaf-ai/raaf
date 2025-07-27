# RAAF DSL - Claude Code Guide

This gem provides a Ruby DSL for building agents with a more declarative syntax, comprehensive debugging tools, and a flexible prompt resolution system.

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
- **ContextVariables** - Dynamic context management
- **Prompt Resolution** - Flexible prompt loading system
- **WebSearch** - Built-in web search tool
- **DebugUtils** - Enhanced debugging capabilities

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
  required :topic, :depth
  optional :language, default: "English"
  
  def system
    <<~SYSTEM
      You are a research assistant specializing in #{@topic}.
      Provide #{@depth} analysis in #{@language}.
    SYSTEM
  end
  
  def user
    "Research the latest developments in #{@topic}."
  end
end

# Use prompts in agents via a custom agent class
class ResearchAgent < RAAF::DSL::Agents::Base
  include RAAF::DSL::Agents::AgentDsl
  
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

- **Validation**: Required/optional variables with contracts
- **Testing**: Easy to test with RSpec
- **IDE Support**: Autocomplete and refactoring
- **Dynamic**: Can use Ruby logic and conditionals
- **Reusable**: Inherit from base classes

## Context Variables

```ruby
result = agent.run("Research AI trends") do
  # Set context variables for this run
  context_variable :search_depth, "deep"
  context_variable :sources, ["academic", "industry"]
  context_variable :time_range, "2024"
end
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

## Environment Variables

```bash
export TAVILY_API_KEY="your-tavily-key"
export OPENAI_API_KEY="your-openai-key"
export RAAF_DEBUG_TOOLS="true"
```
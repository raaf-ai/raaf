# RAAF DSL - Claude Code Guide

This gem provides a Ruby DSL for building agents with a more declarative syntax, plus comprehensive debugging tools.

## Quick Start

```ruby
require 'raaf-dsl'

# Define agent using DSL
agent = RAAF::DSL::AgentBuilder.build do
  name "WebSearchAgent"
  instructions "You help users search the web"
  model "gpt-4o"
  
  tool :web_search do |query|
    RAAF::DSL::Tools::WebSearch.search(query)
  end
end

# Run with context
result = agent.run("Search for Ruby programming tutorials") do
  context_variable :max_results, 5
  context_variable :search_engine, "google"
end
```

## Core Components

- **AgentBuilder** - DSL for defining agents
- **ToolBuilder** - DSL for creating tools
- **ContextVariables** - Dynamic context management
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
    eval(expression) # In production, use a safe evaluator
  end
end

agent.add_tool(calculator)
```

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
# In spec files
require 'raaf-dsl/rspec'

RSpec.describe "Agent behavior" do
  it "should handle web search" do
    agent = build_agent do
      name "TestAgent"
      use_web_search
    end
    
    result = agent.run("Search for Ruby news")
    expect(result).to have_used_tool(:web_search)
    expect(result).to have_successful_completion
  end
end
```

## Environment Variables

```bash
export TAVILY_API_KEY="your-tavily-key"
export OPENAI_API_KEY="your-openai-key"
export RAAF_DEBUG_TOOLS="true"
```
# RAAF Tools - Claude Code Guide

This gem provides tools for RAAF agents to extend their capabilities with external services and operations.

## Quick Start

```ruby
require 'raaf-tools'

# Create Perplexity web search tool
perplexity_tool = RAAF::Tools::PerplexityTool.new(
  api_key: ENV['PERPLEXITY_API_KEY']
)

# Wrap in FunctionTool for agent use
function_tool = RAAF::FunctionTool.new(
  perplexity_tool.method(:call),
  name: "perplexity_search",
  description: "Perform web-grounded search with automatic citations"
)

# Add to agent
agent = RAAF::Agent.new(
  name: "SearchAgent",
  instructions: "You can search the web for current information",
  model: "gpt-4o"
)

agent.add_tool(function_tool)

# Agent will automatically use the tool when needed
runner = RAAF::Runner.new(agent: agent)
result = runner.run("What are the latest Ruby 3.4 features?")
```

## Available Tools

### Perplexity Search Tool

**Web-grounded search with automatic citations using Perplexity AI**

The PerplexityTool provides factual, citation-backed web search capabilities for RAAF agents. Best for research tasks requiring current information with source attribution.

#### Basic Usage with Helper Method (Recommended)

```ruby
# Initialize tool with API key
perplexity_tool = RAAF::Tools::PerplexityTool.new(
  api_key: ENV['PERPLEXITY_API_KEY']
)

# Wrap for agent use with comprehensive description helper
function_tool = RAAF::FunctionTool.new(
  perplexity_tool.method(:call),
  name: "perplexity_search",
  description: RAAF::Tools::PerplexityTool.function_tool_description
)

agent.add_tool(function_tool)

# Agent will call tool when needed with proper understanding
runner = RAAF::Runner.new(agent: agent)
result = runner.run("Find recent Ruby security updates")
```

**Why use the helper method?**
- Provides LLM with complete usage guidelines (when/how to use tool)
- Includes critical model validation warnings (prevents using gpt-4o instead of sonar)
- Contains query engineering best practices from production usage
- Shows all available models with cost information
- Based on real-world patterns from ProspectRadar production agents

#### Custom Description for Specific Use Cases

You can also provide a custom description tailored to your specific use case:

```ruby
# Custom description for company research
function_tool = RAAF::FunctionTool.new(
  perplexity_tool.method(:call),
  name: "perplexity_search",
  description: <<~DESC.strip
    Search for current company information when data_completeness_score < 7.

    CRITICAL: Use ONLY Perplexity models (sonar, sonar-pro, sonar-reasoning, sonar-reasoning-pro, sonar-deep-research).
    DO NOT use gpt-4o, gpt-3.5-turbo, or other non-Perplexity models - they will cause errors.

    Query pattern: "[Company] [Legal Form] [Location] comprehensive business profile: business model, industry sector, B2B/B2C focus, company size, activity status"

    Combine ALL facts into ONE comprehensive search per company for efficiency.
    Use expert terminology, not conversational language.
  DESC
)
```

#### Tool Configuration

```ruby
# Custom configuration
perplexity_tool = RAAF::Tools::PerplexityTool.new(
  api_key: ENV['PERPLEXITY_API_KEY'],
  api_base: "https://custom.api.perplexity.ai",  # Custom endpoint
  timeout: 60,                                    # Request timeout (seconds)
  open_timeout: 10                                # Connection timeout (seconds)
)
```

#### Available Models

```ruby
# sonar - Fast web search (default)
result = perplexity_tool.call(
  query: "Latest Ruby news",
  model: "sonar"
)

# sonar-pro - Advanced search with deeper analysis
result = perplexity_tool.call(
  query: "Ruby performance improvements",
  model: "sonar-pro"
)

# sonar-reasoning - Deep reasoning with web search
result = perplexity_tool.call(
  query: "Compare Ruby vs Python for web development",
  model: "sonar-reasoning"
)
```

#### Search Filtering

```ruby
# Domain filtering - restrict to specific websites
result = perplexity_tool.call(
  query: "Ruby 3.4 release",
  search_domain_filter: ["ruby-lang.org", "github.com"]
)

# Recency filtering - time-based results
# Options: "hour", "day", "week", "month", "year"
result = perplexity_tool.call(
  query: "Ruby security advisories",
  search_recency_filter: "week"
)

# Combined filters
result = perplexity_tool.call(
  query: "Ruby news",
  search_domain_filter: ["ruby-lang.org"],
  search_recency_filter: "month"
)
```

#### Response Format

```ruby
# Success response
{
  success: true,
  content: "Ruby 3.4 includes significant performance improvements...",
  citations: [
    "https://ruby-lang.org/news/2024/ruby-3-4-released",
    "https://github.com/ruby/ruby"
  ],
  web_results: [
    {
      "title" => "Ruby 3.4 Released",
      "url" => "https://ruby-lang.org/news/2024/ruby-3-4-released",
      "snippet" => "Ruby 3.4 is now available..."
    }
  ],
  model: "sonar"
}

# Error response
{
  success: false,
  error: "Authentication failed",
  error_type: "authentication_error",
  message: "Invalid API key"
}
```

#### Token Limits

```ruby
# Control response length with max_tokens
result = perplexity_tool.call(
  query: "Ruby 3.4 features",
  max_tokens: 500  # Limit response to 500 tokens
)
```

#### Error Handling

The tool handles three error types automatically:

```ruby
# Authentication errors (401)
result = perplexity_tool.call(query: "Ruby news")
# Returns: { success: false, error: "Authentication failed", error_type: "authentication_error" }

# Rate limit errors (429)
result = perplexity_tool.call(query: "Ruby news")
# Returns: { success: false, error: "Rate limit exceeded", error_type: "rate_limit_error" }

# General errors (network, timeout, etc.)
result = perplexity_tool.call(query: "Ruby news")
# Returns: { success: false, error: "Search failed", error_type: "general_error", backtrace: [...] }
```

#### Complete Example

```ruby
# Research agent with Perplexity search
agent = RAAF::Agent.new(
  name: "ResearchAgent",
  instructions: <<~INSTRUCTIONS,
    You are a research assistant that provides factual, citation-backed information.
    Always use the perplexity_search tool for current information.
    Include citations in your responses.
  INSTRUCTIONS
  model: "gpt-4o"
)

# Create and add tool
perplexity_tool = RAAF::Tools::PerplexityTool.new(
  api_key: ENV['PERPLEXITY_API_KEY']
)

function_tool = RAAF::FunctionTool.new(
  perplexity_tool.method(:call),
  name: "perplexity_search",
  description: "Search for current, factual information with citations. Use for recent news, technical updates, or verifiable facts."
)

agent.add_tool(function_tool)

# Run research queries
runner = RAAF::Runner.new(agent: agent)

result = runner.run("What are the latest Ruby 3.4 performance improvements?")
# Agent will:
# 1. Call perplexity_search tool with appropriate query
# 2. Receive citations and web results
# 3. Synthesize answer with source attribution

puts result.messages.last[:content]
# => "According to the official Ruby release notes [1], Ruby 3.4 includes..."
```

#### Model Selection Guide

**Use `sonar` for:**
- Quick factual lookups
- Simple queries
- Real-time information
- Cost-effective searches

**Use `sonar-pro` for:**
- Complex research tasks
- Multi-faceted queries
- Detailed analysis
- Higher accuracy requirements

**Use `sonar-reasoning` for:**
- Deep analytical queries
- Comparative analysis
- Complex reasoning tasks
- Multi-step research

#### Best Practices

1. **Be Specific**: Add 2-3 contextual words to queries for better results
2. **Use Filters**: Apply domain/recency filters for focused results
3. **Handle Errors**: Always check `success` field in responses
4. **Citations**: Include citations from `citations` array in final output
5. **Token Limits**: Set appropriate `max_tokens` for response length control

#### Environment Variables

```bash
export PERPLEXITY_API_KEY="your-perplexity-api-key"
```

## Tool Development

### Creating Custom Tools

RAAF tools are plain Ruby classes with a `call` method, wrapped in `FunctionTool` for agent use:

```ruby
# Create custom tool - plain Ruby class
class WeatherTool
  def initialize(api_key:)
    @api_key = api_key
  end

  ##
  # Get current weather for a location
  #
  # @param location [String] City name or coordinates
  # @param units [String] Temperature units ("metric" or "imperial")
  # @return [Hash] Weather data with temperature, condition, humidity
  #
  def call(location:, units: "metric")
    # Call weather API
    weather_data = WeatherAPI.get_current(location, api_key: @api_key, units: units)

    {
      success: true,
      temperature: weather_data[:temp],
      condition: weather_data[:condition],
      humidity: weather_data[:humidity],
      location: location
    }
  rescue StandardError => e
    {
      success: false,
      error: "Weather lookup failed",
      message: e.message
    }
  end
end

# Wrap in FunctionTool for agent use
weather_tool = WeatherTool.new(api_key: ENV['WEATHER_API_KEY'])

function_tool = RAAF::FunctionTool.new(
  weather_tool.method(:call),
  name: "get_weather",
  description: "Get current weather for a location"
)

agent.add_tool(function_tool)
```

### Tool Pattern

1. **Plain Ruby Class**: No DSL required
2. **Initialize Method**: Accept configuration (API keys, endpoints, etc.)
3. **Call Method**: Implement tool logic with keyword arguments
4. **Return Hash**: Always return hash with `:success` key
5. **Error Handling**: Catch exceptions and return structured error hashes
6. **FunctionTool Wrapper**: Wrap `call` method for agent use
7. **YARD Documentation**: Document parameters and return values

## Testing Tools

```ruby
# Test tools in isolation
RSpec.describe MyTool do
  let(:tool) { described_class.new(api_key: "test-key") }

  it "returns success response" do
    result = tool.call(param: "value")

    expect(result[:success]).to be true
    expect(result[:data]).to be_present
  end

  it "handles errors gracefully" do
    allow(ExternalAPI).to receive(:call).and_raise(StandardError)

    result = tool.call(param: "value")

    expect(result[:success]).to be false
    expect(result[:error]).to eq("Operation failed")
  end
end
```

## Environment Variables

```bash
# Tool-specific API keys
export PERPLEXITY_API_KEY="your-perplexity-api-key"
```

## Additional Resources

- **RAAF Core Documentation**: `@raaf/core/CLAUDE.md`
- **Provider Documentation**: `@raaf/providers/CLAUDE.md`
- **Function Tool Reference**: `@raaf/core/lib/raaf/function_tool.rb`
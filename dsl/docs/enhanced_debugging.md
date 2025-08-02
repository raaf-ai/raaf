# Enhanced Debugging Capabilities in RAAF::DSL::Agent

This document describes the enhanced debugging capabilities available in the RAAF::DSL::Agent class, which provide comprehensive visibility into agent execution for troubleshooting and optimization.

## Overview

The enhanced debugging system integrates three debugging modules:
- `LLMInterceptor` - Intercepts and logs OpenAI API requests/responses
- `PromptInspector` - Displays formatted prompts with variable substitutions
- `ContextInspector` - Shows context variable state and summaries

## New Methods

### Enhanced Run Methods

#### `run_with_debug(options)`
The primary enhanced debugging method with comprehensive capabilities.

```ruby
result = agent.run_with_debug(
  input_context_variables: context_vars,
  debug_this_run: true,
  debug_level: :verbose,
  stop_checker: proc { |turn| turn > 5 }
)
```

**Parameters:**
- `input_context_variables` - Context variables to use for this run
- `debug_this_run` - Enable debug for this specific run
- `debug_level` - Debug level (`:minimal`, `:standard`, `:verbose`)
- `stop_checker` - Optional proc to control execution stopping

**Returns:**
Standard agent result hash with additional `debug_info` key containing:
- `debug_level` - The debug level used
- `context_summary` - Agent state summary
- `execution_metadata` - Execution statistics and metadata

#### `run(options)` (Enhanced)
The standard run method now accepts a `debug_level` parameter and automatically delegates to `run_with_debug` when enhanced debugging is requested.

```ruby
# Standard run
result = agent.run

# Enhanced debugging run
result = agent.run(debug_level: :verbose)
```

### Convenience Methods

#### `run_with_minimal_debug(options)`
Executes with minimal debugging output.

```ruby
result = agent.run_with_minimal_debug(
  input_context_variables: context_vars,
  stop_checker: stop_checker
)
```

#### `run_with_standard_debug(options)`
Executes with standard debugging including LLM interception.

```ruby
result = agent.run_with_standard_debug(
  input_context_variables: context_vars,
  stop_checker: stop_checker
)
```

#### `run_with_verbose_debug(options)`
Executes with verbose debugging including prompt and context inspection.

```ruby
result = agent.run_with_verbose_debug(
  input_context_variables: context_vars,
  stop_checker: stop_checker
)
```

### Inspection Methods

#### `debug_context_summary()`
Generates a comprehensive context summary for debugging.

```ruby
summary = agent.debug_context_summary
# Returns hash with:
# - agent_info: Agent configuration and state
# - context_variables: Current context variable summary
# - document_info: Document metadata
# - processing_params: Processing parameters
# - configuration_sources: Where configuration values come from
# - timestamp: When summary was generated
```

#### `inspect_context()`
Inspects the agent's current context using the ContextInspector.

```ruby
summary = agent.inspect_context
# Outputs formatted context information to logger
# Returns context summary hash
```

#### `inspect_prompts()`
Inspects the agent's prompts using the PromptInspector.

```ruby
agent.inspect_prompts
# Outputs formatted prompt information to logger
# Shows prompts with variable substitutions
```

#### `debug_components_available?()`
Checks if all debugging components are available.

```ruby
if agent.debug_components_available?
  puts "Enhanced debugging is available"
end
```

## Debug Levels

### `:minimal`
- Basic execution flow logging
- Agent initialization and completion
- Error logging with context

### `:standard`
- Includes minimal debug output
- LLM request/response interception
- OpenAI API call logging
- Tool usage tracking

### `:verbose`
- Includes standard debug output
- Pre-execution prompt inspection
- Pre-execution context inspection
- Post-execution context inspection
- Detailed execution metadata

## Debug Output Examples

### LLM Interception Output
```
================================================================================
🚀 COMPLETE OPENAI API REQUEST:
📋 Model: gpt-4o
🌡️  Temperature: 0.7
🔄 Max Tokens: unlimited
🛠️  TOOLS CONFIGURED:
│ 1. Type: function
│    Function Name: web_search
│    Description: Search the web for information
│    Parameters: {...}
│    ✅ Properties: query, max_results
│    ✅ Required: query
================================================================================
```

### Context Inspection Output
```
🔍 CONTEXT INSPECTION:
================================================================================
🔍 FULL CONTEXT (using inspect):
│ {
│   "product": {
│     "name": "Test Product"
│   },
│   "search_strategies": [...]
│ }
📊 CONTEXT SUMMARY:
│ product: Test Product
│ search_strategies: 3
│ companies_discovered: 15
│ companies_enriched: 10
│ scored_prospects: 8
│ workflow_step: results_compilation
================================================================================
```

### Prompt Inspection Output
```
📝 PROMPT INSPECTION:
================================================================================
🔧 Prompt Class: Ai::Prompts::Company::Discovery
------------------------------------------------------------
🔧 SYSTEM PROMPT (with substitutions):
│ You are analyzing companies for: Test Product
│ Current workflow step: company_discovery
│ Available strategies: 3
------------------------------------------------------------
👤 USER PROMPT (with substitutions):
│ Discover companies that would be interested in Test Product
│ Focus on companies with 50-500 employees
================================================================================
```

## Integration with ProspectRadar

### In Controllers
```ruby
class ProspectsController < ApplicationController
  def discover
    service = ProspectDiscoveryService.new(params)
    
    if Rails.env.development? && params[:debug]
      @result = service.call_with_debug
    else
      @result = service.call
    end
    
    render json: @result
  end
end
```

### In Services
```ruby
class ProspectDiscoveryService < BaseService
  def call_with_debug
    agent = create_discovery_agent
    
    result = agent.run_with_debug(
      input_context_variables: build_context_variables,
      debug_level: :verbose
    )
    
    # Log debug summary for development
    Rails.logger.info "🔍 Discovery Debug Summary:"
    Rails.logger.info result[:debug_info][:context_summary]
    
    result
  end
  
  private
  
  def create_discovery_agent
    Ai::Agents::CompanyDiscovery.new(
      context: @context,
      processing_params: @processing_params,
      debug: Rails.env.development?
    )
  end
end
```

## Error Handling

Enhanced debugging provides detailed error information:

```ruby
result = agent.run_with_debug(debug_level: :verbose)

if result[:workflow_status] == "error"
  puts "Error occurred: #{result[:error]}"
  puts "Debug context: #{result[:debug_info][:error_context]}"
  puts "Error occurred at: #{result[:debug_info][:error_occurred_at]}"
end
```

## Configuration

Debug behavior can be controlled through:

1. **Agent initialization:**
   ```ruby
   agent = MyAgent.new(context: ctx, debug: true)
   ```

2. **Global configuration:**
   ```ruby
   RAAF::DSL.configure do |config|
     config.debug_enabled = true
     config.debug_level = :standard
   end
   ```

3. **Runtime options:**
   ```ruby
   agent.run_with_debug(debug_level: :verbose)
   ```

## Best Practices

1. **Use appropriate debug levels:**
   - `:minimal` for basic troubleshooting
   - `:standard` for API request debugging
   - `:verbose` for comprehensive analysis

2. **Combine with Rails logging:**
   ```ruby
   Rails.logger.level = :debug if Rails.env.development?
   ```

3. **Conditionally enable debugging:**
   ```ruby
   debug_level = Rails.env.development? ? :verbose : nil
   result = agent.run(debug_level: debug_level)
   ```

4. **Use inspection methods for quick analysis:**
   ```ruby
   agent.inspect_context if Rails.env.development?
   agent.inspect_prompts if params[:debug_prompts]
   ```

The enhanced debugging capabilities provide comprehensive visibility into agent execution, making it easier to understand, debug, and optimize AI agent behavior in the ProspectRadar application.
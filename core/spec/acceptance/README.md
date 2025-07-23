# RAAF Acceptance Tests

This directory contains comprehensive acceptance tests that demonstrate all major features of RAAF working together.

## Test Features

The acceptance tests demonstrate:

1. **Multiple Agents** - Tests with 3 specialized agents (Research, Analysis, Report Writer)
2. **Agent Handoffs** - Automatic handoff between agents using tool-based transfers
3. **Context Sharing** - Hooks that write results back to shared context for use by subsequent agents
4. **Multiple Tool Calls** - Each agent makes multiple tool calls to accomplish its tasks
5. **VCR Recording** - Tests are recordable with VCR for replay testing
6. **Input Guardrails** - Blocks sensitive information like credit cards, SSNs
7. **Output Guardrails** - Filters inappropriate content from agent responses

## Running the Tests

### Run with Mocks (Default)
```bash
# Run acceptance tests with mock provider
RUN_ACCEPTANCE_TESTS=1 bundle exec rspec spec/acceptance/

# Run a specific test file
RUN_ACCEPTANCE_TESTS=1 bundle exec rspec spec/acceptance/comprehensive_multi_agent_workflow_mock_spec.rb
```

### Run with Real API Calls
```bash
# Set your API key
export OPENAI_API_KEY="your-actual-key"

# Run with VCR recording enabled
RUN_ACCEPTANCE_TESTS=1 VCR_ALLOW_HTTP=1 bundle exec rspec spec/acceptance/comprehensive_multi_agent_workflow_spec.rb

# Run with existing VCR cassettes
RUN_ACCEPTANCE_TESTS=1 bundle exec rspec spec/acceptance/comprehensive_multi_agent_workflow_spec.rb
```

## Test Structure

### Mock Test (`comprehensive_multi_agent_workflow_mock_spec.rb`)
- Uses `RAAF::Testing::MockProvider` to simulate API responses
- Demonstrates all features without requiring API keys
- Fast execution, suitable for CI/CD

### Real API Test (`comprehensive_multi_agent_workflow_spec.rb`)
- Uses actual API providers (OpenAI, Anthropic, etc.)
- Records interactions with VCR for replay
- Requires valid API keys for initial recording

## Workflow Example

The test implements a complete research workflow:

1. **Research Agent**
   - Tools: `search_web`, `search_papers`, `get_statistics`
   - Gathers comprehensive information
   - Hands off to Analysis Agent

2. **Analysis Agent**
   - Tools: `calculate_trends`, `compare_data`, `generate_insights`
   - Analyzes research data from shared context
   - Hands off to Report Writer

3. **Report Writer Agent**
   - Tools: `format_section`, `create_summary`, `add_citations`
   - Uses data from both previous agents
   - Produces final formatted report

## Context Sharing

The test uses a custom hook that:
- Stores tool call results in shared context
- Makes previous agent results available to subsequent agents
- Tracks handoff history
- Preserves agent completion status

Example shared context after execution:
```ruby
{
  workflow_data: {
    "search_web_result" => "Ruby is a dynamic programming...",
    "ResearchAgent_completed" => true,
    "ResearchAgent_final_message" => "Research complete...",
    handoffs: [
      { from: "ResearchAgent", to: "AnalysisAgent", timestamp: ... },
      { from: "AnalysisAgent", to: "ReportWriter", timestamp: ... }
    ]
  }
}
```

## Guardrails

### Input Guardrail
Blocks:
- Credit card numbers (4111-1111-1111-1111)
- Social Security Numbers (123-45-6789)
- Private keys

### Output Guardrail
Filters:
- Profanity and inappropriate language
- Replaces with [removed]

## VCR Cassettes

VCR cassettes are stored in `spec/fixtures/vcr_cassettes/`. To update:

```bash
# Delete old cassette
rm spec/fixtures/vcr_cassettes/comprehensive_multi_agent_workflow.yml

# Re-record
RUN_ACCEPTANCE_TESTS=1 VCR_ALLOW_HTTP=1 bundle exec rspec spec/acceptance/comprehensive_multi_agent_workflow_spec.rb
```

## Debugging

Enable debug output:
```bash
RAAF_LOG_LEVEL=debug RUN_ACCEPTANCE_TESTS=1 bundle exec rspec spec/acceptance/
```

View detailed API interactions:
```bash
RAAF_DEBUG_CATEGORIES=api,tracing RUN_ACCEPTANCE_TESTS=1 bundle exec rspec spec/acceptance/
```
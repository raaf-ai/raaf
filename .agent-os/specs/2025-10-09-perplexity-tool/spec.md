# Spec Requirements Document

> Spec: Perplexity Provider Refactoring and Tool Creation
> Created: 2025-10-09
> Updated: 2025-10-09
> Status: Planning

## Overview

This spec has two major components:

1. **Refactor PerplexityProvider** to leverage common retry logic, error handling, and API management code from `ModelInterface` base class, eliminating code duplication and ensuring consistent behavior across all RAAF providers.

2. **Create PerplexityTool** that exposes Perplexity's web search capabilities as a RAAF tool, allowing agents to perform real-time web searches with citations across all Perplexity models and features.

## User Stories

### Consistent Provider Behavior

As a **RAAF developer**, I want **all providers to use the same retry logic and error handling**, so that **I get predictable behavior regardless of which AI provider I choose**.

When an API call fails due to network issues or rate limits, all providers should behave identically with exponential backoff, configurable retries, and consistent error messages. This makes it easier to build reliable applications.

### Code Maintainability

As a **RAAF maintainer**, I want to **eliminate duplicated retry and error handling code**, so that **bug fixes and improvements apply to all providers automatically**.

Currently, PerplexityProvider implements its own retry logic using `with_retry` method, duplicating code from ModelInterface. By refactoring to use the base class implementation, improvements to retry logic (like better backoff strategies or new retryable error types) automatically benefit all providers.

### Simplified Provider Implementation

As a **provider implementer**, I want to **focus only on API-specific code**, so that **I don't need to reimplement common patterns like retries and error handling**.

New providers should only need to implement `perform_chat_completion` and handle API-specific details. The base class should handle all cross-cutting concerns automatically.

### Perplexity Web Search as a Tool

As a **RAAF agent developer**, I want to **give my agents access to real-time web search with citations**, so that **my agents can find current information and provide source attribution**.

Perplexity excels at web-grounded search with automatic citations. By exposing this as a RAAF tool, any agent (regardless of its primary LLM provider) can leverage Perplexity's search capabilities for research tasks, fact-checking, and gathering current information.

### Multi-Model Tool Support

As a **RAAF developer**, I want to **choose the appropriate Perplexity model for each search task**, so that **I can optimize for speed (sonar), quality (sonar-pro), or reasoning (sonar-reasoning)**.

Different search tasks have different requirements. Quick lookups benefit from the fast `sonar` model, while complex research benefits from `sonar-pro` or `sonar-reasoning-pro` with their enhanced capabilities and JSON schema support.

## Spec Scope

### Part 1: Provider Refactoring

1. **Refactor PerplexityProvider** - Remove duplicated retry logic and use `ModelInterface.with_retry` instead
2. **Simplify API Request Method** - Let `perform_chat_completion` handle the API call directly with automatic retry via base class
3. **Maintain Public API** - All existing PerplexityProvider functionality remains unchanged from external perspective
4. **Consistent Error Handling** - Use ModelInterface error handling patterns (`AuthenticationError`, `RateLimitError`, `ServerError`, `APIError`)
5. **Validation Preservation** - Keep Perplexity-specific validations (model support, schema support) in the provider

### Part 2: Tool Creation

1. **PerplexityTool Implementation** - Create a RAAF tool that wraps PerplexityProvider for web search
2. **Multi-Model Support** - Support all Perplexity models (sonar, sonar-pro, sonar-reasoning, sonar-reasoning-pro, sonar-deep-research)
3. **Search Filtering** - Expose domain filtering and recency filtering via tool parameters
4. **Citation Extraction** - Return search results with automatic citations and source URLs
5. **JSON Schema Support** - Enable structured output for sonar-pro and sonar-reasoning-pro models
6. **Tool Integration** - Full RAAF tool DSL integration with parameter validation and error handling

### Part 3: Common Code Extraction

1. **Perplexity Common Module** - Extract shared code between PerplexityProvider and PerplexityTool to `raaf-core` gem
2. **Model Constants** - Centralize `SUPPORTED_MODELS` constant in core module for reuse
3. **Validation Logic** - Extract model validation and schema support validation to shared module
4. **Search Options Building** - Share `web_search_options` construction logic between provider and tool
5. **Citation/Results Extraction** - Common code for parsing citations and web results from API responses
6. **Core Location** - All shared code in `core/lib/raaf/perplexity` module for maximum reusability

## Out of Scope

- Changes to PerplexityProvider public API or external behavior (beyond refactoring)
- New Perplexity features beyond current API support
- Changes to ModelInterface retry logic or base class design
- Modifications to PerplexityFactualSearchAgent (not a provider)
- Streaming support (not yet implemented in provider)

## Current vs Target Architecture

### Current Architecture (Duplicated Code)

```ruby
class PerplexityProvider < ModelInterface
  def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
    validate_model(model)
    # Build request body
    body = { model: model, messages: messages, stream: stream }

    if stream
      raise NotImplementedError, "Streaming not yet implemented"
    else
      with_retry("chat_completion") do  # ❌ DUPLICATE: Custom retry wrapper
        make_request(body)                # ❌ DUPLICATE: Custom API call
      end
    end
  end

  private

  def make_request(body)  # ❌ DUPLICATE: Manual HTTP call
    uri = URI("#{@api_base}/chat/completions")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = @timeout
    http.open_timeout = @open_timeout

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request.body = body.to_json

    response = http.request(request)
    handle_api_error(response) unless response.code.start_with?("2")  # ❌ DUPLICATE: Error check
    RAAF::Utils.parse_json(response.body)
  end
end
```

### Target Architecture (Uses Common Code)

```ruby
class PerplexityProvider < ModelInterface
  # ✅ Base class wraps perform_chat_completion with automatic retry
  def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
    validate_model(model)

    if tools && !tools.empty?
      log_warn("Perplexity does not support function/tool calling", model: model)
    end

    # Build request body
    body = build_request_body(messages, model, stream, **kwargs)

    # ✅ Base class handles retry automatically via chat_completion wrapper
    if stream
      raise NotImplementedError, "Streaming not yet implemented"
    else
      make_api_call(body)  # ✅ SIMPLIFIED: Just make the call, retry handled by base
    end
  end

  private

  def make_api_call(body)  # ✅ SIMPLIFIED: Single responsibility
    uri = URI("#{@api_base}/chat/completions")
    http = configure_http_client(uri)

    request = build_http_request(uri, body)
    response = http.request(request)

    handle_api_error(response, provider_name) unless response.code.start_with?("2")
    RAAF::Utils.parse_json(response.body)
  end

  # ✅ NEW: Extract HTTP client configuration
  def configure_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = @timeout
    http.open_timeout = @open_timeout
    http
  end

  # ✅ NEW: Extract request building logic
  def build_http_request(uri, body)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request.body = body.to_json
    request
  end
end
```

## PerplexityTool Architecture

### Tool Purpose

The **PerplexityTool** exposes Perplexity's web search capabilities as a callable tool that any RAAF agent can use, regardless of the agent's primary LLM provider. This enables:

- Real-time web search with automatic citations
- Multi-model support (fast sonar, advanced sonar-pro, reasoning sonar-reasoning-pro)
- Domain and recency filtering for targeted searches
- Structured output via JSON schemas (on supported models)

### Tool Implementation

```ruby
module RAAF
  module Tools
    class PerplexityTool
      include RAAF::DSL::ToolDsl

      tool_name "perplexity_search"
      tool_description <<~DESC
        Search the web using Perplexity AI with automatic citations.
        Provides real-time information with source attribution.
        Use this for research, fact-checking, and finding current information.
      DESC

      # Required parameters
      parameter :query,
        type: :string,
        required: true,
        description: "Search query to find information about"

      # Optional parameters
      parameter :model,
        type: :string,
        enum: ["sonar", "sonar-pro", "sonar-reasoning", "sonar-reasoning-pro", "sonar-deep-research"],
        default: "sonar",
        description: "Perplexity model: sonar (fast), sonar-pro (quality+schema), sonar-reasoning (deep thinking)"

      parameter :search_domain_filter,
        type: :array,
        description: "Limit search to specific domains (e.g., ['github.com', 'ruby-lang.org'])"

      parameter :search_recency_filter,
        type: :string,
        enum: ["hour", "day", "week", "month", "year"],
        description: "Limit results by recency"

      parameter :max_tokens,
        type: :integer,
        range: 100..4000,
        default: 1000,
        description: "Maximum tokens in response"

      def call(query:, model: "sonar", search_domain_filter: nil, search_recency_filter: nil, max_tokens: 1000)
        provider = RAAF::Models::PerplexityProvider.new(
          api_key: ENV['PERPLEXITY_API_KEY']
        )

        messages = [{ role: "user", content: query }]

        options = { max_tokens: max_tokens }
        options[:web_search_options] = build_search_options(search_domain_filter, search_recency_filter)

        result = provider.chat_completion(
          messages: messages,
          model: model,
          **options
        )

        format_result(result)
      rescue RAAF::Models::AuthenticationError => e
        { success: false, error: "Authentication failed: #{e.message}" }
      rescue RAAF::Models::RateLimitError => e
        { success: false, error: "Rate limit exceeded: #{e.message}" }
      rescue => e
        { success: false, error: "Search failed: #{e.message}" }
      end

      private

      def build_search_options(domain_filter, recency_filter)
        options = {}
        options[:search_domain_filter] = domain_filter if domain_filter&.any?
        options[:search_recency_filter] = recency_filter if recency_filter
        options.empty? ? nil : options
      end

      def format_result(result)
        {
          success: true,
          content: result.dig("choices", 0, "message", "content"),
          citations: result["citations"] || [],
          web_results: result["web_results"] || [],
          model: result["model"]
        }
      end
    end
  end
end
```

### Tool Usage Example

```ruby
# Agent with Perplexity search tool
agent = RAAF::Agent.new(
  name: "Research Assistant",
  instructions: "Help users research topics using web search",
  model: "gpt-4o"  # Agent uses OpenAI...
)

# ...but can use Perplexity for web search via tool
agent.add_tool(RAAF::Tools::PerplexityTool.new)

runner = RAAF::Runner.new(agent: agent)
result = runner.run("What are the latest Ruby 3.4 features?")

# Agent automatically uses perplexity_search tool to find current information
```

### Tool Return Format

```ruby
{
  success: true,
  content: "Ruby 3.4 introduces several new features...",
  citations: [
    "https://www.ruby-lang.org/en/news/2024/ruby-3-4-released/",
    "https://github.com/ruby/ruby/blob/v3_4_0/NEWS.md"
  ],
  web_results: [
    {
      title: "Ruby 3.4.0 Released",
      url: "https://www.ruby-lang.org/en/news/2024/ruby-3-4-released/",
      snippet: "We are pleased to announce the release of Ruby 3.4.0..."
    }
  ],
  model: "sonar-pro"
}
```

## Common Code Architecture (RAAF Core)

### Shared Module Location

All code common to both `PerplexityProvider` and `PerplexityTool` will be extracted to:

```
raaf/
└── core/
    └── lib/
        └── raaf/
            └── perplexity/
                ├── common.rb           # Main module with constants and validations
                ├── search_options.rb   # Web search options builder
                └── result_parser.rb    # Citation and results extraction
```

### Common Module Implementation

```ruby
# core/lib/raaf/perplexity/common.rb
module RAAF
  module Perplexity
    module Common
      # Shared constants
      SUPPORTED_MODELS = %w[
        sonar
        sonar-pro
        sonar-reasoning
        sonar-reasoning-pro
        sonar-deep-research
      ].freeze

      SCHEMA_SUPPORTED_MODELS = %w[
        sonar-pro
        sonar-reasoning-pro
      ].freeze

      RECENCY_FILTERS = %w[
        hour
        day
        week
        month
        year
      ].freeze

      # Shared validation methods
      module_function

      def validate_model(model)
        return if SUPPORTED_MODELS.include?(model)

        raise ArgumentError,
              "Model '#{model}' is not supported. " \
              "Supported models: #{SUPPORTED_MODELS.join(', ')}"
      end

      def validate_schema_support(model)
        return if SCHEMA_SUPPORTED_MODELS.include?(model)

        raise ArgumentError,
              "JSON schema (response_format) is only supported on #{SCHEMA_SUPPORTED_MODELS.join(', ')}. " \
              "Current model: #{model}"
      end

      def validate_recency_filter(filter)
        return unless filter
        return if RECENCY_FILTERS.include?(filter)

        raise ArgumentError,
              "Invalid recency filter '#{filter}'. " \
              "Supported: #{RECENCY_FILTERS.join(', ')}"
      end
    end
  end
end
```

```ruby
# core/lib/raaf/perplexity/search_options.rb
module RAAF
  module Perplexity
    class SearchOptions
      def self.build(domain_filter: nil, recency_filter: nil)
        options = {}

        if domain_filter&.any?
          options[:search_domain_filter] = Array(domain_filter)
        end

        if recency_filter
          RAAF::Perplexity::Common.validate_recency_filter(recency_filter)
          options[:search_recency_filter] = recency_filter
        end

        options.empty? ? nil : options
      end
    end
  end
end
```

```ruby
# core/lib/raaf/perplexity/result_parser.rb
module RAAF
  module Perplexity
    class ResultParser
      def self.extract_content(result)
        result.dig("choices", 0, "message", "content")
      end

      def self.extract_citations(result)
        result["citations"] || []
      end

      def self.extract_web_results(result)
        result["web_results"] || []
      end

      def self.format_search_result(result)
        {
          success: true,
          content: extract_content(result),
          citations: extract_citations(result),
          web_results: extract_web_results(result),
          model: result["model"]
        }
      end
    end
  end
end
```

### Provider Usage of Common Code

```ruby
# providers/lib/raaf/perplexity_provider.rb
require 'raaf/perplexity/common'
require 'raaf/perplexity/search_options'

module RAAF
  module Models
    class PerplexityProvider < ModelInterface
      include RAAF::Perplexity::Common

      SUPPORTED_MODELS = RAAF::Perplexity::Common::SUPPORTED_MODELS

      def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        # Use shared validation
        RAAF::Perplexity::Common.validate_model(model)

        # Use shared search options builder
        if kwargs[:search_domain_filter] || kwargs[:search_recency_filter]
          kwargs[:web_search_options] = RAAF::Perplexity::SearchOptions.build(
            domain_filter: kwargs.delete(:search_domain_filter),
            recency_filter: kwargs.delete(:search_recency_filter)
          )
        end

        # Rest of provider implementation...
      end

      private

      def validate_schema_support(model)
        # Use shared validation
        RAAF::Perplexity::Common.validate_schema_support(model)
      end
    end
  end
end
```

### Tool Usage of Common Code

```ruby
# tools/lib/raaf/tools/perplexity_tool.rb
require 'raaf/perplexity/common'
require 'raaf/perplexity/search_options'
require 'raaf/perplexity/result_parser'

module RAAF
  module Tools
    class PerplexityTool
      include RAAF::DSL::ToolDsl
      include RAAF::Perplexity::Common

      parameter :model,
        type: :string,
        enum: RAAF::Perplexity::Common::SUPPORTED_MODELS,
        default: "sonar"

      def call(query:, model: "sonar", search_domain_filter: nil, search_recency_filter: nil, **options)
        # Use shared validation
        RAAF::Perplexity::Common.validate_model(model)

        # Use shared search options builder
        web_search_options = RAAF::Perplexity::SearchOptions.build(
          domain_filter: search_domain_filter,
          recency_filter: search_recency_filter
        )

        # Make API call via provider
        result = make_search_request(query, model, web_search_options, options)

        # Use shared result parser
        RAAF::Perplexity::ResultParser.format_search_result(result)
      end
    end
  end
end
```

### Benefits of Common Code Extraction

1. **Single Source of Truth**: Model lists, validations, and parsing logic defined once
2. **Consistency**: Provider and tool always use identical validation and parsing
3. **Maintainability**: Changes to Perplexity API handled in one place
4. **Testability**: Common code tested independently from provider and tool
5. **Reusability**: Future Perplexity integrations can leverage the same common code

## PerplexityFactualSearchAgent Impact

**PerplexityFactualSearchAgent is NOT a provider** - it's an agent base class in the ProspectRadar application. This refactoring does **NOT** directly affect it because:

1. **Different Layer**: PerplexityFactualSearchAgent extends `ApplicationAgent`, not `ModelInterface`
2. **Uses Provider**: It uses `PerplexityProvider` internally but doesn't implement provider interface
3. **No Shared Code**: The "common complexity code" being extracted is in `ModelInterface`, which PerplexityFactualSearchAgent doesn't inherit from

**Impact on PerplexityFactualSearchAgent:**
- ✅ **Indirect Benefit**: Will automatically get improved retry behavior through PerplexityProvider
- ✅ **No Changes Required**: No code changes needed in PerplexityFactualSearchAgent itself
- ✅ **Behavior Preserved**: All existing functionality remains unchanged

## Expected Deliverable

### Part 1: Refactored PerplexityProvider

1. **Refactored PerplexityProvider** that:
   - Removes duplicated `with_retry` wrapper (uses base class instead)
   - Simplifies `make_request` to focus on HTTP communication only
   - Uses `ModelInterface.handle_api_error` for consistent error handling
   - Maintains all existing functionality and public API
   - Preserves Perplexity-specific validations and features

2. **Test Coverage** demonstrating:
   - Retry behavior matches ResponsesProvider (exponential backoff, jitter, max attempts)
   - Error handling produces same exception types as other providers
   - Perplexity-specific features still work (schema validation, domain filtering)
   - No regression in existing functionality

3. **Documentation Updates** showing:
   - How PerplexityProvider leverages common retry logic
   - Configuration options for retry behavior
   - Comparison with other providers showing consistent patterns

### Part 2: PerplexityTool

1. **PerplexityTool Implementation** (`tools/lib/raaf/tools/perplexity_tool.rb`):
   - Full RAAF tool DSL integration with `tool_name`, `tool_description`, and parameter definitions
   - Wraps PerplexityProvider for web search functionality
   - Supports all Perplexity models with configurable model selection
   - Exposes search filtering options (domain filter, recency filter)
   - Returns structured results with citations, web results, and content
   - Handles JSON schema responses for sonar-pro/sonar-reasoning-pro models
   - Comprehensive error handling with user-friendly messages

2. **Tool Test Coverage** (`tools/spec/perplexity_tool_spec.rb`):
   - Basic search functionality across all models
   - Domain filtering validation
   - Recency filtering validation
   - Citation extraction verification
   - JSON schema support testing (sonar-pro, sonar-reasoning-pro)
   - Error handling (authentication, rate limits, API errors)
   - Integration with RAAF agent workflows

3. **Tool Documentation**:
   - Usage examples in `tools/CLAUDE.md`
   - Tool parameter documentation with examples
   - Model selection guide (when to use sonar vs sonar-pro vs sonar-reasoning)
   - Search filtering best practices
   - Integration examples with RAAF agents

### Part 3: Common Code (RAAF Core)

1. **Perplexity Common Module** (`core/lib/raaf/perplexity/common.rb`):
   - Shared constants (SUPPORTED_MODELS, SCHEMA_SUPPORTED_MODELS, RECENCY_FILTERS)
   - Model validation (`validate_model`, `validate_schema_support`)
   - Recency filter validation (`validate_recency_filter`)
   - Comprehensive YARD documentation

2. **Search Options Builder** (`core/lib/raaf/perplexity/search_options.rb`):
   - Unified web_search_options construction for provider and tool
   - Domain filter validation and array conversion
   - Recency filter validation and incorporation
   - Returns nil for empty options (API requirement)

3. **Result Parser** (`core/lib/raaf/perplexity/result_parser.rb`):
   - Citation extraction (`extract_citations`)
   - Web results extraction (`extract_web_results`)
   - Content extraction (`extract_content`)
   - Structured result formatting (`format_search_result`)

4. **Common Code Tests** (`core/spec/raaf/perplexity/*_spec.rb`):
   - Unit tests for all validation methods
   - Search options builder tests with various combinations
   - Result parser tests with real API response fixtures
   - Edge case handling (nil values, empty arrays, missing fields)

5. **Integration Requirements**:
   - PerplexityProvider refactored to use common code
   - PerplexityTool built using common code
   - Both implementations stay in sync automatically
   - Future Perplexity integrations can reuse common code

## Architecture Benefits

### Consistency Across Providers

- All providers use identical retry logic from `ModelInterface.with_retry`
- Same exponential backoff algorithm (base_delay × multiplier^(attempt-1))
- Same jitter calculation to avoid thundering herd
- Same retryable exception list (network errors, timeouts, rate limits)

### Reduced Code Duplication

**Before Refactoring:**
- PerplexityProvider: ~264 lines with custom retry logic
- ResponsesProvider: ~677 lines with custom retry logic
- ModelInterface: ~709 lines with retry logic
- **Total complexity points duplicated:** 3 implementations × retry logic

**After Refactoring:**
- PerplexityProvider: ~200 lines (removes retry wrapper)
- ResponsesProvider: Already uses base class retry ✅
- ModelInterface: ~709 lines (single source of truth)
- **Total complexity points:** 1 implementation used by all

### Easier Provider Development

New providers only need to implement:
```ruby
class MyNewProvider < ModelInterface
  def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
    # Just make the API call - retry happens automatically
    response = http_post_to_my_api(messages, model, tools, **kwargs)
    parse_response(response)
  end

  def supported_models
    ["my-model-v1", "my-model-v2"]
  end

  def provider_name
    "MyProvider"
  end
end
```

No need to implement retry logic, error handling, or timeout management - it's all inherited from ModelInterface.

## Spec Documentation

- **Tasks:** @.agent-os/specs/2025-10-09-perplexity-tool/tasks.md
- **Technical Specification:** @.agent-os/specs/2025-10-09-perplexity-tool/sub-specs/technical-spec.md
- **Tests Specification:** @.agent-os/specs/2025-10-09-perplexity-tool/sub-specs/tests.md

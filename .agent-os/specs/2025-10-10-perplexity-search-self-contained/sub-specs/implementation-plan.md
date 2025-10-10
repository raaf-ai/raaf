# Implementation Plan

This is the implementation plan for the spec detailed in @.agent-os/specs/2025-10-10-perplexity-search-self-contained/spec.md

> Created: 2025-10-10
> Version: 1.0.0

## Current State Analysis

### Existing Architecture
```
dsl/lib/raaf/dsl/tools/perplexity_search.rb
├── Inherits from Base
├── Requires "raaf-tools" gem
├── Initializes RAAF::Tools::PerplexityTool
├── Delegates call() to @perplexity_tool
└── Duplicates validation logic
```

### Problems with Current Implementation
1. **Dependency on raaf-tools gem** - Causes loading errors
2. **Error: uninitialized constant RAAF::Tools::PerplexityTool** - Discovery system fails
3. **Wrapper pattern** - Unnecessary indirection
4. **Duplicate constants** - Maintains own VALID_MODELS instead of using Common

### Reference Implementation (TavilySearch)
```
dsl/lib/raaf/dsl/tools/tavily_search.rb
├── Inherits from Base
├── No external gem dependencies
├── Direct HTTP implementation with Net::HTTP
├── Self-contained validation
└── Returns structured results
```

## Proposed Architecture

### New Structure with Shared HTTP Client
```
core/lib/raaf/perplexity/http_client.rb (NEW)
├── Extracted from PerplexityProvider
├── Single source for HTTP communication
├── Handles authentication, timeouts, errors
└── Used by PerplexitySearch, PerplexityProvider, PerplexityTool

dsl/lib/raaf/dsl/tools/perplexity_search.rb
├── Inherits from Base
├── Requires RAAF Core modules only
│   ├── require "raaf/perplexity/common"
│   ├── require "raaf/perplexity/search_options"
│   ├── require "raaf/perplexity/result_parser"
│   └── require "raaf/perplexity/http_client" (NEW)
├── Uses shared HTTP client
├── Uses Core validation and formatting
└── Returns structured results

providers/lib/raaf/perplexity_provider.rb
├── Refactored to use shared HTTP client
└── Removes duplicate HTTP code
```

### Key Components

#### 1. Initialization
```ruby
def initialize(options = {})
  super(DEFAULT_CONFIG.merge(options || {}))
  validate_options!  # Uses RAAF::Perplexity::Common
end
```

#### 2. Shared HTTP Client (RAAF Core)
```ruby
# In core/lib/raaf/perplexity/http_client.rb
module RAAF
  module Perplexity
    class HttpClient
      def initialize(api_key:, api_base: "https://api.perplexity.ai", timeout: 120, open_timeout: 30)
        @api_key = api_key
        @api_base = api_base
        @timeout = timeout
        @open_timeout = open_timeout
      end

      def make_api_call(body)
        uri = URI("#{@api_base}/chat/completions")
        http = configure_http_client(uri)
        request = build_http_request(uri, body)

        response = http.request(request)
        handle_api_error(response) unless response.code.start_with?("2")

        RAAF::Utils.parse_json(response.body)
      end

      private

      def configure_http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @timeout
        http.open_timeout = @open_timeout
        http
      end

      def build_http_request(uri, body)
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = body.to_json
        request
      end

      def handle_api_error(response)
        error_body = RAAF::Utils.parse_json(response.body) rescue {}
        error_message = error_body.dig("error", "message") || "API request failed"
        raise RAAF::APIError.new(error_message, response.code.to_i)
      end
    end
  end
end

# Usage in PerplexitySearch
def initialize(options = {})
  super(DEFAULT_CONFIG.merge(options || {}))
  @http_client = RAAF::Perplexity::HttpClient.new(
    api_key: api_key,
    timeout: self.options[:timeout],
    open_timeout: self.options[:timeout]
  )
  validate_options!
end
```

#### 3. Core Module Integration
```ruby
def validate_options!
  # Use Core validation
  if options[:model]
    RAAF::Perplexity::Common.validate_model(options[:model])
  end

  if options[:search_recency_filter]
    RAAF::Perplexity::Common.validate_recency_filter(options[:search_recency_filter])
  end
end

def build_search_options(kwargs)
  # Use Core option builder
  RAAF::Perplexity::SearchOptions.build(
    domain_filter: kwargs[:search_domain_filter],
    recency_filter: kwargs[:search_recency_filter]
  )
end

def format_response(api_response, query)
  if api_response["error"]
    handle_error(api_response["error"], query)
  else
    # Use Core result parser
    result = RAAF::Perplexity::ResultParser.format_search_result(api_response)
    enhance_result(result, query)
  end
end
```

## Implementation Steps

### Step 0: Create Shared HTTP Client in RAAF Core (NEW - FIRST PRIORITY)
```ruby
# Create: core/lib/raaf/perplexity/http_client.rb

module RAAF
  module Perplexity
    class HttpClient
      attr_reader :api_key, :api_base, :timeout, :open_timeout

      def initialize(api_key:, api_base: "https://api.perplexity.ai", timeout: 120, open_timeout: 30)
        @api_key = api_key
        @api_base = api_base
        @timeout = timeout
        @open_timeout = open_timeout
      end

      def make_api_call(body)
        uri = URI("#{@api_base}/chat/completions")
        http = configure_http_client(uri)
        request = build_http_request(uri, body)

        response = http.request(request)
        handle_api_error(response) unless response.code.start_with?("2")

        RAAF::Utils.parse_json(response.body)
      end

      private

      def configure_http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @timeout
        http.open_timeout = @open_timeout
        http
      end

      def build_http_request(uri, body)
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = body.to_json
        request
      end

      def handle_api_error(response)
        error_body = RAAF::Utils.parse_json(response.body) rescue {}
        error_message = error_body.dig("error", "message") || "API request failed"
        raise RAAF::APIError.new(error_message, response.code.to_i)
      end
    end
  end
end

# Update: core/lib/raaf/perplexity.rb to require new file
require "raaf/perplexity/http_client"

# Write tests: core/spec/raaf/perplexity/http_client_spec.rb
```

### Step 1: Update Requires
```ruby
# Remove
require "raaf-tools"

# Add
require "net/http"
require "uri"
require "json"
require "raaf/perplexity/common"
require "raaf/perplexity/search_options"
require "raaf/perplexity/result_parser"
require "raaf/perplexity/http_client"  # NEW - shared HTTP client
```

### Step 2: Update Constants
```ruby
# Remove duplicate constants
# VALID_MODELS = %w[...].freeze
# VALID_RECENCY_FILTERS = %w[...].freeze

# Use Core constants instead
def valid_models
  RAAF::Perplexity::Common::SUPPORTED_MODELS
end

def valid_recency_filters
  RAAF::Perplexity::Common::RECENCY_FILTERS
end
```

### Step 3: Remove Tool Wrapper
```ruby
# Remove
def initialize(options = {})
  @perplexity_tool = RAAF::Tools::PerplexityTool.new(...)
end

# Replace with (using shared HTTP client)
def initialize(options = {})
  super(DEFAULT_CONFIG.merge(options || {}))
  @http_client = RAAF::Perplexity::HttpClient.new(
    api_key: api_key,
    timeout: self.options[:timeout],
    open_timeout: self.options[:timeout]
  )
  validate_options!
end
```

### Step 4: Use Shared HTTP Client
```ruby
def call(query:, **kwargs)
  # Merge options
  model = kwargs[:model] || options[:model]
  max_tokens = kwargs[:max_tokens] || options[:max_tokens]

  # Build search options
  search_options = build_search_options(kwargs)

  # Build request
  params = {
    model: model,
    messages: [
      { role: "user", content: query }
    ],
    max_tokens: max_tokens
  }

  params[:web_search_options] = search_options if search_options

  # Log request
  log_request(query, model, search_options)

  # Make HTTP request using shared client
  start_time = Time.now
  response = @http_client.make_api_call(params)
  duration_ms = ((Time.now - start_time) * 1000).round(2)

  # Log response
  log_response(response, duration_ms)

  # Format response
  format_response(response, query)
end
```

### Step 5: Update Validation
```ruby
def validate_options!
  # Use Core validation
  if options[:model]
    RAAF::Perplexity::Common.validate_model(options[:model])
  end

  if options[:search_recency_filter]
    RAAF::Perplexity::Common.validate_recency_filter(options[:search_recency_filter])
  end

  # Keep max_tokens validation local (not in Core)
  if options[:max_tokens] && (options[:max_tokens] < 1 || options[:max_tokens] > 4000)
    raise ArgumentError, "Invalid max_tokens: #{options[:max_tokens]}. Must be between 1 and 4000"
  end
end
```

### Step 6: Update Tool Definition
```ruby
def build_tool_definition
  {
    type: "function",
    function: {
      name: tool_name,
      description: "...",
      parameters: {
        type: "object",
        properties: {
          query: { ... },
          model: {
            type: "string",
            enum: RAAF::Perplexity::Common::SUPPORTED_MODELS,  # Use Core constant
            description: "..."
          },
          search_recency_filter: {
            type: "string",
            enum: RAAF::Perplexity::Common::RECENCY_FILTERS,  # Use Core constant
            description: "..."
          },
          # ... rest of parameters
        }
      }
    }
  }
end
```

### Step 7: Add Logging
```ruby
private

def log_request(query, model, search_options)
  RAAF.logger.debug "[PERPLEXITY SEARCH] Executing search with model: #{model}"
  RAAF.logger.debug "[PERPLEXITY SEARCH] Query: #{query.truncate(100)}"

  if search_options
    if search_options[:search_domain_filter]
      RAAF.logger.debug "[PERPLEXITY SEARCH] Domain filter: #{search_options[:search_domain_filter]}"
    end
    if search_options[:search_recency_filter]
      RAAF.logger.debug "[PERPLEXITY SEARCH] Recency filter: #{search_options[:search_recency_filter]}"
    end
  end
end

def log_response(response, duration_ms)
  if response["error"]
    RAAF.logger.error "[PERPLEXITY SEARCH] API Error (#{duration_ms}ms): #{response['error']}"
  else
    content_length = response.dig("choices", 0, "message", "content")&.length || 0
    citations_count = response["citations"]&.length || 0
    web_results_count = response["web_results"]&.length || 0

    RAAF.logger.debug "[PERPLEXITY SEARCH] Success (#{duration_ms}ms): #{content_length} chars, #{citations_count} citations, #{web_results_count} web results"
  end
end
```

### Step 8: Update PerplexityProvider to Use Shared HTTP Client
```ruby
# In providers/lib/raaf/perplexity_provider.rb

# Remove HTTP methods: make_api_call, configure_http_client, build_http_request

# Update initialize
def initialize(api_key: nil, api_base: "https://api.perplexity.ai", timeout: 120, open_timeout: 30)
  @api_key = api_key || ENV["PERPLEXITY_API_KEY"]
  @api_base = api_base
  @timeout = timeout
  @open_timeout = open_timeout

  # Create shared HTTP client
  @http_client = RAAF::Perplexity::HttpClient.new(
    api_key: @api_key,
    api_base: @api_base,
    timeout: @timeout,
    open_timeout: @open_timeout
  )
end

# Replace make_api_call with delegation
def make_api_call(body)
  @http_client.make_api_call(body)
end
```

### Step 9: Error Handling
```ruby
def handle_error(error_message, query)
  {
    success: false,
    error: error_message,
    query: query,
    content: nil,
    citations: [],
    web_results: []
  }
end

def enhance_result(result, query)
  # Add query to result for consistency
  result.merge(query: query)
end
```

## Testing Strategy

### 1. Unit Tests for HTTP
```ruby
RSpec.describe "PerplexitySearch HTTP" do
  it "builds correct request payload" do
    # Test request structure
  end

  it "handles network errors" do
    # Test error handling
  end

  it "respects timeout settings" do
    # Test timeout behavior
  end
end
```

### 2. Integration Tests for Core Modules
```ruby
RSpec.describe "PerplexitySearch Core Integration" do
  it "validates models using Common" do
    # Test model validation
  end

  it "builds options using SearchOptions" do
    # Test option building
  end

  it "formats results using ResultParser" do
    # Test result formatting
  end
end
```

### 3. Backward Compatibility Tests
```ruby
RSpec.describe "PerplexitySearch Compatibility" do
  it "maintains same public API" do
    # Test API compatibility
  end

  it "returns same result structure" do
    # Test result format
  end
end
```

## Rollout Plan

### Phase 0: Create Shared HTTP Client (Day 1)
1. Create `core/lib/raaf/perplexity/http_client.rb`
2. Extract HTTP logic from PerplexityProvider
3. Add comprehensive tests for HTTP client
4. Verify HTTP client works in isolation

### Phase 1: Update PerplexityProvider (Day 2)
1. Refactor PerplexityProvider to use HttpClient
2. Remove duplicate HTTP methods from PerplexityProvider
3. Run provider tests to ensure no regressions
4. Test with real API calls

### Phase 2: Update PerplexitySearch (Day 3)
1. Remove raaf-tools wrapper from PerplexitySearch
2. Integrate HttpClient into PerplexitySearch
3. Add comprehensive tests
4. Run parallel tests with existing implementation

### Phase 3: Validation (Day 4)
1. Test PerplexitySearch with real API calls
2. Verify all parameter combinations work
3. Check error handling scenarios
4. Ensure PerplexityProvider still works correctly

### Phase 4: Deployment (Day 5)
1. Replace existing PerplexitySearch implementation
2. Remove raaf-tools dependency from dsl gemspec
3. Update documentation for both components
4. Update CHANGELOG with breaking changes (if any)

### Phase 5: Cleanup (Day 6)
1. Remove any remaining references to RAAF::Tools::PerplexityTool
2. Remove duplicate HTTP code from other components (if any)
3. Create migration guide for users
4. Update examples and documentation

## Success Criteria

### Functional Requirements
- [ ] SharedHTTP client created in RAAF Core
- [ ] PerplexityProvider uses shared HTTP client
- [ ] PerplexitySearch uses shared HTTP client
- [ ] Tool loads without raaf-tools gem dependency
- [ ] All API parameters work as before
- [ ] Result structure unchanged
- [ ] Error handling maintains same behavior

### Technical Requirements
- [ ] Single HTTP client in `RAAF::Perplexity::HttpClient`
- [ ] No duplicate HTTP code in PerplexityProvider
- [ ] No duplicate HTTP code in PerplexitySearch
- [ ] Uses RAAF::Perplexity::Common for validation
- [ ] Uses RAAF::Perplexity::SearchOptions for options
- [ ] Uses RAAF::Perplexity::ResultParser for formatting
- [ ] HTTP client works reliably across all components

### Quality Requirements
- [ ] All tests pass (Core, Provider, DSL)
- [ ] No performance degradation
- [ ] Logging provides useful debugging info
- [ ] Code maintains consistency across components
- [ ] Single source of truth for HTTP communication
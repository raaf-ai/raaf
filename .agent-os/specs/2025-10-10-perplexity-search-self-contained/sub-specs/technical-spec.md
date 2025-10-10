# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-10-10-perplexity-search-self-contained/spec.md

> Created: 2025-10-10
> Version: 1.0.0

## Technical Requirements

### Architecture Change
- Remove wrapper pattern around RAAF::Tools::PerplexityTool
- Extract HTTP client logic from PerplexityProvider into RAAF Core
- Create shared `RAAF::Perplexity::HttpClient` module in Core
- Both PerplexitySearch and PerplexityProvider use shared HTTP client
- Use RAAF Core common modules for shared functionality
- Follow TavilySearch pattern for consistency

### Shared HTTP Client Implementation (RAAF Core)
- Create new module: `core/lib/raaf/perplexity/http_client.rb`
- Extract HTTP logic from PerplexityProvider (`make_api_call`, `configure_http_client`, `build_http_request`)
- Use Net::HTTP for API calls (no external HTTP gems)
- Target endpoint: `https://api.perplexity.ai/chat/completions`
- Support POST requests with JSON payload
- Handle timeouts and errors gracefully
- Return consistent result structure
- Single source of truth for all Perplexity HTTP communication

### Integration with Core Modules
- Use `RAAF::Perplexity::Common` for model and filter validation
- Use `RAAF::Perplexity::SearchOptions` for building web_search_options
- Use `RAAF::Perplexity::ResultParser` for formatting API responses
- Use `RAAF::Perplexity::HttpClient` for all HTTP communication
- Maintain consistency across PerplexityProvider, PerplexitySearch, and PerplexityTool

## Approach Options

**Option A: Individual HTTP Implementation per Component**
- Each component (PerplexitySearch, PerplexityProvider) has its own HTTP code
- Pros: Minimal changes, components remain independent
- Cons: Code duplication, maintenance burden, inconsistency risk

**Option B: Shared HTTP Client in RAAF Core (Selected)**
- Extract HTTP logic from PerplexityProvider into `RAAF::Perplexity::HttpClient`
- Both PerplexitySearch and PerplexityProvider use shared HTTP client
- Follow established pattern with other Core modules (Common, SearchOptions, ResultParser)
- Pros: Single source of truth, no code duplication, consistent behavior, easier maintenance
- Cons: Requires changes to both PerplexityProvider and PerplexitySearch

**Rationale:** Option B selected to eliminate code duplication and establish a single source of truth for all Perplexity HTTP communication. This aligns with the existing pattern where Core provides shared functionality (Common, SearchOptions, ResultParser) used by multiple components.

## External Dependencies

### To Be Removed
- **raaf-tools gem** - Currently required for RAAF::Tools::PerplexityTool
  - Justification for removal: Creates loading errors in DSL agent discovery

### To Be Added
- **None** - All functionality will use Ruby stdlib (Net::HTTP, URI, JSON)

### Core Dependencies (Retained and Enhanced)
- **raaf-core gem** - For common Perplexity modules
  - RAAF::Perplexity::Common - Model and filter validation
  - RAAF::Perplexity::SearchOptions - Option building
  - RAAF::Perplexity::ResultParser - Result formatting
  - RAAF::Perplexity::HttpClient - **NEW** - Shared HTTP communication

## Implementation Details

### New RAAF Core Module: HttpClient

**File:** `core/lib/raaf/perplexity/http_client.rb`

```ruby
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

      # Main method for making API calls
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
```

### File Structure Changes

```ruby
# Current PerplexitySearch structure (wrapper pattern)
class PerplexitySearch < Base
  def initialize(options = {})
    @perplexity_tool = RAAF::Tools::PerplexityTool.new(...)
  end

  def call(...)
    @perplexity_tool.call(...)
  end
end

# New PerplexitySearch structure (using shared HTTP client)
class PerplexitySearch < Base
  def initialize(options = {})
    super(DEFAULT_CONFIG.merge(options || {}))
    @http_client = RAAF::Perplexity::HttpClient.new(
      api_key: api_key,
      timeout: self.options[:timeout],
      open_timeout: self.options[:timeout]
    )
    validate_options!
  end

  def call(query:, **kwargs)
    # Build request
    params = build_request_params(query, **kwargs)

    # Make HTTP request using shared client
    response = @http_client.make_api_call(params)

    # Format response
    format_response(response, query)
  end

  private

  def build_request_params(query, **kwargs)
    # Use RAAF::Perplexity::SearchOptions
  end

  def format_response(response, query)
    # Use RAAF::Perplexity::ResultParser
  end
end

# Current PerplexityProvider structure (embedded HTTP)
class PerplexityProvider
  def make_api_call(body)
    uri = URI("#{@api_base}/chat/completions")
    http = configure_http_client(uri)
    request = build_http_request(uri, body)
    # ... HTTP logic ...
  end
end

# New PerplexityProvider structure (using shared HTTP client)
class PerplexityProvider
  def initialize(api_key: nil, ...)
    @http_client = RAAF::Perplexity::HttpClient.new(
      api_key: api_key || ENV["PERPLEXITY_API_KEY"],
      api_base: @api_base,
      timeout: @timeout,
      open_timeout: @open_timeout
    )
  end

  def make_api_call(body)
    @http_client.make_api_call(body)
  end
end
```

### HTTP Request Structure

**NOTE:** HTTP logic is now in `RAAF::Perplexity::HttpClient`, not duplicated in each component.

```ruby
# Usage from PerplexitySearch or PerplexityProvider
http_client = RAAF::Perplexity::HttpClient.new(
  api_key: api_key,
  timeout: timeout,
  open_timeout: open_timeout
)

# Make API call with prepared body
response = http_client.make_api_call({
  model: "sonar",
  messages: [{ role: "user", content: "query" }],
  web_search_options: { ... }
})
```

### Request Payload Structure
```json
{
  "model": "sonar",
  "messages": [
    {
      "role": "user",
      "content": "search query here"
    }
  ],
  "web_search_options": {
    "search_domain_filter": ["domain1.com", "domain2.com"],
    "search_recency_filter": "week"
  },
  "max_tokens": 1000
}
```

### Response Handling
```ruby
def format_response(response, query)
  if response["error"]
    {
      success: false,
      error: response["error"],
      query: query,
      results: []
    }
  else
    # Use RAAF::Perplexity::ResultParser
    result = RAAF::Perplexity::ResultParser.format_search_result(response)
    result.merge(query: query)
  end
end
```

## Testing Requirements

### Unit Tests
- HTTP request building with various parameters
- Error handling for network failures
- Timeout handling
- Response parsing for success and error cases

### Integration Tests
- Validation using RAAF::Perplexity::Common
- Option building using RAAF::Perplexity::SearchOptions
- Result formatting using RAAF::Perplexity::ResultParser
- End-to-end API calls (with mocked HTTP)

### Backward Compatibility Tests
- Ensure same public API as current implementation
- Verify result structure matches current format
- Test all parameter combinations still work

## Migration Impact

### Breaking Changes
- None - Public API remains identical

### Required Updates
- DSL agents using PerplexitySearch: No changes required
- Tool registration: No changes required
- Tool definition: No changes required

### Testing Strategy
1. Create new implementation alongside existing
2. Run parallel tests comparing outputs
3. Replace implementation once verified
4. Remove raaf-tools dependency

## Performance Considerations

### HTTP Connection
- Reuse Net::HTTP connection when possible
- Implement connection pooling for high-volume usage
- Respect timeout settings

### Error Recovery
- Implement exponential backoff for rate limits
- Handle network errors gracefully
- Provide meaningful error messages

## Security Considerations

### API Key Handling
- Continue using ENV["PERPLEXITY_API_KEY"]
- Never log or expose API key
- Use secure HTTPS connection

### Request Validation
- Validate all input parameters
- Sanitize query strings
- Enforce parameter limits
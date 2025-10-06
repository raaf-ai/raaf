# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-10-05-perplexity-provider/spec.md

> Created: 2025-10-05
> Version: 1.0.0

## Technical Requirements

### Provider Implementation
- Inherit from `RAAF::Models::ModelInterface` (same as other providers)
- Implement `perform_chat_completion` method
- Follow OpenAI-compatible API format (Perplexity uses OpenAI-compatible endpoints)
- Support `api_key` and `api_base` configuration options
- Handle Perplexity-specific response format (citations, web search results)

### API Integration
- **Base URL:** `https://api.perplexity.ai`
- **Endpoint:** `/chat/completions`
- **Authentication:** Bearer token in Authorization header
- **HTTP Method:** POST

### Supported Models
- `sonar` - Fast, cost-effective web search
- `sonar-pro` - Advanced search with deeper analysis and more citations (supports JSON schema)
- `sonar-reasoning-pro` - Advanced reasoning with structured outputs (supports JSON schema)
- `sonar-deep-research` - In-depth research with async support

### Request Parameters
- `messages` - Conversation history (required)
- `model` - Perplexity model name (required)
- `temperature` - Control response creativity (0.0-2.0)
- `max_tokens` - Limit response length
- `top_p` - Nucleus sampling parameter
- `response_format` - Structured output control (Perplexity-specific)
  - `type: "json_schema"` - Use JSON schema for structured outputs
  - `json_schema` - Schema definition object
    - `schema` - JSON schema object defining expected structure
- `web_search_options` - Control web search behavior (Perplexity-specific)
  - `search_domain_filter` - Limit search to specific domains
  - `search_recency_filter` - Filter by time period

### Response Format
- Parse standard chat completion response
- Extract and expose Perplexity-specific fields:
  - `citations` - Array of web sources cited
  - `web_results` - Raw web search results metadata
  - `search_queries` - Queries used for web search

### Error Handling
- Handle Perplexity-specific rate limits
- Map Perplexity error codes to RAAF error classes
- Provide clear error messages for:
  - Invalid API key (401)
  - Rate limit exceeded (429)
  - Invalid model (400)
  - Service unavailable (503)

## Approach Options

### Option A: Full OpenAI Compatibility Layer
Use OpenAI Ruby client library with modified base_url

**Pros:**
- Minimal code, leverage existing OpenAI client
- Automatic handling of retry logic and error handling
- Streaming support built-in

**Cons:**
- Dependency on openai-ruby gem
- May not expose Perplexity-specific features properly
- Less control over request/response parsing

### Option B: Native HTTP Implementation (Selected)
Implement HTTP requests directly using Net::HTTP

**Pros:**
- Full control over request/response handling
- Easy to expose Perplexity-specific features (citations, web_results)
- No additional gem dependencies
- Consistent with other RAAF providers (Groq, Cohere)

**Cons:**
- More code to write
- Manual error handling and retry logic

**Rationale:** Option B provides better control and consistency with existing RAAF provider patterns. All current providers (Groq, Cohere, Anthropic) use direct HTTP implementations, making this approach more maintainable and aligned with RAAF architecture.

## External Dependencies

**None required** - Use Ruby standard library:
- `net/http` - HTTP client
- `json` - JSON parsing
- `uri` - URL handling

All dependencies already available in Ruby standard library, consistent with other RAAF providers.

## Implementation Pattern

Follow the exact pattern used in `GroqProvider`:
1. Define API_BASE constant
2. Define SUPPORTED_MODELS array
3. Implement `initialize` with api_key and api_base options
4. Implement `perform_chat_completion` with request body building
5. Implement private `make_request` method using Net::HTTP
6. Implement private `handle_api_error` for Perplexity-specific errors
7. Override `supported_models` and `provider_name` methods

## Perplexity-Specific Enhancements

### JSON Schema Support

**Request Format:**
```ruby
# Add response_format for structured outputs
if kwargs[:response_format]
  body[:response_format] = {
    type: "json_schema",
    json_schema: {
      schema: kwargs[:response_format]
    }
  }
end
```

**Supported Models:** `sonar-pro`, `sonar-reasoning-pro`

**Important Limitations:**
- First request with new schema may take 10-30 seconds (caching delay)
- No recursive schemas supported
- No unconstrained objects (e.g., `dict[str, Any]`)
- Models may generate invalid URLs in structured output (use citations field instead)

**RAAF DSL Agent Integration:**
```ruby
# RAAF DSL agents can automatically use Perplexity's JSON schema
class WebSearchAgent < RAAF::DSL::Agent
  instructions "Search the web for #{query}"
  model "sonar-pro"

  schema do
    field :search_results, type: :array, required: true do
      field :title, type: :string, required: true
      field :snippet, type: :string, required: true
    end
    field :result_count, type: :integer, required: true
  end
end

# Provider automatically converts RAAF schema to Perplexity format
provider = RAAF::Models::PerplexityProvider.new
runner = RAAF::Runner.new(agent: agent, provider: provider)
result = runner.run  # Returns structured data matching schema
```

### Citation Extraction
```ruby
def extract_citations(response)
  {
    content: response.dig("choices", 0, "message", "content"),
    citations: response.dig("citations") || [],
    web_results: response.dig("web_results") || []
  }
end
```

### Web Search Options
```ruby
if kwargs[:web_search_options]
  body[:web_search_options] = kwargs[:web_search_options]
end
```

## Testing Strategy

1. **Unit Tests** - Test provider initialization, request building, response parsing
2. **Integration Tests** - Test actual API calls with VCR cassettes
3. **Citation Tests** - Verify citation extraction and formatting
4. **Error Handling Tests** - Test all error scenarios
5. **Model Support Tests** - Verify all supported models work correctly

## Documentation Requirements

1. Update providers README with Perplexity section
2. Add Perplexity examples to examples/ directory
3. Document web_search_options parameter
4. Provide citation handling examples
5. Update CLAUDE.md with Perplexity provider usage

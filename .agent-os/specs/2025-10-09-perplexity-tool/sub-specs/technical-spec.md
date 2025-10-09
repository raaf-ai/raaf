# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-10-09-perplexity-tool/spec.md

> Created: 2025-10-09
> Version: 2.0.0

## Technical Requirements

### PerplexityProvider Refactoring

Refactor `PerplexityProvider` to use common retry logic, error handling, and HTTP management from `ModelInterface` base class.

**Current Issues:**
- Duplicates retry logic with custom `with_retry` wrapper
- Duplicates HTTP request/response handling
- Duplicates error handling patterns
- ~264 lines of code with significant duplication

**Refactoring Goals:**
- Remove custom `with_retry` wrapper → use `ModelInterface.chat_completion` automatic retry
- Simplify `make_request` method → focus only on HTTP communication
- Use `ModelInterface.handle_api_error` → consistent error handling across providers
- Reduce to ~200 lines of focused provider code

### Code Changes Required

**1. Remove Duplicate Retry Wrapper:**

```ruby
# BEFORE: Custom retry in perform_chat_completion
def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
  validate_model(model)
  body = { model: model, messages: messages }

  with_retry("chat_completion") do  # ❌ REMOVE: Base class handles this
    make_request(body)
  end
end

# AFTER: Let base class handle retry automatically
def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
  validate_model(model)

  if tools && !tools.empty?
    log_warn("Perplexity does not support function/tool calling", model: model)
  end

  body = build_request_body(messages, model, stream, **kwargs)
  make_api_call(body)  # ✅ Base class wraps this method with retry via chat_completion
end
```

**2. Extract HTTP Client Configuration:**

```ruby
# NEW: Extract HTTP setup into separate method
def configure_http_client(uri)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = @timeout
  http.open_timeout = @open_timeout
  http
end
```

**3. Extract Request Building:**

```ruby
# NEW: Extract request building logic
def build_http_request(uri, body)
  request = Net::HTTP::Post.new(uri)
  request["Authorization"] = "Bearer #{@api_key}"
  request["Content-Type"] = "application/json"
  request.body = body.to_json
  request
end
```

**4. Simplify API Call Method:**

```ruby
# BEFORE: Monolithic make_request with retry wrapper
def make_request(body)
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
  handle_api_error(response) unless response.code.start_with?("2")
  RAAF::Utils.parse_json(response.body)
end

# AFTER: Focused API call using extracted methods
def make_api_call(body)
  uri = URI("#{@api_base}/chat/completions")
  http = configure_http_client(uri)
  request = build_http_request(uri, body)
  response = http.request(request)

  handle_api_error(response, provider_name) unless response.code.start_with?("2")
  RAAF::Utils.parse_json(response.body)
end
```

**5. Extract Request Body Building:**

```ruby
# NEW: Extract body building for clarity
def build_request_body(messages, model, stream, **kwargs)
  body = {
    model: model,
    messages: messages,
    stream: stream
  }

  # Add optional parameters
  body[:temperature] = kwargs[:temperature] if kwargs[:temperature]
  body[:max_tokens] = kwargs[:max_tokens] if kwargs[:max_tokens]
  body[:top_p] = kwargs[:top_p] if kwargs[:top_p]
  body[:presence_penalty] = kwargs[:presence_penalty] if kwargs[:presence_penalty]
  body[:frequency_penalty] = kwargs[:frequency_penalty] if kwargs[:frequency_penalty]

  # Handle response_format with unwrapping
  if kwargs[:response_format]
    validate_schema_support(model)
    body[:response_format] = unwrap_response_format(kwargs[:response_format])
  end

  # Add Perplexity-specific web_search_options
  body[:web_search_options] = kwargs[:web_search_options] if kwargs[:web_search_options]

  body
end
```

### PerplexityFactualSearchAgent - No Changes Required

**IMPORTANT:** `PerplexityFactualSearchAgent` is an **agent class**, not a provider. This refactoring does **NOT** affect it.

**Architecture Clarification:**
```
PerplexityFactualSearchAgent (Agent)
  └─ uses ──> PerplexityProvider (Provider) ← THIS GETS REFACTORED
                └─ inherits from ──> ModelInterface (Base Class) ← PROVIDES COMMON CODE
```

**Why No Changes?**
1. PerplexityFactualSearchAgent extends `ApplicationAgent`, not `ModelInterface`
2. It configures which provider to use (`model "perplexity"`)
3. It doesn't implement HTTP communication or retry logic
4. All API communication happens in PerplexityProvider

**Impact on PerplexityFactualSearchAgent:**
- ✅ **Zero code changes** - Agent continues working exactly as before
- ✅ **Automatic benefit** - Gets improved retry behavior through refactored provider
- ✅ **Transparent** - Provider refactoring is invisible to agents

### Perplexity-Specific Features Preserved

**Response Format Unwrapping:**
```ruby
# NEW: Extract response_format unwrapping logic
def unwrap_response_format(response_format)
  # Detect if response_format is OpenAI-wrapped format from DSL agents
  if response_format.is_a?(Hash) &&
     response_format[:type] == "json_schema" &&
     response_format[:json_schema]
    # Extract schema from OpenAI format
    schema = response_format[:json_schema][:schema]
  else
    # Use raw schema as-is
    schema = response_format
  end

  # Wrap in Perplexity format
  {
    type: "json_schema",
    json_schema: {
      schema: schema
    }
  }
end
```

**Domain and Recency Filtering:**
```ruby
# Preserved: Perplexity-specific web_search_options
body[:web_search_options] = kwargs[:web_search_options] if kwargs[:web_search_options]

# Example usage (unchanged):
# web_search_options: {
#   search_domain_filter: ["ruby-lang.org"],
#   search_recency_filter: "week"
# }
```

**Schema Support Validation:**
```ruby
# Preserved: Validates JSON schema support per model
def validate_schema_support(model)
  schema_models = %w[sonar-pro sonar-reasoning-pro]
  return if schema_models.include?(model)

  raise ArgumentError,
        "JSON schema (response_format) is only supported on #{schema_models.join(', ')}. " \
        "Current model: #{model}"
end
```

## File Structure

```
vendor/local_gems/raaf/
└── providers/
    └── lib/
        └── raaf/
            └── perplexity_provider.rb (REFACTORED - simplified to use ModelInterface)
```

**Single File Change:**
- Only `perplexity_provider.rb` is modified
- All other files remain unchanged

## Testing Strategy

### Retry Behavior Tests

```ruby
RSpec.describe RAAF::Models::PerplexityProvider do
  describe "retry behavior" do
    it "uses ModelInterface retry logic" do
      provider = described_class.new(api_key: "test")

      # Stub HTTP to fail twice then succeed
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:request)
        .and_raise(Net::ReadTimeout)
        .once
        .and_return(success_response)

      # Should retry and succeed
      result = provider.chat_completion(
        messages: [{ role: "user", content: "test" }],
        model: "sonar"
      )

      expect(result).to be_success
    end

    it "respects exponential backoff" do
      # Test that delays increase exponentially
    end

    it "applies jitter to prevent thundering herd" do
      # Test that delays include random jitter
    end
  end
end
```

### Error Handling Tests

```ruby
RSpec.describe RAAF::Models::PerplexityProvider do
  describe "error handling" do
    it "raises AuthenticationError for 401" do
      expect {
        provider.chat_completion(messages: messages, model: "sonar")
      }.to raise_error(RAAF::Models::AuthenticationError)
    end

    it "raises RateLimitError for 429" do
      expect {
        provider.chat_completion(messages: messages, model: "sonar")
      }.to raise_error(RAAF::Models::RateLimitError)
    end

    it "raises ServerError for 5xx" do
      expect {
        provider.chat_completion(messages: messages, model: "sonar")
      }.to raise_error(RAAF::Models::ServerError)
    end
  end
end
```

### Perplexity-Specific Feature Tests

```ruby
RSpec.describe RAAF::Models::PerplexityProvider do
  describe "Perplexity features" do
    it "validates schema support per model" do
      expect {
        provider.chat_completion(
          messages: messages,
          model: "sonar",  # Doesn't support schemas
          response_format: schema
        )
      }.to raise_error(ArgumentError, /only supported on sonar-pro/)
    end

    it "unwraps OpenAI response_format correctly" do
      # Test response_format unwrapping logic
    end

    it "passes web_search_options to API" do
      # Test domain and recency filtering
    end
  end
end
```

## Performance Considerations

**Retry Configuration:**
- Default: 3 attempts with exponential backoff
- Base delay: 1 second
- Max delay: 30 seconds
- Jitter: ±10% to prevent thundering herd

**HTTP Timeouts:**
- Read timeout: 180 seconds (Perplexity can be slow)
- Open timeout: 30 seconds
- Configurable via environment variables:
  - `PERPLEXITY_TIMEOUT` - Read timeout
  - `PERPLEXITY_OPEN_TIMEOUT` - Connection timeout

**Cost Optimization:**
- No changes to cost tracking (uses existing SearchCostTracking integration)
- Model costs remain consistent:
  - `sonar`: ~$0.01 per search
  - `sonar-pro`: ~$0.03 per search

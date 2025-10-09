# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-10-09-perplexity-tool/spec.md

> Created: 2025-10-09
> Version: 2.0.0

## Test Coverage

### Unit Tests

**RAAF::Models::PerplexityProvider - Retry Logic**
- `chat_completion` uses ModelInterface.with_retry for automatic retry
- `chat_completion` retries on Net::ReadTimeout
- `chat_completion` retries on Net::WriteTimeout
- `chat_completion` retries on Errno::ECONNRESET
- `chat_completion` respects max_attempts (default 3)
- `chat_completion` applies exponential backoff (base_delay × multiplier^(attempt-1))
- `chat_completion` applies jitter to delays (±10%)
- `chat_completion` caps delay at max_delay (30 seconds)
- `chat_completion` logs retry attempts with delay information
- `chat_completion` logs final failure after exhausting retries

**RAAF::Models::PerplexityProvider - Error Handling**
- `handle_api_error` raises AuthenticationError for 401 responses
- `handle_api_error` raises RateLimitError for 429 responses
- `handle_api_error` raises ServerError for 5xx responses
- `handle_api_error` raises APIError for other error responses
- `handle_api_error` includes provider name in error messages
- `handle_api_error` extracts retry-after header for rate limits
- `handle_api_error` parses error messages from response body

**RAAF::Models::PerplexityProvider - HTTP Communication**
- `configure_http_client` sets SSL to true
- `configure_http_client` sets read_timeout from @timeout
- `configure_http_client` sets open_timeout from @open_timeout
- `build_http_request` sets Authorization header with Bearer token
- `build_http_request` sets Content-Type to application/json
- `build_http_request` serializes body to JSON
- `make_api_call` calls handle_api_error for non-2xx responses
- `make_api_call` parses response body as JSON with indifferent access

**RAAF::Models::PerplexityProvider - Request Body Building**
- `build_request_body` includes model parameter
- `build_request_body` includes messages parameter
- `build_request_body` includes stream parameter
- `build_request_body` includes optional temperature
- `build_request_body` includes optional max_tokens
- `build_request_body` includes optional top_p
- `build_request_body` includes optional presence_penalty
- `build_request_body` includes optional frequency_penalty
- `build_request_body` includes web_search_options when provided
- `build_request_body` calls unwrap_response_format for response_format
- `build_request_body` validates schema support before adding response_format

**RAAF::Models::PerplexityProvider - Response Format Handling**
- `unwrap_response_format` extracts schema from OpenAI-wrapped format
- `unwrap_response_format` handles raw schema format
- `unwrap_response_format` wraps in Perplexity json_schema format
- `validate_schema_support` raises error for sonar model with schema
- `validate_schema_support` allows schema for sonar-pro
- `validate_schema_support` allows schema for sonar-reasoning-pro

**RAAF::Models::PerplexityProvider - Model Validation**
- `validate_model` accepts all 4 supported models (sonar, sonar-pro, sonar-reasoning, sonar-reasoning-pro)
- `validate_model` raises ArgumentError for unsupported model
- `supported_models` returns array of 4 model names
- `provider_name` returns "Perplexity"

### Integration Tests

**Provider with Agent Integration**
- Agent using PerplexityProvider can execute chat completions
- Agent with Perplexity model sends correct request format
- Provider returns responses in expected RAAF format
- Agent can make follow-up calls with different models
- Provider integrates with RAAF tracing system

**Provider with Different Models**
- Provider successfully completes chat with sonar model
- Provider successfully completes chat with sonar-pro model
- Provider successfully completes chat with sonar-reasoning model
- Provider successfully completes chat with sonar-reasoning-pro model
- Provider validates model parameter before API call
- Provider raises ArgumentError for unsupported model

**Search Configuration Options**
- Provider passes web_search_options to API correctly
- Provider filters results by domain when specified
- Provider filters results by recency when specified
- Provider includes related questions when requested
- Provider includes images when requested
- Provider handles empty domain filter array

**Provider Consistency with Other Providers**
- PerplexityProvider retry behavior matches ResponsesProvider
- PerplexityProvider error handling matches ResponsesProvider
- PerplexityProvider response format matches RAAF standards
- PerplexityProvider integrates with Runner like other providers

**Runner Integration**
- Runner can use PerplexityProvider for agent execution
- Runner passes context correctly to PerplexityProvider
- Runner handles provider errors gracefully
- Runner supports provider switching between calls

### Feature Tests

**Perplexity-Specific Features Preserved**
- Schema validation works correctly (sonar-pro and sonar-reasoning-pro only)
- Response format unwrapping extracts OpenAI-wrapped schemas
- Response format unwrapping handles raw schemas
- Response format unwrapping wraps in Perplexity json_schema format
- Domain filtering passes through to API
- Recency filtering passes through to API
- Tool call warnings logged when tools provided (not supported by Perplexity)

**API Parameter Handling**
- Optional parameters (temperature, max_tokens, top_p) passed correctly
- Presence_penalty and frequency_penalty passed correctly
- Web_search_options passed correctly with all sub-options
- Response_format validated and transformed correctly
- Stream parameter passed correctly (even though not implemented)

### Mocking Requirements

**Perplexity API Responses**
- Mock standard chat completion response with content
- Mock response with metadata.search_results (citations)
- Mock sonar-pro response with structured output
- Mock sonar-reasoning response with deep analysis
- Mock API error responses (401, 429, 503)
- Mock empty result responses
- Mock responses with and without related questions
- Mock responses with and without images

**HTTP Mocking**
- Mock Net::HTTP.new for HTTP client tests
- Mock Net::HTTP::Post.new for request building tests
- Mock http.request for response handling tests
- Mock successful responses (2xx status codes)
- Mock error responses (4xx, 5xx status codes)

**ModelInterface Mocking**
- Mock ModelInterface.with_retry for retry logic tests
- Mock ModelInterface.handle_api_error for error handling tests
- Verify retry configuration passed correctly
- Verify error responses trigger correct error types

### Error Handling Tests

**Provider Error Handling**
- Provider raises AuthenticationError for 401 responses
- Provider raises RateLimitError for 429 responses
- Provider raises ServerError for 5xx responses
- Provider raises APIError for other error responses
- Provider includes provider name ("Perplexity") in error messages
- Provider extracts retry-after header for rate limits
- Provider parses error messages from response body

**Network Error Handling**
- Provider retries on Net::ReadTimeout
- Provider retries on Net::WriteTimeout
- Provider retries on Errno::ECONNRESET
- Provider logs retry attempts with delay information
- Provider logs final failure after exhausting retries
- Provider respects max_attempts configuration

**Validation Errors**
- Provider raises ArgumentError for invalid model name
- Provider raises error for missing API key
- Provider validates schema support before adding response_format
- Provider handles invalid response_format gracefully
- Provider warns when tools provided (not supported by Perplexity)

### Test Helpers

**Shared Test Fixtures**
```ruby
# spec/support/perplexity_fixtures.rb
module PerplexityFixtures
  def mock_perplexity_response(model: "sonar", citations: 3)
    {
      "choices" => [
        {
          "message" => {
            "content" => "Search results content...",
            "role" => "assistant"
          },
          "finish_reason" => "stop"
        }
      ],
      "metadata" => {
        "search_results" => Array.new(citations) do |i|
          {
            "url" => "https://example.com/article-#{i}",
            "title" => "Article #{i}",
            "snippet" => "Relevant excerpt #{i}"
          }
        end
      },
      "model" => model,
      "usage" => {
        "prompt_tokens" => 100,
        "completion_tokens" => 200,
        "total_tokens" => 300
      }
    }
  end

  def mock_http_response(status: 200, body: {})
    response = Net::HTTPSuccess.new("1.1", status.to_s, "OK")
    allow(response).to receive(:code).and_return(status.to_s)
    allow(response).to receive(:body).and_return(body.to_json)
    response
  end

  def mock_error_response(status: 429, message: "Rate limit exceeded")
    response = Net::HTTPTooManyRequests.new("1.1", status.to_s, message)
    allow(response).to receive(:code).and_return(status.to_s)
    allow(response).to receive(:body).and_return({ error: { message: message } }.to_json)
    response
  end
end
```

**Shared Examples**
```ruby
# spec/support/shared_examples/provider_shared.rb
RSpec.shared_examples "RAAF provider" do
  it "implements required interface methods" do
    expect(subject).to respond_to(:chat_completion)
    expect(subject).to respond_to(:perform_chat_completion)
    expect(subject).to respond_to(:supported_models)
    expect(subject).to respond_to(:provider_name)
  end

  it "returns responses in RAAF format" do
    response = subject.chat_completion(
      messages: [{ role: "user", content: "test" }],
      model: subject.supported_models.first
    )
    expect(response).to be_a(Hash)
    expect(response).to have_key("choices")
  end

  it "retries on transient failures" do
    # Verify retry behavior
    expect(subject).to respond_to(:with_retry)
  end
end
```

### Performance Tests

**Response Time**
- Provider completes chat_completion within timeout for sonar
- Provider completes chat_completion within timeout for sonar-reasoning-pro
- Provider respects read_timeout configuration
- Provider respects open_timeout configuration

**Memory Usage**
- Provider doesn't leak memory with repeated calls
- Response parsing doesn't retain large response objects
- HTTP client properly cleaned up after each request

### Regression Tests

**PerplexityProvider Public API**
- All existing PerplexityProvider tests pass after refactoring
- `chat_completion` method signature unchanged
- `perform_chat_completion` method signature unchanged
- `supported_models` returns same model list
- `provider_name` returns "Perplexity"
- Initialization parameters unchanged (api_key, api_base, timeout, open_timeout)

**Agent Compatibility**
- Agents using PerplexityProvider work identically after refactoring
- PerplexityFactualSearchAgent tests still pass (no changes needed to agent)
- Agents can use all 4 supported models
- Agents receive same response format
- No breaking changes to agent code

**Feature Preservation**
- Schema validation still works for sonar-pro and sonar-reasoning-pro
- Response format unwrapping preserved
- Domain filtering preserved
- Recency filtering preserved
- Web_search_options passed correctly
- Tool call warnings still logged

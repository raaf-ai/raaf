# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-10-05-perplexity-provider/spec.md

> Created: 2025-10-05
> Version: 1.0.0

## Test Coverage

### Unit Tests

**PerplexityProvider Initialization**
- Initializes with API key from constructor
- Initializes with API key from ENV['PERPLEXITY_API_KEY']
- Raises AuthenticationError if no API key provided
- Sets custom api_base when provided
- Uses default API_BASE when not specified

**Model Validation**
- Validates model is in SUPPORTED_MODELS list
- Raises ModelNotFoundError for unsupported models
- Returns supported_models array
- Returns "Perplexity" as provider_name

**Request Building**
- Builds correct request body with messages and model
- Adds temperature when provided
- Adds max_tokens when provided
- Adds top_p when provided
- Adds response_format with JSON schema when provided
- Converts RAAF schema format to Perplexity format
- Adds web_search_options when provided
- Excludes nil values from request body

**Response Parsing**
- Parses standard chat completion response
- Extracts content from response
- Extracts citations when present
- Extracts web_results when present
- Handles response with missing optional fields

### Integration Tests

**Chat Completion**
- Performs basic chat completion with sonar model
- Performs chat completion with sonar-pro model
- Handles multi-message conversations
- Respects temperature parameter
- Respects max_tokens parameter
- Returns response with citations

**JSON Schema Support**
- Accepts response_format parameter with JSON schema
- Converts RAAF DSL agent schema to Perplexity format
- Validates schema-supported models (sonar-pro, sonar-reasoning-pro)
- Returns structured data matching schema
- Handles schema validation errors
- Handles first-request caching delay (10-30 seconds)
- Tests with RAAF DSL agent integration

**Web Search Options**
- Applies search_domain_filter correctly
- Applies search_recency_filter correctly
- Combines multiple web_search_options

**Error Handling**
- Handles 401 authentication errors
- Handles 429 rate limit errors with retry-after
- Handles 400 bad request errors
- Handles 503 service unavailable errors
- Provides clear error messages

**Citation Extraction**
- Extracts citations array from response
- Extracts web_results metadata
- Handles responses without citations
- Formats citations consistently

### Mocking Requirements

**VCR Cassettes**
- Record successful chat completion responses for each model
- Record error responses (401, 429, 400, 503)
- Record responses with citations
- Record responses with JSON schema (sonar-pro, sonar-reasoning-pro)
- Record responses with web_search_options
- Record RAAF DSL agent with schema integration

**WebMock Stubs**
- Stub Perplexity API endpoint
- Stub authentication failures
- Stub rate limit responses with headers
- Stub network timeouts

### Test Files Structure

```
spec/
├── raaf/
│   └── models/
│       └── perplexity_provider_spec.rb      # Main provider tests
└── fixtures/
    └── vcr_cassettes/
        └── perplexity/
            ├── chat_completion_sonar.yml
            ├── chat_completion_sonar_pro.yml
            ├── chat_completion_sonar_reasoning_pro.yml
            ├── chat_completion_with_citations.yml
            ├── json_schema_response.yml
            ├── dsl_agent_schema.yml
            ├── error_unauthorized.yml
            ├── error_rate_limit.yml
            └── web_search_options.yml
```

### Example Test Cases

**Basic Chat Completion Test:**
```ruby
it "performs chat completion with sonar model" do
  VCR.use_cassette("perplexity/chat_completion_sonar") do
    result = provider.chat_completion(
      messages: [{ role: "user", content: "What is RAAF?" }],
      model: "sonar"
    )

    expect(result).to have_key("choices")
    expect(result["choices"][0]["message"]["content"]).to be_a(String)
  end
end
```

**Citation Extraction Test:**
```ruby
it "extracts citations from response" do
  VCR.use_cassette("perplexity/chat_completion_with_citations") do
    result = provider.chat_completion(
      messages: [{ role: "user", content: "Latest Ruby news" }],
      model: "sonar-pro"
    )

    expect(result).to have_key("citations")
    expect(result["citations"]).to be_an(Array)
    expect(result["web_results"]).to be_an(Array)
  end
end
```

**Error Handling Test:**
```ruby
it "handles rate limit errors" do
  stub_request(:post, "https://api.perplexity.ai/chat/completions")
    .to_return(status: 429, headers: { "x-ratelimit-reset" => "60" })

  expect {
    provider.chat_completion(
      messages: [{ role: "user", content: "test" }],
      model: "sonar"
    )
  }.to raise_error(RAAF::Errors::RateLimitError, /Reset at: 60/)
end
```

**JSON Schema Test:**
```ruby
it "performs chat completion with JSON schema" do
  schema = {
    type: "object",
    properties: {
      search_results: {
        type: "array",
        items: {
          type: "object",
          properties: {
            title: { type: "string" },
            snippet: { type: "string" }
          },
          required: ["title", "snippet"]
        }
      },
      result_count: { type: "integer" }
    },
    required: ["search_results", "result_count"]
  }

  VCR.use_cassette("perplexity/json_schema_response") do
    result = provider.chat_completion(
      messages: [{ role: "user", content: "Latest Ruby news" }],
      model: "sonar-pro",
      response_format: schema
    )

    expect(result["choices"][0]["message"]["content"]).to be_a(String)
    parsed = JSON.parse(result["choices"][0]["message"]["content"])
    expect(parsed).to have_key("search_results")
    expect(parsed).to have_key("result_count")
    expect(parsed["search_results"]).to be_an(Array)
  end
end
```

**RAAF DSL Agent Integration Test:**
```ruby
it "works with RAAF DSL agent schema" do
  class TestSearchAgent < RAAF::DSL::Agent
    instructions "Search for Ruby news"
    model "sonar-pro"

    schema do
      field :search_results, type: :array, required: true do
        field :title, type: :string, required: true
        field :snippet, type: :string, required: true
      end
      field :result_count, type: :integer, required: true
    end
  end

  agent = TestSearchAgent.new
  runner = RAAF::Runner.new(agent: agent, provider: provider)

  VCR.use_cassette("perplexity/dsl_agent_schema") do
    result = runner.run("Find latest Ruby news")

    expect(result[:search_results]).to be_an(Array)
    expect(result[:result_count]).to be_an(Integer)
  end
end
```

### Test Execution

Run all provider tests:
```bash
cd providers/
bundle exec rspec spec/raaf/models/perplexity_provider_spec.rb
```

Run with VCR recording:
```bash
VCR_MODE=all bundle exec rspec spec/raaf/models/perplexity_provider_spec.rb
```

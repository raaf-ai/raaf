# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-10-10-perplexity-search-self-contained/spec.md

> Created: 2025-10-10
> Version: 1.0.0

## Test Coverage

### Unit Tests

**RAAF::DSL::Tools::PerplexitySearch**

**Initialization Tests**
- Merges default config with options
- Validates model on initialization
- Validates recency filter on initialization
- Validates max_tokens range
- Raises error for invalid model
- Raises error for invalid recency filter
- Raises error when API key not set

**HTTP Request Tests**
- Builds correct URI for Perplexity API
- Sets proper HTTP headers (Authorization, Content-Type)
- Constructs valid JSON payload
- Includes web_search_options when provided
- Excludes web_search_options when not provided
- Respects timeout settings
- Handles network errors gracefully
- Returns error hash on exception

**Core Module Integration Tests**
- Uses RAAF::Perplexity::Common for model validation
- Uses RAAF::Perplexity::Common for recency validation
- Uses RAAF::Perplexity::SearchOptions to build options
- Uses RAAF::Perplexity::ResultParser to format success response
- Constants reference Core module constants

**Tool Definition Tests**
- Returns correct tool name
- Builds valid function definition
- Includes all required parameters
- Uses Core constants in enum values
- Marks query as required parameter

**Call Method Tests**
- Accepts query parameter
- Accepts optional model parameter
- Accepts optional search_domain_filter
- Accepts optional search_recency_filter
- Accepts optional max_tokens
- Merges runtime params with configured options
- Runtime params override configured options

**Response Formatting Tests**
- Formats successful API response
- Handles error responses
- Includes query in result
- Returns success: false on error
- Returns success: true on success
- Preserves citations from API response
- Preserves web_results from API response

**Logging Tests**
- Logs request details at debug level
- Logs response success at debug level
- Logs errors at error level
- Truncates long queries in logs
- Includes duration in log messages

### Integration Tests

**API Integration**
- Makes successful API call with basic query
- Handles domain filtering correctly
- Handles recency filtering correctly
- Combines multiple filters properly
- Respects max_tokens limit
- Returns citations when available
- Returns web_results when available

**Error Scenarios**
- Handles 401 unauthorized (bad API key)
- Handles 429 rate limit exceeded
- Handles 500 server error
- Handles network timeout
- Handles malformed JSON response
- Provides meaningful error messages

**Backward Compatibility**
- Maintains same public interface as old implementation
- Returns same result structure
- Accepts same parameters
- Validates same constraints
- Produces same error messages

### Mocking Requirements

**HTTP Requests**
- Mock Net::HTTP for unit tests
- Stub API responses for different scenarios
- Simulate network failures
- Simulate timeout conditions

**Environment Variables**
- Mock ENV["PERPLEXITY_API_KEY"]
- Test behavior when API key missing
- Test with different API key values

**Core Modules**
- Allow real Core module calls in integration tests
- Mock Core modules for specific error testing
- Verify Core module methods are called correctly

## Test Implementation Examples

### Unit Test Example
```ruby
RSpec.describe RAAF::DSL::Tools::PerplexitySearch do
  let(:tool) { described_class.new }
  let(:api_key) { "test-api-key" }

  before do
    ENV["PERPLEXITY_API_KEY"] = api_key
  end

  describe "#initialize" do
    context "with valid options" do
      it "accepts valid model" do
        tool = described_class.new(model: "sonar-pro")
        expect(tool.options[:model]).to eq("sonar-pro")
      end
    end

    context "with invalid options" do
      it "raises error for invalid model" do
        expect {
          described_class.new(model: "invalid-model")
        }.to raise_error(ArgumentError, /Model 'invalid-model' is not supported/)
      end
    end
  end

  describe "#call" do
    let(:mock_response) do
      {
        "choices" => [
          { "message" => { "content" => "Search results here" } }
        ],
        "citations" => ["https://example.com"],
        "web_results" => [
          { "title" => "Example", "url" => "https://example.com" }
        ],
        "model" => "sonar"
      }
    end

    before do
      allow(tool).to receive(:make_request).and_return(mock_response)
    end

    it "returns formatted search results" do
      result = tool.call(query: "test query")

      expect(result[:success]).to be true
      expect(result[:content]).to eq("Search results here")
      expect(result[:citations]).to eq(["https://example.com"])
      expect(result[:web_results]).to have_attributes(count: 1)
      expect(result[:query]).to eq("test query")
    end
  end

  describe "#make_request" do
    let(:http) { instance_double(Net::HTTP) }
    let(:request) { instance_double(Net::HTTP::Post) }
    let(:response) { instance_double(Net::HTTPResponse, body: '{"success": true}') }

    before do
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(Net::HTTP::Post).to receive(:new).and_return(request)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:open_timeout=)
      allow(request).to receive(:[]=)
      allow(request).to receive(:body=)
      allow(http).to receive(:request).and_return(response)
    end

    it "makes HTTP POST request to Perplexity API" do
      params = { model: "sonar", messages: [{ role: "user", content: "test" }] }

      result = tool.send(:make_request, params)

      expect(Net::HTTP).to have_received(:new).with("api.perplexity.ai", 443)
      expect(http).to have_received(:use_ssl=).with(true)
      expect(request).to have_received(:[]=).with("Authorization", "Bearer #{api_key}")
      expect(request).to have_received(:[]=).with("Content-Type", "application/json")
      expect(request).to have_received(:body=).with(params.to_json)
      expect(result).to eq({ "success" => true })
    end

    it "handles network errors gracefully" do
      allow(http).to receive(:request).and_raise(Net::ReadTimeout.new("Connection timeout"))

      params = { model: "sonar", messages: [] }
      result = tool.send(:make_request, params)

      expect(result).to eq({ "error" => "Connection timeout" })
    end
  end

  describe "Core module integration" do
    it "uses RAAF::Perplexity::Common for validation" do
      expect(RAAF::Perplexity::Common).to receive(:validate_model).with("sonar-pro")

      described_class.new(model: "sonar-pro")
    end

    it "uses RAAF::Perplexity::SearchOptions for building options" do
      expect(RAAF::Perplexity::SearchOptions).to receive(:build).with(
        domain_filter: ["example.com"],
        recency_filter: "week"
      ).and_return({ search_domain_filter: ["example.com"], search_recency_filter: "week" })

      tool = described_class.new
      allow(tool).to receive(:make_request).and_return({})

      tool.call(
        query: "test",
        search_domain_filter: ["example.com"],
        search_recency_filter: "week"
      )
    end

    it "uses RAAF::Perplexity::ResultParser for formatting" do
      api_response = { "choices" => [{ "message" => { "content" => "result" } }] }

      expect(RAAF::Perplexity::ResultParser).to receive(:format_search_result)
        .with(api_response)
        .and_return({ success: true, content: "result" })

      tool = described_class.new
      allow(tool).to receive(:make_request).and_return(api_response)

      result = tool.call(query: "test")
      expect(result[:success]).to be true
    end
  end
end
```

### Integration Test Example
```ruby
RSpec.describe "PerplexitySearch Integration", type: :integration do
  let(:tool) { RAAF::DSL::Tools::PerplexitySearch.new }

  before do
    ENV["PERPLEXITY_API_KEY"] = "test-key"
  end

  describe "end-to-end search" do
    it "performs search with all parameters" do
      VCR.use_cassette("perplexity_search_full") do
        result = tool.call(
          query: "Ruby programming language features",
          model: "sonar-pro",
          search_domain_filter: ["ruby-lang.org", "github.com"],
          search_recency_filter: "month",
          max_tokens: 500
        )

        expect(result[:success]).to be true
        expect(result[:content]).to include("Ruby")
        expect(result[:citations]).to be_an(Array)
        expect(result[:web_results]).to be_an(Array)
        expect(result[:query]).to eq("Ruby programming language features")
      end
    end
  end

  describe "error handling" do
    it "handles invalid API key gracefully" do
      ENV["PERPLEXITY_API_KEY"] = "invalid-key"

      VCR.use_cassette("perplexity_invalid_key") do
        result = tool.call(query: "test")

        expect(result[:success]).to be false
        expect(result[:error]).to include("unauthorized")
      end
    end
  end
end
```

### Backward Compatibility Test Example
```ruby
RSpec.describe "PerplexitySearch Backward Compatibility" do
  let(:old_tool) { OldPerplexitySearchImplementation.new }  # Preserved old version
  let(:new_tool) { RAAF::DSL::Tools::PerplexitySearch.new }

  before do
    ENV["PERPLEXITY_API_KEY"] = "test-key"

    # Mock both to return same response
    allow(old_tool).to receive(:call).and_return(sample_response)
    allow(new_tool).to receive(:make_request).and_return(sample_api_response)
  end

  it "maintains same public interface" do
    old_methods = old_tool.public_methods(false).sort
    new_methods = new_tool.public_methods(false).sort

    expect(new_methods).to eq(old_methods)
  end

  it "accepts same parameters" do
    params = {
      query: "test",
      model: "sonar",
      search_domain_filter: ["example.com"],
      search_recency_filter: "week",
      max_tokens: 100
    }

    expect { old_tool.call(**params) }.not_to raise_error
    expect { new_tool.call(**params) }.not_to raise_error
  end

  it "returns same result structure" do
    old_result = old_tool.call(query: "test")
    new_result = new_tool.call(query: "test")

    expect(new_result.keys).to match_array(old_result.keys)
    expect(new_result[:success]).to eq(old_result[:success])
    expect(new_result[:content]).to eq(old_result[:content])
    expect(new_result[:citations]).to eq(old_result[:citations])
    expect(new_result[:web_results]).to eq(old_result[:web_results])
  end
end
```

## Test Execution Plan

### Phase 1: Unit Tests
1. Write tests for initialization and validation
2. Write tests for HTTP request building
3. Write tests for Core module integration
4. Write tests for response formatting
5. Achieve 100% code coverage

### Phase 2: Integration Tests
1. Set up VCR for API recording
2. Record successful API calls
3. Record error scenarios
4. Test all parameter combinations
5. Verify Core module behavior

### Phase 3: Compatibility Tests
1. Preserve current implementation as reference
2. Run parallel tests on both implementations
3. Compare outputs for identical inputs
4. Verify interface compatibility
5. Document any minor differences

### Phase 4: Performance Tests
1. Measure response times
2. Test timeout behavior
3. Test concurrent requests
4. Compare with old implementation
5. Ensure no performance regression

## Coverage Requirements

### Code Coverage Goals
- Unit test coverage: 100%
- Integration test coverage: 90%
- Overall coverage: 95%

### Critical Path Coverage
- HTTP request/response: 100%
- Error handling: 100%
- Core module integration: 100%
- Public API methods: 100%

### Edge Cases to Test
- Empty query string
- Very long query (>1000 chars)
- Special characters in query
- Empty search results
- Partial API responses
- Malformed JSON responses
- Network interruptions
- Concurrent requests
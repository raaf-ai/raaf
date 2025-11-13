# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-11-13-ollama-provider/spec.md

> Created: 2025-11-13
> Version: 1.0.0

## Test Coverage

### Unit Tests

**RAAF::Models::OllamaProvider**
- Provider initialization with default host (localhost:11434)
- Provider initialization with custom host
- Provider initialization with custom timeout
- Provider initialization with environment variable `OLLAMA_HOST`
- `perform_chat_completion` with basic message
- `perform_chat_completion` with tools parameter
- `perform_chat_completion` with optional parameters (temperature, top_p, max_tokens)
- `perform_stream_completion` with block yielding chunks
- `supported_models` returns empty array (Ollama is extensible)
- `provider_name` returns "Ollama"
- Tool format conversion from RAAF to Ollama format
- Tool call parsing from Ollama response to OpenAI format
- Response parsing and format conversion

**Error Handling**
- Connection refused error (Ollama not running)
- Model not found error (HTTP 404)
- Timeout error (slow model loading)
- Invalid JSON response handling
- HTTP error codes (400, 500, 503)

### Integration Tests

**Live Ollama Integration** (requires `OLLAMA_INTEGRATION_TESTS=true`)
- Successful chat completion with llama3.2 model
- Streaming response with llama3.2 model
- Function calling with llama3.2 model
- Multi-turn conversation maintaining context
- Temperature and max_tokens parameter effects
- Model not installed error scenario

**Runner Integration**
- RAAF::Runner with OllamaProvider performs chat completion
- RAAF::Runner with OllamaProvider streams responses
- RAAF::Runner with OllamaProvider handles tool calls
- Agent handoffs work with tool-calling models

**DSL Integration**
- DSL agent with `provider :ollama` auto-instantiates provider
- DSL agent with custom provider_options (host, timeout)
- DSL agent schema validation with Ollama responses
- DSL agent tool usage with Ollama

### Feature Tests

**End-to-End Workflows**
- Local development workflow: Define agent, add tools, run locally
- Multi-agent workflow: Research agent hands off to writer agent locally
- Streaming conversation: Progressive response rendering
- Tool chaining: Agent calls multiple tools in sequence

### Mocking Requirements

- **HTTP Responses**: Mock Net::HTTP for unit tests using WebMock or VCR
- **Ollama API Responses**:
  - Chat completion response format
  - Streaming response format (newline-delimited JSON)
  - Tool call response format
  - Error response formats (404, 500, connection refused)
- **Model Loading Delays**: Simulate first-request model loading time
- **Streaming Chunks**: Mock progressive token streaming

## Test Data Fixtures

### Sample Ollama Chat Response

```json
{
  "model": "llama3.2",
  "created_at": "2025-11-13T10:00:00Z",
  "message": {
    "role": "assistant",
    "content": "Hello! How can I help you today?"
  },
  "done": true,
  "done_reason": "stop",
  "total_duration": 5000000000,
  "load_duration": 2000000000,
  "prompt_eval_count": 10,
  "eval_count": 15
}
```

### Sample Ollama Tool Call Response

```json
{
  "model": "llama3.2",
  "message": {
    "role": "assistant",
    "content": "",
    "tool_calls": [
      {
        "function": {
          "name": "get_weather",
          "arguments": "{\"location\": \"Tokyo\"}"
        }
      }
    ]
  },
  "done": true,
  "done_reason": "stop"
}
```

### Sample Streaming Response

```
{"model":"llama3.2","created_at":"2025-11-13T10:00:00Z","message":{"role":"assistant","content":"Hello"},"done":false}
{"model":"llama3.2","created_at":"2025-11-13T10:00:01Z","message":{"role":"assistant","content":"!"},"done":false}
{"model":"llama3.2","created_at":"2025-11-13T10:00:02Z","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}
```

## CI/CD Configuration

### GitHub Actions Example

```yaml
name: OllamaProvider Tests

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.3
          bundler-cache: true
      - name: Run unit tests
        run: |
          cd providers
          bundle exec rspec spec/raaf/ollama_provider_spec.rb

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install Ollama
        run: |
          curl -fsSL https://ollama.com/install.sh | sh
          ollama serve &
          sleep 5
          ollama pull llama3.2
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.3
          bundler-cache: true
      - name: Run integration tests
        env:
          OLLAMA_INTEGRATION_TESTS: true
        run: |
          cd providers
          bundle exec rspec spec/integration/ollama_integration_spec.rb
```

### Local Testing Commands

```bash
# Run unit tests only (no Ollama required)
cd providers
bundle exec rspec spec/raaf/ollama_provider_spec.rb

# Run integration tests (requires Ollama running)
ollama serve &  # Start Ollama in background
ollama pull llama3.2  # Pull test model
OLLAMA_INTEGRATION_TESTS=true bundle exec rspec spec/integration/ollama_integration_spec.rb

# Run all provider tests
bundle exec rspec
```

## Test Organization

```
providers/
└── spec/
    ├── raaf/
    │   └── ollama_provider_spec.rb          # Unit tests
    ├── integration/
    │   └── ollama_integration_spec.rb       # Integration tests (requires Ollama)
    ├── fixtures/
    │   ├── ollama_chat_response.json        # Sample API responses
    │   ├── ollama_tool_call_response.json
    │   └── ollama_streaming_response.txt
    └── support/
        ├── ollama_helpers.rb                # Test helpers
        └── webmock_stubs.rb                 # HTTP mocking
```

## Coverage Goals

- **Unit Test Coverage**: 100% of OllamaProvider class
- **Integration Test Coverage**: Core workflows (chat, stream, tools)
- **Error Handling Coverage**: All error scenarios tested
- **DSL Integration Coverage**: All provider DSL methods tested

## Manual Testing Scenarios

1. **First-Time Setup**: Install Ollama, pull model, run agent
2. **Model Switching**: Change model in agent configuration, verify behavior
3. **Performance Testing**: Measure CPU vs GPU inference times
4. **Memory Monitoring**: Verify model loading/unloading behavior
5. **Tool Calling Verification**: Test complex multi-tool workflows locally


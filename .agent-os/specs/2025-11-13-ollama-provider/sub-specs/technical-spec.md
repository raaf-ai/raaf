# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-11-13-ollama-provider/spec.md

> Created: 2025-11-13
> Version: 1.0.0

## Technical Requirements

### Provider Interface Compliance

- Inherit from `RAAF::Models::ModelInterface` (defined in raaf-core)
- Implement `perform_chat_completion(messages:, model:, tools:, stream:, **kwargs)` method
- Implement `perform_stream_completion(messages:, model:, tools:, **kwargs, &block)` method
- Implement `supported_models` method returning array of model names
- Implement `provider_name` method returning "Ollama"
- Support standard parameters: temperature, top_p, max_tokens, stop sequences

### Environment Variable Priority

**Priority Order:** Explicit parameter → Environment variable → Default value

- **Host Configuration**: `host:` parameter → `OLLAMA_HOST` → `http://localhost:11434`
- **Timeout Configuration**: `timeout:` parameter → `RAAF_OLLAMA_TIMEOUT` → `120` seconds

Example:
```ruby
# Uses explicit parameter (highest priority)
provider = OllamaProvider.new(host: "http://192.168.1.100:11434", timeout: 300)

# Uses environment variables
# ENV['OLLAMA_HOST'] = "http://server:11434"
# ENV['RAAF_OLLAMA_TIMEOUT'] = "180"
provider = OllamaProvider.new  # Uses env vars

# Uses defaults (no params, no env vars)
provider = OllamaProvider.new  # localhost:11434, 120s timeout
```

### HTTP Communication

- Use Net::HTTP for API communication (consistent with GroqProvider pattern)
- Default endpoint: `http://localhost:11434/api/chat` (Ollama's default port)
- Support custom host configuration via initialization parameter
- POST requests with JSON payload and streaming response handling
- No API key required (Ollama is local, no authentication)

### Response Format and Metadata

**Ollama-Specific Metadata Handling:**
- Preserve Ollama's extra fields (`total_duration`, `load_duration`, `eval_count`, `prompt_eval_count`) in the `usage` object
- Include alongside standard token counts for OpenAI compatibility
- Example response structure:
  ```ruby
  {
    content: "response text",
    usage: {
      prompt_tokens: 10,
      completion_tokens: 15,
      total_tokens: 25,
      # Ollama-specific fields
      total_duration: 5000000000,  # nanoseconds
      load_duration: 2000000000,
      prompt_eval_count: 10,
      eval_count: 15
    },
    model: "llama3.2",
    finish_reason: "stop"
  }
  ```

### Model Loading Behavior

**First Request Handling:**
- Log model loading with `log_info` (visible by default)
- Example: `"Loading model llama3.2 (may take 5-10 seconds)..."`
- Provide user feedback during the initial loading delay
- Extended timeout (120s default) accommodates model loading

### Tool Calling Implementation

**Compatibility:**
- Pass tools to Ollama and let it handle compatibility
- Ollama will return appropriate errors for non-compatible models
- No runtime detection of tool calling capabilities

**Format Conversion:**
- Convert RAAF tool format to Ollama function calling format
- Ollama format:
  ```json
  {
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get weather for a location",
          "parameters": {
            "type": "object",
            "properties": {
              "location": {"type": "string"}
            },
            "required": ["location"]
          }
        }
      }
    ]
  }
  ```
- Parse tool call responses from Ollama format:
  ```json
  {
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
    }
  }
  ```
- Map to OpenAI-compatible format for RAAF core consistency

### Streaming Support

**Chunk Handling:**
- Handle streaming responses using chunked transfer encoding
- Parse newline-delimited JSON chunks (Ollama streams each token as JSON)
- Yield chunks in format: `{ type: "content", content: "token" }`
- Yield final chunk: `{ type: "done", content: accumulated_content }`

**Tool Calls in Streaming:**
- Yield progressive chunks of tool calls as they arrive
- Follow GroqProvider pattern:
  ```ruby
  yield({
    type: "tool_calls",
    tool_calls: new_chunk,                    # Current chunk
    accumulated_tool_calls: all_tool_calls    # Complete accumulation
  })
  ```
- Accumulate tool call JSON and provide both incremental and complete data

### Model Validation

- Support all Ollama-compatible models (no hardcoded list - Ollama is extensible)
- Log warnings for models not explicitly verified with RAAF
- Verified models (initial list):
  - `llama3.2` (3B parameter, function calling)
  - `llama3.2:70b` (70B parameter, advanced function calling)
  - `mistral` (7B parameter, function calling)
  - `codellama` (7B/13B/34B parameter variants)
  - `gemma2` (2B/9B parameter variants)
- Provide clear error messages when Ollama server is unreachable or model not found

### Error Handling

- **Connection Errors**: `Errno::ECONNREFUSED` → `ConnectionError` with helpful message: "Ollama not running. Start with: ollama serve"
- **Model Not Found**: HTTP 404 → `ModelNotFoundError` with simple message: "Model not found. Pull with: ollama pull <model>"
- **Model Loading**: Log with `log_info` on first request: "Loading model {model} (may take 5-10 seconds)..."
- **Rate Limiting**: Not applicable for local Ollama (no rate limits)
- **Timeout Handling**: Default 120 second timeout (models can be slow on CPU), configurable via `RAAF_OLLAMA_TIMEOUT`

## Approach Options

### Option A: Use Faraday HTTP Client (Rejected)

- **Pros**: Consistent with some existing providers, middleware support, connection pooling
- **Cons**: Additional dependency, heavier than needed, RAAF is moving away from Faraday
- **Rationale for Rejection**: Recent providers (GroqProvider, Perplexity Provider) use Net::HTTP directly. Adding Faraday goes against the trend of reducing dependencies.

### Option B: Use Net::HTTP (Selected)

- **Pros**: Standard library, no additional dependencies, consistent with recent provider implementations
- **Cons**: Slightly more verbose than HTTP client gems, manual request building
- **Rationale for Selection**: Matches GroqProvider pattern exactly, no new dependencies, follows RAAF's recent architectural direction

### Option C: Use Custom HTTP Wrapper

- **Pros**: Tailored interface, could abstract Ollama-specific logic
- **Cons**: More code to maintain, reinventing standard library functionality
- **Rationale for Rejection**: Unnecessary abstraction for straightforward HTTP communication

**Selected Approach: Option B (Net::HTTP)**

Reasoning: Consistency with recent providers (GroqProvider), zero additional dependencies, sufficient for Ollama's straightforward API, and aligns with RAAF's direction of using standard library where possible.

## Implementation Pattern

Follow GroqProvider and HuggingFaceProvider as reference implementations:

```ruby
module RAAF
  module Models
    class OllamaProvider < ModelInterface
      include RAAF::Logger

      API_DEFAULT_HOST = "http://localhost:11434"
      DEFAULT_TIMEOUT = 120

      def initialize(host: nil, timeout: nil, **options)
        super
        @host = host || ENV["OLLAMA_HOST"] || API_DEFAULT_HOST
        @http_timeout = timeout || ENV.fetch("RAAF_OLLAMA_TIMEOUT", DEFAULT_TIMEOUT.to_s).to_i
      end

      def perform_chat_completion(messages:, model:, tools: nil, stream: false, **kwargs)
        # Build request body in Ollama format
        body = {
          model: model,
          messages: messages,
          stream: stream
        }

        # Add tools if provided
        body[:tools] = prepare_tools(tools) if tools && !tools.empty?

        # Add optional parameters
        body[:options] = build_options(kwargs)

        if stream
          stream_response(body, &block)
        else
          make_request(body)
        end
      end

      private

      def make_request(body)
        uri = URI("#{@host}/api/chat")
        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = @timeout

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = body.to_json

        response = http.request(request)

        handle_api_error(response) unless response.code.start_with?("2")

        parse_response(response.body)
      rescue Errno::ECONNREFUSED
        raise ConnectionError, "Ollama not running. Start with: ollama serve"
      end

      def prepare_tools(tools)
        # Convert RAAF tools to Ollama format
        tools.map do |tool|
          {
            type: "function",
            function: {
              name: tool[:name],
              description: tool[:description],
              parameters: tool[:parameters]
            }
          }
        end
      end

      def parse_response(body)
        # Parse Ollama response and convert to OpenAI format
        ollama_response = JSON.parse(body)

        {
          content: ollama_response.dig("message", "content"),
          tool_calls: parse_tool_calls(ollama_response),
          model: ollama_response["model"],
          finish_reason: map_finish_reason(ollama_response["done_reason"]),
          usage: {
            prompt_tokens: ollama_response["prompt_eval_count"],
            completion_tokens: ollama_response["eval_count"],
            total_tokens: (ollama_response["prompt_eval_count"] || 0) + (ollama_response["eval_count"] || 0),
            # Ollama-specific metadata
            total_duration: ollama_response["total_duration"],
            load_duration: ollama_response["load_duration"],
            prompt_eval_count: ollama_response["prompt_eval_count"],
            eval_count: ollama_response["eval_count"]
          }
        }
      end
    end
  end
end
```

## External Dependencies

**None** - Uses Ruby standard library only:
- `net/http` - HTTP client (standard library)
- `json` - JSON parsing (standard library)
- `uri` - URL parsing (standard library)

**Rationale**: Ollama provider should be zero-dependency to align with RAAF's direction and because the HTTP API is simple enough not to require specialized gems.

## Configuration Examples

```ruby
# Default configuration (localhost, 120s timeout)
ollama_provider = RAAF::Models::OllamaProvider.new

# Custom host
ollama_provider = RAAF::Models::OllamaProvider.new(
  host: "http://192.168.1.100:11434"
)

# Custom timeout (for slower hardware)
ollama_provider = RAAF::Models::OllamaProvider.new(
  timeout: 300  # 5 minutes
)

# Environment variable configuration
# OLLAMA_HOST=http://server:11434
# RAAF_OLLAMA_TIMEOUT=180
ollama_provider = RAAF::Models::OllamaProvider.new  # Uses env vars

# DSL integration
class LocalAgent < RAAF::DSL::Agent
  instructions "You are a local assistant"
  model "llama3.2"
  provider :ollama

  # Optional: custom host for DSL
  provider_options(
    host: "http://server:11434",
    timeout: 180
  )
end
```

## Performance Characteristics

- **Latency**: 100ms - 10 seconds depending on hardware (CPU vs GPU)
- **First Request**: 5-10 seconds (model loading into RAM/VRAM)
- **Subsequent Requests**: Near-instant (model stays loaded)
- **Memory Usage**: 2-70GB depending on model size
- **Throughput**: 10-50 tokens/second on CPU, 50-200 tokens/second on GPU

## Compatibility Matrix

| Feature | Support | Notes |
|---------|---------|-------|
| Chat Completion | ✅ Full | All models |
| Streaming | ✅ Full | All models |
| Tool Calling | ⚠️ Partial | Llama 3.2+, Mistral (Ollama handles compatibility) |
| Multi-Agent Handoffs | ⚠️ Limited | Source agent must support tool calling |
| JSON Mode | ✅ Full | Via Ollama's format parameter |
| Vision | ❌ Deferred | Llama 3.2 Vision support in future enhancement |
| Embeddings | ❌ Future | Separate endpoint/feature |

## Testing Strategy

1. **Unit Tests**: Mock HTTP responses, test response parsing
2. **Integration Tests**: Require Ollama running locally (conditional via CI environment variable)
3. **Tool Calling Tests**: Verify function call format conversion
4. **Streaming Tests**: Test chunk accumulation and callback handling
5. **Error Handling Tests**: Connection refused, model not found, timeout scenarios


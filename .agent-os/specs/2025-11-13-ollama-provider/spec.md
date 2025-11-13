# Spec Requirements Document

> Spec: Ollama Provider
> Created: 2025-11-13
> Status: Ready for Implementation
> Version: 2.0.0

## Overview

Implement an OllamaProvider for RAAF that enables local LLM usage through Ollama's API. This provider will support developers who want to run AI agents locally without external API dependencies, reducing costs and enabling offline development while maintaining full compatibility with RAAF's provider interface and multi-agent orchestration capabilities.

**Key Benefits:**
- Zero API costs for development and testing
- Complete offline operation capability
- Privacy-preserving local inference for sensitive data
- Full RAAF feature compatibility (streaming, tools, handoffs)
- Seamless transition path from local development to production providers

## User Stories

### Local Development Workflow

As a RAAF developer, I want to run AI agents locally using Ollama, so that I can develop and test agents offline without incurring API costs or depending on external services.

**Workflow:**
1. Developer installs Ollama: `brew install ollama` (macOS) or via install script
2. Pulls desired model: `ollama pull llama3.2` (3B parameter, function calling support)
3. Configures RAAF agent with `provider: :ollama` in DSL or `OllamaProvider.new` directly
4. Runs agents locally with full RAAF capabilities (tools, streaming, handoffs)
5. Provider handles communication with local Ollama instance automatically
6. All operations work offline without internet connectivity or API keys

**Acceptance Criteria:**
- Developer can initialize OllamaProvider and connect to local Ollama (localhost:11434)
- Agent successfully completes chat interactions with local models
- Streaming responses work with progressive token rendering
- Tool calling works on compatible models (Llama 3.2+, Mistral)
- Clear error messages guide troubleshooting (Ollama not running, model not found)

### Cost-Effective Testing

As a RAAF user, I want to test agent configurations locally before deploying with commercial providers, so that I can iterate quickly without accumulating API charges during development.

**Workflow:**
1. User develops prompts and agent logic using local Llama/Mistral models
2. Tests tool calling, multi-agent handoffs, and complex workflows locally
3. Validates behavior and outputs with zero API costs
4. Switches to production providers (OpenAI, Anthropic) by changing `provider` configuration
5. OllamaProvider provides identical interface to other providers, making transition seamless

**Acceptance Criteria:**
- Can develop and test complete multi-agent systems locally
- Provider interface matches other RAAF providers (OpenAI, Anthropic, etc.)
- Configuration change from `:ollama` to `:openai` requires no code changes beyond provider setting
- Local testing catches logic errors before production deployment
- Token usage and cost tracking work locally (even though costs are zero)

### Privacy-Sensitive Applications

As an enterprise developer, I want to process sensitive data with local LLMs, so that confidential information never leaves our infrastructure while still benefiting from AI agent capabilities.

**Workflow:**
1. Developer deploys Ollama on internal servers (corporate network, on-premise)
2. Configures RAAF agents to use OllamaProvider with custom endpoint: `host: "http://server:11434"`
3. Processes sensitive customer data, financial records, or proprietary information
4. All data remains within organization's infrastructure (GDPR, HIPAA, SOC2 compliance)
5. Maintains full RAAF functionality for orchestration, tool usage, and multi-agent workflows

**Acceptance Criteria:**
- Can configure custom Ollama host (not just localhost)
- All communication stays within specified network boundary
- No external API calls or data transmission
- Full RAAF agent capabilities available (tools, handoffs, streaming)
- Documentation includes enterprise deployment patterns

## Spec Scope

### Must-Have Features (MVP)

1. **Core Provider Implementation**
   - Complete OllamaProvider class inheriting from `RAAF::Models::ModelInterface`
   - Non-streaming chat completion support
   - Streaming response support with progressive token rendering
   - Response format conversion from Ollama to OpenAI-compatible structure

2. **Model Management**
   - Support for all Ollama-compatible models (no hardcoded list)
   - Validation and clear error handling for missing models
   - Initial verified model list: llama3.2, llama3.2:70b, mistral, codellama, gemma2

3. **Tool Calling Support**
   - Implement function calling using Ollama's tool format
   - Format conversion from RAAF tools to Ollama function calling format
   - Response parsing from Ollama tool calls to OpenAI-compatible format
   - Compatibility handling (pass tools to Ollama, let it handle model compatibility)

4. **DSL Integration**
   - Automatic provider detection using `:ollama` symbol in DSL agents
   - Provider instantiation via `provider :ollama` declaration
   - Support for `provider_options` DSL for custom host/timeout configuration

5. **Configuration Options**
   - Custom Ollama host configuration (default: `http://localhost:11434`)
   - Timeout configuration (default: 120 seconds for model loading)
   - Environment variable support: `OLLAMA_HOST`, `RAAF_OLLAMA_TIMEOUT`
   - Priority: Explicit parameter → Environment variable → Default value

6. **Error Handling**
   - Connection refused error with actionable message: "Ollama not running. Start with: ollama serve"
   - Model not found error with actionable message: "Model not found. Pull with: ollama pull <model>"
   - Timeout handling for slow model loading (configurable, default 120s)
   - HTTP error code handling (400, 500, 503)

7. **Response Metadata**
   - Standard OpenAI-compatible fields (content, usage, model, finish_reason)
   - Ollama-specific metrics preserved in usage object (total_duration, load_duration, eval_count)
   - Token usage tracking (prompt_tokens, completion_tokens, total_tokens)

8. **Model Loading Feedback**
   - Log model loading progress using `log_info` (visible by default)
   - Example: "Loading model llama3.2 (may take 5-10 seconds)..."
   - Extended timeout to accommodate initial model loading (120s default)

### Should-Have Features (Future Enhancements)

- Vision model support (Llama 3.2 Vision, LLaVA models)
- Embedding generation via Ollama's separate endpoint
- Automatic model recommendation based on task requirements
- Model performance benchmarking and hardware capability detection
- Advanced streaming features (token probability scores, alternative completions)

## Out of Scope

**The following are explicitly excluded from this implementation:**

- Ollama installation automation or system setup
- Model downloading or version management (Ollama CLI handles this)
- GPU acceleration configuration (handled by Ollama installation)
- Model fine-tuning or training capabilities
- Embedding generation (separate feature, different endpoint)
- Runtime detection of tool calling capabilities (Ollama handles compatibility)
- Automatic model downloading when not found
- Model recommendation engine or model selection AI
- Performance optimization beyond basic timeout configuration
- Ollama server management or lifecycle control

## Technical Decisions

### 1. HTTP Client: Net::HTTP (Standard Library)

**Decision:** Use Net::HTTP instead of Faraday or custom HTTP wrapper

**Rationale:**
- Consistent with recent RAAF providers (GroqProvider, PerplexityProvider)
- Zero additional dependencies
- Sufficient for Ollama's straightforward HTTP API
- Aligns with RAAF's direction of using standard library where possible

**Trade-offs:**
- Slightly more verbose than HTTP client gems
- Manual request building required
- No built-in middleware support
- ✅ Accepted: Simplicity and zero dependencies outweigh convenience features

### 2. Tool Calling Compatibility: Delegate to Ollama

**Decision:** Pass tools to Ollama and let it handle compatibility errors

**Rationale:**
- Ollama itself knows which models support tool calling
- Avoids maintaining hardcoded list of tool-capable models
- Simpler implementation (no runtime detection)
- Ollama provides appropriate error messages for incompatible models

**Implementation:** No runtime capability detection, pass tools through and handle Ollama errors gracefully

### 3. Streaming Tool Calls: Progressive Chunks

**Decision:** Yield progressive chunks as they arrive with both incremental and accumulated data

**Rationale:**
- Follows existing RAAF pattern (GroqProvider)
- Provides flexibility for consumers (incremental updates vs full state)
- Consistent with how RAAF handles streaming across all providers

**Format:**
```ruby
yield({
  type: "tool_calls",
  tool_calls: new_chunk,                    # Current chunk
  accumulated_tool_calls: all_tool_calls    # Complete accumulation
})
```

### 4. Response Metadata: Preserve Ollama-Specific Fields

**Decision:** Place Ollama metrics in `usage` object alongside standard token counts

**Rationale:**
- Ollama provides valuable metrics (total_duration, load_duration, eval_count)
- Maintains OpenAI compatibility (standard fields at response root)
- Keeps response structure clean while preserving provider-specific data
- Users can access Ollama metrics if needed for performance analysis

**Response Structure:**
```ruby
{
  content: "response text",
  usage: {
    prompt_tokens: 10,
    completion_tokens: 15,
    total_tokens: 25,
    # Ollama-specific fields
    total_duration: 5000000000,  # nanoseconds
    load_duration: 2000000000,   # nanoseconds
    prompt_eval_count: 10,
    eval_count: 15
  },
  model: "llama3.2",
  finish_reason: "stop"
}
```

### 5. Environment Variable Configuration

**Decision:** Standard RAAF priority: Explicit parameter → Environment variable → Default value

**Configuration Variables:**
- **Host**: `host:` param → `OLLAMA_HOST` → `http://localhost:11434`
- **Timeout**: `timeout:` param → `RAAF_OLLAMA_TIMEOUT` → `120` seconds

**Rationale:**
- Follows HuggingFaceProvider pattern
- Explicit parameters for fine-grained control
- Environment variables for deployment configuration
- Sensible defaults for local development

### 6. Model Loading Logging

**Decision:** Log model loading using `log_info` (visible by default)

**Rationale:**
- First request can take 5-10 seconds (model loads into memory)
- Users need feedback about the delay
- `log_info` visible by default (unlike `log_debug`)
- Not a warning/error, just informational progress

**Implementation:**
```ruby
log_info("Loading model #{model} (may take 5-10 seconds)...",
         provider: "OllamaProvider", model: model)
```

### 7. Multi-Agent Handoffs: Source Agent Requirements

**Decision:** Handoffs only work if source agent's model supports tool calling

**Rationale:**
- RAAF handoffs implemented as tool calls (transfer_to_* functions)
- Source agent must be able to invoke tools to initiate handoff
- Target agent doesn't need tool calling (receives control via Runner)

**Compatibility:**
- Tool Calling: ⚠️ Partial (Llama 3.2+, Mistral - Ollama handles compatibility)
- Multi-Agent Handoffs: ⚠️ Limited (Source agent must support tool calling)

### 8. Vision Support: Future Enhancement

**Decision:** Defer vision support to future implementation

**Rationale:**
- Focus MVP on core functionality (chat, streaming, tools)
- Vision requires additional image handling complexity
- Llama 3.2 Vision and LLaVA models available but not in scope
- Can be added as follow-up feature once core provider stable

### 9. Error Messages: Simple and Actionable

**Decision:** Provide clear, actionable error messages with specific commands

**Rationale:**
- Users need immediate guidance for common issues
- Suggesting specific commands (`ollama serve`, `ollama pull <model>`) accelerates problem resolution
- Parsing Ollama error details adds complexity without significant benefit

**Error Messages:**
- Connection refused: "Ollama not running. Start with: ollama serve"
- Model not found: "Model not found. Pull with: ollama pull <model>"

## Expected Deliverables

### 1. Working OllamaProvider

**Acceptance Criteria:**
- Developer can instantiate `RAAF::Models::OllamaProvider`
- Provider connects to local Ollama instance (default: localhost:11434)
- Successfully completes chat interactions with local models
- Returns responses in OpenAI-compatible format
- Handles connection errors gracefully with actionable messages

### 2. Tool Calling Support

**Acceptance Criteria:**
- Agents using OllamaProvider can define and use tools
- Tool format correctly converted from RAAF to Ollama function calling format
- Tool call responses parsed from Ollama to OpenAI-compatible format
- Verified working with Llama 3.2 (3B and 70B variants)
- Verified working with Mistral models
- Clear error messages for models without tool calling support

### 3. Streaming Support

**Acceptance Criteria:**
- Provider supports streaming responses with `stream: true`
- Progressive token rendering works correctly
- Streaming tool calls yield both incremental and accumulated data
- Stream chunks follow RAAF format (`type`, `content`, `accumulated_content`)
- Final chunk includes complete response with metadata

### 4. DSL Integration

**Acceptance Criteria:**
- Developer can use `provider :ollama` in RAAF::DSL::Agent
- Provider automatically instantiated with default configuration
- `provider_options` DSL method supports host and timeout configuration
- Automatic provider detection from `:ollama` symbol
- Seamless integration with existing DSL patterns

### 5. Comprehensive Test Suite

**Acceptance Criteria:**
- 100% unit test coverage of OllamaProvider class
- Unit tests mock HTTP responses (no Ollama required)
- Integration tests cover real Ollama interactions (conditional via env var)
- Tool calling tests verify format conversion
- Streaming tests validate chunk accumulation
- Error handling tests cover all error scenarios
- DSL integration tests verify automatic provider instantiation

### 6. Complete Documentation

**Acceptance Criteria:**
- Provider documented in `providers/CLAUDE.md`
- Usage examples for basic chat, streaming, and tool calling
- Configuration examples (default, custom host, environment variables)
- Supported models list with tool calling capabilities
- Performance characteristics documented (CPU vs GPU, model loading times)
- Troubleshooting guide for common issues
- Enterprise deployment patterns documented

## Implementation Approach

### Provider Class Structure

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
        # Implementation
      end

      def perform_stream_completion(messages:, model:, tools: nil, **kwargs, &block)
        # Implementation
      end

      def supported_models
        [] # Ollama is extensible, no hardcoded list
      end

      def provider_name
        "Ollama"
      end

      private

      def prepare_tools(tools)
        # Convert RAAF tools to Ollama format
      end

      def parse_response(body)
        # Parse Ollama response to OpenAI format
      end

      def parse_tool_calls(response)
        # Parse Ollama tool calls to OpenAI format
      end
    end
  end
end
```

### Reference Implementations

**Follow these RAAF providers as patterns:**

1. **GroqProvider** - Streaming tool calls, Net::HTTP usage, response parsing
2. **HuggingFaceProvider** - Environment variable priority, timeout configuration, RAAF::Logger integration
3. **TogetherProvider** - OpenAI-compatible API handling

### Configuration Examples

```ruby
# Default configuration (localhost, 120s timeout)
provider = RAAF::Models::OllamaProvider.new

# Custom host
provider = RAAF::Models::OllamaProvider.new(
  host: "http://192.168.1.100:11434"
)

# Custom timeout (for slower hardware)
provider = RAAF::Models::OllamaProvider.new(timeout: 300)

# Environment variable configuration
# OLLAMA_HOST=http://server:11434
# RAAF_OLLAMA_TIMEOUT=180
provider = RAAF::Models::OllamaProvider.new  # Uses env vars

# DSL integration
class LocalAgent < RAAF::DSL::Agent
  instructions "You are a local assistant"
  model "llama3.2"
  provider :ollama

  # Optional: custom provider options
  provider_options host: "http://server:11434", timeout: 180
end
```

## Performance Characteristics

- **Latency**: 100ms - 10 seconds depending on hardware (CPU vs GPU)
- **First Request**: 5-10 seconds (model loading into RAM/VRAM)
- **Subsequent Requests**: Near-instant (model stays loaded in memory)
- **Memory Usage**: 2-70GB depending on model size
- **Throughput**: 10-50 tokens/second on CPU, 50-200 tokens/second on GPU
- **Concurrent Requests**: Limited by available RAM/VRAM

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

## Success Metrics

1. **Functional Success**: All test suite tests pass (100% unit, comprehensive integration)
2. **Developer Experience**: Clear documentation enables first-time setup in < 5 minutes
3. **Error Handling**: All error scenarios produce actionable guidance
4. **Performance**: First request completes within timeout (120s default)
5. **Compatibility**: Works with all documented Ollama-compatible models
6. **Integration**: DSL integration requires zero configuration beyond `provider :ollama`

## Spec Documentation

### Core Documentation
- **Main Spec**: @.agent-os/specs/2025-11-13-ollama-provider/spec.md (this document)
- **Tasks Breakdown**: @.agent-os/specs/2025-11-13-ollama-provider/tasks.md

### Technical Specifications
- **Technical Specification**: @.agent-os/specs/2025-11-13-ollama-provider/sub-specs/technical-spec.md
- **Tests Specification**: @.agent-os/specs/2025-11-13-ollama-provider/sub-specs/tests.md

### Requirements Documentation
- **Requirements & Decisions**: @.agent-os/specs/2025-11-13-ollama-provider/planning/requirements-decisions.md

## Next Steps

1. Review and approve this specification document
2. Proceed to implementation following tasks.md
3. Follow TDD approach (write tests first)
4. Reference GroqProvider and HuggingFaceProvider patterns
5. Validate with real Ollama instance during integration testing
6. Update providers/CLAUDE.md with complete documentation

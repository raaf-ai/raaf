# Requirements and Design Decisions

> Date: 2025-11-13
> Status: Finalized

## Overview

This document captures the key requirements and design decisions made during the spec shaping process for the OllamaProvider implementation.

## Design Decisions

### 1. Tool Calling Model Compatibility
**Decision:** Pass tools to Ollama and let it handle compatibility errors

**Rationale:**
- Ollama itself knows which models support tool calling
- Simpler implementation (no runtime detection needed)
- Ollama provides appropriate error messages for incompatible models
- Avoids maintaining a hardcoded list of tool-capable models

**Implementation:** No runtime detection, pass tools through and handle Ollama errors gracefully.

---

### 2. Streaming Tool Calls
**Decision:** Yield progressive chunks as they arrive

**Rationale:**
- Follows existing RAAF pattern (GroqProvider)
- Provides both incremental chunks and accumulated data
- Consistent with how RAAF handles streaming across all providers

**Implementation Pattern:**
```ruby
yield({
  type: "tool_calls",
  tool_calls: new_chunk,                    # Current chunk
  accumulated_tool_calls: all_tool_calls    # Complete accumulation
})
```

---

### 3. Model Loading Behavior
**Decision:** Log model loading progress using `log_info`

**Rationale:**
- First request can take 5-10 seconds (model loads into memory)
- Users need feedback about the delay
- `log_info` is visible by default (unlike `log_debug`)
- Not a warning/error, just informational

**Implementation:**
```ruby
log_info("Loading model #{model} (may take 5-10 seconds)...",
         provider: "OllamaProvider", model: model)
```

---

### 4. Response Format Mapping
**Decision:** Preserve Ollama-specific fields in the `usage` object

**Rationale:**
- Ollama provides valuable metrics (`total_duration`, `load_duration`, `eval_count`)
- Placing in `usage` keeps response structure clean
- Maintains OpenAI compatibility (standard fields at root)
- Users can access Ollama-specific metrics if needed

**Response Structure:**
```ruby
{
  content: "response text",
  usage: {
    prompt_tokens: 10,
    completion_tokens: 15,
    total_tokens: 25,
    # Ollama-specific fields
    total_duration: 5000000000,
    load_duration: 2000000000,
    prompt_eval_count: 10,
    eval_count: 15
  },
  model: "llama3.2",
  finish_reason: "stop"
}
```

---

### 5. Environment Variable Priority
**Decision:** Explicit parameter → Environment variable → Default value

**Rationale:**
- Standard pattern across RAAF providers (HuggingFaceProvider)
- Explicit parameters give developers fine-grained control
- Environment variables useful for deployment configuration
- Sensible defaults for local development

**Configuration:**
- `host`: `host:` param → `OLLAMA_HOST` → `http://localhost:11434`
- `timeout`: `timeout:` param → `RAAF_OLLAMA_TIMEOUT` → `120` seconds

**Timeout Variable:** `RAAF_OLLAMA_TIMEOUT` (namespaced under RAAF for consistency)

---

### 6. Multi-Agent Handoffs
**Decision:** Handoffs only work if source agent's model supports tool calling

**Rationale:**
- RAAF handoffs are implemented as tool calls (transfer_to_* functions)
- Source agent must be able to invoke tools to hand off
- Target agent doesn't need tool calling (receives control via Runner)

**Compatibility Matrix:**
- Tool Calling: ⚠️ Partial (Llama 3.2+, Mistral - Ollama handles compatibility)
- Multi-Agent Handoffs: ⚠️ Limited (Source agent must support tool calling)

---

### 7. Vision Model Support
**Decision:** Defer vision support to future enhancement

**Rationale:**
- Focus MVP on core functionality (chat, streaming, tools)
- Vision requires additional image handling complexity
- Llama 3.2 Vision and LLaVA models available but not yet in scope
- Can be added as follow-up feature once core provider is stable

**Compatibility Matrix:** Vision: ❌ Deferred (Future enhancement)

---

### 8. Error Message Specificity
**Decision:** Simple error messages with actionable commands

**Rationale:**
- Users need clear, actionable guidance
- Suggesting specific commands (`ollama serve`, `ollama pull`) helps quick resolution
- Parsing Ollama errors adds complexity without significant benefit

**Error Messages:**
- Connection refused: "Ollama not running. Start with: ollama serve"
- Model not found: "Model not found. Pull with: ollama pull <model>"

---

### 9. Reference Provider Patterns
**Decision:** Follow GroqProvider and HuggingFaceProvider patterns

**Reference Implementations:**
- **GroqProvider**: Streaming tool calls, Net::HTTP usage, response parsing
- **HuggingFaceProvider**: Environment variable priority, timeout configuration, RAAF::Logger integration
- **TogetherProvider**: OpenAI-compatible API handling

**Key Patterns Adopted:**
- Net::HTTP for zero-dependency communication
- RAAF::Logger mixin for consistent logging
- Standard env var precedence (param → env → default)
- Streaming chunk format with `type`, `content`, `accumulated_content`

---

## Implementation References

### Code Patterns

**Initialization (from HuggingFaceProvider):**
```ruby
def initialize(host: nil, timeout: nil, **options)
  super
  @host = host || ENV["OLLAMA_HOST"] || API_DEFAULT_HOST
  @http_timeout = timeout || ENV.fetch("RAAF_OLLAMA_TIMEOUT", DEFAULT_TIMEOUT.to_s).to_i
end
```

**Streaming Tool Calls (from GroqProvider):**
```ruby
if parsed.dig("choices", 0, "delta", "tool_calls")
  tool_calls = parsed["choices"][0]["delta"]["tool_calls"]
  accumulated_tool_calls.concat(tool_calls)

  if block_given?
    yield({
      type: "tool_calls",
      tool_calls: tool_calls,
      accumulated_tool_calls: accumulated_tool_calls
    })
  end
end
```

**Logging (from multiple providers):**
```ruby
include RAAF::Logger

log_info("Loading model #{model}...", provider: "OllamaProvider", model: model)
log_debug("Request body: #{body}", provider: "OllamaProvider")
```

---

## Visual Assets

**Status:** No visual assets provided

The implementation will follow existing RAAF provider patterns and Ollama API documentation without requiring additional visual references.

---

## Scope Confirmation

### In Scope (MVP)
- ✅ Core OllamaProvider class with ModelInterface compliance
- ✅ Chat completion (non-streaming)
- ✅ Streaming responses
- ✅ Tool calling support (Ollama handles compatibility)
- ✅ DSL integration (`:ollama` provider symbol)
- ✅ Environment variable configuration
- ✅ Comprehensive error handling
- ✅ Complete test suite (unit + integration)
- ✅ Documentation in providers/CLAUDE.md

### Out of Scope (Future Enhancements)
- ❌ Vision model support (Llama 3.2 Vision, LLaVA)
- ❌ Embedding generation (separate endpoint)
- ❌ Model management automation (Ollama CLI handles this)
- ❌ Runtime tool calling capability detection
- ❌ Automatic model downloading

---

## Success Criteria

1. **Functional:** Developer can run agents locally with Ollama without external API dependencies
2. **Tool Calling:** Function calling works on compatible models (Llama 3.2+, Mistral)
3. **Streaming:** Progressive response rendering with tool call support
4. **DSL Integration:** `provider :ollama` automatically instantiates provider
5. **Error Handling:** Clear, actionable error messages for common issues
6. **Testing:** 100% unit test coverage, comprehensive integration tests
7. **Documentation:** Complete provider documentation with examples

---

## Next Steps

1. **Proceed to Implementation:** Execute tasks.md following TDD approach
2. **Reference Files:**
   - Technical spec: @.agent-os/specs/2025-11-13-ollama-provider/sub-specs/technical-spec.md
   - Tests spec: @.agent-os/specs/2025-11-13-ollama-provider/sub-specs/tests.md
   - Tasks breakdown: @.agent-os/specs/2025-11-13-ollama-provider/tasks.md
3. **Follow Patterns:** GroqProvider (streaming), HuggingFaceProvider (config)


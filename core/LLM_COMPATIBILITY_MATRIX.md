# LLM Compatibility Matrix - RAAF Core

## 🎯 Overview
This matrix shows LLM compatibility with RAAF Core's tool-based handoff system. **IMPORTANT**: RAAF Core exclusively uses tool-based handoffs through function calling and currently supports OpenAI models only.

## 📊 Core Gem Compatibility Matrix

| Provider | LLM Type | Function Calling | Handoff Support | Implementation |
|----------|----------|------------------|------------------|----------------|
| **ResponsesProvider** | OpenAI GPT-4/3.5 | ✅ Full | ✅ Full | OpenAI Responses API (default) |
| **OpenAIProvider** | OpenAI GPT-4/3.5 | ✅ Full | ✅ Full | OpenAI Chat Completions (deprecated) |

**Other Provider Support**: Additional providers (Anthropic, Google, etc.) are available in separate RAAF gems, not in this core gem.

## 🔧 Implementation Details

### ✅ **Function Calling in RAAF Core**
RAAF Core requires OpenAI models that support function/tool calling. Handoffs are implemented as explicit tool calls that the LLM must invoke.

**How it works with OpenAI models:**
1. When you add a handoff target: `agent.add_handoff(target_agent)`
2. RAAF automatically creates a tool: `transfer_to_<agent_name>`
3. The LLM must explicitly call this tool to trigger a handoff

**Example Tool Call:**
```json
{
  "tool_calls": [{
    "function": {
      "name": "transfer_to_billing",
      "arguments": "{}"
    }
  }]
}
```

### ❌ **Providers Without Function Calling**
Providers that don't support function calling cannot be used with RAAF's handoff system. This includes:
- Base models without instruction tuning
- Legacy providers without tool support
- Text-only completion models

**Important**: Simply mentioning a transfer in the response text will NOT trigger a handoff. The LLM must make an explicit tool call.

## 🚀 Supported in RAAF Core

RAAF Core currently supports:

### Native OpenAI Integration
- **ResponsesProvider** (default): GPT-4, GPT-3.5-turbo via OpenAI Responses API
- **OpenAIProvider** (deprecated): GPT-4, GPT-3.5-turbo via Chat Completions API

**Other Providers**: For additional LLM providers (Anthropic Claude, Google Gemini, Groq, Cohere, etc.), see the `raaf-providers` gem which extends RAAF Core with multi-provider support.

## 📋 Migration Guide

If you were using content-based handoffs:

### Old Pattern (No Longer Supported)
```ruby
# This will NOT work anymore:
"I'll transfer you to billing. {"handoff_to": "BillingAgent"}"
```

### New Pattern (Tool-Based Only)
```ruby
# Agent must explicitly call the tool:
agent.add_handoff(billing_agent)
# This creates a transfer_to_billing tool that the LLM must invoke
```

## 🔍 Debugging Handoffs

If handoffs aren't working:

1. **Verify you're using OpenAI models**
   ```ruby
   # RAAF Core only supports OpenAI function calling
   agent = RAAF::Agent.new(model: "gpt-4o")
   ```

2. **Check handoff tools are registered**
   ```ruby
   agent.tools.map(&:name) # Should include transfer_to_* tools
   ```

3. **Enable debug logging**
   ```bash
   export RAAF_LOG_LEVEL=debug
   export RAAF_DEBUG_CATEGORIES=handoff,tools
   ```

## 📝 Best Practices

1. **Always verify provider compatibility** before using handoffs
2. **Use explicit handoff instructions** in your agent prompts
3. **Test handoff flows** with your specific provider
4. **Monitor tool call logs** to ensure handoffs are triggered correctly

## ⚠️ Important Notes

- **Content-based handoff detection has been completely removed**
- **All handoffs must be explicit tool calls**
- **Providers without function calling cannot participate in handoffs**
- **The system will not parse message content for handoff patterns**
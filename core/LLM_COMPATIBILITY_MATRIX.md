# LLM Compatibility Matrix

## 🎯 Overview
This matrix shows LLM compatibility with RAAF's tool-based handoff system. **IMPORTANT**: RAAF now exclusively uses tool-based handoffs through function calling. All providers must support function/tool calling for handoffs to work.

## 📊 Compatibility Matrix

| LLM Type | Function Calling | Handoff Support | Implementation |
|----------|------------------|------------------|----------------|
| **OpenAI GPT-4/3.5** | ✅ Full | ✅ Full | Native tool calling |
| **Anthropic Claude 3** | ✅ Full | ✅ Full | Native tool calling |
| **Google Gemini** | ✅ Full | ✅ Full | Native tool calling |
| **Cohere Command R+** | ✅ Full | ✅ Full | Native tool calling |
| **Mistral Large** | ✅ Full | ✅ Full | Native tool calling |
| **Groq (Llama/Mixtral)** | ✅ Full | ✅ Full | Native tool calling |
| **Together AI** | ✅ Full | ✅ Full | Native tool calling |
| **LiteLLM (OpenAI-compatible)** | ✅ Full | ✅ Full | Native tool calling |
| **LLaMA 2/3 Base** | ❌ None | ❌ None | Not supported |
| **Mistral 7B Base** | ❌ None | ❌ None | Not supported |
| **Falcon** | ❌ None | ❌ None | Not supported |
| **CodeLlama Base** | ❌ None | ❌ None | Not supported |
| **Vicuna** | ❌ None | ❌ None | Not supported |
| **Alpaca** | ❌ None | ❌ None | Not supported |

## 🔧 Implementation Details

### ✅ **Full Function Calling Support Required**
RAAF requires providers that support function/tool calling. Handoffs are implemented as explicit tool calls that the LLM must invoke.

**How it works:**
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

## 🚀 Supported Providers

RAAF has been tested with the following providers that support function calling:

### Native Integration
- **OpenAI**: GPT-4, GPT-3.5-turbo (via ResponsesProvider)
- **Anthropic**: Claude 3 family (via AnthropicProvider)
- **Google**: Gemini Pro (via appropriate provider)
- **Groq**: Fast inference with Llama/Mixtral models
- **Together AI**: Various open models with function calling
- **Cohere**: Command R+ with native tool support

### Via LiteLLM
Any provider supported by LiteLLM that offers function calling can be used with RAAF.

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

1. **Verify provider supports function calling**
   ```ruby
   provider.supports_function_calling? # Should return true
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
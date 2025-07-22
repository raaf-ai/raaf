# Tool-Based Handoff System

## 🎯 Overview
RAAF uses an exclusive tool-based handoff system where agents transfer control through explicit function/tool calls. This document describes the current implementation and requirements.

## 📋 System Requirements

### Provider Requirements
- **Function Calling Support**: All providers MUST support function/tool calling
- **Tool Execution**: Providers must be able to execute registered tools
- **Response Format**: Must support tool_calls in responses

### Unsupported Providers
Providers without function calling support cannot participate in handoffs:
- Base language models without tool support
- Legacy chat-only providers
- Text completion models

## 🛠 Implementation Details

### How Handoffs Work

1. **Tool Registration**
   ```ruby
   # When you add a handoff
   agent.add_handoff(target_agent)
   
   # RAAF automatically creates a tool
   # Name: transfer_to_<agent_name>
   # Description: Transfer the conversation to <agent_name>
   ```

2. **Tool Invocation**
   The LLM must explicitly call the handoff tool:
   ```json
   {
     "tool_calls": [{
       "function": {
         "name": "transfer_to_support",
         "arguments": "{}"
       }
     }]
   }
   ```

3. **Handoff Execution**
   - Runner detects the tool call
   - Validates the target agent exists
   - Transfers control to the target agent
   - Preserves conversation context

### Key Components

#### HandoffTool (`lib/raaf/handoff_tool.rb`)
- Creates transfer tools for agents
- Handles tool execution
- Manages handoff data

#### HandoffContext (`lib/raaf/handoff_context.rb`)
- Tracks handoff state
- Prevents circular handoffs
- Manages context transfer

#### Agent (`lib/raaf/agent.rb`)
- `add_handoff` method creates handoff tools
- `generate_handoff_tools` creates all transfer tools
- Maintains handoff registry

## 🚀 Usage Examples

### Basic Handoff Setup
```ruby
# Create agents
support_agent = RAAF::Agent.new(
  name: "SupportAgent",
  instructions: "Handle customer support requests"
)

billing_agent = RAAF::Agent.new(
  name: "BillingAgent", 
  instructions: "Handle billing inquiries"
)

# Enable handoffs
support_agent.add_handoff(billing_agent)
billing_agent.add_handoff(support_agent)

# Run with multiple agents
runner = RAAF::Runner.new(
  agent: support_agent,
  agents: [support_agent, billing_agent]
)
```

### Prompt Engineering for Handoffs
```ruby
agent = RAAF::Agent.new(
  name: "Receptionist",
  instructions: <<~INST
    You are a receptionist. Direct users to the appropriate department:
    - Technical issues → transfer_to_tech_support
    - Billing questions → transfer_to_billing
    - General inquiries → handle yourself
    
    Use the transfer tools when appropriate.
  INST
)
```

## 📊 Provider Compatibility

### ✅ Compatible Providers
- OpenAI (GPT-4, GPT-3.5-turbo)
- Anthropic (Claude 3 family)
- Google (Gemini Pro)
- Groq (with function calling models)
- Together AI (with function calling models)
- Any provider implementing function calling

### ❌ Incompatible Providers
- Base models without instruction tuning
- Providers without tool/function support
- Legacy chat completion only providers

## 🔍 Debugging Handoffs

### Common Issues

1. **Handoff Not Triggering**
   - Verify provider supports function calling
   - Check handoff tool is registered
   - Ensure LLM is calling the tool (not just mentioning it)

2. **Target Agent Not Found**
   - Verify target agent is in the agents array
   - Check agent names match exactly
   - Ensure handoff was properly registered

3. **Circular Handoffs**
   - HandoffContext prevents infinite loops
   - Check agent instructions for logic errors

### Debug Logging
```bash
# Enable detailed handoff logging
export RAAF_LOG_LEVEL=debug
export RAAF_DEBUG_CATEGORIES=handoff,tools,api
```

### Checking Tool Registration
```ruby
# List all tools including handoffs
agent.tools.each do |tool|
  puts "Tool: #{tool.name}"
end

# Check specific handoff exists
agent.tools.any? { |t| t.name == "transfer_to_billing" }
```

## 📝 Best Practices

1. **Clear Instructions**: Tell agents when to handoff
2. **Tool Names**: Use descriptive agent names for clear tool names
3. **Validation**: Always validate handoff targets exist
4. **Context**: Use HandoffContext for state management
5. **Testing**: Test handoff flows with your specific provider

## ⚠️ Important Notes

- **No Content Parsing**: The system will NOT parse message content for handoff patterns
- **Explicit Tools Only**: Handoffs must be explicit tool calls
- **Provider Requirement**: Function calling is mandatory
- **No Fallback**: There is no fallback for providers without tool support

## 🔄 Migration from Content-Based Handoffs

If you were using the old content-based system:

### ❌ Old Pattern (Removed)
```ruby
# These patterns NO LONGER WORK:
"Transfer to SupportAgent"
'{"handoff_to": "SupportAgent"}'
"[HANDOFF:SupportAgent]"
```

### ✅ New Pattern (Tool-Based)
```ruby
# Agent must call the tool:
{
  "tool_calls": [{
    "function": {
      "name": "transfer_to_support",
      "arguments": "{}"
    }
  }]
}
```

## 🎯 Future Considerations

The tool-based handoff system provides:
- **Reliability**: Explicit tool calls are unambiguous
- **Consistency**: Same pattern across all providers
- **Simplicity**: No complex parsing or pattern matching
- **Compatibility**: Works with standard function calling

This is the permanent handoff architecture for RAAF.
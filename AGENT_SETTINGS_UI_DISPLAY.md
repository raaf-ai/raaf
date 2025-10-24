# Agent Settings Display in Rails Spans UI

## 🎯 Current Status

**✅ COMPLETE** - Temperature and all agent settings are now fully captured and displayed in the Rails spans UI.

## 📊 What Gets Displayed

The "Agent Configuration" section now shows up to 10 configurable settings:

```
┌─────────────────────────────────────────────────────────┐
│              Agent Configuration                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Agent Name    │  ProspectScoringAgent                 │
│  Model         │  gpt-4o                               │
│  Status        │  ✓ Ok                                 │
│  Duration      │  37.2s                                │
│                                                         │
│  Temperature   │  0.7                                  │
│  Max Tokens    │  2000                                 │
│  Top P         │  0.95                                 │
│                                                         │
│  Freq Penalty  │  0.1                                  │
│  Pres Penalty  │  0.05                                 │
│                                                         │
│  Tools         │  3                                    │
│  Tool Choice   │  "auto"                               │
│  Parallel      │  Enabled                              │
│                                                         │
│  Response Fmt  │  {"type":"json_schema",...}          │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## 🔍 Captured Settings

### Core Model Parameters

| Setting | Example | Source | Display |
|---------|---------|--------|---------|
| **Temperature** | `0.7` | `agent.model_settings[:temperature]` | ✅ Yes |
| **Max Tokens** | `2000` | `agent.model_settings[:max_tokens]` | ✅ Yes |
| **Top P** | `0.95` | `agent.model_settings[:top_p]` | ✅ Yes |

### Penalty Parameters

| Setting | Example | Source | Display |
|---------|---------|--------|---------|
| **Frequency Penalty** | `0.1` | `agent.model_settings[:frequency_penalty]` | ✅ Yes |
| **Presence Penalty** | `0.05` | `agent.model_settings[:presence_penalty]` | ✅ Yes |

### Tool Configuration

| Setting | Example | Source | Display |
|---------|---------|--------|---------|
| **Tools Available** | `3` | `agent.tools.length` | ✅ Yes |
| **Tool Choice** | `"auto"` | `agent.tool_choice` | ✅ Yes |
| **Parallel Tool Calls** | `"Enabled"` | `agent.model_settings[:parallel_tool_calls]` | ✅ Yes |

### Response Configuration

| Setting | Example | Source | Display |
|---------|---------|--------|---------|
| **Response Format** | `{"type":"json_schema"}` | `agent.response_format` | ✅ Yes |

## 🔧 How to Populate These Settings

### For Core RAAF::Agent

```ruby
agent = RAAF::Agent.new(
  name: "MyAgent",
  model: "gpt-4o",
  instructions: "You are helpful",

  # These will be captured in spans:
  model_settings: {
    temperature: 0.7,
    max_tokens: 2000,
    top_p: 0.95,
    frequency_penalty: 0.1,
    presence_penalty: 0.05,
    parallel_tool_calls: true
  },

  tool_choice: "auto",
  response_format: { type: "json_schema", schema: { ... } }
)

# Execute with tracing
tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(RAAF::Tracing::ActiveRecordProcessor.new)
runner = RAAF::Runner.new(agent: agent, tracer: tracer)
result = runner.run("Hello!")

# Settings now visible in /raaf/tracing/spans
```

### For DSL Agents

```ruby
class MyAgent < RAAF::DSL::Agent
  agent_name "MySearchAgent"
  model "gpt-4o"
  max_turns 5

  # These will be captured:
  temperature 0.7
  max_tokens 2000
  top_p 0.95
  frequency_penalty 0.1
  presence_penalty 0.05
  parallel_tool_calls true
  tool_choice "auto"
  response_format { type: "json_schema" }
end

agent = MyAgent.new
result = agent.call

# Settings now visible in /raaf/tracing/spans
```

## 📁 Files Modified

### 1. Span Collectors (Backend Capture)

**AgentCollector** - `raaf/tracing/lib/raaf/tracing/span_collectors/agent_collector.rb`
- Lines 60-132: Added 9 span capture definitions
- Captures all model settings from agent.model_settings
- Handles both symbol and string keys
- Returns "N/A" for missing values

**DSL AgentCollector** - `raaf/tracing/lib/raaf/tracing/span_collectors/dsl/agent_collector.rb`
- Lines 70-106: Extended to capture 8 model settings
- Extracts from DSL _context_config
- Maintains consistency with core collector

### 2. Rails UI Component (Display Layer)

**AgentSpanComponent** - `raaf/rails/app/components/raaf/rails/tracing/agent_span_component.rb`
- Lines 217-229: Updated agent_config extraction method
- Lines 246-301: Enhanced render_agent_configuration method
- Added conditional rendering for each setting
- Organized into logical sections

## 🎨 Display Features

✨ **Smart Filtering**
- Only shows settings with actual values
- Hides "N/A" defaults
- Clean, uncluttered interface

✨ **Monospace Formatting**
- Technical settings (model, tool_choice, response_format) use monospace
- Easier to read JSON and technical values

✨ **Conditional Display**
- Tools only shown if tools_count > 0
- Settings only shown if they have meaningful values
- Response format shown in collapsible JSON section

✨ **Organized Layout**
- Grid layout with 1-2 columns depending on screen size
- Grouped by setting type for readability
- Responsive design for mobile and desktop

## 🔄 Data Flow

```
Agent Execution
    ↓
AgentCollector/DSL::AgentCollector
    ├─ extract agent.model_settings
    ├─ extract agent.tool_choice
    ├─ extract agent.response_format
    └─ store in span_attributes JSONB
    ↓
SpanRecord saved to database
    ├─ span_attributes = {
    │   "agent.temperature": "0.7",
    │   "agent.max_tokens": "2000",
    │   "agent.top_p": "0.95",
    │   ...
    │ }
    ↓
AgentSpanComponent renders
    ├─ agent_config extracts values
    ├─ Conditional rendering
    └─ Display in Agent Configuration section
    ↓
User sees complete agent configuration
```

## 📈 Example Span Attributes

When an agent with settings executes, the SpanRecord stores:

```json
{
  "agent.name": "ProspectScoringAgent",
  "agent.model": "gpt-4o",
  "agent.max_turns": "3",
  "agent.tools_count": "3",
  "agent.handoffs_count": "0",

  "agent.temperature": "0.7",
  "agent.max_tokens": "2000",
  "agent.top_p": "0.95",
  "agent.frequency_penalty": "0.1",
  "agent.presence_penalty": "0.05",
  "agent.tool_choice": "auto",
  "agent.parallel_tool_calls": "Enabled",
  "agent.response_format": "{\"type\":\"json_schema\"}",
  "agent.model_settings_json": "{\"temperature\":0.7,\"max_tokens\":2000,...}",

  "agent.conversation_messages": "[...]",
  "agent.conversation_stats": "{...}",

  "result.type": "RAAF::RunResult",
  "result.success": true
}
```

## ✅ Verification Steps

1. **Create Agent with Settings**
   ```bash
   # In Rails console:
   agent = RAAF::Agent.new(
     name: "Test", model: "gpt-4o",
     model_settings: { temperature: 0.7, max_tokens: 2000 }
   )
   ```

2. **Execute with Tracing**
   ```ruby
   tracer = RAAF::Tracing::SpanTracer.new
   tracer.add_processor(RAAF::Tracing::ActiveRecordProcessor.new)
   runner = RAAF::Runner.new(agent: agent, tracer: tracer)
   result = runner.run("Hello!")
   ```

3. **View in Dashboard**
   - Navigate to `http://localhost:3000/raaf/tracing/spans`
   - Click the agent span
   - Scroll to "Agent Configuration" section
   - Verify all settings are displayed

4. **Check Database**
   ```sql
   SELECT span_attributes FROM raaf_rails_tracing_span_records
   WHERE span_attributes->>'agent.temperature' IS NOT NULL
   LIMIT 1;
   ```

## 🚀 Ready for Production

The implementation is **complete and ready** for:

✅ New agent executions - Will capture all settings automatically
✅ Production deployment - No migration needed
✅ Backward compatibility - Gracefully handles missing settings
✅ Performance - Minimal overhead, efficient storage
✅ Scalability - Works with high-volume agent execution

---

**Implementation:** October 24, 2025
**Status:** ✅ Complete
**Tested:** ✅ Yes
**Production Ready:** ✅ Yes

# Tests Specification

This is the tests coverage details for the spec detailed in @.agent-os/specs/2025-09-25-tracing-ai-dialog-ui/spec.md

> Created: 2025-09-25
> Version: 1.0.0

## Test Coverage

### Unit Tests

**SpanDetail Component**
- Test main span detail component routes to correct type-specific component
- Test span overview displays correctly for all span types
- Test grouped attributes rendering with proper categorization
- Test span hierarchy and relationship navigation
- Test timing information display and calculations

**Type-Specific Components**
- **ToolSpanComponent**: Test tool function display, input parameters, output results, execution flow
- **AgentSpanComponent**: Test agent information, model details, configuration display
- **LlmSpanComponent**: Test LLM request/response, token usage, cost information
- **HandoffSpanComponent**: Test source/target agent display, handoff reasons, context transfer
- **GuardrailSpanComponent**: Test security filter results, blocked content, reasoning
- **PipelineSpanComponent**: Test pipeline stages, step execution, data flow

**Data Extraction and Formatting**
- Test type-specific data extraction methods for each span kind
- Test JSON formatting and truncation for large data objects
- Test expand/collapse state management across component types

### Integration Tests

**Span Detail Page Flow**
- Test complete span detail page loads with type-specific component for each span kind
- Test component switching based on span.kind attribute
- Test JavaScript toggle functionality works across different component types
- Test responsive design on mobile and desktop viewports
- Test large attribute data handling (complex nested JSON)
- Test component rendering with missing or malformed span data

**Cross-Component Integration**
- Test consistent styling and layout across all span type components
- Test shared JavaScript functionality (expand/collapse) works in all components
- Test proper data passing from main SpanDetail to type-specific components

### Feature Tests

**End-to-end User Scenarios**
- Navigate to span detail page and verify conversation timeline displays
- Expand and collapse individual messages using toggle buttons
- Review tool calls with input/output data clearly separated
- Verify token usage and performance metrics are visible
- Test conversation export functionality (if implemented)

### Mocking Requirements

**Span Data Mocking**
- Mock SpanRecord with various conversation data structures
- Mock complex multi-turn conversations with tool calls
- Mock edge cases: empty messages, malformed JSON, missing data

**Stimulus Controller Testing**
- Test Stimulus controller registration and initialization
- Test toggleSection, toggleToolInput, toggleToolOutput actions
- Test data-action and data-target attribute functionality
- Test expand/collapse state management via Stimulus

## Test Data Examples

### Basic Conversation Span
```ruby
let(:basic_conversation_span) do
  create(:span_record, span_attributes: {
    "agent" => { "name" => "TestAgent", "model" => "gpt-4o" },
    "messages" => [
      { "role" => "system", "content" => "You are a helpful assistant" },
      { "role" => "user", "content" => "Hello, how are you?" },
      { "role" => "assistant", "content" => "I'm doing well, thank you!" }
    ],
    "usage" => { "total_tokens" => 45, "prompt_tokens" => 25, "completion_tokens" => 20 }
  })
end
```

### Complex Tool Call Conversation
```ruby
let(:tool_conversation_span) do
  create(:span_record, span_attributes: {
    "agent" => { "name" => "SearchAgent", "model" => "gpt-4o" },
    "messages" => [
      { "role" => "user", "content" => "Search for Ruby documentation" },
      {
        "role" => "assistant",
        "content" => "I'll search for Ruby documentation for you.",
        "tool_calls" => [{
          "id" => "call_123",
          "type" => "function",
          "function" => {
            "name" => "web_search",
            "arguments" => { "query" => "Ruby programming documentation" }
          }
        }]
      },
      {
        "role" => "tool",
        "content" => "Found 10 results about Ruby documentation...",
        "tool_call_id" => "call_123"
      }
    ],
    "usage" => { "total_tokens" => 150 }
  })
end
```

### Edge Case Test Data
```ruby
let(:empty_conversation_span) { create(:span_record, span_attributes: {}) }
let(:malformed_conversation_span) do
  create(:span_record, span_attributes: { "messages" => "invalid_data" })
end
let(:large_conversation_span) do
  messages = 25.times.map do |i|
    { "role" => "user", "content" => "Message #{i + 1}" }
  end
  create(:span_record, span_attributes: { "messages" => messages })
end
```

## Browser Testing Requirements

**Cross-browser Compatibility**
- Chrome/Chromium latest
- Firefox latest
- Safari latest
- Edge latest

**Responsive Testing**
- Mobile viewport (320px-768px)
- Tablet viewport (768px-1024px)
- Desktop viewport (1024px+)

**Stimulus Controller Functionality**
- Toggle buttons work without page refresh via Stimulus actions
- Stimulus controller handles component interactions properly
- No JavaScript errors in console
- Proper data-controller, data-action, and data-target attribute usage
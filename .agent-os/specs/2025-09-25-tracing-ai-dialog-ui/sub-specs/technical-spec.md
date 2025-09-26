# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-09-25-tracing-ai-dialog-ui/spec.md

> Created: 2025-09-25
> Version: 1.0.0

## Technical Requirements

### Span Data Structure Analysis

Based on analysis of the current RAAF tracing system, span data is stored in multiple fields with the following structure:

```ruby
span: {
  id: "span_id_123",
  name: "Agent.run",
  status: "success",
  start_time: timestamp,
  end_time: timestamp,
  duration: milliseconds,
  trace_id: "trace_id_456",
  parent_span_id: "parent_span_id_789",
  span_attributes: {
    "agent.name" => "ResearchAgent",
    "agent.model" => "gpt-4o",
    "input.query" => "User query text",
    "output.response" => "Agent response",
    "usage.tokens.total" => 225,
    # Additional attributes...
  }
}
```

### UI Component Architecture

- **Main SpanDetail component** (`RAAF::Rails::Tracing::SpanDetail`) - Orchestrates rendering and routes to type-specific components
- **Separate type-specific components** - Independent components per span kind in their own files
- **Shared base component** - Common functionality and styling for all span types
- **File structure**:
  - `span_detail.rb` - Main orchestrator component
  - `span_detail_base.rb` - Shared functionality base class
  - `tool_span_component.rb` - Tool-specific rendering
  - `agent_span_component.rb` - Agent-specific rendering
  - `llm_span_component.rb` - LLM-specific rendering
  - `handoff_span_component.rb` - Handoff-specific rendering
  - `guardrail_span_component.rb` - Guardrail-specific rendering
  - `pipeline_span_component.rb` - Pipeline-specific rendering
- **Maintain existing Phlex component structure** and styling patterns

### Type-Specific Rendering Strategy

- **Universal Span Header**: ID, trace, parent, name, kind, status, timing (all types)
- **Tool Spans**: Function name, input parameters, output results, execution flow visualization
- **Agent Spans**: Agent name, model, configuration, instructions, context variables
- **LLM Spans**: Request/response, token usage, cost metrics, model parameters
- **Handoff Spans**: Source/target agents, handoff reason, context transfer data
- **Guardrail Spans**: Filter results, blocked content, security reasoning, policy applied
- **Pipeline Spans**: Stage execution, data flow, step results, pipeline metadata

### Performance Considerations

- **Conditional rendering**: Only render tool details section when `kind == "tool"` and tool data exists
- **JSON formatting**: Use existing `format_json_display` method for tool parameters and results
- **Content truncation**: Auto-collapse large JSON objects with "Show more" toggle
- **Grouped attributes**: Organize attributes into sections (pipeline, context, execution, results) for better performance and navigation

## Approach Options

**Option A: Separate Tool Visualization Component (Selected)**
- Pros: Modular, reusable, easier to test, clear separation of concerns
- Cons: Additional file complexity, need for data passing

**Option B: Enhanced Inline Integration**
- Pros: Simpler file structure, direct access to span data, consistent with existing patterns, leverages existing tool rendering logic
- Cons: Larger component file, tighter coupling

**Rationale:** Option A selected because separate components provide better modularity, easier testing, and clear separation of concerns. Each span type component can be developed, tested, and maintained independently. The additional file complexity is offset by improved code organization and reusability across different parts of the application.

## External Dependencies

None required - implementation uses existing dependencies:

- **Phlex-rails** - Already integrated for component rendering
- **Preline UI** - Already used for styling classes
- **Bootstrap Icons** - Already available for message type icons

## Implementation Details

### Component Structure

```ruby
# Main SpanDetail component (app/components/RAAF/rails/tracing/span_detail.rb)
class RAAF::Rails::Tracing::SpanDetail < Phlex::HTML
  def view_template
    render_universal_span_header
    render_type_specific_component
  end

  private

  def render_type_specific_component
    case @span.kind
    when "tool" then render(RAAF::Rails::Tracing::ToolSpanComponent.new(@span))
    when "agent" then render(RAAF::Rails::Tracing::AgentSpanComponent.new(@span))
    when "llm" then render(RAAF::Rails::Tracing::LlmSpanComponent.new(@span))
    when "handoff" then render(RAAF::Rails::Tracing::HandoffSpanComponent.new(@span))
    when "guardrail" then render(RAAF::Rails::Tracing::GuardrailSpanComponent.new(@span))
    when "pipeline" then render(RAAF::Rails::Tracing::PipelineSpanComponent.new(@span))
    else render(RAAF::Rails::Tracing::GenericSpanComponent.new(@span))
    end
  end
end

# Shared base class (app/components/RAAF/rails/tracing/span_detail_base.rb)
class RAAF::Rails::Tracing::SpanDetailBase < Phlex::HTML
  def initialize(span)
    @span = span
  end

  protected

  def render_json_section(title, data, collapsed: true)
    # Shared JSON rendering with expand/collapse using Preline classes
    section(class: "bg-gray-50 rounded-lg p-4") do
      button(
        class: "flex items-center gap-2 text-sm font-medium text-gray-700 hover:text-gray-900",
        data: { action: "click->span-detail#toggleSection" }
      ) do
        i(class: collapsed ? "bi bi-chevron-right" : "bi bi-chevron-down")
        span { title }
      end
      div(class: collapsed ? "hidden mt-2" : "mt-2") do
        pre(class: "bg-white p-3 rounded border text-xs overflow-x-auto") do
          JSON.pretty_generate(data)
        end
      end
    end
  end

  def format_timestamp(time)
    return "N/A" unless time
    time.strftime("%Y-%m-%d %H:%M:%S.%3N")
  end

  def render_duration_badge(duration_ms)
    color_class = case duration_ms
    when 0..100 then "bg-green-100 text-green-800"
    when 101..1000 then "bg-yellow-100 text-yellow-800"
    else "bg-red-100 text-red-800"
    end

    span(class: "px-2 py-1 text-xs font-medium rounded-full #{color_class}") do
      "#{duration_ms}ms"
    end
  end
end

# Tool-specific component (app/components/RAAF/rails/tracing/tool_span_component.rb)
class RAAF::Rails::Tracing::ToolSpanComponent < RAAF::Rails::Tracing::SpanDetailBase
  def view_template
    div(class: "space-y-6") do
      render_tool_overview
      render_function_execution_flow if tool_data
    end
  end

  private

  def tool_data
    @tool_data ||= @span.span_attributes&.dig("function")
  end

  def render_tool_overview
    div(class: "bg-blue-50 border border-blue-200 rounded-lg p-4") do
      div(class: "flex items-center gap-3") do
        i(class: "bi bi-tools text-blue-600 text-lg")
        div do
          h3(class: "font-semibold text-blue-900") { "Tool Execution" }
          p(class: "text-sm text-blue-700") { tool_data&.dig("name") || "Unknown Tool" }
        end
      end
    end
  end

  def render_function_execution_flow
    div(class: "grid grid-cols-1 lg:grid-cols-2 gap-6") do
      render_json_section("Input Parameters", tool_data["input"], collapsed: false)
      render_json_section("Output Results", tool_data["output"], collapsed: false)
    end
  end
end
```

### Stimulus Controller Requirements

Use Stimulus controllers for expand/collapse functionality - extend existing Stimulus patterns:

```javascript
// Stimulus controller (app/javascript/controllers/span_detail_controller.js)
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggleSection", "toggleIcon"]

  toggleSection(event) {
    const targetId = event.currentTarget.dataset.target
    const section = document.getElementById(targetId)
    const icon = event.currentTarget.querySelector('.toggle-icon')

    if (section.classList.contains('hidden')) {
      section.classList.remove('hidden')
      icon.classList.replace('bi-chevron-right', 'bi-chevron-down')
    } else {
      section.classList.add('hidden')
      icon.classList.replace('bi-chevron-down', 'bi-chevron-right')
    }
  }

  toggleToolInput(event) {
    this.toggleSection(event)
  }

  toggleToolOutput(event) {
    this.toggleSection(event)
  }

  toggleAttributeGroup(event) {
    this.toggleSection(event)
  }
}
```

**HTML Integration in Components:**
```ruby
div(data: { controller: "span-detail" }) do
  button(
    class: "flex items-center gap-2 text-sm font-medium text-gray-700 hover:text-gray-900",
    data: {
      action: "click->span-detail#toggleSection",
      target: "tool-input-section-#{@span.span_id}"
    }
  ) do
    i(class: "bi bi-chevron-right toggle-icon")
    span { "Input Parameters" }
  end

  div(id: "tool-input-section-#{@span.span_id}", class: "hidden mt-2") do
    # Content here
  end
end
```

### CSS Integration

Use existing Preline classes with custom span visualization styles:

- `.tool-execution-flow` - Main tool visualization container
- `.tool-input-section` - Tool input parameters styling
- `.tool-output-section` - Tool output results styling
- `.attribute-group` - Grouped attribute sections styling
- `.span-hierarchy` - Parent/child relationship indicators

### Data Extraction Strategy

```ruby
def extract_tool_execution_data
  return nil unless @span.kind == "tool" && @span.span_attributes&.dig("function")

  function_data = @span.span_attributes["function"]
  {
    function_name: function_data["name"],
    input_parameters: function_data["input"],
    output_results: function_data["output"],
    execution_status: @span.status,
    duration_ms: @span.duration_ms,
    error_details: @span.error_details
  }
end

def extract_grouped_attributes
  return {} unless @span.span_attributes

  grouped = {
    pipeline: {},
    context: {},
    execution: {},
    results: {},
    other: {}
  }

  @span.span_attributes.each do |key, value|
    case key.to_s
    when /^pipeline\./
      grouped[:pipeline][key] = value
    when /^(context|initial_context|market_data)/
      grouped[:context][key] = value
    when /^(execution|duration|agents|success)/
      grouped[:execution][key] = value
    when /^(result|final_result|transformation)/
      grouped[:results][key] = value
    else
      grouped[:other][key] = value
    end
  end

  grouped.reject { |_, v| v.empty? }
end
```

## Integration Points

- **Existing SpanDetail rendering flow** - Enhance existing tool details section and add grouped attributes display
- **Existing toggle functionality** - Extend current JavaScript event delegation for tool input/output sections
- **Existing styling system** - Use Preline classes with tool visualization additions
- **Existing JSON formatting** - Reuse `format_json_display` for tool parameters and results
- **Existing attribute grouping** - Build on current attribute categorization logic
- **Existing hierarchy navigation** - Enhance parent/child span relationship display
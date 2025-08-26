# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-08-25-enhanced-agent-tracing-ui/spec.md

> Created: 2025-08-25
> Version: 1.0.0

## Technical Requirements

- **Enhanced Data Capture**: Extend existing ActiveRecord processor to capture prompts, input/output context, schema information, chat messages, agent names, and execution timestamps
- **Database Schema Extensions**: Add new fields to existing tracing tables and create new tables for complex data structures  
- **Rails Engine Enhancement**: Extend existing RAAF::Tracing::Engine with new controllers and views for enhanced UI
- **JSON Viewer Component**: JavaScript/Stimulus component for interactive JSON display with syntax highlighting and collapsible sections
- **Performance Optimization**: Proper database indexing and pagination for large datasets
- **Responsive Design**: Modern CSS framework integration for mobile and desktop viewing

## Approach Options

**Option A: Extend Existing Architecture** (Selected)
- Pros: Leverages existing RAAF tracing infrastructure, maintains backward compatibility, follows established patterns
- Cons: May require refactoring some existing components, needs careful migration planning

**Option B: Create Separate Tracing System**
- Pros: Clean slate implementation, no legacy constraints, optimized for new requirements
- Cons: Duplicates existing functionality, breaks existing integrations, higher development effort

**Option C: Hybrid Approach with New Engine**
- Pros: Preserves existing system, allows parallel development
- Cons: Complexity of maintaining two systems, potential data synchronization issues

**Rationale:** Option A selected because RAAF already has a robust tracing foundation with ActiveRecord processor, Rails engine, and established patterns. Extending this system provides the fastest path to value while maintaining existing integrations and backwards compatibility.

## External Dependencies

- **rouge** (~> 4.0) - Ruby syntax highlighter for JSON formatting in views
- **Justification:** Provides server-side JSON syntax highlighting as fallback for JavaScript, ensuring functionality without JS enabled

- **stimulus-rails** (already in Rails stack) - JavaScript framework for interactive components  
- **Justification:** Required for collapsible JSON viewer, follows Rails conventions, minimal footprint

## Implementation Architecture

### Data Flow Enhancement

```ruby
# Enhanced span processing with additional data capture
class RAAF::Tracing::EnhancedSpanProcessor
  def process_agent_span(span)
    # Capture existing data plus new requirements
    {
      # Existing fields
      span_id: span.span_id,
      trace_id: span.trace_id,
      name: span.name,
      
      # New enhanced fields
      agent_name: extract_agent_name(span),
      prompt_text: extract_prompt(span),
      input_context: extract_input_context(span),
      output_context: extract_output_context(span),
      schema_info: extract_schema(span),
      chat_messages: extract_chat_messages(span),
      execution_metadata: extract_metadata(span)
    }
  end
end
```

### Rails Engine Structure

```
tracing/
├── app/
│   ├── controllers/raaf/tracing/
│   │   ├── enhanced_traces_controller.rb
│   │   └── json_viewer_controller.rb
│   ├── views/raaf/tracing/
│   │   ├── enhanced_traces/
│   │   │   ├── index.html.erb
│   │   │   └── show.html.erb
│   │   └── shared/
│   │       └── _json_viewer.html.erb
│   ├── assets/stylesheets/raaf/tracing/
│   │   └── enhanced_ui.css
│   └── javascript/raaf/tracing/
│       └── json_viewer_controller.js
```

### JSON Viewer Component

```javascript
// Stimulus controller for interactive JSON viewing
export default class extends Controller {
  static targets = ["container", "toggle"]
  
  toggle(event) {
    const section = event.target.closest('.json-section')
    section.classList.toggle('collapsed')
    this.updateToggleIcon(event.target)
  }
  
  expandAll() {
    this.containerTargets.forEach(container => {
      container.classList.remove('collapsed')
    })
  }
  
  collapseAll() {
    this.containerTargets.forEach(container => {
      container.classList.add('collapsed')
    })
  }
}
```

## Data Storage Strategy

### Enhanced Span Attributes

Store complex data structures as JSONB fields for efficient querying:

```ruby
# Enhanced span model with new fields
class RAAF::Tracing::SpanRecord < ActiveRecord::Base
  # New JSONB fields for enhanced data
  # prompt_data: { text: string, template: string, variables: hash }
  # input_context: { data: hash, schema: hash, validation: array }
  # output_context: { data: hash, schema: hash, transformations: array }
  # chat_messages: [{ role: string, content: string, timestamp: datetime }]
  # execution_metadata: { start_time: datetime, end_time: datetime, agent_name: string }
end
```

### Indexing Strategy

```sql
-- Optimize for common query patterns
CREATE INDEX idx_spans_agent_name ON raaf_tracing_spans USING btree (agent_name);
CREATE INDEX idx_spans_execution_time ON raaf_tracing_spans USING btree (start_time DESC);
CREATE INDEX idx_spans_input_context ON raaf_tracing_spans USING gin (input_context);
CREATE INDEX idx_spans_output_context ON raaf_tracing_spans USING gin (output_context);
```

## UI/UX Requirements

### Dashboard Layout
- **Header**: Search/filter controls with date range picker and agent name selector
- **Main View**: Paginated list of agent executions with expandable details
- **Detail Panel**: Interactive JSON viewers for each data category
- **Footer**: Pagination controls and data export options

### JSON Viewer Features
- **Syntax Highlighting**: Color-coded JSON with proper indentation
- **Collapsible Sections**: Click to expand/collapse nested objects and arrays
- **Search Within JSON**: Find specific keys or values within large structures  
- **Copy Functionality**: Copy specific JSON sections to clipboard
- **Responsive Design**: Proper display on mobile and desktop screens

## Performance Considerations

### Database Optimization
- JSONB fields with GIN indexes for efficient querying
- Partitioning large trace tables by date
- Connection pooling for high-traffic scenarios
- Pagination with cursor-based navigation for large datasets

### Frontend Optimization  
- Lazy loading of JSON data for large structures
- Virtual scrolling for long lists of traces
- Progressive enhancement for JavaScript features
- Caching of syntax-highlighted JSON content

## Security Requirements

### Data Privacy
- PII detection and redaction in captured context data
- Configurable data retention policies with automatic cleanup
- Access control for sensitive tracing information
- Audit logging for trace data access

### Input Validation
- Sanitization of all user inputs in search/filter forms
- CSRF protection for all forms
- XSS prevention in JSON display components
- Rate limiting for API endpoints
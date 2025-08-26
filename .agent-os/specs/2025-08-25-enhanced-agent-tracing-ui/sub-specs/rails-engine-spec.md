# Rails Engine UI Specification

This is the Rails engine UI specification for the spec detailed in @.agent-os/specs/2025-08-25-enhanced-agent-tracing-ui/spec.md

> Created: 2025-08-25
> Version: 1.0.0

## Rails Engine Architecture

### Engine Structure
```
tracing/
├── app/
│   ├── controllers/raaf/tracing/
│   │   ├── enhanced_traces_controller.rb
│   │   ├── spans_controller.rb (enhanced)
│   │   └── json_data_controller.rb
│   ├── views/raaf/tracing/
│   │   ├── enhanced_traces/
│   │   │   ├── index.html.erb
│   │   │   └── show.html.erb
│   │   ├── spans/
│   │   │   ├── show.html.erb (enhanced)
│   │   │   └── _agent_details.html.erb
│   │   └── shared/
│   │       ├── _json_viewer.html.erb
│   │       ├── _search_form.html.erb
│   │       └── _filter_controls.html.erb
│   ├── assets/
│   │   ├── stylesheets/raaf/tracing/
│   │   │   ├── enhanced_ui.css
│   │   │   └── json_viewer.css
│   │   └── javascripts/raaf/tracing/
│   │       ├── json_viewer_controller.js
│   │       └── search_controller.js
│   └── helpers/raaf/tracing/
│       └── enhanced_traces_helper.rb
```

## Controller Specifications

### EnhancedTracesController

```ruby
class RAAF::Tracing::EnhancedTracesController < ApplicationController
  before_action :set_trace, only: [:show]
  
  # GET /tracing/enhanced_traces
  def index
    @traces = filtered_traces.page(params[:page]).per(25)
    @agents = distinct_agent_names
    @total_count = @traces.total_count
    
    respond_to do |format|
      format.html
      format.json { render json: traces_json }
    end
  end
  
  # GET /tracing/enhanced_traces/:id  
  def show
    @spans = @trace.spans.includes(:parent_span)
                    .where.not(agent_name: nil)
                    .order(:start_time)
    
    respond_to do |format|
      format.html
      format.json { render json: trace_json }
    end
  end
  
  # GET /tracing/enhanced_traces/search
  def search
    @results = search_traces(params[:q])
    render json: @results
  end
  
  private
  
  def filtered_traces
    traces = RAAF::Tracing::TraceRecord.includes(:spans)
    traces = traces.joins(:spans).where(spans: { agent_name: params[:agent] }) if params[:agent].present?
    traces = traces.where(started_at: date_range) if date_range_params?
    traces = traces.where("workflow_name ILIKE ?", "%#{params[:workflow]}%") if params[:workflow].present?
    traces.distinct.order(started_at: :desc)
  end
  
  def set_trace
    @trace = RAAF::Tracing::TraceRecord.find(params[:id])
  end
end
```

### JsonDataController

```ruby
class RAAF::Tracing::JsonDataController < ApplicationController
  # GET /tracing/json_data/span/:span_id/:field
  def show
    @span = RAAF::Tracing::SpanRecord.find(params[:span_id])
    @field = params[:field]
    @data = @span.send(@field)
    
    render json: {
      field: @field,
      data: @data,
      formatted: format_json(@data),
      size: @data.to_json.bytesize
    }
  end
  
  private
  
  def format_json(data)
    JSON.pretty_generate(data)
  rescue JSON::GeneratorError
    data.to_s
  end
end
```

## View Specifications

### Enhanced Traces Index View

```erb
<!-- app/views/raaf/tracing/enhanced_traces/index.html.erb -->
<div class="enhanced-traces-dashboard" data-controller="search">
  <header class="dashboard-header">
    <h1>Agent Execution Traces</h1>
    <div class="stats-summary">
      <span class="stat">Total: <%= @total_count %></span>
      <span class="stat">Showing: <%= @traces.current_page_record_count %></span>
    </div>
  </header>

  <!-- Search and Filter Controls -->
  <%= render 'shared/search_form' %>
  <%= render 'shared/filter_controls' %>

  <!-- Traces Table -->
  <div class="traces-table-container">
    <table class="traces-table">
      <thead>
        <tr>
          <th>Timestamp</th>
          <th>Workflow</th>
          <th>Agents</th>
          <th>Duration</th>
          <th>Status</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <% @traces.each do |trace| %>
          <tr class="trace-row" data-trace-id="<%= trace.id %>">
            <td class="timestamp">
              <%= time_tag trace.started_at, format: :short %>
            </td>
            <td class="workflow-name">
              <%= link_to trace.workflow_name, enhanced_trace_path(trace), 
                          class: "workflow-link" %>
            </td>
            <td class="agents">
              <div class="agent-pills">
                <% trace.agent_names.each do |agent_name| %>
                  <span class="agent-pill"><%= agent_name %></span>
                <% end %>
              </div>
            </td>
            <td class="duration">
              <%= duration_display(trace.duration_ms) %>
            </td>
            <td class="status">
              <span class="status-badge status-<%= trace.status %>">
                <%= trace.status.humanize %>
              </span>
            </td>
            <td class="actions">
              <%= link_to "View Details", enhanced_trace_path(trace),
                          class: "btn btn-sm btn-primary" %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>

  <!-- Pagination -->
  <%= paginate @traces, theme: 'raaf_tracing' %>
</div>
```

### Trace Detail View

```erb
<!-- app/views/raaf/tracing/enhanced_traces/show.html.erb -->
<div class="trace-detail" data-controller="json-viewer">
  <header class="trace-header">
    <div class="trace-info">
      <h1><%= @trace.workflow_name %></h1>
      <div class="trace-meta">
        <span class="meta-item">Started: <%= @trace.started_at %></span>
        <span class="meta-item">Duration: <%= duration_display(@trace.duration_ms) %></span>
        <span class="meta-item">Status: 
          <span class="status-<%= @trace.status %>"><%= @trace.status.humanize %></span>
        </span>
      </div>
    </div>
    
    <div class="trace-actions">
      <button type="button" class="btn btn-sm" data-action="json-viewer#expandAll">
        Expand All
      </button>
      <button type="button" class="btn btn-sm" data-action="json-viewer#collapseAll">
        Collapse All
      </button>
    </div>
  </header>

  <!-- Agent Execution Timeline -->
  <div class="agent-timeline">
    <% @spans.each_with_index do |span, index| %>
      <div class="agent-execution-card" data-span-id="<%= span.span_id %>">
        <%= render 'spans/agent_details', span: span, index: index %>
      </div>
    <% end %>
  </div>
</div>
```

### Agent Details Partial

```erb
<!-- app/views/raaf/tracing/spans/_agent_details.html.erb -->
<div class="agent-card" data-controller="json-viewer" data-span-id="<%= span.span_id %>">
  <div class="agent-header">
    <div class="agent-info">
      <h3 class="agent-name"><%= span.agent_name %></h3>
      <div class="agent-meta">
        <span class="execution-time">
          <%= time_tag span.start_time, format: :time_only %> - 
          <%= time_tag span.end_time, format: :time_only %>
        </span>
        <span class="duration">
          (<%= duration_display(span.duration_ms) %>)
        </span>
      </div>
    </div>
    <div class="agent-status">
      <span class="status-badge status-<%= span.status %>">
        <%= span.status.humanize %>
      </span>
    </div>
  </div>

  <!-- JSON Data Sections -->
  <div class="json-sections">
    <!-- Prompt Data -->
    <% if span.prompt_data.present? %>
      <div class="json-section">
        <h4 class="section-header">
          <button type="button" class="toggle-btn" data-action="json-viewer#toggle">
            <span class="toggle-icon">▶</span>
            Prompt Data
          </button>
          <span class="data-size"><%= data_size(span.prompt_data) %></span>
        </h4>
        <div class="json-content collapsed" data-json-viewer-target="container">
          <%= render 'shared/json_viewer', data: span.prompt_data, field: 'prompt_data' %>
        </div>
      </div>
    <% end %>

    <!-- Input Context -->
    <% if span.input_context.present? %>
      <div class="json-section">
        <h4 class="section-header">
          <button type="button" class="toggle-btn" data-action="json-viewer#toggle">
            <span class="toggle-icon">▶</span>
            Input Context
          </button>
          <span class="data-size"><%= data_size(span.input_context) %></span>
        </h4>
        <div class="json-content collapsed" data-json-viewer-target="container">
          <%= render 'shared/json_viewer', data: span.input_context, field: 'input_context' %>
        </div>
      </div>
    <% end %>

    <!-- Output Context -->
    <% if span.output_context.present? %>
      <div class="json-section">
        <h4 class="section-header">
          <button type="button" class="toggle-btn" data-action="json-viewer#toggle">
            <span class="toggle-icon">▶</span>
            Output Context
          </button>
          <span class="data-size"><%= data_size(span.output_context) %></span>
        </h4>
        <div class="json-content collapsed" data-json-viewer-target="container">
          <%= render 'shared/json_viewer', data: span.output_context, field: 'output_context' %>
        </div>
      </div>
    <% end %>

    <!-- Chat Messages -->
    <% if span.chat_messages.present? %>
      <div class="json-section">
        <h4 class="section-header">
          <button type="button" class="toggle-btn" data-action="json-viewer#toggle">
            <span class="toggle-icon">▶</span>
            Chat Messages (<%= span.chat_messages.length %>)
          </button>
        </h4>
        <div class="json-content collapsed" data-json-viewer-target="container">
          <%= render 'shared/json_viewer', data: span.chat_messages, field: 'chat_messages' %>
        </div>
      </div>
    <% end %>

    <!-- Execution Metadata -->
    <% if span.execution_metadata.present? %>
      <div class="json-section">
        <h4 class="section-header">
          <button type="button" class="toggle-btn" data-action="json-viewer#toggle">
            <span class="toggle-icon">▶</span>
            Execution Metadata
          </button>
        </h4>
        <div class="json-content collapsed" data-json-viewer-target="container">
          <%= render 'shared/json_viewer', data: span.execution_metadata, field: 'execution_metadata' %>
        </div>
      </div>
    <% end %>
  </div>
</div>
```

### JSON Viewer Partial

```erb
<!-- app/views/raaf/tracing/shared/_json_viewer.html.erb -->
<div class="json-viewer" data-field="<%= field %>">
  <div class="json-toolbar">
    <button type="button" class="copy-btn" data-action="json-viewer#copy" 
            data-clipboard-target="<%= dom_id(data, field) %>">
      Copy JSON
    </button>
  </div>
  
  <pre class="json-content" id="<%= dom_id(data, field) %>"><code class="language-json"><%= JSON.pretty_generate(data) %></code></pre>
</div>
```

## JavaScript Specifications

### JSON Viewer Stimulus Controller

```javascript
// app/assets/javascripts/raaf/tracing/json_viewer_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "toggle"]
  static values = { 
    spanId: String,
    autoExpand: Boolean 
  }

  connect() {
    this.initializeSyntaxHighlighting()
    if (this.autoExpandValue) {
      this.expandAll()
    }
  }

  toggle(event) {
    const section = event.target.closest('.json-section')
    const content = section.querySelector('.json-content')
    const icon = section.querySelector('.toggle-icon')
    
    if (content.classList.contains('collapsed')) {
      content.classList.remove('collapsed')
      icon.textContent = '▼'
      this.loadJsonContent(section)
    } else {
      content.classList.add('collapsed')
      icon.textContent = '▶'
    }
  }

  expandAll() {
    this.containerTargets.forEach(container => {
      const section = container.closest('.json-section')
      container.classList.remove('collapsed')
      section.querySelector('.toggle-icon').textContent = '▼'
      this.loadJsonContent(section)
    })
  }

  collapseAll() {
    this.containerTargets.forEach(container => {
      const section = container.closest('.json-section')
      container.classList.add('collapsed') 
      section.querySelector('.toggle-icon').textContent = '▶'
    })
  }

  copy(event) {
    const targetId = event.target.dataset.clipboardTarget
    const element = document.getElementById(targetId)
    
    if (navigator.clipboard) {
      navigator.clipboard.writeText(element.textContent).then(() => {
        this.showCopyFeedback(event.target)
      })
    } else {
      // Fallback for older browsers
      this.legacyCopy(element, event.target)
    }
  }

  // Private methods

  loadJsonContent(section) {
    const content = section.querySelector('.json-content')
    if (content.dataset.loaded) return

    const field = section.dataset.field
    const url = `/tracing/json_data/span/${this.spanIdValue}/${field}`
    
    fetch(url)
      .then(response => response.json())
      .then(data => {
        content.innerHTML = this.formatJsonContent(data.formatted)
        content.dataset.loaded = 'true'
        this.highlightSyntax(content)
      })
      .catch(error => {
        content.innerHTML = `<div class="error">Failed to load data: ${error.message}</div>`
      })
  }

  formatJsonContent(jsonString) {
    return `<pre class="json-syntax"><code class="language-json">${this.escapeHtml(jsonString)}</code></pre>`
  }

  initializeSyntaxHighlighting() {
    if (window.Prism) {
      window.Prism.highlightAllUnder(this.element)
    }
  }

  highlightSyntax(element) {
    if (window.Prism) {
      window.Prism.highlightAllUnder(element)
    }
  }

  showCopyFeedback(button) {
    const originalText = button.textContent
    button.textContent = 'Copied!'
    button.classList.add('copied')
    
    setTimeout(() => {
      button.textContent = originalText
      button.classList.remove('copied')
    }, 1500)
  }

  legacyCopy(element, button) {
    const selection = window.getSelection()
    const range = document.createRange()
    range.selectNodeContents(element)
    selection.removeAllRanges()
    selection.addRange(range)
    
    try {
      document.execCommand('copy')
      this.showCopyFeedback(button)
    } catch (err) {
      console.warn('Copy failed:', err)
    }
    
    selection.removeAllRanges()
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
```

## CSS Specifications

### Enhanced UI Styles

```scss
// app/assets/stylesheets/raaf/tracing/enhanced_ui.scss
.enhanced-traces-dashboard {
  min-height: 100vh;
  background: #f8f9fa;
  
  .dashboard-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 2rem 0;
    margin-bottom: 2rem;
    border-bottom: 1px solid #e9ecef;
    
    h1 {
      margin: 0;
      color: #2c3e50;
      font-weight: 600;
    }
    
    .stats-summary {
      display: flex;
      gap: 1rem;
      
      .stat {
        padding: 0.5rem 1rem;
        background: white;
        border-radius: 6px;
        border: 1px solid #dee2e6;
        font-weight: 500;
        color: #6c757d;
      }
    }
  }
}

.traces-table-container {
  background: white;
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  overflow: hidden;
}

.traces-table {
  width: 100%;
  border-collapse: collapse;
  
  thead {
    background: #f8f9fa;
    border-bottom: 2px solid #dee2e6;
    
    th {
      padding: 1rem;
      text-align: left;
      font-weight: 600;
      color: #495057;
    }
  }
  
  tbody tr {
    border-bottom: 1px solid #dee2e6;
    transition: background-color 0.2s;
    
    &:hover {
      background: #f8f9fa;
    }
  }
  
  td {
    padding: 1rem;
    vertical-align: middle;
  }
}

.agent-pills {
  display: flex;
  flex-wrap: wrap;
  gap: 0.25rem;
}

.agent-pill {
  display: inline-block;
  padding: 0.25rem 0.5rem;
  background: #e3f2fd;
  color: #1976d2;
  border-radius: 12px;
  font-size: 0.75rem;
  font-weight: 500;
}

.status-badge {
  padding: 0.25rem 0.75rem;
  border-radius: 12px;
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  
  &.status-completed {
    background: #d4edda;
    color: #155724;
  }
  
  &.status-failed {
    background: #f8d7da;
    color: #721c24;
  }
  
  &.status-running {
    background: #fff3cd;
    color: #856404;
  }
}
```

### JSON Viewer Styles

```scss
// app/assets/stylesheets/raaf/tracing/json_viewer.scss
.agent-card {
  background: white;
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  margin-bottom: 1.5rem;
  overflow: hidden;
  
  .agent-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1.5rem;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    
    .agent-name {
      margin: 0;
      font-size: 1.25rem;
      font-weight: 600;
    }
    
    .agent-meta {
      display: flex;
      gap: 1rem;
      font-size: 0.875rem;
      opacity: 0.9;
    }
  }
}

.json-sections {
  .json-section {
    border-bottom: 1px solid #e9ecef;
    
    &:last-child {
      border-bottom: none;
    }
  }
  
  .section-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1rem 1.5rem;
    margin: 0;
    background: #f8f9fa;
    border: none;
    cursor: pointer;
    font-weight: 600;
    color: #495057;
    
    .toggle-btn {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      background: none;
      border: none;
      color: inherit;
      font: inherit;
      cursor: pointer;
      
      &:hover {
        color: #007bff;
      }
    }
    
    .toggle-icon {
      transition: transform 0.2s;
      color: #6c757d;
    }
    
    .data-size {
      font-size: 0.75rem;
      color: #6c757d;
      font-weight: 400;
    }
  }
}

.json-content {
  max-height: 600px;
  overflow: auto;
  
  &.collapsed {
    display: none;
  }
  
  .json-toolbar {
    display: flex;
    justify-content: flex-end;
    padding: 0.5rem;
    background: #f8f9fa;
    border-bottom: 1px solid #dee2e6;
    
    .copy-btn {
      padding: 0.25rem 0.75rem;
      background: #007bff;
      color: white;
      border: none;
      border-radius: 4px;
      font-size: 0.75rem;
      cursor: pointer;
      transition: background-color 0.2s;
      
      &:hover {
        background: #0056b3;
      }
      
      &.copied {
        background: #28a745;
      }
    }
  }
}

.json-viewer {
  pre {
    margin: 0;
    padding: 1rem;
    background: #f8f9fa;
    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
    font-size: 0.875rem;
    line-height: 1.4;
    white-space: pre-wrap;
    word-wrap: break-word;
  }
  
  // Syntax highlighting colors
  .token {
    &.property {
      color: #0451a5;
    }
    
    &.string {
      color: #a31515;
    }
    
    &.number {
      color: #09885a;
    }
    
    &.boolean {
      color: #0000ff;
    }
    
    &.null {
      color: #0451a5;
      font-weight: bold;
    }
    
    &.punctuation {
      color: #393a34;
    }
  }
}

// Responsive design
@media (max-width: 768px) {
  .agent-header {
    flex-direction: column;
    align-items: flex-start;
    gap: 0.5rem;
  }
  
  .traces-table {
    font-size: 0.875rem;
    
    th, td {
      padding: 0.75rem 0.5rem;
    }
  }
  
  .json-content pre {
    font-size: 0.75rem;
    padding: 0.75rem;
  }
}
```

## Helper Methods

```ruby
# app/helpers/raaf/tracing/enhanced_traces_helper.rb
module RAAF::Tracing::EnhancedTracesHelper
  def duration_display(duration_ms)
    return 'N/A' if duration_ms.nil?
    
    if duration_ms < 1000
      "#{duration_ms}ms"
    elsif duration_ms < 60000
      "#{(duration_ms / 1000.0).round(2)}s"
    else
      minutes = (duration_ms / 60000).floor
      seconds = ((duration_ms % 60000) / 1000.0).round(1)
      "#{minutes}m #{seconds}s"
    end
  end
  
  def data_size(data)
    size = data.to_json.bytesize
    
    if size < 1024
      "#{size} B"
    elsif size < 1024 * 1024
      "#{(size / 1024.0).round(1)} KB"
    else
      "#{(size / (1024.0 * 1024.0)).round(2)} MB"
    end
  end
  
  def time_tag_with_tooltip(time, format: :short)
    time_tag time, format: format, title: time.iso8601
  end
end
```

## Routing Configuration

```ruby
# config/routes.rb (within engine)
RAAF::Tracing::Engine.routes.draw do
  resources :enhanced_traces, only: [:index, :show] do
    collection do
      get :search
    end
  end
  
  get 'json_data/span/:span_id/:field', to: 'json_data#show', as: :json_data
  
  # Keep existing routes
  resources :traces, only: [:index, :show]
  resources :spans, only: [:show]
end
```
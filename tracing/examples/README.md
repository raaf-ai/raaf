# Visualization Examples

This directory contains examples demonstrating visualization capabilities for RAAF (Ruby AI Agents Factory).

## Example Status

✅ = Working example  

## Visualization Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `workflow_visualization_example.rb` | ✅ | Workflow and agent visualization | Fully working |

## Running Examples

### Prerequisites

1. Set your OpenAI API key:
   ```bash
   export OPENAI_API_KEY="your-api-key"
   ```

2. Install required gems:
   ```bash
   bundle install
   ```

3. Optional: Install visualization dependencies:
   ```bash
   # For graph generation
   gem install graphviz
   
   # For chart generation
   gem install gruff
   ```

### Running Visualization Examples

```bash
# Workflow visualization
ruby visualization/examples/workflow_visualization_example.rb
```

## Visualization Features

### Workflow Visualization
- **Agent flow diagrams**: Visualize agent interactions
- **Execution paths**: Show conversation flows
- **Decision trees**: Display agent decision making
- **Timeline views**: Show execution over time

### Performance Visualization
- **Response time charts**: Track performance metrics
- **Usage analytics**: Visualize usage patterns
- **Cost tracking**: Monitor spending trends
- **Error rate graphs**: Track system health

### Conversation Visualization
- **Message flows**: Show conversation structure
- **Tool usage**: Visualize tool interactions
- **Context evolution**: Show how context changes
- **Handoff patterns**: Display agent handoffs

## Visualization Types

### Flow Diagrams
```ruby
visualizer = RAAF::Visualization::FlowDiagrammer.new
diagram = visualizer.create_flow_diagram(agent_workflow)
diagram.save("workflow.svg")
```

### Performance Charts
```ruby
chart_generator = RAAF::Visualization::ChartGenerator.new
chart = chart_generator.performance_chart(performance_data)
chart.render("performance.png")
```

### Interactive Dashboards
```ruby
dashboard = RAAF::Visualization::Dashboard.new
dashboard.add_chart(:performance, performance_chart)
dashboard.add_diagram(:workflow, flow_diagram)
dashboard.generate("dashboard.html")
```

## Graph Types

### Agent Flow Graphs
- **Node types**: Agents, tools, decisions, outcomes
- **Edge types**: Messages, handoffs, data flow
- **Layout algorithms**: Hierarchical, force-directed, circular
- **Styling**: Colors, shapes, annotations

### Timeline Visualizations
- **Execution timeline**: Show when things happen
- **Performance timeline**: Track metrics over time
- **User interaction timeline**: Show user engagement
- **System timeline**: Display system events

### Network Diagrams
- **Agent networks**: Show agent relationships
- **Tool dependencies**: Display tool usage patterns
- **Data flow**: Visualize information flow
- **System architecture**: Show component relationships

## Output Formats

### Static Images
- **PNG**: High-quality raster images
- **SVG**: Scalable vector graphics
- **PDF**: Print-ready documents
- **EPS**: Professional graphics format

### Interactive Formats
- **HTML**: Interactive web visualizations
- **D3.js**: Dynamic, interactive charts
- **JSON**: Data for custom visualizations
- **CSV**: Tabular data export

### Animated Formats
- **GIF**: Simple animations
- **MP4**: Video recordings
- **WebM**: Web-optimized videos
- **Interactive timelines**: Scrubber controls

## Customization

### Styling
```ruby
style = RAAF::Visualization::Style.new do |s|
  s.agent_color = "#4CAF50"
  s.tool_color = "#2196F3"
  s.error_color = "#F44336"
  s.font_family = "Arial"
  s.font_size = 12
end

visualizer.apply_style(style)
```

### Layout Options
```ruby
layout = RAAF::Visualization::Layout.new do |l|
  l.algorithm = :hierarchical
  l.direction = :top_to_bottom
  l.spacing = 50
  l.margin = 20
end

diagram.apply_layout(layout)
```

### Custom Renderers
```ruby
class CustomRenderer < RAAF::Visualization::Renderer
  def render_agent(agent)
    # Custom agent rendering logic
  end
  
  def render_connection(from, to)
    # Custom connection rendering
  end
end

visualizer.renderer = CustomRenderer.new
```

## Integration

### Web Applications
```ruby
# Generate visualizations for web display
class VisualizationController < ApplicationController
  def workflow
    diagram = generate_workflow_diagram(params[:agent_id])
    render json: { svg: diagram.to_svg }
  end
  
  def performance
    chart = generate_performance_chart(params[:timeframe])
    send_data chart.to_png, type: 'image/png'
  end
end
```

### API Integration
```ruby
# REST API for visualizations
post '/api/visualizations/workflow' do
  data = JSON.parse(request.body.read)
  diagram = create_workflow_diagram(data)
  content_type 'image/svg+xml'
  diagram.to_svg
end
```

### Real-time Updates
```ruby
# WebSocket updates for live visualizations
class VisualizationChannel < ApplicationCable::Channel
  def subscribed
    stream_from "visualization_#{params[:agent_id]}"
  end
  
  def update_visualization(data)
    updated_diagram = regenerate_diagram(data)
    ActionCable.server.broadcast(
      "visualization_#{params[:agent_id]}",
      { diagram: updated_diagram.to_json }
    )
  end
end
```

## Performance Considerations

### Optimization
- **Lazy loading**: Generate visualizations on demand
- **Caching**: Cache generated visualizations
- **Compression**: Optimize file sizes
- **Progressive loading**: Load large diagrams progressively

### Scalability
- **Background processing**: Generate large visualizations asynchronously
- **CDN integration**: Serve static visualizations from CDN
- **Memory management**: Handle large datasets efficiently
- **Parallel processing**: Generate multiple visualizations concurrently

## Notes

- Visualization tools help understand complex agent workflows
- Multiple output formats support different use cases
- Interactive features enhance user experience
- Performance optimization is important for large datasets
- Check individual example files for detailed implementation patterns
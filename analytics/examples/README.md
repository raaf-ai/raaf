# Analytics Examples

This directory contains examples demonstrating analytics capabilities for RAAF (Ruby AI Agents Factory).

## Example Status

✅ = Working example  

## Analytics Examples

| Example | Status | Description | Notes |
|---------|--------|-------------|-------|
| `ai_analyzer_example.rb` | ✅ | AI-powered analytics | Fully working |
| `natural_language_query_example.rb` | ✅ | Natural language data queries | Fully working |

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

### Running Analytics Examples

```bash
# AI analyzer
ruby analytics/examples/ai_analyzer_example.rb

# Natural language queries
ruby analytics/examples/natural_language_query_example.rb
```

## Analytics Features

### AI-Powered Analysis
- **Pattern detection**: Identify trends in agent interactions
- **Performance insights**: Analyze agent effectiveness
- **Usage analytics**: Track feature utilization
- **Quality metrics**: Measure output quality

### Natural Language Queries
- **Conversational analytics**: Query data using natural language
- **Dynamic filtering**: Filter results based on criteria
- **Aggregation**: Summarize data across dimensions
- **Visualization**: Generate charts and graphs

### Data Processing
- **Real-time analysis**: Process data as it's generated
- **Batch processing**: Analyze historical data
- **Data export**: Export results in various formats
- **Integration**: Connect to existing analytics tools

## Analytics Patterns

### Basic Analysis
```ruby
analyzer = RAAF::Analytics::AIAnalyzer.new
analyzer.add_data_source(:agent_interactions, interactions)
analyzer.add_data_source(:performance_metrics, metrics)

insights = analyzer.analyze("What are the performance trends?")
puts insights.summary
```

### Natural Language Queries
```ruby
query_engine = RAAF::Analytics::NLQueryEngine.new
query_engine.connect_to(:database, connection)

result = query_engine.query("Show me agent performance last week")
puts result.to_table
```

### Custom Metrics
```ruby
analyzer.define_metric(:success_rate) do |data|
  successful = data.count { |d| d[:success] }
  total = data.length
  (successful.to_f / total * 100).round(2)
end

rate = analyzer.calculate(:success_rate)
```

## Analytics Types

### Performance Analytics
- **Response times**: Track agent response latency
- **Success rates**: Measure task completion rates
- **Error analysis**: Identify common failure patterns
- **Resource usage**: Monitor computational resources

### Usage Analytics
- **Feature adoption**: Track which features are used
- **User patterns**: Understand user behavior
- **Peak usage times**: Identify high-traffic periods
- **Geographic distribution**: Analyze usage by location

### Quality Analytics
- **Output quality**: Assess response quality
- **User satisfaction**: Track user feedback
- **Accuracy metrics**: Measure task accuracy
- **Improvement trends**: Track quality over time

### Business Analytics
- **Cost analysis**: Track operational costs
- **ROI calculation**: Measure return on investment
- **Efficiency gains**: Quantify productivity improvements
- **Compliance metrics**: Monitor regulatory compliance

## Visualization

### Chart Generation
```ruby
chart = analyzer.create_chart(:line) do |c|
  c.title = "Agent Performance Over Time"
  c.x_axis = :timestamp
  c.y_axis = :response_time
  c.data = performance_data
end

chart.save("performance_chart.png")
```

### Dashboard Creation
```ruby
dashboard = RAAF::Analytics::Dashboard.new
dashboard.add_widget(:performance_chart, chart)
dashboard.add_widget(:usage_metrics, metrics_widget)
dashboard.add_widget(:alerts, alerts_widget)

dashboard.generate("analytics_dashboard.html")
```

## Integration

### External Analytics
- **Google Analytics**: Web analytics integration
- **Mixpanel**: Event tracking and analysis
- **DataDog**: Infrastructure and application monitoring
- **Custom APIs**: Connect to proprietary systems

### Data Export
- **CSV export**: Tabular data export
- **JSON export**: Structured data export
- **PDF reports**: Formatted report generation
- **API endpoints**: Real-time data access

## Notes

- Analytics tools provide actionable insights
- Natural language querying makes data accessible
- Visualization helps communicate findings
- Integration with existing tools is seamless
- Check individual example files for detailed usage patterns
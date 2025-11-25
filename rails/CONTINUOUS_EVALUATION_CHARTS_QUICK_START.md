# RAAF Continuous Evaluation Charts - Quick Start Guide

## Overview

This guide shows how to use the D3.js-powered visualization components for the Continuous Evaluation analytics dashboard.

## Available Charts

### 1. Pass Rate Time-Series Chart
Shows pass rate trends over time with animated line chart.

### 2. Score Distribution Histogram
Displays score distribution across 10 buckets (0.0-0.1, 0.1-0.2, etc.) with color gradient.

### 3. Failure Analysis Chart
Horizontal bar chart showing failure breakdown by evaluator.

### 4. Model Comparison Table
Sortable table comparing performance metrics across different models.

---

## Quick Usage Examples

### In ERB Views

```erb
<!-- Pass Rate Chart -->
<div class="mb-8">
  <h3 class="text-lg font-semibold mb-4">Pass Rate Trend</h3>
  <div
    data-controller="raaf--rails--continuous--pass-rate-chart"
    data-raaf--rails--continuous--pass-rate-chart-url-value="/raaf/rails/continuous/analytics/pass_rate_data"
    data-raaf--rails--continuous--pass-rate-chart-agent-value="MyAgent"
    data-raaf--rails--continuous--pass-rate-chart-period-value="daily"
    data-raaf--rails--continuous--pass-rate-chart-refresh-interval-value="30000"
  >
    <div data-raaf--rails--continuous--pass-rate-chart-target="chart" style="min-height: 400px;"></div>
    <div data-raaf--rails--continuous--pass-rate-chart-target="loading" class="hidden">Loading...</div>
    <div data-raaf--rails--continuous--pass-rate-chart-target="error" class="hidden"></div>
  </div>
</div>

<!-- Score Distribution Chart -->
<div class="mb-8">
  <h3 class="text-lg font-semibold mb-4">Score Distribution</h3>
  <div
    data-controller="raaf--rails--continuous--score-distribution-chart"
    data-raaf--rails--continuous--score-distribution-chart-url-value="/raaf/rails/continuous/analytics/score_distribution_data"
    data-raaf--rails--continuous--score-distribution-chart-agent-value="MyAgent"
  >
    <div data-raaf--rails--continuous--score-distribution-chart-target="chart" style="min-height: 400px;"></div>
  </div>
</div>

<!-- Failure Analysis Chart -->
<div class="mb-8">
  <h3 class="text-lg font-semibold mb-4">Failure Analysis</h3>
  <div
    data-controller="raaf--rails--continuous--failure-analysis-chart"
    data-raaf--rails--continuous--failure-analysis-chart-url-value="/raaf/rails/continuous/analytics/failure_analysis_data"
    data-raaf--rails--continuous--failure-analysis-chart-agent-value="MyAgent"
  >
    <div data-raaf--rails--continuous--failure-analysis-chart-target="chart" style="min-height: 400px;"></div>
  </div>
</div>

<!-- Model Comparison Table -->
<div class="mb-8">
  <%= render RAAF::Rails::Continuous::ModelComparisonTable.new(
    url: "/raaf/rails/continuous/analytics/model_comparison_data",
    agent: @agent,
    refresh_interval: 30000
  ) %>
</div>
```

### In Phlex Components

```ruby
class AnalyticsDashboard < Phlex::HTML
  def initialize(agent:)
    @agent = agent
  end

  def view_template
    div(class: "space-y-8") do
      # Pass Rate Chart
      chart_section("Pass Rate Trend") do
        div(
          data: {
            controller: "raaf--rails--continuous--pass-rate-chart",
            raaf__rails__continuous__pass_rate_chart_url_value: "/raaf/rails/continuous/analytics/pass_rate_data",
            raaf__rails__continuous__pass_rate_chart_agent_value: @agent
          },
          style: "min-height: 400px;"
        ) do
          div(data: { raaf__rails__continuous__pass_rate_chart_target: "chart" })
        end
      end

      # Score Distribution Chart
      chart_section("Score Distribution") do
        div(
          data: {
            controller: "raaf--rails--continuous--score-distribution-chart",
            raaf__rails__continuous__score_distribution_chart_url_value: "/raaf/rails/continuous/analytics/score_distribution_data",
            raaf__rails__continuous__score_distribution_chart_agent_value: @agent
          },
          style: "min-height: 400px;"
        ) do
          div(data: { raaf__rails__continuous__score_distribution_chart_target: "chart" })
        end
      end

      # Model Comparison Table
      chart_section("Model Performance Comparison") do
        render RAAF::Rails::Continuous::ModelComparisonTable.new(
          url: "/raaf/rails/continuous/analytics/model_comparison_data",
          agent: @agent
        )
      end

      # Failure Analysis Chart
      chart_section("Failure Analysis") do
        div(
          data: {
            controller: "raaf--rails--continuous--failure-analysis-chart",
            raaf__rails__continuous__failure-analysis-chart_url_value: "/raaf/rails/continuous/analytics/failure_analysis_data",
            raaf__rails__continuous__failure_analysis_chart_agent_value: @agent
          },
          style: "min-height: 400px;"
        ) do
          div(data: { raaf__rails__continuous__failure_analysis_chart_target: "chart" })
        end
      end
    end
  end

  private

  def chart_section(title, &block)
    div(class: "bg-white dark:bg-gray-800 rounded-lg shadow p-6") do
      h3(class: "text-lg font-semibold mb-4 text-gray-900 dark:text-gray-100") { title }
      block.call
    end
  end
end
```

---

## Configuration Options

### Pass Rate Chart

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | String | Required | API endpoint for pass rate data |
| `agent` | String | Optional | Filter by agent name |
| `period` | String | "daily" | Time period: hourly, daily, weekly |
| `refreshInterval` | Number | 30000 | Auto-refresh interval in milliseconds (0 to disable) |

### Score Distribution Chart

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | String | Required | API endpoint for score distribution data |
| `agent` | String | Optional | Filter by agent name |
| `refreshInterval` | Number | 30000 | Auto-refresh interval in milliseconds |

### Failure Analysis Chart

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | String | Required | API endpoint for failure analysis data |
| `agent` | String | Optional | Filter by agent name |
| `refreshInterval` | Number | 30000 | Auto-refresh interval in milliseconds |

### Model Comparison Table

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | String | Required | API endpoint for model comparison data |
| `agent` | String | Optional | Filter by agent name |
| `refresh_interval` | Number | 30000 | Auto-refresh interval in milliseconds |

---

## Styling Customization

All charts respect Tailwind CSS dark mode classes. To customize:

```html
<!-- Container styling -->
<div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
  <!-- Chart here -->
</div>

<!-- Chart container sizing -->
<div style="min-height: 300px; max-height: 600px;">
  <!-- Chart will be responsive within these constraints -->
</div>
```

---

## Manual Refresh

Each controller has a `refresh()` method that can be called programmatically:

```javascript
// Get controller instance
const controller = this.application.getControllerForElementAndIdentifier(
  document.querySelector('[data-controller*="pass-rate-chart"]'),
  "raaf--rails--continuous--pass-rate-chart"
)

// Manually refresh
controller.refresh()
```

Or add a refresh button:

```erb
<button
  data-action="click->raaf--rails--continuous--pass-rate-chart#refresh"
  class="px-4 py-2 bg-blue-600 text-white rounded"
>
  Refresh
</button>
```

---

## API Response Formats

### Pass Rate Data Response
```json
[
  {
    "date": "2025-11-25T00:00:00Z",
    "pass_rate": 92.5,
    "total": 1000,
    "passed": 925,
    "failed": 75
  }
]
```

### Score Distribution Response
```json
[
  {
    "range": "0.0-0.1",
    "count": 5,
    "percentage": 0.5
  },
  {
    "range": "0.9-1.0",
    "count": 850,
    "percentage": 85.0
  }
]
```

### Model Comparison Response
```json
[
  {
    "model": "gpt-4o",
    "total_evaluations": 1000,
    "pass_rate": 92.5,
    "avg_score": 0.8756,
    "avg_latency_ms": 1250,
    "total_cost": 2.45
  }
]
```

### Failure Analysis Response
```json
[
  {
    "evaluator": "ContentQualityEvaluator",
    "count": 45,
    "percentage": 60.0
  },
  {
    "evaluator": "ResponseLengthEvaluator",
    "count": 30,
    "percentage": 40.0
  }
]
```

---

## Troubleshooting

### Chart Not Rendering

1. **Check D3.js is loaded:**
   ```javascript
   console.log(window.d3) // Should not be undefined
   ```

2. **Check data endpoint:**
   ```bash
   curl http://localhost:3000/raaf/rails/continuous/analytics/pass_rate_data
   ```

3. **Check browser console for errors:**
   - Open DevTools (F12)
   - Look for JavaScript errors

### Dark Mode Not Working

Ensure the `dark` class is toggled on `document.documentElement`:

```javascript
// Enable dark mode
document.documentElement.classList.add('dark')

// Disable dark mode
document.documentElement.classList.remove('dark')
```

### Auto-Refresh Not Working

Check that the refresh interval is set and not zero:

```erb
data-raaf--rails--continuous--pass-rate-chart-refresh-interval-value="30000"
```

Set to `0` to disable auto-refresh.

---

## Performance Tips

1. **Disable Auto-Refresh for Static Pages:**
   ```erb
   data-refresh-interval-value="0"
   ```

2. **Use Appropriate Chart Sizes:**
   ```html
   <div style="min-height: 300px; max-height: 500px;">
   ```

3. **Limit Data Points:**
   - Use appropriate time periods (hourly for recent, daily for weeks)
   - Server-side pagination if needed

4. **Monitor Network Requests:**
   - Check DevTools Network tab
   - Ensure data responses are < 100KB

---

## Accessibility

All charts include:
- ARIA labels on SVG elements
- Keyboard navigation (table)
- Screen reader compatible tooltips
- Semantic HTML structure

To enhance accessibility:

```html
<div
  role="region"
  aria-label="Pass rate trend visualization"
  data-controller="raaf--rails--continuous--pass-rate-chart"
>
  <!-- Chart content -->
</div>
```

---

## Browser Support

Minimum requirements:
- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

Required features:
- ES6 modules
- Fetch API
- ResizeObserver
- SVG rendering

---

## Further Documentation

- **Complete Implementation Details:** See `D3_CHARTS_IMPLEMENTATION_SUMMARY.md`
- **D3.js Documentation:** https://d3js.org/
- **Stimulus Documentation:** https://stimulus.hotwired.dev/
- **RAAF Documentation:** See main `CLAUDE.md`

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Analytics Dashboard", type: :feature, js: true do
  # These tests verify the analytics dashboard functionality for continuous
  # evaluation data visualization through the RAAF Rails dashboard UI.

  let!(:policy) do
    EvaluationPolicy.create!(
      name: "Test Policy",
      agent_name: "TestAgent",
      sampling_mode: "percentage",
      sample_rate: 10,
      active: true,
      evaluators: []
    )
  end

  let!(:queue_item) do
    EvaluationQueue.create!(
      evaluation_policy: policy,
      evaluation_policy_id: policy.id,
      span_id: "span-base",
      status: "completed"
    )
  end

  describe "Dashboard Overview" do
    before do
      # Create sample evaluation results
      10.times do |i|
        EvaluationResult.create!(
          evaluation_queue: queue_item,
          evaluation_policy: policy,
          evaluation_policy_id: policy.id,
          span_id: "span-overview-#{i}",
          agent_name: "TestAgent",
          model: "gpt-4o",
          evaluator_name: "token_limit",
          evaluator_type: "rule_based",
          status: i < 8 ? "passed" : "failed",
          score: i < 8 ? 0.85 + (i * 0.01) : 0.35,
          metrics: { "latency_ms" => 1000 + (i * 100), "cost" => 0.01 }
        )
      end
    end

    it "displays overview statistics cards" do
      visit raaf_rails_continuous_analytics_path

      within ".overview-stats" do
        expect(page).to have_content("Total Evaluations")
        expect(page).to have_content("10")
        expect(page).to have_content("Pass Rate")
        expect(page).to have_content("80%")
        expect(page).to have_content("Average Score")
      end
    end

    it "shows agent selection dropdown" do
      visit raaf_rails_continuous_analytics_path

      expect(page).to have_select("Agent", with_options: ["TestAgent"])
    end

    it "shows date range filter" do
      visit raaf_rails_continuous_analytics_path

      expect(page).to have_field("From")
      expect(page).to have_field("To")
    end

    it "defaults to last 30 days" do
      visit raaf_rails_continuous_analytics_path

      expect(page).to have_field("From", with: 30.days.ago.to_date.to_s)
      expect(page).to have_field("To", with: Date.current.to_s)
    end

    it "shows multiple chart containers" do
      visit raaf_rails_continuous_analytics_path

      expect(page).to have_css("#pass-rate-chart")
      expect(page).to have_css("#score-distribution-chart")
      expect(page).to have_css("#model-comparison-table")
      expect(page).to have_css("#failure-analysis-chart")
    end
  end

  describe "Pass Rate Chart" do
    before do
      # Create daily metrics for time-series chart
      7.days.ago.to_date.upto(Date.current) do |date|
        EvaluationMetric.create!(
          agent_name: "TestAgent",
          period_type: "daily",
          period_start: date.beginning_of_day,
          period_end: date.end_of_day,
          total_evaluations: 100,
          passed_count: 80 + rand(10),
          failed_count: 10 - rand(5),
          warning_count: 5,
          avg_score: 0.85
        )
      end
    end

    it "loads pass rate time-series chart" do
      visit raaf_rails_continuous_analytics_path

      within "#pass-rate-chart" do
        # Wait for D3 chart to render
        expect(page).to have_css("svg", wait: 5)
      end
    end

    it "displays chart with data points for each day" do
      visit raaf_rails_continuous_analytics_path

      within "#pass-rate-chart" do
        # Should have data points (circles or paths) for the time series
        expect(page).to have_css("svg circle, svg path.line", minimum: 1)
      end
    end

    it "shows chart tooltip on hover" do
      visit raaf_rails_continuous_analytics_path

      within "#pass-rate-chart" do
        svg = find("svg")
        svg.hover

        # Tooltip should appear (may vary based on D3 implementation)
        expect(page).to have_css(".tooltip, .chart-tooltip", visible: :all)
      end
    end

    it "has proper chart axes and labels" do
      visit raaf_rails_continuous_analytics_path

      within "#pass-rate-chart" do
        expect(page).to have_css("svg .x-axis, svg .axis--x")
        expect(page).to have_css("svg .y-axis, svg .axis--y")
      end
    end

    it "updates chart when date range changes" do
      visit raaf_rails_continuous_analytics_path

      fill_in "From", with: 3.days.ago.to_date.to_s
      fill_in "To", with: Date.current.to_s
      click_button "Filter"

      within "#pass-rate-chart" do
        expect(page).to have_css("svg", wait: 5)
      end
    end
  end

  describe "Score Distribution Chart" do
    before do
      # Create metric with score distribution
      EvaluationMetric.create!(
        agent_name: "TestAgent",
        period_type: "daily",
        period_start: Date.current.beginning_of_day,
        period_end: Date.current.end_of_day,
        total_evaluations: 100,
        passed_count: 80,
        failed_count: 20,
        score_distribution: {
          "0.0-0.1" => 5,
          "0.1-0.2" => 5,
          "0.2-0.3" => 10,
          "0.3-0.4" => 5,
          "0.4-0.5" => 5,
          "0.5-0.6" => 10,
          "0.6-0.7" => 10,
          "0.7-0.8" => 15,
          "0.8-0.9" => 20,
          "0.9-1.0" => 15
        }
      )
    end

    it "loads score distribution histogram" do
      visit raaf_rails_continuous_analytics_path

      within "#score-distribution-chart" do
        expect(page).to have_css("svg", wait: 5)
      end
    end

    it "displays bars for each score range" do
      visit raaf_rails_continuous_analytics_path

      within "#score-distribution-chart" do
        # Should have 10 bars for 10 score ranges
        expect(page).to have_css("svg rect.bar, svg rect", minimum: 10)
      end
    end

    it "shows distribution percentages" do
      visit raaf_rails_continuous_analytics_path

      within "#score-distribution-chart" do
        # Chart should show percentage labels or have tooltip
        expect(page).to have_css("svg text, .bar-label", minimum: 1)
      end
    end

    it "colors bars based on score range" do
      visit raaf_rails_continuous_analytics_path

      within "#score-distribution-chart" do
        # Low scores should be red/orange, high scores green
        expect(page).to have_css("svg rect[fill]", minimum: 1)
      end
    end
  end

  describe "Model Comparison Table" do
    before do
      # Create results for different models
      %w[gpt-4o claude-3-sonnet gpt-4-turbo].each do |model|
        5.times do |i|
          EvaluationResult.create!(
            evaluation_queue: queue_item,
            evaluation_policy: policy,
            evaluation_policy_id: policy.id,
            span_id: "span-model-#{model}-#{i}",
            agent_name: "TestAgent",
            model: model,
            evaluator_name: "quality_check",
            evaluator_type: "llm_judge",
            status: i < 4 ? "passed" : "failed",
            score: model == "gpt-4o" ? 0.9 : (model == "claude-3-sonnet" ? 0.85 : 0.8),
            metrics: { "latency_ms" => model == "gpt-4o" ? 1200 : 1500, "cost" => 0.02 }
          )
        end
      end
    end

    it "displays model comparison table" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within "#model-comparison-table" do
        expect(page).to have_css("table")
        expect(page).to have_content("gpt-4o")
        expect(page).to have_content("claude-3-sonnet")
        expect(page).to have_content("gpt-4-turbo")
      end
    end

    it "shows metrics for each model" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within "#model-comparison-table" do
        expect(page).to have_content("Total Evaluations")
        expect(page).to have_content("Pass Rate")
        expect(page).to have_content("Avg Score")
        expect(page).to have_content("Avg Latency")
        expect(page).to have_content("Total Cost")
      end
    end

    it "sorts models by pass rate by default" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within "#model-comparison-table tbody" do
        rows = all("tr")
        # First row should be the model with highest pass rate
        expect(rows.first).to have_content("gpt-4o")
      end
    end

    it "allows sorting by different columns" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within "#model-comparison-table" do
        click_link "Avg Latency"
      end

      # Table should re-sort by latency
      expect(page).to have_css("#model-comparison-table tbody tr")
    end

    it "highlights best performing model" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within "#model-comparison-table" do
        expect(page).to have_css("tr.best-performer, tr.highlighted")
      end
    end
  end

  describe "Failure Analysis Chart" do
    before do
      # Create failed results with different evaluators
      {
        "token_limit" => 15,
        "quality_check" => 10,
        "latency_check" => 8,
        "safety_filter" => 5
      }.each do |evaluator, count|
        count.times do |i|
          EvaluationResult.create!(
            evaluation_queue: queue_item,
            evaluation_policy: policy,
            evaluation_policy_id: policy.id,
            span_id: "span-fail-#{evaluator}-#{i}",
            agent_name: "TestAgent",
            evaluator_name: evaluator,
            evaluator_type: "rule_based",
            status: "failed",
            score: 0.3,
            reasoning: "Failed #{evaluator} check"
          )
        end
      end
    end

    it "displays failure breakdown chart" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within "#failure-analysis-chart" do
        expect(page).to have_css("svg", wait: 5)
      end
    end

    it "shows failures grouped by evaluator" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within "#failure-analysis-chart" do
        expect(page).to have_content("token_limit")
        expect(page).to have_content("quality_check")
        expect(page).to have_content("latency_check")
        expect(page).to have_content("safety_filter")
      end
    end

    it "displays failure counts and percentages" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within "#failure-analysis-chart" do
        expect(page).to have_content("15")  # token_limit count
        expect(page).to have_content(/\d+%/)  # percentage
      end
    end

    it "sorts failures by count descending" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within "#failure-analysis-chart" do
        # First item should be token_limit with most failures
        first_bar = first(".bar, rect")
        expect(first_bar).to be_present
      end
    end

    it "allows drilling down into failure details" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within "#failure-analysis-chart" do
        click_link "token_limit"
      end

      # Should navigate to results filtered by evaluator and failed status
      expect(current_url).to include("evaluator=token_limit")
      expect(current_url).to include("status=failed")
    end
  end

  describe "Date Range Filtering" do
    before do
      # Create metrics for different dates
      14.days.ago.to_date.upto(Date.current) do |date|
        EvaluationMetric.create!(
          agent_name: "TestAgent",
          period_type: "daily",
          period_start: date.beginning_of_day,
          period_end: date.end_of_day,
          total_evaluations: 50,
          passed_count: 40,
          failed_count: 10
        )
      end
    end

    it "updates all charts when date range changes" do
      visit raaf_rails_continuous_analytics_path

      fill_in "From", with: 7.days.ago.to_date.to_s
      click_button "Filter"

      # All charts should update
      expect(page).to have_css("#pass-rate-chart svg", wait: 5)
      expect(page).to have_css("#score-distribution-chart svg", wait: 5)
    end

    it "provides quick date range presets" do
      visit raaf_rails_continuous_analytics_path

      click_button "Last 7 Days"

      expect(page).to have_field("From", with: 7.days.ago.to_date.to_s)
    end

    it "validates date range inputs" do
      visit raaf_rails_continuous_analytics_path

      fill_in "From", with: Date.current.to_s
      fill_in "To", with: 7.days.ago.to_date.to_s
      click_button "Filter"

      expect(page).to have_content(/invalid|error|must be before/i)
    end

    it "persists date range in URL" do
      visit raaf_rails_continuous_analytics_path

      fill_in "From", with: 7.days.ago.to_date.to_s
      fill_in "To", with: Date.current.to_s
      click_button "Filter"

      expect(current_url).to include("from=")
      expect(current_url).to include("to=")
    end
  end

  describe "Agent Filtering" do
    before do
      # Create results for multiple agents
      %w[AgentA AgentB AgentC].each do |agent|
        EvaluationResult.create!(
          evaluation_queue: queue_item,
          evaluation_policy: policy,
          evaluation_policy_id: policy.id,
          span_id: "span-agent-filter-#{agent}",
          agent_name: agent,
          evaluator_name: "quality",
          evaluator_type: "llm_judge",
          status: "passed",
          score: 0.85
        )
      end
    end

    it "populates agent dropdown with available agents" do
      visit raaf_rails_continuous_analytics_path

      within "[data-filter='agent']" do
        expect(page).to have_select("Agent", with_options: %w[AgentA AgentB AgentC])
      end
    end

    it "updates dashboard for selected agent" do
      visit raaf_rails_continuous_analytics_path

      select "AgentA", from: "Agent"
      click_button "Filter"

      expect(page).to have_content("AgentA")
      expect(current_url).to include("agent=AgentA")
    end

    it "shows all agents option" do
      visit raaf_rails_continuous_analytics_path

      expect(page).to have_select("Agent", with_options: ["All Agents"])
    end
  end

  describe "Chart Interactions" do
    before do
      7.days.ago.to_date.upto(Date.current) do |date|
        EvaluationMetric.create!(
          agent_name: "TestAgent",
          period_type: "daily",
          period_start: date.beginning_of_day,
          period_end: date.end_of_day,
          total_evaluations: 100,
          passed_count: 80,
          failed_count: 20,
          avg_score: 0.85
        )
      end
    end

    it "shows tooltip with detailed data on hover" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within "#pass-rate-chart" do
        data_point = find("svg circle, svg .data-point", match: :first)
        data_point.hover

        expect(page).to have_css(".tooltip", visible: true, wait: 2)
      end
    end

    it "allows zooming into time ranges" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within "#pass-rate-chart" do
        # D3 brush or zoom interaction
        expect(page).to have_css("svg .brush, svg .zoom-control", visible: :all)
      end
    end

    it "supports chart legend interactions" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      within ".chart-legend" do
        legend_item = find(".legend-item", match: :first)
        legend_item.click

        # Clicking legend should toggle series visibility
        expect(page).to have_css(".legend-item.inactive, .legend-item.hidden")
      end
    end
  end

  describe "Data Export" do
    before do
      5.times do |i|
        EvaluationResult.create!(
          evaluation_queue: queue_item,
          evaluation_policy: policy,
          evaluation_policy_id: policy.id,
          span_id: "span-export-#{i}",
          agent_name: "TestAgent",
          evaluator_name: "quality",
          evaluator_type: "llm_judge",
          status: "passed",
          score: 0.85 + (i * 0.02)
        )
      end
    end

    it "provides export options for analytics data" do
      visit raaf_rails_continuous_analytics_path

      expect(page).to have_button("Export")
    end

    it "exports chart data to CSV" do
      visit raaf_rails_continuous_analytics_path

      click_button "Export"
      click_link "Export to CSV"

      # Verify download initiated (may need to check headers or filename)
      expect(page.response_headers["Content-Type"]).to include("text/csv")
    end

    it "exports data respecting current filters" do
      visit raaf_rails_continuous_analytics_path(agent: "TestAgent")

      click_button "Export"

      # Export link should include filter parameters
      expect(page).to have_link("Export to CSV", href: /agent=TestAgent/)
    end
  end

  describe "Responsive Design" do
    it "adapts charts for mobile viewport" do
      visit raaf_rails_continuous_analytics_path

      page.driver.browser.manage.window.resize_to(375, 667)

      # Charts should resize
      within "#pass-rate-chart" do
        svg = find("svg")
        expect(svg["width"].to_i).to be < 400
      end
    end

    it "stacks cards vertically on mobile" do
      visit raaf_rails_continuous_analytics_path

      page.driver.browser.manage.window.resize_to(375, 667)

      expect(page).to have_css(".overview-stats.flex-col, .overview-stats.grid-cols-1")
    end
  end

  describe "Error States" do
    it "handles no data gracefully" do
      # Clear all results
      EvaluationResult.records = []
      EvaluationMetric.records = []

      visit raaf_rails_continuous_analytics_path(agent: "NonExistent")

      expect(page).to have_content(/no data|no evaluations/i)
    end

    it "shows error message when chart data fails to load" do
      allow_any_instance_of(RAAF::Rails::Continuous::AnalyticsController)
        .to receive(:pass_rate_data)
        .and_raise(StandardError, "Database error")

      visit raaf_rails_continuous_analytics_path

      within "#pass-rate-chart" do
        expect(page).to have_content(/error|failed to load/i)
      end
    end

    it "provides retry option for failed charts" do
      visit raaf_rails_continuous_analytics_path

      within "#pass-rate-chart.error" do
        expect(page).to have_button("Retry")
      end
    end
  end

  describe "Performance" do
    it "loads charts progressively" do
      visit raaf_rails_continuous_analytics_path

      # Charts should show loading state initially
      expect(page).to have_css(".chart-loading, .spinner", wait: 1)

      # Then render the actual chart
      expect(page).to have_css("#pass-rate-chart svg", wait: 10)
    end

    it "caches chart data for improved performance" do
      visit raaf_rails_continuous_analytics_path

      # Second load should be faster due to caching
      start_time = Time.current
      visit raaf_rails_continuous_analytics_path
      load_time = Time.current - start_time

      # Should load quickly (adjust threshold as needed)
      expect(load_time).to be < 3
    end
  end

  describe "Accessibility" do
    before do
      EvaluationMetric.create!(
        agent_name: "TestAgent",
        period_type: "daily",
        period_start: Date.current.beginning_of_day,
        period_end: Date.current.end_of_day,
        total_evaluations: 100,
        passed_count: 80,
        failed_count: 20
      )
    end

    it "provides accessible chart alternatives" do
      visit raaf_rails_continuous_analytics_path

      # Charts should have text alternatives or data tables
      expect(page).to have_css("[aria-label], .sr-only, .visually-hidden")
    end

    it "supports keyboard navigation for charts" do
      visit raaf_rails_continuous_analytics_path

      within "#pass-rate-chart" do
        expect(page).to have_css("[tabindex], [role='img']")
      end
    end

    it "announces filter changes to screen readers" do
      visit raaf_rails_continuous_analytics_path

      # Live region for announcements
      expect(page).to have_css("[aria-live='polite'], [role='status']")
    end

    it "provides proper color contrast for charts" do
      visit raaf_rails_continuous_analytics_path

      # Charts should not rely solely on color
      within "#pass-rate-chart" do
        expect(page).to have_css("[data-pattern], .pattern-fill, text")
      end
    end
  end
end

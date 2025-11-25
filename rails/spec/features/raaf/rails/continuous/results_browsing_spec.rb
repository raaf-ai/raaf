# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Results Browsing", type: :feature, js: true do
  # These tests verify the user workflow for browsing and analyzing
  # continuous evaluation results through the RAAF Rails dashboard UI.

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

  describe "Results List View" do
    before do
      # Create evaluation results with various statuses and evaluators
      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-passed-1",
        trace_id: "trace-1",
        agent_name: "TestAgent",
        model: "gpt-4o",
        evaluator_name: "token_limit",
        evaluator_type: "rule_based",
        status: "passed",
        score: 0.92,
        metrics: { "latency_ms" => 1200 }
      )

      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-failed-1",
        trace_id: "trace-2",
        agent_name: "TestAgent",
        model: "gpt-4o",
        evaluator_name: "quality_check",
        evaluator_type: "llm_judge",
        status: "failed",
        score: 0.35,
        reasoning: "Response lacks required detail"
      )

      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-warning-1",
        trace_id: "trace-3",
        agent_name: "TestAgent",
        model: "claude-3-sonnet",
        evaluator_name: "latency_check",
        evaluator_type: "rule_based",
        status: "warning",
        score: 0.65,
        metrics: { "latency_ms" => 4500 }
      )
    end

    it "displays all results with key information" do
      visit raaf_rails_continuous_results_path

      expect(page).to have_content("token_limit")
      expect(page).to have_content("quality_check")
      expect(page).to have_content("latency_check")
      expect(page).to have_css(".badge-success, .status-passed", minimum: 1)
      expect(page).to have_css(".badge-danger, .status-failed", minimum: 1)
      expect(page).to have_css(".badge-warning, .status-warning", minimum: 1)
    end

    it "shows result scores with visual indicators" do
      visit raaf_rails_continuous_results_path

      within "tbody" do
        expect(page).to have_content("0.92")
        expect(page).to have_content("0.35")
        expect(page).to have_content("0.65")
      end
    end

    it "displays evaluator type and name" do
      visit raaf_rails_continuous_results_path

      within "tbody" do
        expect(page).to have_content("rule_based")
        expect(page).to have_content("llm_judge")
      end
    end

    it "shows agent and model information" do
      visit raaf_rails_continuous_results_path

      expect(page).to have_content("TestAgent")
      expect(page).to have_content("gpt-4o")
      expect(page).to have_content("claude-3-sonnet")
    end

    it "displays summary statistics" do
      visit raaf_rails_continuous_results_path

      within ".summary-stats" do
        expect(page).to have_content("Total Results")
        expect(page).to have_content("3")
        expect(page).to have_content("Pass Rate")
        expect(page).to have_content(/\d+%/)
        expect(page).to have_content("Average Score")
      end
    end
  end

  describe "Filtering Results" do
    before do
      # Create results with different attributes for filtering
      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-filter-1",
        agent_name: "AgentA",
        evaluator_name: "token_limit",
        evaluator_type: "rule_based",
        status: "passed",
        score: 0.9
      )

      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-filter-2",
        agent_name: "AgentB",
        evaluator_name: "quality_check",
        evaluator_type: "llm_judge",
        status: "failed",
        score: 0.3
      )

      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-filter-3",
        agent_name: "AgentA",
        evaluator_name: "quality_check",
        evaluator_type: "llm_judge",
        status: "passed",
        score: 0.85
      )
    end

    context "filtering by evaluator" do
      it "filters results by evaluator name" do
        visit raaf_rails_continuous_results_path

        select "token_limit", from: "Evaluator"
        click_button "Filter"

        expect(page).to have_content("span-filter-1")
        expect(page).not_to have_content("span-filter-2")
        expect(page).not_to have_content("span-filter-3")
      end

      it "shows all results when evaluator filter is cleared" do
        visit raaf_rails_continuous_results_path(evaluator: "token_limit")

        select "All Evaluators", from: "Evaluator"
        click_button "Filter"

        expect(page).to have_content("span-filter-1")
        expect(page).to have_content("span-filter-2")
        expect(page).to have_content("span-filter-3")
      end
    end

    context "filtering by status" do
      it "filters results by passed status" do
        visit raaf_rails_continuous_results_path(status: "passed")

        expect(page).to have_content("span-filter-1")
        expect(page).to have_content("span-filter-3")
        expect(page).not_to have_content("span-filter-2")
      end

      it "filters results by failed status" do
        visit raaf_rails_continuous_results_path(status: "failed")

        expect(page).to have_content("span-filter-2")
        expect(page).not_to have_content("span-filter-1")
        expect(page).not_to have_content("span-filter-3")
      end
    end

    context "filtering by agent" do
      it "filters results by agent name" do
        visit raaf_rails_continuous_results_path(agent: "AgentA")

        expect(page).to have_content("span-filter-1")
        expect(page).to have_content("span-filter-3")
        expect(page).not_to have_content("span-filter-2")
      end

      it "populates agent dropdown with available agents" do
        visit raaf_rails_continuous_results_path

        within "[data-filter='agent']" do
          expect(page).to have_content("AgentA")
          expect(page).to have_content("AgentB")
        end
      end
    end

    context "filtering by date range" do
      before do
        # Simulate older results
        EvaluationResult.create!(
          evaluation_queue: queue_item,
          evaluation_policy: policy,
          evaluation_policy_id: policy.id,
          span_id: "span-old",
          agent_name: "OldAgent",
          evaluator_name: "token_limit",
          evaluator_type: "rule_based",
          status: "passed",
          score: 0.8
        ).tap { |r| r.instance_variable_set(:@created_at, 10.days.ago) }
      end

      it "filters results by date range" do
        visit raaf_rails_continuous_results_path

        fill_in "From", with: 1.week.ago.to_date.to_s
        fill_in "To", with: Date.current.to_s
        click_button "Filter"

        # Only recent results should appear
        expect(page).to have_content("span-filter-1")
        expect(page).not_to have_content("span-old")
      end

      it "provides date range shortcuts" do
        visit raaf_rails_continuous_results_path

        expect(page).to have_link("Last 24 hours")
        expect(page).to have_link("Last 7 days")
        expect(page).to have_link("Last 30 days")
      end

      it "applies date range shortcut" do
        visit raaf_rails_continuous_results_path

        click_link "Last 7 days"

        expect(page).to have_field("From", with: 7.days.ago.to_date.to_s)
        expect(page).to have_field("To", with: Date.current.to_s)
      end
    end

    context "combining multiple filters" do
      it "applies multiple filters simultaneously" do
        visit raaf_rails_continuous_results_path

        select "AgentA", from: "Agent"
        select "passed", from: "Status"
        click_button "Filter"

        expect(page).to have_content("span-filter-1")
        expect(page).to have_content("span-filter-3")
        expect(page).not_to have_content("span-filter-2")
      end

      it "maintains filter state in URL" do
        visit raaf_rails_continuous_results_path

        select "AgentA", from: "Agent"
        select "passed", from: "Status"
        click_button "Filter"

        expect(current_url).to include("agent=AgentA")
        expect(current_url).to include("status=passed")
      end
    end
  end

  describe "Result Detail View" do
    let!(:detailed_result) do
      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-detail-test",
        trace_id: "trace-detail-test",
        agent_name: "DetailAgent",
        agent_version: "2.0",
        model: "gpt-4o",
        provider: "openai",
        environment: "production",
        evaluator_name: "quality_check",
        evaluator_type: "llm_judge",
        evaluator_version: "1.5.0",
        status: "passed",
        score: 0.88,
        scores: { "accuracy" => 0.9, "completeness" => 0.85 },
        metrics: { "latency_ms" => 1500, "tokens" => 450, "cost" => 0.025 },
        reasoning: "Response demonstrates high accuracy with minor completeness gaps",
        details: { "criteria_met" => ["factual", "coherent"], "criteria_missed" => ["exhaustive"] },
        evaluation_duration_ms: 2300
      )
    end

    it "displays complete result information" do
      visit raaf_rails_continuous_result_path(detailed_result)

      expect(page).to have_content("span-detail-test")
      expect(page).to have_content("trace-detail-test")
      expect(page).to have_content("DetailAgent")
      expect(page).to have_content("2.0")
      expect(page).to have_content("gpt-4o")
      expect(page).to have_content("openai")
      expect(page).to have_content("production")
    end

    it "shows evaluator details" do
      visit raaf_rails_continuous_result_path(detailed_result)

      within ".evaluator-info" do
        expect(page).to have_content("quality_check")
        expect(page).to have_content("llm_judge")
        expect(page).to have_content("1.5.0")
      end
    end

    it "displays score breakdown" do
      visit raaf_rails_continuous_result_path(detailed_result)

      within ".scores-section" do
        expect(page).to have_content("0.88")
        expect(page).to have_content("accuracy")
        expect(page).to have_content("0.9")
        expect(page).to have_content("completeness")
        expect(page).to have_content("0.85")
      end
    end

    it "shows evaluation reasoning" do
      visit raaf_rails_continuous_result_path(detailed_result)

      within ".reasoning-section" do
        expect(page).to have_content("Response demonstrates high accuracy")
      end
    end

    it "displays metrics" do
      visit raaf_rails_continuous_result_path(detailed_result)

      within ".metrics-section" do
        expect(page).to have_content("Latency")
        expect(page).to have_content("1500 ms")
        expect(page).to have_content("Tokens")
        expect(page).to have_content("450")
        expect(page).to have_content("Cost")
        expect(page).to have_content("$0.025")
      end
    end

    it "shows additional details in expandable section" do
      visit raaf_rails_continuous_result_path(detailed_result)

      within ".details-section" do
        expect(page).to have_content("criteria_met")
        expect(page).to have_content("factual")
        expect(page).to have_content("coherent")
        expect(page).to have_content("criteria_missed")
        expect(page).to have_content("exhaustive")
      end
    end

    it "shows evaluation timing" do
      visit raaf_rails_continuous_result_path(detailed_result)

      expect(page).to have_content("Evaluation Duration")
      expect(page).to have_content("2.3 s")
    end

    it "provides link to associated span" do
      visit raaf_rails_continuous_result_path(detailed_result)

      expect(page).to have_link("View Span")
    end

    it "provides link to evaluation policy" do
      visit raaf_rails_continuous_result_path(detailed_result)

      expect(page).to have_link("Test Policy")
    end
  end

  describe "Related Results" do
    let!(:primary_result) do
      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-same",
        evaluator_name: "token_limit",
        evaluator_type: "rule_based",
        status: "passed",
        score: 0.9,
        agent_name: "TestAgent"
      )
    end

    let!(:related_result) do
      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-same",
        evaluator_name: "quality_check",
        evaluator_type: "llm_judge",
        status: "passed",
        score: 0.85,
        agent_name: "TestAgent"
      )
    end

    it "shows other evaluation results for the same span" do
      visit raaf_rails_continuous_result_path(primary_result)

      within ".related-results" do
        expect(page).to have_content("Other evaluations for this span")
        expect(page).to have_content("quality_check")
        expect(page).to have_content("0.85")
      end
    end

    it "allows navigation to related results" do
      visit raaf_rails_continuous_result_path(primary_result)

      within ".related-results" do
        click_link "quality_check"
      end

      expect(page).to have_content("quality_check")
      expect(page).to have_content("llm_judge")
    end
  end

  describe "Results Export" do
    before do
      5.times do |i|
        EvaluationResult.create!(
          evaluation_queue: queue_item,
          evaluation_policy: policy,
          evaluation_policy_id: policy.id,
          span_id: "span-export-#{i}",
          agent_name: "ExportAgent",
          evaluator_name: "token_limit",
          evaluator_type: "rule_based",
          status: "passed",
          score: 0.8 + (i * 0.02)
        )
      end
    end

    it "provides export to CSV option" do
      visit raaf_rails_continuous_results_path

      expect(page).to have_link("Export CSV")
    end

    it "provides export to JSON option" do
      visit raaf_rails_continuous_results_path

      expect(page).to have_link("Export JSON")
    end

    it "applies current filters to export" do
      visit raaf_rails_continuous_results_path(status: "passed")

      # Export links should include current filter parameters
      expect(page).to have_link("Export CSV", href: /status=passed/)
    end
  end

  describe "Results Pagination" do
    before do
      60.times do |i|
        EvaluationResult.create!(
          evaluation_queue: queue_item,
          evaluation_policy: policy,
          evaluation_policy_id: policy.id,
          span_id: "span-page-#{i}",
          agent_name: "PageAgent",
          evaluator_name: "token_limit",
          evaluator_type: "rule_based",
          status: "passed",
          score: 0.8
        )
      end
    end

    it "paginates results" do
      visit raaf_rails_continuous_results_path

      expect(page).to have_css(".pagination")
      expect(page).to have_link("2")
      expect(page).to have_link("Next")
    end

    it "preserves filters during pagination" do
      visit raaf_rails_continuous_results_path(status: "passed")

      click_link "2"

      expect(current_url).to include("status=passed")
      expect(current_url).to include("page=2")
    end

    it "shows page information" do
      visit raaf_rails_continuous_results_path

      expect(page).to have_content(/showing \d+ of \d+/i)
    end
  end

  describe "Score Visualization" do
    before do
      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-viz-high",
        agent_name: "VizAgent",
        evaluator_name: "quality",
        evaluator_type: "llm_judge",
        status: "passed",
        score: 0.95
      )

      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-viz-low",
        agent_name: "VizAgent",
        evaluator_name: "quality",
        evaluator_type: "llm_judge",
        status: "failed",
        score: 0.25
      )
    end

    it "shows color-coded score indicators" do
      visit raaf_rails_continuous_results_path

      # High score should have green indicator
      expect(page).to have_css(".score-high, .text-green-600, .bg-green-100")

      # Low score should have red indicator
      expect(page).to have_css(".score-low, .text-red-600, .bg-red-100")
    end

    it "displays score progress bar on detail page" do
      result = EvaluationResult.records.find { |r| r.score == 0.95 }
      visit raaf_rails_continuous_result_path(result)

      expect(page).to have_css(".score-bar, .progress-bar")
    end
  end

  describe "Error Handling" do
    it "handles missing result gracefully" do
      visit "/raaf/rails/continuous/results/99999"

      expect(page).to have_content(/not found|does not exist/i)
    end

    it "shows empty state when no results match filters" do
      visit raaf_rails_continuous_results_path(agent: "NonExistentAgent")

      expect(page).to have_content(/no results found/i)
    end
  end

  describe "Accessibility" do
    before do
      EvaluationResult.create!(
        evaluation_queue: queue_item,
        evaluation_policy: policy,
        evaluation_policy_id: policy.id,
        span_id: "span-a11y",
        agent_name: "A11yAgent",
        evaluator_name: "quality",
        evaluator_type: "llm_judge",
        status: "passed",
        score: 0.9
      )
    end

    it "provides accessible table structure" do
      visit raaf_rails_continuous_results_path

      expect(page).to have_css("table[role='table'], table")
      expect(page).to have_css("th[scope='col'], thead th")
    end

    it "uses proper heading hierarchy" do
      visit raaf_rails_continuous_results_path

      expect(page).to have_css("h1, h2")
    end

    it "provides skip navigation link" do
      visit raaf_rails_continuous_results_path

      expect(page).to have_css("[class*='skip'], [href='#main']", visible: :all)
    end
  end
end

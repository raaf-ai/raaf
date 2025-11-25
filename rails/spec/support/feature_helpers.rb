# frozen_string_literal: true

# Feature test helpers for continuous evaluation UI
module FeatureHelpers
  # Navigation helpers
  def visit_policies_page
    visit raaf_rails_continuous_policies_path
  end

  def visit_policy_page(policy)
    visit raaf_rails_continuous_policy_path(policy)
  end

  def visit_new_policy_page
    visit new_raaf_rails_continuous_policy_path
  end

  def visit_edit_policy_page(policy)
    visit edit_raaf_rails_continuous_policy_path(policy)
  end

  def visit_queue_page
    visit raaf_rails_continuous_queue_index_path
  end

  def visit_queue_item_page(item)
    visit raaf_rails_continuous_queue_path(item)
  end

  def visit_results_page
    visit raaf_rails_continuous_results_path
  end

  def visit_result_page(result)
    visit raaf_rails_continuous_result_path(result)
  end

  def visit_analytics_page
    visit raaf_rails_continuous_analytics_path
  end

  # Form helpers
  def fill_in_policy_form(attrs = {})
    fill_in "Name", with: attrs[:name] || "Test Policy"
    fill_in "Agent name", with: attrs[:agent_name] || "TestAgent"

    if attrs[:description]
      fill_in "Description", with: attrs[:description]
    end

    if attrs[:sampling_mode]
      select attrs[:sampling_mode].humanize, from: "Sampling mode"
    end

    if attrs[:sample_rate]
      fill_in "Sample rate", with: attrs[:sample_rate]
    end

    if attrs[:max_daily_evaluations]
      fill_in "Max daily evaluations", with: attrs[:max_daily_evaluations]
    end

    if attrs[:priority]
      fill_in "Priority", with: attrs[:priority]
    end
  end

  def submit_policy_form
    click_button "Create Policy"
  end

  def update_policy_form
    click_button "Update Policy"
  end

  # Assertion helpers
  def expect_policy_in_list(policy)
    within ".policies-list" do
      expect(page).to have_content(policy.name)
      expect(page).to have_content(policy.agent_name)
    end
  end

  def expect_flash_notice(message)
    expect(page).to have_css(".flash-notice, .alert-success, [data-flash='notice']", text: message)
  end

  def expect_flash_alert(message)
    expect(page).to have_css(".flash-alert, .alert-danger, [data-flash='alert']", text: message)
  end

  # Action helpers
  def activate_policy(policy)
    within "[data-policy-id='#{policy.id}']" do
      click_button "Activate"
    end
  end

  def deactivate_policy(policy)
    within "[data-policy-id='#{policy.id}']" do
      click_button "Deactivate"
    end
  end

  def duplicate_policy(policy)
    within "[data-policy-id='#{policy.id}']" do
      click_button "Duplicate"
    end
  end

  def retry_queue_item(item)
    within "[data-queue-item-id='#{item.id}']" do
      click_button "Retry"
    end
  end

  def cancel_queue_item(item)
    within "[data-queue-item-id='#{item.id}']" do
      click_button "Cancel"
    end
  end

  # Filter helpers
  def filter_by_status(status)
    select status.humanize, from: "Status"
    click_button "Filter"
  end

  def filter_by_agent(agent_name)
    select agent_name, from: "Agent"
    click_button "Filter"
  end

  def filter_by_date_range(from_date, to_date)
    fill_in "From", with: from_date.to_s
    fill_in "To", with: to_date.to_s
    click_button "Filter"
  end

  # Chart helpers
  def expect_chart_loaded(chart_id)
    expect(page).to have_css("##{chart_id} svg", wait: 5)
  end

  def expect_chart_data_points(chart_id, count)
    within "##{chart_id}" do
      expect(page).to have_css(".data-point, circle, rect", minimum: count)
    end
  end

  # Table helpers
  def expect_table_rows(count)
    expect(page).to have_css("tbody tr", count: count)
  end

  def expect_table_to_contain(content)
    within "table" do
      expect(page).to have_content(content)
    end
  end

  # Status badge helpers
  def expect_status_badge(status)
    expect(page).to have_css(".badge, .status-badge", text: status)
  end

  def expect_active_badge
    expect(page).to have_css(".badge-success, .bg-green-100", text: /active/i)
  end

  def expect_inactive_badge
    expect(page).to have_css(".badge-secondary, .bg-gray-100", text: /inactive/i)
  end

  # Queue status helpers
  def expect_queue_stats(pending:, running:, completed:, failed:)
    within ".queue-stats" do
      expect(page).to have_content("Pending: #{pending}") if pending
      expect(page).to have_content("Running: #{running}") if running
      expect(page).to have_content("Completed: #{completed}") if completed
      expect(page).to have_content("Failed: #{failed}") if failed
    end
  end

  # Results helpers
  def expect_result_details(result)
    expect(page).to have_content(result.evaluator_name)
    expect(page).to have_content(result.status)
    expect(page).to have_content(result.score.to_s) if result.score
  end

  # Analytics helpers
  def expect_overview_stats
    expect(page).to have_css(".overview-stats, .stats-cards")
    expect(page).to have_content(/total evaluations/i)
    expect(page).to have_content(/pass rate/i)
  end
end

RSpec.configure do |config|
  config.include FeatureHelpers, type: :feature
end

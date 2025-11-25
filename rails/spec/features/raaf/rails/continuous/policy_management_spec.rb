# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Policy Management", type: :feature, js: true do
  # These tests verify the complete user workflow for managing continuous evaluation policies
  # through the RAAF Rails dashboard UI.

  describe "Policy Creation Workflow" do
    before do
      # Mock evaluator discovery to return available evaluators
      allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return([
        {
          name: "token_limit",
          type: "rule_based",
          description: "Validates token usage against limits",
          config_schema: { max_tokens: { type: "integer", required: true } }
        },
        {
          name: "quality_check",
          type: "llm_judge",
          description: "LLM-based quality assessment",
          config_schema: { model: { type: "string", default: "gpt-4o-mini" } }
        }
      ])
    end

    context "when creating a new policy" do
      it "displays the new policy form with all required fields" do
        visit new_raaf_rails_continuous_policy_path

        expect(page).to have_content("New Evaluation Policy")
        expect(page).to have_field("Name")
        expect(page).to have_field("Agent name")
        expect(page).to have_select("Sampling mode")
        expect(page).to have_field("Sample rate")
        expect(page).to have_field("Max daily evaluations")
        expect(page).to have_field("Priority")
      end

      it "shows available evaluators for selection" do
        visit new_raaf_rails_continuous_policy_path

        expect(page).to have_content("token_limit")
        expect(page).to have_content("quality_check")
        expect(page).to have_content("rule_based")
        expect(page).to have_content("llm_judge")
      end

      it "creates a policy with valid attributes and redirects to policy show page" do
        visit new_raaf_rails_continuous_policy_path

        fill_in "Name", with: "Production Quality Policy"
        fill_in "Agent name", with: "CustomerSupportAgent"
        fill_in "Description", with: "Monitor customer support agent quality"
        select "Percentage", from: "Sampling mode"
        fill_in "Sample rate", with: "25"
        fill_in "Max daily evaluations", with: "1000"
        fill_in "Priority", with: "75"

        click_button "Create Policy"

        expect(page).to have_content("Policy created successfully")
        expect(page).to have_content("Production Quality Policy")
        expect(page).to have_content("CustomerSupportAgent")
      end

      it "shows validation errors for invalid policy attributes" do
        visit new_raaf_rails_continuous_policy_path

        # Submit without required fields
        fill_in "Name", with: ""
        fill_in "Agent name", with: ""

        click_button "Create Policy"

        expect(page).to have_content(/can't be blank|is required/i)
        expect(page).to have_css(".field-error, .invalid-feedback, .error")
      end

      it "pre-fills default values for new policies" do
        visit new_raaf_rails_continuous_policy_path

        expect(page).to have_select("Sampling mode", selected: "Percentage")
        expect(page).to have_field("Sample rate", with: "10")
        expect(page).to have_field("Priority", with: "50")
        expect(page).to have_field("Retention days", with: "90")
      end
    end

    context "when configuring evaluators" do
      it "allows adding evaluators to the policy" do
        visit new_raaf_rails_continuous_policy_path

        # Add a rule-based evaluator
        within ".evaluators-section" do
          click_button "Add Evaluator"
          select "token_limit", from: "Evaluator"
          fill_in "Max tokens", with: "4000"
        end

        fill_in "Name", with: "Token Limit Policy"
        fill_in "Agent name", with: "TestAgent"
        click_button "Create Policy"

        expect(page).to have_content("Policy created successfully")
        expect(page).to have_content("token_limit")
      end

      it "allows configuring LLM judge evaluators" do
        visit new_raaf_rails_continuous_policy_path

        within ".evaluators-section" do
          click_button "Add Evaluator"
          select "quality_check", from: "Evaluator"
        end

        fill_in "Name", with: "Quality Check Policy"
        fill_in "Agent name", with: "TestAgent"
        click_button "Create Policy"

        expect(page).to have_content("Policy created successfully")
      end
    end
  end

  describe "Policy Listing" do
    let!(:active_policy) do
      EvaluationPolicy.create!(
        name: "Active Production Policy",
        agent_name: "ProductionAgent",
        sampling_mode: "percentage",
        sample_rate: 20,
        active: true,
        evaluators: []
      )
    end

    let!(:inactive_policy) do
      EvaluationPolicy.create!(
        name: "Inactive Test Policy",
        agent_name: "TestAgent",
        sampling_mode: "every_n",
        sample_every_n: 5,
        active: false,
        evaluators: []
      )
    end

    it "displays all policies with their status" do
      visit raaf_rails_continuous_policies_path

      expect(page).to have_content("Active Production Policy")
      expect(page).to have_content("Inactive Test Policy")
      expect(page).to have_content("ProductionAgent")
      expect(page).to have_content("TestAgent")
    end

    it "shows active/inactive status badges" do
      visit raaf_rails_continuous_policies_path

      within "[data-policy-id='#{active_policy.id}']" do
        expect(page).to have_css(".badge-success, .bg-green-100", text: /active/i)
      end

      within "[data-policy-id='#{inactive_policy.id}']" do
        expect(page).to have_css(".badge-secondary, .bg-gray-100", text: /inactive/i)
      end
    end

    it "filters policies by active status" do
      visit raaf_rails_continuous_policies_path(active: "true")

      expect(page).to have_content("Active Production Policy")
      expect(page).not_to have_content("Inactive Test Policy")
    end

    it "filters policies by agent name" do
      visit raaf_rails_continuous_policies_path(agent: "ProductionAgent")

      expect(page).to have_content("Active Production Policy")
      expect(page).not_to have_content("Inactive Test Policy")
    end

    it "provides links to view, edit, and manage each policy" do
      visit raaf_rails_continuous_policies_path

      within "[data-policy-id='#{active_policy.id}']" do
        expect(page).to have_link("View")
        expect(page).to have_link("Edit")
        expect(page).to have_button("Deactivate")
        expect(page).to have_button("Duplicate")
      end
    end
  end

  describe "Policy Detail View" do
    let!(:policy) do
      EvaluationPolicy.create!(
        name: "Detailed Policy",
        description: "A comprehensive evaluation policy",
        agent_name: "DetailedAgent",
        environment: "production",
        sampling_mode: "percentage",
        sample_rate: 15,
        max_daily_evaluations: 500,
        priority: 80,
        active: true,
        evaluators: [
          { "type" => "rule_based", "name" => "token_limit", "config" => { "max_tokens" => 4000 } }
        ]
      )
    end

    it "displays complete policy details" do
      visit raaf_rails_continuous_policy_path(policy)

      expect(page).to have_content("Detailed Policy")
      expect(page).to have_content("A comprehensive evaluation policy")
      expect(page).to have_content("DetailedAgent")
      expect(page).to have_content("production")
      expect(page).to have_content("15%")
      expect(page).to have_content("500")
      expect(page).to have_content("80")
    end

    it "shows configured evaluators" do
      visit raaf_rails_continuous_policy_path(policy)

      within ".evaluators-list" do
        expect(page).to have_content("token_limit")
        expect(page).to have_content("rule_based")
        expect(page).to have_content("4000")
      end
    end

    it "displays today's evaluation statistics" do
      visit raaf_rails_continuous_policy_path(policy)

      within ".policy-stats" do
        expect(page).to have_content(/evaluations today/i)
        expect(page).to have_content(/passed/i)
        expect(page).to have_content(/failed/i)
      end
    end

    it "shows recent evaluation results" do
      visit raaf_rails_continuous_policy_path(policy)

      expect(page).to have_content("Recent Results")
    end
  end

  describe "Policy Editing" do
    let!(:policy) do
      EvaluationPolicy.create!(
        name: "Original Policy Name",
        agent_name: "OriginalAgent",
        sampling_mode: "percentage",
        sample_rate: 10,
        active: true,
        evaluators: []
      )
    end

    before do
      allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return([])
    end

    it "loads the edit form with current values" do
      visit edit_raaf_rails_continuous_policy_path(policy)

      expect(page).to have_field("Name", with: "Original Policy Name")
      expect(page).to have_field("Agent name", with: "OriginalAgent")
      expect(page).to have_field("Sample rate", with: "10")
    end

    it "updates policy attributes successfully" do
      visit edit_raaf_rails_continuous_policy_path(policy)

      fill_in "Name", with: "Updated Policy Name"
      fill_in "Sample rate", with: "25"

      click_button "Update Policy"

      expect(page).to have_content("Policy updated successfully")
      expect(page).to have_content("Updated Policy Name")
    end

    it "shows validation errors for invalid updates" do
      visit edit_raaf_rails_continuous_policy_path(policy)

      fill_in "Name", with: ""

      click_button "Update Policy"

      expect(page).to have_content(/can't be blank|is required/i)
    end
  end

  describe "Policy Deletion" do
    let!(:policy) do
      EvaluationPolicy.create!(
        name: "Policy to Delete",
        agent_name: "DeleteAgent",
        active: false,
        evaluators: []
      )
    end

    it "deletes a policy with confirmation" do
      visit raaf_rails_continuous_policy_path(policy)

      accept_confirm do
        click_button "Delete Policy"
      end

      expect(page).to have_content("Policy deleted")
      expect(page).to have_current_path(raaf_rails_continuous_policies_path)
      expect(page).not_to have_content("Policy to Delete")
    end

    it "cancels deletion when confirmation is rejected" do
      visit raaf_rails_continuous_policy_path(policy)

      dismiss_confirm do
        click_button "Delete Policy"
      end

      expect(page).to have_content("Policy to Delete")
    end
  end

  describe "Policy Activation/Deactivation" do
    context "when activating an inactive policy" do
      let!(:inactive_policy) do
        EvaluationPolicy.create!(
          name: "Inactive Policy",
          agent_name: "InactiveAgent",
          active: false,
          evaluators: []
        )
      end

      it "activates the policy and shows success message" do
        visit raaf_rails_continuous_policies_path

        within "[data-policy-id='#{inactive_policy.id}']" do
          click_button "Activate"
        end

        expect(page).to have_content("Policy activated")

        within "[data-policy-id='#{inactive_policy.id}']" do
          expect(page).to have_css(".badge-success, .bg-green-100", text: /active/i)
          expect(page).to have_button("Deactivate")
        end
      end
    end

    context "when deactivating an active policy" do
      let!(:active_policy) do
        EvaluationPolicy.create!(
          name: "Active Policy",
          agent_name: "ActiveAgent",
          active: true,
          evaluators: []
        )
      end

      it "deactivates the policy and shows success message" do
        visit raaf_rails_continuous_policies_path

        within "[data-policy-id='#{active_policy.id}']" do
          click_button "Deactivate"
        end

        expect(page).to have_content("Policy deactivated")

        within "[data-policy-id='#{active_policy.id}']" do
          expect(page).to have_css(".badge-secondary, .bg-gray-100", text: /inactive/i)
          expect(page).to have_button("Activate")
        end
      end
    end
  end

  describe "Policy Duplication" do
    let!(:original_policy) do
      EvaluationPolicy.create!(
        name: "Original Policy",
        description: "Original description",
        agent_name: "OriginalAgent",
        sampling_mode: "percentage",
        sample_rate: 20,
        active: true,
        evaluators: [{ "type" => "rule_based", "name" => "token_limit" }]
      )
    end

    it "creates a duplicate policy with (Copy) suffix" do
      visit raaf_rails_continuous_policies_path

      within "[data-policy-id='#{original_policy.id}']" do
        click_button "Duplicate"
      end

      expect(page).to have_content("Policy duplicated")
      # Should redirect to edit page of the duplicate
      expect(page).to have_field("Name", with: "Original Policy (Copy)")
    end

    it "sets the duplicate as inactive by default" do
      visit raaf_rails_continuous_policies_path

      within "[data-policy-id='#{original_policy.id}']" do
        click_button "Duplicate"
      end

      # After duplication, the duplicate should be inactive
      expect(page).to have_unchecked_field("Active")
    end

    it "preserves evaluator configuration in the duplicate" do
      visit raaf_rails_continuous_policies_path

      within "[data-policy-id='#{original_policy.id}']" do
        click_button "Duplicate"
      end

      # Should show the evaluator from original
      expect(page).to have_content("token_limit")
    end
  end

  describe "Error Handling" do
    it "handles missing policy gracefully" do
      visit "/raaf/rails/continuous/policies/99999"

      expect(page).to have_content(/not found|does not exist/i)
    end

    it "displays error messages for server errors" do
      allow(EvaluationPolicy).to receive(:create!).and_raise(StandardError, "Database connection error")

      visit new_raaf_rails_continuous_policy_path

      fill_in "Name", with: "Test Policy"
      fill_in "Agent name", with: "TestAgent"

      click_button "Create Policy"

      expect(page).to have_content(/error|failed/i)
    end
  end

  describe "Keyboard Navigation and Accessibility" do
    it "allows navigating the policy list with keyboard" do
      visit raaf_rails_continuous_policies_path

      # Tab through interactive elements
      page.send_keys(:tab)

      # Check that focus is visible
      expect(page).to have_css(":focus")
    end

    it "provides proper ARIA labels for form fields" do
      visit new_raaf_rails_continuous_policy_path

      expect(page).to have_css("[aria-label], label[for]")
    end

    it "announces status changes to screen readers" do
      visit raaf_rails_continuous_policies_path

      # Flash messages should be in a live region
      expect(page).to have_css("[role='alert'], [aria-live]")
    end
  end
end

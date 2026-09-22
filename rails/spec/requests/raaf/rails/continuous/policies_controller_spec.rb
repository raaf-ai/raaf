# frozen_string_literal: true

require "rails_helper"

RSpec.describe RAAF::Rails::Continuous::PoliciesController, type: :request do
  let(:valid_attributes) do
    {
      name: "Test Policy",
      agent_name: "TestAgent",
      sampling_mode: "every_n",
      sample_every_n: 10,
      evaluators: []
    }
  end

  let(:invalid_attributes) do
    {
      name: nil,
      agent_name: nil
    }
  end

  describe "GET /raaf/continuous/policies" do
    it "returns a successful response" do
      get continuous_policies_path
      expect(response).to have_http_status(:success)
    end

    it "filters by active status" do
      EvaluationPolicy.create!(valid_attributes.merge(active: true))
      EvaluationPolicy.create!(valid_attributes.merge(name: "Inactive", active: false))

      get continuous_policies_path(active: "true")
      expect(response).to have_http_status(:success)
    end

    it "offers each row the toggle for the state it is in" do
      active_policy = EvaluationPolicy.create!(valid_attributes.merge(active: true))
      paused_policy = EvaluationPolicy.create!(valid_attributes.merge(name: "Paused", active: false))

      get continuous_policies_path

      expect(response.body).to include(deactivate_continuous_policy_path(active_policy))
      expect(response.body).to include(activate_continuous_policy_path(paused_policy))
      expect(response.body).to include("Pause", "Resume")
    end
  end

  describe "GET /raaf/continuous/policies/:id" do
    let(:policy) { EvaluationPolicy.create!(valid_attributes) }

    it "returns a successful response" do
      get continuous_policy_path(policy)
      expect(response).to have_http_status(:success)
    end

    it "carries the pause control in its header" do
      get continuous_policy_path(policy)

      expect(response.body).to include(deactivate_continuous_policy_path(policy))
      expect(response.body).to include("Pause")
    end
  end

  describe "GET /raaf/continuous/policies/new" do
    it "returns a successful response" do
      allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return([])

      get new_continuous_policy_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /raaf/continuous/policies" do
    context "with valid parameters" do
      it "creates a new policy" do
        expect do
          post continuous_policies_path, params: { evaluation_policy: valid_attributes }
        end.to change(EvaluationPolicy, :count).by(1)
      end

      it "redirects to the created policy" do
        post continuous_policies_path, params: { evaluation_policy: valid_attributes }
        expect(response).to redirect_to(continuous_policy_path(EvaluationPolicy.last))
      end
    end

    context "with invalid parameters" do
      it "does not create a new policy" do
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return([])

        expect do
          post continuous_policies_path, params: { evaluation_policy: invalid_attributes }
        end.not_to change(EvaluationPolicy, :count)
      end

      # Rack 3.2 deprecated :unprocessable_entity in favour of :unprocessable_content.
      it "renders the new template with unprocessable content status" do
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return([])

        post continuous_policies_path, params: { evaluation_policy: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PATCH /raaf/continuous/policies/:id" do
    let(:policy) { EvaluationPolicy.create!(valid_attributes) }
    let(:new_attributes) { { name: "Updated Policy" } }

    context "with valid parameters" do
      it "updates the policy" do
        patch continuous_policy_path(policy), params: { evaluation_policy: new_attributes }
        policy.reload
        expect(policy.name).to eq("Updated Policy")
      end

      it "redirects to the policy" do
        patch continuous_policy_path(policy), params: { evaluation_policy: new_attributes }
        expect(response).to redirect_to(continuous_policy_path(policy))
      end
    end
  end

  describe "DELETE /raaf/continuous/policies/:id" do
    let!(:policy) { EvaluationPolicy.create!(valid_attributes) }

    it "destroys the policy" do
      expect do
        delete continuous_policy_path(policy)
      end.to change(EvaluationPolicy, :count).by(-1)
    end

    it "redirects to the policies list" do
      delete continuous_policy_path(policy)
      expect(response).to redirect_to(continuous_policies_path)
    end
  end

  describe "POST /raaf/continuous/policies/:id/activate" do
    let(:policy) { EvaluationPolicy.create!(valid_attributes.merge(active: false)) }

    it "activates the policy" do
      post activate_continuous_policy_path(policy)
      policy.reload
      expect(policy.active).to be true
    end

    it "redirects to policies list" do
      post activate_continuous_policy_path(policy)
      expect(response).to redirect_to(continuous_policies_path)
    end

    it "returns to the page the button was pressed on" do
      post activate_continuous_policy_path(policy),
           headers: { "HTTP_REFERER" => continuous_policy_path(policy) }

      expect(response).to redirect_to(continuous_policy_path(policy))
    end
  end

  describe "POST /raaf/continuous/policies/:id/deactivate" do
    let(:policy) { EvaluationPolicy.create!(valid_attributes.merge(active: true)) }

    it "deactivates the policy" do
      post deactivate_continuous_policy_path(policy)
      policy.reload
      expect(policy.active).to be false
    end
  end

  describe "POST /raaf/continuous/policies/:id/duplicate" do
    # let!, so the original is already there when the count is taken -- lazily
    # created inside the expect block it counted as one of the two.
    let!(:policy) { EvaluationPolicy.create!(valid_attributes) }

    it "creates a duplicate policy" do
      expect do
        post duplicate_continuous_policy_path(policy)
      end.to change(EvaluationPolicy, :count).by(1)
    end

    it "duplicates with (Copy) suffix and inactive status" do
      post duplicate_continuous_policy_path(policy)
      duplicate = EvaluationPolicy.last
      expect(duplicate.name).to eq("#{policy.name} (Copy)")
      expect(duplicate.active).to be false
    end
  end
end

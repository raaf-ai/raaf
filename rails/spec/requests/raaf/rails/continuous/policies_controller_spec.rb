# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RAAF::Rails::Continuous::PoliciesController, type: :request do
  let(:valid_attributes) do
    {
      name: 'Test Policy',
      agent_name: 'TestAgent',
      sampling_mode: 'percentage',
      sample_rate: 10,
      evaluators: []
    }
  end

  let(:invalid_attributes) do
    {
      name: nil,
      agent_name: nil
    }
  end

  describe "GET /raaf/rails/continuous/policies" do
    it "returns a successful response" do
      get raaf_rails_continuous_policies_path
      expect(response).to have_http_status(:success)
    end

    it "filters by active status" do
      active_policy = EvaluationPolicy.create!(valid_attributes.merge(active: true))
      inactive_policy = EvaluationPolicy.create!(valid_attributes.merge(name: 'Inactive', active: false))

      get raaf_rails_continuous_policies_path(active: 'true')
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /raaf/rails/continuous/policies/:id" do
    let(:policy) { EvaluationPolicy.create!(valid_attributes) }

    it "returns a successful response" do
      get raaf_rails_continuous_policy_path(policy)
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /raaf/rails/continuous/policies/new" do
    it "returns a successful response" do
      allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return([])

      get new_raaf_rails_continuous_policy_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /raaf/rails/continuous/policies" do
    context "with valid parameters" do
      it "creates a new policy" do
        expect {
          post raaf_rails_continuous_policies_path, params: { evaluation_policy: valid_attributes }
        }.to change(EvaluationPolicy, :count).by(1)
      end

      it "redirects to the created policy" do
        post raaf_rails_continuous_policies_path, params: { evaluation_policy: valid_attributes }
        expect(response).to redirect_to(raaf_rails_continuous_policy_path(EvaluationPolicy.last))
      end
    end

    context "with invalid parameters" do
      it "does not create a new policy" do
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return([])

        expect {
          post raaf_rails_continuous_policies_path, params: { evaluation_policy: invalid_attributes }
        }.to change(EvaluationPolicy, :count).by(0)
      end

      it "renders the new template with unprocessable entity status" do
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return([])

        post raaf_rails_continuous_policies_path, params: { evaluation_policy: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH /raaf/rails/continuous/policies/:id" do
    let(:policy) { EvaluationPolicy.create!(valid_attributes) }
    let(:new_attributes) { { name: 'Updated Policy' } }

    context "with valid parameters" do
      it "updates the policy" do
        patch raaf_rails_continuous_policy_path(policy), params: { evaluation_policy: new_attributes }
        policy.reload
        expect(policy.name).to eq('Updated Policy')
      end

      it "redirects to the policy" do
        patch raaf_rails_continuous_policy_path(policy), params: { evaluation_policy: new_attributes }
        expect(response).to redirect_to(raaf_rails_continuous_policy_path(policy))
      end
    end
  end

  describe "DELETE /raaf/rails/continuous/policies/:id" do
    let!(:policy) { EvaluationPolicy.create!(valid_attributes) }

    it "destroys the policy" do
      expect {
        delete raaf_rails_continuous_policy_path(policy)
      }.to change(EvaluationPolicy, :count).by(-1)
    end

    it "redirects to the policies list" do
      delete raaf_rails_continuous_policy_path(policy)
      expect(response).to redirect_to(raaf_rails_continuous_policies_path)
    end
  end

  describe "POST /raaf/rails/continuous/policies/:id/activate" do
    let(:policy) { EvaluationPolicy.create!(valid_attributes.merge(active: false)) }

    it "activates the policy" do
      post activate_raaf_rails_continuous_policy_path(policy)
      policy.reload
      expect(policy.active).to be true
    end

    it "redirects to policies list" do
      post activate_raaf_rails_continuous_policy_path(policy)
      expect(response).to redirect_to(raaf_rails_continuous_policies_path)
    end
  end

  describe "POST /raaf/rails/continuous/policies/:id/deactivate" do
    let(:policy) { EvaluationPolicy.create!(valid_attributes.merge(active: true)) }

    it "deactivates the policy" do
      post deactivate_raaf_rails_continuous_policy_path(policy)
      policy.reload
      expect(policy.active).to be false
    end
  end

  describe "POST /raaf/rails/continuous/policies/:id/duplicate" do
    let(:policy) { EvaluationPolicy.create!(valid_attributes) }

    it "creates a duplicate policy" do
      expect {
        post duplicate_raaf_rails_continuous_policy_path(policy)
      }.to change(EvaluationPolicy, :count).by(1)
    end

    it "duplicates with (Copy) suffix and inactive status" do
      post duplicate_raaf_rails_continuous_policy_path(policy)
      duplicate = EvaluationPolicy.last
      expect(duplicate.name).to eq("#{policy.name} (Copy)")
      expect(duplicate.active).to be false
    end
  end
end

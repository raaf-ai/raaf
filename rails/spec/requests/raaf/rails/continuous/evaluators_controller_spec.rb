# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RAAF::Rails::Continuous::EvaluatorsController, type: :request do
  describe "GET /raaf/rails/continuous/evaluators" do
    it "returns a list of available evaluators" do
      allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return([
        { name: 'test_evaluator', type: 'rule_based', description: 'Test evaluator' }
      ])

      get raaf_rails_continuous_evaluators_path
      expect(response).to have_http_status(:success)
    end

    it "returns JSON when requested" do
      evaluators = [
        { name: 'test_evaluator', type: 'rule_based', description: 'Test evaluator' }
      ]
      allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return(evaluators)

      get raaf_rails_continuous_evaluators_path, as: :json
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to eq(evaluators.map(&:stringify_keys))
    end
  end

  describe "GET /raaf/rails/continuous/evaluators/:id" do
    context "when evaluator exists" do
      it "returns evaluator details" do
        evaluator = { name: 'test_evaluator', type: 'rule_based', description: 'Test evaluator' }
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return([evaluator])

        get raaf_rails_continuous_evaluator_path('test_evaluator')
        expect(response).to have_http_status(:success)
      end

      it "returns JSON when requested" do
        evaluator = { name: 'test_evaluator', type: 'rule_based', description: 'Test evaluator' }
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return([evaluator])

        get raaf_rails_continuous_evaluator_path('test_evaluator'), as: :json
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)).to eq(evaluator.stringify_keys)
      end
    end

    context "when evaluator does not exist" do
      it "returns not found" do
        allow(RAAF::Eval::Continuous::EvaluatorDiscovery).to receive(:evaluator_details).and_return([])

        get raaf_rails_continuous_evaluator_path('nonexistent'), as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end

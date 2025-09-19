# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::AgentPipeline, "builder DSL" do
  let(:initial_context) do
    {
      product: "SaaS Platform",
      market: "Enterprise Software"
    }
  end

  describe ".build" do
    it "creates a pipeline using the builder DSL" do
      pipeline = described_class.build do
        step :test_step, agent: MockPipelineAgents::MockSearchAgent do
          input :product
          output :companies
        end
      end

      expect(pipeline).to be_a(RAAF::DSL::AgentPipeline)
    end

    it "supports complex pipeline structures" do
      pipeline = described_class.build do
        step :discovery, agent: MockPipelineAgents::MockSearchAgent do
          input :product, :market
          output :companies
        end

        parallel_group :enrichment, merge_strategy: :companies do
          step :basic_enrich, agent: MockPipelineAgents::MockEnrichmentAgent do
            input :companies
            output :basic_data
          end

          step :detailed_enrich, agent: MockPipelineAgents::MockEnrichmentAgent do
            input :companies
            output :detailed_data
          end
        end

        step :final_score, agent: MockPipelineAgents::MockScoringAgent do
          input :basic_data, :detailed_data
          output :final_results
        end
      end

      expect(pipeline).to be_a(RAAF::DSL::AgentPipeline)
    end
  end
end
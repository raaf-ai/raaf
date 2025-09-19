# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::AgentPipeline, "execution" do
  let(:basic_pipeline) do
    described_class.build do
      step :search, agent: MockPipelineAgents::MockSearchAgent do
        input :product, :market
        output :companies
      end

      step :enrich, agent: MockPipelineAgents::MockEnrichmentAgent do
        input :companies
        output :enriched_companies
      end

      step :score, agent: MockPipelineAgents::MockScoringAgent do
        input :enriched_companies, :product
        output :scored_prospects
      end
    end
  end

  let(:initial_context) do
    {
      product: "SaaS Platform",
      market: "Enterprise Software"
    }
  end

  describe "#execute" do
    context "successful execution" do
      it "executes a linear pipeline successfully" do
        result = basic_pipeline.execute(initial_context)

        expect(result[:success]).to be true
        expect(result[:workflow_status]).to eq("completed")
        expect(result[:execution_log]).to be_an(Array)
        expect(result[:execution_log].size).to eq(3)
        expect(result[:context]).to be_a(RAAF::DSL::ContextVariables)
      end

      it "passes data between steps correctly" do
        result = basic_pipeline.execute(initial_context)

        # Check that companies were found and passed through
        expect(result[:context].get(:companies)).to be_an(Array)
        expect(result[:context].get(:companies).size).to eq(2)

        # Check that enrichment happened
        expect(result[:context].get(:enriched_companies)).to be_an(Array)
        expect(result[:context].get(:enriched_companies).first[:employee_count]).to eq(100)

        # Check that scoring happened
        expect(result[:context].get(:scored_prospects)).to be_an(Array)
        expect(result[:context].get(:scored_prospects).first[:score]).to eq(85)
      end

      it "handles ContextVariables as initial context" do
        context_vars = RAAF::DSL::ContextVariables.new(initial_context)
        result = basic_pipeline.execute(context_vars)

        expect(result[:success]).to be true
        expect(result[:context]).to be_a(RAAF::DSL::ContextVariables)
      end

      it "preserves original context data" do
        result = basic_pipeline.execute(initial_context)

        expect(result[:context].get(:product)).to eq("SaaS Platform")
        expect(result[:context].get(:market)).to eq("Enterprise Software")
      end
    end

    context "conditional execution" do
      let(:conditional_pipeline) do
        described_class.build do
          step :search, agent: MockPipelineAgents::MockSearchAgent do
            input :product
            output :companies
            condition { |ctx| !ctx.get(:product).nil? }
          end

          step :skip_me, agent: MockPipelineAgents::MockEnrichmentAgent do
            input :companies
            output :enriched_companies
            condition { |ctx| ctx.get(:skip_flag) == true }
          end

          step :final, agent: MockPipelineAgents::MockScoringAgent do
            input :companies
            output :final_results
          end
        end
      end

      it "executes steps when conditions are met" do
        result = conditional_pipeline.execute({ product: "Test Product" })

        expect(result[:success]).to be true
        expect(result[:execution_log].size).to eq(3)
        expect(result[:execution_log][0][:success]).to be true
        expect(result[:execution_log][1][:success]).to be true
        expect(result[:execution_log][1][:message]).to include("Skipped")
      end

      it "skips steps when conditions are not met" do
        result = conditional_pipeline.execute({})

        expect(result[:success]).to be true
        # All steps should be skipped due to missing product
        expect(result[:execution_log].any? { |log| log[:message]&.include?("Skipped") }).to be true
      end
    end
  end
end
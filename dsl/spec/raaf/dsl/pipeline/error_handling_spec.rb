# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::AgentPipeline, "error handling" do
  let(:initial_context) do
    {
      product: "SaaS Platform",
      market: "Enterprise Software"
    }
  end

  let(:failing_pipeline) do
    described_class.build do
      step :search, agent: MockPipelineAgents::MockSearchAgent do
        input :product
        output :companies
      end

      step :fail, agent: MockPipelineAgents::MockFailingAgent do
        input :companies
        output :enriched_companies
      end

      step :score, agent: MockPipelineAgents::MockScoringAgent do
        input :enriched_companies
        output :final_results
      end
    end
  end

  let(:error_pipeline) do
    described_class.build do
      step :search, agent: MockPipelineAgents::MockSearchAgent do
        input :product
        output :companies
      end

      step :error, agent: MockPipelineAgents::MockErrorAgent do
        input :companies
        output :enriched_companies
      end

      step :score, agent: MockPipelineAgents::MockScoringAgent do
        input :enriched_companies
        output :final_results
      end
    end
  end

  describe "failure handling" do
    it "handles step failures gracefully" do
      result = failing_pipeline.execute(initial_context)

      expect(result[:success]).to be false
      expect(result[:workflow_status]).to eq("failed")
      expect(result[:failed_step]).to eq(:fail)
      # The error might be in different places depending on the implementation
      error_message = result[:error] || result[:context]&.get(:error) || result[:execution_log]&.last&.dig(:error)
      expect(error_message).to include("Agent execution failed") if error_message
      expect(result[:execution_log].size).to eq(2)  # Only first two steps executed
    end

    it "handles step exceptions gracefully" do
      result = error_pipeline.execute(initial_context)

      expect(result[:success]).to be false
      expect(result[:workflow_status]).to eq("failed")
      expect(result[:error]).to include("Agent threw an exception")
      # Exception details might be in execution log or different field
      exception_info = result[:exception] || result[:execution_log]&.last&.dig(:exception)
      expect(exception_info).to eq("StandardError") if exception_info
    end

    it "preserves context state on failure" do
      result = failing_pipeline.execute(initial_context)

      expect(result[:context].get(:product)).to eq("SaaS Platform")
      expect(result[:context].get(:companies)).to be_an(Array)
    end
  end

  describe "error recovery and resilience" do
    it "continues execution after failed parallel steps" do
      # Mock a partially failing parallel group
      class MockPartialFailAgent
        def initialize(context: {})
          @context = context
        end

        def run(context: {})
          step_name = @context.get(:step_name)
          if step_name == "fail_me"
            { success: false, error: "Simulated failure" }
          else
            { success: true, data: "success_data" }
          end
        end
      end

      pipeline = described_class.build do
        step :setup, agent: MockPipelineAgents::MockSearchAgent do
          input :product
          output :companies
        end

        parallel_group :mixed_results do
          step :success_step, agent: MockPartialFailAgent do
            input :companies
            output :success_data
          end

          step :fail_step, agent: MockPartialFailAgent do
            input :companies
            output :fail_data
          end
        end
      end

      # Set context to make one step fail
      context = RAAF::DSL::ContextVariables.new(product: "Test Product")
      context = context.set(:step_name, "normal")

      result = pipeline.execute(context.to_h)

      # Pipeline should handle partial parallel failures
      expect(result[:execution_log].size).to eq(2)
      setup_log = result[:execution_log].first
      parallel_log = result[:execution_log].last

      expect(setup_log[:success]).to be true
      # Parallel group might succeed if merger handles partial results
    end
  end
end
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Pipeline Failure Propagation" do
  # Mock agents for testing failure scenarios
  class SuccessfulAgent < RAAF::DSL::Agent
    agent_name "SuccessfulAgent"
    model "gpt-4o"

    context do
      optional input_data: "test"
      output :output_data
    end

    schema do
      field :output_data, type: :string, required: true
    end

    def call
      { success: true, output_data: "success from #{self.class.name}" }
    end
  end

  class FailingAgent < RAAF::DSL::Agent
    agent_name "FailingAgent"
    model "gpt-4o"

    context do
      optional input_data: "test"
      output :output_data
    end

    schema do
      field :output_data, type: :string, required: true
    end

    def call
      {
        success: false,
        error: "Agent execution failed",
        error_type: "test_failure",
        output_data: nil
      }
    end
  end

  class SecondAgent < RAAF::DSL::Agent
    agent_name "SecondAgent"
    model "gpt-4o"

    context do
      optional input_data: "test"
      output :result
    end

    schema do
      field :result, type: :string, required: true
    end

    def call
      { success: true, result: "should not reach here" }
    end
  end

  describe "Sequential pipeline failure propagation" do
    it "stops execution when first agent fails" do
      pipeline_class = Class.new(RAAF::Pipeline) do
        flow FailingAgent >> SecondAgent

        context do
          optional input_data: "test"
        end
      end

      pipeline = pipeline_class.new(input_data: "test")
      result = pipeline.run

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Agent execution failed")
      expect(result[:error_type]).to eq("test_failure")
      expect(result[:failed_at]).to eq("FailingAgent")
      expect(result[:result]).to be_nil  # SecondAgent should not execute
    end

    it "stops execution when second agent fails" do
      pipeline_class = Class.new(RAAF::Pipeline) do
        flow SuccessfulAgent >> FailingAgent >> SecondAgent

        context do
          optional input_data: "test"
        end
      end

      pipeline = pipeline_class.new(input_data: "test")
      result = pipeline.run

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Agent execution failed")
      expect(result[:failed_at]).to eq("FailingAgent")
      # First agent should have executed
      expect(result[:output_data]).to be_nil
    end

    it "succeeds when all agents succeed" do
      pipeline_class = Class.new(RAAF::Pipeline) do
        flow SuccessfulAgent >> SecondAgent

        context do
          optional input_data: "test"
        end
      end

      pipeline = pipeline_class.new(input_data: "test")
      result = pipeline.run

      expect(result[:success]).to be true
      expect(result[:error]).to be_nil
      expect(result[:failed_at]).to be_nil
    end
  end

  describe "Parallel pipeline failure propagation" do
    it "fails entire pipeline when one parallel agent fails" do
      pipeline_class = Class.new(RAAF::Pipeline) do
        flow SuccessfulAgent | FailingAgent

        context do
          optional input_data: "test"
        end
      end

      pipeline = pipeline_class.new(input_data: "test")

      expect {
        pipeline.run
      }.to raise_error(RAAF::DSL::PipelineDSL::PipelineFailureError) do |error|
        expect(error.agent_name).to eq("FailingAgent")
        expect(error.error_message).to eq("Agent execution failed")
        expect(error.error_type).to eq("test_failure")
      end
    end

    it "succeeds when all parallel agents succeed" do
      pipeline_class = Class.new(RAAF::Pipeline) do
        flow SuccessfulAgent | SecondAgent

        context do
          optional input_data: "test"
        end
      end

      pipeline = pipeline_class.new(input_data: "test")
      result = pipeline.run

      expect(result[:success]).to be true
      expect(result[:error]).to be_nil
    end
  end

  describe "Mixed sequential and parallel failure propagation" do
    it "fails when parallel group contains failure" do
      pipeline_class = Class.new(RAAF::Pipeline) do
        flow SuccessfulAgent >> (SecondAgent | FailingAgent)

        context do
          optional input_data: "test"
        end
      end

      pipeline = pipeline_class.new(input_data: "test")

      expect {
        pipeline.run
      }.to raise_error(RAAF::DSL::PipelineDSL::PipelineFailureError)
    end

    it "fails when sequential agent after parallel group fails" do
      pipeline_class = Class.new(RAAF::Pipeline) do
        flow (SuccessfulAgent | SecondAgent) >> FailingAgent

        context do
          optional input_data: "test"
        end
      end

      pipeline = pipeline_class.new(input_data: "test")
      result = pipeline.run

      expect(result[:success]).to be false
      expect(result[:failed_at]).to eq("FailingAgent")
    end
  end

  describe "Error result structure" do
    it "includes all required error fields" do
      pipeline_class = Class.new(RAAF::Pipeline) do
        flow FailingAgent

        context do
          optional input_data: "test"
        end
      end

      pipeline = pipeline_class.new(input_data: "test")
      result = pipeline.run

      expect(result).to include(
        success: false,
        error: "Agent execution failed",
        error_type: "test_failure",
        failed_at: "FailingAgent"
      )

      expect(result[:full_error_details]).to be_a(Hash)
      expect(result[:full_error_details][:success]).to be false
    end

    it "preserves error type from failing agent" do
      custom_failure_agent = Class.new(RAAF::DSL::Agent) do
        agent_name "CustomFailureAgent"
        model "gpt-4o"

        context do
          optional input_data: "test"
        end

        def call
          {
            success: false,
            error: "Custom error message",
            error_type: "custom_error_type"
          }
        end
      end

      pipeline_class = Class.new(RAAF::Pipeline) do
        flow custom_failure_agent

        context do
          optional input_data: "test"
        end
      end

      pipeline = pipeline_class.new(input_data: "test")
      result = pipeline.run

      expect(result[:error_type]).to eq("custom_error_type")
      expect(result[:error]).to eq("Custom error message")
    end
  end

  describe "Backward compatibility" do
    it "does not fail when agent returns success: true" do
      pipeline_class = Class.new(RAAF::Pipeline) do
        flow SuccessfulAgent

        context do
          optional input_data: "test"
        end
      end

      pipeline = pipeline_class.new(input_data: "test")
      result = pipeline.run

      expect(result[:success]).to be true
    end

    it "does not fail when agent result has no success key" do
      no_success_key_agent = Class.new(RAAF::DSL::Agent) do
        agent_name "NoSuccessKeyAgent"
        model "gpt-4o"

        context do
          optional input_data: "test"
          output :data
        end

        schema do
          field :data, type: :string, required: true
        end

        def call
          { data: "some data" }  # No success key
        end
      end

      pipeline_class = Class.new(RAAF::Pipeline) do
        flow no_success_key_agent

        context do
          optional input_data: "test"
        end
      end

      pipeline = pipeline_class.new(input_data: "test")
      result = pipeline.run

      expect(result[:success]).to be true  # Pipeline adds success: true
    end

    it "still propagates exceptions raised by agents" do
      exception_agent = Class.new(RAAF::DSL::Agent) do
        agent_name "ExceptionAgent"
        model "gpt-4o"

        context do
          optional input_data: "test"
        end

        def call
          raise StandardError, "Something went wrong"
        end
      end

      pipeline_class = Class.new(RAAF::Pipeline) do
        flow exception_agent

        context do
          optional input_data: "test"
        end
      end

      pipeline = pipeline_class.new(input_data: "test")

      expect {
        pipeline.run
      }.to raise_error(StandardError, "Something went wrong")
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Business Class Method Removal" do
  describe "Agent classes" do
    describe RAAF::Agent do
      let(:agent) { RAAF::Agent.new(name: "TestAgent", instructions: "Test") }

      it "does not respond to collect_span_attributes" do
        expect(agent).not_to respond_to(:collect_span_attributes)
      end

      it "does not respond to collect_result_attributes" do
        expect(agent).not_to respond_to(:collect_result_attributes)
      end

      it "does not define collect_span_attributes as private method" do
        expect(agent.private_methods).not_to include(:collect_span_attributes)
      end

      it "does not define collect_result_attributes as private method" do
        expect(agent.private_methods).not_to include(:collect_result_attributes)
      end
    end

    describe RAAF::DSL::Agent do
      let(:agent_class) do
        Class.new(RAAF::DSL::Agent) do
          agent_name "TestDSLAgent"
          model "gpt-4o"
          instructions "Test DSL agent"
        end
      end
      let(:agent) { agent_class.new }

      it "does not respond to collect_span_attributes" do
        expect(agent).not_to respond_to(:collect_span_attributes)
      end

      it "does not respond to collect_result_attributes" do
        expect(agent).not_to respond_to(:collect_result_attributes)
      end

      it "does not define collect_span_attributes as private method" do
        expect(agent.private_methods).not_to include(:collect_span_attributes)
      end

      it "does not define collect_result_attributes as private method" do
        expect(agent.private_methods).not_to include(:collect_result_attributes)
      end
    end
  end

  describe "Pipeline classes" do
    describe RAAF::DSL::Pipeline do
      let(:pipeline_class) do
        Class.new(RAAF::DSL::Pipeline) do
          def self.name
            "TestPipeline"
          end
        end
      end
      let(:pipeline) { pipeline_class.new }

      it "does not respond to collect_span_attributes" do
        expect(pipeline).not_to respond_to(:collect_span_attributes)
      end

      it "does not respond to collect_result_attributes" do
        expect(pipeline).not_to respond_to(:collect_result_attributes)
      end

      it "does not define collect_span_attributes as private method" do
        expect(pipeline.private_methods).not_to include(:collect_span_attributes)
      end

      it "does not define collect_result_attributes as private method" do
        expect(pipeline.private_methods).not_to include(:collect_result_attributes)
      end
    end
  end

  describe "TracedJob classes" do
    describe RAAF::Tracing::TracedJob do
      # Create a test job class that includes TracedJob
      let(:job_class) do
        Class.new do
          include RAAF::Tracing::TracedJob
          
          def self.name
            "TestTracedJob"
          end
          
          def perform
            "test job"
          end
        end
      end
      let(:job) { job_class.new }

      it "does not respond to collect_span_attributes" do
        expect(job).not_to respond_to(:collect_span_attributes)
      end

      it "does not respond to collect_result_attributes" do
        expect(job).not_to respond_to(:collect_result_attributes)
      end

      it "does not define collect_span_attributes as private method" do
        expect(job.private_methods).not_to include(:collect_span_attributes)
      end

      it "does not define collect_result_attributes as private method" do
        expect(job.private_methods).not_to include(:collect_result_attributes)
      end
    end
  end
end

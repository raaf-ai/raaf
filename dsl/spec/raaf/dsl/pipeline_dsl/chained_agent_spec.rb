# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl"

RSpec.describe RAAF::DSL::PipelineDSL::ChainedAgent do
  # Create test agents
  let(:producer_agent) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "ProducerAgent"

      context do
        required :input_data
        output :output_data
      end

      result_transform do
        field :output_data, computed: :process
      end

      def process(data)
        "processed"
      end

      def run
        { output_data: "processed", extra_field: "extra" }
      end
    end
  end
  
  let(:consumer_agent) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "ConsumerAgent"

      context do
        required :output_data
        output :final_result
      end

      result_transform do
        field :final_result, computed: :finalize
      end

      def finalize(data)
        "finalized"
      end

      def run
        { final_result: "finalized" }
      end
    end
  end
  
  let(:incompatible_agent) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "IncompatibleAgent"

      context do
        required :missing_field
      end

      def run
        {}
      end
    end
  end
  
  describe "#initialize" do
    it "creates a chain with two agents" do
      chain = described_class.new(producer_agent, consumer_agent)
      expect(chain.first).to eq(producer_agent)
      expect(chain.second).to eq(consumer_agent)
    end
    
    it "validates field compatibility" do
      chain = described_class.new(producer_agent, incompatible_agent)
      expect {
        chain.validate_with_pipeline_context([])
      }.to raise_error(RAAF::DSL::PipelineDSL::FieldMismatchError)
    end
    
    it "allows initial context fields to be missing" do
      agent_needing_initial = Class.new(RAAF::DSL::Agent) do
        agent_name "InitialAgent"
        # Context is automatically available through auto-context
        # Input fields: product, company
      end
      
      expect {
        described_class.new(producer_agent, agent_needing_initial)
      }.not_to raise_error
    end
  end
  
  describe "#>>" do
    it "chains with another agent" do
      chain = producer_agent >> consumer_agent
      result = chain >> incompatible_agent
      expect(result).to be_a(described_class)
      expect(result.first).to eq(chain)
    end
  end
  
  describe "#execute" do
    let(:context) { { input_data: "test" } }
    
    before do
      allow_any_instance_of(producer_agent).to receive(:run).and_return({ output_data: "processed" })
      allow_any_instance_of(consumer_agent).to receive(:run).and_return({ final_result: "finalized" })
    end
    
    it "executes agents in sequence" do
      chain = described_class.new(producer_agent, consumer_agent)
      result = chain.execute(context)

      expect(result[:input_data]).to eq("test")
      expect(result[:output_data]).to eq("processed")
      expect(result[:final_result]).to eq("finalized")
    end
    
    it "passes context from first agent to second" do
      chain = described_class.new(producer_agent, consumer_agent)

      expect_any_instance_of(consumer_agent).to receive(:initialize) do |instance, **ctx|
        expect(ctx[:output_data]).to eq("processed")
      end.and_call_original

      chain.execute(context)
    end
    
    it "skips agent execution when requirements not met" do
      chain = described_class.new(producer_agent, incompatible_agent)

      expect(RAAF.logger).to receive(:warn).with(/Skipping.*IncompatibleAgent.*requirements not met/)

      result = chain.execute(context)
      expect(result[:output_data]).to eq("processed")
      expect(result[:input_data]).to eq("test")
    end
  end
  
  describe "#required_fields" do
    it "returns requirements of first agent in chain" do
      chain = described_class.new(producer_agent, consumer_agent)
      expect(chain.required_fields).to eq([:input_data])
    end
    
    it "handles nested chains" do
      chain1 = described_class.new(producer_agent, consumer_agent)
      chain2 = described_class.new(chain1, incompatible_agent)
      expect(chain2.required_fields).to eq([:input_data])
    end
  end
  
  describe "#provided_fields" do
    it "returns provisions of last agent in chain" do
      chain = described_class.new(producer_agent, consumer_agent)
      expect(chain.provided_fields).to eq([:final_result])
    end
    
    it "handles nested chains" do
      chain1 = described_class.new(producer_agent, consumer_agent)
      chain2 = described_class.new(incompatible_agent, chain1)
      expect(chain2.provided_fields).to eq([:final_result])
    end
  end
end
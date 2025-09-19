# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl"

RSpec.describe RAAF::DSL::PipelineDSL::ParallelAgents do
  let(:agent1) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "Agent1"
      # Context is automatically available through auto-context
      result_transform do
        field :output1, computed: :process
      end
      
      def run
        sleep(0.01) # Simulate work
        { output1: "result1" }
      end
    end
  end
  
  let(:agent2) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "Agent2"
      # Context is automatically available through auto-context
      result_transform do
        field :output2, computed: :process
      end
      
      def run
        sleep(0.01) # Simulate work
        { output2: "result2" }
      end
    end
  end
  
  let(:agent3) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "Agent3"
      # Context is automatically available through auto-context
      result_transform do
        field :output3, computed: :process
      end
      
      def run
        sleep(0.01) # Simulate work
        { output3: "result3" }
      end
    end
  end
  
  describe "#initialize" do
    it "creates a parallel group with multiple agents" do
      parallel = described_class.new([agent1, agent2])
      expect(parallel.agents).to eq([agent1, agent2])
    end
    
    it "flattens nested arrays" do
      parallel = described_class.new([[agent1], agent2])
      expect(parallel.agents).to eq([agent1, agent2])
    end
  end
  
  describe "#|" do
    it "adds more agents to parallel group" do
      parallel = described_class.new([agent1])
      result = parallel | agent2
      expect(result).to be_a(described_class)
      expect(result.agents).to eq([agent1, agent2])
    end
    
    it "chains multiple parallel operations" do
      result = agent1 | agent2 | agent3
      expect(result.agents).to eq([agent1, agent2, agent3])
    end
  end
  
  describe "#>>" do
    it "creates ChainedAgent with parallel group as first" do
      parallel = described_class.new([agent1, agent2])
      result = parallel >> agent3
      expect(result).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
      expect(result.first).to eq(parallel)
      expect(result.second).to eq(agent3)
    end
  end
  
  describe "#execute" do
    let(:context) { RAAF::DSL::ContextVariables.new(input: "test") }
    
    it "executes multiple agents in parallel" do
      parallel = described_class.new([agent1, agent2, agent3])
      
      start_time = Time.now
      result = parallel.execute(context)
      elapsed = Time.now - start_time
      
      # Should be faster than sequential (0.03s)
      expect(elapsed).to be < 0.025
      
      expect(result).to include(
        input: "test",
        output1: "result1",
        output2: "result2",
        output3: "result3"
      )
    end
    
    it "each agent gets a copy of context" do
      # Agents shouldn't interfere with each other
      agent_modifying = Class.new(RAAF::DSL::Agent) do
        agent_name "ModifyingAgent"
        def run
          @context[:shared_value] = "modified"
          {}
        end
      end
      
      parallel = described_class.new([agent1, agent_modifying])
      result = parallel.execute(context)
      
      # Original context should have results but not internal modifications
      expect(result).to include(:output1)
    end
    
    it "handles errors in individual agents gracefully" do
      failing_agent = Class.new(RAAF::DSL::Agent) do
        agent_name "FailingAgent"
        def run
          raise "Test error"
        end
      end
      
      parallel = described_class.new([agent1, failing_agent, agent2])
      
      expect(RAAF.logger).to receive(:error).with(/Error in parallel agent/)
      
      result = parallel.execute(context)
      expect(result).to include(:output1, :output2)
    end
    
    it "skips agents whose requirements aren't met" do
      agent_with_req = Class.new(RAAF::DSL::Agent) do
        agent_name "RequiringAgent"
        # Context is automatically available through auto-context
        # Requires: missing_field
        def run
          { should_not_appear: true }
        end
      end
      
      parallel = described_class.new([agent1, agent_with_req])
      result = parallel.execute(context)
      
      expect(result).to include(:output1)
      expect(result).not_to include(:should_not_appear)
    end
  end
  
  describe "#required_fields" do
    it "returns union of all agents' requirements" do
      agent_a = Class.new(RAAF::DSL::Agent) do
        context do
          required :field_a, :common
        end
      end

      agent_b = Class.new(RAAF::DSL::Agent) do
        context do
          required :field_b, :common
        end
      end
      
      parallel = described_class.new([agent_a, agent_b])
      expect(parallel.required_fields).to contain_exactly(:field_a, :field_b, :common)
    end
  end
  
  describe "#provided_fields" do
    it "returns union of all agents' provisions" do
      parallel = described_class.new([agent1, agent2, agent3])
      expect(parallel.provided_fields).to contain_exactly(:output1, :output2, :output3)
    end
  end
end
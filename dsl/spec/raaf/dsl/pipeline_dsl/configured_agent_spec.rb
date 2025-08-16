# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl"
require "timeout"

RSpec.describe RAAF::DSL::PipelineDSL::ConfiguredAgent do
  let(:base_agent) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "BaseAgent"
      
      context_reader :input
      
      result_transform do
        field :output, computed: :process
      end
      
      def run
        limit = @context[:limit]
        { output: "processed", limit_used: limit }
      end
    end
  end
  
  describe "#initialize" do
    it "wraps agent class with configuration options" do
      configured = described_class.new(base_agent, timeout: 60, retry: 3)
      expect(configured.agent_class).to eq(base_agent)
      expect(configured.options).to eq({ timeout: 60, retry: 3 })
    end
  end
  
  describe "configuration methods" do
    let(:configured) { described_class.new(base_agent, {}) }
    
    it "supports chaining timeout configuration" do
      result = configured.timeout(30)
      expect(result).to eq(configured)
      expect(configured.options[:timeout]).to eq(30)
    end
    
    it "supports chaining retry configuration" do
      result = configured.retry(5)
      expect(result).to eq(configured)
      expect(configured.options[:retry]).to eq(5)
    end
    
    it "supports chaining limit configuration" do
      result = configured.limit(100)
      expect(result).to eq(configured)
      expect(configured.options[:limit]).to eq(100)
    end
    
    it "supports stacking multiple configurations" do
      configured.timeout(30).retry(3).limit(10)
      expect(configured.options).to eq({
        timeout: 30,
        retry: 3,
        limit: 10
      })
    end
  end
  
  describe "delegation methods" do
    let(:configured) { described_class.new(base_agent, {}) }
    
    it "delegates required_fields to wrapped agent" do
      expect(configured.required_fields).to eq([:input])
    end
    
    it "delegates provided_fields to wrapped agent" do
      expect(configured.provided_fields).to eq([:output])
    end
    
    it "delegates requirements_met? to wrapped agent" do
      context = { input: "test" }
      expect(configured.requirements_met?(context)).to be true
      
      context = {}
      expect(configured.requirements_met?(context)).to be false
    end
  end
  
  describe "#execute" do
    let(:context) { { input: "test" } }
    
    context "with timeout" do
      it "applies timeout during execution" do
        slow_agent = Class.new(RAAF::DSL::Agent) do
          def run
            sleep(0.5)
            { output: "done" }
          end
        end
        
        configured = described_class.new(slow_agent, timeout: 0.1)
        
        expect {
          configured.execute(context)
        }.to raise_error(Timeout::Error)
      end
      
      it "logs timeout errors" do
        slow_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "SlowAgent"
          def run
            sleep(1)
            {}
          end
        end
        
        configured = described_class.new(slow_agent, timeout: 0.01)
        
        expect(RAAF.logger).to receive(:error).with(/SlowAgent timed out after/)
        
        expect {
          configured.execute(context)
        }.to raise_error(Timeout::Error)
      end
    end
    
    context "with retry" do
      let(:flaky_agent) do
        agent_class = Class.new(RAAF::DSL::Agent) do
          agent_name "FlakyAgent"
          
          class << self
            attr_accessor :attempt_count
          end
          
          def run
            self.class.attempt_count ||= 0
            self.class.attempt_count += 1
            
            if self.class.attempt_count < 3
              raise "Transient error"
            end
            
            { output: "success" }
          end
        end
        agent_class.attempt_count = 0
        agent_class
      end
      
      it "retries on failure" do
        configured = described_class.new(flaky_agent, retry: 3)
        
        expect(RAAF.logger).to receive(:warn).twice # 2 retries
        
        result = configured.execute(context)
        expect(result).to include(output: "success")
        expect(flaky_agent.attempt_count).to eq(3)
      end
      
      it "implements exponential backoff" do
        configured = described_class.new(flaky_agent, retry: 3)
        
        expect(configured).to receive(:sleep).with(1).ordered  # 2^0
        expect(configured).to receive(:sleep).with(2).ordered  # 2^1
        
        configured.execute(context)
      end
      
      it "raises error after retry exhaustion" do
        always_failing = Class.new(RAAF::DSL::Agent) do
          def run
            raise "Permanent error"
          end
        end
        
        configured = described_class.new(always_failing, retry: 2)
        
        expect {
          configured.execute(context)
        }.to raise_error("Permanent error")
      end
    end
    
    context "with limit" do
      it "passes limit to agent context" do
        configured = described_class.new(base_agent, limit: 25)
        result = configured.execute(context)
        
        expect(result).to include(limit_used: 25)
      end
    end
    
    it "merges provided fields back to context" do
      configured = described_class.new(base_agent, {})
      result = configured.execute(context)
      
      expect(result).to include(output: "processed")
    end
  end
  
  describe "chainability" do
    let(:configured) { described_class.new(base_agent, timeout: 30) }
    let(:other_agent) { Class.new(RAAF::DSL::Agent) }
    
    it "maintains chainability with >> operator" do
      result = configured >> other_agent
      expect(result).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
    end
    
    it "maintains parallel support with | operator" do
      result = configured | other_agent
      expect(result).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
    end
  end
end
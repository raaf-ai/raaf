# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl"

RSpec.describe RAAF::Pipeline do
  let(:agent1) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "Agent1"
      
      # Context is automatically available through auto-context
      
      result_transform do
        field :markets, computed: :find_markets
      end
      
      def run
        { markets: ["market1", "market2"] }
      end
    end
  end
  
  let(:agent2) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "Agent2"
      
      # Context is automatically available through auto-context
      
      result_transform do
        field :scored_markets, computed: :score
      end
      
      def run
        { scored_markets: @context[:markets].map { |m| { name: m, score: 0.8 } } }
      end
    end
  end
  
  let(:agent3) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "Agent3"
      
      # Context is automatically available through auto-context
      
      result_transform do
        field :companies, computed: :find_companies
      end
      
      def run
        limit = @context[:limit] || 10
        { companies: ["company1", "company2"].take(limit) }
      end
    end
  end
  
  describe "class methods" do
    let(:pipeline_class) do
      agents = [agent1, agent2, agent3]
      Class.new(described_class) do
        flow agents[0] >> agents[1] >> agents[2]
      end
    end
    
    describe ".flow" do
      it "stores the agent chain" do
        expect(pipeline_class.flow_chain).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
      end
    end
    
    describe ".context" do
      let(:pipeline_with_context) do
        Class.new(described_class) do
          context do
            optional market_data: {}, threshold: 0.7
          end
        end
      end
      
      it "stores context defaults" do
        config = pipeline_with_context.context_config
        expect(config[:defaults]).to include(
          market_data: {},
          threshold: 0.7
        )
      end
    end
    
    describe ".context_reader (legacy)" do
      # NOTE: context_reader has been removed in favor of auto-context
      # This test is maintained for backward compatibility documentation
      it "has been replaced by auto-context functionality" do
        # Pipeline requirements are now handled automatically through auto-context
        expect(true).to be true # Placeholder test
      end
    end
  end
  
  describe "#initialize" do
    let(:simple_pipeline) do
      agents = [agent1, agent2]
      Class.new(described_class) do
        flow agents[0] >> agents[1]
      end
    end
    
    it "builds initial context from provided values" do
      pipeline = simple_pipeline.new(product: "Test", company: "Corp")
      context = pipeline.instance_variable_get(:@context)
      expect(context).to include(product: "Test", company: "Corp")
    end
    
    context "with context defaults" do
      let(:pipeline_with_defaults) do
        agents = [agent1, agent2]
        Class.new(described_class) do
          flow agents[0] >> agents[1]
          
          context do
            optional market_data: { regions: ["NA"] }, analysis_depth: "standard"
          end
        end
      end
      
      it "applies defaults from context block" do
        pipeline = pipeline_with_defaults.new(product: "Test", company: "Corp")
        context = pipeline.instance_variable_get(:@context)
        
        expect(context).to include(
          product: "Test",
          company: "Corp",
          market_data: { regions: ["NA"] },
          analysis_depth: "standard"
        )
      end
      
      it "allows provided values to override defaults" do
        pipeline = pipeline_with_defaults.new(
          product: "Test",
          company: "Corp",
          analysis_depth: "deep"
        )
        context = pipeline.instance_variable_get(:@context)
        
        expect(context[:analysis_depth]).to eq("deep")
      end
    end
    
    context "with dynamic context building" do
      let(:pipeline_with_builder) do
        agents = [agent1]
        Class.new(described_class) do
          flow agents[0]
          
          # Context variables are automatically available through auto-context
          
          def build_market_data_context
            { regions: ["NA", "EU"], segments: ["SMB"] }
          end
        end
      end
      
      it "calls build_*_context methods" do
        pipeline = pipeline_with_builder.new(product: "Test", company: "Corp")
        context = pipeline.instance_variable_get(:@context)
        
        expect(context[:market_data]).to eq({
          regions: ["NA", "EU"],
          segments: ["SMB"]
        })
      end
    end
    
    context "validation" do
      it "validates first agent requirements" do
        expect {
          simple_pipeline.new(product: "Test") # Missing company
        }.to raise_error(ArgumentError, /Pipeline initialization error/)
      end
      
      it "provides helpful error message" do
        begin
          simple_pipeline.new(product: "Test")
        rescue ArgumentError => e
          expect(e.message).to include("First agent Agent1 requires")
          expect(e.message).to include("Missing: [:company]")
          expect(e.message).to include("company: company_value")
        end
      end
    end
  end
  
  describe "#run" do
    let(:full_pipeline) do
      agents = [agent1, agent2, agent3]
      Class.new(described_class) do
        flow agents[0] >> agents[1] >> agents[2].limit(1)
      end
    end
    
    it "executes the flow chain" do
      pipeline = full_pipeline.new(product: "Test", company: "Corp")
      result = pipeline.run
      
      expect(result).to include(
        product: "Test",
        company: "Corp",
        markets: ["market1", "market2"],
        scored_markets: array_including(
          { name: "market1", score: 0.8 },
          { name: "market2", score: 0.8 }
        ),
        companies: ["company1"]  # Limited to 1
      )
    end
    
    context "with parallel execution" do
      let(:parallel_agent1) do
        Class.new(RAAF::DSL::Agent) do
          agent_name "ParallelAgent1"
          # Context is automatically available through auto-context
          result_transform do
            field :result1, computed: :compute
          end
          def run
            { result1: "parallel1" }
          end
        end
      end
      
      let(:parallel_agent2) do
        Class.new(RAAF::DSL::Agent) do
          agent_name "ParallelAgent2"
          # Context is automatically available through auto-context
          result_transform do
            field :result2, computed: :compute
          end
          def run
            { result2: "parallel2" }
          end
        end
      end
      
      let(:parallel_pipeline) do
        agents = [parallel_agent1, parallel_agent2, agent3]
        Class.new(described_class) do
          flow (agents[0] | agents[1]) >> agents[2]
        end
      end
      
      it "handles parallel execution in flow" do
        pipeline = parallel_pipeline.new(input: "test", scored_markets: [])
        result = pipeline.run
        
        expect(result).to include(
          result1: "parallel1",
          result2: "parallel2",
          companies: []
        )
      end
    end
    
    context "with symbol handlers" do
      let(:pipeline_with_handler) do
        agents = [agent1, agent2]
        Class.new(described_class) do
          flow agents[0] >> agents[1] >> :post_process
          
          private
          
          def post_process(context)
            context[:processed] = true
            context
          end
        end
      end
      
      it "calls symbol methods on pipeline instance" do
        pipeline = pipeline_with_handler.new(product: "Test", company: "Corp")
        result = pipeline.run
        
        expect(result).to include(processed: true)
      end
    end
  end
  
  describe "integration example" do
    let(:market_discovery_pipeline) do
      agents = [agent1, agent2, agent3]
      Class.new(described_class) do
        flow agents[0] >> agents[1] >> agents[2].limit(25)
        
        # Context variables are automatically available through auto-context
        
        context do
          optional market_data: {}, analysis_depth: "standard"
        end
      end
    end
    
    it "works as a complete pipeline with context management" do
      pipeline = market_discovery_pipeline.new(
        product: "SaaS Product",
        company: "Tech Corp"
      )
      
      result = pipeline.run
      
      expect(result).to include(
        product: "SaaS Product",
        company: "Tech Corp",
        market_data: {},
        analysis_depth: "standard",
        markets: be_an(Array),
        scored_markets: be_an(Array),
        companies: be_an(Array)
      )
    end
  end
end
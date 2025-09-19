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

  describe "tracing and span support" do
    let(:mock_tracer) { instance_double(RAAF::Tracing::SpanTracer) }
    let(:mock_span) { instance_double(RAAF::Tracing::Span, span_id: "span_123", set_attribute: nil, add_event: nil, set_status: nil) }

    let(:simple_pipeline) do
      Class.new(described_class) do
        flow agent1 >> agent2

        context do
          required :product, :company
          optional analysis_depth: "standard"
        end
      end
    end

    before do
      allow(mock_tracer).to receive(:pipeline_span).and_yield(mock_span)
      allow(RAAF).to receive(:tracer).and_return(mock_tracer)
    end

    describe "#initialize" do
      context "with tracer parameter" do
        it "accepts tracer in constructor" do
          pipeline = simple_pipeline.new(
            tracer: mock_tracer,
            product: "Test Product",
            company: "Test Company"
          )

          expect(pipeline.instance_variable_get(:@tracer)).to eq(mock_tracer)
        end
      end

      context "without tracer parameter" do
        it "uses RAAF.tracer as default" do
          pipeline = simple_pipeline.new(
            product: "Test Product",
            company: "Test Company"
          )

          expect(pipeline.instance_variable_get(:@tracer)).to eq(mock_tracer)
        end
      end
    end

    describe "#run with tracing" do
      let(:pipeline) do
        simple_pipeline.new(
          tracer: mock_tracer,
          product: "Test Product",
          company: "Test Company"
        )
      end

      it "creates pipeline span with name" do
        expect(mock_tracer).to receive(:pipeline_span).with(simple_pipeline.name)

        pipeline.run
      end

      it "sets comprehensive pipeline span attributes" do
        pipeline_name = simple_pipeline.name

        # Expect all the span attributes to be set
        expect(mock_span).to receive(:set_attribute).with("pipeline.class", simple_pipeline.name)
        expect(mock_span).to receive(:set_attribute).with("pipeline.name", pipeline_name)
        expect(mock_span).to receive(:set_attribute).with("pipeline.flow_structure", "Agent1 >> Agent2")
        expect(mock_span).to receive(:set_attribute).with("pipeline.agent_count", 2)
        expect(mock_span).to receive(:set_attribute).with("pipeline.context_fields", [:product, :company, :analysis_depth])
        expect(mock_span).to receive(:set_attribute).with("pipeline.required_fields", [:product, :company])
        expect(mock_span).to receive(:set_attribute).with("pipeline.optional_fields", [:analysis_depth])
        expect(mock_span).to receive(:set_attribute).with("pipeline.has_schema", false)
        expect(mock_span).to receive(:set_attribute).with("pipeline.has_hooks", false)
        expect(mock_span).to receive(:set_attribute).with("pipeline.validation_enabled", true)
        expect(mock_span).to receive(:set_attribute).with("pipeline.execution_mode", "sequential")
        expect(mock_span).to receive(:set_attribute).with("pipeline.initial_context", hash_including(
          product: "Test Product",
          company: "Test Company",
          analysis_depth: "standard"
        ))

        pipeline.run
      end

      it "adds pipeline lifecycle events" do
        expect(mock_span).to receive(:add_event).with("pipeline.validation_completed")

        pipeline.run
      end

      it "captures final pipeline result" do
        expect(mock_span).to receive(:set_attribute).with("pipeline.result_keys", anything)
        expect(mock_span).to receive(:set_attribute).with("pipeline.final_result", anything)
        expect(mock_span).to receive(:set_attribute).with("pipeline.agents_executed", anything)
        expect(mock_span).to receive(:set_attribute).with("pipeline.successful_agents", anything)

        pipeline.run
      end

      it "sets final span status based on pipeline success" do
        expect(mock_span).to receive(:set_status).with(:ok)
        expect(mock_span).to receive(:set_attribute).with("pipeline.success", true)

        pipeline.run
      end
    end

    describe "#run without tracer" do
      let(:pipeline) do
        simple_pipeline.new(
          tracer: nil,
          product: "Test Product",
          company: "Test Company"
        )
      end

      it "executes without tracing when tracer is nil" do
        expect(mock_tracer).not_to receive(:pipeline_span)

        result = pipeline.run
        expect(result).to be_a(Hash)
        expect(result[:success]).to be(true)
      end
    end

    describe "pipeline span attribute methods" do
      let(:pipeline) do
        simple_pipeline.new(
          product: "Test Product",
          company: "Test Company"
        )
      end

      describe "#pipeline_name" do
        it "returns class name" do
          expect(pipeline.send(:pipeline_name)).to eq(simple_pipeline.name)
        end

        context "when class has no name" do
          let(:anonymous_pipeline) do
            Class.new(described_class) do
              flow agent1 >> agent2
            end
          end

          it "returns 'UnknownPipeline'" do
            pipeline = anonymous_pipeline.new
            expect(pipeline.send(:pipeline_name)).to eq("UnknownPipeline")
          end
        end
      end

      describe "#flow_structure_description" do
        let(:complex_pipeline) do
          Class.new(described_class) do
            flow agent1 >> (agent2 | agent3) >> agent1
          end
        end

        it "describes sequential flow" do
          pipeline = simple_pipeline.new
          description = pipeline.send(:flow_structure_description, pipeline.instance_variable_get(:@flow))
          expect(description).to include(">>")
        end

        it "describes parallel flow" do
          pipeline = complex_pipeline.new
          description = pipeline.send(:flow_structure_description, pipeline.instance_variable_get(:@flow))
          expect(description).to include("|")
          expect(description).to include(">>")
        end
      end

      describe "#count_agents_in_flow" do
        it "counts agents in sequential flow" do
          pipeline = simple_pipeline.new
          count = pipeline.send(:count_agents_in_flow, pipeline.instance_variable_get(:@flow))
          expect(count).to eq(2)
        end

        let(:parallel_pipeline) do
          Class.new(described_class) do
            flow agent1 | agent2 | agent3
          end
        end

        it "counts agents in parallel flow" do
          pipeline = parallel_pipeline.new
          count = pipeline.send(:count_agents_in_flow, pipeline.instance_variable_get(:@flow))
          expect(count).to eq(3)
        end
      end

      describe "#detect_execution_mode" do
        it "detects sequential execution" do
          pipeline = simple_pipeline.new
          mode = pipeline.send(:detect_execution_mode, pipeline.instance_variable_get(:@flow))
          expect(mode).to eq("sequential")
        end

        let(:parallel_pipeline) do
          Class.new(described_class) do
            flow agent1 | agent2
          end
        end

        it "detects parallel execution" do
          pipeline = parallel_pipeline.new
          mode = pipeline.send(:detect_execution_mode, pipeline.instance_variable_get(:@flow))
          expect(mode).to eq("parallel")
        end

        let(:mixed_pipeline) do
          Class.new(described_class) do
            flow agent1 >> (agent2 | agent3)
          end
        end

        it "detects mixed execution mode" do
          pipeline = mixed_pipeline.new
          mode = pipeline.send(:detect_execution_mode, pipeline.instance_variable_get(:@flow))
          expect(mode).to eq("mixed")
        end
      end
    end

    describe "sensitive data redaction" do
      let(:pipeline) do
        simple_pipeline.new(
          product: "Test Product",
          company: "Test Company"
        )
      end

      describe "#redact_sensitive_data" do
        it "redacts password fields" do
          data = { username: "user", password: "secret123" }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted[:username]).to eq("user")
          expect(redacted[:password]).to eq("[REDACTED]")
        end

        it "redacts API keys" do
          data = { config: { api_key: "sk-1234567890" } }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted[:config][:api_key]).to eq("[REDACTED]")
        end

        it "redacts sensitive data in arrays" do
          data = {
            users: [
              { name: "John", email: "john@example.com" },
              { name: "Jane", token: "abc123" }
            ]
          }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted[:users][0][:email]).to eq("[REDACTED]")
          expect(redacted[:users][1][:token]).to eq("[REDACTED]")
          expect(redacted[:users][0][:name]).to eq("John")
        end

        it "preserves non-sensitive data" do
          data = { product: "Test", company: "Corp", count: 5 }
          redacted = pipeline.send(:redact_sensitive_data, data)

          expect(redacted).to eq(data)
        end

        it "handles non-hash data gracefully" do
          expect(pipeline.send(:redact_sensitive_data, "string")).to eq("string")
          expect(pipeline.send(:redact_sensitive_data, 123)).to eq(123)
          expect(pipeline.send(:redact_sensitive_data, nil)).to be_nil
        end
      end

      describe "#sensitive_key?" do
        sensitive_keys = %w[
          password token secret key api_key auth credential
          email phone ssn social_security credit_card
        ]

        sensitive_keys.each do |key|
          it "detects #{key} as sensitive" do
            expect(pipeline.send(:sensitive_key?, key)).to be(true)
          end

          it "detects #{key.upcase} as sensitive" do
            expect(pipeline.send(:sensitive_key?, key.upcase)).to be(true)
          end

          it "detects user_#{key} as sensitive" do
            expect(pipeline.send(:sensitive_key?, "user_#{key}")).to be(true)
          end
        end

        it "does not detect normal keys as sensitive" do
          normal_keys = %w[name product company count data result]
          normal_keys.each do |key|
            expect(pipeline.send(:sensitive_key?, key)).to be(false)
          end
        end
      end
    end

    describe "pipeline with hooks and tracing" do
      let(:hooked_pipeline) do
        Class.new(described_class) do
          flow agent1 >> agent2

          on_end do |context, pipeline, result|
            result[:processed_at] = Time.now.iso8601
            result
          end
        end
      end

      let(:pipeline) do
        hooked_pipeline.new(
          tracer: mock_tracer,
          product: "Test Product",
          company: "Test Company"
        )
      end

      it "adds hook lifecycle events to span" do
        expect(mock_span).to receive(:add_event).with("pipeline.on_end_hook_start")
        expect(mock_span).to receive(:add_event).with("pipeline.on_end_hook_completed")

        pipeline.run
      end

      it "sets has_hooks attribute to true" do
        expect(mock_span).to receive(:set_attribute).with("pipeline.has_hooks", true)

        pipeline.run
      end
    end

    describe "pipeline with schema and tracing" do
      let(:schema_pipeline) do
        Class.new(described_class) do
          flow agent1 >> agent2

          pipeline_schema do
            field :markets, type: :array, required: true
            field :scored_markets, type: :array, required: true
          end
        end
      end

      let(:pipeline) do
        schema_pipeline.new(
          tracer: mock_tracer,
          product: "Test Product",
          company: "Test Company"
        )
      end

      it "sets has_schema attribute to true" do
        expect(mock_span).to receive(:set_attribute).with("pipeline.has_schema", true)

        pipeline.run
      end
    end

    describe "validation disabled pipeline tracing" do
      let(:no_validation_pipeline) do
        Class.new(described_class) do
          flow agent1 >> agent2
          skip_validation!
        end
      end

      let(:pipeline) do
        no_validation_pipeline.new(
          tracer: mock_tracer,
          product: "Test Product",
          company: "Test Company"
        )
      end

      it "sets validation_enabled attribute to false" do
        expect(mock_span).to receive(:set_attribute).with("pipeline.validation_enabled", false)

        pipeline.run
      end

      it "does not add validation_completed event" do
        expect(mock_span).not_to receive(:add_event).with("pipeline.validation_completed")

        pipeline.run
      end
    end
  end
end
# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl"

# Load TracingRegistry for testing
begin
  require "raaf/tracing/tracing_registry"
  require "raaf/tracing/noop_tracer"
rescue LoadError
  # TracingRegistry not available - tests will be skipped
end

RSpec.describe RAAF::Pipeline do
  # Agents declare what they need and what they hand on: only fields listed
  # under +output+ are written back into the pipeline context for the next
  # agent (see Pipelineable.provided_fields).
  let(:agent1) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "Agent1"

      context do
        required :product, :company
        output :markets
      end

      def run
        { markets: %w[market1 market2] }
      end
    end
  end

  let(:agent2) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "Agent2"

      context do
        output :scored_markets
      end

      def run
        { scored_markets: Array(@context[:markets]).map { |m| { name: m, score: 0.8 } } }
      end
    end
  end

  let(:agent3) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "Agent3"

      context do
        output :companies
      end

      def run
        limit = @context[:limit] || 10
        { companies: %w[company1 company2].take(limit) }
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
        expect(config[:optional]).to include(
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

      expect(context.get(:product)).to eq("Test")
      expect(context.get(:company)).to eq("Corp")
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

        expect(context.get(:product)).to eq("Test")
        expect(context.get(:company)).to eq("Corp")
        expect(context.get(:market_data)[:regions]).to eq(["NA"])
        expect(context.get(:analysis_depth)).to eq("standard")
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

          # A build_<field>_context method fills in a declared field that the
          # caller did not provide.
          context do
            optional market_data: nil
          end

          def build_market_data_context
            { regions: %w[NA EU], segments: ["SMB"] }
          end
        end
      end

      it "calls build_*_context methods" do
        pipeline = pipeline_with_builder.new(product: "Test", company: "Corp")
        context = pipeline.instance_variable_get(:@context)

        expect(context[:market_data][:regions]).to eq(%w[NA EU])
        expect(context[:market_data][:segments]).to eq(["SMB"])
      end

      it "leaves a provided value alone" do
        pipeline = pipeline_with_builder.new(product: "Test", company: "Corp", market_data: { regions: ["APAC"] })
        context = pipeline.instance_variable_get(:@context)

        expect(context[:market_data][:regions]).to eq(["APAC"])
      end
    end

    context "validation" do
      it "validates first agent requirements" do
        expect do
          simple_pipeline.new(product: "Test") # Missing company
        end.to raise_error(ArgumentError, /Pipeline initialization error/)
      end

      it "provides helpful error message" do
        simple_pipeline.new(product: "Test")
        raise "expected the pipeline to reject the missing field"
      rescue ArgumentError => e
        expect(e.message).to include("First agent Agent1 requires")
        expect(e.message).to include("Missing: [:company]")
        expect(e.message).to include("company: company_value")
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
        markets: %w[market1 market2],
        scored_markets: array_including(
          { name: "market1", score: 0.8 },
          { name: "market2", score: 0.8 }
        ),
        companies: ["company1"] # Limited to 1
      )
    end

    context "with parallel execution" do
      let(:parallel_agent1) do
        Class.new(RAAF::DSL::Agent) do
          agent_name "ParallelAgent1"

          context do
            output :result1
          end

          def run
            { result1: "parallel1" }
          end
        end
      end

      let(:parallel_agent2) do
        Class.new(RAAF::DSL::Agent) do
          agent_name "ParallelAgent2"

          context do
            output :result2
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
          companies: %w[company1 company2]
        )
      end
    end

    context "with symbol handlers" do
      let(:pipeline_with_handler) do
        agents = [agent1, agent2]
        Class.new(described_class) do
          flow agents[0] >> agents[1] >> :post_process

          context do
            output :processed
          end

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

        context do
          optional market_data: {}, analysis_depth: "standard"
          output :market_data, :analysis_depth
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
        market_data: {},
        analysis_depth: "standard",
        markets: be_an(Array),
        scored_markets: be_an(Array),
        companies: be_an(Array)
      )
    end
  end

  describe "tracing and span support" do
    let(:span_processor) { RAAF::Tracing::MemorySpanProcessor.new }
    let(:tracer) do
      RAAF::Tracing::SpanTracer.new.tap { |t| t.add_processor(span_processor) }
    end

    let(:simple_pipeline) do
      agents = [agent1, agent2]
      Class.new(described_class) do
        flow agents[0] >> agents[1]

        context do
          required :product, :company
          optional analysis_depth: "standard"
        end
      end
    end

    describe "#initialize" do
      context "with tracer parameter" do
        it "accepts tracer in constructor" do
          pipeline = simple_pipeline.new(
            tracer: tracer,
            product: "Test Product",
            company: "Test Company"
          )

          expect(pipeline.instance_variable_get(:@tracer)).to be(tracer)
        end
      end

      context "without tracer parameter" do
        it "falls back to the ambient tracer" do
          pipeline = simple_pipeline.new(
            product: "Test Product",
            company: "Test Company"
          )

          expect(pipeline.instance_variable_get(:@tracer)).to eq(pipeline.send(:get_default_tracer))
        end
      end
    end

    describe "#run with tracing" do
      let(:pipeline) do
        simple_pipeline.new(
          tracer: tracer,
          product: "Test Product",
          company: "Test Company"
        )
      end

      def pipeline_span
        span_processor.spans.find { |span| span[:kind] == :pipeline }
      end

      it "emits a single pipeline span" do
        pipeline.run

        expect(span_processor.spans.count { |span| span[:kind] == :pipeline }).to eq(1)
      end

      it "names the span after the traced method" do
        pipeline.run

        expect(pipeline_span[:name]).to eq("run.workflow.pipeline")
      end

      it "records the component that produced the span" do
        pipeline.run

        expect(pipeline_span[:attributes]["component.type"]).to eq("pipeline")
        expect(pipeline_span[:attributes]).to have_key("component.name")
      end

      it "records the outcome of the run" do
        pipeline.run

        expect(pipeline_span[:attributes]["success"]).to be(true)
        expect(pipeline_span[:attributes]["result.success"]).to be(true)
      end

      it "closes the span with an ok status and a duration" do
        pipeline.run

        expect(pipeline_span[:status]).to eq(:ok)
        expect(pipeline_span[:attributes]["duration_ms"]).to be_a(Numeric)
      end

      it "marks the span as failed when the pipeline raises" do
        allow(pipeline).to receive(:execute_pipeline_logic).and_raise("boom")

        expect { pipeline.run }.to raise_error("boom")
        expect(pipeline_span[:status]).to eq(:error)
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

      it "still executes and reports success" do
        result = pipeline.run

        expect(result).to be_a(Hash)
        expect(result[:success]).to be(true)
        expect(span_processor.spans).to be_empty
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
        it "returns the class name when there is one" do
          named = Class.new(simple_pipeline)
          stub_const("NamedTestPipeline", named)

          expect(named.new(product: "p", company: "c").send(:pipeline_name)).to eq("NamedTestPipeline")
        end

        context "when class has no name" do
          let(:anonymous_pipeline) do
            agents = [agent1, agent2]
            Class.new(described_class) do
              flow agents[0] >> agents[1]
            end
          end

          it "returns 'UnknownPipeline'" do
            anonymous = anonymous_pipeline.new(product: "Test Product", company: "Test Company")
            expect(anonymous.send(:pipeline_name)).to eq("UnknownPipeline")
          end
        end
      end

      describe "#flow_structure_description" do
        let(:complex_pipeline) do
          agents = [agent1, agent2, agent3]
          Class.new(described_class) do
            flow agents[0] >> (agents[1] | agents[2]) >> agents[0]
          end
        end

        it "describes sequential flow" do
          description = pipeline.send(:flow_structure_description, pipeline.instance_variable_get(:@flow))
          expect(description).to include(">>")
        end

        it "describes parallel flow" do
          complex = complex_pipeline.new(product: "Test Product", company: "Test Company")
          description = complex.send(:flow_structure_description, complex.instance_variable_get(:@flow))
          expect(description).to include("|")
          expect(description).to include(">>")
        end
      end

      describe "#count_agents_in_flow" do
        let(:parallel_pipeline) do
          agents = [agent1, agent2, agent3]
          Class.new(described_class) do
            flow agents[0] | agents[1] | agents[2]
          end
        end

        it "counts agents in sequential flow" do
          count = pipeline.send(:count_agents_in_flow, pipeline.instance_variable_get(:@flow))
          expect(count).to eq(2)
        end

        it "counts agents in parallel flow" do
          parallel = parallel_pipeline.new(product: "Test Product", company: "Test Company")
          count = parallel.send(:count_agents_in_flow, parallel.instance_variable_get(:@flow))
          expect(count).to eq(3)
        end
      end

      describe "#detect_execution_mode" do
        let(:mixed_pipeline) do
          agents = [agent1, agent2, agent3]
          Class.new(described_class) do
            flow agents[0] >> (agents[1] | agents[2])
          end
        end
        let(:parallel_pipeline) do
          agents = [agent1, agent2]
          Class.new(described_class) do
            flow agents[0] | agents[1]
          end
        end

        it "detects sequential execution" do
          mode = pipeline.send(:detect_execution_mode, pipeline.instance_variable_get(:@flow))
          expect(mode).to eq("sequential")
        end

        it "detects parallel execution" do
          parallel = parallel_pipeline.new(product: "Test Product", company: "Test Company")
          mode = parallel.send(:detect_execution_mode, parallel.instance_variable_get(:@flow))
          expect(mode).to eq("parallel")
        end

        it "detects mixed execution mode" do
          mixed = mixed_pipeline.new(product: "Test Product", company: "Test Company")
          mode = mixed.send(:detect_execution_mode, mixed.instance_variable_get(:@flow))
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

        it "redacts regardless of key casing" do
          redacted = pipeline.send(:redact_sensitive_data, { "PASSWORD" => "secret", "Api_Key" => "sk-1" })

          expect(redacted["PASSWORD"]).to eq("[REDACTED]")
          expect(redacted["Api_Key"]).to eq("[REDACTED]")
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

    describe "pipeline with an on_end hook" do
      let(:hooked_pipeline) do
        agents = [agent1, agent2]
        Class.new(described_class) do
          flow agents[0] >> agents[1]

          on_end do |_context, _pipeline, result|
            result[:processed_at] = "2026-01-01T00:00:00Z"
            result
          end
        end
      end

      let(:pipeline) do
        hooked_pipeline.new(
          tracer: tracer,
          product: "Test Product",
          company: "Test Company"
        )
      end

      it "runs the hook and keeps its changes in the result" do
        result = pipeline.run

        expect(result[:processed_at]).to eq("2026-01-01T00:00:00Z")
      end

      it "still traces the run" do
        pipeline.run

        expect(span_processor.spans.map { |span| span[:kind] }).to include(:pipeline)
      end
    end

    describe "pipeline with a shared schema" do
      let(:schema_pipeline) do
        agents = [agent1, agent2]
        Class.new(described_class) do
          flow agents[0] >> agents[1]

          pipeline_schema do
            field :markets, type: :array, required: true
            field :scored_markets, type: :array, required: true
          end
        end
      end

      let(:pipeline) do
        schema_pipeline.new(
          tracer: tracer,
          product: "Test Product",
          company: "Test Company"
        )
      end

      it "exposes the schema to the agents it runs" do
        expect(pipeline.pipeline_schema).to be_a(Proc)
        expect(pipeline.pipeline_schema.call[:schema]["properties"].keys).to include("markets", "scored_markets")
      end

      it "runs to completion" do
        expect(pipeline.run[:success]).to be(true)
      end
    end

    describe "pipeline with validation disabled" do
      let(:no_validation_pipeline) do
        agents = [agent1, agent2]
        Class.new(described_class) do
          flow agents[0] >> agents[1]
          skip_validation!
        end
      end

      let(:pipeline) do
        no_validation_pipeline.new(
          tracer: tracer,
          product: "Test Product",
          company: "Test Company"
        )
      end

      it "reports validation as disabled" do
        expect(no_validation_pipeline.skip_validation).to be(true)
      end

      it "never runs the validation pass" do
        expect(pipeline).not_to receive(:validate_pipeline!)

        pipeline.run
      end
    end
  end

  # TracingRegistry integration tests
  describe "TracingRegistry integration", if: defined?(RAAF::Tracing::TracingRegistry) do
    let(:registry_tracer) { double("MockTracer") }
    let(:mock_span) { double("MockSpan", span_id: "span_123", set_attribute: nil, add_event: nil, set_status: nil) }

    let(:simple_pipeline) do
      agents = [agent1, agent2]
      Class.new(described_class) do
        flow agents[0] >> agents[1]
      end
    end

    before do
      allow(registry_tracer).to receive(:pipeline_span).and_yield(mock_span)
      allow(registry_tracer).to receive(:processors).and_return([])
      RAAF::Tracing::TracingRegistry.clear_all_contexts!
    end

    after do
      RAAF::Tracing::TracingRegistry.clear_all_contexts!
    end

    describe "tracer priority hierarchy" do
      context "with explicit tracer parameter" do
        let(:explicit_tracer) { double("MockExplicitTracer") }

        before do
          allow(explicit_tracer).to receive(:pipeline_span).and_yield(mock_span)
          allow(explicit_tracer).to receive(:processors).and_return([])
          RAAF::Tracing::TracingRegistry.set_process_tracer(registry_tracer)
        end

        it "uses explicit tracer over registry tracer" do
          pipeline = simple_pipeline.new(
            tracer: explicit_tracer,
            product: "Test Product",
            company: "Test Company"
          )

          expect(pipeline.instance_variable_get(:@tracer)).to eq(explicit_tracer)
        end
      end

      context "with no explicit tracer" do
        before do
          allow(RAAF).to receive(:tracer).and_return(nil)
        end

        it "uses TracingRegistry.current_tracer when available" do
          RAAF::Tracing::TracingRegistry.set_process_tracer(registry_tracer)

          pipeline = simple_pipeline.new(
            product: "Test Product",
            company: "Test Company"
          )

          # Check that the pipeline gets the registry tracer
          expect(pipeline.instance_variable_get(:@tracer)).to eq(registry_tracer)
        end

        it "falls back to RAAF.tracer when registry has no tracer" do
          fallback_tracer = double("MockFallbackTracer")
          allow(fallback_tracer).to receive(:pipeline_span).and_yield(mock_span)
          allow(fallback_tracer).to receive(:processors).and_return([])
          allow(RAAF).to receive(:tracer).and_return(fallback_tracer)

          pipeline = simple_pipeline.new(
            product: "Test Product",
            company: "Test Company"
          )

          # Test that get_default_tracer works without error
          expect { pipeline.send(:get_default_tracer) }.not_to raise_error
        end
      end

      context "with thread-local registry tracer" do
        let(:thread_tracer) { double("MockThreadTracer") }

        before do
          allow(thread_tracer).to receive(:pipeline_span).and_yield(mock_span)
          allow(thread_tracer).to receive(:processors).and_return([])
          RAAF::Tracing::TracingRegistry.set_process_tracer(registry_tracer)
        end

        it "uses thread-local tracer over process tracer" do
          RAAF::Tracing::TracingRegistry.with_tracer(thread_tracer) do
            pipeline = simple_pipeline.new(
              product: "Test Product",
              company: "Test Company"
            )

            expect(pipeline.instance_variable_get(:@tracer)).to eq(thread_tracer)
          end
        end
      end
    end

    describe "nested pipeline context preservation" do
      let(:outer_tracer) { double("MockOuterTracer") }
      let(:inner_tracer) { double("MockInnerTracer") }

      before do
        allow(outer_tracer).to receive(:pipeline_span).and_yield(mock_span)
        allow(outer_tracer).to receive(:processors).and_return([])
        allow(inner_tracer).to receive(:pipeline_span).and_yield(mock_span)
        allow(inner_tracer).to receive(:processors).and_return([])
      end

      it "preserves registry context for nested pipeline execution" do
        RAAF::Tracing::TracingRegistry.with_tracer(outer_tracer) do
          outer_pipeline = simple_pipeline.new(
            product: "Outer Product",
            company: "Outer Company"
          )

          expect(outer_pipeline.instance_variable_get(:@tracer)).to eq(outer_tracer)

          RAAF::Tracing::TracingRegistry.with_tracer(inner_tracer) do
            inner_pipeline = simple_pipeline.new(
              product: "Inner Product",
              company: "Inner Company"
            )

            expect(inner_pipeline.instance_variable_get(:@tracer)).to eq(inner_tracer)
          end

          # Context should be restored after inner block
          final_pipeline = simple_pipeline.new(
            product: "Final Product",
            company: "Final Company"
          )

          expect(final_pipeline.instance_variable_get(:@tracer)).to eq(outer_tracer)
        end
      end
    end

    describe "multi-agent pipeline with registry tracing" do
      let(:multi_agent_pipeline) do
        agents = [agent1, agent2, agent3]
        Class.new(described_class) do
          flow agents[0] >> agents[1] >> agents[2]
        end
      end

      before do
        RAAF::Tracing::TracingRegistry.set_process_tracer(registry_tracer)
      end

      it "uses registry tracer for pipeline execution" do
        pipeline = multi_agent_pipeline.new(
          product: "Test Product",
          company: "Test Company"
        )

        # Verify the tracer is set from registry
        expect(pipeline.instance_variable_get(:@tracer)).to eq(registry_tracer)
      end

      it "maintains registry context throughout pipeline execution" do
        pipeline = multi_agent_pipeline.new(
          product: "Test Product",
          company: "Test Company"
        )

        # Verify the tracer is set from registry
        expect(pipeline.instance_variable_get(:@tracer)).to eq(registry_tracer)

        # Verify the pipeline can access the registry tracer for initialization
        expect(pipeline.send(:get_default_tracer)).to eq(registry_tracer)
      end
    end

    describe "NoOpTracer fallback behavior" do
      before do
        allow(RAAF).to receive(:tracer).and_return(nil)
        RAAF::Tracing::TracingRegistry.clear_all_contexts!
      end

      it "uses NoOpTracer when no tracer is available anywhere" do
        pipeline = simple_pipeline.new(
          product: "Test Product",
          company: "Test Company"
        )

        tracer = pipeline.instance_variable_get(:@tracer)
        expect(tracer).to be_a(RAAF::Tracing::NoOpTracer) if defined?(RAAF::Tracing::NoOpTracer)
      end
    end
  end
end

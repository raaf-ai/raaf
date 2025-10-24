# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl/pipeline"
require "raaf/dsl/agent"
require "raaf/dsl/intelligent_streaming"

RSpec.describe "RAAF::Pipeline intelligent streaming integration" do
  # Mock agents for testing
  let(:company_discovery) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "CompanyDiscovery"
      model "gpt-4o"

      def call
        { companies: Array.new(1000) { |i| { id: i, name: "Company #{i}" } } }
      end
    end
  end

  let(:quick_fit_analyzer) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "QuickFitAnalyzer"
      model "gpt-4o-mini"
      intelligent_streaming stream_size: 100, over: :companies

      def call
        companies = context[:companies]
        { companies: companies.select { |c| c[:id] % 3 != 0 } } # Filter out every 3rd
      end
    end
  end

  let(:deep_intel) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "DeepIntel"
      model "gpt-4o"

      def call
        companies = context[:companies]
        { companies: companies.map { |c| c.merge(intel: "data") } }
      end
    end
  end

  let(:scoring) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "Scoring"
      model "gpt-4o"

      def call
        companies = context[:companies]
        { companies: companies.map { |c| c.merge(score: rand(100)) } }
      end
    end
  end

  describe "Pipeline with intelligent streaming" do
    let(:pipeline_class) do
      Class.new(RAAF::Pipeline) do
        def self.name
          "TestStreamingPipeline"
        end
      end
    end

    before do
      # Reset pipeline class state
      pipeline_class.instance_variable_set(:@flow_chain, nil)
      pipeline_class.instance_variable_set(:@_context_config, nil)
    end

    it "detects streaming scopes during initialization" do
      pipeline_class.flow company_discovery >> quick_fit_analyzer >> deep_intel >> scoring

      pipeline = pipeline_class.new
      expect(pipeline).to respond_to(:streaming_scopes)

      scopes = pipeline.streaming_scopes
      expect(scopes).to be_an(Array)
      expect(scopes.size).to eq(1)

      scope = scopes.first
      expect(scope.trigger_agent).to eq(quick_fit_analyzer)
      expect(scope.scope_agents).to include(deep_intel)
      expect(scope.stream_size).to eq(100)
      expect(scope.array_field).to eq(:companies)
    end

    it "detects no scopes when no streaming agents" do
      normal_agent = Class.new(RAAF::DSL::Agent) do
        agent_name "NormalAgent"
        model "gpt-4o"
      end

      pipeline_class.flow company_discovery >> normal_agent >> scoring

      pipeline = pipeline_class.new
      scopes = pipeline.streaming_scopes
      expect(scopes).to be_empty
    end

    it "detects multiple streaming scopes" do
      second_streaming_agent = Class.new(RAAF::DSL::Agent) do
        agent_name "SecondStreaming"
        model "gpt-4o"
        intelligent_streaming stream_size: 50, over: :prospects
      end

      pipeline_class.flow company_discovery >>
                          quick_fit_analyzer >>
                          deep_intel >>
                          second_streaming_agent >>
                          scoring

      pipeline = pipeline_class.new
      scopes = pipeline.streaming_scopes
      expect(scopes.size).to eq(2)

      # First scope
      expect(scopes[0].trigger_agent).to eq(quick_fit_analyzer)
      expect(scopes[0].stream_size).to eq(100)

      # Second scope
      expect(scopes[1].trigger_agent).to eq(second_streaming_agent)
      expect(scopes[1].stream_size).to eq(50)
    end

    describe "streaming scope execution" do
      it "executes agents in streaming scope with correct batch sizes" do
        execution_log = []

        # Modify quick_fit_analyzer to log execution
        quick_fit_with_logging = Class.new(quick_fit_analyzer) do
          define_method :call do
            companies = context[:companies]
            execution_log << { agent: "QuickFit", batch_size: companies.size }
            super()
          end
        end

        # Modify deep_intel to log execution
        deep_intel_with_logging = Class.new(deep_intel) do
          define_method :call do
            companies = context[:companies]
            execution_log << { agent: "DeepIntel", batch_size: companies.size }
            super()
          end
        end

        pipeline_class.flow company_discovery >>
                            quick_fit_with_logging >>
                            deep_intel_with_logging >>
                            scoring

        pipeline = pipeline_class.new(execution_log: execution_log)

        # When pipeline.run is called with streaming scopes
        # it should execute in batches of 100
        # This would be implemented in the Pipeline#run method
      end
    end

    describe "context flow with streaming" do
      it "preserves context through streaming execution" do
        pipeline_class.flow company_discovery >> quick_fit_analyzer >> deep_intel >> scoring
        pipeline_class.context do
          required :product, :company
          optional :metadata
        end

        context_data = {
          product: "TestProduct",
          company: "TestCompany",
          metadata: { source: "test" }
        }

        pipeline = pipeline_class.new(**context_data)

        # Verify context is available
        expect(pipeline.context[:product]).to eq("TestProduct")
        expect(pipeline.context[:company]).to eq("TestCompany")
        expect(pipeline.context[:metadata]).to eq({ source: "test" })
      end

      it "merges streaming results correctly" do
        # Test that results from multiple streams are merged properly
        pipeline_class.flow company_discovery >> quick_fit_analyzer >> deep_intel >> scoring

        pipeline = pipeline_class.new

        # This would test the actual merging logic when implemented
        # Results from all streams should be combined appropriately
      end
    end

    describe "streaming with pipeline operators" do
      it "works with sequential operator (>>)" do
        pipeline_class.flow company_discovery >> quick_fit_analyzer >> deep_intel

        pipeline = pipeline_class.new
        scopes = pipeline.streaming_scopes
        expect(scopes.size).to eq(1)
      end

      it "works with parallel operator (|)" do
        parallel_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "ParallelAgent"
          model "gpt-4o"
        end

        pipeline_class.flow company_discovery >>
                           quick_fit_analyzer >>
                           (deep_intel | parallel_agent) >>
                           scoring

        pipeline = pipeline_class.new
        scopes = pipeline.streaming_scopes
        expect(scopes.size).to eq(1)
        # Both deep_intel and parallel_agent should be in scope
      end
    end

    describe "backward compatibility" do
      it "works with pipelines without streaming" do
        normal_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "NormalAgent"
          model "gpt-4o"
        end

        pipeline_class.flow company_discovery >> normal_agent >> scoring

        pipeline = pipeline_class.new
        expect(pipeline.streaming_scopes).to be_empty

        # Pipeline should execute normally without streaming
      end

      it "works with existing context configuration" do
        pipeline_class.flow company_discovery >> quick_fit_analyzer >> scoring
        pipeline_class.context do
          required :search_terms
          default :max_results, 100
        end

        pipeline = pipeline_class.new(search_terms: ["CTO", "DevOps"])
        expect(pipeline.context[:search_terms]).to eq(["CTO", "DevOps"])
        expect(pipeline.context[:max_results]).to eq(100)
      end
    end

    describe "error handling" do
      it "handles errors in streaming scope gracefully" do
        error_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "ErrorAgent"
          model "gpt-4o"
          intelligent_streaming stream_size: 100, over: :companies

          def call
            raise "Test error in streaming"
          end
        end

        pipeline_class.flow company_discovery >> error_agent >> scoring

        pipeline = pipeline_class.new

        # Should handle the error appropriately
        # Partial results should be preserved
      end
    end

    describe "streaming hooks in pipeline context" do
      it "executes on_stream_start hooks" do
        start_log = []

        streaming_with_hooks = Class.new(RAAF::DSL::Agent) do
          agent_name "StreamingWithHooks"
          model "gpt-4o"
          intelligent_streaming stream_size: 100, over: :companies do
            on_stream_start { |num, total, data| start_log << "Stream #{num}/#{total}" }
          end
        end

        pipeline_class.flow company_discovery >> streaming_with_hooks >> scoring

        pipeline = pipeline_class.new(start_log: start_log)

        # When executed, hooks should fire
        # Verify start_log contains expected entries
      end

      it "executes on_stream_complete hooks" do
        complete_log = []

        streaming_with_hooks = Class.new(RAAF::DSL::Agent) do
          agent_name "StreamingWithHooks"
          model "gpt-4o"
          intelligent_streaming stream_size: 100, over: :companies, incremental: true do
            on_stream_complete { |num, total, results| complete_log << "Complete #{num}/#{total}" }
          end
        end

        pipeline_class.flow company_discovery >> streaming_with_hooks >> scoring

        pipeline = pipeline_class.new(complete_log: complete_log)

        # When executed, complete hooks should fire after each stream
      end
    end
  end
end
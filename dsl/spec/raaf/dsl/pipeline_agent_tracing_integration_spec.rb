# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl"
# Skip tracing integration for now - requires raaf-tracing gem to be properly loaded
# require "raaf/tracing/spans"

RSpec.describe "Pipeline and Agent Tracing Integration", skip: "Requires raaf-tracing gem integration" do
  # Create realistic test agents for integration testing
  let(:market_analyzer_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "MarketAnalyzer"
      model "gpt-4o"
      temperature 0.7
      timeout 30

      context do
        required :product, :company
        optional analysis_depth: "standard"
      end

      schema do
        field :markets, type: :array, required: true
        field :analysis_summary, type: :string, required: true
      end

      def run
        {
          success: true,
          markets: [
            { name: "fintech", score: 0.8 },
            { name: "healthtech", score: 0.9 }
          ],
          analysis_summary: "Market analysis completed successfully"
        }
      end
    end
  end

  let(:market_scorer_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "MarketScorer"
      model "gpt-4o"
      temperature 0.3
      retry_count 2
      max_turns 5

      context do
        required :markets
      end

      schema do
        field :scored_markets, type: :array, required: true
        field :overall_confidence, type: :number, required: true
      end

      def run
        {
          success: true,
          scored_markets: markets.map { |m| m.merge(detailed_score: m[:score] + 0.1) },
          overall_confidence: 0.85
        }
      end
    end
  end

  let(:search_term_generator_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "SearchTermGenerator"
      model "gpt-4o"
      circuit_breaker threshold: 3, timeout: 60

      context do
        required :scored_markets
      end

      schema do
        field :search_terms, type: :array, required: true
        field :terms_per_market, type: :integer, required: true
      end

      def run
        terms = scored_markets.flat_map do |market|
          ["#{market[:name]} companies", "#{market[:name]} trends"]
        end

        {
          success: true,
          search_terms: terms,
          terms_per_market: 2
        }
      end
    end
  end

  # Create test pipeline that uses the above agents
  let(:market_discovery_pipeline_class) do
    agents = [market_analyzer_class, market_scorer_class, search_term_generator_class]
    Class.new(RAAF::Pipeline) do
      flow agents[0] >> agents[1] >> agents[2]

      context do
        required :product, :company
        optional analysis_depth: "standard", min_confidence: 0.7
      end

      on_end do |context, pipeline, result|
        result[:pipeline_completed_at] = Time.now.iso8601
        result[:total_markets] = result[:scored_markets]&.length || 0
        result
      end
    end
  end

  # Test with real span collection
  let(:memory_processor) { RAAF::Tracing::MemorySpanProcessor.new }
  let(:tracer) do
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(memory_processor)
    tracer
  end

  describe "end-to-end pipeline tracing" do
    let(:pipeline) do
      market_discovery_pipeline_class.new(
        tracer: tracer,
        product: "AI Analytics Platform",
        company: "TechCorp Inc",
        analysis_depth: "comprehensive"
      )
    end

    before do
      # Mock the RAAF::Runner to avoid actual LLM calls
      allow(RAAF::Runner).to receive(:new) do |**args|
        agent = args[:agent]
        mock_runner = instance_double(RAAF::Runner)

        # Create appropriate mock response based on agent name
        mock_result = case agent.name
                     when "MarketAnalyzer"
                       create_mock_result_for_analyzer
                     when "MarketScorer"
                       create_mock_result_for_scorer
                     when "SearchTermGenerator"
                       create_mock_result_for_generator
                     else
                       create_default_mock_result
                     end

        allow(mock_runner).to receive(:run).and_return(mock_result)
        mock_runner
      end
    end

    it "creates hierarchical spans for pipeline and agents" do
      result = pipeline.run

      # Verify successful execution
      expect(result[:success]).to be(true)
      expect(result[:pipeline_completed_at]).to be_present
      expect(result[:total_markets]).to eq(2)

      # Collect all spans
      spans = memory_processor.spans
      expect(spans.length).to eq(4)  # 1 pipeline + 3 agents

      # Find pipeline span (should be root span with no parent)
      pipeline_span = spans.find { |s| s[:kind] == :pipeline }
      expect(pipeline_span).to be_present
      expect(pipeline_span[:parent_id]).to be_nil
      expect(pipeline_span[:name]).to include("Pipeline")

      # Find agent spans (should be children of pipeline span)
      agent_spans = spans.select { |s| s[:kind] == :agent }
      expect(agent_spans.length).to eq(3)

      # Verify parent-child relationships
      agent_spans.each do |agent_span|
        expect(agent_span[:parent_id]).to eq(pipeline_span[:span_id])
      end

      # Verify agent span names
      agent_names = agent_spans.map { |s| s[:name] }
      expect(agent_names).to include("agent.MarketAnalyzer")
      expect(agent_names).to include("agent.MarketScorer")
      expect(agent_names).to include("agent.SearchTermGenerator")
    end

    it "captures comprehensive pipeline metadata" do
      pipeline.run
      spans = memory_processor.spans
      pipeline_span = spans.find { |s| s[:kind] == :pipeline }

      expect(pipeline_span[:attributes]).to include(
        "pipeline.flow_structure" => kind_of(String),
        "pipeline.agent_count" => 3,
        "pipeline.execution_mode" => "sequential",
        "pipeline.has_hooks" => true,
        "pipeline.validation_enabled" => true,
        "pipeline.success" => true
      )

      # Check initial context is captured and sensitive data redacted
      initial_context = pipeline_span[:attributes]["pipeline.initial_context"]
      expect(initial_context).to include(
        "product" => "AI Analytics Platform",
        "company" => "TechCorp Inc",
        "analysis_depth" => "comprehensive"
      )
    end

    it "captures comprehensive agent metadata for each agent" do
      pipeline.run
      spans = memory_processor.spans
      agent_spans = spans.select { |s| s[:kind] == :agent }

      # Check MarketAnalyzer span
      analyzer_span = agent_spans.find { |s| s[:name] == "agent.MarketAnalyzer" }
      expect(analyzer_span[:attributes]).to include(
        "agent.name" => "MarketAnalyzer",
        "agent.model" => "gpt-4o",
        "agent.temperature" => 0.7,
        "agent.timeout" => 30,
        "agent.has_schema" => true,
        "agent.auto_merge_enabled" => true,
        "agent.parent_pipeline" => "pipeline"
      )

      # Check MarketScorer span
      scorer_span = agent_spans.find { |s| s[:name] == "agent.MarketScorer" }
      expect(scorer_span[:attributes]).to include(
        "agent.name" => "MarketScorer",
        "agent.model" => "gpt-4o",
        "agent.temperature" => 0.3,
        "agent.retry_count" => 2,
        "agent.max_turns" => 5
      )

      # Check SearchTermGenerator span
      generator_span = agent_spans.find { |s| s[:name] == "agent.SearchTermGenerator" }
      expect(generator_span[:attributes]).to include(
        "agent.name" => "SearchTermGenerator",
        "agent.circuit_breaker_enabled" => true,
        "agent.circuit_breaker_threshold" => 3,
        "agent.circuit_breaker_timeout" => 60
      )
    end

    it "captures dialog information for each agent" do
      pipeline.run
      spans = memory_processor.spans
      agent_spans = spans.select { |s| s[:kind] == :agent }

      agent_spans.each do |span|
        # Each agent should have dialog information
        expect(span[:attributes]).to include(
          "dialog.context_size" => kind_of(Integer),
          "dialog.context_keys" => kind_of(Array),
          "dialog.initial_context" => kind_of(Hash),
          "dialog.messages" => kind_of(Array),
          "dialog.message_count" => kind_of(Integer),
          "dialog.total_tokens" => kind_of(Hash)
        )

        # Check token structure
        tokens = span[:attributes]["dialog.total_tokens"]
        expect(tokens).to include(
          "prompt_tokens" => kind_of(Integer),
          "completion_tokens" => kind_of(Integer),
          "total_tokens" => kind_of(Integer)
        )
      end
    end

    it "maintains correct span timing relationships" do
      start_time = Time.now
      pipeline.run
      end_time = Time.now

      spans = memory_processor.spans

      # All spans should have timestamps within execution window
      spans.each do |span|
        span_start = Time.parse(span[:start_time])
        span_end = Time.parse(span[:end_time])

        expect(span_start).to be >= start_time
        expect(span_end).to be <= end_time
        expect(span_end).to be >= span_start
      end

      # Pipeline span should encompass all agent spans
      pipeline_span = spans.find { |s| s[:kind] == :pipeline }
      agent_spans = spans.select { |s| s[:kind] == :agent }

      pipeline_start = Time.parse(pipeline_span[:start_time])
      pipeline_end = Time.parse(pipeline_span[:end_time])

      agent_spans.each do |agent_span|
        agent_start = Time.parse(agent_span[:start_time])
        agent_end = Time.parse(agent_span[:end_time])

        expect(agent_start).to be >= pipeline_start
        expect(agent_end).to be <= pipeline_end
      end
    end

    it "captures pipeline events and lifecycle" do
      pipeline.run
      spans = memory_processor.spans
      pipeline_span = spans.find { |s| s[:kind] == :pipeline }

      # Pipeline should have lifecycle events
      events = pipeline_span[:events]
      expect(events).to be_present

      event_names = events.map { |e| e[:name] }
      expect(event_names).to include("pipeline.validation_completed")
      expect(event_names).to include("pipeline.on_end_hook_start")
      expect(event_names).to include("pipeline.on_end_hook_completed")
    end

    it "captures agent events and lifecycle" do
      pipeline.run
      spans = memory_processor.spans
      agent_spans = spans.select { |s| s[:kind] == :agent }

      agent_spans.each do |span|
        events = span[:events]
        expect(events).to be_present

        event_names = events.map { |e| e[:name] }
        expect(event_names).to include("agent.context_resolved")
        expect(event_names).to include("agent.openai_agent_created")
        expect(event_names).to include("agent.prompt_built")
        expect(event_names).to include("agent.runner_created")
        expect(event_names).to include("agent.llm_execution_completed")
        expect(event_names).to include("agent.result_transformed")
      end
    end

    context "with sensitive data in context" do
      let(:sensitive_pipeline) do
        market_discovery_pipeline_class.new(
          tracer: tracer,
          product: "AI Analytics Platform",
          company: "TechCorp Inc",
          api_key: "sk-proj-secret123456789",
          user_email: "admin@techcorp.com",
          database_password: "super_secret_db_pass"
        )
      end

      it "redacts sensitive data from pipeline context" do
        sensitive_pipeline.run
        spans = memory_processor.spans
        pipeline_span = spans.find { |s| s[:kind] == :pipeline }

        initial_context = pipeline_span[:attributes]["pipeline.initial_context"]
        expect(initial_context["product"]).to eq("AI Analytics Platform")
        expect(initial_context["company"]).to eq("TechCorp Inc")
        expect(initial_context["api_key"]).to eq("[REDACTED]")
        expect(initial_context["user_email"]).to eq("[REDACTED]")
        expect(initial_context["database_password"]).to eq("[REDACTED]")
      end

      it "redacts sensitive data from agent dialog context" do
        sensitive_pipeline.run
        spans = memory_processor.spans
        agent_spans = spans.select { |s| s[:kind] == :agent }

        agent_spans.each do |span|
          dialog_context = span[:attributes]["dialog.initial_context"]
          expect(dialog_context["api_key"]).to eq("[REDACTED]")
          expect(dialog_context["user_email"]).to eq("[REDACTED]")
          expect(dialog_context["database_password"]).to eq("[REDACTED]")
        end
      end
    end
  end

  describe "error scenarios with tracing" do
    let(:error_agent_class) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "ErrorAgent"

        def run
          raise StandardError, "Simulated agent error"
        end
      end
    end

    let(:error_pipeline_class) do
      agent = error_agent_class
      Class.new(RAAF::Pipeline) do
        flow agent
      end
    end

    let(:error_pipeline) do
      error_pipeline_class.new(
        tracer: tracer,
        product: "Test Product"
      )
    end

    before do
      allow(RAAF::Runner).to receive(:new).and_raise(StandardError, "Simulated agent error")
    end

    it "captures error information in spans" do
      result = error_pipeline.run

      # Pipeline should still complete but mark as error
      expect(result[:success]).to be(false)

      spans = memory_processor.spans
      expect(spans).not_to be_empty

      # Check for error status in spans
      error_spans = spans.select { |s| s[:status] == :error }
      expect(error_spans).to be_present
    end
  end

  describe "parallel pipeline tracing" do
    let(:parallel_agent_a) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "ParallelAgentA"

        def run
          { success: true, result_a: "data_a" }
        end
      end
    end

    let(:parallel_agent_b) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "ParallelAgentB"

        def run
          { success: true, result_b: "data_b" }
        end
      end
    end

    let(:parallel_pipeline_class) do
      agents = [parallel_agent_a, parallel_agent_b]
      Class.new(RAAF::Pipeline) do
        flow agents[0] | agents[1]  # Parallel execution
      end
    end

    let(:parallel_pipeline) do
      parallel_pipeline_class.new(
        tracer: tracer,
        product: "Test Product"
      )
    end

    before do
      allow(RAAF::Runner).to receive(:new) do |**args|
        mock_runner = instance_double(RAAF::Runner)
        allow(mock_runner).to receive(:run).and_return(create_default_mock_result)
        mock_runner
      end
    end

    it "traces parallel agent execution correctly" do
      result = parallel_pipeline.run

      spans = memory_processor.spans
      pipeline_span = spans.find { |s| s[:kind] == :pipeline }
      agent_spans = spans.select { |s| s[:kind] == :agent }

      # Should have parallel execution mode
      expect(pipeline_span[:attributes]["pipeline.execution_mode"]).to eq("parallel")

      # Both agents should be children of the pipeline
      agent_spans.each do |span|
        expect(span[:parent_id]).to eq(pipeline_span[:span_id])
      end

      # Agent names should be correct
      agent_names = agent_spans.map { |s| s[:attributes]["agent.name"] }
      expect(agent_names).to contain_exactly("ParallelAgentA", "ParallelAgentB")
    end
  end

  private

  def create_mock_result_for_analyzer
    double("RunResult",
           messages: [
             { role: "user", content: "Analyze markets for AI Analytics Platform" },
             { role: "assistant", content: "Found 2 potential markets: fintech and healthtech" }
           ],
           usage: { prompt_tokens: 45, completion_tokens: 80, total_tokens: 125 })
  end

  def create_mock_result_for_scorer
    double("RunResult",
           messages: [
             { role: "user", content: "Score the identified markets" },
             { role: "assistant", content: "Scored markets with confidence levels" }
           ],
           usage: { prompt_tokens: 35, completion_tokens: 60, total_tokens: 95 })
  end

  def create_mock_result_for_generator
    double("RunResult",
           messages: [
             { role: "user", content: "Generate search terms for scored markets" },
             { role: "assistant", content: "Generated 4 search terms for market research" }
           ],
           usage: { prompt_tokens: 50, completion_tokens: 40, total_tokens: 90 })
  end

  def create_default_mock_result
    double("RunResult",
           messages: [
             { role: "user", content: "Default user message" },
             { role: "assistant", content: "Default assistant response" }
           ],
           usage: { prompt_tokens: 20, completion_tokens: 30, total_tokens: 50 })
  end
end
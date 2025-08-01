# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::ContextPipeline do
  # Mock agent classes for testing
  class TestAnalysisAgent
    def initialize(context:)
      @context = context
    end

    def call
      product = @context.get(:product)
      {
        success: true,
        markets: ["Market A", "Market B"],
        product_analyzed: product
      }
    end
  end

  class TestScoringAgent
    def initialize(context:)
      @context = context
    end

    def call
      markets = @context.get(:markets)
      {
        success: true,
        scored_markets: markets.map { |m| { name: m, score: rand(70..95) } }
      }
    end
  end

  class TestFailingAgent
    def initialize(context:)
      @context = context
    end

    def call
      {
        success: false,
        error: "Processing failed"
      }
    end
  end

  class TestErrorAgent
    def initialize(context:)
      @context = context
    end

    def call
      raise StandardError, "Unexpected error occurred"
    end
  end

  describe "#initialize" do
    it "creates a pipeline with empty context" do
      pipeline = described_class.new
      expect(pipeline.context).to be_a(RAAF::DSL::ContextVariables)
      expect(pipeline.results).to eq({})
      expect(pipeline.stages).to eq([])
    end

    it "creates a pipeline with initial context" do
      pipeline = described_class.new(product: "Test", company: "Acme")
      expect(pipeline.context.get(:product)).to eq("Test")
      expect(pipeline.context.get(:company)).to eq("Acme")
    end

    it "accepts existing ContextVariables" do
      context = RAAF::DSL::ContextVariables.new(product: "Test")
      pipeline = described_class.new(context)
      expect(pipeline.context).to eq(context)
    end
  end

  describe "#pipe" do
    let(:pipeline) { described_class.new(product: "TestProduct") }

    it "adds an agent to the pipeline" do
      pipeline.pipe(TestAnalysisAgent, :analysis)
      
      expect(pipeline.stages.size).to eq(1)
      expect(pipeline.stages.first[:agent_class]).to eq(TestAnalysisAgent)
      expect(pipeline.stages.first[:result_key]).to eq(:analysis)
    end

    it "supports method chaining" do
      result = pipeline
        .pipe(TestAnalysisAgent, :analysis)
        .pipe(TestScoringAgent, :scoring)
      
      expect(result).to eq(pipeline)
      expect(pipeline.stages.size).to eq(2)
    end

    it "accepts static context additions" do
      pipeline.pipe(TestAnalysisAgent, :analysis, debug: true, max_results: 10)
      
      stage = pipeline.stages.first
      expect(stage[:context_additions]).to eq(debug: true, max_results: 10)
    end

    it "accepts dynamic context additions with lambda" do
      pipeline.pipe(TestScoringAgent, :scoring, 
        markets: -> (ctx) { ctx.get(:analysis)[:markets] }
      )
      
      stage = pipeline.stages.first
      expect(stage[:context_additions][:markets]).to be_a(Proc)
    end
  end

  describe "#pipe_if" do
    let(:pipeline) { described_class.new(score: 85) }

    it "adds a conditional stage" do
      pipeline.pipe_if(
        -> (ctx) { ctx.get(:score) > 80 },
        TestAnalysisAgent,
        :analysis
      )
      
      stage = pipeline.stages.first
      expect(stage[:condition]).to be_a(Proc)
      expect(stage[:agent_class]).to eq(TestAnalysisAgent)
    end
  end

  describe "#execute" do
    let(:pipeline) { described_class.new(product: "TestProduct") }

    it "executes all stages in sequence" do
      pipeline
        .pipe(TestAnalysisAgent, :analysis)
        .pipe(TestScoringAgent, :scoring, markets: -> (ctx) { ctx.get(:analysis)[:markets] })
      
      result = pipeline.execute
      
      expect(result[:success]).to be true
      expect(result[:results][:analysis][:success]).to be true
      expect(result[:results][:analysis][:markets]).to eq(["Market A", "Market B"])
      expect(result[:results][:scoring][:success]).to be true
      expect(result[:results][:scoring][:scored_markets]).to be_an(Array)
    end

    it "updates context with successful results" do
      pipeline.pipe(TestAnalysisAgent, :analysis)
      
      pipeline.execute
      
      # Context should contain the analysis result
      expect(pipeline.context.get(:analysis)).to include(success: true, markets: ["Market A", "Market B"])
    end

    it "skips conditional stages when condition is false" do
      pipeline
        .pipe(TestAnalysisAgent, :analysis)
        .pipe_if(-> (ctx) { false }, TestScoringAgent, :scoring)
      
      result = pipeline.execute
      
      expect(result[:results][:analysis][:success]).to be true
      expect(result[:results][:scoring][:skipped]).to be true
      expect(result[:results][:scoring][:reason]).to eq("condition_not_met")
    end

    it "executes conditional stages when condition is true" do
      pipeline
        .pipe(TestAnalysisAgent, :analysis)
        .pipe_if(-> (ctx) { true }, TestScoringAgent, :scoring, 
          markets: -> (ctx) { ctx.get(:analysis)[:markets] }
        )
      
      result = pipeline.execute
      
      expect(result[:results][:scoring][:success]).to be true
    end

    context "with failing agents" do
      it "halts on failure by default" do
        pipeline
          .pipe(TestAnalysisAgent, :analysis)
          .pipe(TestFailingAgent, :failing)
          .pipe(TestScoringAgent, :scoring)
        
        result = pipeline.execute
        
        expect(result[:results][:analysis][:success]).to be true
        expect(result[:results][:failing][:success]).to be false
        expect(result[:results][:scoring]).to be_nil
      end

      it "continues on failure when halt_on_error is false" do
        pipeline
          .pipe(TestAnalysisAgent, :analysis)
          .pipe(TestFailingAgent, :failing)
          .pipe(TestScoringAgent, :scoring, markets: ["Default"])
        
        result = pipeline.execute(halt_on_error: false)
        
        expect(result[:results][:analysis][:success]).to be true
        expect(result[:results][:failing][:success]).to be false
        expect(result[:results][:scoring][:success]).to be true
      end
    end

    context "with error handling" do
      it "catches and handles exceptions" do
        pipeline.pipe(TestErrorAgent, :error)
        
        result = pipeline.execute
        
        expect(result[:success]).to be false
        expect(result[:results][:error][:success]).to be false
        expect(result[:results][:error][:error]).to include("Unexpected error occurred")
      end

      it "calls error handler when provided" do
        error_handled = false
        error_info = nil
        
        pipeline
          .on_error do |error, stage_info|
            error_handled = true
            error_info = { error: error.message, stage: stage_info }
          end
          .pipe(TestErrorAgent, :error)
        
        pipeline.execute
        
        expect(error_handled).to be true
        expect(error_info[:error]).to include("Unexpected error occurred")
        expect(error_info[:stage][:agent_class]).to eq(TestErrorAgent)
      end
    end
  end

  describe "#execute_last" do
    let(:pipeline) { described_class.new(product: "TestProduct") }

    it "returns only the last stage result" do
      pipeline
        .pipe(TestAnalysisAgent, :analysis)
        .pipe(TestScoringAgent, :scoring, markets: ["A", "B"])
      
      result = pipeline.execute_last
      
      expect(result[:success]).to be true
      expect(result[:scored_markets]).to be_an(Array)
      expect(result).not_to have_key(:markets) # From first stage
    end
  end

  describe "#result" do
    let(:pipeline) { described_class.new(product: "TestProduct") }

    it "retrieves intermediate results by key" do
      pipeline
        .pipe(TestAnalysisAgent, :analysis)
        .pipe(TestScoringAgent, :scoring, markets: -> (ctx) { ctx.get(:analysis)[:markets] })
        .execute
      
      analysis_result = pipeline.result(:analysis)
      expect(analysis_result[:success]).to be true
      expect(analysis_result[:markets]).to eq(["Market A", "Market B"])
    end
  end

  describe "#success?" do
    let(:pipeline) { described_class.new }

    it "returns true when all stages succeed" do
      pipeline
        .pipe(TestAnalysisAgent, :analysis)
        .pipe(TestScoringAgent, :scoring, markets: ["A", "B"])
        .execute
      
      expect(pipeline.success?).to be true
    end

    it "returns false when any stage fails" do
      pipeline
        .pipe(TestAnalysisAgent, :analysis)
        .pipe(TestFailingAgent, :failing)
        .execute
      
      expect(pipeline.success?).to be false
    end

    it "considers skipped stages as successful" do
      pipeline
        .pipe(TestAnalysisAgent, :analysis)
        .pipe_if(-> (ctx) { false }, TestScoringAgent, :scoring)
        .execute
      
      expect(pipeline.success?).to be true
    end
  end

  describe "#summary" do
    let(:pipeline) { described_class.new }

    it "provides execution summary" do
      pipeline
        .pipe(TestAnalysisAgent, :analysis)
        .pipe(TestFailingAgent, :failing)
        .pipe_if(-> (ctx) { false }, TestScoringAgent, :scoring)
        .execute
      
      summary = pipeline.summary
      
      expect(summary[:success]).to be false
      expect(summary[:stages_executed]).to eq(3)
      expect(summary[:stages_succeeded]).to eq(1)
      expect(summary[:stages_failed]).to eq(1)
      expect(summary[:stages_skipped]).to eq(1)
      expect(summary[:total_duration_ms]).to be_a(Numeric)
    end
  end

  describe "hooks" do
    let(:pipeline) { described_class.new }
    let(:hook_calls) { [] }

    it "calls before_stage hook" do
      pipeline
        .before_stage do |stage_info, context|
          hook_calls << { type: :before, stage: stage_info[:agent_class].name, context_size: context.size }
        end
        .pipe(TestAnalysisAgent, :analysis)
        .execute
      
      expect(hook_calls.size).to eq(1)
      expect(hook_calls.first[:type]).to eq(:before)
      expect(hook_calls.first[:stage]).to eq("TestAnalysisAgent")
    end

    it "calls after_stage hook" do
      pipeline
        .after_stage do |stage_info, result, context|
          hook_calls << { type: :after, stage: stage_info[:agent_class].name, success: result[:success] }
        end
        .pipe(TestAnalysisAgent, :analysis)
        .execute
      
      expect(hook_calls.size).to eq(1)
      expect(hook_calls.first[:type]).to eq(:after)
      expect(hook_calls.first[:success]).to be true
    end
  end

  describe "real-world usage patterns" do
    it "implements a complete orchestration pipeline" do
      # Simulate a market discovery pipeline
      pipeline = described_class.new(
        product: "ProspectRadar",
        company: "Acme Corp"
      )
      
      results = pipeline
        .on_error { |e, stage| puts "Pipeline error at #{stage[:agent_class]}: #{e.message}" }
        .pipe(TestAnalysisAgent, :analysis)
        .pipe(TestScoringAgent, :scoring, 
          markets: -> (ctx) { ctx.get(:analysis)[:markets] }
        )
        .pipe_if(
          -> (ctx) { ctx.get(:scoring)[:scored_markets].any? { |m| m[:score] > 90 } },
          TestAnalysisAgent,
          :deep_analysis
        )
        .execute
      
      expect(results[:success]).to be true
      expect(results[:results][:analysis]).to be_present
      expect(results[:results][:scoring]).to be_present
      expect(results[:metadata][:stage_durations]).to have_key(:analysis)
      expect(results[:metadata][:stage_durations]).to have_key(:scoring)
    end

    it "handles complex context transformations" do
      pipeline = described_class.new(base_config: { timeout: 30 })
      
      pipeline
        .pipe(TestAnalysisAgent, :analysis, 
          config: -> (ctx) { ctx.get(:base_config).merge(step: "analysis") }
        )
        .pipe(TestScoringAgent, :scoring,
          markets: -> (ctx) { ctx.get(:analysis)[:markets] },
          config: -> (ctx) { ctx.get(:base_config).merge(step: "scoring") }
        )
      
      result = pipeline.execute
      
      expect(result[:success]).to be true
      expect(result[:context][:analysis]).to be_present
      expect(result[:context][:scoring]).to be_present
    end
  end
end
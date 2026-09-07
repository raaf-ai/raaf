# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl/pipeline"
require "raaf/dsl/agent"
require "raaf/dsl/intelligent_streaming/config"
require "raaf/dsl/intelligent_streaming/scope"
require "raaf/dsl/intelligent_streaming/executor"
require "raaf/dsl/core/context_variables"

# End-to-end exercise of a prospect-discovery shaped workload: a pipeline that
# narrows a list of companies stage by stage, and an executor that walks the
# surviving records in streams with state management and progress hooks.
RSpec.describe "IntelligentStreaming End-to-End Integration" do
  let(:context_class) { RAAF::DSL::ContextVariables }

  let(:companies) do
    (1..100).map do |i|
      {
        id: i,
        name: "Company #{i}",
        industry: i.even? ? "tech" : "retail",
        revenue: i * 1_000_000
      }
    end
  end

  let(:company_discovery_agent) do
    all_companies = companies

    Class.new(RAAF::DSL::Agent) do
      agent_name "CompanyDiscovery"
      model "gpt-4o"

      context do
        output :companies, :discovery_complete
      end

      def self.name
        "CompanyDiscovery"
      end

      define_method(:run) { { companies: all_companies, discovery_complete: true } }
    end
  end

  let(:quick_fit_analyzer_agent) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "QuickFitAnalyzer"
      model "gpt-4o-mini"

      intelligent_streaming do
        stream_size 20
        over :companies
      end

      context do
        output :companies, :quick_fit_complete, :rejection_count
      end

      def self.name
        "QuickFitAnalyzer"
      end

      def run
        incoming = Array(context[:companies])
        kept = incoming.select { |company| company[:industry] == "tech" && company[:revenue] > 10_000_000 }

        {
          companies: kept,
          quick_fit_complete: true,
          rejection_count: incoming.size - kept.size
        }
      end
    end
  end

  let(:scoring_agent) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "ScoringAgent"
      model "gpt-4o"

      context do
        output :prospects, :scoring_complete
      end

      def self.name
        "ScoringAgent"
      end

      def run
        scored = Array(context[:companies]).map { |company| company.merge(overall_score: company[:revenue] / 1_000_000) }

        { prospects: scored.sort_by { |company| -company[:overall_score] }, scoring_complete: true }
      end
    end
  end

  # Agent used directly by the executor: it stamps each streamed record.
  let(:record_agent) do
    Class.new do
      def self.name
        "RecordAgent"
      end

      def run(context: {})
        record = context[:current_record]
        context.merge(scored: true, id: record[:id])
      end
    end
  end

  def executor_for(config, context)
    scope = RAAF::DSL::IntelligentStreaming::Scope.new(
      trigger_agent: record_agent,
      scope_agents: [record_agent],
      stream_size: config.stream_size,
      array_field: config.array_field
    )

    RAAF::DSL::IntelligentStreaming::Executor.new(scope: scope, context: context, config: config)
  end

  def config_for(stream_size: 20, over: :items, incremental: false, &block)
    config = RAAF::DSL::IntelligentStreaming::Config.new(
      stream_size: stream_size,
      over: over,
      incremental: incremental
    )
    config.instance_eval(&block) if block
    config
  end

  describe "complete prospect discovery pipeline" do
    let(:pipeline_class) do
      agents = [company_discovery_agent, quick_fit_analyzer_agent, scoring_agent]

      Class.new(RAAF::Pipeline) do
        flow agents[0] >> agents[1] >> agents[2]

        context do
          optional companies: []
        end
      end
    end

    it "narrows the list stage by stage" do
      result = pipeline_class.new.run

      expect(result[:discovery_complete]).to be true
      expect(result[:quick_fit_complete]).to be true
      expect(result[:scoring_complete]).to be true
      expect(result[:prospects].size).to be < 100
      expect(result[:prospects]).to all(include(overall_score: be_a(Integer)))
    end

    it "returns the prospects ranked" do
      prospects = pipeline_class.new.run[:prospects]

      expect(prospects.map { |p| p[:overall_score] }).to eq(prospects.map { |p| p[:overall_score] }.sort.reverse)
    end

    it "keeps the streaming agent's own configuration visible" do
      config = quick_fit_analyzer_agent._intelligent_streaming_config

      expect(config.stream_size).to eq(20)
      expect(config.array_field).to eq(:companies)
    end
  end

  describe "state management integration" do
    let(:items) { (1..100).map { |i| { id: i } } }

    it "skips already-processed records efficiently" do
      processed_ids = (1..50).to_a
      config = config_for do
        skip_if { |record, _context| processed_ids.include?(record[:id]) }
      end

      executor = executor_for(config, context_class.new(items: items))
      executor.execute([record_agent.new])

      expect(executor.execution_stats[:skipped_items]).to eq(50)
      expect(executor.execution_stats[:processed_items]).to eq(50)
    end

    it "loads existing results from cache" do
      cache = (1..50).to_h { |i| [i, { id: i, from_cache: true }] }
      config = config_for do
        skip_if { |record, _context| cache.key?(record[:id]) }
        load_existing { |record, _context| cache[record[:id]] }
      end

      results = executor_for(config, context_class.new(items: items)).execute([record_agent.new])

      expect(results.count { |result| result[:from_cache] }).to eq(50)
      expect(results.size).to eq(100)
    end

    it "persists results after each stream" do
      persisted = []
      config = config_for do
        persist { |stream_results, _context| persisted << stream_results.map { |r| r[:id] } }
      end

      executor_for(config, context_class.new(items: items)).execute([record_agent.new])

      expect(persisted.size).to eq(5)
      expect(persisted.flatten).to eq((1..100).to_a)
    end
  end

  describe "incremental delivery" do
    let(:items) { (1..100).map { |i| { id: i } } }

    it "delivers results per stream when incremental is on" do
      deliveries = []
      config = config_for(incremental: true) do
        on_stream_complete { |num, total, _data, results| deliveries << [num, total, results.size] }
      end

      executor_for(config, context_class.new(items: items)).execute([record_agent.new])

      expect(deliveries).to eq([[1, 5, 20], [2, 5, 20], [3, 5, 20], [4, 5, 20], [5, 5, 20]])
    end

    it "accumulates all results when incremental is off" do
      deliveries = []
      config = config_for do
        on_stream_complete { |all_results| deliveries << all_results.size }
      end

      executor_for(config, context_class.new(items: items)).execute([record_agent.new])

      expect(deliveries).to eq([100])
    end
  end

  describe "large dataset processing" do
    it "processes 1000+ items" do
      items = (1..1_000).map { |i| { id: i } }
      executor = executor_for(config_for(stream_size: 100), context_class.new(items: items))

      results = executor.execute([record_agent.new])

      expect(results.size).to eq(1_000)
      expect(executor.execution_stats[:total_streams]).to eq(10)
    end

    it "scales to 5000+ items without changing the per-stream shape" do
      items = (1..5_000).map { |i| { id: i } }
      sizes = []
      config = config_for(stream_size: 250) do
        on_stream_start { |_num, _total, stream_items| sizes << stream_items.size }
      end

      executor_for(config, context_class.new(items: items)).execute([])

      expect(sizes).to eq([250] * 20)
    end
  end

  describe "real-world pipeline patterns" do
    it "progressively filters data through stages" do
      items = (1..100).map { |i| { id: i, keep: i <= 40 } }

      first_pass = executor_for(
        config_for(stream_size: 25) { skip_if { |record, _context| !record[:keep] } },
        context_class.new(items: items)
      )
      survivors = first_pass.execute([record_agent.new])

      second_pass = executor_for(
        config_for(stream_size: 10, over: :survivors),
        context_class.new(survivors: survivors)
      )
      final = second_pass.execute([record_agent.new])

      expect(survivors.size).to eq(40)
      expect(final.size).to eq(40)
      expect(final).to all(include(scored: true))
    end
  end
end

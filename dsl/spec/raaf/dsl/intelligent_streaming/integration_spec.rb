# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl/pipeline"
require "raaf/dsl/agent"
require "raaf/dsl/intelligent_streaming/config"
require "raaf/dsl/intelligent_streaming/executor"
require "raaf/dsl/core/context_variables"

RSpec.describe "IntelligentStreaming End-to-End Integration" do
  let(:context_class) { RAAF::DSL::Core::ContextVariables }

  # Simulated agents for prospect discovery pipeline
  let(:company_discovery_agent) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "CompanyDiscovery"
      model "gpt-4o"

      def self.name
        "CompanyDiscovery"
      end

      def call
        # Simulate company discovery
        companies = (1..100).map do |i|
          {
            id: i,
            name: "Company #{i}",
            industry: ["tech", "finance", "healthcare", "retail"].sample,
            size: ["small", "medium", "large"].sample,
            location: ["US", "EU", "ASIA"].sample,
            revenue: rand(1_000_000..100_000_000)
          }
        end
        context[:companies] = companies
        context[:discovery_complete] = true
        context
      end
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

      def self.name
        "QuickFitAnalyzer"
      end

      def call
        # Simulate quick fit analysis - filter out 70% of companies
        analyzed = context[:companies].select do |company|
          # Simple fit criteria
          fit_score = 0
          fit_score += 30 if company[:industry] == "tech"
          fit_score += 20 if company[:size] == "medium" || company[:size] == "large"
          fit_score += 25 if company[:revenue] > 10_000_000
          fit_score += 25 if company[:location] == "US"

          company[:fit_score] = fit_score
          fit_score >= 60 # Keep only high-fit companies
        end

        context[:companies] = analyzed
        context[:quick_fit_complete] = true
        context[:rejection_count] = context[:companies].size - analyzed.size
        context
      end
    end
  end

  let(:deep_intelligence_agent) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "DeepIntelligence"
      model "gpt-4o"

      def self.name
        "DeepIntelligence"
      end

      def call
        # Simulate deep intelligence gathering
        enriched = context[:companies].map do |company|
          company.merge(
            technologies: ["Ruby", "Rails", "PostgreSQL", "Redis"].sample(2),
            employee_count: rand(10..10_000),
            growth_rate: rand(5..50),
            funding_stage: ["seed", "series_a", "series_b", "series_c"].sample,
            recent_news: "Recent #{['expansion', 'product launch', 'acquisition', 'partnership'].sample}",
            decision_makers: rand(3..10),
            pain_points: ["scaling", "automation", "integration", "compliance"].sample(2)
          )
        end

        context[:companies] = enriched
        context[:deep_intel_complete] = true
        context
      end
    end
  end

  let(:scoring_agent) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "ScoringAgent"
      model "gpt-4o"

      def self.name
        "ScoringAgent"
      end

      def call
        # Score each company across dimensions
        scored = context[:companies].map do |company|
          company.merge(
            scores: {
              product_market_fit: rand(60..95),
              market_size_potential: rand(50..90),
              competition_level: rand(30..80),
              entry_difficulty: rand(40..85),
              revenue_opportunity: rand(55..95),
              strategic_alignment: rand(65..90)
            },
            overall_score: rand(70..95),
            tier: ["A", "B", "C"].sample
          )
        end

        context[:prospects] = scored.sort_by { |c| -c[:overall_score] }
        context[:scoring_complete] = true
        context
      end
    end
  end

  describe "complete prospect discovery pipeline" do
    context "with streaming enabled" do
      it "discovers prospects with streaming" do
        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow company_discovery_agent >> quick_fit_analyzer_agent >> deep_intelligence_agent >> scoring_agent

          context do
            required :product, :market
          end
        end

        pipeline = pipeline_class.new(
          product: "AI Sales Tool",
          market: "B2B SaaS"
        )

        result = pipeline.run

        expect(result[:discovery_complete]).to be true
        expect(result[:quick_fit_complete]).to be true
        expect(result[:deep_intel_complete]).to be true
        expect(result[:scoring_complete]).to be true

        # Should have filtered companies
        expect(result[:prospects].size).to be < 100
        expect(result[:prospects].size).to be > 0

        # All prospects should have scores
        expect(result[:prospects].all? { |p| p[:overall_score] }).to be true
        expect(result[:prospects].all? { |p| p[:scores] }).to be true
      end

      it "tracks progress with hooks" do
        progress_updates = []

        analyzer_with_hooks = Class.new(quick_fit_analyzer_agent) do
          intelligent_streaming do
            stream_size 20
            over :companies

            on_stream_start do |stream_num, total, context|
              progress_updates << {
                event: :start,
                stream: stream_num,
                total: total,
                companies_count: context[:companies].size
              }
            end

            on_stream_complete do |stream_num, total, results|
              progress_updates << {
                event: :complete,
                stream: stream_num,
                total: total,
                analyzed_count: results[:companies].size
              }
            end
          end
        end

        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow company_discovery_agent >> analyzer_with_hooks >> deep_intelligence_agent >> scoring_agent
        end

        pipeline = pipeline_class.new(
          product: "AI Tool",
          market: "Tech"
        )

        result = pipeline.run

        # Should have progress updates for each stream
        expect(progress_updates).not_to be_empty
        expect(progress_updates.count { |u| u[:event] == :start }).to eq(5) # 100 companies / 20 per stream
        expect(progress_updates.count { |u| u[:event] == :complete }).to eq(5)

        # Progress should be sequential
        start_streams = progress_updates.select { |u| u[:event] == :start }.map { |u| u[:stream] }
        expect(start_streams).to eq([1, 2, 3, 4, 5])
      end

      it "handles mixed processing (skip/new/load)" do
        # Simulate some companies already processed
        processed_companies = Set.new((1..30).to_a) # IDs 1-30 already processed
        cached_results = {}
        (1..30).each do |id|
          cached_results[id] = {
            id: id,
            name: "Cached Company #{id}",
            fit_score: 75,
            cached: true
          }
        end

        analyzer_with_state = Class.new(RAAF::DSL::Agent) do
          agent_name "StatefulAnalyzer"
          model "gpt-4o-mini"

          intelligent_streaming do
            stream_size 20
            over :companies

            skip_if do |company, context|
              processed_companies.include?(company[:id]) && cached_results[company[:id]]
            end

            load_existing do |company, context|
              cached_results[company[:id]]
            end

            persist do |stream_results, context|
              # Simulate persisting to database
              stream_results[:companies].each do |company|
                unless company[:cached]
                  processed_companies.add(company[:id])
                  cached_results[company[:id]] = company
                end
              end
            end
          end

          def call
            # Process only new companies
            analyzed = context[:companies].map do |company|
              if company[:cached]
                company
              else
                company.merge(
                  fit_score: rand(60..90),
                  analyzed_at: Time.now,
                  cached: false
                )
              end
            end

            context[:companies] = analyzed
            context[:state_processing_complete] = true
            context
          end
        end

        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow company_discovery_agent >> analyzer_with_state >> scoring_agent
        end

        pipeline = pipeline_class.new(
          product: "Tool",
          market: "Market"
        )

        result = pipeline.run

        # Should have mix of cached and fresh results
        cached_count = result[:prospects].count { |p| p[:cached] == true }
        fresh_count = result[:prospects].count { |p| p[:cached] == false }

        expect(cached_count).to be > 0
        expect(fresh_count).to be > 0
        expect(cached_count + fresh_count).to eq(result[:prospects].size)
      end
    end
  end

  describe "state management integration" do
    context "skip already-processed records" do
      it "skips already-processed records efficiently" do
        processed_ids = Set.new((1..30).to_a)

        skip_analyzer = Class.new(RAAF::DSL::Agent) do
          agent_name "SkipAnalyzer"

          intelligent_streaming do
            stream_size 20
            over :items

            skip_if do |item, context|
              processed_ids.include?(item[:id])
            end
          end

          def call
            # Only process new items
            context[:items] = context[:items].map do |item|
              item.merge(processed: true, timestamp: Time.now)
            end
            context[:processing_complete] = true
            context
          end
        end

        items = (1..100).map { |i| { id: i, data: "item#{i}" } }
        context = context_class.new(items: items)
        agent = skip_analyzer.new
        config = skip_analyzer.class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        result = executor.execute(context)

        # Should process only new items (70 out of 100)
        processed_items = result[:items].select { |i| i[:timestamp] }
        expect(processed_items.size).to eq(70)
      end
    end

    context "persist results incrementally" do
      it "persists results after each batch" do
        persisted_batches = []

        persist_analyzer = Class.new(RAAF::DSL::Agent) do
          agent_name "PersistAnalyzer"

          intelligent_streaming do
            stream_size 25
            over :items

            persist do |stream_results, context|
              batch_data = {
                timestamp: Time.now,
                count: stream_results[:items].size,
                ids: stream_results[:items].map { |i| i[:id] }
              }
              persisted_batches << batch_data
              true # Simulate successful persistence
            end
          end

          def call
            context[:items] = context[:items].map { |item| item.merge(processed: true) }
            context
          end
        end

        items = (1..100).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = persist_analyzer.new
        config = persist_analyzer.class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        result = executor.execute(context)

        # Should have persisted 4 batches (100 / 25)
        expect(persisted_batches.size).to eq(4)
        expect(persisted_batches.map { |b| b[:count] }).to eq([25, 25, 25, 25])

        # All items should be persisted
        all_persisted_ids = persisted_batches.flat_map { |b| b[:ids] }
        expect(all_persisted_ids.sort).to eq((1..100).to_a)
      end
    end

    context "load cached results" do
      it "loads existing results from cache" do
        # Pre-populate cache
        cache = {}
        (1..100).step(2) do |i|
          cache[i] = { id: i, cached: true, score: 85 }
        end

        cache_analyzer = Class.new(RAAF::DSL::Agent) do
          agent_name "CacheAnalyzer"

          intelligent_streaming do
            stream_size 20
            over :items

            load_existing do |item, context|
              cache[item[:id]]
            end
          end

          def call
            # Process items not in cache
            context[:items] = context[:items].map do |item|
              if item[:cached]
                item # Use cached version
              else
                item.merge(processed: true, score: rand(60..80))
              end
            end
            context[:cache_hits] = context[:items].count { |i| i[:cached] }
            context
          end
        end

        items = (1..100).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = cache_analyzer.new
        config = cache_analyzer.class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        result = executor.execute(context)

        # Should have 50 cache hits (even IDs)
        expect(result[:cache_hits]).to eq(50)

        # Cached items should have score of 85
        cached_items = result[:items].select { |i| i[:cached] }
        expect(cached_items.all? { |i| i[:score] == 85 }).to be true

        # Non-cached items should have different scores
        fresh_items = result[:items].reject { |i| i[:cached] }
        expect(fresh_items.all? { |i| i[:score] != 85 }).to be true
      end
    end
  end

  describe "incremental delivery" do
    context "with incremental: true" do
      it "delivers results per-stream" do
        delivered_results = []

        incremental_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "IncrementalAgent"

          intelligent_streaming do
            stream_size 20
            over :items
            incremental true

            on_stream_complete do |stream_num, total, results|
              delivered_results << {
                stream: stream_num,
                total: total,
                count: results[:items].size,
                first_id: results[:items].first[:id],
                last_id: results[:items].last[:id]
              }
            end
          end

          def call
            context[:items] = context[:items].map { |item| item.merge(processed: true) }
            context
          end
        end

        items = (1..60).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = incremental_agent.new
        config = incremental_agent.class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        result = executor.execute(context)

        # Should have delivered results 3 times (60 / 20)
        expect(delivered_results.size).to eq(3)

        # Each delivery should have correct stream info
        expect(delivered_results[0][:stream]).to eq(1)
        expect(delivered_results[0][:count]).to eq(20)
        expect(delivered_results[0][:first_id]).to eq(1)
        expect(delivered_results[0][:last_id]).to eq(20)

        expect(delivered_results[1][:stream]).to eq(2)
        expect(delivered_results[1][:first_id]).to eq(21)
        expect(delivered_results[1][:last_id]).to eq(40)

        expect(delivered_results[2][:stream]).to eq(3)
        expect(delivered_results[2][:first_id]).to eq(41)
        expect(delivered_results[2][:last_id]).to eq(60)
      end
    end

    context "with incremental: false (default)" do
      it "accumulates all results" do
        final_results = nil

        accumulated_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "AccumulatedAgent"

          intelligent_streaming do
            stream_size 20
            over :items
            incremental false # Explicit, but this is default

            on_stream_complete do |all_results|
              final_results = {
                total_count: all_results[:items].size,
                all_ids: all_results[:items].map { |i| i[:id] }
              }
            end
          end

          def call
            context[:items] = context[:items].map { |item| item.merge(processed: true) }
            context
          end
        end

        items = (1..60).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = accumulated_agent.new
        config = accumulated_agent.class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        result = executor.execute(context)

        # Should have called hook once with all results
        expect(final_results).not_to be_nil
        expect(final_results[:total_count]).to eq(60)
        expect(final_results[:all_ids]).to eq((1..60).to_a)
      end
    end
  end

  describe "large dataset processing" do
    context "with 1000+ items" do
      it "processes 1000+ items efficiently" do
        large_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "LargeDatasetAgent"

          intelligent_streaming do
            stream_size 100
            over :items
          end

          def call
            # Simulate processing
            context[:items] = context[:items].map do |item|
              item.merge(
                processed: true,
                score: rand(100),
                category: ["A", "B", "C"].sample
              )
            end
            context[:total_processed] = context[:items].size
            context
          end
        end

        items = (1..1000).map { |i| { id: i, data: "x" * 100 } }
        context = context_class.new(items: items)
        agent = large_agent.new
        config = large_agent.class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = executor.execute(context)
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        execution_time = end_time - start_time

        expect(result[:total_processed]).to eq(1000)
        expect(result[:items].all? { |i| i[:processed] }).to be true

        # Should complete in reasonable time (< 1 second for 1000 items)
        expect(execution_time).to be < 1.0
      end
    end

    context "with 10000+ items" do
      it "scales to 10000+ items" do
        stream_count = 0

        massive_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "MassiveDatasetAgent"

          intelligent_streaming do
            stream_size 500
            over :items

            on_stream_start do |stream_num, total, context|
              stream_count += 1
            end
          end

          def call
            # Minimal processing for performance test
            context[:items] = context[:items].map { |item| item.merge(p: true) }
            context
          end
        end

        items = (1..10_000).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = massive_agent.new
        config = massive_agent.class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        # Measure memory before
        GC.start
        memory_before = GC.stat[:heap_live_slots]

        result = executor.execute(context)

        # Measure memory after
        GC.start
        memory_after = GC.stat[:heap_live_slots]

        expect(result[:items].size).to eq(10_000)
        expect(stream_count).to eq(20) # 10,000 / 500

        # Memory should not explode
        memory_growth = memory_after - memory_before
        expect(memory_growth).to be < memory_before # Should not double memory
      end
    end
  end

  describe "real-world pipeline patterns" do
    context "multi-stage filtering pipeline" do
      it "progressively filters data through stages" do
        # Stage 1: Initial filter
        filter1_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "Filter1"

          intelligent_streaming do
            stream_size 50
            over :records
          end

          def call
            # Keep 60% of records
            context[:records] = context[:records].select { |r| r[:value] > 40 }
            context[:filter1_complete] = true
            context
          end
        end

        # Stage 2: Deep analysis
        filter2_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "Filter2"

          def call
            # Keep 50% of remaining
            context[:records] = context[:records].select { |r| r[:value] > 60 }
            context[:filter2_complete] = true
            context
          end
        end

        # Stage 3: Final scoring
        scorer = Class.new(RAAF::DSL::Agent) do
          agent_name "Scorer"

          def call
            context[:records] = context[:records].map { |r| r.merge(final_score: r[:value] * 1.5) }
            context[:scoring_complete] = true
            context
          end
        end

        pipeline_class = Class.new(RAAF::DSL::PipelineDSL::Pipeline) do
          flow filter1_agent >> filter2_agent >> scorer
        end

        records = (1..200).map { |i| { id: i, value: rand(100) } }
        pipeline = pipeline_class.new(records: records)
        result = pipeline.run

        expect(result[:filter1_complete]).to be true
        expect(result[:filter2_complete]).to be true
        expect(result[:scoring_complete]).to be true

        # Should have progressively filtered
        expect(result[:records].size).to be < 200
        expect(result[:records].all? { |r| r[:value] > 60 }).to be true
        expect(result[:records].all? { |r| r[:final_score] }).to be true
      end
    end
  end
end
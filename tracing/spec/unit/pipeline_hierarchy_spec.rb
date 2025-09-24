# frozen_string_literal: true

require "spec_helper"
require "raaf/tracing/spans"
require "raaf/tracing/trace_provider"

# Test pipeline hierarchy support in RAAF tracing
# This spec covers task 3 from the coherent tracing refactor spec:
# - Nested pipeline execution contexts
# - Pipeline nesting detection
# - Pipeline span as parent context for contained agents
# - Context isolation in parallel execution branches

RSpec.describe "RAAF Pipeline Hierarchy Tracing" do
  let(:memory_processor) { RAAF::Tracing::MemorySpanProcessor.new }
  let(:tracer) do
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(memory_processor)
    tracer
  end

  # Mock pipeline classes for testing
  let(:outer_pipeline_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :pipeline
      
      attr_reader :name, :inner_pipelines, :tracer
      
      def initialize(name:, tracer: nil, inner_pipelines: [])
        @name = name
        @tracer = tracer
        @inner_pipelines = inner_pipelines
      end
      
      def run
        with_tracing(:run) do
          results = []
          
          # Execute inner pipelines if any
          inner_pipelines.each do |inner_pipeline|
            # Pass current pipeline as parent to create hierarchy
            inner_pipeline.instance_variable_set(:@parent_component, self)
            results << inner_pipeline.run
          end
          
          # Simulate some work
          sleep(0.01)
          
          {
            success: true,
            name: name,
            inner_results: results,
            processed_at: Time.now.iso8601
          }
        end
      end
      
      def collect_span_attributes
        {
          "pipeline.name" => name,
          "pipeline.type" => "outer",
          "pipeline.has_inner_pipelines" => !inner_pipelines.empty?,
          "pipeline.inner_count" => inner_pipelines.length
        }
      end
    end
  end
  
  let(:inner_pipeline_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :pipeline
      
      attr_reader :name, :agents, :tracer, :execution_mode
      
      def initialize(name:, tracer: nil, agents: [], execution_mode: :sequential)
        @name = name
        @tracer = tracer
        @agents = agents
        @execution_mode = execution_mode
      end
      
      def run
        with_tracing(:run) do
          agent_results = []
          
          if execution_mode == :parallel
            # Simulate parallel execution
            threads = agents.map do |agent|
              Thread.new do
                # Each thread gets isolated context
                agent.instance_variable_set(:@parent_component, self)
                agent.run
              end
            end
            agent_results = threads.map(&:value)
          else
            # Sequential execution
            agents.each do |agent|
              agent.instance_variable_set(:@parent_component, self)
              agent_results << agent.run
            end
          end
          
          {
            success: true,
            name: name,
            execution_mode: execution_mode,
            agent_results: agent_results,
            completed_at: Time.now.iso8601
          }
        end
      end
      
      def collect_span_attributes
        {
          "pipeline.name" => name,
          "pipeline.type" => "inner",
          "pipeline.execution_mode" => execution_mode.to_s,
          "pipeline.agent_count" => agents.length,
          "pipeline.nesting_level" => calculate_nesting_level
        }
      end
      
      private
      
      def calculate_nesting_level
        level = 1
        parent = @parent_component
        while parent && parent.respond_to?(:trace_component_type) && parent.class.trace_component_type == :pipeline
          level += 1
          parent = parent.instance_variable_get(:@parent_component)
        end
        level
      end
    end
  end
  
  let(:mock_agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :agent
      
      attr_reader :name, :tracer, :task_id
      
      def initialize(name:, tracer: nil, task_id: nil)
        @name = name
        @tracer = tracer
        @task_id = task_id || SecureRandom.hex(4)
      end
      
      def run
        with_tracing(:run) do
          # Simulate agent work
          sleep(0.005)
          
          {
            success: true,
            agent_name: name,
            task_id: task_id,
            result: "Agent #{name} completed task #{task_id}",
            execution_time: Time.now.iso8601
          }
        end
      end
      
      def collect_span_attributes
        {
          "agent.name" => name,
          "agent.task_id" => task_id,
          "agent.parent_pipeline" => detect_parent_pipeline,
          "agent.nesting_depth" => calculate_nesting_depth
        }
      end
      
      private
      
      def detect_parent_pipeline
        parent = @parent_component
        return "none" unless parent
        
        if parent.respond_to?(:trace_component_type) && parent.class.trace_component_type == :pipeline
          parent.respond_to?(:name) ? parent.name : "unknown_pipeline"
        else
          "not_pipeline"
        end
      end
      
      def calculate_nesting_depth
        depth = 0
        parent = @parent_component
        while parent && parent.respond_to?(:trace_component_type) && parent.class.trace_component_type == :pipeline
          depth += 1
          parent = parent.instance_variable_get(:@parent_component)
        end
        depth
      end
    end
  end
  
  before do
    memory_processor.clear
  end
  
  describe "nested pipeline execution contexts" do
    context "with simple nested pipelines" do
      let(:agent1) { mock_agent_class.new(name: "Agent1", tracer: tracer) }
      let(:agent2) { mock_agent_class.new(name: "Agent2", tracer: tracer) }
      
      let(:inner_pipeline) do
        inner_pipeline_class.new(
          name: "InnerPipeline",
          tracer: tracer,
          agents: [agent1, agent2],
          execution_mode: :sequential
        )
      end
      
      let(:outer_pipeline) do
        outer_pipeline_class.new(
          name: "OuterPipeline",
          tracer: tracer,
          inner_pipelines: [inner_pipeline]
        )
      end
      
      it "creates proper hierarchical span structure" do
        result = outer_pipeline.run
        
        expect(result[:success]).to be(true)
        expect(result[:inner_results].length).to eq(1)
        
        spans = memory_processor.spans
        expect(spans.length).to eq(4) # outer + inner + 2 agents
        
        # Find spans by type
        outer_span = spans.find { |s| s[:attributes]["pipeline.type"] == "outer" }
        inner_span = spans.find { |s| s[:attributes]["pipeline.type"] == "inner" }
        agent_spans = spans.select { |s| s[:kind] == :agent }
        
        expect(outer_span).not_to be_nil
        expect(inner_span).not_to be_nil
        expect(agent_spans.length).to eq(2)
        
        # Verify hierarchy: outer -> inner -> agents
        expect(outer_span[:parent_id]).to be_nil # Root span
        expect(inner_span[:parent_id]).to eq(outer_span[:span_id])
        
        agent_spans.each do |agent_span|
          expect(agent_span[:parent_id]).to eq(inner_span[:span_id])
        end
      end
      
      it "maintains consistent trace IDs throughout hierarchy" do
        outer_pipeline.run
        
        spans = memory_processor.spans
        trace_ids = spans.map { |s| s[:trace_id] }.uniq
        
        expect(trace_ids.length).to eq(1) # All spans in same trace
      end
      
      it "captures nesting level metadata" do
        outer_pipeline.run
        
        spans = memory_processor.spans
        inner_span = spans.find { |s| s[:attributes]["pipeline.type"] == "inner" }
        agent_spans = spans.select { |s| s[:kind] == :agent }
        
        expect(inner_span[:attributes]["pipeline.nesting_level"]).to eq(2)
        
        agent_spans.each do |agent_span|
          expect(agent_span[:attributes]["agent.nesting_depth"]).to eq(2)
          expect(agent_span[:attributes]["agent.parent_pipeline"]).to eq("InnerPipeline")
        end
      end
    end
    
    context "with deeply nested pipelines" do
      let(:leaf_agent) { mock_agent_class.new(name: "LeafAgent", tracer: tracer) }
      
      let(:level3_pipeline) do
        inner_pipeline_class.new(
          name: "Level3Pipeline",
          tracer: tracer,
          agents: [leaf_agent]
        )
      end
      
      let(:level2_pipeline) do
        outer_pipeline_class.new(
          name: "Level2Pipeline",
          tracer: tracer,
          inner_pipelines: [level3_pipeline]
        )
      end
      
      let(:level1_pipeline) do
        outer_pipeline_class.new(
          name: "Level1Pipeline",
          tracer: tracer,
          inner_pipelines: [level2_pipeline]
        )
      end
      
      it "handles deep nesting correctly" do
        result = level1_pipeline.run
        
        expect(result[:success]).to be(true)
        
        spans = memory_processor.spans
        expect(spans.length).to eq(4) # 3 pipelines + 1 agent
        
        # Find spans
        level1_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level1Pipeline" }
        level2_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level2Pipeline" }
        level3_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level3Pipeline" }
        agent_span = spans.find { |s| s[:kind] == :agent }
        
        # Verify parent-child chain
        expect(level1_span[:parent_id]).to be_nil
        expect(level2_span[:parent_id]).to eq(level1_span[:span_id])
        expect(level3_span[:parent_id]).to eq(level2_span[:span_id])
        expect(agent_span[:parent_id]).to eq(level3_span[:span_id])
        
        # Verify nesting levels
        expect(level3_span[:attributes]["pipeline.nesting_level"]).to eq(3)
        expect(agent_span[:attributes]["agent.nesting_depth"]).to eq(3)
      end
    end
  end
  
  describe "pipeline nesting detection" do
    let(:standalone_pipeline) do
      inner_pipeline_class.new(
        name: "StandalonePipeline",
        tracer: tracer,
        agents: [mock_agent_class.new(name: "StandaloneAgent", tracer: tracer)]
      )
    end
    
    let(:nested_pipeline) do
      agent = mock_agent_class.new(name: "NestedAgent", tracer: tracer)
      inner = inner_pipeline_class.new(
        name: "NestedPipeline",
        tracer: tracer,
        agents: [agent]
      )
      
      outer_pipeline_class.new(
        name: "OuterPipeline",
        tracer: tracer,
        inner_pipelines: [inner]
      )
    end
    
    it "correctly identifies standalone pipelines" do
      standalone_pipeline.run
      
      spans = memory_processor.spans
      pipeline_span = spans.find { |s| s[:kind] == :pipeline }
      agent_span = spans.find { |s| s[:kind] == :agent }
      
      expect(pipeline_span[:parent_id]).to be_nil # Root pipeline
      expect(pipeline_span[:attributes]["pipeline.nesting_level"]).to eq(1)
      expect(agent_span[:attributes]["agent.nesting_depth"]).to eq(1)
    end
    
    it "correctly identifies nested pipelines" do
      nested_pipeline.run
      
      spans = memory_processor.spans
      outer_span = spans.find { |s| s[:attributes]["pipeline.name"] == "OuterPipeline" }
      inner_span = spans.find { |s| s[:attributes]["pipeline.name"] == "NestedPipeline" }
      
      expect(outer_span[:parent_id]).to be_nil # Root
      expect(inner_span[:parent_id]).to eq(outer_span[:span_id]) # Nested
      
      expect(outer_span[:attributes]["pipeline.nesting_level"]).to eq(1)
      expect(inner_span[:attributes]["pipeline.nesting_level"]).to eq(2)
    end
    
    it "detects nesting depth in span attributes" do
      nested_pipeline.run
      
      spans = memory_processor.spans
      agent_span = spans.find { |s| s[:kind] == :agent }
      
      expect(agent_span[:attributes]["agent.nesting_depth"]).to eq(2)
      expect(agent_span[:attributes]["agent.parent_pipeline"]).to eq("NestedPipeline")
    end
  end
  
  describe "pipeline span as parent context for contained agents" do
    let(:agent1) { mock_agent_class.new(name: "Agent1", tracer: tracer) }
    let(:agent2) { mock_agent_class.new(name: "Agent2", tracer: tracer) }
    let(:agent3) { mock_agent_class.new(name: "Agent3", tracer: tracer) }
    
    let(:pipeline) do
      inner_pipeline_class.new(
        name: "ContainerPipeline",
        tracer: tracer,
        agents: [agent1, agent2, agent3],
        execution_mode: :sequential
      )
    end
    
    it "sets pipeline span as parent for all contained agents" do
      pipeline.run
      
      spans = memory_processor.spans
      pipeline_span = spans.find { |s| s[:kind] == :pipeline }
      agent_spans = spans.select { |s| s[:kind] == :agent }
      
      expect(pipeline_span).not_to be_nil
      expect(agent_spans.length).to eq(3)
      
      # All agents should have pipeline as parent
      agent_spans.each do |agent_span|
        expect(agent_span[:parent_id]).to eq(pipeline_span[:span_id])
        expect(agent_span[:trace_id]).to eq(pipeline_span[:trace_id])
      end
    end
    
    it "maintains agent execution order in span timestamps" do
      pipeline.run
      
      spans = memory_processor.spans
      agent_spans = spans.select { |s| s[:kind] == :agent }
                          .sort_by { |s| Time.parse(s[:start_time]) }
      
      # Sequential execution means Agent1 starts before Agent2, etc.
      agent_names = agent_spans.map { |s| s[:attributes]["agent.name"] }
      expect(agent_names).to eq(["Agent1", "Agent2", "Agent3"])
      
      # Each agent should start after the previous one finishes (sequential)
      (0...agent_spans.length - 1).each do |i|
        current_end = Time.parse(agent_spans[i][:end_time])
        next_start = Time.parse(agent_spans[i + 1][:start_time])
        expect(next_start).to be >= current_end
      end
    end
    
    it "captures agent metadata with pipeline context" do
      pipeline.run
      
      spans = memory_processor.spans
      agent_spans = spans.select { |s| s[:kind] == :agent }
      
      agent_spans.each do |span|
        attributes = span[:attributes]
        expect(attributes["agent.parent_pipeline"]).to eq("ContainerPipeline")
        expect(attributes["agent.nesting_depth"]).to eq(1)
        expect(attributes["agent.task_id"]).not_to be_nil
      end
    end
  end
  
  describe "context isolation in parallel execution branches" do
    let(:parallel_agent1) { mock_agent_class.new(name: "ParallelAgent1", tracer: tracer) }
    let(:parallel_agent2) { mock_agent_class.new(name: "ParallelAgent2", tracer: tracer) }
    let(:parallel_agent3) { mock_agent_class.new(name: "ParallelAgent3", tracer: tracer) }
    
    let(:parallel_pipeline) do
      inner_pipeline_class.new(
        name: "ParallelPipeline",
        tracer: tracer,
        agents: [parallel_agent1, parallel_agent2, parallel_agent3],
        execution_mode: :parallel
      )
    end
    
    it "creates isolated spans for parallel agents" do
      pipeline_result = parallel_pipeline.run
      
      expect(pipeline_result[:success]).to be(true)
      expect(pipeline_result[:execution_mode]).to eq(:parallel)
      
      spans = memory_processor.spans
      pipeline_span = spans.find { |s| s[:kind] == :pipeline }
      agent_spans = spans.select { |s| s[:kind] == :agent }
      
      expect(agent_spans.length).to eq(3)
      
      # All agents should have the same parent (pipeline) but different span IDs
      span_ids = agent_spans.map { |s| s[:span_id] }
      expect(span_ids.uniq.length).to eq(3) # All unique
      
      # All should have same parent and trace
      agent_spans.each do |span|
        expect(span[:parent_id]).to eq(pipeline_span[:span_id])
        expect(span[:trace_id]).to eq(pipeline_span[:trace_id])
      end
    end
    
    it "ensures parallel execution timing" do
      start_time = Time.now
      parallel_pipeline.run
      end_time = Time.now
      
      spans = memory_processor.spans
      agent_spans = spans.select { |s| s[:kind] == :agent }
      
      # All agents should start around the same time (parallel execution)
      start_times = agent_spans.map { |s| Time.parse(s[:start_time]) }
      start_time_spread = start_times.max - start_times.min
      
      # Parallel execution should have minimal start time spread
      expect(start_time_spread).to be < 0.1 # Less than 100ms spread
      
      # All agent spans should overlap (indicating parallel execution)
      agent_spans.combination(2).each do |span1, span2|
        start1 = Time.parse(span1[:start_time])
        end1 = Time.parse(span1[:end_time])
        start2 = Time.parse(span2[:start_time])
        end2 = Time.parse(span2[:end_time])
        
        # Check for time overlap (parallel execution)
        overlap = [end1, end2].min - [start1, start2].max
        expect(overlap).to be > 0 # Should overlap
      end
    end
    
    it "maintains context isolation between parallel branches" do
      parallel_pipeline.run
      
      spans = memory_processor.spans
      agent_spans = spans.select { |s| s[:kind] == :agent }
      
      # Each agent should have unique task IDs (no shared state)
      task_ids = agent_spans.map { |s| s[:attributes]["agent.task_id"] }
      expect(task_ids.uniq.length).to eq(3)
      
      # All should share same parent pipeline but have different execution contexts
      agent_spans.each do |span|
        expect(span[:attributes]["agent.parent_pipeline"]).to eq("ParallelPipeline")
        expect(span[:attributes]["agent.nesting_depth"]).to eq(1)
      end
    end
    
    context "with nested parallel pipelines" do
      let(:nested_parallel_pipeline) do
        inner = inner_pipeline_class.new(
          name: "InnerParallelPipeline",
          tracer: tracer,
          agents: [parallel_agent1, parallel_agent2],
          execution_mode: :parallel
        )
        
        outer_pipeline_class.new(
          name: "OuterParallelContainer",
          tracer: tracer,
          inner_pipelines: [inner]
        )
      end
      
      it "maintains isolation across nested parallel contexts" do
        nested_parallel_pipeline.run
        
        spans = memory_processor.spans
        outer_span = spans.find { |s| s[:attributes]["pipeline.name"] == "OuterParallelContainer" }
        inner_span = spans.find { |s| s[:attributes]["pipeline.name"] == "InnerParallelPipeline" }
        agent_spans = spans.select { |s| s[:kind] == :agent }
        
        # Verify hierarchy
        expect(outer_span[:parent_id]).to be_nil
        expect(inner_span[:parent_id]).to eq(outer_span[:span_id])
        
        agent_spans.each do |agent_span|
          expect(agent_span[:parent_id]).to eq(inner_span[:span_id])
          expect(agent_span[:attributes]["agent.parent_pipeline"]).to eq("InnerParallelPipeline")
          expect(agent_span[:attributes]["agent.nesting_depth"]).to eq(2)
        end
      end
    end
  end
  
  describe "comprehensive pipeline hierarchy validation" do
    # Complex scenario: mixed sequential and parallel execution with nesting
    let(:complex_hierarchy) do
      # Level 3 agents
      leaf_agent1 = mock_agent_class.new(name: "LeafAgent1", tracer: tracer)
      leaf_agent2 = mock_agent_class.new(name: "LeafAgent2", tracer: tracer)
      
      # Level 2 parallel pipeline
      parallel_pipeline = inner_pipeline_class.new(
        name: "ParallelLeafPipeline",
        tracer: tracer,
        agents: [leaf_agent1, leaf_agent2],
        execution_mode: :parallel
      )
      
      # Level 2 sequential agent
      sequential_agent = mock_agent_class.new(name: "SequentialAgent", tracer: tracer)
      
      # Level 1 container (sequential execution of parallel pipeline + agent)
      container_pipeline = inner_pipeline_class.new(
        name: "ContainerPipeline",
        tracer: tracer,
        agents: [sequential_agent],
        execution_mode: :sequential
      )
      
      # Root pipeline
      outer_pipeline_class.new(
        name: "RootPipeline",
        tracer: tracer,
        inner_pipelines: [parallel_pipeline, container_pipeline]
      )
    end
    
    it "handles complex mixed execution patterns" do
      result = complex_hierarchy.run
      
      expect(result[:success]).to be(true)
      expect(result[:inner_results].length).to eq(2)
      
      spans = memory_processor.spans
      expect(spans.length).to eq(6) # 1 root + 2 inner + 3 agents
      
      # Verify span types
      pipeline_spans = spans.select { |s| s[:kind] == :pipeline }
      agent_spans = spans.select { |s| s[:kind] == :agent }
      
      expect(pipeline_spans.length).to eq(3)
      expect(agent_spans.length).to eq(3)
      
      # Find specific spans
      root_span = spans.find { |s| s[:attributes]["pipeline.name"] == "RootPipeline" }
      parallel_span = spans.find { |s| s[:attributes]["pipeline.name"] == "ParallelLeafPipeline" }
      container_span = spans.find { |s| s[:attributes]["pipeline.name"] == "ContainerPipeline" }
      
      # Verify hierarchy structure
      expect(root_span[:parent_id]).to be_nil # Root
      expect(parallel_span[:parent_id]).to eq(root_span[:span_id])
      expect(container_span[:parent_id]).to eq(root_span[:span_id])
      
      # Verify agent parent relationships
      leaf_agents = agent_spans.select { |s| s[:attributes]["agent.name"].include?("Leaf") }
      sequential_agents = agent_spans.select { |s| s[:attributes]["agent.name"].include?("Sequential") }
      
      leaf_agents.each do |agent|
        expect(agent[:parent_id]).to eq(parallel_span[:span_id])
        expect(agent[:attributes]["agent.parent_pipeline"]).to eq("ParallelLeafPipeline")
      end
      
      sequential_agents.each do |agent|
        expect(agent[:parent_id]).to eq(container_span[:span_id])
        expect(agent[:attributes]["agent.parent_pipeline"]).to eq("ContainerPipeline")
      end
    end
    
    it "maintains trace coherence across all hierarchy levels" do
      complex_hierarchy.run
      
      spans = memory_processor.spans
      trace_ids = spans.map { |s| s[:trace_id] }.uniq
      
      # All spans should share the same trace ID
      expect(trace_ids.length).to eq(1)
      
      # Verify timing coherence
      root_span = spans.find { |s| s[:attributes]["pipeline.name"] == "RootPipeline" }
      root_start = Time.parse(root_span[:start_time])
      root_end = Time.parse(root_span[:end_time])
      
      spans.each do |span|
        span_start = Time.parse(span[:start_time])
        span_end = Time.parse(span[:end_time])
        
        # All spans should be within root pipeline timeframe
        expect(span_start).to be >= root_start
        expect(span_end).to be <= root_end
      end
    end
    
    it "captures accurate nesting metadata" do
      complex_hierarchy.run
      
      spans = memory_processor.spans
      
      # Check nesting levels
      root_span = spans.find { |s| s[:attributes]["pipeline.name"] == "RootPipeline" }
      parallel_span = spans.find { |s| s[:attributes]["pipeline.name"] == "ParallelLeafPipeline" }
      container_span = spans.find { |s| s[:attributes]["pipeline.name"] == "ContainerPipeline" }
      
      # Root pipeline doesn't have nesting level (it's the outermost)
      expect(parallel_span[:attributes]["pipeline.nesting_level"]).to eq(2)
      expect(container_span[:attributes]["pipeline.nesting_level"]).to eq(2)
      
      # Check agent nesting depths
      agent_spans = spans.select { |s| s[:kind] == :agent }
      agent_spans.each do |agent_span|
        expect(agent_span[:attributes]["agent.nesting_depth"]).to eq(2)
      end
    end
  end
end
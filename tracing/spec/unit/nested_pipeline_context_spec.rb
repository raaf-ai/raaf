# frozen_string_literal: true

require "spec_helper"
require "raaf/tracing/spans"
require "raaf/tracing/trace_provider"

# Test nested pipeline execution contexts for RAAF tracing
# This spec covers task 3.1: nested pipeline execution contexts

RSpec.describe "RAAF Nested Pipeline Context Management" do
  let(:memory_processor) { RAAF::Tracing::MemorySpanProcessor.new }
  let(:tracer) do
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(memory_processor)
    tracer
  end

  # Mock nested pipeline implementation that closely resembles real RAAF::Pipeline behavior
  let(:nested_pipeline_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :pipeline
      
      attr_reader :name, :children, :tracer, :context_data, :nesting_level
      
      def initialize(name:, tracer: nil, children: [], context_data: {}, nesting_level: 1)
        @name = name
        @tracer = tracer
        @children = children
        @context_data = context_data
        @nesting_level = nesting_level
      end
      
      def run
        with_tracing(:run) do
          # Add nested execution event
          if current_span
            current_span[:events] << {
              name: "pipeline.execution_start",
              timestamp: Time.now.utc.iso8601,
              attributes: {
                children_count: children.length,
                nesting_level: nesting_level
              }
            }
          end
          
          child_results = []
          
          # Execute children with proper parent context
          children.each_with_index do |child, index|
            # Pass current pipeline as parent to create hierarchy
            child.instance_variable_set(:@parent_component, self)
            
            # Add context isolation event
            if current_span
              current_span[:events] << {
                name: "pipeline.child_execution_start",
                timestamp: Time.now.utc.iso8601,
                attributes: {
                  child_name: child.respond_to?(:name) ? child.name : "child_#{index}",
                  child_type: child.class.trace_component_type.to_s
                }
              }
            end
            
            result = child.run
            child_results << result
            
            # Add completion event
            if current_span
              current_span[:events] << {
                name: "pipeline.child_execution_end",
                timestamp: Time.now.utc.iso8601,
                attributes: {
                  child_name: child.respond_to?(:name) ? child.name : "child_#{index}",
                  success: result[:success] != false
                }
              }
            end
          end
          
          # Simulate some pipeline work
          sleep(0.001)
          
          {
            success: true,
            pipeline_name: name,
            nesting_level: nesting_level,
            child_results: child_results,
            context_data: context_data,
            execution_id: SecureRandom.hex(8)
          }
        end
      end
      
      def collect_span_attributes
        {
          "pipeline.name" => name,
          "pipeline.nesting_level" => nesting_level,
          "pipeline.children_count" => children.length,
          "pipeline.context_keys" => context_data.keys.sort,
          "pipeline.execution_mode" => "nested",
          "pipeline.parent_type" => detect_parent_type
        }
      end
      
      private
      
      def detect_parent_type
        parent = @parent_component
        return "none" unless parent
        
        if parent.respond_to?(:trace_component_type)
          parent.class.trace_component_type.to_s
        else
          "unknown"
        end
      end
    end
  end
  
  # Mock agent that can be nested in pipelines
  let(:nested_agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :agent
      
      attr_reader :name, :tracer, :work_duration, :agent_id
      
      def initialize(name:, tracer: nil, work_duration: 0.002, agent_id: nil)
        @name = name
        @tracer = tracer
        @work_duration = work_duration
        @agent_id = agent_id || SecureRandom.hex(4)
      end
      
      def run
        with_tracing(:run) do
          # Add execution events
          if current_span
            current_span[:events] << {
              name: "agent.execution_start",
              timestamp: Time.now.utc.iso8601,
              attributes: {
                agent_id: agent_id,
                work_duration: work_duration
              }
            }
          end
          
          # Simulate agent work
          sleep(work_duration)
          
          if current_span
            current_span[:events] << {
              name: "agent.execution_end",
              timestamp: Time.now.utc.iso8601,
              attributes: {
                agent_id: agent_id,
                completed: true
              }
            }
          end
          
          {
            success: true,
            agent_name: name,
            agent_id: agent_id,
            work_duration: work_duration,
            parent_pipeline: detect_parent_pipeline,
            execution_context: calculate_execution_context
          }
        end
      end
      
      def collect_span_attributes
        {
          "agent.name" => name,
          "agent.agent_id" => agent_id,
          "agent.work_duration" => work_duration,
          "agent.parent_pipeline" => detect_parent_pipeline,
          "agent.execution_context" => calculate_execution_context,
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
      
      def calculate_execution_context
        parent = @parent_component
        context_path = []
        
        while parent
          if parent.respond_to?(:name)
            context_path.unshift(parent.name)
          end
          parent = parent.instance_variable_get(:@parent_component)
        end
        
        context_path.join(" -> ")
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
  
  describe "single level nesting" do
    let(:leaf_agent) { nested_agent_class.new(name: "LeafAgent", tracer: tracer) }
    let(:inner_pipeline) do
      nested_pipeline_class.new(
        name: "InnerPipeline",
        tracer: tracer,
        children: [leaf_agent],
        context_data: { level: "inner", task_id: "task_123" },
        nesting_level: 2
      )
    end
    
    let(:outer_pipeline) do
      nested_pipeline_class.new(
        name: "OuterPipeline",
        tracer: tracer,
        children: [inner_pipeline],
        context_data: { level: "outer", session_id: "session_456" },
        nesting_level: 1
      )
    end
    
    it "creates proper nested execution contexts" do
      result = outer_pipeline.run
      
      expect(result[:success]).to be(true)
      expect(result[:pipeline_name]).to eq("OuterPipeline")
      expect(result[:child_results]).to have(1).item
      
      inner_result = result[:child_results].first
      expect(inner_result[:pipeline_name]).to eq("InnerPipeline")
      expect(inner_result[:child_results]).to have(1).item
      
      agent_result = inner_result[:child_results].first
      expect(agent_result[:agent_name]).to eq("LeafAgent")
      expect(agent_result[:parent_pipeline]).to eq("InnerPipeline")
    end
    
    it "maintains hierarchical span relationships" do
      outer_pipeline.run
      
      spans = memory_processor.spans
      expect(spans.length).to eq(3) # outer + inner + agent
      
      # Find spans by name
      outer_span = spans.find { |s| s[:attributes]["pipeline.name"] == "OuterPipeline" }
      inner_span = spans.find { |s| s[:attributes]["pipeline.name"] == "InnerPipeline" }
      agent_span = spans.find { |s| s[:attributes]["agent.name"] == "LeafAgent" }
      
      # Verify hierarchy
      expect(outer_span[:parent_id]).to be_nil # Root
      expect(inner_span[:parent_id]).to eq(outer_span[:span_id])
      expect(agent_span[:parent_id]).to eq(inner_span[:span_id])
      
      # Verify trace consistency
      trace_ids = [outer_span[:trace_id], inner_span[:trace_id], agent_span[:trace_id]]
      expect(trace_ids.uniq.length).to eq(1)
    end
    
    it "captures context isolation at each level" do
      outer_pipeline.run
      
      spans = memory_processor.spans
      outer_span = spans.find { |s| s[:attributes]["pipeline.name"] == "OuterPipeline" }
      inner_span = spans.find { |s| s[:attributes]["pipeline.name"] == "InnerPipeline" }
      agent_span = spans.find { |s| s[:attributes]["agent.name"] == "LeafAgent" }
      
      # Verify context data isolation
      expect(outer_span[:attributes]["pipeline.context_keys"]).to include("level", "session_id")
      expect(inner_span[:attributes]["pipeline.context_keys"]).to include("level", "task_id")
      
      # Verify nesting levels
      expect(outer_span[:attributes]["pipeline.nesting_level"]).to eq(1)
      expect(inner_span[:attributes]["pipeline.nesting_level"]).to eq(2)
      expect(agent_span[:attributes]["agent.nesting_depth"]).to eq(2)
    end
    
    it "captures execution events throughout the hierarchy" do
      outer_pipeline.run
      
      spans = memory_processor.spans
      
      # Check outer pipeline events
      outer_span = spans.find { |s| s[:attributes]["pipeline.name"] == "OuterPipeline" }
      outer_events = outer_span[:events]
      
      expect(outer_events.map { |e| e[:name] }).to include(
        "pipeline.execution_start",
        "pipeline.child_execution_start",
        "pipeline.child_execution_end"
      )
      
      # Check inner pipeline events
      inner_span = spans.find { |s| s[:attributes]["pipeline.name"] == "InnerPipeline" }
      inner_events = inner_span[:events]
      
      expect(inner_events.map { |e| e[:name] }).to include(
        "pipeline.execution_start",
        "pipeline.child_execution_start",
        "pipeline.child_execution_end"
      )
      
      # Check agent events
      agent_span = spans.find { |s| s[:attributes]["agent.name"] == "LeafAgent" }
      agent_events = agent_span[:events]
      
      expect(agent_events.map { |e| e[:name] }).to include(
        "agent.execution_start",
        "agent.execution_end"
      )
    end
  end
  
  describe "multi-level nesting" do
    let(:leaf_agents) do
      [
        nested_agent_class.new(name: "LeafAgent1", tracer: tracer),
        nested_agent_class.new(name: "LeafAgent2", tracer: tracer)
      ]
    end
    
    let(:level3_pipeline) do
      nested_pipeline_class.new(
        name: "Level3Pipeline",
        tracer: tracer,
        children: leaf_agents,
        context_data: { level: 3, batch_id: "batch_789" },
        nesting_level: 3
      )
    end
    
    let(:level2_pipeline) do
      nested_pipeline_class.new(
        name: "Level2Pipeline",
        tracer: tracer,
        children: [level3_pipeline],
        context_data: { level: 2, workflow_id: "workflow_456" },
        nesting_level: 2
      )
    end
    
    let(:level1_pipeline) do
      nested_pipeline_class.new(
        name: "Level1Pipeline",
        tracer: tracer,
        children: [level2_pipeline],
        context_data: { level: 1, session_id: "session_123" },
        nesting_level: 1
      )
    end
    
    it "handles deep nesting correctly" do
      result = level1_pipeline.run
      
      expect(result[:success]).to be(true)
      expect(result[:nesting_level]).to eq(1)
      
      # Navigate through nested results
      level2_result = result[:child_results].first
      expect(level2_result[:nesting_level]).to eq(2)
      
      level3_result = level2_result[:child_results].first
      expect(level3_result[:nesting_level]).to eq(3)
      
      agent_results = level3_result[:child_results]
      expect(agent_results.length).to eq(2)
      
      agent_results.each do |agent_result|
        expect(agent_result[:parent_pipeline]).to eq("Level3Pipeline")
        expect(agent_result[:execution_context]).to eq("Level1Pipeline -> Level2Pipeline -> Level3Pipeline")
      end
    end
    
    it "creates correct span hierarchy for deep nesting" do
      level1_pipeline.run
      
      spans = memory_processor.spans
      expect(spans.length).to eq(5) # 3 pipelines + 2 agents
      
      # Find spans
      level1_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level1Pipeline" }
      level2_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level2Pipeline" }
      level3_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level3Pipeline" }
      agent_spans = spans.select { |s| s[:kind] == :agent }
      
      # Verify parent-child chain
      expect(level1_span[:parent_id]).to be_nil
      expect(level2_span[:parent_id]).to eq(level1_span[:span_id])
      expect(level3_span[:parent_id]).to eq(level2_span[:span_id])
      
      agent_spans.each do |agent_span|
        expect(agent_span[:parent_id]).to eq(level3_span[:span_id])
        expect(agent_span[:attributes]["agent.nesting_depth"]).to eq(3)
      end
    end
    
    it "maintains context isolation at all levels" do
      level1_pipeline.run
      
      spans = memory_processor.spans
      
      # Check each level has its own context
      level1_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level1Pipeline" }
      level2_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level2Pipeline" }
      level3_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level3Pipeline" }
      
      expect(level1_span[:attributes]["pipeline.context_keys"]).to include("level", "session_id")
      expect(level2_span[:attributes]["pipeline.context_keys"]).to include("level", "workflow_id")
      expect(level3_span[:attributes]["pipeline.context_keys"]).to include("level", "batch_id")
      
      # Verify nesting levels are correct
      expect(level1_span[:attributes]["pipeline.nesting_level"]).to eq(1)
      expect(level2_span[:attributes]["pipeline.nesting_level"]).to eq(2)
      expect(level3_span[:attributes]["pipeline.nesting_level"]).to eq(3)
    end
    
    it "captures timing relationships correctly" do
      start_time = Time.now
      level1_pipeline.run
      end_time = Time.now
      
      spans = memory_processor.spans
      
      # All spans should be within execution window
      spans.each do |span|
        span_start = Time.parse(span[:start_time])
        span_end = Time.parse(span[:end_time])
        
        expect(span_start).to be >= start_time
        expect(span_end).to be <= end_time
        expect(span_end).to be >= span_start
      end
      
      # Outer spans should encompass inner spans
      level1_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level1Pipeline" }
      level2_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level2Pipeline" }
      level3_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level3Pipeline" }
      
      level1_start = Time.parse(level1_span[:start_time])
      level1_end = Time.parse(level1_span[:end_time])
      level2_start = Time.parse(level2_span[:start_time])
      level2_end = Time.parse(level2_span[:end_time])
      level3_start = Time.parse(level3_span[:start_time])
      level3_end = Time.parse(level3_span[:end_time])
      
      # Level 1 encompasses Level 2
      expect(level2_start).to be >= level1_start
      expect(level2_end).to be <= level1_end
      
      # Level 2 encompasses Level 3
      expect(level3_start).to be >= level2_start
      expect(level3_end).to be <= level2_end
    end
  end
  
  describe "context isolation in complex scenarios" do
    context "with shared data between contexts" do
      let(:shared_data) { { shared_value: "global", counter: 0 } }
      
      let(:context_aware_agent_class) do
        Class.new(nested_agent_class) do
          attr_reader :context_modifications
          
          def initialize(name:, tracer: nil, context_modifications: {})
            super(name: name, tracer: tracer)
            @context_modifications = context_modifications
          end
          
          def run
            with_tracing(:run) do
              # Simulate context modifications
              modified_context = context_modifications.dup
              
              {
                success: true,
                agent_name: name,
                context_modifications: modified_context,
                parent_pipeline: detect_parent_pipeline,
                isolation_test: "isolated_#{name}_#{SecureRandom.hex(4)}"
              }
            end
          end
          
          def collect_span_attributes
            super.merge({
              "agent.context_modifications" => context_modifications.keys.sort,
              "agent.isolation_test" => "isolated_#{name}"
            })
          end
        end
      end
      
      let(:agent1) do
        context_aware_agent_class.new(
          name: "ContextAgent1",
          tracer: tracer,
          context_modifications: { local_value: "agent1", agent1_counter: 1 }
        )
      end
      
      let(:agent2) do
        context_aware_agent_class.new(
          name: "ContextAgent2",
          tracer: tracer,
          context_modifications: { local_value: "agent2", agent2_counter: 2 }
        )
      end
      
      let(:pipeline1) do
        nested_pipeline_class.new(
          name: "Pipeline1",
          tracer: tracer,
          children: [agent1],
          context_data: shared_data.merge({ pipeline_id: "p1" })
        )
      end
      
      let(:pipeline2) do
        nested_pipeline_class.new(
          name: "Pipeline2",
          tracer: tracer,
          children: [agent2],
          context_data: shared_data.merge({ pipeline_id: "p2" })
        )
      end
      
      let(:root_pipeline) do
        nested_pipeline_class.new(
          name: "RootPipeline",
          tracer: tracer,
          children: [pipeline1, pipeline2],
          context_data: shared_data.merge({ root: true })
        )
      end
      
      it "maintains context isolation between sibling pipelines" do
        result = root_pipeline.run
        
        expect(result[:success]).to be(true)
        expect(result[:child_results].length).to eq(2)
        
        # Check that each child pipeline executed with its own context
        pipeline1_result = result[:child_results].first
        pipeline2_result = result[:child_results].last
        
        expect(pipeline1_result[:pipeline_name]).to eq("Pipeline1")
        expect(pipeline2_result[:pipeline_name]).to eq("Pipeline2")
        
        # Check agent results for isolation
        agent1_result = pipeline1_result[:child_results].first
        agent2_result = pipeline2_result[:child_results].first
        
        expect(agent1_result[:isolation_test]).to include("ContextAgent1")
        expect(agent2_result[:isolation_test]).to include("ContextAgent2")
        expect(agent1_result[:isolation_test]).not_to eq(agent2_result[:isolation_test])
      end
      
      it "captures context isolation in spans" do
        root_pipeline.run
        
        spans = memory_processor.spans
        
        pipeline1_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Pipeline1" }
        pipeline2_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Pipeline2" }
        agent1_span = spans.find { |s| s[:attributes]["agent.name"] == "ContextAgent1" }
        agent2_span = spans.find { |s| s[:attributes]["agent.name"] == "ContextAgent2" }
        
        # Each pipeline should have different context keys
        expect(pipeline1_span[:attributes]["pipeline.context_keys"]).to include("pipeline_id")
        expect(pipeline2_span[:attributes]["pipeline.context_keys"]).to include("pipeline_id")
        
        # Agents should have different isolation markers
        expect(agent1_span[:attributes]["agent.isolation_test"]).to eq("isolated_ContextAgent1")
        expect(agent2_span[:attributes]["agent.isolation_test"]).to eq("isolated_ContextAgent2")
        
        # Different context modifications
        expect(agent1_span[:attributes]["agent.context_modifications"]).to include("local_value", "agent1_counter")
        expect(agent2_span[:attributes]["agent.context_modifications"]).to include("local_value", "agent2_counter")
      end
    end
  end
end
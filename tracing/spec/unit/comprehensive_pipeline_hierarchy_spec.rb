# frozen_string_literal: true

require "spec_helper"
require "raaf/tracing/spans"
require "raaf/tracing/trace_provider"

# Comprehensive test for all pipeline hierarchy features
# This spec covers task 3.5: ensuring all pipeline hierarchy tests pass
# Combines all aspects: nesting, detection, parent context, and isolation

RSpec.describe "RAAF Pipeline Hierarchy - Comprehensive Integration" do
  let(:memory_processor) { RAAF::Tracing::MemorySpanProcessor.new }
  let(:tracer) do
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(memory_processor)
    tracer
  end

  # Complete mock pipeline that combines all hierarchy features
  let(:comprehensive_pipeline_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :pipeline
      
      attr_reader :name, :children, :tracer, :execution_mode, :context_data
      
      def initialize(name:, tracer: nil, children: [], execution_mode: :sequential, context_data: {})
        @name = name
        @tracer = tracer
        @children = children
        @execution_mode = execution_mode
        @context_data = context_data
      end
      
      def run
        with_tracing(:run) do
          # Comprehensive pipeline execution with all hierarchy features
          hierarchy_info = analyze_hierarchy
          
          # Add comprehensive execution start event
          if current_span
            current_span[:events] << {
              name: "pipeline.comprehensive_execution_start",
              timestamp: Time.now.utc.iso8601,
              attributes: hierarchy_info.merge({
                children_count: children.length,
                execution_mode: execution_mode.to_s
              })
            }
          end
          
          child_results = execute_children_with_hierarchy
          
          # Add execution completion event
          if current_span
            current_span[:events] << {
              name: "pipeline.comprehensive_execution_end",
              timestamp: Time.now.utc.iso8601,
              attributes: {
                successful_children: child_results.count { |r| r[:success] },
                hierarchy_verified: verify_hierarchy_integrity(child_results)
              }
            }
          end
          
          {
            success: true,
            pipeline_name: name,
            execution_mode: execution_mode,
            hierarchy_info: hierarchy_info,
            child_results: child_results,
            context_data: context_data,
            hierarchy_verification: verify_hierarchy_integrity(child_results)
          }
        end
      end
      
      def collect_span_attributes
        hierarchy_info = analyze_hierarchy
        
        {
          "pipeline.name" => name,
          "pipeline.execution_mode" => execution_mode.to_s,
          "pipeline.children_count" => children.length,
          "pipeline.is_root" => hierarchy_info[:is_root],
          "pipeline.nesting_level" => hierarchy_info[:nesting_level],
          "pipeline.has_pipeline_ancestors" => hierarchy_info[:has_pipeline_ancestors],
          "pipeline.context_keys" => context_data.keys.sort,
          "pipeline.hierarchy_complexity" => calculate_hierarchy_complexity,
          "pipeline.supports_parallel" => execution_mode == :parallel,
          "pipeline.parent_type" => detect_parent_type
        }
      end
      
      private
      
      def analyze_hierarchy
        parent_chain = build_parent_chain
        
        {
          is_root: parent_chain.empty?,
          nesting_level: parent_chain.length + 1,
          parent_chain: parent_chain,
          has_pipeline_ancestors: parent_chain.any? { |p| p[:type] == :pipeline },
          immediate_parent_type: detect_parent_type,
          hierarchy_depth: calculate_hierarchy_depth,
          nesting_pattern: classify_nesting_pattern(parent_chain)
        }
      end
      
      def execute_children_with_hierarchy
        case execution_mode
        when :parallel
          execute_parallel_with_isolation
        when :sequential
          execute_sequential_with_context
        else
          raise ArgumentError, "Unknown execution mode: #{execution_mode}"
        end
      end
      
      def execute_parallel_with_isolation
        # Parallel execution with context isolation
        threads = children.map.with_index do |child, index|
          Thread.new do
            # Create isolated context for each branch
            isolated_context = create_isolated_context(index)
            
            # Set up parent relationship with isolation
            child.instance_variable_set(:@parent_component, self)
            child.instance_variable_set(:@branch_index, index)
            child.instance_variable_set(:@isolated_context, isolated_context)
            
            # Add branch execution event
            if current_span
              current_span[:events] << {
                name: "pipeline.parallel_branch_start",
                timestamp: Time.now.utc.iso8601,
                attributes: {
                  branch_index: index,
                  child_name: child.respond_to?(:name) ? child.name : "child_#{index}",
                  thread_id: Thread.current.object_id,
                  isolation_id: isolated_context[:isolation_id]
                }
              }
            end
            
            result = child.run
            
            result.merge({
              branch_index: index,
              thread_id: Thread.current.object_id,
              isolated_context: isolated_context,
              execution_mode: :parallel
            })
          end
        end
        
        results = threads.map(&:value)
        
        # Add parallel completion event
        if current_span
          current_span[:events] << {
            name: "pipeline.parallel_execution_completed",
            timestamp: Time.now.utc.iso8601,
            attributes: {
              total_branches: results.length,
              unique_threads: results.map { |r| r[:thread_id] }.uniq.length,
              isolation_verified: verify_parallel_isolation(results)
            }
          }
        end
        
        results
      end
      
      def execute_sequential_with_context
        # Sequential execution with context propagation
        results = []
        accumulated_context = context_data.dup
        
        children.each_with_index do |child, index|
          # Set up parent relationship with accumulated context
          child.instance_variable_set(:@parent_component, self)
          child.instance_variable_set(:@child_index, index)
          child.instance_variable_set(:@accumulated_context, accumulated_context)
          
          # Add sequential execution event
          if current_span
            current_span[:events] << {
              name: "pipeline.sequential_child_start",
              timestamp: Time.now.utc.iso8601,
              attributes: {
                child_index: index,
                child_name: child.respond_to?(:name) ? child.name : "child_#{index}",
                accumulated_context_keys: accumulated_context.keys.sort
              }
            }
          end
          
          result = child.run
          
          # Accumulate context from child result
          if result.is_a?(Hash) && result[:context_data]
            accumulated_context.merge!(result[:context_data])
          end
          
          result_with_context = result.merge({
            child_index: index,
            accumulated_context: accumulated_context.dup,
            execution_mode: :sequential
          })
          
          results << result_with_context
        end
        
        results
      end
      
      def create_isolated_context(branch_index)
        {
          branch_index: branch_index,
          isolation_id: SecureRandom.hex(8),
          thread_id: Thread.current.object_id,
          created_at: Time.now.utc.iso8601,
          parent_context: context_data.dup.freeze # Read-only access to parent context
        }
      end
      
      def build_parent_chain
        chain = []
        current_parent = @parent_component
        
        while current_parent
          parent_info = {
            name: current_parent.respond_to?(:name) ? current_parent.name : "unnamed",
            type: detect_component_type(current_parent),
            class_name: current_parent.class.name,
            level: chain.length + 1
          }
          
          chain << parent_info
          current_parent = current_parent.instance_variable_get(:@parent_component)
        end
        
        chain
      end
      
      def detect_component_type(component)
        if component.respond_to?(:trace_component_type)
          component.class.trace_component_type
        elsif component.class.name&.include?("Pipeline")
          :pipeline
        elsif component.class.name&.include?("Agent")
          :agent
        else
          :unknown
        end
      end
      
      def detect_parent_type
        parent = @parent_component
        return :none unless parent
        
        detect_component_type(parent)
      end
      
      def calculate_hierarchy_depth
        build_parent_chain.length + 1
      end
      
      def calculate_hierarchy_complexity
        complexity = {
          depth: calculate_hierarchy_depth,
          children_count: children.length,
          parallel_branches: execution_mode == :parallel ? children.length : 0,
          nested_pipelines: children.count { |c| detect_component_type(c) == :pipeline }
        }
        
        # Calculate complexity score
        score = complexity[:depth] * 2 +
                complexity[:children_count] +
                complexity[:parallel_branches] * 1.5 +
                complexity[:nested_pipelines] * 3
        
        {
          details: complexity,
          score: score.round(1)
        }
      end
      
      def classify_nesting_pattern(parent_chain)
        return "root" if parent_chain.empty?
        
        pipeline_count = parent_chain.count { |p| p[:type] == :pipeline }
        
        case pipeline_count
        when 0
          "non_pipeline_parent"
        when 1
          "single_pipeline_nesting"
        when 2..3
          "moderate_pipeline_nesting"
        else
          "deep_pipeline_nesting"
        end
      end
      
      def verify_hierarchy_integrity(child_results)
        checks = {
          all_children_executed: child_results.length == children.length,
          all_successful: child_results.all? { |r| r[:success] },
          proper_parent_context: verify_parent_context_propagation(child_results),
          isolation_maintained: execution_mode == :parallel ? verify_parallel_isolation(child_results) : true,
          context_accumulated: execution_mode == :sequential ? verify_context_accumulation(child_results) : true
        }
        
        checks[:overall_integrity] = checks.values.all?
        checks
      end
      
      def verify_parent_context_propagation(child_results)
        child_results.all? do |result|
          # Each child should have reference to this pipeline as parent
          result.key?(:execution_mode) && 
          (result[:execution_mode] == execution_mode)
        end
      end
      
      def verify_parallel_isolation(results)
        return true unless execution_mode == :parallel
        
        # Check that each parallel branch has unique isolation
        isolation_ids = results.map { |r| r.dig(:isolated_context, :isolation_id) }.compact
        thread_ids = results.map { |r| r[:thread_id] }.compact
        
        isolation_ids.uniq.length == isolation_ids.length &&
        thread_ids.uniq.length == thread_ids.length
      end
      
      def verify_context_accumulation(results)
        return true unless execution_mode == :sequential
        
        # Check that context accumulates through sequential execution
        previous_context_size = 0
        
        results.all? do |result|
          current_context_size = result.dig(:accumulated_context)&.keys&.length || 0
          valid = current_context_size >= previous_context_size
          previous_context_size = current_context_size
          valid
        end
      end
    end
  end
  
  # Comprehensive agent that works with all hierarchy features
  let(:comprehensive_agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :agent
      
      attr_reader :name, :tracer, :capabilities
      
      def initialize(name:, tracer: nil, capabilities: {})
        @name = name
        @tracer = tracer
        @capabilities = capabilities
      end
      
      def run
        with_tracing(:run) do
          # Comprehensive agent execution with hierarchy awareness
          execution_context = analyze_execution_context
          
          # Add comprehensive execution event
          if current_span
            current_span[:events] << {
              name: "agent.comprehensive_execution",
              timestamp: Time.now.utc.iso8601,
              attributes: execution_context.slice(
                :pipeline_nesting_depth,
                :execution_mode,
                :has_isolation,
                :has_accumulated_context
              )
            }
          end
          
          # Simulate work based on capabilities
          work_duration = capabilities[:work_duration] || 0.001
          sleep(work_duration)
          
          {
            success: true,
            agent_name: name,
            execution_context: execution_context,
            capabilities: capabilities,
            context_data: generate_context_data,
            performance_metrics: {
              work_duration: work_duration,
              thread_id: Thread.current.object_id
            }
          }
        end
      end
      
      def collect_span_attributes
        execution_context = analyze_execution_context
        
        {
          "agent.name" => name,
          "agent.pipeline_nesting_depth" => execution_context[:pipeline_nesting_depth],
          "agent.immediate_parent_type" => execution_context[:immediate_parent_type],
          "agent.execution_mode" => execution_context[:execution_mode],
          "agent.has_isolation" => execution_context[:has_isolation],
          "agent.has_accumulated_context" => execution_context[:has_accumulated_context],
          "agent.capabilities" => capabilities.keys.sort,
          "agent.hierarchy_verified" => verify_hierarchy_position
        }
      end
      
      private
      
      def analyze_execution_context
        parent = @parent_component
        
        {
          immediate_parent_type: detect_parent_type,
          pipeline_nesting_depth: calculate_pipeline_nesting_depth,
          execution_mode: detect_execution_mode,
          has_isolation: has_isolated_context?,
          has_accumulated_context: has_accumulated_context?,
          parent_pipeline_chain: build_pipeline_chain,
          thread_context: {
            thread_id: Thread.current.object_id,
            is_main_thread: Thread.current == Thread.main
          }
        }
      end
      
      def detect_parent_type
        parent = @parent_component
        return :none unless parent
        
        if parent.respond_to?(:trace_component_type)
          parent.class.trace_component_type
        elsif parent.class.name&.include?("Pipeline")
          :pipeline
        else
          :unknown
        end
      end
      
      def calculate_pipeline_nesting_depth
        depth = 0
        current_parent = @parent_component
        
        while current_parent
          if detect_component_type(current_parent) == :pipeline
            depth += 1
          end
          current_parent = current_parent.instance_variable_get(:@parent_component)
        end
        
        depth
      end
      
      def detect_execution_mode
        # Check for parallel execution markers
        if instance_variable_get(:@isolated_context)
          :parallel
        elsif instance_variable_get(:@accumulated_context)
          :sequential
        else
          :unknown
        end
      end
      
      def has_isolated_context?
        !instance_variable_get(:@isolated_context).nil?
      end
      
      def has_accumulated_context?
        !instance_variable_get(:@accumulated_context).nil?
      end
      
      def build_pipeline_chain
        chain = []
        current_parent = @parent_component
        
        while current_parent
          if detect_component_type(current_parent) == :pipeline
            chain << {
              name: current_parent.respond_to?(:name) ? current_parent.name : "unnamed",
              level: chain.length + 1
            }
          end
          current_parent = current_parent.instance_variable_get(:@parent_component)
        end
        
        chain
      end
      
      def detect_component_type(component)
        if component.respond_to?(:trace_component_type)
          component.class.trace_component_type
        elsif component.class.name&.include?("Pipeline")
          :pipeline
        else
          :unknown
        end
      end
      
      def verify_hierarchy_position
        # Verify that the agent is properly positioned in the hierarchy
        checks = {
          has_parent: !@parent_component.nil?,
          parent_is_pipeline: detect_parent_type == :pipeline,
          proper_nesting: calculate_pipeline_nesting_depth > 0,
          execution_context_valid: [:parallel, :sequential, :unknown].include?(detect_execution_mode)
        }
        
        checks.values.all?
      end
      
      def generate_context_data
        base_data = {
          agent_id: name,
          generated_at: Time.now.utc.iso8601,
          thread_id: Thread.current.object_id
        }
        
        # Add execution mode specific data
        case detect_execution_mode
        when :parallel
          isolation_context = instance_variable_get(:@isolated_context)
          base_data.merge({
            isolation_id: isolation_context&.dig(:isolation_id),
            branch_index: isolation_context&.dig(:branch_index)
          })
        when :sequential
          accumulated = instance_variable_get(:@accumulated_context) || {}
          base_data.merge({
            accumulated_keys: accumulated.keys.sort,
            child_index: instance_variable_get(:@child_index)
          })
        else
          base_data
        end
      end
    end
  end
  
  before do
    memory_processor.clear
  end
  
  describe "comprehensive pipeline hierarchy validation" do
    context "with complex nested structure" do
      # Build a complex hierarchy:
      # Root (sequential) -> [Branch1 (parallel), Branch2 (sequential)] -> Agents
      
      let(:leaf_agents) do
        4.times.map do |i|
          comprehensive_agent_class.new(
            name: "LeafAgent#{i + 1}",
            tracer: tracer,
            capabilities: { work_duration: 0.001, agent_index: i }
          )
        end
      end
      
      let(:parallel_branch_pipeline) do
        comprehensive_pipeline_class.new(
          name: "ParallelBranchPipeline",
          tracer: tracer,
          children: leaf_agents[0..1],
          execution_mode: :parallel,
          context_data: { branch_type: "parallel", branch_id: "p1" }
        )
      end
      
      let(:sequential_branch_pipeline) do
        comprehensive_pipeline_class.new(
          name: "SequentialBranchPipeline",
          tracer: tracer,
          children: leaf_agents[2..3],
          execution_mode: :sequential,
          context_data: { branch_type: "sequential", branch_id: "s1" }
        )
      end
      
      let(:root_pipeline) do
        comprehensive_pipeline_class.new(
          name: "ComprehensiveRootPipeline",
          tracer: tracer,
          children: [parallel_branch_pipeline, sequential_branch_pipeline],
          execution_mode: :sequential,
          context_data: { root: true, session_id: "session_123" }
        )
      end
      
      it "executes complete hierarchy with all features" do
        start_time = Time.now
        result = root_pipeline.run
        end_time = Time.now
        
        expect(result[:success]).to be(true)
        expect(result[:child_results].length).to eq(2)
        
        # Verify hierarchy integrity
        verification = result[:hierarchy_verification]
        expect(verification[:overall_integrity]).to be(true)
        expect(verification[:all_children_executed]).to be(true)
        expect(verification[:all_successful]).to be(true)
        
        # Check parallel branch results
        parallel_result = result[:child_results].find { |r| r[:pipeline_name] == "ParallelBranchPipeline" }
        expect(parallel_result[:execution_mode]).to eq(:parallel)
        expect(parallel_result[:hierarchy_verification][:isolation_maintained]).to be(true)
        
        # Check sequential branch results
        sequential_result = result[:child_results].find { |r| r[:pipeline_name] == "SequentialBranchPipeline" }
        expect(sequential_result[:execution_mode]).to eq(:sequential)
        expect(sequential_result[:hierarchy_verification][:context_accumulated]).to be(true)
        
        # Verify timing (parallel should be concurrent)
        total_duration = end_time - start_time
        expect(total_duration).to be < 0.1 # Should complete quickly due to parallelism
      end
      
      it "creates comprehensive span hierarchy" do
        root_pipeline.run
        
        spans = memory_processor.spans
        expect(spans.length).to eq(7) # 3 pipelines + 4 agents
        
        # Find all spans
        root_span = spans.find { |s| s[:attributes]["pipeline.name"] == "ComprehensiveRootPipeline" }
        parallel_span = spans.find { |s| s[:attributes]["pipeline.name"] == "ParallelBranchPipeline" }
        sequential_span = spans.find { |s| s[:attributes]["pipeline.name"] == "SequentialBranchPipeline" }
        agent_spans = spans.select { |s| s[:kind] == :agent }
        
        # Verify root hierarchy
        expect(root_span[:parent_id]).to be_nil
        expect(root_span[:attributes]["pipeline.is_root"]).to be(true)
        expect(root_span[:attributes]["pipeline.nesting_level"]).to eq(1)
        
        # Verify branch hierarchies
        expect(parallel_span[:parent_id]).to eq(root_span[:span_id])
        expect(sequential_span[:parent_id]).to eq(root_span[:span_id])
        
        expect(parallel_span[:attributes]["pipeline.nesting_level"]).to eq(2)
        expect(sequential_span[:attributes]["pipeline.nesting_level"]).to eq(2)
        
        # Verify agent hierarchies
        agent_spans.each do |agent_span|
          parent_pipeline = [parallel_span, sequential_span].find { |ps| ps[:span_id] == agent_span[:parent_id] }
          expect(parent_pipeline).not_to be_nil
          expect(agent_span[:attributes]["agent.pipeline_nesting_depth"]).to eq(2)
        end
        
        # Verify execution modes
        parallel_agents = agent_spans.select { |s| s[:parent_id] == parallel_span[:span_id] }
        sequential_agents = agent_spans.select { |s| s[:parent_id] == sequential_span[:span_id] }
        
        parallel_agents.each do |agent|
          expect(agent[:attributes]["agent.execution_mode"]).to eq("parallel")
          expect(agent[:attributes]["agent.has_isolation"]).to be(true)
        end
        
        sequential_agents.each do |agent|
          expect(agent[:attributes]["agent.execution_mode"]).to eq("sequential")
          expect(agent[:attributes]["agent.has_accumulated_context"]).to be(true)
        end
      end
      
      it "captures comprehensive execution events" do
        root_pipeline.run
        
        spans = memory_processor.spans
        
        # Check root pipeline events
        root_span = spans.find { |s| s[:attributes]["pipeline.name"] == "ComprehensiveRootPipeline" }
        root_events = root_span[:events]
        
        expect(root_events.map { |e| e[:name] }).to include(
          "pipeline.comprehensive_execution_start",
          "pipeline.comprehensive_execution_end",
          "pipeline.sequential_child_start"
        )
        
        # Check parallel pipeline events
        parallel_span = spans.find { |s| s[:attributes]["pipeline.name"] == "ParallelBranchPipeline" }
        parallel_events = parallel_span[:events]
        
        expect(parallel_events.map { |e| e[:name] }).to include(
          "pipeline.comprehensive_execution_start",
          "pipeline.parallel_branch_start",
          "pipeline.parallel_execution_completed"
        )
        
        # Check agent events
        agent_spans = spans.select { |s| s[:kind] == :agent }
        agent_spans.each do |span|
          events = span[:events]
          expect(events.map { |e| e[:name] }).to include("agent.comprehensive_execution")
        end
      end
      
      it "maintains trace coherence throughout complex hierarchy" do
        root_pipeline.run
        
        spans = memory_processor.spans
        
        # All spans should share the same trace ID
        trace_ids = spans.map { |s| s[:trace_id] }.uniq
        expect(trace_ids.length).to eq(1)
        
        # Verify timing relationships
        root_span = spans.find { |s| s[:attributes]["pipeline.name"] == "ComprehensiveRootPipeline" }
        root_start = Time.parse(root_span[:start_time])
        root_end = Time.parse(root_span[:end_time])
        
        spans.each do |span|
          span_start = Time.parse(span[:start_time])
          span_end = Time.parse(span[:end_time])
          
          # All spans should be within root timeframe
          expect(span_start).to be >= root_start
          expect(span_end).to be <= root_end
          expect(span_end).to be >= span_start
        end
      end
      
      it "validates hierarchy complexity metrics" do
        root_pipeline.run
        
        spans = memory_processor.spans
        
        # Check complexity metrics in pipeline spans
        pipeline_spans = spans.select { |s| s[:kind] == :pipeline }
        
        pipeline_spans.each do |span|
          complexity = span[:attributes]["pipeline.hierarchy_complexity"]
          expect(complexity).not_to be_nil
          expect(complexity).to be_a(Hash)
          expect(complexity["score"]).to be_a(Numeric)
          expect(complexity["score"]).to be > 0
        end
        
        # Root should have highest complexity
        root_span = spans.find { |s| s[:attributes]["pipeline.name"] == "ComprehensiveRootPipeline" }
        root_complexity = root_span[:attributes]["pipeline.hierarchy_complexity"]["score"]
        
        other_pipeline_spans = pipeline_spans.reject { |s| s == root_span }
        other_complexities = other_pipeline_spans.map { |s| s[:attributes]["pipeline.hierarchy_complexity"]["score"] }
        
        expect(root_complexity).to be >= other_complexities.max
      end
    end
  end
  
  describe "edge cases and error handling" do
    context "with deeply nested pipelines" do
      let(:deep_hierarchy) do
        # Create 5 levels of nesting
        leaf_agent = comprehensive_agent_class.new(name: "DeepLeafAgent", tracer: tracer)
        
        (1..5).reverse_each.reduce(leaf_agent) do |child, level|
          comprehensive_pipeline_class.new(
            name: "DeepLevel#{level}Pipeline",
            tracer: tracer,
            children: [child],
            context_data: { level: level, depth_test: true }
          )
        end
      end
      
      it "handles extreme nesting depth" do
        result = deep_hierarchy.run
        
        expect(result[:success]).to be(true)
        expect(result[:hierarchy_info][:nesting_level]).to eq(1) # Root level
        
        # Navigate to deepest level
        current_result = result
        nesting_levels = []
        
        while current_result[:child_results]&.any?
          nesting_levels << current_result[:hierarchy_info][:nesting_level]
          current_result = current_result[:child_results].first
        end
        
        expect(nesting_levels).to eq([1, 2, 3, 4, 5])
      end
      
      it "creates proper span hierarchy for deep nesting" do
        deep_hierarchy.run
        
        spans = memory_processor.spans
        expect(spans.length).to eq(6) # 5 pipelines + 1 agent
        
        # Verify sequential parent-child relationships
        pipeline_spans = spans.select { |s| s[:kind] == :pipeline }.sort_by { |s| s[:attributes]["pipeline.nesting_level"] }
        
        pipeline_spans.each_with_index do |span, index|
          if index == 0
            expect(span[:parent_id]).to be_nil # Root
          else
            expect(span[:parent_id]).to eq(pipeline_spans[index - 1][:span_id])
          end
          expect(span[:attributes]["pipeline.nesting_level"]).to eq(index + 1)
        end
        
        # Agent should be child of deepest pipeline
        agent_span = spans.find { |s| s[:kind] == :agent }
        deepest_pipeline = pipeline_spans.last
        expect(agent_span[:parent_id]).to eq(deepest_pipeline[:span_id])
        expect(agent_span[:attributes]["agent.pipeline_nesting_depth"]).to eq(5)
      end
    end
    
    context "with mixed execution modes" do
      let(:mixed_agent) { comprehensive_agent_class.new(name: "MixedAgent", tracer: tracer) }
      
      let(:parallel_inner) do
        comprehensive_pipeline_class.new(
          name: "ParallelInner",
          tracer: tracer,
          children: [mixed_agent],
          execution_mode: :parallel
        )
      end
      
      let(:sequential_outer) do
        comprehensive_pipeline_class.new(
          name: "SequentialOuter",
          tracer: tracer,
          children: [parallel_inner],
          execution_mode: :sequential
        )
      end
      
      it "handles mixed execution modes correctly" do
        result = sequential_outer.run
        
        expect(result[:success]).to be(true)
        expect(result[:execution_mode]).to eq(:sequential)
        
        inner_result = result[:child_results].first
        expect(inner_result[:execution_mode]).to eq(:parallel)
        
        agent_result = inner_result[:child_results].first
        expect(agent_result[:execution_context][:execution_mode]).to eq(:parallel)
      end
    end
  end
end
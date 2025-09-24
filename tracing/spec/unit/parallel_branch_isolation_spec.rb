# frozen_string_literal: true

require "spec_helper"
require "raaf/tracing/spans"
require "raaf/tracing/trace_provider"

# Test context isolation in parallel execution branches for RAAF tracing
# This spec covers task 3.4: context isolation in parallel execution branches

RSpec.describe "RAAF Parallel Branch Context Isolation" do
  let(:memory_processor) { RAAF::Tracing::MemorySpanProcessor.new }
  let(:tracer) do
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(memory_processor)
    tracer
  end

  # Mock parallel pipeline that executes children concurrently
  let(:parallel_pipeline_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :pipeline
      
      attr_reader :name, :branches, :tracer, :shared_state, :isolation_mode
      
      def initialize(name:, tracer: nil, branches: [], shared_state: {}, isolation_mode: :strict)
        @name = name
        @tracer = tracer
        @branches = branches
        @shared_state = shared_state
        @isolation_mode = isolation_mode
      end
      
      def run
        with_tracing(:run) do
          # Add parallel execution start event
          if current_span
            current_span[:events] << {
              name: "parallel.execution_start",
              timestamp: Time.now.utc.iso8601,
              attributes: {
                branch_count: branches.length,
                isolation_mode: isolation_mode.to_s,
                shared_state_keys: shared_state.keys.sort
              }
            }
          end
          
          # Execute branches in parallel with isolated contexts
          branch_results = execute_parallel_branches
          
          if current_span
            current_span[:events] << {
              name: "parallel.execution_end",
              timestamp: Time.now.utc.iso8601,
              attributes: {
                successful_branches: branch_results.count { |r| r[:success] },
                failed_branches: branch_results.count { |r| !r[:success] }
              }
            }
          end
          
          {
            success: true,
            pipeline_name: name,
            execution_mode: "parallel",
            isolation_mode: isolation_mode,
            branch_results: branch_results,
            shared_state_snapshot: shared_state.dup,
            execution_summary: create_execution_summary(branch_results)
          }
        end
      end
      
      def collect_span_attributes
        {
          "pipeline.name" => name,
          "pipeline.execution_mode" => "parallel",
          "pipeline.branch_count" => branches.length,
          "pipeline.isolation_mode" => isolation_mode.to_s,
          "pipeline.shared_state_keys" => shared_state.keys.sort,
          "pipeline.thread_safety" => "enabled"
        }
      end
      
      private
      
      def execute_parallel_branches
        # Create isolated execution contexts for each branch
        threads = branches.map.with_index do |branch, index|
          Thread.new do
            # Create isolated context for this branch
            isolated_context = create_isolated_context(index)
            
            # Set parent component with isolated state
            branch.instance_variable_set(:@parent_component, self)
            branch.instance_variable_set(:@branch_index, index)
            branch.instance_variable_set(:@isolated_context, isolated_context)
            
            begin
              # Execute branch with isolated context
              result = branch.run
              
              # Add branch completion event to parent span
              if current_span
                current_span[:events] << {
                  name: "parallel.branch_completed",
                  timestamp: Time.now.utc.iso8601,
                  attributes: {
                    branch_index: index,
                    branch_name: branch.respond_to?(:name) ? branch.name : "branch_#{index}",
                    success: result[:success] != false,
                    thread_id: Thread.current.object_id
                  }
                }
              end
              
              result.merge({
                branch_index: index,
                thread_id: Thread.current.object_id,
                isolated_context: isolated_context
              })
            rescue StandardError => e
              {
                success: false,
                error: e.message,
                branch_index: index,
                thread_id: Thread.current.object_id,
                isolated_context: isolated_context
              }
            end
          end
        end
        
        # Wait for all branches to complete
        threads.map(&:value)
      end
      
      def create_isolated_context(branch_index)
        base_context = {
          branch_index: branch_index,
          thread_id: Thread.current.object_id,
          isolation_id: SecureRandom.hex(8),
          created_at: Time.now.utc.iso8601
        }
        
        case isolation_mode
        when :strict
          # Completely isolated - no shared state
          base_context
        when :shared_read
          # Read-only access to shared state
          base_context.merge(shared_state_readonly: shared_state.dup.freeze)
        when :shared_write
          # Shared writable state (not recommended for parallel execution)
          base_context.merge(shared_state: shared_state)
        else
          base_context
        end
      end
      
      def create_execution_summary(branch_results)
        {
          total_branches: branch_results.length,
          successful_branches: branch_results.count { |r| r[:success] },
          unique_threads: branch_results.map { |r| r[:thread_id] }.uniq.length,
          unique_isolation_ids: branch_results.map { |r| r.dig(:isolated_context, :isolation_id) }.uniq.length,
          execution_overlap: calculate_execution_overlap(branch_results)
        }
      end
      
      def calculate_execution_overlap(branch_results)
        # Simple overlap calculation based on thread diversity
        unique_threads = branch_results.map { |r| r[:thread_id] }.uniq.length
        total_branches = branch_results.length
        
        if total_branches <= 1
          0.0
        else
          unique_threads.to_f / total_branches.to_f
        end
      end
    end
  end
  
  # Mock agent that can detect its execution context
  let(:context_aware_agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :agent
      
      attr_reader :name, :tracer, :work_duration, :state_modifications
      
      def initialize(name:, tracer: nil, work_duration: 0.01, state_modifications: {})
        @name = name
        @tracer = tracer
        @work_duration = work_duration
        @state_modifications = state_modifications
      end
      
      def run
        with_tracing(:run) do
          # Capture execution context
          execution_context = capture_execution_context
          
          # Add context capture event
          if current_span
            current_span[:events] << {
              name: "agent.context_captured",
              timestamp: Time.now.utc.iso8601,
              attributes: execution_context.slice(:thread_id, :branch_index, :isolation_id)
            }
          end
          
          # Simulate work with potential state modifications
          sleep(work_duration)
          modified_state = apply_state_modifications(execution_context)
          
          if current_span
            current_span[:events] << {
              name: "agent.work_completed",
              timestamp: Time.now.utc.iso8601,
              attributes: {
                state_changes: state_modifications.keys.length,
                isolation_verified: verify_isolation(execution_context)
              }
            }
          end
          
          {
            success: true,
            agent_name: name,
            execution_context: execution_context,
            modified_state: modified_state,
            isolation_verified: verify_isolation(execution_context),
            performance: {
              work_duration: work_duration,
              thread_id: Thread.current.object_id
            }
          }
        end
      end
      
      def collect_span_attributes
        execution_context = capture_execution_context
        
        {
          "agent.name" => name,
          "agent.work_duration" => work_duration,
          "agent.thread_id" => Thread.current.object_id,
          "agent.branch_index" => execution_context[:branch_index],
          "agent.isolation_id" => execution_context[:isolation_id],
          "agent.state_modifications" => state_modifications.keys.sort,
          "agent.isolation_verified" => verify_isolation(execution_context)
        }
      end
      
      private
      
      def capture_execution_context
        isolated_context = instance_variable_get(:@isolated_context) || {}
        branch_index = instance_variable_get(:@branch_index)
        
        {
          thread_id: Thread.current.object_id,
          branch_index: branch_index,
          isolation_id: isolated_context[:isolation_id],
          parent_pipeline: detect_parent_pipeline,
          isolated_context: isolated_context,
          capture_time: Time.now.utc.iso8601
        }
      end
      
      def apply_state_modifications(context)
        modified = {}
        
        state_modifications.each do |key, value|
          # Apply modifications based on context
          modified[key] = if value.respond_to?(:call)
                          value.call(context)
                        else
                          value
                        end
        end
        
        modified
      end
      
      def verify_isolation(context)
        # Verify that this agent has its own isolated context
        isolation_checks = {
          has_isolation_id: !context[:isolation_id].nil?,
          has_branch_index: !context[:branch_index].nil?,
          unique_thread: Thread.current.object_id != 0,
          isolated_context_present: !context[:isolated_context].empty?
        }
        
        isolation_checks.all? { |_, check| check }
      end
      
      def detect_parent_pipeline
        parent = @parent_component
        return "none" unless parent
        
        if parent.respond_to?(:trace_component_type) && parent.class.trace_component_type == :pipeline
          parent.respond_to?(:name) ? parent.name : "unknown_pipeline"
        else
          "not_pipeline"
        end
      end
    end
  end
  
  before do
    memory_processor.clear
  end
  
  describe "basic parallel branch isolation" do
    let(:agent1) do
      context_aware_agent_class.new(
        name: "ParallelAgent1",
        tracer: tracer,
        work_duration: 0.005,
        state_modifications: { counter: 1, agent_id: "agent1" }
      )
    end
    
    let(:agent2) do
      context_aware_agent_class.new(
        name: "ParallelAgent2",
        tracer: tracer,
        work_duration: 0.007,
        state_modifications: { counter: 2, agent_id: "agent2" }
      )
    end
    
    let(:agent3) do
      context_aware_agent_class.new(
        name: "ParallelAgent3",
        tracer: tracer,
        work_duration: 0.003,
        state_modifications: { counter: 3, agent_id: "agent3" }
      )
    end
    
    let(:parallel_pipeline) do
      parallel_pipeline_class.new(
        name: "IsolatedParallelPipeline",
        tracer: tracer,
        branches: [agent1, agent2, agent3],
        isolation_mode: :strict
      )
    end
    
    it "executes branches in parallel with isolated contexts" do
      start_time = Time.now
      result = parallel_pipeline.run
      end_time = Time.now
      
      expect(result[:success]).to be(true)
      expect(result[:execution_mode]).to eq("parallel")
      expect(result[:branch_results].length).to eq(3)
      
      # Verify parallel execution (should be faster than sequential)
      total_work_duration = [0.005, 0.007, 0.003].sum
      actual_duration = end_time - start_time
      
      # Parallel execution should be significantly faster than sequential
      expect(actual_duration).to be < (total_work_duration * 0.8)
      
      # Verify each agent completed successfully
      branch_results = result[:branch_results]
      expect(branch_results.all? { |r| r[:success] }).to be(true)
      
      # Verify isolation
      agent_names = branch_results.map { |r| r[:agent_name] }
      expect(agent_names).to contain_exactly("ParallelAgent1", "ParallelAgent2", "ParallelAgent3")
      
      # Verify unique isolation contexts
      isolation_ids = branch_results.map { |r| r.dig(:execution_context, :isolation_id) }
      expect(isolation_ids.uniq.length).to eq(3) # All unique
      
      # Verify unique threads
      thread_ids = branch_results.map { |r| r.dig(:performance, :thread_id) }
      expect(thread_ids.uniq.length).to eq(3) # All unique threads
    end
    
    it "creates isolated spans for each parallel branch" do
      parallel_pipeline.run
      
      spans = memory_processor.spans
      expect(spans.length).to eq(4) # 1 pipeline + 3 agents
      
      pipeline_span = spans.find { |s| s[:kind] == :pipeline }
      agent_spans = spans.select { |s| s[:kind] == :agent }
      
      # All agents should have the same parent (pipeline)
      agent_spans.each do |span|
        expect(span[:parent_id]).to eq(pipeline_span[:span_id])
        expect(span[:trace_id]).to eq(pipeline_span[:trace_id])
      end
      
      # Each agent should have unique isolation attributes
      isolation_ids = agent_spans.map { |s| s[:attributes]["agent.isolation_id"] }
      expect(isolation_ids.uniq.length).to eq(3)
      
      thread_ids = agent_spans.map { |s| s[:attributes]["agent.thread_id"] }
      expect(thread_ids.uniq.length).to eq(3)
      
      # All should verify isolation
      agent_spans.each do |span|
        expect(span[:attributes]["agent.isolation_verified"]).to be(true)
      end
    end
    
    it "captures parallel execution events" do
      parallel_pipeline.run
      
      spans = memory_processor.spans
      pipeline_span = spans.find { |s| s[:kind] == :pipeline }
      
      events = pipeline_span[:events]
      event_names = events.map { |e| e[:name] }
      
      expect(event_names).to include(
        "parallel.execution_start",
        "parallel.execution_end"
      )
      
      # Should have branch completion events
      branch_events = events.select { |e| e[:name] == "parallel.branch_completed" }
      expect(branch_events.length).to eq(3)
      
      # Each branch should have unique thread ID
      branch_thread_ids = branch_events.map { |e| e[:attributes][:thread_id] }
      expect(branch_thread_ids.uniq.length).to eq(3)
    end
    
    it "maintains timing overlap for parallel execution" do
      parallel_pipeline.run
      
      spans = memory_processor.spans
      agent_spans = spans.select { |s| s[:kind] == :agent }
      
      # Check timing overlap
      timings = agent_spans.map do |span|
        {
          start: Time.parse(span[:start_time]),
          end: Time.parse(span[:end_time]),
          name: span[:attributes]["agent.name"]
        }
      end
      
      # Verify overlapping execution (parallel)
      timings.combination(2).each do |timing1, timing2|
        # Check for time overlap
        overlap_start = [timing1[:start], timing2[:start]].max
        overlap_end = [timing1[:end], timing2[:end]].min
        
        if overlap_start < overlap_end
          overlap_duration = overlap_end - overlap_start
          expect(overlap_duration).to be > 0
        else
          # If no overlap, they should be very close in time (parallel execution)
          time_gap = (timing1[:start] - timing2[:start]).abs
          expect(time_gap).to be < 0.1 # Less than 100ms apart
        end
      end
    end
  end
  
  describe "context isolation modes" do
    let(:shared_state) { { global_counter: 0, shared_data: "initial" } }
    
    let(:state_modifying_agent_class) do
      Class.new(context_aware_agent_class) do
        def run
          with_tracing(:run) do
            execution_context = capture_execution_context
            
            # Try to modify shared state based on isolation mode
            state_result = attempt_state_modification(execution_context)
            
            {
              success: true,
              agent_name: name,
              execution_context: execution_context,
              state_modification_result: state_result,
              isolation_mode_detected: detect_isolation_mode(execution_context)
            }
          end
        end
        
        private
        
        def attempt_state_modification(context)
          isolated_context = context[:isolated_context]
          
          if isolated_context.key?(:shared_state)
            # Shared write mode - can modify
            begin
              isolated_context[:shared_state][:global_counter] += 1
              { success: true, mode: "shared_write", value: isolated_context[:shared_state][:global_counter] }
            rescue => e
              { success: false, mode: "shared_write", error: e.message }
            end
          elsif isolated_context.key?(:shared_state_readonly)
            # Shared read mode - cannot modify
            begin
              isolated_context[:shared_state_readonly][:global_counter] += 1
              { success: false, mode: "shared_read", error: "should_not_succeed" }
            rescue FrozenError => e
              { success: true, mode: "shared_read", readonly_verified: true }
            rescue => e
              { success: false, mode: "shared_read", error: e.message }
            end
          else
            # Strict isolation - no shared state
            { success: true, mode: "strict", isolated: true }
          end
        end
        
        def detect_isolation_mode(context)
          isolated_context = context[:isolated_context]
          
          if isolated_context.key?(:shared_state)
            :shared_write
          elsif isolated_context.key?(:shared_state_readonly)
            :shared_read
          else
            :strict
          end
        end
      end
    end
    
    context "with strict isolation mode" do
      let(:agents) do
        3.times.map do |i|
          state_modifying_agent_class.new(
            name: "StrictAgent#{i + 1}",
            tracer: tracer,
            state_modifications: { agent_index: i }
          )
        end
      end
      
      let(:strict_pipeline) do
        parallel_pipeline_class.new(
          name: "StrictIsolationPipeline",
          tracer: tracer,
          branches: agents,
          shared_state: shared_state,
          isolation_mode: :strict
        )
      end
      
      it "provides complete context isolation" do
        result = strict_pipeline.run
        
        expect(result[:success]).to be(true)
        expect(result[:isolation_mode]).to eq(:strict)
        
        branch_results = result[:branch_results]
        
        # All agents should detect strict isolation
        branch_results.each do |branch_result|
          expect(branch_result[:isolation_mode_detected]).to eq(:strict)
          expect(branch_result.dig(:state_modification_result, :mode)).to eq("strict")
          expect(branch_result.dig(:state_modification_result, :isolated)).to be(true)
        end
        
        # Shared state should remain unchanged
        expect(result[:shared_state_snapshot]).to eq(shared_state)
      end
      
      it "creates isolated span contexts" do
        strict_pipeline.run
        
        spans = memory_processor.spans
        agent_spans = spans.select { |s| s[:kind] == :agent }
        
        # Each agent should have unique isolation
        isolation_ids = agent_spans.map { |s| s[:attributes]["agent.isolation_id"] }
        expect(isolation_ids.uniq.length).to eq(3)
        
        # All should be verified as isolated
        agent_spans.each do |span|
          expect(span[:attributes]["agent.isolation_verified"]).to be(true)
        end
      end
    end
    
    context "with shared read isolation mode" do
      let(:read_agents) do
        3.times.map do |i|
          state_modifying_agent_class.new(
            name: "ReadAgent#{i + 1}",
            tracer: tracer,
            state_modifications: { agent_index: i }
          )
        end
      end
      
      let(:read_pipeline) do
        parallel_pipeline_class.new(
          name: "SharedReadPipeline",
          tracer: tracer,
          branches: read_agents,
          shared_state: shared_state,
          isolation_mode: :shared_read
        )
      end
      
      it "provides read-only access to shared state" do
        result = read_pipeline.run
        
        expect(result[:success]).to be(true)
        expect(result[:isolation_mode]).to eq(:shared_read)
        
        branch_results = result[:branch_results]
        
        # All agents should detect shared read mode
        branch_results.each do |branch_result|
          expect(branch_result[:isolation_mode_detected]).to eq(:shared_read)
          state_result = branch_result[:state_modification_result]
          expect(state_result[:mode]).to eq("shared_read")
          expect(state_result[:readonly_verified]).to be(true)
        end
        
        # Original shared state should remain unchanged
        expect(result[:shared_state_snapshot]).to eq(shared_state)
      end
    end
  end
  
  describe "complex parallel scenarios" do
    context "with nested parallel pipelines" do
      let(:leaf_agents) do
        4.times.map do |i|
          context_aware_agent_class.new(
            name: "NestedLeafAgent#{i + 1}",
            tracer: tracer,
            work_duration: 0.002
          )
        end
      end
      
      let(:inner_parallel_pipeline1) do
        parallel_pipeline_class.new(
          name: "InnerParallel1",
          tracer: tracer,
          branches: leaf_agents[0..1],
          isolation_mode: :strict
        )
      end
      
      let(:inner_parallel_pipeline2) do
        parallel_pipeline_class.new(
          name: "InnerParallel2",
          tracer: tracer,
          branches: leaf_agents[2..3],
          isolation_mode: :strict
        )
      end
      
      let(:outer_parallel_pipeline) do
        parallel_pipeline_class.new(
          name: "OuterParallelPipeline",
          tracer: tracer,
          branches: [inner_parallel_pipeline1, inner_parallel_pipeline2],
          isolation_mode: :strict
        )
      end
      
      it "maintains isolation across nested parallel contexts" do
        result = outer_parallel_pipeline.run
        
        expect(result[:success]).to be(true)
        expect(result[:branch_results].length).to eq(2)
        
        # Each inner pipeline should have executed successfully
        inner_results = result[:branch_results]
        inner_results.each do |inner_result|
          expect(inner_result[:success]).to be(true)
          expect(inner_result[:execution_mode]).to eq("parallel")
          expect(inner_result[:branch_results].length).to eq(2)
        end
        
        # Verify execution summary
        summary = result[:execution_summary]
        expect(summary[:total_branches]).to eq(2)
        expect(summary[:successful_branches]).to eq(2)
        expect(summary[:unique_threads]).to eq(2)
      end
      
      it "creates correct span hierarchy for nested parallel execution" do
        outer_parallel_pipeline.run
        
        spans = memory_processor.spans
        expect(spans.length).to eq(7) # 1 outer + 2 inner + 4 agents
        
        # Find spans
        outer_span = spans.find { |s| s[:attributes]["pipeline.name"] == "OuterParallelPipeline" }
        inner_spans = spans.select { |s| s[:attributes]["pipeline.name"]&.include?("InnerParallel") }
        agent_spans = spans.select { |s| s[:kind] == :agent }
        
        # Verify hierarchy
        expect(outer_span[:parent_id]).to be_nil
        
        inner_spans.each do |inner_span|
          expect(inner_span[:parent_id]).to eq(outer_span[:span_id])
        end
        
        # Verify agents are children of their respective inner pipelines
        agent_spans.each do |agent_span|
          expect(inner_spans.map { |s| s[:span_id] }).to include(agent_span[:parent_id])
        end
        
        # All should share the same trace
        trace_ids = spans.map { |s| s[:trace_id] }.uniq
        expect(trace_ids.length).to eq(1)
      end
    end
  end
end
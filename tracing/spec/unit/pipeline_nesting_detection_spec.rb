# frozen_string_literal: true

require "spec_helper"
require "raaf/tracing/spans"
require "raaf/tracing/trace_provider"

# Test pipeline nesting detection in RAAF tracing
# This spec covers task 3.2: pipeline nesting detection in RAAF::Pipeline

RSpec.describe "RAAF Pipeline Nesting Detection" do
  let(:memory_processor) { RAAF::Tracing::MemorySpanProcessor.new }
  let(:tracer) do
    tracer = RAAF::Tracing::SpanTracer.new
    tracer.add_processor(memory_processor)
    tracer
  end

  # Mock pipeline detector that can analyze nesting patterns
  let(:nesting_detector_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :pipeline
      
      attr_reader :name, :children, :tracer, :nesting_metadata
      
      def initialize(name:, tracer: nil, children: [], nesting_metadata: {})
        @name = name
        @tracer = tracer
        @children = children
        @nesting_metadata = nesting_metadata
      end
      
      def run
        with_tracing(:run) do
          # Detect and record nesting information
          nesting_info = detect_nesting_context
          
          # Add nesting detection event
          if current_span
            current_span[:events] << {
              name: "pipeline.nesting_detected",
              timestamp: Time.now.utc.iso8601,
              attributes: nesting_info
            }
          end
          
          child_results = []
          
          # Execute children and propagate nesting context
          children.each_with_index do |child, index|
            child.instance_variable_set(:@parent_component, self)
            
            # Add child execution event with nesting context
            if current_span
              child_nesting = if child.respond_to?(:detect_nesting_context)
                              child.detect_nesting_context
                            else
                              detect_child_nesting_context(child)
                            end
              
              current_span[:events] << {
                name: "pipeline.child_nesting_analyzed",
                timestamp: Time.now.utc.iso8601,
                attributes: {
                  child_index: index,
                  child_name: child.respond_to?(:name) ? child.name : "child_#{index}",
                  child_type: detect_child_type(child),
                  child_nesting: child_nesting
                }
              }
            end
            
            result = child.run
            child_results << result
          end
          
          {
            success: true,
            pipeline_name: name,
            nesting_info: nesting_info,
            child_results: child_results,
            nesting_analysis: analyze_nesting_patterns(child_results)
          }
        end
      end
      
      def detect_nesting_context
        parent_chain = build_parent_chain
        
        {
          is_root_pipeline: parent_chain.empty?,
          nesting_level: parent_chain.length + 1,
          parent_chain: parent_chain,
          has_pipeline_ancestors: parent_chain.any? { |p| p[:type] == :pipeline },
          max_depth_possible: calculate_max_depth,
          nesting_pattern: classify_nesting_pattern(parent_chain)
        }
      end
      
      def collect_span_attributes
        nesting_info = detect_nesting_context
        
        {
          "pipeline.name" => name,
          "pipeline.is_root" => nesting_info[:is_root_pipeline],
          "pipeline.nesting_level" => nesting_info[:nesting_level],
          "pipeline.has_pipeline_ancestors" => nesting_info[:has_pipeline_ancestors],
          "pipeline.parent_chain_length" => nesting_info[:parent_chain].length,
          "pipeline.nesting_pattern" => nesting_info[:nesting_pattern],
          "pipeline.max_depth_possible" => nesting_info[:max_depth_possible],
          "pipeline.children_count" => children.length,
          "pipeline.children_types" => children.map { |c| detect_child_type(c) }.uniq
        }
      end
      
      private
      
      def build_parent_chain
        chain = []
        current_parent = @parent_component
        
        while current_parent
          parent_info = {
            name: current_parent.respond_to?(:name) ? current_parent.name : "unnamed",
            type: detect_component_type(current_parent),
            class_name: current_parent.class.name
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
      
      def detect_child_type(child)
        detect_component_type(child)
      end
      
      def detect_child_nesting_context(child)
        if child.respond_to?(:detect_nesting_context)
          child.detect_nesting_context
        else
          {
            will_be_nested: true,
            predicted_level: detect_nesting_context[:nesting_level] + 1,
            parent_type: :pipeline
          }
        end
      end
      
      def calculate_max_depth
        # Calculate maximum possible nesting depth for this pipeline
        current_depth = detect_nesting_context[:nesting_level]
        child_pipeline_count = children.count { |c| detect_child_type(c) == :pipeline }
        
        if child_pipeline_count > 0
          current_depth + 1 # At least one more level possible
        else
          current_depth # This is likely a leaf pipeline
        end
      end
      
      def classify_nesting_pattern(parent_chain)
        return "root" if parent_chain.empty?
        
        pipeline_ancestors = parent_chain.select { |p| p[:type] == :pipeline }
        agent_ancestors = parent_chain.select { |p| p[:type] == :agent }
        
        if pipeline_ancestors.length == parent_chain.length
          "pure_pipeline_nesting"
        elsif agent_ancestors.any?
          "mixed_component_nesting"
        elsif pipeline_ancestors.length == 1
          "single_level_nesting"
        else
          "deep_pipeline_nesting"
        end
      end
      
      def analyze_nesting_patterns(child_results)
        patterns = {
          total_children: child_results.length,
          nested_pipelines: 0,
          nested_agents: 0,
          max_child_depth: 0,
          nesting_distribution: {}
        }
        
        child_results.each do |result|
          if result.is_a?(Hash)
            if result.key?(:nesting_info)
              # Child is a pipeline
              patterns[:nested_pipelines] += 1
              child_depth = result.dig(:nesting_info, :nesting_level) || 0
              patterns[:max_child_depth] = [patterns[:max_child_depth], child_depth].max
            else
              # Child is likely an agent
              patterns[:nested_agents] += 1
            end
          end
        end
        
        patterns
      end
    end
  end
  
  # Mock agent that can be nested and report its context
  let(:nesting_aware_agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :agent
      
      attr_reader :name, :tracer, :agent_metadata
      
      def initialize(name:, tracer: nil, agent_metadata: {})
        @name = name
        @tracer = tracer
        @agent_metadata = agent_metadata
      end
      
      def run
        with_tracing(:run) do
          # Detect agent's nesting context
          nesting_context = detect_agent_nesting_context
          
          if current_span
            current_span[:events] << {
              name: "agent.nesting_context_detected",
              timestamp: Time.now.utc.iso8601,
              attributes: nesting_context
            }
          end
          
          {
            success: true,
            agent_name: name,
            nesting_context: nesting_context,
            metadata: agent_metadata
          }
        end
      end
      
      def detect_agent_nesting_context
        parent_pipeline_chain = build_pipeline_ancestor_chain
        
        {
          has_pipeline_parent: !parent_pipeline_chain.empty?,
          pipeline_nesting_depth: parent_pipeline_chain.length,
          immediate_parent_type: detect_immediate_parent_type,
          pipeline_ancestor_chain: parent_pipeline_chain,
          is_deeply_nested: parent_pipeline_chain.length > 2
        }
      end
      
      def collect_span_attributes
        nesting_context = detect_agent_nesting_context
        
        {
          "agent.name" => name,
          "agent.has_pipeline_parent" => nesting_context[:has_pipeline_parent],
          "agent.pipeline_nesting_depth" => nesting_context[:pipeline_nesting_depth],
          "agent.immediate_parent_type" => nesting_context[:immediate_parent_type],
          "agent.is_deeply_nested" => nesting_context[:is_deeply_nested],
          "agent.pipeline_ancestors" => nesting_context[:pipeline_ancestor_chain].map { |p| p[:name] }
        }
      end
      
      private
      
      def build_pipeline_ancestor_chain
        chain = []
        current_parent = @parent_component
        
        while current_parent
          if detect_component_type(current_parent) == :pipeline
            pipeline_info = {
              name: current_parent.respond_to?(:name) ? current_parent.name : "unnamed_pipeline",
              level: chain.length + 1
            }
            chain << pipeline_info
          end
          
          current_parent = current_parent.instance_variable_get(:@parent_component)
        end
        
        chain
      end
      
      def detect_immediate_parent_type
        parent = @parent_component
        return :none unless parent
        
        detect_component_type(parent)
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
    end
  end
  
  before do
    memory_processor.clear
  end
  
  describe "root pipeline detection" do
    let(:root_agent) { nesting_aware_agent_class.new(name: "RootAgent", tracer: tracer) }
    let(:root_pipeline) do
      nesting_detector_class.new(
        name: "RootPipeline",
        tracer: tracer,
        children: [root_agent]
      )
    end
    
    it "correctly identifies root pipeline" do
      result = root_pipeline.run
      
      expect(result[:success]).to be(true)
      nesting_info = result[:nesting_info]
      
      expect(nesting_info[:is_root_pipeline]).to be(true)
      expect(nesting_info[:nesting_level]).to eq(1)
      expect(nesting_info[:parent_chain]).to be_empty
      expect(nesting_info[:has_pipeline_ancestors]).to be(false)
      expect(nesting_info[:nesting_pattern]).to eq("root")
    end
    
    it "creates root span without parent" do
      root_pipeline.run
      
      spans = memory_processor.spans
      pipeline_span = spans.find { |s| s[:kind] == :pipeline }
      
      expect(pipeline_span[:parent_id]).to be_nil
      expect(pipeline_span[:attributes]["pipeline.is_root"]).to be(true)
      expect(pipeline_span[:attributes]["pipeline.nesting_level"]).to eq(1)
      expect(pipeline_span[:attributes]["pipeline.nesting_pattern"]).to eq("root")
    end
    
    it "captures root pipeline events" do
      root_pipeline.run
      
      spans = memory_processor.spans
      pipeline_span = spans.find { |s| s[:kind] == :pipeline }
      
      events = pipeline_span[:events]
      nesting_event = events.find { |e| e[:name] == "pipeline.nesting_detected" }
      
      expect(nesting_event).not_to be_nil
      expect(nesting_event[:attributes][:is_root_pipeline]).to be(true)
      expect(nesting_event[:attributes][:nesting_level]).to eq(1)
    end
  end
  
  describe "single-level nesting detection" do
    let(:nested_agent) { nesting_aware_agent_class.new(name: "NestedAgent", tracer: tracer) }
    let(:inner_pipeline) do
      nesting_detector_class.new(
        name: "InnerPipeline",
        tracer: tracer,
        children: [nested_agent]
      )
    end
    let(:outer_pipeline) do
      nesting_detector_class.new(
        name: "OuterPipeline",
        tracer: tracer,
        children: [inner_pipeline]
      )
    end
    
    it "detects single-level nesting correctly" do
      result = outer_pipeline.run
      
      expect(result[:success]).to be(true)
      
      # Check outer pipeline nesting info
      outer_nesting = result[:nesting_info]
      expect(outer_nesting[:is_root_pipeline]).to be(true)
      expect(outer_nesting[:nesting_level]).to eq(1)
      expect(outer_nesting[:nesting_pattern]).to eq("root")
      
      # Check inner pipeline nesting info
      inner_result = result[:child_results].first
      inner_nesting = inner_result[:nesting_info]
      expect(inner_nesting[:is_root_pipeline]).to be(false)
      expect(inner_nesting[:nesting_level]).to eq(2)
      expect(inner_nesting[:has_pipeline_ancestors]).to be(true)
      expect(inner_nesting[:nesting_pattern]).to eq("single_level_nesting")
    end
    
    it "creates proper span hierarchy for single-level nesting" do
      outer_pipeline.run
      
      spans = memory_processor.spans
      outer_span = spans.find { |s| s[:attributes]["pipeline.name"] == "OuterPipeline" }
      inner_span = spans.find { |s| s[:attributes]["pipeline.name"] == "InnerPipeline" }
      agent_span = spans.find { |s| s[:kind] == :agent }
      
      # Verify hierarchy
      expect(outer_span[:parent_id]).to be_nil
      expect(inner_span[:parent_id]).to eq(outer_span[:span_id])
      expect(agent_span[:parent_id]).to eq(inner_span[:span_id])
      
      # Verify nesting attributes
      expect(outer_span[:attributes]["pipeline.is_root"]).to be(true)
      expect(inner_span[:attributes]["pipeline.is_root"]).to be(false)
      expect(inner_span[:attributes]["pipeline.nesting_level"]).to eq(2)
      expect(agent_span[:attributes]["agent.pipeline_nesting_depth"]).to eq(2)
    end
  end
  
  describe "deep nesting detection" do
    let(:leaf_agent) { nesting_aware_agent_class.new(name: "LeafAgent", tracer: tracer) }
    let(:level3_pipeline) do
      nesting_detector_class.new(
        name: "Level3Pipeline",
        tracer: tracer,
        children: [leaf_agent],
        nesting_metadata: { expected_level: 3 }
      )
    end
    let(:level2_pipeline) do
      nesting_detector_class.new(
        name: "Level2Pipeline",
        tracer: tracer,
        children: [level3_pipeline],
        nesting_metadata: { expected_level: 2 }
      )
    end
    let(:level1_pipeline) do
      nesting_detector_class.new(
        name: "Level1Pipeline",
        tracer: tracer,
        children: [level2_pipeline],
        nesting_metadata: { expected_level: 1 }
      )
    end
    
    it "detects deep nesting patterns correctly" do
      result = level1_pipeline.run
      
      expect(result[:success]).to be(true)
      
      # Level 1 (root)
      level1_nesting = result[:nesting_info]
      expect(level1_nesting[:nesting_level]).to eq(1)
      expect(level1_nesting[:nesting_pattern]).to eq("root")
      
      # Level 2
      level2_result = result[:child_results].first
      level2_nesting = level2_result[:nesting_info]
      expect(level2_nesting[:nesting_level]).to eq(2)
      expect(level2_nesting[:nesting_pattern]).to eq("single_level_nesting")
      
      # Level 3
      level3_result = level2_result[:child_results].first
      level3_nesting = level3_result[:nesting_info]
      expect(level3_nesting[:nesting_level]).to eq(3)
      expect(level3_nesting[:nesting_pattern]).to eq("deep_pipeline_nesting")
      expect(level3_nesting[:parent_chain].length).to eq(2)
      
      # Agent at deepest level
      agent_result = level3_result[:child_results].first
      agent_nesting = agent_result[:nesting_context]
      expect(agent_nesting[:pipeline_nesting_depth]).to eq(3)
      expect(agent_nesting[:is_deeply_nested]).to be(true)
    end
    
    it "creates correct span attributes for deep nesting" do
      level1_pipeline.run
      
      spans = memory_processor.spans
      
      level1_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level1Pipeline" }
      level2_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level2Pipeline" }
      level3_span = spans.find { |s| s[:attributes]["pipeline.name"] == "Level3Pipeline" }
      agent_span = spans.find { |s| s[:kind] == :agent }
      
      # Verify nesting levels
      expect(level1_span[:attributes]["pipeline.nesting_level"]).to eq(1)
      expect(level2_span[:attributes]["pipeline.nesting_level"]).to eq(2)
      expect(level3_span[:attributes]["pipeline.nesting_level"]).to eq(3)
      
      # Verify parent chain lengths
      expect(level1_span[:attributes]["pipeline.parent_chain_length"]).to eq(0)
      expect(level2_span[:attributes]["pipeline.parent_chain_length"]).to eq(1)
      expect(level3_span[:attributes]["pipeline.parent_chain_length"]).to eq(2)
      
      # Verify agent nesting
      expect(agent_span[:attributes]["agent.pipeline_nesting_depth"]).to eq(3)
      expect(agent_span[:attributes]["agent.is_deeply_nested"]).to be(true)
      expect(agent_span[:attributes]["agent.pipeline_ancestors"]).to eq(["Level3Pipeline", "Level2Pipeline", "Level1Pipeline"])
    end
    
    it "captures comprehensive nesting events" do
      level1_pipeline.run
      
      spans = memory_processor.spans
      pipeline_spans = spans.select { |s| s[:kind] == :pipeline }
      
      # Each pipeline should have nesting detection events
      pipeline_spans.each do |span|
        events = span[:events]
        nesting_event = events.find { |e| e[:name] == "pipeline.nesting_detected" }
        
        expect(nesting_event).not_to be_nil
        expect(nesting_event[:attributes]).to include(:nesting_level, :nesting_pattern)
        
        # Should have child nesting analysis events if there are children
        if span[:attributes]["pipeline.children_count"] > 0
          child_events = events.select { |e| e[:name] == "pipeline.child_nesting_analyzed" }
          expect(child_events).not_to be_empty
        end
      end
    end
  end
  
  describe "complex nesting pattern detection" do
    context "with mixed component nesting" do
      let(:mixed_agent1) { nesting_aware_agent_class.new(name: "MixedAgent1", tracer: tracer) }
      let(:mixed_agent2) { nesting_aware_agent_class.new(name: "MixedAgent2", tracer: tracer) }
      
      let(:mixed_pipeline) do
        nesting_detector_class.new(
          name: "MixedPipeline",
          tracer: tracer,
          children: [mixed_agent1, mixed_agent2]
        )
      end
      
      let(:container_pipeline) do
        nesting_detector_class.new(
          name: "ContainerPipeline",
          tracer: tracer,
          children: [mixed_pipeline]
        )
      end
      
      it "detects mixed component patterns" do
        result = container_pipeline.run
        
        expect(result[:success]).to be(true)
        
        # Check nesting analysis
        nesting_analysis = result[:nesting_analysis]
        expect(nesting_analysis[:total_children]).to eq(1)
        expect(nesting_analysis[:nested_pipelines]).to eq(1)
        expect(nesting_analysis[:nested_agents]).to eq(0)
        
        # Check inner pipeline
        inner_result = result[:child_results].first
        inner_analysis = inner_result[:nesting_analysis]
        expect(inner_analysis[:total_children]).to eq(2)
        expect(inner_analysis[:nested_pipelines]).to eq(0)
        expect(inner_analysis[:nested_agents]).to eq(2)
      end
    end
    
    context "with multiple pipeline branches" do
      let(:branch1_agent) { nesting_aware_agent_class.new(name: "Branch1Agent", tracer: tracer) }
      let(:branch2_agent) { nesting_aware_agent_class.new(name: "Branch2Agent", tracer: tracer) }
      
      let(:branch1_pipeline) do
        nesting_detector_class.new(
          name: "Branch1Pipeline",
          tracer: tracer,
          children: [branch1_agent]
        )
      end
      
      let(:branch2_pipeline) do
        nesting_detector_class.new(
          name: "Branch2Pipeline",
          tracer: tracer,
          children: [branch2_agent]
        )
      end
      
      let(:multi_branch_pipeline) do
        nesting_detector_class.new(
          name: "MultiBranchPipeline",
          tracer: tracer,
          children: [branch1_pipeline, branch2_pipeline]
        )
      end
      
      it "detects multiple branch nesting patterns" do
        result = multi_branch_pipeline.run
        
        expect(result[:success]).to be(true)
        expect(result[:child_results].length).to eq(2)
        
        # Root pipeline should detect multiple nested pipelines
        nesting_analysis = result[:nesting_analysis]
        expect(nesting_analysis[:nested_pipelines]).to eq(2)
        expect(nesting_analysis[:nested_agents]).to eq(0)
        
        # Each branch should have the same nesting level
        branch_results = result[:child_results]
        branch_results.each do |branch_result|
          expect(branch_result[:nesting_info][:nesting_level]).to eq(2)
          expect(branch_result[:nesting_info][:nesting_pattern]).to eq("single_level_nesting")
        end
      end
      
      it "creates parallel sibling spans with same parent" do
        multi_branch_pipeline.run
        
        spans = memory_processor.spans
        root_span = spans.find { |s| s[:attributes]["pipeline.name"] == "MultiBranchPipeline" }
        branch_spans = spans.select { |s| s[:attributes]["pipeline.name"]&.include?("Branch") }
        
        # Both branches should have the same parent
        branch_spans.each do |branch_span|
          expect(branch_span[:parent_id]).to eq(root_span[:span_id])
          expect(branch_span[:attributes]["pipeline.nesting_level"]).to eq(2)
        end
        
        # Should have different span IDs (not shared)
        branch_span_ids = branch_spans.map { |s| s[:span_id] }
        expect(branch_span_ids.uniq.length).to eq(2)
      end
    end
  end
end
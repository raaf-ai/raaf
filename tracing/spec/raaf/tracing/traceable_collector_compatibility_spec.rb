# frozen_string_literal: true

require "spec_helper"
require "securerandom"

RSpec.describe RAAF::Tracing::Traceable, "collector system compatibility" do
  # This test suite ensures that the collector system doesn't break
  # the core functionality of the Traceable module
  
  # Create test classes that include the Traceable module
  let(:test_agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable
      trace_as :agent
      
      attr_reader :name, :current_span
      
      def initialize(name: "TestAgent")
        @name = name
      end
      
      def self.name
        "TestAgent"
      end
    end
  end
  
  let(:agent) { test_agent_class.new }
  
  describe "basic span functionality with collectors" do
    it "creates spans successfully" do
      span_created = false
      span_id = nil
      
      result = agent.with_tracing(:test_method) do
        span_created = !agent.current_span.nil?
        span_id = agent.current_span&.dig(:span_id)
        "test result"
      end
      
      expect(result).to eq("test result")
      expect(span_created).to be(true), "Expected span to be created during execution"
      expect(span_id).to be_a(String), "Expected span to have an ID"
      expect(agent.current_span).to be_nil, "Expected span to be cleaned up after execution"
    end
    
    it "collects span attributes through collector system" do
      attributes_collected = nil
      
      agent.with_tracing(:test_method) do
        span = agent.current_span
        attributes_collected = span[:attributes] if span
      end
      
      expect(attributes_collected).to be_a(Hash)
      expect(attributes_collected["component.type"]).to eq("agent")
      expect(attributes_collected["component.name"]).to eq("TestAgent")
    end
    
    it "collects result attributes through collector system" do
      final_attributes = nil
      
      # Use a simple test to verify result collection
      # Since we can't easily inspect the final span, we'll test via the collect_result_attributes method directly
      result_attrs = agent.collect_result_attributes("test result")
      
      expect(result_attrs).to be_a(Hash)
      expect(result_attrs["result.type"]).to eq("String")
      expect(result_attrs["result.success"]).to be(true)
    end
    
    it "handles traced_run method" do
      result = agent.traced_run("input") do |input|
        "processed: #{input}"
      end
      
      expect(result).to eq("processed: input")
    end
    
    it "handles traced_execute method" do
      result = agent.traced_execute("input") do |input|
        "executed: #{input}"
      end
      
      expect(result).to eq("executed: input")
    end
  end
  
  describe "traceable interface methods with collectors" do
    it "trace_parent_span returns span during execution" do
      parent_span = nil
      
      agent.with_tracing(:test) do
        parent_span = agent.trace_parent_span
      end
      
      expect(parent_span).to be_a(Hash)
      expect(parent_span[:span_id]).to be_a(String)
    end
    
    it "traced? returns correct status" do
      traced_during = nil
      traced_before = agent.traced?
      traced_after = nil
      
      agent.with_tracing(:test) do
        traced_during = agent.traced?
      end
      traced_after = agent.traced?
      
      expect(traced_before).to be(false)
      expect(traced_during).to be(true)
      expect(traced_after).to be(false)
    end
    
    it "trace_id returns ID during execution" do
      trace_id = nil
      
      agent.with_tracing(:test) do
        trace_id = agent.trace_id
      end
      
      expect(trace_id).to be_a(String)
      expect(trace_id).to start_with("trace_")
    end
  end
  
  describe "error handling with collectors" do
    it "handles exceptions without breaking" do
      error_occurred = false
      
      expect {
        agent.with_tracing(:error_method) do
          error_occurred = true
          raise StandardError, "Test error"
        end
      }.to raise_error(StandardError, "Test error")
      
      expect(error_occurred).to be(true)
      expect(agent.current_span).to be_nil, "Span should be cleaned up even after errors"
    end
  end
  
  describe "collector fallback behavior" do
    context "when collectors are not available" do
      before do
        # Temporarily hide the SpanCollectors module to test fallback
        if defined?(RAAF::Tracing::SpanCollectors)
          @original_collectors = RAAF::Tracing::SpanCollectors
          RAAF::Tracing.send(:remove_const, :SpanCollectors)
        end
      end
      
      after do
        # Restore the SpanCollectors module
        if @original_collectors
          RAAF::Tracing.const_set(:SpanCollectors, @original_collectors)
        end
      end
      
      it "falls back to original implementation gracefully" do
        span_attributes = agent.collect_span_attributes
        
        expect(span_attributes["component.type"]).to eq("agent")
        expect(span_attributes["component.name"]).to eq("TestAgent")
      end
      
      it "still creates spans when collectors unavailable" do
        span_created = false
        
        agent.with_tracing(:test_method) do
          span_created = !agent.current_span.nil?
        end
        
        expect(span_created).to be(true)
      end
    end
    
    context "when collector raises error" do
      before do
        # Mock the collector to raise an error
        allow(RAAF::Tracing::SpanCollectors).to receive(:collector_for).and_raise(StandardError, "Collector error")
      end
      
      it "falls back to original implementation" do
        span_attributes = nil
        
        expect {
          span_attributes = agent.collect_span_attributes
        }.not_to raise_error
        
        # Should still get basic attributes via fallback
        expect(span_attributes["component.type"]).to eq("agent")
        expect(span_attributes["component.name"]).to eq("TestAgent")
      end
      
      it "still creates spans when collector fails" do
        span_created = false
        
        expect {
          agent.with_tracing(:test_method) do
            span_created = !agent.current_span.nil?
          end
        }.not_to raise_error
        
        expect(span_created).to be(true)
      end
    end
  end
end

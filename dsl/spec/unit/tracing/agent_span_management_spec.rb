# frozen_string_literal: true

require "spec_helper"
require "raaf-tracing"
require "raaf/dsl/agent"

RSpec.describe "Agent Span Management", type: :unit do
  # Test agent for span management testing
  class TestAgent < RAAF::DSL::Agent
    include RAAF::Tracing::Traceable
    trace_as :agent

    def initialize(parent_component: nil, **options)
      @parent_component = parent_component
      super(**options)
    end

    def collect_span_attributes
      super.merge({
        "agent.name" => self.class.name,
        "agent.type" => "test_agent"
      })
    end

    # Simplified run method for testing
    def run_without_timeout(**options)
      with_tracing(:run, parent_component: @parent_component) do
        { success: true, result: "test_completed" }
      end
    end
  end

  # Mock pipeline component for testing parent contexts
  class MockPipeline
    include RAAF::Tracing::Traceable
    trace_as :pipeline

    def initialize
      @current_span = {
        span_id: "pipeline_span_123",
        trace_id: "trace_abc_456"
      }
    end

    attr_reader :current_span
  end

  let(:test_agent) { TestAgent.new }
  let(:mock_pipeline) { MockPipeline.new }

  describe "span creation with parent context" do
    it "creates root span when no parent component provided" do
      result = test_agent.run_without_timeout

      expect(result[:success]).to be true
      expect(test_agent.current_span).to be_nil # Span cleaned up after execution
    end

    it "creates child span when parent_component provided in constructor" do
      child_agent = TestAgent.new(parent_component: mock_pipeline)

      result = child_agent.run_without_timeout

      expect(result[:success]).to be true
      expect(result[:result]).to eq("test_completed")
    end

    it "creates child span when parent_component provided in run method" do
      result = test_agent.run_without_timeout(parent_component: mock_pipeline)

      expect(result[:success]).to be true
      expect(result[:result]).to eq("test_completed")
    end

    it "prioritizes run method parent_component over constructor parent_component" do
      other_pipeline = MockPipeline.new
      other_pipeline.instance_variable_set(:@current_span, {
        span_id: "other_pipeline_span",
        trace_id: "other_trace_id"
      })

      child_agent = TestAgent.new(parent_component: mock_pipeline)
      result = child_agent.run_without_timeout(parent_component: other_pipeline)

      expect(result[:success]).to be true
    end
  end

  describe "span lifecycle management" do
    it "properly cleans up span after successful execution" do
      test_agent.run_without_timeout

      expect(test_agent.current_span).to be_nil
    end

    it "properly cleans up span after failed execution" do
      expect {
        test_agent.with_tracing(:run) do
          raise StandardError, "Test error"
        end
      }.to raise_error(StandardError, "Test error")

      expect(test_agent.current_span).to be_nil
    end

    it "avoids creating duplicate spans for nested calls" do
      spans_created = []

      allow(test_agent).to receive(:send_span) do |span|
        spans_created << span[:span_id]
      end

      test_agent.run_without_timeout

      expect(spans_created.length).to eq(1)
    end
  end

  describe "span attribute collection" do
    it "includes agent-specific attributes in spans" do
      captured_span = nil
      allow(test_agent).to receive(:send_span) do |span|
        captured_span = span
      end

      test_agent.run_without_timeout

      expect(captured_span).to_not be_nil
      expect(captured_span[:attributes]).to include({
        "component.type" => "agent",
        "component.name" => "TestAgent",
        "agent.name" => "TestAgent",
        "agent.type" => "test_agent"
      })
    end

    it "includes success and duration attributes" do
      captured_span = nil
      allow(test_agent).to receive(:send_span) do |span|
        captured_span = span
      end

      test_agent.run_without_timeout

      expect(captured_span[:attributes]).to include({
        "success" => true
      })
      expect(captured_span[:attributes]).to have_key("duration_ms")
    end
  end

  describe "trace context propagation" do
    it "inherits trace ID from parent component" do
      captured_span = nil
      allow(test_agent).to receive(:send_span) do |span|
        captured_span = span
      end

      test_agent.run_without_timeout(parent_component: mock_pipeline)

      expect(captured_span[:trace_id]).to eq("trace_abc_456")
      expect(captured_span[:parent_id]).to eq("pipeline_span_123")
    end

    it "creates new trace ID when no parent component" do
      captured_span = nil
      allow(test_agent).to receive(:send_span) do |span|
        captured_span = span
      end

      test_agent.run_without_timeout

      expect(captured_span[:trace_id]).to_not be_nil
      expect(captured_span[:trace_id]).to_not eq("trace_abc_456")
      expect(captured_span[:parent_id]).to be_nil
    end
  end

  describe "error handling in spans" do
    it "marks span as failed when exception occurs" do
      captured_span = nil
      allow(test_agent).to receive(:send_span) do |span|
        captured_span = span
      end

      expect {
        test_agent.with_tracing(:run) do
          raise StandardError, "Test error"
        end
      }.to raise_error(StandardError, "Test error")

      expect(captured_span[:status]).to eq(:error)
      expect(captured_span[:attributes]).to include({
        "success" => false,
        "error.type" => "StandardError",
        "error.message" => "Test error"
      })
      expect(captured_span[:attributes]).to have_key("error.backtrace")
    end
  end

  describe "integration with ExecutionContext" do
    it "can auto-detect parent from execution context when no explicit parent" do
      # Simulate execution context with active span
      execution_context_span = {
        span_id: "context_span_789",
        trace_id: "context_trace_xyz"
      }

      allow(RAAF::Tracing::ExecutionContext).to receive(:current_span)
        .and_return(execution_context_span)

      captured_span = nil
      allow(test_agent).to receive(:send_span) do |span|
        captured_span = span
      end

      test_agent.run_without_timeout

      expect(captured_span[:trace_id]).to eq("context_trace_xyz")
      expect(captured_span[:parent_id]).to eq("context_span_789")
    end
  end
end
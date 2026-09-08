# frozen_string_literal: true

require "spec_helper"
require "securerandom"

RSpec.describe RAAF::Tracing::Traceable, "span data identity with collectors" do
  # This test suite ensures that the collector system produces
  # EXACTLY the same span data as the original implementation

  # Mock collector that exactly replicates original behavior
  let(:identity_collector_class) do
    Class.new do
      def self.collector_for(_component)
        IdentityCollector.new
      end

      class IdentityCollector

        def collect_attributes(component)
          # Replicate EXACT original behavior from Traceable module
          {
            "component.type" => component.class.trace_component_type.to_s,
            "component.name" => component.class.name
          }
        end

        def collect_result(_component, result)
          # Replicate EXACT original behavior from Traceable module
          {
            "result.type" => result.class.name,
            "result.success" => !result.nil?
          }
        end

      end
    end
  end

  # Create test classes that include the Traceable module
  let(:test_agent_class) do
    Class.new do
      include RAAF::Tracing::Traceable

      trace_as :agent

      attr_reader :name

      def initialize(name: "TestAgent")
        @name = name
      end

      def self.name
        "TestAgent"
      end
    end
  end

  let(:test_pipeline_class) do
    Class.new do
      include RAAF::Tracing::Traceable

      trace_as :pipeline

      def self.name
        "TestPipeline"
      end
    end
  end

  let(:test_tool_class) do
    Class.new do
      include RAAF::Tracing::Traceable

      trace_as :tool

      def self.name
        "TestTool"
      end
    end
  end

  let(:agent) { test_agent_class.new }
  let(:pipeline) { test_pipeline_class.new }
  let(:tool) { test_tool_class.new }

  # Traceable only falls back to its own attribute collection when the collector
  # system raises. `defined?` is a keyword rather than a method, so stubbing it
  # on the component does nothing at all; making collector_for raise is what
  # actually exercises the pre-collector code path.
  def without_collectors
    stub_const("RAAF::Tracing::SpanCollectors", Class.new do
      def self.collector_for(_component)
        raise "collectors unavailable"
      end
    end)
    yield
  end

  describe "span attribute identity" do
    it "produces identical span attributes with and without collectors" do
      # Capture original behavior (without collectors)
      original_attributes = without_collectors { agent.collect_span_attributes }

      stub_const("RAAF::Tracing::SpanCollectors", identity_collector_class)

      # Capture collector behavior
      collector_attributes = agent.collect_span_attributes

      # Should be identical
      expect(collector_attributes).to eq(original_attributes)
      expect(collector_attributes["component.type"]).to eq("agent")
      expect(collector_attributes["component.name"]).to eq("TestAgent")
    end

    it "produces identical result attributes with and without collectors" do
      result = "test result"

      # Capture original behavior (without collectors)
      original_attributes = without_collectors { agent.collect_result_attributes(result) }

      stub_const("RAAF::Tracing::SpanCollectors", identity_collector_class)

      # Capture collector behavior
      collector_attributes = agent.collect_result_attributes(result)

      # Should be identical
      expect(collector_attributes).to eq(original_attributes)
      expect(collector_attributes["result.type"]).to eq("String")
      expect(collector_attributes["result.success"]).to be(true)
    end

    it "handles nil results identically with and without collectors" do
      result = nil

      # Capture original behavior (without collectors)
      original_attributes = without_collectors { agent.collect_result_attributes(result) }

      stub_const("RAAF::Tracing::SpanCollectors", identity_collector_class)

      # Capture collector behavior
      collector_attributes = agent.collect_result_attributes(result)

      # Should be identical
      expect(collector_attributes).to eq(original_attributes)
      expect(collector_attributes["result.type"]).to eq("NilClass")
      expect(collector_attributes["result.success"]).to be(false)
    end
  end

  describe "span data identity across component types" do
    it "produces identical attributes for agents" do
      # Without collectors
      original = without_collectors { agent.collect_span_attributes }

      # With collectors
      stub_const("RAAF::Tracing::SpanCollectors", identity_collector_class)
      collector = agent.collect_span_attributes

      expect(collector).to eq(original)
      expect(collector["component.type"]).to eq("agent")
    end

    it "produces identical attributes for pipelines" do
      # Without collectors
      original = without_collectors { pipeline.collect_span_attributes }

      # With collectors
      stub_const("RAAF::Tracing::SpanCollectors", identity_collector_class)
      collector = pipeline.collect_span_attributes

      expect(collector).to eq(original)
      expect(collector["component.type"]).to eq("pipeline")
    end

    it "produces identical attributes for tools" do
      # Without collectors
      original = without_collectors { tool.collect_span_attributes }

      # With collectors
      stub_const("RAAF::Tracing::SpanCollectors", identity_collector_class)
      collector = tool.collect_span_attributes

      expect(collector).to eq(original)
      expect(collector["component.type"]).to eq("tool")
    end
  end

  describe "end-to-end span data identity" do
    it "produces identical span data throughout complete tracing lifecycle" do
      # Collect span data without collectors
      original_span_data = nil

      without_collectors do
        agent.with_tracing(:test_method) do
          original_span_data = agent.current_span[:attributes].dup
          "test result"
        end
      end

      # Reset and collect with collectors
      stub_const("RAAF::Tracing::SpanCollectors", identity_collector_class)

      collector_span_data = nil

      # Create a new agent instance to avoid state pollution
      new_agent = test_agent_class.new

      new_agent.with_tracing(:test_method) do
        collector_span_data = new_agent.current_span[:attributes].dup
        "test result"
      end

      # Extract the core attributes that should be identical
      # (excluding metadata added by framework during tracing)
      core_original = original_span_data.select { |k, _v| k.start_with?("component.", "result.") }
      core_collector = collector_span_data.select { |k, _v| k.start_with?("component.", "result.") }

      expect(core_collector).to eq(core_original)
    end

    it "maintains span hierarchy and timing when using collectors" do
      # Test with parent-child span relationships
      parent_span = nil
      child_span = nil

      stub_const("RAAF::Tracing::SpanCollectors", identity_collector_class)

      agent.with_tracing(:parent_method) do
        parent_span = agent.current_span.dup

        child_tool = test_tool_class.new
        child_tool.instance_variable_set(:@parent_component, agent)

        child_tool.with_tracing(:child_method) do
          child_span = child_tool.current_span.dup
        end
      end

      # Verify hierarchy is maintained with collectors
      expect(child_span[:parent_id]).to eq(parent_span[:span_id])
      expect(child_span[:trace_id]).to eq(parent_span[:trace_id])

      # Verify component types are correct
      expect(parent_span[:kind]).to eq(:agent)
      expect(child_span[:kind]).to eq(:tool)
    end
  end

  describe "error handling identity" do
    it "produces identical error attributes with and without collectors" do
      # Capture the failed span from each path. The span is popped on the way
      # out, so it has to be read from inside send_span.
      capture = lambda do |component|
        captured = nil
        allow(component).to receive(:send_span) { |span| captured = span }
        begin
          component.with_tracing(:error_method) { raise StandardError, "Test error" }
        rescue StandardError
          # Expected: with_tracing re-raises after marking the span
        end
        captured
      end

      original_span = without_collectors { capture.call(agent) }

      stub_const("RAAF::Tracing::SpanCollectors", identity_collector_class)
      collector_span = capture.call(test_agent_class.new)

      error_keys = %w[success error.type error.message]
      expect(collector_span[:status]).to eq(original_span[:status])
      expect(collector_span[:attributes].slice(*error_keys))
        .to eq(original_span[:attributes].slice(*error_keys))
      expect(collector_span[:attributes]["error.message"]).to eq("Test error")
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "active_support/core_ext/hash/indifferent_access"

RSpec.describe "Pipeline Token Usage Aggregation" do
  # Mock agent classes that return usage data
  let(:agent_class_1) do
    Class.new do
      include RAAF::DSL::Pipelineable

      attr_reader :usage_data

      def self.name
        "TestAgent1"
      end

      def self.requirements_met?(_context)
        true
      end

      def self.required_fields
        []
      end

      def self.externally_required_fields
        []
      end

      def self.provided_fields
        [:result1]
      end

      def initialize(**context)
        @context = context
        @usage_data = {
          input_tokens: 100,
          output_tokens: 150,
          total_tokens: 250
        }
      end

      def can_validate_for_pipeline?
        true
      end

      def validate_for_pipeline(_context_hash)
        # Validation passes
        true
      end

      def call
        {
          success: true,
          agent_name: "TestAgent1",
          result1: "data1",
          usage: @usage_data
        }
      end

      def run
        call
      end
    end
  end

  let(:agent_class_2) do
    Class.new do
      include RAAF::DSL::Pipelineable

      attr_reader :usage_data

      def self.name
        "TestAgent2"
      end

      def self.requirements_met?(_context)
        true
      end

      def self.required_fields
        []
      end

      def self.externally_required_fields
        []
      end

      def self.provided_fields
        [:result2]
      end

      def initialize(**context)
        @context = context
        @usage_data = {
          input_tokens: 200,
          output_tokens: 250,
          total_tokens: 450,
          cache_read_input_tokens: 50
        }
      end

      def can_validate_for_pipeline?
        true
      end

      def validate_for_pipeline(_context_hash)
        true
      end

      def call
        {
          success: true,
          agent_name: "TestAgent2",
          result2: "data2",
          usage: @usage_data
        }
      end

      def run
        call
      end
    end
  end

  let(:agent_class_3_reasoning) do
    Class.new do
      include RAAF::DSL::Pipelineable

      attr_reader :usage_data

      def self.name
        "TestAgent3Reasoning"
      end

      def self.requirements_met?(_context)
        true
      end

      def self.required_fields
        []
      end

      def self.externally_required_fields
        []
      end

      def self.provided_fields
        [:result3]
      end

      def initialize(**context)
        @context = context
        @usage_data = {
          input_tokens: 150,
          output_tokens: 300,
          total_tokens: 450,
          output_tokens_details: {
            reasoning_tokens: 100
          }
        }
      end

      def can_validate_for_pipeline?
        true
      end

      def validate_for_pipeline(_context_hash)
        true
      end

      def call
        {
          success: true,
          agent_name: "TestAgent3Reasoning",
          result3: "data3",
          usage: @usage_data
        }
      end

      def run
        call
      end
    end
  end

  let(:agent_without_usage) do
    Class.new do
      include RAAF::DSL::Pipelineable

      def self.name
        "AgentWithoutUsage"
      end

      def self.requirements_met?(_context)
        true
      end

      def self.required_fields
        []
      end

      def self.externally_required_fields
        []
      end

      def self.provided_fields
        [:result_no_usage]
      end

      def initialize(**context)
        @context = context
      end

      def can_validate_for_pipeline?
        true
      end

      def validate_for_pipeline(_context_hash)
        true
      end

      def call
        {
          success: true,
          agent_name: "AgentWithoutUsage",
          result_no_usage: "data without usage"
        }
      end

      def run
        call
      end
    end
  end

  describe "#aggregate_usage_statistics" do
    let(:pipeline_class) do
      Class.new(RAAF::Pipeline) do
        def self.name
          "TestPipeline"
        end
      end
    end

    it "aggregates usage from single agent" do
      pipeline = pipeline_class.new

      agent_results = [
        {
          success: true,
          agent_name: "Agent1",
          usage: {
            input_tokens: 100,
            output_tokens: 200,
            total_tokens: 300
          }
        }
      ]

      usage = pipeline.send(:aggregate_usage_statistics, agent_results)

      expect(usage[:input_tokens]).to eq(100)
      expect(usage[:output_tokens]).to eq(200)
      expect(usage[:total_tokens]).to eq(300)
      expect(usage[:prompt_tokens]).to eq(100)  # Alias
      expect(usage[:completion_tokens]).to eq(200)  # Alias
      expect(usage[:agent_breakdown].length).to eq(1)
      expect(usage[:agent_breakdown][0][:agent_name]).to eq("Agent1")
    end

    it "aggregates usage from multiple agents" do
      pipeline = pipeline_class.new

      agent_results = [
        {
          success: true,
          agent_name: "Agent1",
          usage: {
            input_tokens: 100,
            output_tokens: 150,
            total_tokens: 250
          }
        },
        {
          success: true,
          agent_name: "Agent2",
          usage: {
            input_tokens: 200,
            output_tokens: 250,
            total_tokens: 450
          }
        }
      ]

      usage = pipeline.send(:aggregate_usage_statistics, agent_results)

      expect(usage[:input_tokens]).to eq(300)
      expect(usage[:output_tokens]).to eq(400)
      expect(usage[:total_tokens]).to eq(700)
      expect(usage[:agent_breakdown].length).to eq(2)
    end

    it "handles agents without usage data" do
      pipeline = pipeline_class.new

      agent_results = [
        {
          success: true,
          agent_name: "Agent1",
          usage: {
            input_tokens: 100,
            output_tokens: 150
          }
        },
        {
          success: true,
          agent_name: "Agent2"
          # No usage field
        }
      ]

      usage = pipeline.send(:aggregate_usage_statistics, agent_results)

      expect(usage[:input_tokens]).to eq(100)
      expect(usage[:output_tokens]).to eq(150)
      expect(usage[:total_tokens]).to eq(250)
      expect(usage[:agent_breakdown].length).to eq(1)  # Only Agent1
    end

    it "supports both input_tokens/output_tokens and prompt_tokens/completion_tokens" do
      pipeline = pipeline_class.new

      agent_results = [
        {
          success: true,
          agent_name: "Agent1",
          usage: {
            prompt_tokens: 100,
            completion_tokens: 150
          }
        }
      ]

      usage = pipeline.send(:aggregate_usage_statistics, agent_results)

      expect(usage[:input_tokens]).to eq(100)
      expect(usage[:output_tokens]).to eq(150)
    end

    it "aggregates cache_read_input_tokens when present" do
      pipeline = pipeline_class.new

      agent_results = [
        {
          success: true,
          agent_name: "Agent1",
          usage: {
            input_tokens: 100,
            output_tokens: 150,
            cache_read_input_tokens: 50
          }
        },
        {
          success: true,
          agent_name: "Agent2",
          usage: {
            input_tokens: 200,
            output_tokens: 250,
            cache_read_input_tokens: 75
          }
        }
      ]

      usage = pipeline.send(:aggregate_usage_statistics, agent_results)

      expect(usage[:cache_read_input_tokens]).to eq(125)
    end

    it "aggregates reasoning_tokens when present" do
      pipeline = pipeline_class.new

      agent_results = [
        {
          success: true,
          agent_name: "Agent1",
          usage: {
            input_tokens: 100,
            output_tokens: 200,
            output_tokens_details: {
              reasoning_tokens: 50
            }
          }
        },
        {
          success: true,
          agent_name: "Agent2",
          usage: {
            input_tokens: 150,
            output_tokens: 250,
            output_tokens_details: {
              reasoning_tokens: 75
            }
          }
        }
      ]

      usage = pipeline.send(:aggregate_usage_statistics, agent_results)

      expect(usage[:output_tokens_details][:reasoning_tokens]).to eq(125)
    end

    it "supports indifferent hash access" do
      pipeline = pipeline_class.new

      agent_results = [
        {
          success: true,
          agent_name: "Agent1",
          usage: {
            input_tokens: 100,
            output_tokens: 200
          }
        }
      ]

      usage = pipeline.send(:aggregate_usage_statistics, agent_results)

      # Test both symbol and string access
      expect(usage[:input_tokens]).to eq(100)
      expect(usage["input_tokens"]).to eq(100)
      expect(usage[:output_tokens]).to eq(200)
      expect(usage["output_tokens"]).to eq(200)
    end
  end

  describe "Pipeline with usage aggregation" do
    it "includes aggregated usage in pipeline result" do
      a1 = agent_class_1
      a2 = agent_class_2

      pipeline_class = Class.new(RAAF::Pipeline) do
        flow a1 >> a2

        def self.name
          "TestPipeline"
        end
      end

      pipeline = pipeline_class.new
      result = pipeline.run

      expect(result[:usage]).to be_present
      expect(result[:usage][:input_tokens]).to eq(300)  # 100 + 200
      expect(result[:usage][:output_tokens]).to eq(400)  # 150 + 250
      expect(result[:usage][:total_tokens]).to eq(700)
      expect(result[:usage][:agent_breakdown].length).to eq(2)
    end

    it "supports indifferent access for usage field" do
      a1 = agent_class_1

      pipeline_class = Class.new(RAAF::Pipeline) do
        flow a1

        def self.name
          "TestPipeline"
        end
      end

      pipeline = pipeline_class.new
      result = pipeline.run

      # Test both symbol and string access
      expect(result[:usage][:input_tokens]).to eq(100)
      expect(result["usage"]["input_tokens"]).to eq(100)
    end

    it "handles pipeline with agents without usage data" do
      a1 = agent_class_1
      a_no_usage = agent_without_usage

      pipeline_class = Class.new(RAAF::Pipeline) do
        flow a1 >> a_no_usage

        def self.name
          "TestPipeline"
        end
      end

      pipeline = pipeline_class.new
      result = pipeline.run

      expect(result[:usage][:input_tokens]).to eq(100)
      expect(result[:usage][:output_tokens]).to eq(150)
      expect(result[:usage][:agent_breakdown].length).to eq(1)  # Only Agent1
    end

    it "aggregates usage from pipeline with reasoning model" do
      a1 = agent_class_1
      a3 = agent_class_3_reasoning

      pipeline_class = Class.new(RAAF::Pipeline) do
        flow a1 >> a3

        def self.name
          "ReasoningPipeline"
        end
      end

      pipeline = pipeline_class.new
      result = pipeline.run

      expect(result[:usage][:input_tokens]).to eq(250)  # 100 + 150
      expect(result[:usage][:output_tokens]).to eq(450)  # 150 + 300
      expect(result[:usage][:output_tokens_details][:reasoning_tokens]).to eq(100)
    end

    it "aggregates usage from pipeline with cache usage" do
      a1 = agent_class_1
      a2 = agent_class_2

      pipeline_class = Class.new(RAAF::Pipeline) do
        flow a1 >> a2

        def self.name
          "CachePipeline"
        end
      end

      pipeline = pipeline_class.new
      result = pipeline.run

      expect(result[:usage][:cache_read_input_tokens]).to eq(50)
    end
  end
end

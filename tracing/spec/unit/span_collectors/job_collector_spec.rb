# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Tracing::SpanCollectors::JobCollector do
  let(:job) do
    double("Job",
      class: double("JobClass", name: "RAAF::AgentProcessingJob"),
      queue_name: "ai_agents",
      arguments: ["agent_id_123", { mode: "async", priority: "high" }]
    ).tap do |job|
      allow(job).to receive(:respond_to?).with(:queue_name).and_return(true)
      allow(job).to receive(:respond_to?).with(:arguments).and_return(true)
    end
  end

  let(:collector) { described_class.new }

  describe "DSL declarations" do
    it "declares custom span attributes with lambdas" do
      custom_attrs = described_class.instance_variable_get(:@span_custom)
      expect(custom_attrs).to have_key(:queue)
      expect(custom_attrs).to have_key(:arguments)
    end

    it "declares result attributes" do
      result_attrs = described_class.instance_variable_get(:@result_custom)
      expect(result_attrs).to have_key(:status)
    end
  end

  describe "#collect_attributes" do
    it "collects base attributes" do
      attributes = collector.collect_attributes(job)

      expect(attributes).to include("component.type")
      expect(attributes).to include("component.name")
      expect(attributes["component.name"]).to eq("RAAF::AgentProcessingJob")
    end

    it "collects queue name" do
      attributes = collector.collect_attributes(job)
      queue_key = attributes.keys.find { |k| k.end_with?(".queue") }
      expect(attributes[queue_key]).to eq("ai_agents")
    end

    it "falls back to default queue when queue_name not available" do
      allow(job).to receive(:respond_to?).with(:queue_name).and_return(false)
      
      attributes = collector.collect_attributes(job)
      queue_key = attributes.keys.find { |k| k.end_with?(".queue") }
      expect(attributes[queue_key]).to eq("default")
    end

    it "collects job arguments with inspection" do
      attributes = collector.collect_attributes(job)
      arguments_key = attributes.keys.find { |k| k.end_with?(".arguments") }
      
      # Allow for different symbol syntax in Hash#inspect output
      expect(attributes[arguments_key]).to match(/\["agent_id_123", \{.*mode.*async.*priority.*high.*\}\]/)
    end

    it "truncates long arguments to 101 characters" do
      long_args = ["x" * 200, "y" * 200]
      allow(job).to receive(:arguments).and_return(long_args)

      attributes = collector.collect_attributes(job)
      arguments_key = attributes.keys.find { |k| k.end_with?(".arguments") }

      expect(attributes[arguments_key].length).to eq(101)
      expect(attributes[arguments_key]).to start_with('["xxxx')
    end

    it "handles missing arguments gracefully" do
      allow(job).to receive(:respond_to?).with(:arguments).and_return(false)
      
      attributes = collector.collect_attributes(job)
      arguments_key = attributes.keys.find { |k| k.end_with?(".arguments") }
      expect(attributes[arguments_key]).to eq("N/A")
    end

    it "handles nil arguments" do
      allow(job).to receive(:arguments).and_return(nil)
      
      attributes = collector.collect_attributes(job)
      arguments_key = attributes.keys.find { |k| k.end_with?(".arguments") }
      expect(attributes[arguments_key]).to eq("nil")
    end

    it "handles empty arguments" do
      allow(job).to receive(:arguments).and_return([])
      
      attributes = collector.collect_attributes(job)
      arguments_key = attributes.keys.find { |k| k.end_with?(".arguments") }
      expect(attributes[arguments_key]).to eq("[]")
    end
  end

  describe "#collect_result" do
    let(:successful_result) { double("Result", status: "completed", class: double("ResultClass", name: "JobResult")) }
    let(:failed_result) { double("Result", status: "failed", class: double("ResultClass", name: "JobResult")) }
    
    it "collects base result attributes" do
      allow(successful_result).to receive(:respond_to?).with(:status).and_return(true)
      attributes = collector.collect_result(job, successful_result)

      expect(attributes).to include("result.type")
      expect(attributes).to include("result.success")
      expect(attributes["result.type"]).to eq("JobResult")
      expect(attributes["result.success"]).to be true
    end

    it "collects status from result when available" do
      allow(successful_result).to receive(:respond_to?).with(:status).and_return(true)
      
      attributes = collector.collect_result(job, successful_result)
      expect(attributes).to include("result.status")
      expect(attributes["result.status"]).to eq("completed")
    end

    it "handles failed job status" do
      allow(failed_result).to receive(:respond_to?).with(:status).and_return(true)
      
      attributes = collector.collect_result(job, failed_result)
      expect(attributes["result.status"]).to eq("failed")
    end

    it "falls back to unknown status when not available" do
      result_without_status = double("Result", class: double("ResultClass", name: "BasicResult"))
      allow(result_without_status).to receive(:respond_to?).with(:status).and_return(false)
      
      attributes = collector.collect_result(job, result_without_status)
      expect(attributes["result.status"]).to eq("unknown")
    end

    it "handles nil result" do
      attributes = collector.collect_result(job, nil)

      expect(attributes["result.type"]).to eq("NilClass")
      expect(attributes["result.success"]).to be false
      expect(attributes["result.status"]).to eq("unknown")
    end

    it "handles string results" do
      string_result = "Job completed successfully"
      
      attributes = collector.collect_result(job, string_result)
      expect(attributes["result.type"]).to eq("String")
      expect(attributes["result.status"]).to eq("unknown")
    end

    it "handles hash results" do
      hash_result = { status: "success", data: "processed" }
      
      attributes = collector.collect_result(job, hash_result)
      expect(attributes["result.type"]).to eq("Hash")
      expect(attributes["result.status"]).to eq("unknown")  # Hash doesn't respond_to status
    end
  end

  describe "component prefix" do
    it "generates correct prefix for job collector" do
      prefix = collector.send(:component_prefix)
      expect(prefix).to match(/job$/)
    end
  end
end

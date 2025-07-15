# frozen_string_literal: true

require "spec_helper"

# Skip Rails-specific tests if Rails is not available
begin
  require "rails"
  require "active_record"
  require_relative "../../../../lib/openai_agents/tracing/rails_integrations"
  
  # Check if database connection is available
  ActiveRecord::Base.connection.migration_context.current_version
rescue LoadError, ActiveRecord::ConnectionNotDefined, ActiveRecord::NoDatabaseError => e
  puts "Skipping Rails tests: #{e.message}"
  return
end

RSpec.describe OpenAIAgents::Tracing::RailsIntegrations do
  describe OpenAIAgents::Tracing::RailsIntegrations::JobTracing do
    let(:job_class) do
      Class.new(ActiveJob::Base) do
        include OpenAIAgents::Tracing::RailsIntegrations::JobTracing
        
        def perform(data)
          @performed_data = data
        end
        
        attr_reader :performed_data
      end
    end

    let(:job) { job_class.new("test_data") }

    before do
      allow(OpenAIAgents).to receive(:trace).and_yield(double("trace", metadata: {}))
    end

    it "wraps job execution in a trace" do
      expect(OpenAIAgents).to receive(:trace).with(/Job/)
      job.perform_now
    end

    it "adds job metadata to trace" do
      trace_metadata = {}
      allow(OpenAIAgents).to receive(:trace).and_yield(double("trace", metadata: trace_metadata))
      
      job.perform_now
      
      expect(trace_metadata).to include(
        job_class: job_class.name,
        arguments: ["test_data"]
      )
    end

    it "executes the job successfully" do
      job.perform_now
      expect(job.performed_data).to eq("test_data")
    end

    it "propagates job exceptions" do
      failing_job_class = Class.new(ActiveJob::Base) do
        include OpenAIAgents::Tracing::RailsIntegrations::JobTracing
        
        def perform
          raise StandardError, "Job failed"
        end
      end

      job = failing_job_class.new
      expect { job.perform_now }.to raise_error(StandardError, "Job failed")
    end
  end

  describe OpenAIAgents::Tracing::RailsIntegrations::CorrelationMiddleware do
    let(:app) { ->(_env) { [200, {}, ["OK"]] } }
    let(:middleware) { described_class.new(app) }
    let(:env) { Rack::MockRequest.env_for("http://example.com/test") }

    before do
      # Mock Rails request
      allow(ActionDispatch::Request).to receive(:new).with(env).and_return(
        double("request", 
               request_id: "req_123", 
               user_agent: "TestAgent/1.0",
               remote_ip: "192.168.1.1")
      )
    end

    it "sets thread-local correlation data" do
      middleware.call(env)
      
      expect(Thread.current[:openai_agents_request_id]).to eq("req_123")
      expect(Thread.current[:openai_agents_user_agent]).to eq("TestAgent/1.0")
      expect(Thread.current[:openai_agents_remote_ip]).to eq("192.168.1.1")
    end

    it "cleans up thread-local data after request" do
      middleware.call(env)
      
      expect(Thread.current[:openai_agents_request_id]).to be_nil
      expect(Thread.current[:openai_agents_user_agent]).to be_nil
      expect(Thread.current[:openai_agents_remote_ip]).to be_nil
    end

    it "calls the next middleware" do
      expect(app).to receive(:call).with(env).and_return([200, {}, ["OK"]])
      response = middleware.call(env)
      expect(response).to eq([200, {}, ["OK"]])
    end

    it "cleans up even if exception occurs" do
      failing_app = ->(_env) { raise StandardError, "App failed" }
      failing_middleware = described_class.new(failing_app)
      
      expect { failing_middleware.call(env) }.to raise_error(StandardError, "App failed")
      
      expect(Thread.current[:openai_agents_request_id]).to be_nil
      expect(Thread.current[:openai_agents_user_agent]).to be_nil
      expect(Thread.current[:openai_agents_remote_ip]).to be_nil
    end
  end

  describe OpenAIAgents::Tracing::RailsIntegrations::ConsoleHelpers do
    let(:helper_class) do
      Class.new do
        include OpenAIAgents::Tracing::RailsIntegrations::ConsoleHelpers
      end
    end
    
    let(:helper) { helper_class.new }
    let(:trace) { OpenAIAgents::Tracing::Trace.create!(workflow_name: "Test Workflow") }

    describe "#recent_traces" do
      before do
        allow(OpenAIAgents::Tracing::Trace).to receive(:recent).and_return(
          double("relation", limit: double("limited", includes: [trace]))
        )
      end

      it "returns recent traces" do
        result = helper.recent_traces(5)
        expect(result).to include(trace)
      end

      it "handles missing models gracefully" do
        stub_const("OpenAIAgents::Tracing::Trace", nil)
        expect(helper.recent_traces).to eq([])
      end
    end

    describe "#traces_for" do
      before do
        allow(OpenAIAgents::Tracing::Trace).to receive(:by_workflow).with("Test Workflow").and_return(
          double("relation", recent: double("recent", limit: double("limited", includes: [trace])))
        )
      end

      it "returns traces for specific workflow" do
        result = helper.traces_for("Test Workflow")
        expect(result).to include(trace)
      end
    end

    describe "#performance_stats" do
      before do
        allow(OpenAIAgents::Tracing::Trace).to receive(:within_timeframe).and_return(
          double("traces", 
                 count: 10,
                 completed: double("completed", count: 8),
                 failed: double("failed", count: 1),
                 running: double("running", count: 1))
        )
        allow(OpenAIAgents::Tracing::Span).to receive(:within_timeframe).and_return(
          double("spans",
                 count: 50,
                 errors: double("errors", count: 5))
        )
      end

      it "prints performance statistics" do
        expect { helper.performance_stats }.to output(/Performance Stats/).to_stdout
      end
    end

    describe "#trace_summary" do
      let(:span) { double("span", name: "test_span", kind: "llm", status: "ok", duration_ms: 1000) }
      
      before do
        allow(helper).to receive(:trace).with(trace.trace_id).and_return(trace)
        allow(trace).to receive_messages(
          trace_id: trace.trace_id,
          workflow_name: "Test Workflow",
          status: "completed",
          duration_ms: 5000,
          started_at: 1.hour.ago,
          ended_at: 30.minutes.ago
        )
        allow(trace).to receive(:spans).and_return(
          double("spans", 
                 count: 1,
                 where: double("error_spans", count: 0),
                 order: [span])
        )
      end

      it "prints trace summary" do
        expect { helper.trace_summary(trace.trace_id) }.to output(/Trace Summary/).to_stdout
      end

      it "handles missing trace" do
        allow(helper).to receive(:trace).with("missing").and_return(nil)
        expect { helper.trace_summary("missing") }.to output(/Trace not found/).to_stdout
      end
    end
  end

  describe OpenAIAgents::Tracing::RailsIntegrations::RakeTasks do
    describe ".cleanup_old_traces" do
      before do
        allow(OpenAIAgents::Tracing::Trace).to receive(:cleanup_old_traces).and_return(5)
      end

      it "calls cleanup and reports results" do
        expect do 
          described_class.cleanup_old_traces(older_than: 1.month) 
        end.to output(/Cleaned up 5 traces/).to_stdout
      end

      it "handles missing models gracefully" do
        stub_const("OpenAIAgents::Tracing::Trace", nil)
        result = described_class.cleanup_old_traces
        expect(result).to eq(0)
      end
    end

    describe ".performance_report" do
      before do
        allow(OpenAIAgents::Tracing::Trace).to receive(:performance_stats).and_return({
                                                                                        total_traces: 100,
                                                                                        success_rate: 95.0,
                                                                                        avg_duration: 2.5
                                                                                      })
        allow(OpenAIAgents::Tracing::Trace).to receive(:top_workflows).and_return([
                                                                                    { workflow_name: "Test Workflow", trace_count: 50, success_rate: 98.0 }
                                                                                  ])
        allow(OpenAIAgents::Tracing::Span).to receive(:error_analysis).and_return({
                                                                                    total_errors: 5,
                                                                                    errors_by_kind: { "llm" => 3, "tool" => 2 }
                                                                                  })
      end

      it "generates comprehensive performance report" do
        expect do 
          described_class.performance_report(timeframe: 24.hours) 
        end.to output(/Performance Report.*Total Traces: 100.*Test Workflow: 50/m).to_stdout
      end

      it "handles missing models gracefully" do
        stub_const("OpenAIAgents::Tracing::Trace", nil)
        expect { described_class.performance_report }.not_to raise_error
      end
    end
  end
end
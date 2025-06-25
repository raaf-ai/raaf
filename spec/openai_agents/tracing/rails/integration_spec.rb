# frozen_string_literal: true

require "spec_helper"

# Skip Rails-specific tests if Rails is not available
begin
  require "rails"
  require "active_record"
  require_relative "../../../../lib/openai_agents/tracing/active_record_processor"
  
  # Check if database connection is available
  ActiveRecord::Base.connection.migration_context.current_version
rescue LoadError, ActiveRecord::ConnectionNotDefined, ActiveRecord::NoDatabaseError => e
  puts "Skipping Rails tests: #{e.message}"
  return
end

RSpec.describe "Rails Tracing Integration" do
  describe "end-to-end integration" do
    let(:agent) do
      OpenAIAgents::Agent.new(
        name: "TestAgent",
        instructions: "You are a helpful test agent.",
        model: "gpt-4o"
      )
    end

    let(:processor) do
      OpenAIAgents::Tracing::ActiveRecordProcessor.new(
        sampling_rate: 1.0,
        batch_size: 1
      )
    end

    before do
      # Set up tracing with ActiveRecord processor
      OpenAIAgents.tracer.add_processor(processor)
      
      # Mock OpenAI API response
      allow_any_instance_of(OpenAIAgents::Models::ResponsesProvider).to receive(:run).and_return(
        OpenAIAgents::Result.new(
          agent: agent,
          messages: [{ role: "assistant", content: "Hello from test agent!" }]
        )
      )
    end

    after do
      # Clean up
      OpenAIAgents.tracer.instance_variable_set(:@processors, [])
    end

    it "traces agent execution and stores in database" do
      # Execute agent within a trace
      trace_result = nil
      OpenAIAgents.trace("Integration Test") do
        runner = OpenAIAgents::Runner.new(agent: agent)
        trace_result = runner.run("Hello, test agent!")
      end

      # Verify trace was created in database
      expect(OpenAIAgents::Tracing::Trace.count).to eq(1)
      
      trace = OpenAIAgents::Tracing::Trace.first
      expect(trace.workflow_name).to eq("Integration Test")
      expect(trace.status).to be_in(%w[completed running])

      # Verify spans were created
      expect(OpenAIAgents::Tracing::Span.count).to be >= 1
      
      agent_span = OpenAIAgents::Tracing::Span.find_by(kind: "agent")
      expect(agent_span).to be_present
      expect(agent_span.name).to include("TestAgent")
      expect(agent_span.trace_id).to eq(trace.trace_id)

      # Verify result
      expect(trace_result).to be_a(OpenAIAgents::Result)
      expect(trace_result.messages.last[:content]).to eq("Hello from test agent!")
    end

    it "handles job tracing integration" do
      # Create a test job class
      job_class = Class.new(ActiveJob::Base) do
        include OpenAIAgents::Tracing::RailsIntegrations::JobTracing
        
        def perform(message)
          @test_agent = OpenAIAgents::Agent.new(
            name: "JobAgent",
            instructions: "Test job agent",
            model: "gpt-4o"
          )
          
          runner = OpenAIAgents::Runner.new(agent: @test_agent)
          runner.run(message)
        end
      end

      # Mock the job execution
      allow_any_instance_of(job_class).to receive(:job_id).and_return("job_123")
      allow_any_instance_of(job_class).to receive(:queue_name).and_return("default")
      allow_any_instance_of(job_class).to receive(:arguments).and_return(["test message"])
      allow_any_instance_of(job_class).to receive(:executions).and_return(1)
      allow_any_instance_of(job_class).to receive(:enqueued_at).and_return(1.minute.ago)

      # Execute the job
      job = job_class.new("test message")
      job.perform_now

      # Verify job trace was created
      job_trace = OpenAIAgents::Tracing::Trace.find_by(workflow_name: /Job/)
      expect(job_trace).to be_present
      expect(job_trace.metadata["job_id"]).to eq("job_123")
      expect(job_trace.metadata["arguments"]).to eq(["test message"])
    end

    it "provides console helpers functionality" do
      # Create test data
      trace = OpenAIAgents::Tracing::Trace.create!(
        workflow_name: "Console Test",
        status: "completed",
        started_at: 1.hour.ago,
        ended_at: 30.minutes.ago
      )

      span = OpenAIAgents::Tracing::Span.create!(
        span_id: "span_test123",
        trace_id: trace.trace_id,
        name: "test_span",
        kind: "llm",
        start_time: 1.hour.ago,
        end_time: 30.minutes.ago,
        duration_ms: 1_800_000,
        status: "ok"
      )

      # Test console helpers
      helper_class = Class.new do
        include OpenAIAgents::Tracing::RailsIntegrations::ConsoleHelpers
      end
      helper = helper_class.new

      # Test recent_traces
      recent = helper.recent_traces(5)
      expect(recent).to include(trace)

      # Test traces_for
      workflow_traces = helper.traces_for("Console Test")
      expect(workflow_traces).to include(trace)

      # Test trace lookup
      found_trace = helper.trace(trace.trace_id)
      expect(found_trace).to eq(trace)

      # Test span lookup
      found_span = helper.span("span_test123")
      expect(found_span).to eq(span)
    end

    it "supports search functionality" do
      # Create searchable test data
      trace = OpenAIAgents::Tracing::Trace.create!(
        workflow_name: "Searchable Workflow",
        status: "completed"
      )

      span = OpenAIAgents::Tracing::Span.create!(
        span_id: "span_search123",
        trace_id: trace.trace_id,
        name: "searchable_operation",
        kind: "tool",
        start_time: 1.hour.ago,
        status: "ok",
        span_attributes: { "tool.name" => "search_tool" }
      )

      # Test search controller functionality
      search_controller = OpenAIAgents::Tracing::SearchController.new
      search_controller.instance_variable_set(:@query, "searchable")

      # Test trace search
      found_traces = search_controller.send(:search_traces)
      expect(found_traces).to include(trace)

      # Test span search
      found_spans = search_controller.send(:search_spans)
      expect(found_spans).to include(span)
    end

    it "calculates performance metrics correctly" do
      # Create performance test data
      trace = OpenAIAgents::Tracing::Trace.create!(
        workflow_name: "Performance Test",
        status: "completed",
        started_at: 2.hours.ago,
        ended_at: 1.hour.ago
      )

      # Create spans with known performance characteristics
      OpenAIAgents::Tracing::Span.create!(
        span_id: "fast_span123",
        trace_id: trace.trace_id,
        name: "fast_operation",
        kind: "llm",
        duration_ms: 100,
        status: "ok",
        start_time: 2.hours.ago
      )

      OpenAIAgents::Tracing::Span.create!(
        span_id: "slow_span123", 
        trace_id: trace.trace_id,
        name: "slow_operation",
        kind: "llm",
        duration_ms: 5000,
        status: "ok",
        start_time: 2.hours.ago
      )

      # Test performance metrics
      metrics = OpenAIAgents::Tracing::Span.performance_metrics(kind: "llm")
      expect(metrics[:total_spans]).to be >= 2
      expect(metrics[:avg_duration_ms]).to be_a(Numeric)
      expect(metrics[:success_rate]).to eq(100.0)

      # Test trace performance summary
      summary = trace.performance_summary
      expect(summary[:total_spans]).to eq(2)
      expect(summary[:success_rate]).to eq(100.0)
    end
  end

  describe "engine configuration" do
    it "loads Rails integration components conditionally" do
      # Verify Rails-specific classes are loaded
      expect(defined?(OpenAIAgents::Tracing::Engine)).to be_truthy
      expect(defined?(OpenAIAgents::Tracing::ActiveRecordProcessor)).to be_truthy
      expect(defined?(OpenAIAgents::Tracing::RailsIntegrations)).to be_truthy
    end

    it "provides configuration options" do
      config = OpenAIAgents::Tracing.configuration
      expect(config).to respond_to(:auto_configure)
      expect(config).to respond_to(:mount_path)
      expect(config).to respond_to(:retention_days)
      expect(config).to respond_to(:sampling_rate)
    end

    it "allows configuration changes" do
      original_config = {
        auto_configure: OpenAIAgents::Tracing.configuration.auto_configure,
        mount_path: OpenAIAgents::Tracing.configuration.mount_path,
        retention_days: OpenAIAgents::Tracing.configuration.retention_days,
        sampling_rate: OpenAIAgents::Tracing.configuration.sampling_rate
      }

      # Change configuration
      OpenAIAgents::Tracing.configure do |config|
        config.auto_configure = true
        config.mount_path = "/custom-tracing"
        config.retention_days = 14
        config.sampling_rate = 0.5
      end

      # Verify changes
      config = OpenAIAgents::Tracing.configuration
      expect(config.auto_configure).to be true
      expect(config.mount_path).to eq("/custom-tracing")
      expect(config.retention_days).to eq(14)
      expect(config.sampling_rate).to eq(0.5)

      # Restore original configuration
      OpenAIAgents::Tracing.configure do |config|
        config.auto_configure = original_config[:auto_configure]
        config.mount_path = original_config[:mount_path]
        config.retention_days = original_config[:retention_days]
        config.sampling_rate = original_config[:sampling_rate]
      end
    end
  end
end
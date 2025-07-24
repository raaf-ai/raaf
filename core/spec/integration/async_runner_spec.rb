# frozen_string_literal: true

require "spec_helper"

require "async"
require_relative "../../lib/raaf/streaming/async"

RSpec.describe RAAF::Async::Runner do
  let(:agent) do
    RAAF::Agent.new(
      name: "AsyncTestAgent",
      instructions: "You are a helpful assistant.",
      model: "gpt-4o"
    )
  end

  let(:messages) { [{ role: "user", content: "Hello" }] }
  let(:mock_response) do
    {
      "choices" => [
        {
          "message" => {
            "role" => "assistant",
            "content" => "Hello! How can I help you?"
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => { "total_tokens" => 15 }
    }
  end

  describe "#initialize" do
    it "creates an async runner with an agent" do
      runner = described_class.new(agent: agent)
      expect(runner.agent).to eq(agent)
    end

    it "wraps synchronous providers in AsyncProviderWrapper" do
      sync_provider = RAAF::Models::OpenAIProvider.new
      runner = described_class.new(agent: agent, provider: sync_provider)

      async_provider = runner.instance_variable_get(:@async_provider)
      expect(async_provider).to be_a(described_class::AsyncProviderWrapper)
    end

    it "uses async providers directly if they support async_chat_completion" do
      async_provider = double("AsyncProvider")
      allow(async_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(true)

      runner = described_class.new(agent: agent, provider: async_provider)
      expect(runner.instance_variable_get(:@async_provider)).to eq(async_provider)
    end
  end

  describe "#run_async" do
    let(:mock_provider) { double("MockProvider") }
    let(:runner) { described_class.new(agent: agent, provider: mock_provider) }

    before do
      allow(mock_provider).to receive(:chat_completion).and_return(mock_response)
      allow(mock_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
    end

    it "returns an Async task" do
      task = runner.run_async(messages)
      expect(task).to be_a(Async::Task)
    end

    it "processes messages asynchronously" do
      Async do
        result = runner.run_async(messages).wait
        expect(result).to be_a(RAAF::RunResult)
        expect(result.messages.size).to eq(3) # system + user + assistant
        expect(result.messages.first[:role]).to eq("system")
        expect(result.messages[1][:role]).to eq("user")
        expect(result.messages.last[:role]).to eq("assistant")
      end
    end

    it "handles config parameters" do
      config = RAAF::RunConfig.new(max_turns: 5)

      Async do
        result = runner.run_async(messages, config: config).wait
        expect(result).to be_success
      end
    end

    it "normalizes string messages to message arrays" do
      Async do
        result = runner.run_async("Hello there").wait
        expect(result.messages.size).to eq(3) # system + user + assistant
        expect(result.messages.first[:role]).to eq("system")
        expect(result.messages[1][:role]).to eq("user")
        expect(result.messages[1][:content]).to eq("Hello there")
      end
    end
  end

  describe "#run" do
    let(:mock_provider) { double("MockProvider") }
    let(:runner) { described_class.new(agent: agent, provider: mock_provider) }

    before do
      allow(mock_provider).to receive(:chat_completion).and_return(mock_response)
      allow(mock_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
    end

    it "waits for async completion synchronously" do
      result = runner.run(messages)
      expect(result).to be_a(RAAF::RunResult)
      expect(result.messages.last[:content]).to eq("Hello! How can I help you?")
    end
  end

  describe "async tool execution" do
    let(:agent_with_tools) do
      agent = RAAF::Agent.new(name: "AsyncToolAgent")
      agent.add_tool(RAAF::FunctionTool.new(
                       proc { |x:| x * 2 },
                       name: "double",
                       description: "Doubles a number"
                     ))
      agent
    end

    let(:runner) { described_class.new(agent: agent_with_tools) }

    let(:tool_response) do
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [
                {
                  "id" => "call_123",
                  "type" => "function",
                  "function" => {
                    "name" => "double",
                    "arguments" => '{"x": 5}'
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ]
      }
    end

    let(:final_response) do
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "The result is 10."
            },
            "finish_reason" => "stop"
          }
        ]
      }
    end

    before do
      allow_any_instance_of(RAAF::Models::ResponsesProvider)
        .to receive(:chat_completion)
        .and_return(tool_response, final_response)
    end

    it "executes tools asynchronously" do
      Async do
        result = runner.run_async(messages).wait

        # Should have user, assistant (tool call), tool result, and final assistant message
        expect(result.messages.size).to eq(4)
        expect(result.messages[2][:role]).to eq("tool")
        expect(result.messages[2][:content]).to eq("10")
        expect(result.messages.last[:content]).to eq("The result is 10.")
      end
    end
  end

  describe "async agent handoffs" do
    let(:handoff_agent) do
      RAAF::Agent.new(
        name: "HandoffAgent",
        instructions: "I handle handoffs"
      )
    end

    let(:main_agent) do
      agent = RAAF::Agent.new(
        name: "MainAgent",
        instructions: "I can hand off to other agents"
      )
      agent.add_handoff(handoff_agent)
      agent
    end

    let(:runner) { described_class.new(agent: main_agent) }

    let(:handoff_response) do
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "HANDOFF: HandoffAgent"
            },
            "finish_reason" => "stop"
          }
        ]
      }
    end

    let(:handoff_final_response) do
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "Handoff completed successfully."
            },
            "finish_reason" => "stop"
          }
        ]
      }
    end

    before do
      allow_any_instance_of(RAAF::Models::ResponsesProvider)
        .to receive(:chat_completion)
        .and_return(handoff_response, handoff_final_response)
    end

    it "handles agent handoffs asynchronously" do
      Async do
        result = runner.run_async(messages).wait

        expect(result).to be_success
        expect(result.last_agent.name).to eq("HandoffAgent")
      end
    end
  end

  describe "error handling" do
    let(:mock_provider) { double("MockProvider") }
    let(:runner) { described_class.new(agent: agent, provider: mock_provider) }

    before do
      allow(mock_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
    end

    it "handles API errors gracefully" do
      allow(mock_provider).to receive(:chat_completion)
        .and_raise(RAAF::APIError, "API failed")

      Async do
        expect do
          runner.run_async(messages).wait
        end.to raise_error(RAAF::APIError, "API failed")
      end
    end

    it "handles max turns exceeded" do
      agent.max_turns = 1

      # Mock a response that would cause infinite loop without max turns
      loop_response = {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [
                {
                  "id" => "call_123",
                  "type" => "function",
                  "function" => {
                    "name" => "nonexistent_tool",
                    "arguments" => "{}"
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ]
      }

      allow(mock_provider).to receive(:chat_completion).and_return(loop_response)

      Async do
        expect do
          runner.run_async(messages).wait
        end.to raise_error(RAAF::MaxTurnsError)
      end
    end
  end

  describe "AsyncProviderWrapper" do
    let(:sync_provider) { RAAF::Models::OpenAIProvider.new }
    let(:wrapper) { described_class::AsyncProviderWrapper.new(sync_provider) }

    it "wraps synchronous providers" do
      expect(wrapper.instance_variable_get(:@sync_provider)).to eq(sync_provider)
    end

    it "provides async_chat_completion method" do
      expect(wrapper).to respond_to(:async_chat_completion)
    end

    it "wraps sync calls in Async blocks" do
      allow(sync_provider).to receive(:chat_completion).and_return(mock_response)

      Async do
        result = wrapper.async_chat_completion(
          messages: messages,
          model: "gpt-4o"
        ).wait

        expect(result).to eq(mock_response)
      end
    end
  end

  describe "process_async method" do
    let(:runner) { described_class.new(agent: agent) }

    before do
      allow_any_instance_of(RAAF::Models::ResponsesProvider)
        .to receive(:chat_completion).and_return(mock_response)
    end

    it "returns a task ID" do
      task_id = runner.process_async(agent, "test message")
      expect(task_id).to be_a(String)
      expect(task_id).to include("task_")
    end

    it "stores task information" do
      task_id = runner.process_async(agent, "test message")

      active_tasks = runner.instance_variable_get(:@active_tasks)
      expect(active_tasks).to have_key(task_id)

      task = active_tasks[task_id]
      expect(task[:agent]).to eq(agent)
      expect(task[:message]).to eq("test message")
      expect(task[:status]).to eq(:queued)
    end

    it "accepts completion block" do
      completed_results = []
      completion_block = proc { |result| completed_results << result }

      task_id = runner.process_async(agent, "test message", &completion_block)

      # Wait briefly for async execution
      sleep(0.1)

      expect(runner.instance_variable_get(:@active_tasks)[task_id][:block]).to eq(completion_block)
    end
  end

  describe "process_concurrent method" do
    let(:agents) { [agent, RAAF::Agent.new(name: "Agent2", instructions: "Second agent")] }
    let(:runner) { described_class.new(agent: agent) }

    before do
      allow_any_instance_of(RAAF::Models::ResponsesProvider)
        .to receive(:chat_completion).and_return(mock_response)
    end

    it "returns array of task IDs" do
      task_ids = runner.process_concurrent(agents, "test message")
      expect(task_ids).to be_an(Array)
      expect(task_ids.size).to eq(2)
      expect(task_ids).to all(be_a(String))
    end

    it "processes each agent" do
      expect(runner).to receive(:process_async).twice.and_call_original
      runner.process_concurrent(agents, "test message")
    end

    it "calls completion block for each agent" do
      results = []
      completion_block = proc { |agent_instance, result| results << [agent_instance, result] }

      runner.process_concurrent(agents, "test message", &completion_block)

      # Verify that tasks were created with the block
      active_tasks = runner.instance_variable_get(:@active_tasks)
      expect(active_tasks.size).to eq(2)
    end
  end

  describe "task management methods" do
    let(:runner) { described_class.new(agent: agent) }

    before do
      # Set up mock tasks
      active_tasks = runner.instance_variable_get(:@active_tasks)
      active_tasks["task_1"] = {
        status: :completed,
        result: "result_1",
        started_at: Time.now - 1,
        completed_at: Time.now
      }
      active_tasks["task_2"] = {
        status: :running,
        result: nil,
        started_at: Time.now - 0.5
      }
      active_tasks["task_3"] = {
        status: :queued,
        started_at: Time.now
      }
    end

    describe "#wait_for_tasks" do
      it "returns results for completed tasks" do
        results = runner.wait_for_tasks(["task_1"], timeout: 1)

        expect(results.size).to eq(1)
        expect(results[0][:task_id]).to eq("task_1")
        expect(results[0][:result]).to eq("result_1")
        expect(results[0][:duration]).to be_a(Numeric)
      end

      it "waits for running tasks up to timeout" do
        start_time = Time.now
        results = runner.wait_for_tasks(["task_2"], timeout: 0.2)
        end_time = Time.now

        expect(results).to be_empty
        expect(end_time - start_time).to be >= 0.2
      end
    end

    describe "#cancel_task" do
      it "cancels running tasks" do
        expect(runner.cancel_task("task_2")).to be true

        active_tasks = runner.instance_variable_get(:@active_tasks)
        expect(active_tasks["task_2"][:status]).to eq(:cancelled)
      end

      it "returns false for non-running tasks" do
        expect(runner.cancel_task("task_1")).to be false
      end

      it "returns false for non-existent tasks" do
        expect(runner.cancel_task("non_existent")).to be false
      end
    end

    describe "#task_status" do
      it "returns task status information" do
        status = runner.task_status("task_1")

        expect(status[:task_id]).to eq("task_1")
        expect(status[:status]).to eq(:completed)
        expect(status[:started_at]).to be_a(Time)
        expect(status[:completed_at]).to be_a(Time)
        expect(status[:duration]).to be_a(Numeric)
      end

      it "returns nil for non-existent tasks" do
        expect(runner.task_status("non_existent")).to be_nil
      end
    end

    describe "#active_tasks" do
      it "returns only running task IDs" do
        running_tasks = runner.active_tasks
        expect(running_tasks).to contain_exactly("task_2")
      end
    end

    describe "#stats" do
      it "returns comprehensive statistics" do
        # Set task counter
        runner.instance_variable_set(:@task_counter, 10)

        stats = runner.stats

        expect(stats[:pool_size]).to eq(10)
        expect(stats[:queue_size]).to eq(100)
        expect(stats[:active_tasks]).to eq(1)
        expect(stats[:queued_tasks]).to eq(1)
        expect(stats[:completed_tasks]).to eq(1)
        expect(stats[:failed_tasks]).to eq(0)
        expect(stats[:total_tasks]).to eq(10)
      end
    end

    describe "#job_count" do
      it "returns number of active tasks" do
        expect(runner.job_count).to eq(3)
      end
    end
  end

  describe "retry functionality" do
    let(:runner) { described_class.new(agent: agent) }

    describe "#process_with_retry" do
      it "returns a task ID" do
        task_id = runner.process_with_retry(agent, "test message")
        expect(task_id).to be_a(String)
      end

      it "stores retry configuration" do
        task_id = runner.process_with_retry(
          agent,
          "test message",
          retry_count: 5,
          retry_delay: 2.0
        )

        active_tasks = runner.instance_variable_get(:@active_tasks)
        task = active_tasks[task_id]

        expect(task[:retry_count]).to eq(5)
        expect(task[:retry_delay]).to eq(2.0)
        expect(task[:attempts]).to eq(0)
      end
    end
  end

  describe "streaming session" do
    let(:runner) { described_class.new(agent: agent) }

    describe "#create_streaming_session" do
      it "creates an AsyncStreamingSession" do
        session = runner.create_streaming_session(agent)
        expect(session).to be_a(RAAF::Async::AsyncStreamingSession)
        expect(session.agent).to eq(agent)
        expect(session.runner).to eq(runner)
      end

      it "passes options to session" do
        expect(RAAF::Async::AsyncStreamingSession).to receive(:new).with(
          agent: agent,
          runner: runner,
          custom_option: "value"
        )

        runner.create_streaming_session(agent, custom_option: "value")
      end
    end
  end

  describe "shutdown functionality" do
    let(:runner) { described_class.new(agent: agent) }

    describe "#shutdown" do
      it "marks runner as shutdown" do
        runner.shutdown
        expect(runner.shutdown?).to be true
      end

      it "cancels all active tasks" do
        active_tasks = runner.instance_variable_get(:@active_tasks)
        active_tasks["task_1"] = { status: :running }
        active_tasks["task_2"] = { status: :running }

        runner.shutdown

        expect(active_tasks["task_1"][:status]).to eq(:cancelled)
        expect(active_tasks["task_2"][:status]).to eq(:cancelled)
      end
    end
  end

  describe "logging methods" do
    let(:runner) { described_class.new(agent: agent) }

    before do
      # Test without RAAF::Logging defined
      hide_const("RAAF::Logging") if defined?(RAAF::Logging)
    end

    describe "#log_info" do
      it "outputs to puts when RAAF::Logging not available and debug level" do
        ENV["RAAF_LOG_LEVEL"] = "debug"
        expect { runner.log_info("test message", key: "value") }.to output(
          "[INFO] test message {:key=>\"value\"}\n"
        ).to_stdout
      end

      it "doesn't output when log level is not debug" do
        ENV["RAAF_LOG_LEVEL"] = "info"
        expect { runner.log_info("test message") }.not_to output.to_stdout
      end
    end

    describe "#log_debug" do
      it "outputs to puts when debug level" do
        ENV["RAAF_LOG_LEVEL"] = "debug"
        expect { runner.log_debug("debug message") }.to output(
          "[DEBUG] debug message {}\n"
        ).to_stdout
      end
    end

    describe "#log_warn" do
      it "outputs to puts when debug level" do
        ENV["RAAF_LOG_LEVEL"] = "debug"
        expect { runner.log_warn("warning message") }.to output(
          "[WARN] warning message {}\n"
        ).to_stdout
      end
    end

    describe "#log_error" do
      it "always outputs error messages" do
        expect { runner.log_error("error message") }.to output(
          "[ERROR] error message {}\n"
        ).to_stdout
      end
    end
  end

  describe "tracing support" do
    let(:tracer) { defined?(RAAF::Tracing) ? RAAF::Tracing::SpanTracer.new : double("MockTracer") }
    let(:runner) { described_class.new(agent: agent, tracer: tracer, disabled_tracing: false) }

    before do
      # Mock both sync and async methods to ensure compatibility
      allow_any_instance_of(RAAF::Models::ResponsesProvider)
        .to receive(:chat_completion).and_return(mock_response)
      allow_any_instance_of(RAAF::Async::Runner::AsyncProviderWrapper)
        .to receive(:async_chat_completion).and_return(
          Async { mock_response }
        )
    end

    it "creates proper span hierarchy for async operations" do
      skip "RAAF::Tracing not available in core module" unless defined?(RAAF::Tracing)

      # Temporarily enable tracing for this test
      original_env = ENV.fetch("RAAF_DISABLE_TRACING", nil)
      ENV["RAAF_DISABLE_TRACING"] = "false"

      # Create a new runner with tracing enabled
      test_runner = described_class.new(agent: agent, tracer: tracer, disabled_tracing: false)

      spans = []
      tracer.add_processor(double("processor").tap do |p|
        allow(p).to receive(:on_span_start)
        allow(p).to receive(:on_span_end) { |span| spans << span }
      end)

      Async do
        test_runner.run_async(messages).wait
      end

      # Should have agent span
      agent_spans = spans.select { |s| s.kind == :agent }
      expect(agent_spans.size).to eq(1)
      expect(agent_spans.first.name).to include("AsyncTestAgent")

      # Restore environment
      ENV["RAAF_DISABLE_TRACING"] = original_env
    end
  end
end

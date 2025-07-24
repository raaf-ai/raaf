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

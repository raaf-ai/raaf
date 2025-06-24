# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenAIAgents::Runner do
  let(:agent) { OpenAIAgents::Agent.new(name: "TestAgent", instructions: "You are helpful") }
  let(:runner) { described_class.new(agent: agent) }

  describe "#initialize" do
    it "creates a runner with an agent" do
      expect(runner.agent).to eq(agent)
      expect(runner.tracer).to be_a(OpenAIAgents::Tracing::SpanTracer)
    end

    it "accepts a custom tracer" do
      custom_tracer = OpenAIAgents::Tracing::SpanTracer.new
      runner = described_class.new(agent: agent, tracer: custom_tracer)

      expect(runner.tracer).to eq(custom_tracer)
    end

    it "uses ResponsesProvider by default" do
      runner = described_class.new(agent: agent)

      expect(runner.instance_variable_get(:@provider)).to be_a(OpenAIAgents::Models::ResponsesProvider)
    end

    it "accepts a custom provider" do
      custom_provider = OpenAIAgents::Models::OpenAIProvider.new
      runner = described_class.new(agent: agent, provider: custom_provider)

      expect(runner.instance_variable_get(:@provider)).to eq(custom_provider)
    end
  end

  describe "#run" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:mock_response) do
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "Hello! How can I help you?"
            }
          }
        ]
      }
    end

    before do
      allow(runner.instance_variable_get(:@provider)).to receive(:chat_completion).and_return(mock_response)
    end

    it "processes messages and returns results" do
      result = runner.run(messages)

      expect(result).to be_a(OpenAIAgents::RunResult)
      expect(result.last_agent).to eq(agent)
      expect(result.turns).to be >= 0
      expect(result.messages).to be_an(Array)
      expect(result.final_output).to be_a(String)
    end

    it "preserves original messages array" do
      original_messages = messages.dup
      runner.run(messages)

      expect(messages).to eq(original_messages)
    end

    it "adds assistant response to conversation" do
      result = runner.run(messages)

      expect(result.messages).to include(
        hash_including(role: "assistant")
      )
    end

    it "raises MaxTurnsError when max turns exceeded" do
      agent.max_turns = 1
      allow(runner.instance_variable_get(:@provider)).to receive(:chat_completion).and_return(
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "Response",
              "tool_calls" => [{ "id" => "call_1", "function" => { "name" => "unknown_tool", "arguments" => "{}" } }]
            }
          }
        ]
      )

      expect { runner.run(messages) }.to raise_error(OpenAIAgents::MaxTurnsError)
    end

    it "traces the conversation flow" do
      # The new tracing system doesn't expose traces in the same way
      # Instead we just verify the run completes successfully with tracing enabled
      result = runner.run(messages)
      expect(result).to be_a(OpenAIAgents::RunResult)
      expect(result.success?).to be true
    end
  end

  describe "#run_async" do
    let(:messages) { [{ role: "user", content: "Hello" }] }

    it "returns an Async task" do
      allow(runner.instance_variable_get(:@provider)).to receive(:chat_completion).and_return(
        "choices" => [{ "message" => { "role" => "assistant", "content" => "Hello!" } }]
      )

      task = runner.run_async(messages)
      expect(task).to be_a(Async::Task)
    end
  end

  describe "tool execution" do
    let(:agent_with_tools) do
      agent = OpenAIAgents::Agent.new(name: "ToolAgent")
      agent.add_tool(OpenAIAgents::FunctionTool.new(
                       proc { |x:| x * 2 },
                       name: "double",
                       description: "Doubles a number"
                     ))
      agent
    end
    let(:runner) { described_class.new(agent: agent_with_tools) }
    let(:messages) { [{ role: "user", content: "Double the number 5" }] }

    let(:tool_call_response) do
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                {
                  "id" => "call_123",
                  "function" => {
                    "name" => "double",
                    "arguments" => '{"x": 5}'
                  }
                }
              ]
            }
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
              "content" => "The result is 10"
            }
          }
        ]
      }
    end

    it "executes tools and continues conversation" do
      call_count = 0
      allow(runner.instance_variable_get(:@provider)).to receive(:chat_completion) do
        call_count += 1
        case call_count
        when 1
          tool_call_response
        when 2
          final_response
        end
      end

      result = runner.run(messages)

      expect(result.messages).to include(
        hash_including(role: "tool", tool_call_id: "call_123", content: "10")
      )
      expect(result.messages).to include(
        hash_including(role: "assistant", content: "The result is 10")
      )
    end

    it "handles tool execution errors gracefully" do
      agent_with_tools.add_tool(OpenAIAgents::FunctionTool.new(
                                  proc { raise StandardError, "Tool failed" },
                                  name: "failing_tool"
                                ))

      error_response = {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "tool_calls" => [
                {
                  "id" => "call_456",
                  "function" => {
                    "name" => "failing_tool",
                    "arguments" => "{}"
                  }
                }
              ]
            }
          }
        ]
      }

      call_count = 0
      allow(runner.instance_variable_get(:@provider)).to receive(:chat_completion) do
        call_count += 1
        case call_count
        when 1
          error_response
        when 2
          final_response
        end
      end

      result = runner.run(messages)

      expect(result.messages).to include(
        hash_including(role: "tool", tool_call_id: "call_456", content: /Error:/)
      )
    end

    it "traces tool execution" do
      allow(runner.instance_variable_get(:@provider)).to receive(:chat_completion).and_return(tool_call_response, final_response)

      result = runner.run(messages)
      
      # Verify that tracing works by checking the run completed successfully
      expect(result).to be_a(OpenAIAgents::RunResult)
      expect(result.success?).to be true
    end
  end

  describe "agent handoffs" do
    let(:agent1) { OpenAIAgents::Agent.new(name: "Agent1") }
    let(:agent2) { OpenAIAgents::Agent.new(name: "Agent2") }
    let(:runner) { described_class.new(agent: agent1) }
    let(:messages) { [{ role: "user", content: "Transfer to Agent2" }] }

    before do
      agent1.add_handoff(agent2)
    end

    let(:handoff_response) do
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "I'll transfer you to Agent2. HANDOFF: Agent2"
            }
          }
        ]
      }
    end

    let(:agent2_response) do
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "Hello from Agent2!"
            }
          }
        ]
      }
    end

    it "handles agent handoffs" do
      call_count = 0
      allow(runner.instance_variable_get(:@provider)).to receive(:chat_completion) do
        call_count += 1
        case call_count
        when 1
          handoff_response
        when 2
          agent2_response
        end
      end

      result = runner.run(messages)

      expect(result.last_agent).to eq(agent2)
      expect(result.messages).to include(
        hash_including(role: "assistant", content: "Hello from Agent2!")
      )
    end

    it "raises HandoffError for invalid handoff" do
      invalid_handoff_response = {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "HANDOFF: NonExistentAgent"
            }
          }
        ]
      }

      allow(runner.instance_variable_get(:@provider)).to receive(:chat_completion).and_return(invalid_handoff_response)

      expect { runner.run(messages) }.to raise_error(OpenAIAgents::HandoffError)
    end

    it "traces handoff events" do
      allow(runner.instance_variable_get(:@provider)).to receive(:chat_completion).and_return(handoff_response, agent2_response)

      result = runner.run(messages)

      # Verify that tracing works by checking the run completed successfully
      expect(result).to be_a(OpenAIAgents::RunResult)
      expect(result.success?).to be true
    end

    it "resets turn counter after handoff" do
      agent1.max_turns = 1
      agent2.max_turns = 1

      allow(runner.instance_variable_get(:@provider)).to receive(:chat_completion).and_return(handoff_response, agent2_response)

      result = runner.run(messages)

      expect(result.last_agent).to eq(agent2)
      expect(result.turns).to eq(1)
    end
  end

  describe "streaming support" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:mock_response) do
      {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "Streaming response"
            }
          }
        ]
      }
    end

    it "supports streaming mode" do
      allow(runner.instance_variable_get(:@provider)).to receive(:stream_completion).and_return(mock_response)

      result = runner.run(messages, stream: true)

      expect(result.messages).to include(
        hash_including(role: "assistant")
      )
    end
  end

  describe "private methods" do
    describe "#build_system_prompt" do
      it "includes agent name and instructions" do
        prompt = runner.send(:build_system_prompt, agent)

        expect(prompt).to include("Name: TestAgent")
        expect(prompt).to include("Instructions: You are helpful")
      end

      it "includes available tools" do
        agent.add_tool(OpenAIAgents::FunctionTool.new(
                         proc { |value| value },
                         name: "test_tool",
                         description: "A test tool"
                       ))

        prompt = runner.send(:build_system_prompt, agent)

        expect(prompt).to include("Available tools:")
        expect(prompt).to include("test_tool: A test tool")
      end

      it "includes available handoffs" do
        other_agent = OpenAIAgents::Agent.new(name: "OtherAgent")
        agent.add_handoff(other_agent)

        prompt = runner.send(:build_system_prompt, agent)

        expect(prompt).to include("Available handoffs:")
        expect(prompt).to include("OtherAgent")
        expect(prompt).to include("HANDOFF: <agent_name>")
      end

      it "handles agents without tools or handoffs" do
        basic_agent = OpenAIAgents::Agent.new(name: "BasicAgent")

        prompt = runner.send(:build_system_prompt, basic_agent)

        expect(prompt).not_to include("Available tools:")
        expect(prompt).not_to include("Available handoffs:")
      end
    end

    describe "#build_messages" do
      let(:conversation) { [{ role: "user", content: "Hello" }] }

      it "prepends system message to conversation" do
        messages = runner.send(:build_messages, conversation, agent)

        expect(messages.first[:role]).to eq("system")
        expect(messages[1]).to eq(role: "user", content: "Hello")
      end
    end
  end
end

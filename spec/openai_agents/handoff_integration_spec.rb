# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Handoff Integration Tests" do
  let(:source_agent) { OpenAIAgents::Agent.new(name: "SourceAgent", instructions: "You are a source agent") }
  let(:target_agent) { OpenAIAgents::Agent.new(name: "TargetAgent", instructions: "You are a target agent") }
  let(:support_agent) { OpenAIAgents::Agent.new(name: "SupportAgent", instructions: "You are a support agent") }

  before do
    source_agent.add_handoff(target_agent)
    source_agent.add_handoff(support_agent)
  end

  describe "End-to-End Handoff Scenarios" do
    let(:mock_provider) { instance_double(OpenAIAgents::Models::ResponsesProvider) }
    let(:runner) { OpenAIAgents::Runner.new(agent: source_agent, provider: mock_provider) }

    before do
      allow(mock_provider).to receive(:responses_completion).and_return(mock_response)
    end

    context "with JSON-based handoffs" do
      it "successfully processes structured output handoffs" do
        # Mock response with JSON handoff
        mock_response = {
          "id" => "response_123",
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => [
                {
                  "type" => "text",
                  "text" => '{"response": "I understand your request", "handoff_to": "SupportAgent"}'
                }
              ]
            }
          ]
        }

        allow(mock_provider).to receive(:responses_completion).and_return(mock_response)

        result = runner.run("I need technical help")

        expect(result.last_agent.name).to eq("SupportAgent")
        expect(result.messages.last[:content]).to include("SupportAgent")
      end

      it "handles nested JSON handoff structures" do
        mock_response = {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => '{"handoff": {"to": "TargetAgent", "reason": "Specialized query"}}'
              }
            }
          ]
        }

        allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

        result = runner.run("Complex query here")

        expect(result.last_agent.name).to eq("TargetAgent")
      end

      it "ignores handoffs to non-existent agents" do
        mock_response = {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => '{"handoff_to": "NonExistentAgent"}'
              }
            }
          ]
        }

        allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

        result = runner.run("Test message")

        expect(result.last_agent.name).to eq("SourceAgent") # Should stay with original agent
      end
    end

    context "with text-based handoffs" do
      it "processes transfer language handoffs" do
        mock_response = {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "I'll transfer you to the SupportAgent for technical assistance."
              }
            }
          ]
        }

        allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

        result = runner.run("I need help with a technical issue")

        expect(result.last_agent.name).to eq("SupportAgent")
      end

      it "processes contact language handoffs" do
        mock_response = {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "Please contact TargetAgent for more information about that topic."
              }
            }
          ]
        }

        allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

        result = runner.run("I need specific information")

        expect(result.last_agent.name).to eq("TargetAgent")
      end

      it "processes explicit agent name mentions" do
        mock_response = {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "For this type of request, you need SupportAgent assistance."
              }
            }
          ]
        }

        allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

        result = runner.run("Specific request type")

        expect(result.last_agent.name).to eq("SupportAgent")
      end

      it "handles case-insensitive agent names" do
        mock_response = {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "I'll transfer you to targetagent for help."
              }
            }
          ]
        }

        allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

        result = runner.run("Need help")

        expect(result.last_agent.name).to eq("TargetAgent")
      end
    end

    context "with tool-based handoffs" do
      it "processes transfer tool calls" do
        mock_response = {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "I'll help you with that.",
                "tool_calls" => [
                  {
                    "id" => "call_123",
                    "function" => {
                      "name" => "transfer_to_targetagent",
                      "arguments" => "{}"
                    }
                  }
                ]
              }
            }
          ]
        }

        allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

        result = runner.run("Need specialized help")

        expect(result.last_agent.name).to eq("TargetAgent")
      end

      it "handles tool call errors gracefully" do
        mock_response = {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "I'll transfer you.",
                "tool_calls" => [
                  {
                    "id" => "call_456",
                    "function" => {
                      "name" => "transfer_to_nonexistent",
                      "arguments" => "{}"
                    }
                  }
                ]
              }
            }
          ]
        }

        allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

        result = runner.run("Transfer me")

        expect(result.last_agent.name).to eq("SourceAgent") # Should stay with original agent
        expect(result.messages.last[:content]).to include("Error")
      end
    end

    context "with handoff priority" do
      it "prioritizes tool-based handoffs over content-based handoffs" do
        mock_response = {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "I'll transfer you to SupportAgent", # Text-based handoff
                "tool_calls" => [
                  {
                    "id" => "call_123",
                    "function" => {
                      "name" => "transfer_to_targetagent", # Tool-based handoff
                      "arguments" => "{}"
                    }
                  }
                ]
              }
            }
          ]
        }

        allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

        result = runner.run("Need help")

        expect(result.last_agent.name).to eq("TargetAgent") # Tool-based should win
      end

      it "falls back to content-based when no tool handoffs" do
        mock_response = {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "I'll transfer you to SupportAgent",
                "tool_calls" => [
                  {
                    "id" => "call_123",
                    "function" => {
                      "name" => "some_other_tool",
                      "arguments" => "{}"
                    }
                  }
                ]
              }
            }
          ]
        }

        # Mock the tool execution to not return a handoff
        allow(source_agent).to receive(:execute_tool).and_return("Some tool result")

        allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

        result = runner.run("Need help")

        expect(result.last_agent.name).to eq("SupportAgent") # Content-based should work
      end
    end

    context "with multiple handoff detection" do
      it "handles multiple handoff attempts gracefully" do
        mock_response = {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => "Multiple handoffs detected",
                "tool_calls" => [
                  {
                    "id" => "call_1",
                    "function" => {
                      "name" => "transfer_to_targetagent",
                      "arguments" => "{}"
                    }
                  },
                  {
                    "id" => "call_2",
                    "function" => {
                      "name" => "transfer_to_supportagent",
                      "arguments" => "{}"
                    }
                  }
                ]
              }
            }
          ]
        }

        allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

        result = runner.run("Multiple handoffs")

        expect(result.last_agent.name).to eq("SourceAgent") # Should stay with original
        expect(result.messages.last[:content]).to include("Multiple agent handoffs detected")
      end
    end
  end

  describe "Responses API Integration" do
    let(:responses_provider) { OpenAIAgents::Models::ResponsesProvider.new }
    let(:runner) { OpenAIAgents::Runner.new(agent: source_agent, provider: responses_provider) }

    before do
      allow(responses_provider).to receive(:responses_completion).and_return(mock_responses_output)
    end

    context "with function call handoffs" do
      let(:mock_responses_output) do
        {
          "id" => "response_123",
          "output" => [
            {
              "type" => "function_call",
              "name" => "transfer_to_targetagent",
              "arguments" => "{}",
              "call_id" => "call_123"
            }
          ]
        }
      end

      it "processes handoffs in Responses API format" do
        result = runner.run("Need help")

        expect(result.last_agent.name).to eq("TargetAgent")
      end
    end

    context "with message output handoffs" do
      let(:mock_responses_output) do
        {
          "id" => "response_456",
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => [
                {
                  "type" => "text",
                  "text" => '{"response": "I understand", "handoff_to": "SupportAgent"}'
                }
              ]
            }
          ]
        }
      end

      it "processes JSON handoffs in message content" do
        result = runner.run("Technical issue")

        expect(result.last_agent.name).to eq("SupportAgent")
      end
    end
  end

  describe "Error Handling" do
    let(:runner) { OpenAIAgents::Runner.new(agent: source_agent) }
    let(:mock_provider) { instance_double(OpenAIAgents::Models::ResponsesProvider) }

    before do
      allow(runner).to receive(:instance_variable_get).with(:@provider).and_return(mock_provider)
    end

    it "handles malformed JSON gracefully" do
      mock_response = {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => '{"handoff_to": "SupportAgent"' # Missing closing brace
            }
          }
        ]
      }

      allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

      result = runner.run("Test message")

      expect(result.last_agent.name).to eq("SourceAgent") # Should stay with original
    end

    it "handles empty responses gracefully" do
      mock_response = {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => ""
            }
          }
        ]
      }

      allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

      result = runner.run("Test message")

      expect(result.last_agent.name).to eq("SourceAgent")
    end

    it "handles null content gracefully" do
      mock_response = {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => nil
            }
          }
        ]
      }

      allow(mock_provider).to receive(:chat_completion).and_return(mock_response)

      result = runner.run("Test message")

      expect(result.last_agent.name).to eq("SourceAgent")
    end
  end

  describe "Logging and Debugging" do
    let(:runner) { OpenAIAgents::Runner.new(agent: source_agent) }

    it "logs handoff detection events" do
      expect(runner).to receive(:log_debug_handoff).with(
        "JSON handoff detected in agent response",
        hash_including(
          from_agent: "SourceAgent",
          to_agent: "SupportAgent",
          detection_method: "json_field"
        )
      )

      content = '{"handoff_to": "SupportAgent"}'
      runner.send(:detect_handoff_in_content, content, source_agent)
    end

    it "logs text handoff detection events" do
      expect(runner).to receive(:log_debug_handoff).with(
        "Text handoff detected in agent response",
        hash_including(
          from_agent: "SourceAgent",
          to_agent: "SupportAgent",
          detection_method: "text_pattern"
        )
      )

      content = "I'll transfer you to the SupportAgent."
      runner.send(:detect_handoff_in_content, content, source_agent)
    end
  end
end
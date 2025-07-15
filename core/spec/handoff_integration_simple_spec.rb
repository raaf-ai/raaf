# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Simple Handoff Integration Tests" do
  let(:source_agent) { OpenAIAgents::Agent.new(name: "SourceAgent", instructions: "You are a source agent") }
  let(:target_agent) { OpenAIAgents::Agent.new(name: "TargetAgent", instructions: "You are a target agent") }
  let(:support_agent) { OpenAIAgents::Agent.new(name: "SupportAgent", instructions: "You are a support agent") }

  before do
    source_agent.add_handoff(target_agent)
    source_agent.add_handoff(support_agent)
  end

  describe "Direct Response Processing" do
    let(:runner) { OpenAIAgents::Runner.new(agent: source_agent) }

    it "processes JSON handoffs in responses" do
      mock_response = {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => '{"response": "I understand", "handoff_to": "SupportAgent"}'
            }
          }
        ]
      }

      result = runner.send(:process_response, mock_response, source_agent, [])
      
      expect(result[:handoff]).to eq("SupportAgent")
      expect(result[:done]).to be false
    end

    it "processes text-based handoffs in responses" do
      mock_response = {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "I'll transfer you to the SupportAgent for assistance."
            }
          }
        ]
      }

      result = runner.send(:process_response, mock_response, source_agent, [])
      
      expect(result[:handoff]).to eq("SupportAgent")
      expect(result[:done]).to be false
    end

    it "processes tool-based handoffs in responses" do
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

      # Mock tool processing to return handoff
      allow(runner).to receive(:process_tool_calls).and_return("TargetAgent")

      result = runner.send(:process_response, mock_response, source_agent, [])
      
      expect(result[:handoff]).to eq("TargetAgent")
      expect(result[:done]).to be false
    end

    it "ignores handoffs to non-existent agents" do
      mock_response = {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => '{"handoff_to": "CompletelyUnknownAgent"}'
            }
          }
        ]
      }

      result = runner.send(:process_response, mock_response, source_agent, [])
      
      expect(result[:handoff]).to be_nil
      expect(result[:done]).to be true
    end

    it "prioritizes tool-based handoffs over content-based handoffs" do
      mock_response = {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => "I'll transfer you to SupportAgent", # Text handoff
              "tool_calls" => [
                {
                  "id" => "call_123",
                  "function" => {
                    "name" => "transfer_to_targetagent", # Tool handoff
                    "arguments" => "{}"
                  }
                }
              ]
            }
          }
        ]
      }

      # Mock tool processing to return handoff
      allow(runner).to receive(:process_tool_calls).and_return("TargetAgent")

      result = runner.send(:process_response, mock_response, source_agent, [])
      
      expect(result[:handoff]).to eq("TargetAgent") # Tool-based should win
    end

    it "falls back to content-based handoffs when no tool handoffs" do
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

      # Mock tool processing to not return handoff
      allow(runner).to receive(:process_tool_calls).and_return(false)

      result = runner.send(:process_response, mock_response, source_agent, [])
      
      expect(result[:handoff]).to eq("SupportAgent") # Content-based should work
    end

    it "handles multiple handoff detection gracefully" do
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

      # Mock tool processing to return false for multiple handoffs
      allow(runner).to receive(:process_tool_calls).and_return(false)

      result = runner.send(:process_response, mock_response, source_agent, [])
      
      expect(result[:handoff]).to be_nil # Should not handoff
    end
  end

  describe "Responses API Integration" do
    let(:runner) { OpenAIAgents::Runner.new(agent: source_agent) }

    it "processes function call handoffs in Responses API format" do
      response = {
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

      generated_items = []
      result = runner.send(:process_responses_api_output, response, source_agent, generated_items)
      
      expect(result[:handoff]).to include(:assistant => "TargetAgent")
    end

    it "processes message handoffs in Responses API format" do
      response = {
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

      generated_items = []
      result = runner.send(:process_responses_api_output, response, source_agent, generated_items)
      
      # The message should be processed and handoff detected in the unified system
      expect(generated_items.size).to eq(1)
      expect(generated_items.first).to be_a(OpenAIAgents::Items::MessageOutputItem)
    end
  end

  describe "Error Handling" do
    let(:runner) { OpenAIAgents::Runner.new(agent: source_agent) }

    it "handles malformed JSON gracefully" do
      mock_response = {
        "choices" => [
          {
            "message" => {
              "role" => "assistant",
              "content" => '{"handoff_to": "NonExistentAgent"' # Missing closing brace, invalid agent
            }
          }
        ]
      }

      result = runner.send(:process_response, mock_response, source_agent, [])
      
      expect(result[:handoff]).to be_nil
      expect(result[:done]).to be true
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

      result = runner.send(:process_response, mock_response, source_agent, [])
      
      expect(result[:handoff]).to be_nil
      expect(result[:done]).to be true
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

      result = runner.send(:process_response, mock_response, source_agent, [])
      
      expect(result[:handoff]).to be_nil
      expect(result[:done]).to be true
    end

    it "handles missing message gracefully" do
      mock_response = {
        "choices" => [
          {
            "message" => nil
          }
        ]
      }

      result = runner.send(:process_response, mock_response, source_agent, [])
      
      expect(result[:handoff]).to be_nil
      expect(result[:done]).to be true
    end
  end

  describe "Handoff Detection Priority" do
    let(:runner) { OpenAIAgents::Runner.new(agent: source_agent) }

    it "processes handoffs in correct order: JSON > text" do
      # This test verifies that the detection system works in the right priority order
      
      # First, test that JSON detection works alone
      json_only_content = '{"handoff_to": "SupportAgent"}'
      result = runner.send(:detect_handoff_in_content, json_only_content, source_agent)
      expect(result).to eq("SupportAgent")
      
      # Then test that text detection works alone
      text_only_content = "I will transfer you to TargetAgent."
      result = runner.send(:detect_handoff_in_content, text_only_content, source_agent)
      expect(result).to eq("TargetAgent")
      
      # Test that JSON takes priority with valid JSON containing both handoff types
      mixed_json_content = '{"handoff_to": "SupportAgent", "message": "I will transfer you to TargetAgent"}'
      result = runner.send(:detect_handoff_in_content, mixed_json_content, source_agent)
      expect(result).to eq("SupportAgent") # JSON should win
      
      # Test that text detection works when JSON parsing fails
      invalid_json_content = '{"handoff_to": "SupportAgent" invalid json, but I will transfer you to TargetAgent.'
      result = runner.send(:detect_handoff_in_content, invalid_json_content, source_agent)
      expect(result).to eq("TargetAgent") # Text detection should work as fallback
    end
  end
end
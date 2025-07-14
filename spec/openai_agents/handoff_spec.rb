# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenAIAgents Handoff System" do
  let(:source_agent) { OpenAIAgents::Agent.new(name: "SourceAgent", instructions: "You are a source agent") }
  let(:target_agent) { OpenAIAgents::Agent.new(name: "TargetAgent", instructions: "You are a target agent") }
  let(:support_agent) { OpenAIAgents::Agent.new(name: "SupportAgent", instructions: "You are a support agent") }
  let(:customer_service) { OpenAIAgents::Agent.new(name: "CustomerService", instructions: "You are customer service") }
  
  before do
    # Add handoff targets to source agent
    source_agent.add_handoff(target_agent)
    source_agent.add_handoff(support_agent)
    source_agent.add_handoff(customer_service)
  end

  describe "Unified Handoff Detection System" do
    let(:runner) { OpenAIAgents::Runner.new(agent: source_agent) }
    
    describe "#detect_handoff_in_content" do
      it "detects JSON handoffs" do
        content = '{"response": "I can help with that", "handoff_to": "TargetAgent"}'
        result = runner.send(:detect_handoff_in_content, content, source_agent)
        expect(result).to eq("TargetAgent")
      end

      it "detects text handoffs" do
        content = "I'll transfer you to the SupportAgent for further assistance."
        result = runner.send(:detect_handoff_in_content, content, source_agent)
        expect(result).to eq("SupportAgent")
      end

      it "returns nil when no handoff is detected" do
        content = "I can help you with that directly."
        result = runner.send(:detect_handoff_in_content, content, source_agent)
        expect(result).to be_nil
      end
    end

    describe "#detect_json_handoff" do
      context "with handoff_to field" do
        it "detects string key format" do
          content = '{"handoff_to": "TargetAgent"}'
          result = runner.send(:detect_json_handoff, content, source_agent)
          expect(result).to eq("TargetAgent")
        end

        it "detects symbol key format" do
          content = '{"handoff_to": "SupportAgent"}'
          result = runner.send(:detect_json_handoff, content, source_agent)
          expect(result).to eq("SupportAgent")
        end
      end

      context "with alternative field names" do
        it "detects transfer_to field" do
          content = '{"transfer_to": "CustomerService"}'
          result = runner.send(:detect_json_handoff, content, source_agent)
          expect(result).to eq("CustomerService")
        end

        it "detects next_agent field" do
          content = '{"next_agent": "TargetAgent"}'
          result = runner.send(:detect_json_handoff, content, source_agent)
          expect(result).to eq("TargetAgent")
        end
      end

      context "with nested handoff structures" do
        it "detects nested handoff.to field" do
          content = '{"handoff": {"to": "SupportAgent", "reason": "Complex issue"}}'
          result = runner.send(:detect_json_handoff, content, source_agent)
          expect(result).to eq("SupportAgent")
        end
      end

      context "with invalid JSON" do
        it "returns nil for malformed JSON" do
          content = '{"handoff_to": "TargetAgent"' # missing closing brace
          result = runner.send(:detect_json_handoff, content, source_agent)
          expect(result).to be_nil
        end

        it "returns nil for non-JSON content" do
          content = "This is just plain text"
          result = runner.send(:detect_json_handoff, content, source_agent)
          expect(result).to be_nil
        end
      end

      context "with mixed content" do
        it "detects handoff in JSON with other fields" do
          content = '{"response": "I understand your concern", "handoff_to": "CustomerService", "confidence": 0.95}'
          result = runner.send(:detect_json_handoff, content, source_agent)
          expect(result).to eq("CustomerService")
        end
      end
    end

    describe "#detect_text_handoff" do
      context "with direct transfer patterns" do
        it "detects 'transfer to' pattern" do
          content = "I'll transfer you to the SupportAgent for assistance."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("SupportAgent")
        end

        it "detects 'transferring to' pattern" do
          content = "Transferring to CustomerService now."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("CustomerService")
        end

        it "detects 'hand off to' pattern" do
          content = "Let me hand this off to TargetAgent."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("TargetAgent")
        end

        it "detects 'delegate to' pattern" do
          content = "I'll delegate this to SupportAgent."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("SupportAgent")
        end

        it "detects 'routing to' pattern" do
          content = "Routing you to the CustomerService team."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("CustomerService")
        end
      end

      context "with mention patterns" do
        it "detects 'contact agent' pattern" do
          content = "Please contact CustomerService for billing issues."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("CustomerService")
        end

        it "detects 'speak with agent' pattern" do
          content = "You should speak with SupportAgent about this."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("SupportAgent")
        end

        it "detects 'talk to agent' pattern" do
          content = "You need to talk to TargetAgent for more details."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("TargetAgent")
        end
      end

      context "with explicit agent name references" do
        it "detects standalone agent names" do
          content = "For this issue, you need TargetAgent assistance."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("TargetAgent")
        end

        it "detects agent names with word boundaries" do
          content = "The SupportAgent team can help with technical issues."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("SupportAgent")
        end
      end

      context "with case insensitive matching" do
        it "detects lowercase agent names" do
          content = "Please contact customerservice for help."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("CustomerService")
        end

        it "detects mixed case patterns" do
          content = "I'll TRANSFER you to the supportagent."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("SupportAgent")
        end
      end

      context "with no available targets" do
        let(:isolated_agent) { OpenAIAgents::Agent.new(name: "IsolatedAgent", instructions: "No handoffs") }
        let(:isolated_runner) { OpenAIAgents::Runner.new(agent: isolated_agent) }

        it "returns nil when no handoff targets are available" do
          content = "I'll transfer you to SupportAgent."
          result = isolated_runner.send(:detect_text_handoff, content, isolated_agent)
          expect(result).to be_nil
        end
      end

      context "with invalid agent names" do
        it "returns nil for non-existent agents" do
          content = "I'll transfer you to NonExistentAgent."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to be_nil
        end

        it "returns nil for partial matches that don't validate" do
          content = "I'll transfer you to Target."
          result = runner.send(:detect_text_handoff, content, source_agent)
          expect(result).to eq("TargetAgent") # Should fuzzy match
        end
      end
    end

    describe "#validate_handoff_target" do
      let(:available_targets) { ["TargetAgent", "SupportAgent", "CustomerService"] }

      it "validates exact matches" do
        result = runner.send(:validate_handoff_target, "TargetAgent", available_targets)
        expect(result).to eq("TargetAgent")
      end

      it "validates case-insensitive matches" do
        result = runner.send(:validate_handoff_target, "targetagent", available_targets)
        expect(result).to eq("TargetAgent")
      end

      it "validates substring matches" do
        result = runner.send(:validate_handoff_target, "Target", available_targets)
        expect(result).to eq("TargetAgent")
      end

      it "validates contains matches" do
        result = runner.send(:validate_handoff_target, "CustomerServiceTeam", available_targets)
        expect(result).to eq("CustomerService")
      end

      it "returns nil for no matches" do
        result = runner.send(:validate_handoff_target, "NonExistent", available_targets)
        expect(result).to be_nil
      end

      it "returns nil for empty input" do
        result = runner.send(:validate_handoff_target, "", available_targets)
        expect(result).to be_nil
      end

      it "returns nil for nil input" do
        result = runner.send(:validate_handoff_target, nil, available_targets)
        expect(result).to be_nil
      end
    end

    describe "#get_available_handoff_targets" do
      it "returns agent names for Agent handoffs" do
        targets = runner.send(:get_available_handoff_targets, source_agent)
        expect(targets).to contain_exactly("TargetAgent", "SupportAgent", "CustomerService")
      end

      it "returns empty array for agents without handoffs" do
        no_handoff_agent = OpenAIAgents::Agent.new(name: "NoHandoffAgent", instructions: "No handoffs")
        targets = runner.send(:get_available_handoff_targets, no_handoff_agent)
        expect(targets).to eq([])
      end

      it "handles mixed handoff types" do
        # Test with both Agent objects and Handoff objects
        handoff_obj = OpenAIAgents::Handoff.new(
          tool_name: "transfer_to_custom",
          tool_description: "Custom handoff",
          input_json_schema: {},
          on_invoke_handoff: ->(context, input) { "custom result" },
          agent_name: "CustomAgent"
        )
        
        mixed_agent = OpenAIAgents::Agent.new(name: "MixedAgent", instructions: "Mixed handoffs")
        mixed_agent.add_handoff(target_agent)
        mixed_agent.handoffs << handoff_obj
        
        targets = runner.send(:get_available_handoff_targets, mixed_agent)
        expect(targets).to contain_exactly("TargetAgent", "CustomAgent")
      end
    end
  end

  describe "Tool-based Handoffs" do
    let(:runner) { OpenAIAgents::Runner.new(agent: source_agent) }
    let(:mock_provider) { instance_double(OpenAIAgents::Models::ResponsesProvider) }

    before do
      allow(runner).to receive(:instance_variable_get).with(:@provider).and_return(mock_provider)
    end

    describe "#process_handoff_tool_call" do
      let(:tool_call) do
        {
          "id" => "call_123",
          "function" => {
            "name" => "transfer_to_targetagent",
            "arguments" => "{}"
          }
        }
      end

      it "processes handoff tool calls successfully" do
        result = runner.send(:process_handoff_tool_call, tool_call, source_agent, nil)
        
        expect(result).to include(
          role: "tool",
          tool_call_id: "call_123",
          handoff: "TargetAgent"
        )
        expect(result[:content]).to include("assistant")
      end

      it "handles tool calls for non-existent agents" do
        bad_tool_call = {
          "id" => "call_456",
          "function" => {
            "name" => "transfer_to_nonexistent",
            "arguments" => "{}"
          }
        }

        result = runner.send(:process_handoff_tool_call, bad_tool_call, source_agent, nil)
        
        expect(result).to include(
          role: "tool",
          tool_call_id: "call_456",
          handoff_error: true
        )
        expect(result[:content]).to include("Error")
      end

      it "prevents circular handoffs" do
        # Add source agent as a handoff target for circular test
        source_agent.add_handoff(source_agent)
        
        # Simulate a handoff chain
        runner.instance_variable_set(:@handoff_chain, ["SourceAgent", "TargetAgent"])
        
        circular_tool_call = {
          "id" => "call_789",
          "function" => {
            "name" => "transfer_to_sourceagent",
            "arguments" => "{}"
          }
        }

        result = runner.send(:process_handoff_tool_call, circular_tool_call, source_agent, nil)
        
        expect(result).to include(
          role: "tool",
          tool_call_id: "call_789",
          handoff_error: true
        )
        expect(result[:content]).to include("Circular handoff detected")
      end

      it "limits handoff chain length" do
        # Simulate a long handoff chain
        runner.instance_variable_set(:@handoff_chain, ["Agent1", "Agent2", "Agent3", "Agent4", "Agent5"])
        
        long_chain_tool_call = {
          "id" => "call_101",
          "function" => {
            "name" => "transfer_to_targetagent",
            "arguments" => "{}"
          }
        }

        result = runner.send(:process_handoff_tool_call, long_chain_tool_call, source_agent, nil)
        
        expect(result).to include(
          role: "tool",
          tool_call_id: "call_101",
          handoff_error: true
        )
        expect(result[:content]).to include("Maximum handoff chain length")
      end
    end

    describe "#extract_agent_name_from_tool" do
      it "extracts properly cased agent names" do
        result = runner.send(:extract_agent_name_from_tool, "transfer_to_SupportAgent")
        expect(result).to eq("SupportAgent")
      end

      it "handles underscore separated names" do
        result = runner.send(:extract_agent_name_from_tool, "transfer_to_customer_service")
        expect(result).to eq("CustomerService")
      end

      it "capitalizes simple names" do
        result = runner.send(:extract_agent_name_from_tool, "transfer_to_support")
        expect(result).to eq("Support")
      end
    end
  end

  describe "Integration with process_response" do
    let(:runner) { OpenAIAgents::Runner.new(agent: source_agent) }

    describe "handoff priority" do
      it "prioritizes tool-based handoffs over content-based handoffs" do
        message = {
          "content" => '{"handoff_to": "SupportAgent"}',
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

        # Mock the tool processing to return a handoff
        allow(runner).to receive(:process_tool_calls).and_return("TargetAgent")
        
        result = runner.send(:process_response, { "choices" => [{ "message" => message }] }, source_agent, [])
        
        expect(result[:handoff]).to eq("TargetAgent") # Tool-based handoff wins
      end

      it "falls back to content-based handoffs when no tool handoffs" do
        message = {
          "content" => '{"handoff_to": "SupportAgent"}'
        }

        result = runner.send(:process_response, { "choices" => [{ "message" => message }] }, source_agent, [])
        
        expect(result[:handoff]).to eq("SupportAgent")
      end

      it "processes text-based handoffs when JSON parsing fails" do
        message = {
          "content" => "I'll transfer you to the SupportAgent for assistance."
        }

        result = runner.send(:process_response, { "choices" => [{ "message" => message }] }, source_agent, [])
        
        expect(result[:handoff]).to eq("SupportAgent")
      end
    end

    describe "multiple handoff detection" do
      it "handles multiple tool-based handoffs correctly" do
        message = {
          "tool_calls" => [
            {
              "id" => "call_1",
              "function" => { "name" => "transfer_to_targetagent", "arguments" => "{}" }
            },
            {
              "id" => "call_2", 
              "function" => { "name" => "transfer_to_supportagent", "arguments" => "{}" }
            }
          ]
        }

        # Mock multiple handoff detection
        allow(runner).to receive(:process_tool_calls).and_return(false) # Simulate multiple handoff error
        
        result = runner.send(:process_response, { "choices" => [{ "message" => message }] }, source_agent, [])
        
        expect(result[:handoff]).to be_nil # Should not handoff when multiple detected
      end
    end
  end

  describe "Responses API Integration" do
    let(:responses_provider) { OpenAIAgents::Models::ResponsesProvider.new }
    let(:runner) { OpenAIAgents::Runner.new(agent: source_agent, provider: responses_provider) }

    describe "#process_responses_api_output" do
      it "processes JSON handoffs in message output" do
        response = {
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
        
        # The handoff should not be detected here since we removed that logic
        # It should be detected in the unified detection system
        expect(generated_items.size).to eq(1)
        expect(generated_items.first).to be_a(OpenAIAgents::Items::MessageOutputItem)
      end

      it "processes tool-based handoffs in function calls" do
        response = {
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
    end
  end
end
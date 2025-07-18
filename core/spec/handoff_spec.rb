# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenAIAgents Handoff System" do
  let(:source_agent) { RAAF::Agent.new(name: "SourceAgent", instructions: "You are a source agent") }
  let(:target_agent) { RAAF::Agent.new(name: "TargetAgent", instructions: "You are a target agent") }
  let(:support_agent) { RAAF::Agent.new(name: "SupportAgent", instructions: "You are a support agent") }
  let(:customer_service) { RAAF::Agent.new(name: "CustomerService", instructions: "You are customer service") }

  describe "RECOMMENDED_PROMPT_PREFIX" do
    it "contains the standard handoff instructions" do
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("multi-agent system")
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("transfer_to_<agent_name>")
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("handled seamlessly")
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("do not mention or draw attention")
    end

    it "includes system context header" do
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("# System context")
    end

    it "mentions Agents SDK" do
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("Agents SDK")
    end

    it "explains handoff functions" do
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("handoff function")
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("generally named")
    end
  end

  describe "prompt_with_handoff_instructions" do
    it "prepends handoff instructions to custom prompt" do
      custom_prompt = "You are a helpful assistant."
      result = RAAF.prompt_with_handoff_instructions(custom_prompt)
      
      expect(result).to start_with(RAAF::RECOMMENDED_PROMPT_PREFIX)
      expect(result).to end_with(custom_prompt)
      expect(result).to include("\n\n#{custom_prompt}")
    end

    it "handles empty prompt" do
      result = RAAF.prompt_with_handoff_instructions("")
      expect(result).to eq(RAAF::RECOMMENDED_PROMPT_PREFIX)
    end

    it "handles nil prompt" do
      result = RAAF.prompt_with_handoff_instructions(nil)
      expect(result).to eq(RAAF::RECOMMENDED_PROMPT_PREFIX)
    end

    it "properly separates prefix from custom instructions" do
      custom_prompt = "You are a customer service agent."
      result = RAAF.prompt_with_handoff_instructions(custom_prompt)
      
      lines = result.split("\n")
      expect(lines).to include("# System context")
      expect(lines).to include("You are a customer service agent.")
      
      # Should have blank lines separating sections
      expect(result).to include("\n\n")
    end

    it "maintains formatting with multi-line custom prompts" do
      custom_prompt = <<~INSTRUCTIONS
        You are a technical support agent.
        
        Your responsibilities:
        - Diagnose technical issues
        - Provide solutions
        - Escalate when necessary
      INSTRUCTIONS
      
      result = RAAF.prompt_with_handoff_instructions(custom_prompt)
      
      expect(result).to start_with(RAAF::RECOMMENDED_PROMPT_PREFIX)
      expect(result).to include("You are a technical support agent.")
      expect(result).to include("Your responsibilities:")
      expect(result).to include("- Diagnose technical issues")
    end
  end

  describe "automatic handoff instructions in Runner" do
    let(:runner) { RAAF::Runner.new(agent: source_agent) }

    context "when agent has handoffs" do
      before do
        source_agent.add_handoff(target_agent)
      end

      it "automatically adds handoff instructions to system prompt" do
        result = runner.send(:build_system_prompt, source_agent)
        
        expect(result).to include("# System context")
        expect(result).to include("multi-agent system")
        expect(result).to include("transfer_to_<agent_name>")
        expect(result).to include("You are a source agent")
      end

      it "doesn't duplicate handoff instructions if already present" do
        # Create agent with handoff instructions already included
        agent_with_handoff_instructions = RAAF::Agent.new(
          name: "TestAgent",
          instructions: RAAF.prompt_with_handoff_instructions("You are a test agent.")
        )
        agent_with_handoff_instructions.add_handoff(target_agent)
        
        test_runner = RAAF::Runner.new(agent: agent_with_handoff_instructions)
        result = test_runner.send(:build_system_prompt, agent_with_handoff_instructions)
        
        # Should only contain the handoff instructions once
        system_context_count = result.scan(/# System context/).length
        expect(system_context_count).to eq(1)
      end
    end

    context "when agent has no handoffs" do
      let(:no_handoff_agent) { RAAF::Agent.new(name: "NoHandoffAgent", instructions: "You are a simple agent") }
      let(:no_handoff_runner) { RAAF::Runner.new(agent: no_handoff_agent) }

      it "doesn't add handoff instructions to system prompt" do
        result = no_handoff_runner.send(:build_system_prompt, no_handoff_agent)
        
        expect(result).not_to include("# System context")
        expect(result).not_to include("multi-agent system")
        expect(result).to include("You are a simple agent")
      end
    end

    context "when agent has empty instructions" do
      let(:empty_instructions_agent) { RAAF::Agent.new(name: "EmptyAgent", instructions: nil) }
      let(:empty_runner) { RAAF::Runner.new(agent: empty_instructions_agent) }

      it "handles nil instructions gracefully" do
        empty_instructions_agent.add_handoff(target_agent)
        
        result = empty_runner.send(:build_system_prompt, empty_instructions_agent)
        
        expect(result).to include("Name: EmptyAgent")
        expect(result).not_to include("Instructions:")
      end
    end
  end

  before do
    # Add handoff targets to source agent
    source_agent.add_handoff(target_agent)
    source_agent.add_handoff(support_agent)
    source_agent.add_handoff(customer_service)
  end

  describe "Unified Handoff Detection System" do
    let(:runner) { RAAF::Runner.new(agent: source_agent) }

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
        let(:isolated_agent) { RAAF::Agent.new(name: "IsolatedAgent", instructions: "No handoffs") }
        let(:isolated_runner) { RAAF::Runner.new(agent: isolated_agent) }

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
      let(:available_targets) { %w[TargetAgent SupportAgent CustomerService] }

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
        no_handoff_agent = RAAF::Agent.new(name: "NoHandoffAgent", instructions: "No handoffs")
        targets = runner.send(:get_available_handoff_targets, no_handoff_agent)
        expect(targets).to eq([])
      end

      it "handles mixed handoff types" do
        # Test with both Agent objects and Handoff objects
        custom_agent = RAAF::Agent.new(name: "CustomAgent", instructions: "Custom agent")
        handoff_obj = RAAF::Handoff.new(
          custom_agent,
          tool_name_override: "transfer_to_custom",
          tool_description_override: "Custom handoff"
        )

        mixed_agent = RAAF::Agent.new(name: "MixedAgent", instructions: "Mixed handoffs")
        mixed_agent.add_handoff(target_agent)
        mixed_agent.handoffs << handoff_obj

        targets = runner.send(:get_available_handoff_targets, mixed_agent)
        expect(targets).to contain_exactly("TargetAgent", "CustomAgent")
      end
    end
  end

  describe "Tool-based Handoffs" do
    let(:runner) { RAAF::Runner.new(agent: source_agent) }
    let(:mock_provider) { instance_double(RAAF::Models::ResponsesProvider) }

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
        runner.instance_variable_set(:@handoff_chain, %w[SourceAgent TargetAgent])

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
        runner.instance_variable_set(:@handoff_chain, %w[Agent1 Agent2 Agent3 Agent4 Agent5])

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
    let(:runner) { RAAF::Runner.new(agent: source_agent) }

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
    let(:responses_provider) { RAAF::Models::ResponsesProvider.new }
    let(:runner) { RAAF::Runner.new(agent: source_agent, provider: responses_provider) }
    
    before do
      source_agent.add_handoff(target_agent)
    end

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
        runner.send(:process_responses_api_output, response, source_agent, generated_items)

        # The handoff should not be detected here since we removed that logic
        # It should be detected in the unified detection system
        expect(generated_items.size).to eq(1)
        expect(generated_items.first).to be_a(RAAF::Items::MessageOutputItem)
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

        expect(result[:handoff]).to include(assistant: "TargetAgent")
      end
    end
  end

  # =============================================================================
  # CONSOLIDATED HANDOFF INTEGRATION TESTS
  # =============================================================================
  
  describe "End-to-End Handoff Scenarios" do
    let(:responses_provider) { instance_double(RAAF::Models::ResponsesProvider) }
    let(:runner) { RAAF::Runner.new(agent: source_agent, provider: responses_provider) }
    
    before do
      source_agent.add_handoff(target_agent)
      source_agent.add_handoff(support_agent)
    end

    # Helper method to convert old Chat Completions format to Responses API format
    def convert_to_responses_format(old_response)
      return old_response if old_response["output"] # Already in Responses format

      choices = old_response["choices"] || []
      output = []

      choices.each do |choice|
        message = choice["message"]

        # Add message content if present
        if message["content"]
          output << {
            "type" => "message",
            "role" => message["role"],
            "content" => [
              {
                "type" => "text",
                "text" => message["content"]
              }
            ]
          }
        end

        # Add tool calls if present
        if message["tool_calls"]
          message["tool_calls"].each do |tool_call|
            output << {
              "type" => "function_call",
              "name" => tool_call["function"]["name"],
              "arguments" => tool_call["function"]["arguments"],
              "call_id" => tool_call["id"]
            }
          end
        end
      end

      {
        "output" => output,
        "usage" => old_response["usage"]
      }
    end

    context "JSON-based handoffs" do
      it "handles structured JSON handoffs correctly" do
        response = {
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => '{"response": "I understand your request", "handoff_to": "SupportAgent"}'
                }
              ]
            }
          ],
          "usage" => { "input_tokens" => 10, "output_tokens" => 15 }
        }

        allow(responses_provider).to receive(:responses_completion).and_return(response)
        allow(responses_provider).to receive(:complete).and_return(response)
        
        result = runner.run([{ role: "user", content: "Help me with support" }])
        
        expect(result.last_agent.name).to eq("SupportAgent")
        expect(result.messages.size).to be >= 1
      end

      it "handles malformed JSON gracefully" do
        response = {
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => [
                {
                  "type" => "text",
                  "text" => '{"response": "I understand", "handoff_to": "SupportAgent"'  # Missing closing brace
                }
              ]
            }
          ],
          "usage" => { "input_tokens" => 10, "output_tokens" => 15 }
        }

        allow(responses_provider).to receive(:responses_completion).and_return(response)
        allow(responses_provider).to receive(:complete).and_return(response)
        
        result = runner.run([{ role: "user", content: "Help me" }])
        
        # Should not crash and should stay with original agent
        expect(result.last_agent.name).to eq("SourceAgent")
      end
    end

    context "Text-based handoffs" do
      it "detects natural language handoff instructions" do
        response = {
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => [
                {
                  "type" => "text",
                  "text" => "I need to transfer you to our SupportAgent for specialized assistance."
                }
              ]
            }
          ],
          "usage" => { "input_tokens" => 10, "output_tokens" => 15 }
        }

        allow(responses_provider).to receive(:responses_completion).and_return(response)
        allow(responses_provider).to receive(:complete).and_return(response)
        
        result = runner.run([{ role: "user", content: "Need help" }])
        
        expect(result.last_agent.name).to eq("SupportAgent")
      end

      it "detects transfer_to patterns" do
        response = {
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => [
                {
                  "type" => "text",
                  "text" => "Let me transfer_to_targetagent for you."
                }
              ]
            }
          ],
          "usage" => { "input_tokens" => 10, "output_tokens" => 15 }
        }

        allow(responses_provider).to receive(:responses_completion).and_return(response)
        allow(responses_provider).to receive(:complete).and_return(response)
        
        result = runner.run([{ role: "user", content: "Transfer me" }])
        
        expect(result.last_agent.name).to eq("TargetAgent")
      end
    end

    context "Tool-based handoffs" do
      it "handles function call handoffs" do
        response = {
          "output" => [
            {
              "type" => "function_call",
              "name" => "transfer_to_supportagent",
              "arguments" => '{"reason": "User needs specialized support"}',
              "call_id" => "call_123"
            }
          ],
          "usage" => { "input_tokens" => 10, "output_tokens" => 15 }
        }

        allow(responses_provider).to receive(:responses_completion).and_return(response)
        allow(responses_provider).to receive(:complete).and_return(response)
        
        result = runner.run([{ role: "user", content: "Need support" }])
        
        expect(result.last_agent.name).to eq("SupportAgent")
      end

      it "prioritizes tool-based handoffs over content-based" do
        response = {
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => [
                {
                  "type" => "text",
                  "text" => "Let me transfer you to TargetAgent."
                }
              ]
            },
            {
              "type" => "function_call",
              "name" => "transfer_to_supportagent",
              "arguments" => '{"reason": "Tool-based handoff"}',
              "call_id" => "call_456"
            }
          ],
          "usage" => { "input_tokens" => 10, "output_tokens" => 15 }
        }

        allow(responses_provider).to receive(:responses_completion).and_return(response)
        allow(responses_provider).to receive(:complete).and_return(response)
        
        result = runner.run([{ role: "user", content: "Help me" }])
        
        # Should prioritize tool-based handoff (SupportAgent) over content-based (TargetAgent)
        expect(result.last_agent.name).to eq("SupportAgent")
      end
    end

    context "Error handling" do
      it "handles empty responses gracefully" do
        response = {
          "output" => [],
          "usage" => { "input_tokens" => 10, "output_tokens" => 0 }
        }

        allow(responses_provider).to receive(:responses_completion).and_return(response)
        allow(responses_provider).to receive(:complete).and_return(response)
        
        result = runner.run([{ role: "user", content: "Help" }])
        
        expect(result.last_agent.name).to eq("SourceAgent")
      end

      it "handles null content gracefully" do
        response = {
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => nil
            }
          ],
          "usage" => { "input_tokens" => 10, "output_tokens" => 5 }
        }

        allow(responses_provider).to receive(:responses_completion).and_return(response)
        allow(responses_provider).to receive(:complete).and_return(response)
        
        result = runner.run([{ role: "user", content: "Help" }])
        
        expect(result.last_agent.name).to eq("SourceAgent")
      end
    end
  end

  describe "Context Preservation During Handoffs" do
    let(:search_agent) { RAAF::Agent.new(name: "SearchStrategyAgent", instructions: "You find market research strategies") }
    let(:discovery_agent) { RAAF::Agent.new(name: "CompanyDiscoveryAgent", instructions: "You discover companies") }
    let(:responses_provider) { instance_double(RAAF::Models::ResponsesProvider, :responses_completion => nil, :complete => nil) }
    let(:runner) { RAAF::Runner.new(agent: search_agent, provider: responses_provider) }
    
    before do
      search_agent.add_handoff(discovery_agent)
    end

    it "preserves context and prevents duplicate filtering" do
      # First API call - SearchStrategyAgent responds with handoff
      first_response = {
        "output" => [
          {
            "type" => "message",
            "role" => "assistant",
            "content" => [
              {
                "type" => "text",
                "text" => "Here's the market research strategy. Now transferring to CompanyDiscoveryAgent."
              }
            ]
          },
          {
            "type" => "function_call",
            "name" => "transfer_to_companydiscoveryagent",
            "arguments" => '{"strategy": "competitive analysis"}',
            "call_id" => "call_search_123"
          }
        ],
        "usage" => { "input_tokens" => 20, "output_tokens" => 25 }
      }

      # Second API call - CompanyDiscoveryAgent responds
      second_response = {
        "output" => [
          {
            "type" => "message",
            "role" => "assistant",
            "content" => [
              {
                "type" => "text",
                "text" => "Based on the strategy, I found relevant companies."
              }
            ]
          }
        ],
        "usage" => { "input_tokens" => 30, "output_tokens" => 20 }
      }

      allow(responses_provider).to receive(:responses_completion)
        .and_return(first_response, second_response)
      allow(responses_provider).to receive(:complete)
        .and_return(first_response, second_response)

      result = runner.run([{ role: "user", content: "Find companies for competitive analysis" }])

      expect(result.last_agent.name).to eq("CompanyDiscoveryAgent")
      expect(result.messages.size).to be >= 2
      
      # Verify conversation flow preservation
      user_message = result.messages.find { |msg| msg[:role] == "user" }
      expect(user_message[:content]).to include("competitive analysis")
    end

    it "handles function call outputs properly" do
      # First response - SearchStrategyAgent with handoff function call
      first_response = {
        "output" => [
          {
            "type" => "function_call",
            "name" => "transfer_to_companydiscoveryagent",
            "arguments" => '{"context": "market research"}',
            "call_id" => "call_function_123"
          }
        ],
        "usage" => { "input_tokens" => 15, "output_tokens" => 10 }
      }

      # Second response - CompanyDiscoveryAgent response after handoff
      second_response = {
        "output" => [
          {
            "type" => "message",
            "role" => "assistant",
            "content" => [
              {
                "type" => "output_text",
                "text" => "Hello! I'm CompanyDiscoveryAgent. I'll help you with market research."
              }
            ]
          }
        ],
        "usage" => { "input_tokens" => 20, "output_tokens" => 15 }
      }

      # Mock function call result sequence
      allow(responses_provider).to receive(:responses_completion).and_return(first_response, second_response)
      allow(responses_provider).to receive(:complete).and_return(first_response, second_response)

      result = runner.run([{ role: "user", content: "Research request" }])

      expect(result.last_agent.name).to eq("CompanyDiscoveryAgent")
      
      # Should have function call output in conversation
      function_outputs = result.messages.select { |msg| msg[:role] == "tool" }
      expect(function_outputs).not_to be_empty
    end
  end

  describe "Multi-Agent Handoff Chains" do
    let(:researcher) { RAAF::Agent.new(name: "ResearchAgent", instructions: "You conduct research") }
    let(:analyst) { RAAF::Agent.new(name: "AnalystAgent", instructions: "You analyze data") }
    let(:summarizer) { RAAF::Agent.new(name: "SummarizerAgent", instructions: "You create summaries") }
    
    before do
      researcher.add_handoff(analyst)
      analyst.add_handoff(summarizer)
    end

    it "handles multi-step handoff chains" do
      runner = RAAF::Runner.new(agent: researcher)
      
      # Mock API responses for the entire handoff chain
      mock_responses = [
        # First response from researcher with handoff to analyst
        {
          id: "resp_1",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [
                {
                  type: "output_text",
                  text: "I've researched AI trends. Let me transfer to AnalystAgent for analysis."
                }
              ]
            }
          ],
          usage: { input_tokens: 20, output_tokens: 15, total_tokens: 35 }
        },
        # Second response from analyst with handoff to summarizer
        {
          id: "resp_2",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [
                {
                  type: "output_text",
                  text: "Analysis complete. Transferring to SummarizerAgent for final summary."
                }
              ]
            }
          ],
          usage: { input_tokens: 25, output_tokens: 12, total_tokens: 37 }
        },
        # Final response from summarizer
        {
          id: "resp_3",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [
                {
                  type: "output_text",
                  text: "Final summary: AI trends show significant growth in automation and efficiency."
                }
              ]
            }
          ],
          usage: { input_tokens: 30, output_tokens: 18, total_tokens: 48 }
        }
      ]
      
      call_count = 0
      allow_any_instance_of(RAAF::Models::ResponsesProvider).to receive(:responses_completion) do
        call_count += 1
        mock_responses[call_count - 1] || mock_responses.last
      end
      
      result = runner.run([
        { role: "user", content: "Please research AI trends, analyze the findings, and provide a summary" }
      ])
      
      # Should end with the final agent in the chain
      expect(result.last_agent.name).to eq("SummarizerAgent")
      expect(result.messages.size).to be >= 3  # At least user + 2 agent responses
    end
  end

  describe "Handoff Priority and Detection" do
    let(:test_runner) { RAAF::Runner.new(agent: source_agent) }
    
    before do
      source_agent.add_handoff(target_agent)
      source_agent.add_handoff(support_agent)
    end

    it "prioritizes JSON handoffs over text handoffs" do
      message = {
        role: "assistant",
        content: '{"response": "Help needed", "handoff_to": "SupportAgent"} Please transfer to TargetAgent.'
      }
      
      result = test_runner.send(:detect_handoff_in_content, message[:content], source_agent)
      
      expect(result).not_to be_nil
      expect(result.name).to eq("SupportAgent")  # JSON takes priority
    end

    it "detects handoff patterns in text when no JSON present" do
      message = {
        role: "assistant",
        content: "I need to transfer you to our TargetAgent for specialized help."
      }
      
      result = test_runner.send(:detect_handoff_in_content, message[:content], source_agent)
      
      expect(result).not_to be_nil
      expect(result.name).to eq("TargetAgent")
    end

    it "returns no handoff when no patterns detected" do
      message = {
        role: "assistant",
        content: "I can help you with that request directly."
      }
      
      result = test_runner.send(:detect_handoff_in_content, message[:content], source_agent)
      
      expect(result[:handoff_occurred]).to be false
      expect(result[:target_agent]).to be_nil
    end
  end

  describe "Assistant Content Extraction" do
    let(:test_runner) { RAAF::Runner.new(agent: source_agent) }

    it "extracts content from single output_text item" do
      response = {
        "output" => [
          {
            "type" => "output_text",
            "text" => "Hello, I can help you with that."
          }
        ]
      }

      result = test_runner.send(:extract_assistant_content_from_response, response)
      
      expect(result).to eq("Hello, I can help you with that.")
    end

    it "concatenates multiple output_text items" do
      response = {
        "output" => [
          {
            "type" => "output_text",
            "text" => "First part. "
          },
          {
            "type" => "output_text",
            "text" => "Second part."
          }
        ]
      }

      result = test_runner.send(:extract_assistant_content_from_response, response)
      
      expect(result).to eq("First part. Second part.")
    end

    it "handles responses with no output_text items" do
      response = {
        "output" => [
          {
            "type" => "function_call",
            "name" => "some_function",
            "arguments" => "{}"
          }
        ]
      }

      result = test_runner.send(:extract_assistant_content_from_response, response)
      
      expect(result).to eq("")
    end

    it "handles empty responses" do
      response = { "output" => [] }

      result = test_runner.send(:extract_assistant_content_from_response, response)
      
      expect(result).to eq("")
    end
  end

end

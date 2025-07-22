# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Handoff System Integration", :integration do
  let(:source_agent) { RAAF::Agent.new(name: "SourceAgent", instructions: "You are a source agent") }
  let(:target_agent) { RAAF::Agent.new(name: "TargetAgent", instructions: "You are a target agent") }
  let(:support_agent) { RAAF::Agent.new(name: "SupportAgent", instructions: "You are a support agent") }
  let(:customer_service) { RAAF::Agent.new(name: "CustomerService", instructions: "You are customer service") }

  before do
    # Add handoff targets to source agent
    source_agent.add_handoff(target_agent)
    source_agent.add_handoff(support_agent)
    source_agent.add_handoff(customer_service)
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
        system_context_count = result.scan("# System context").length
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
      it "processes tool-based handoffs in function calls" do
        response = {
          "output" => [
            {
              "type" => "function_call",
              "name" => "transfer_to_target_agent",
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

    describe "End-to-End Handoff Scenarios" do
      let(:responses_provider) { RAAF::Models::ResponsesProvider.new }
      let(:runner) { RAAF::Runner.new(agent: source_agent, provider: responses_provider) }

      before do
        source_agent.add_handoff(target_agent)
        source_agent.add_handoff(support_agent)
      end

      context "Tool-based handoffs" do
        it "handles function call handoffs" do
          # First response - source agent performs handoff
          handoff_response = {
            "output" => [
              {
                "type" => "function_call",
                "name" => "transfer_to_support_agent",
                "arguments" => '{"reason": "User needs specialized support"}',
                "call_id" => "call_123"
              }
            ],
            "usage" => { "input_tokens" => 10, "output_tokens" => 15 }
          }

          # Second response - target agent responds normally
          target_response = {
            "output" => [
              {
                "type" => "message",
                "role" => "assistant",
                "content" => [
                  {
                    "type" => "text",
                    "text" => "Hello! I'm the support agent. How can I help you?"
                  }
                ]
              }
            ],
            "usage" => { "input_tokens" => 15, "output_tokens" => 20 }
          }

          allow(responses_provider).to receive(:responses_completion)
            .and_return(handoff_response, target_response)
          allow(responses_provider).to receive(:complete)
            .and_return(handoff_response, target_response)

          result = runner.run([{ role: "user", content: "Need support" }])

          expect(result.last_agent.name).to eq("SupportAgent")
        end

        it "prioritizes tool-based handoffs over content-based" do
          # First response - source agent performs handoff
          handoff_response = {
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
                "name" => "transfer_to_support_agent",
                "arguments" => '{"reason": "Tool-based handoff"}',
                "call_id" => "call_456"
              }
            ],
            "usage" => { "input_tokens" => 10, "output_tokens" => 15 }
          }

          # Second response - target agent responds normally
          target_response = {
            "output" => [
              {
                "type" => "message",
                "role" => "assistant",
                "content" => [
                  {
                    "type" => "text",
                    "text" => "Hello! I'm the support agent handling your request."
                  }
                ]
              }
            ],
            "usage" => { "input_tokens" => 15, "output_tokens" => 20 }
          }

          allow(responses_provider).to receive(:responses_completion)
            .and_return(handoff_response, target_response)
          allow(responses_provider).to receive(:complete)
            .and_return(handoff_response, target_response)

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

          allow(responses_provider).to receive_messages(responses_completion: response, complete: response)

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

          allow(responses_provider).to receive_messages(responses_completion: response, complete: response)

          result = runner.run([{ role: "user", content: "Help" }])

          expect(result.last_agent.name).to eq("SourceAgent")
        end
      end
    end

    describe "Context Preservation During Handoffs" do
      let(:search_agent) { RAAF::Agent.new(name: "SearchStrategyAgent", instructions: "You find market research strategies") }
      let(:discovery_agent) { RAAF::Agent.new(name: "CompanyDiscoveryAgent", instructions: "You discover companies") }
      let(:responses_provider) { RAAF::Models::ResponsesProvider.new }
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
              "name" => "transfer_to_company_discovery_agent",
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
              "name" => "transfer_to_company_discovery_agent",
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

        # Handoffs should not generate tool response messages - they are control transfers
        # The test should verify that the handoff worked (agent changed) and messages are present
        expect(result.messages.size).to be >= 2

        # Should have assistant messages from the target agent
        assistant_messages = result.messages.select { |msg| msg[:role] == "assistant" }
        expect(assistant_messages).not_to be_empty

        # Verify the content comes from CompanyDiscoveryAgent
        expect(assistant_messages.last[:content]).to include("CompanyDiscoveryAgent")
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

        # Mock API responses for the entire handoff chain using function calls
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
                    text: "I've researched AI trends. Let me transfer to the analyst for analysis."
                  }
                ]
              },
              {
                type: "function_call",
                name: "transfer_to_analyst_agent",
                arguments: '{"context": "Research on AI trends completed"}',
                call_id: "call_analyst"
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
                    text: "Analysis complete. Transferring to the summarizer for final summary."
                  }
                ]
              },
              {
                type: "function_call",
                name: "transfer_to_summarizer_agent",
                arguments: '{"context": "Analysis of AI trends completed"}',
                call_id: "call_summarizer"
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
        provider_mock = proc do
          call_count += 1
          mock_responses[call_count - 1] || mock_responses.last
        end

        allow_any_instance_of(RAAF::Models::ResponsesProvider).to receive(:responses_completion, &provider_mock)
        allow_any_instance_of(RAAF::Models::ResponsesProvider).to receive(:complete, &provider_mock)

        result = runner.run([
                              { role: "user", content: "Please research AI trends, analyze the findings, and provide a summary" }
                            ])

        # Should end with the final agent in the chain
        expect(result.last_agent.name).to eq("SummarizerAgent")
        expect(result.messages.size).to be >= 3 # At least user + 2 agent responses
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
end

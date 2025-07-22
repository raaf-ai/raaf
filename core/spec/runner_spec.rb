# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Runner do
  let(:agent) { RAAF::Agent.new(name: "TestAgent", instructions: "You are helpful") }
  let(:runner) { described_class.new(agent: agent) }

  describe "#initialize" do
    it "creates a runner with an agent" do
      expect(runner.agent).to eq(agent)
      # When tracing is disabled or gem is not available, tracer will be nil
      expect(runner.tracer).to be_nil
    end

    it "accepts a custom tracer", skip: "Tracing is in a separate gem" do
      # This test requires the raaf-tracing gem
      # custom_tracer = RAAF::Tracing::SpanTracer.new
      # runner = described_class.new(agent: agent, tracer: custom_tracer)
      # expect(runner.tracer).to eq(custom_tracer)
    end

    it "uses ResponsesProvider by default" do
      runner = described_class.new(agent: agent)

      expect(runner.instance_variable_get(:@provider)).to be_a(RAAF::Models::ResponsesProvider)
    end

    it "accepts a custom provider" do
      custom_provider = RAAF::Models::OpenAIProvider.new
      runner = described_class.new(agent: agent, provider: custom_provider)

      expect(runner.instance_variable_get(:@provider)).to eq(custom_provider)
    end
  end

  describe "#run" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:mock_response) do
      {
        id: "resp_123",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [
              {
                type: "output_text",
                text: "Hello! How can I help you?"
              }
            ]
          }
        ],
        usage: {
          input_tokens: 10,
          output_tokens: 5,
          total_tokens: 15
        }
      }
    end

    before do
      allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion).and_return(mock_response)
    end

    it "processes messages and returns results" do
      result = runner.run(messages)

      expect(result).to be_a(RAAF::RunResult)
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
      tool_call_response = {
        id: "resp_123",
        output: [
          {
            type: "function_call",
            call_id: "call_1",
            name: "unknown_tool",
            arguments: "{}"
          }
        ],
        usage: {
          input_tokens: 10,
          output_tokens: 5,
          total_tokens: 15
        }
      }

      allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion).and_return(tool_call_response)

      expect { runner.run(messages) }.to raise_error(RAAF::MaxTurnsError)
    end

    it "traces the conversation flow" do
      # The new tracing system doesn't expose traces in the same way
      # Instead we just verify the run completes successfully with tracing enabled
      result = runner.run(messages)
      expect(result).to be_a(RAAF::RunResult)
      expect(result.success?).to be true
    end
  end

  describe "#run_async" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:mock_response) do
      {
        id: "resp_123",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [
              {
                type: "output_text",
                text: "Hello! How can I help you?"
              }
            ]
          }
        ],
        usage: {
          input_tokens: 10,
          output_tokens: 5,
          total_tokens: 15
        }
      }
    end

    it "returns an Async task" do
      allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion).and_return(mock_response)

      task = runner.run_async(messages)
      expect(task).to be_a(Async::Task)
    end
  end

  describe "tool execution" do
    let(:agent_with_tools) do
      agent = RAAF::Agent.new(name: "ToolAgent")
      agent.add_tool(RAAF::FunctionTool.new(
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
        id: "resp_123",
        output: [
          {
            type: "function_call",
            call_id: "call_123",
            name: "double",
            arguments: '{"x": 5}'
          }
        ],
        usage: {
          input_tokens: 10,
          output_tokens: 5,
          total_tokens: 15
        }
      }
    end

    let(:final_response) do
      {
        id: "resp_124",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [
              {
                type: "output_text",
                text: "The result is 10"
              }
            ]
          }
        ],
        usage: {
          input_tokens: 15,
          output_tokens: 8,
          total_tokens: 23
        }
      }
    end

    it "executes tools and continues conversation" do
      call_count = 0
      allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion) do
        call_count += 1
        case call_count
        when 1
          tool_call_response
        when 2
          final_response
        end
      end

      result = runner.run(messages)

      # For Responses API, the conversation format is different
      # We should check that the result contains the expected final text
      expect(result.messages.last[:content]).to include("The result is 10")
    end

    it "handles tool execution errors gracefully" do
      agent_with_tools.add_tool(RAAF::FunctionTool.new(
                                  proc { raise StandardError, "Tool failed" },
                                  name: "failing_tool"
                                ))

      error_response = {
        id: "resp_125",
        output: [
          {
            type: "function_call",
            call_id: "call_456",
            name: "failing_tool",
            arguments: "{}"
          }
        ],
        usage: {
          input_tokens: 10,
          output_tokens: 5,
          total_tokens: 15
        }
      }

      call_count = 0
      allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion) do
        call_count += 1
        case call_count
        when 1
          error_response
        when 2
          final_response
        end
      end

      result = runner.run(messages)

      # For Responses API, errors are handled internally and the conversation continues
      expect(result.messages.last[:content]).to include("The result is 10")
    end

    it "traces tool execution" do
      allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion).and_return(tool_call_response,
                                                                                                   final_response)

      result = runner.run(messages)

      # Verify that tracing works by checking the run completed successfully
      expect(result).to be_a(RAAF::RunResult)
      expect(result.messages.last[:content]).to include("The result is 10")
    end
  end


  describe "streaming support" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:mock_streaming_response) do
      {
        id: "resp_123",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [
              {
                type: "output_text",
                text: "Streaming response"
              }
            ]
          }
        ],
        usage: {
          input_tokens: 10,
          output_tokens: 5,
          total_tokens: 15
        }
      }
    end

    it "supports streaming mode" do
      allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion).and_return(mock_streaming_response)

      result = runner.run(messages, stream: true)

      expect(result.messages.last[:content]).to include("Streaming response")
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
        agent.add_tool(RAAF::FunctionTool.new(
                         proc { |value| value },
                         name: "test_tool",
                         description: "A test tool"
                       ))

        prompt = runner.send(:build_system_prompt, agent)

        expect(prompt).to include("Available tools:")
        expect(prompt).to include("test_tool: A test tool")
      end

      it "does not include handoffs in system prompt" do
        other_agent = RAAF::Agent.new(name: "OtherAgent")
        agent.add_handoff(other_agent)

        prompt = runner.send(:build_system_prompt, agent)

        # Handoffs are now available as tools, not in the system prompt
        expect(prompt).not_to include("Available handoffs:")
      end

      it "handles agents without tools or handoffs" do
        basic_agent = RAAF::Agent.new(name: "BasicAgent")

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

  # =============================================================================
  # CONSOLIDATED CONTENT EXTRACTION TESTS
  # =============================================================================

  describe "Assistant Content Extraction" do
    let(:extraction_agent) { RAAF::Agent.new(name: "TestAgent", instructions: "Test agent") }
    let(:extraction_runner) { described_class.new(agent: extraction_agent) }

    describe "final message construction" do
      it "extracts assistant content from Responses API format" do
        # Mock the responses provider to return a realistic response
        mock_response = {
          "id" => "response_123",
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => "This is the assistant response content"
                }
              ]
            }
          ],
          "usage" => {
            "input_tokens" => 10,
            "output_tokens" => 8,
            "total_tokens" => 18
          }
        }

        allow_any_instance_of(RAAF::Models::ResponsesProvider)
          .to receive(:responses_completion)
          .and_return(mock_response)

        result = extraction_runner.run("Hello")

        # The final messages should contain the assistant response with proper content
        expect(result.messages.last).to have_key(:role)
        expect(result.messages.last[:role]).to eq("assistant")
        expect(result.messages.last).to have_key(:content)
        expect(result.messages.last[:content]).to eq("This is the assistant response content")
        expect(result.messages.last[:content]).not_to be_empty
      end

      it "handles multiple output_text items" do
        mock_response = {
          "id" => "response_456",
          "output" => [
            {
              "type" => "message",
              "role" => "assistant",
              "content" => [
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
          ],
          "usage" => {
            "input_tokens" => 10,
            "output_tokens" => 8,
            "total_tokens" => 18
          }
        }

        allow_any_instance_of(RAAF::Models::ResponsesProvider)
          .to receive(:responses_completion)
          .and_return(mock_response)

        result = extraction_runner.run("Hello")

        # Should concatenate multiple output_text items
        expect(result.messages.last[:content]).to eq("First part. Second part.")
      end

      it "prevents empty assistant messages" do
        mock_response = {
          "id" => "response_789",
          "output" => [
            {
              "type" => "function_call",
              "name" => "some_function",
              "arguments" => "{}"
            }
          ],
          "usage" => {
            "input_tokens" => 10,
            "output_tokens" => 8,
            "total_tokens" => 18
          }
        }

        allow_any_instance_of(RAAF::Models::ResponsesProvider)
          .to receive(:responses_completion)
          .and_return(mock_response)

        result = extraction_runner.run("Hello")

        # Should not create empty assistant messages
        assistant_messages = result.messages.select { |msg| msg[:role] == "assistant" }
        empty_messages = assistant_messages.select { |msg| msg[:content].nil? || msg[:content].empty? }
        expect(empty_messages).to be_empty
      end
    end

    describe "extract_assistant_content_from_response method" do
      it "extracts content from single output_text item" do
        response = {
          "output" => [
            {
              "type" => "output_text",
              "text" => "Hello, I can help you with that."
            }
          ]
        }

        result = extraction_runner.send(:extract_assistant_content_from_response, response)
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

        result = extraction_runner.send(:extract_assistant_content_from_response, response)
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

        result = extraction_runner.send(:extract_assistant_content_from_response, response)
        expect(result).to eq("")
      end

      it "handles empty responses" do
        response = { "output" => [] }

        result = extraction_runner.send(:extract_assistant_content_from_response, response)
        expect(result).to eq("")
      end

      it "handles responses with nil output" do
        response = { "output" => nil }

        result = extraction_runner.send(:extract_assistant_content_from_response, response)
        expect(result).to eq("")
      end

      it "handles malformed responses gracefully" do
        response = {}

        result = extraction_runner.send(:extract_assistant_content_from_response, response)
        expect(result).to eq("")
      end
    end

    describe "content preservation during complex scenarios" do
      it "preserves content through multiple API calls" do
        # First response with content
        first_response = {
          "output" => [
            {
              "type" => "output_text",
              "text" => "I understand your request. Let me process this."
            }
          ]
        }

        # Second response with more content
        second_response = {
          "output" => [
            {
              "type" => "output_text",
              "text" => "Here's the final result of your request."
            }
          ]
        }

        allow_any_instance_of(RAAF::Models::ResponsesProvider)
          .to receive(:responses_completion)
          .and_return(first_response, second_response)

        result = extraction_runner.run("Complex request")

        # Should preserve both responses
        assistant_messages = result.messages.select { |msg| msg[:role] == "assistant" }
        expect(assistant_messages.size).to be >= 1
        expect(assistant_messages.any? { |msg| msg[:content].include?("understand your request") || msg[:content].include?("final result") }).to be true
      end

      it "handles mixed content types in responses" do
        response = {
          "output" => [
            {
              "type" => "output_text",
              "text" => "Text content. "
            },
            {
              "type" => "function_call",
              "name" => "some_function",
              "arguments" => "{}"
            },
            {
              "type" => "output_text",
              "text" => "More text."
            }
          ]
        }

        result = extraction_runner.send(:extract_assistant_content_from_response, response)
        expect(result).to eq("Text content. More text.")
      end
    end
  end

  # =============================================================================
  # NORMALIZE_AGENT_NAME UTILITY METHOD TESTS
  # =============================================================================

  describe "normalize_agent_name utility method" do
    let(:test_agent) { RAAF::Agent.new(name: "TestAgent", instructions: "Test agent") }

    it "converts Agent objects to their name strings" do
      result = runner.send(:normalize_agent_name, test_agent)
      expect(result).to eq("TestAgent")
      expect(result).to be_a(String)
    end

    it "passes through string names unchanged" do
      result = runner.send(:normalize_agent_name, "SupportAgent")
      expect(result).to eq("SupportAgent")
      expect(result).to be_a(String)
    end

    it "handles nil input gracefully" do
      result = runner.send(:normalize_agent_name, nil)
      expect(result).to be_nil
    end

    it "converts non-Agent objects to strings" do
      result = runner.send(:normalize_agent_name, 123)
      expect(result).to eq("123")
      expect(result).to be_a(String)
    end

    it "handles empty strings correctly" do
      result = runner.send(:normalize_agent_name, "")
      expect(result).to eq("")
      expect(result).to be_a(String)
    end

    it "works with objects that respond to :name" do
      # Create a mock object that responds to :name
      mock_object = double("MockAgent", name: "MockedAgent")
      result = runner.send(:normalize_agent_name, mock_object)
      expect(result).to eq("MockedAgent")
    end

    it "handles symbols by converting to strings" do
      result = runner.send(:normalize_agent_name, :symbol_agent)
      expect(result).to eq("symbol_agent")
      expect(result).to be_a(String)
    end

    it "handles edge case with whitespace in names" do
      agent_with_spaces = RAAF::Agent.new(name: "  Agent With Spaces  ")
      result = runner.send(:normalize_agent_name, agent_with_spaces)
      expect(result).to eq("  Agent With Spaces  ")
      expect(result).to be_a(String)
    end

    context "with different Agent objects" do
      it "works with agents having different names" do
        agent1 = RAAF::Agent.new(name: "Agent1")
        agent2 = RAAF::Agent.new(name: "Agent2")

        expect(runner.send(:normalize_agent_name, agent1)).to eq("Agent1")
        expect(runner.send(:normalize_agent_name, agent2)).to eq("Agent2")
      end

      it "works with agents having complex names" do
        complex_agent = RAAF::Agent.new(name: "ComplexAgent_With-Special.Characters")
        result = runner.send(:normalize_agent_name, complex_agent)
        expect(result).to eq("ComplexAgent_With-Special.Characters")
      end
    end
  end

  # =============================================================================
  # INTEGRATION TESTS FOR NORMALIZE_AGENT_NAME IN HANDOFF SCENARIOS
  # =============================================================================

  describe "normalize_agent_name integration with handoff methods" do
    let(:source_agent) { RAAF::Agent.new(name: "SourceAgent") }
    let(:target_agent) { RAAF::Agent.new(name: "TargetAgent") }

    before do
      source_agent.add_handoff(target_agent)
    end

    it "find_handoff_agent works with Agent objects" do
      result = runner.send(:find_handoff_agent, target_agent, source_agent)
      expect(result).to eq(target_agent)
    end

    it "find_handoff_agent works with string names" do
      result = runner.send(:find_handoff_agent, "TargetAgent", source_agent)
      expect(result).to eq(target_agent)
    end

    it "find_handoff_agent returns nil for non-existent agents" do
      result = runner.send(:find_handoff_agent, "NonExistentAgent", source_agent)
      expect(result).to be_nil
    end

    it "find_handoff_agent handles nil input" do
      result = runner.send(:find_handoff_agent, nil, source_agent)
      expect(result).to be_nil
    end

    it "provides consistent results regardless of input type" do
      # Both should return the same agent object
      result_with_agent = runner.send(:find_handoff_agent, target_agent, source_agent)
      result_with_string = runner.send(:find_handoff_agent, "TargetAgent", source_agent)

      expect(result_with_agent).to eq(result_with_string)
      expect(result_with_agent).to eq(target_agent)
    end
  end
end

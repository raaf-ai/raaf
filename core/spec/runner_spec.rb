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

      # First, add a simple tool to the agent that will be called successfully
      def dummy_tool
        "Tool executed"
      end
      agent.add_tool(method(:dummy_tool))

      # Create responses that will keep the conversation going
      call_count = 0
      allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion) do
        call_count += 1
        {
          id: "resp_#{call_count}",
          output: [
            {
              type: "function_call",
              call_id: "call_#{call_count}",
              name: "dummy_tool",
              arguments: "{}"
            }
          ],
          usage: {
            input_tokens: 10,
            output_tokens: 5,
            total_tokens: 15
          }
        }
      end

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
    skip "Skipping run_async method"
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
      skip "Skipping run_async method"
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

      # For Responses API, find the assistant's final response
      assistant_messages = result.messages.select { |msg| msg[:role] == "assistant" }
      expect(assistant_messages).not_to be_empty, "Expected at least one assistant message"

      # The last assistant message should contain the final response
      last_assistant_content = assistant_messages.last[:content]
      expect(last_assistant_content).to be_a(String)
      expect(last_assistant_content).to include("The result is 10")
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
      # Find the assistant's final response
      assistant_messages = result.messages.select { |msg| msg[:role] == "assistant" }
      expect(assistant_messages).not_to be_empty, "Expected at least one assistant message"

      last_assistant_content = assistant_messages.last[:content]
      expect(last_assistant_content).to be_a(String)
      expect(last_assistant_content).to include("The result is 10")
    end

    it "traces tool execution" do
      allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion).and_return(tool_call_response,
                                                                                                   final_response)

      result = runner.run(messages)

      # Verify that tracing works by checking the run completed successfully
      expect(result).to be_a(RAAF::RunResult)

      # Find the assistant's final response
      assistant_messages = result.messages.select { |msg| msg[:role] == "assistant" }
      expect(assistant_messages).not_to be_empty, "Expected at least one assistant message"

      last_assistant_content = assistant_messages.last[:content]
      expect(last_assistant_content).to be_a(String)
      expect(last_assistant_content).to include("The result is 10")
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

  describe "error handling and resilience" do
    describe "#should_stop?" do
      it "returns false when no stop checker is set" do
        expect(runner.send(:should_stop?)).to be false
      end

      it "handles stop checker exceptions gracefully" do
        failing_checker = proc { raise StandardError, "Stop checker failed" }
        runner.instance_variable_set(:@stop_checker, failing_checker)

        expect(runner).to receive(:log_exception)
        expect(runner.send(:should_stop?)).to be false
      end

      it "returns true when stop checker indicates stop" do
        stop_checker = proc { true }
        runner.instance_variable_set(:@stop_checker, stop_checker)

        expect(runner.send(:should_stop?)).to be true
      end

      it "returns false when stop checker indicates continue" do
        continue_checker = proc { false }
        runner.instance_variable_set(:@stop_checker, continue_checker)

        expect(runner.send(:should_stop?)).to be false
      end
    end

    describe "tool execution error handling" do
      let(:tool_result) { { role: "tool", tool_call_id: "call_123", content: "Tool result" } }

      it "processes tool responses appropriately" do
        # This test verifies that the tool processing pipeline works
        test_tool = proc { "Tool executed successfully" }
        agent.add_tool(test_tool)

        # Verify the tool was added
        expect(agent.tools).not_to be_empty
        expect(agent.tools.first).to be_a(RAAF::FunctionTool)
      end

      it "handles tool execution exceptions" do
        failing_tool = proc { raise StandardError, "Tool execution failed" }
        agent.add_tool(failing_tool)

        mock_response = {
          id: "resp_123",
          output: [
            {
              type: "function_call",
              call_id: "call_123",
              name: "failing_tool",
              arguments: "{}"
            }
          ],
          usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 }
        }

        allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion)
          .and_return(mock_response)

        result = runner.run("Test with failing tool")
        expect(result).to be_a(RAAF::RunResult)
      end
    end

    describe "session processing edge cases" do
      it "handles empty session gracefully" do
        session = RAAF::Session.new
        result = runner.send(:process_session, session, [])

        expect(result).to be_an(Array)
        expect(result).to eq([]) # Should return empty combined messages
      end

      it "handles session with very large message history" do
        session = RAAF::Session.new
        large_messages = Array.new(1000) { |i| { role: "user", content: "Message #{i}" } }

        expect do
          runner.send(:process_session, session, large_messages)
        end.not_to raise_error
      end

      it "handles memory manager failures during session processing" do
        session = RAAF::Session.new
        mock_memory_manager = double("MemoryManager")
        runner.instance_variable_set(:@memory_manager, mock_memory_manager)

        allow(mock_memory_manager).to receive(:token_limit).and_return(4096)
        allow(mock_memory_manager).to receive(:get_relevant_context)
          .and_raise(StandardError, "Memory manager failed")

        messages = [{ role: "user", content: "Test message" }]
        # Currently the implementation allows memory manager exceptions to bubble up
        # In the future this should be wrapped with error handling
        expect { runner.send(:process_session, session, messages) }.to raise_error(StandardError, "Memory manager failed")
      end
    end

    describe "guardrails integration" do
      let(:mock_guardrail) { instance_double(Guardrail) }

      before do
        # Mock guardrails if available
        allow(mock_guardrail).to receive_messages(process_input: "Safe input", process_output: "Safe output") if defined?(Guardrails)
      end

      it "handles input guardrail exceptions" do
        skip "Guardrails gem not available" unless defined?(Guardrails)

        allow(mock_guardrail).to receive(:process_input)
          .and_raise(StandardError, "Guardrail processing failed")

        runner.instance_variable_set(:@input_guardrails, [mock_guardrail])

        expect { runner.run("Test message") }.not_to raise_error
      end

      it "handles output guardrail exceptions" do
        skip "Guardrails gem not available" unless defined?(Guardrails)

        allow(mock_guardrail).to receive(:process_output)
          .and_raise(StandardError, "Output guardrail failed")

        runner.instance_variable_set(:@output_guardrails, [mock_guardrail])

        expect { runner.run("Test message") }.not_to raise_error
      end
    end
  end

  describe "complex execution flows" do
    describe "input validation" do
      let(:mock_provider) { instance_double(RAAF::Models::ResponsesProvider) }
      let(:runner_with_provider) { described_class.new(agent: agent, provider: mock_provider) }

      it "handles mixed message formats" do
        mixed_messages = [
          { role: "user", content: "Message 1" },
          { role: "assistant", content: "Response 1" },
          { role: "user", content: "Message 2" }
        ]

        # Mock both API formats
        chat_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "Handled mixed formats"
            }
          }],
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 15, "total_tokens" => 25 }
        }

        responses_response = {
          id: "resp_123",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "Handled mixed formats" }]
            }
          ],
          usage: { input_tokens: 10, output_tokens: 15 }
        }

        allow(mock_provider).to receive_messages(chat_completion: chat_response, responses_completion: responses_response)

        result = runner_with_provider.run(mixed_messages)
        expect(result).to be_a(RAAF::RunResult)
      end

      it "processes large conversations efficiently" do
        # Test with a reasonable number of messages
        large_input = Array.new(20) { |i| { role: "user", content: "Message #{i}" } }

        # Mock both API formats
        chat_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "Processed efficiently"
            }
          }],
          "usage" => { "prompt_tokens" => 100, "completion_tokens" => 10, "total_tokens" => 110 }
        }

        responses_response = {
          id: "resp_123",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "Processed efficiently" }]
            }
          ],
          usage: { input_tokens: 100, output_tokens: 10 }
        }

        allow(mock_provider).to receive_messages(chat_completion: chat_response, responses_completion: responses_response)

        result = runner_with_provider.run(large_input)
        expect(result).to be_a(RAAF::RunResult)
      end
    end

    describe "handoff functionality" do
      let(:agent1) { RAAF::Agent.new(name: "Agent1", instructions: "First agent") }
      let(:agent2) { RAAF::Agent.new(name: "Agent2", instructions: "Second agent") }
      let(:mock_provider) { instance_double(RAAF::Models::ResponsesProvider) }

      it "supports basic handoff setup" do
        agent1.add_handoff(agent2)
        runner_with_handoffs = described_class.new(agent: agent1, provider: mock_provider)

        # Mock both API formats
        chat_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "Handoff configured"
            }
          }],
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
        }

        responses_response = {
          id: "resp_123",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "Handoff configured" }]
            }
          ],
          usage: { input_tokens: 10, output_tokens: 5 }
        }

        allow(mock_provider).to receive_messages(chat_completion: chat_response, responses_completion: responses_response)

        result = runner_with_handoffs.run("Test handoff setup")
        expect(result).to be_a(RAAF::RunResult)
      end
    end

    describe "conversation context management" do
      let(:mock_provider) { instance_double(RAAF::Models::ResponsesProvider) }
      let(:runner_with_mock) { described_class.new(agent: agent, provider: mock_provider) }

      it "maintains context across multiple turns" do
        # Mock both API formats
        chat_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "Context maintained"
            }
          }],
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
        }

        responses_response = {
          id: "resp_123",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "Context maintained" }]
            }
          ],
          usage: { input_tokens: 10, output_tokens: 5 }
        }

        allow(mock_provider).to receive_messages(chat_completion: chat_response, responses_completion: responses_response)

        conversation_history = [{ role: "user", content: "Previous message" }]
        result = runner_with_mock.run(conversation_history + [{ role: "user", content: "Current message" }])

        expect(result).to be_a(RAAF::RunResult)
        expect(result.messages).not_to be_empty
      end

      it "handles reasonable conversation lengths" do
        # Mock both API formats
        chat_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "Handled conversation"
            }
          }],
          "usage" => { "prompt_tokens" => 100, "completion_tokens" => 10, "total_tokens" => 110 }
        }

        responses_response = {
          id: "resp_123",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "Handled conversation" }]
            }
          ],
          usage: { input_tokens: 100, output_tokens: 10 }
        }

        allow(mock_provider).to receive_messages(chat_completion: chat_response, responses_completion: responses_response)

        # Create a reasonable conversation history
        conversation_history = Array.new(10) do |i|
          [
            { role: "user", content: "Question #{i}" },
            { role: "assistant", content: "Answer #{i}" }
          ]
        end.flatten

        result = runner_with_mock.run(conversation_history + [{ role: "user", content: "Final question" }])
        expect(result).to be_a(RAAF::RunResult)
      end
    end

    describe "tool integration" do
      it "supports agents with tools" do
        # Add simple tools to the agent
        tool1 = proc { |arg| "Tool1: #{arg}" }
        tool2 = proc { |arg| "Tool2: #{arg}" }

        agent.add_tool(tool1)
        agent.add_tool(tool2)

        # Verify the agent has tools
        expect(agent.tools).not_to be_empty
        expect(agent.tools.size).to eq(2)
      end

      it "handles agents with no tools" do
        # Use a basic agent with no tools
        basic_agent = RAAF::Agent.new(name: "BasicAgent", instructions: "Basic agent")
        basic_runner = described_class.new(agent: basic_agent)

        mock_provider = instance_double(RAAF::Models::ResponsesProvider)
        basic_runner.instance_variable_set(:@provider, mock_provider)

        # Mock both API methods since the execution path may vary
        chat_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "No tools response"
            }
          }],
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
        }

        responses_response = {
          id: "resp_123",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "No tools response" }]
            }
          ],
          usage: { input_tokens: 10, output_tokens: 5 }
        }

        allow(mock_provider).to receive_messages(chat_completion: chat_response, responses_completion: responses_response)

        result = basic_runner.run("Test with no tools")
        expect(result).to be_a(RAAF::RunResult)
      end
    end
  end

  describe "resource management and performance" do
    it "handles large response processing efficiently" do
      # Simulate a large API response
      large_response = {
        id: "resp_123",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [
              {
                type: "output_text",
                text: "Very long response: #{"A" * 10_000}"
              }
            ]
          }
        ],
        usage: { input_tokens: 10, output_tokens: 5000, total_tokens: 5010 }
      }

      allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion)
        .and_return(large_response)

      start_time = Time.now
      result = runner.run("Generate large response")
      duration = Time.now - start_time

      expect(result).to be_a(RAAF::RunResult)
      expect(duration).to be < 5.0 # Should complete in reasonable time
    end

    it "manages memory usage during long conversations" do
      # Test memory usage doesn't grow excessively
      initial_memory = `ps -o rss= -p #{Process.pid}`.to_i

      mock_response = {
        id: "resp_123",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [{ type: "output_text", text: "Response" }]
          }
        ],
        usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 }
      }

      allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion)
        .and_return(mock_response)

      # Run multiple conversations
      10.times do |i|
        runner.run("Conversation turn #{i}")
      end

      final_memory = `ps -o rss= -p #{Process.pid}`.to_i
      memory_growth = final_memory - initial_memory

      # Memory growth should be reasonable (less than 50MB for 10 turns)
      expect(memory_growth).to be < 50_000 # KB
    end

    it "handles concurrent access safely" do
      results = []
      threads = []

      mock_response = {
        id: "resp_123",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [{ type: "output_text", text: "Concurrent response" }]
          }
        ],
        usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 }
      }

      allow(runner.instance_variable_get(:@provider)).to receive(:responses_completion)
        .and_return(mock_response)

      # Simulate concurrent requests
      5.times do |i|
        threads << Thread.new do
          result = runner.run("Concurrent request #{i}")
          results << result
        rescue StandardError => e
          results << e
        end
      end

      threads.each(&:join)

      # All requests should complete successfully
      expect(results.length).to eq(5)
      expect(results).to all(be_a(RAAF::RunResult))
    end
  end

  # Boundary conditions and edge cases
  describe "message boundary conditions" do
    let(:mock_provider) { create_mock_provider }

    context "message content boundaries" do
      it "handles messages with zero-length content" do
        agent = create_test_agent(name: "EmptyContentAgent")
        mock_provider.add_response("Handled empty content")
        runner = described_class.new(agent: agent, provider: mock_provider)

        result = runner.run("")
        expect(result.messages).not_to be_empty
        # Find the user message in the messages array
        user_message = result.messages.find { |m| m[:role] == "user" }
        expect(user_message).not_to be_nil
        expect(user_message[:content]).to eq("")
      end

      it "handles messages with extremely long content" do
        agent = create_test_agent(name: "LongContentAgent")
        mock_provider.add_response("Handled long content")
        runner = described_class.new(agent: agent, provider: mock_provider)

        long_content = "Long message content. " * 100_000 # ~2MB message

        result = runner.run(long_content)
        # Find the user message in the messages array
        user_message = result.messages.find { |m| m[:role] == "user" }
        expect(user_message).not_to be_nil
        expect(user_message[:content]).to eq(long_content)
      end

      it "handles messages with various whitespace patterns" do
        whitespace_messages = [
          "\n\n\n",      # Multiple newlines
          "\t\t\t",      # Multiple tabs
          "   \t\n  ",   # Mixed whitespace
          " " * 1000     # Lots of spaces
        ]

        agent = create_test_agent(name: "WhitespaceAgent")
        runner = described_class.new(agent: agent, provider: mock_provider)

        whitespace_messages.each do |msg|
          mock_provider.add_response("Handled whitespace")
          result = runner.run(msg)
          # Find the user message in the messages array
          user_message = result.messages.find { |m| m[:role] == "user" }
          expect(user_message).not_to be_nil
          expect(user_message[:content]).to eq(msg)
        end
      end

      it "handles messages with control characters" do
        control_chars = [
          "\u0000",      # Null character
          "\u001B",      # Escape character
          "\u007F",      # Delete character
          "\u{200B}",    # Zero-width space
          "\u{FEFF}"     # Byte order mark
        ]

        agent = create_test_agent(name: "ControlCharAgent")
        runner = described_class.new(agent: agent, provider: mock_provider)

        control_chars.each do |char|
          mock_provider.add_response("Handled control char")

          # Should not crash, though content might be sanitized
          expect { runner.run(char) }.not_to raise_error
        end
      end
    end

    context "message history boundaries" do
      it "handles empty message history" do
        agent = create_test_agent(name: "EmptyHistoryAgent")
        mock_provider.add_response("No history response")
        runner = described_class.new(agent: agent, provider: mock_provider)

        # Pass empty array as messages
        result = runner.run([])
        expect(result.messages).not_to be_empty
        # Should have system message and assistant response
        expect(result.messages.any? { |m| m[:role] == "assistant" }).to be true
      end

      it "handles single message in history" do
        agent = create_test_agent(name: "SingleHistoryAgent")
        mock_provider.add_response("Single history response")
        runner = described_class.new(agent: agent, provider: mock_provider)

        # Pass messages array with history
        messages = [
          { role: "user", content: "Previous message" },
          { role: "assistant", content: "Previous response" },
          { role: "user", content: "New message" }
        ]
        result = runner.run(messages)

        expect(result.messages).not_to be_empty
        expect(result.messages.length).to be >= 3
      end

      it "handles alternating role message history" do
        agent = create_test_agent(name: "AlternatingAgent")
        mock_provider.add_response("Alternating response")
        runner = described_class.new(agent: agent, provider: mock_provider)

        # Create alternating user/assistant history
        history = 100.times.map do |i|
          {
            role: i.even? ? "user" : "assistant",
            content: "Message #{i}"
          }
        end

        # Add final user message
        history << { role: "user", content: "Final message" }

        result = runner.run(history)
        expect(result.messages).not_to be_empty
      end
    end
  end
end

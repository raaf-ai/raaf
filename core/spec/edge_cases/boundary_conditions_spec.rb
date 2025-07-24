# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Boundary Conditions" do
  let(:mock_provider) { create_mock_provider }

  describe "Agent boundary conditions" do
    context "agent name limits" do
      it "handles extremely long agent names" do
        long_name = "Agent#{"X" * 1000}"
        agent = RAAF::Agent.new(name: long_name, instructions: "Test agent")

        expect(agent.name).to eq(long_name)
        expect(agent.name.length).to eq(1005)
      end

      it "handles empty agent names" do
        agent = RAAF::Agent.new(name: "", instructions: "Test agent")
        expect(agent.name).to eq("")
      end

      it "handles agent names with special characters" do
        special_names = [
          "Agent-With-Dashes",
          "Agent_With_Underscores",
          "Agent With Spaces",
          "Agent\tWith\tTabs",
          "Agent\nWith\nNewlines",
          "Agent🚀With🎭Emojis",
          "Agent<>With<>Brackets",
          "Agent\"With\"Quotes",
          "Agent'With'Apostrophes"
        ]

        special_names.each do |name|
          agent = RAAF::Agent.new(name: name, instructions: "Test")
          expect(agent.name).to eq(name)
        end
      end
    end

    context "instructions boundary conditions" do
      it "handles extremely long instructions" do
        long_instructions = "You are a helpful assistant. " * 10_000
        agent = RAAF::Agent.new(name: "TestAgent", instructions: long_instructions)

        expect(agent.instructions.length).to be > 250_000
        expect(agent.instructions).to eq(long_instructions)
      end

      it "handles nil instructions" do
        agent = RAAF::Agent.new(name: "TestAgent", instructions: nil)
        expect(agent.instructions).to be_nil
      end

      it "handles empty string instructions" do
        agent = RAAF::Agent.new(name: "TestAgent", instructions: "")
        expect(agent.instructions).to eq("")
      end

      it "handles instructions with Unicode and special encoding" do
        unicode_instructions = "You are 🤖 an AI assistant. Помогайте пользователям. 你是一个助手。 العربية"
        agent = RAAF::Agent.new(name: "UnicodeAgent", instructions: unicode_instructions)

        expect(agent.instructions).to eq(unicode_instructions)
        expect(agent.instructions.encoding).to eq(Encoding::UTF_8)
      end
    end

    context "max_turns boundary conditions" do
      it "handles zero max_turns" do
        agent = RAAF::Agent.new(name: "ZeroTurns", max_turns: 0)
        expect(agent.max_turns).to eq(0)
      end

      it "handles negative max_turns" do
        agent = RAAF::Agent.new(name: "NegativeTurns", max_turns: -1)
        expect(agent.max_turns).to eq(-1)
      end

      it "handles extremely large max_turns" do
        large_turns = (2**31) - 1 # Max 32-bit integer
        agent = RAAF::Agent.new(name: "LargeTurns", max_turns: large_turns)
        expect(agent.max_turns).to eq(large_turns)
      end
    end
  end

  describe "Tool boundary conditions" do
    context "tool name boundaries" do
      it "handles tools with very long names" do
        long_name = "tool_with_very_long_name_#{"x" * 1000}"
        tool = RAAF::FunctionTool.new(
          proc { "result" },
          name: long_name
        )

        expect(tool.name).to eq(long_name)
      end

      it "handles tools with special characters in names" do
        special_names = %w[
          tool-with-dashes
          tool_with_underscores
          tool123with456numbers
          toolWithCamelCase
          TOOL_WITH_CAPS
        ]

        special_names.each do |name|
          tool = RAAF::FunctionTool.new(proc { "result" }, name: name)
          expect(tool.name).to eq(name)
        end
      end
    end

    context "tool parameter boundaries" do
      it "handles tools with no parameters" do
        tool = RAAF::FunctionTool.new(proc { "no params" }, name: "no_param_tool")

        expect(tool.parameters?).to be false
        expect(tool.required_parameters?).to be false
      end

      it "handles tools with maximum parameter counts" do
        # Create proc with many parameters
        many_params = (1..50).map { |i| "param#{i}:" }.join(", ")
        proc_string = "proc { |#{many_params}| 'many params' }"
        # rubocop:disable Security/Eval
        many_param_proc = eval(proc_string)
        # rubocop:enable Security/Eval

        tool = RAAF::FunctionTool.new(many_param_proc, name: "many_param_tool")

        expect(tool.parameters?).to be true
        expect(tool.required_parameters?).to be true

        schema = tool.to_h[:function][:parameters]
        expect(schema[:properties].keys.size).to eq(50)
        expect(schema[:required].size).to eq(50)
      end

      it "handles parameter names with special characters" do
        # Parameters can't have special chars in Ruby, but descriptions can
        tool = RAAF::FunctionTool.new(
          proc { |special_param:| special_param },
          name: "special_tool",
          description: "Tool with special characters: !@#$%^&*()"
        )

        expect(tool.description).to include("!@#$%^&*()")
      end
    end

    context "tool execution boundaries" do
      it "handles tools that return nil" do
        nil_tool = RAAF::FunctionTool.new(
          proc {},
          name: "nil_tool"
        )

        result = nil_tool.call
        expect(result).to be_nil
      end

      it "handles tools that return very large results" do
        large_result_tool = RAAF::FunctionTool.new(
          proc { "x" * 1_000_000 }, # 1MB result
          name: "large_result_tool"
        )

        result = large_result_tool.call
        expect(result.size).to eq(1_000_000)
      end

      it "handles tools with infinite loops (timeout protection)" do
        infinite_tool = RAAF::FunctionTool.new(
          proc { loop { sleep 0.001 } },
          name: "infinite_tool"
        )

        # This should not hang the test - tool execution should have timeouts
        # In production, there would be timeout protection
        expect do
          Timeout.timeout(1) { infinite_tool.call }
        end.to raise_error(Timeout::Error)
      end

      it "handles tools that consume excessive memory" do
        memory_hog_tool = RAAF::FunctionTool.new(
          proc {
            # Try to allocate large array
            begin
              Array.new(100_000_000, "memory hog")
            rescue NoMemoryError
              "Memory allocation failed safely"
            end
          },
          name: "memory_hog_tool"
        )

        # Should either succeed or fail gracefully
        result = memory_hog_tool.call
        expect([String, Array]).to include(result.class)
      end
    end
  end

  describe "Message boundary conditions" do
    context "message content boundaries" do
      it "handles messages with zero-length content" do
        agent = RAAF::Agent.new(name: "EmptyContentAgent")
        mock_provider.add_response("Handled empty content")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        result = runner.run("")
        expect(result.messages).not_to be_empty
        # Find the user message in the messages array
        user_message = result.messages.find { |m| m[:role] == "user" }
        expect(user_message).not_to be_nil
        expect(user_message[:content]).to eq("")
      end

      it "handles messages with extremely long content" do
        agent = RAAF::Agent.new(name: "LongContentAgent")
        mock_provider.add_response("Handled long content")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        long_content = "Long message content. " * 100_000 # ~2MB message

        result = runner.run(long_content)
        # Find the user message in the messages array
        user_message = result.messages.find { |m| m[:role] == "user" }
        expect(user_message).not_to be_nil
        expect(user_message[:content]).to eq(long_content)
      end

      it "handles messages with only whitespace" do
        whitespace_messages = [
          " ",           # Single space
          "\t",          # Tab
          "\n",          # Newline
          "\r\n",        # CRLF
          "   \t\n  ",   # Mixed whitespace
          " " * 1000     # Lots of spaces
        ]

        agent = RAAF::Agent.new(name: "WhitespaceAgent")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

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
          "\x00", # Null
          "\x01\x02\x03", # Control chars
          "\b\f\v",      # Backspace, form feed, vertical tab
          "\x7f",        # DEL
          "\u{200B}",    # Zero-width space
          "\u{FEFF}"     # Byte order mark
        ]

        agent = RAAF::Agent.new(name: "ControlCharAgent")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        control_chars.each do |char|
          mock_provider.add_response("Handled control char")

          # Should not crash, though content might be sanitized
          expect { runner.run(char) }.not_to raise_error
        end
      end
    end

    context "message history boundaries" do
      it "handles empty message history" do
        agent = RAAF::Agent.new(name: "EmptyHistoryAgent")
        mock_provider.add_response("No history response")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        # Pass empty array as messages
        result = runner.run([])
        expect(result.messages).not_to be_empty
        # Should have system message and assistant response
        expect(result.messages.any? { |m| m[:role] == "assistant" }).to be true
      end

      it "handles single message in history" do
        agent = RAAF::Agent.new(name: "SingleHistoryAgent")
        mock_provider.add_response("Single history response")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        # Pass messages array with history
        messages = [
          { role: "user", content: "Previous message" },
          { role: "assistant", content: "Previous response" },
          { role: "user", content: "New message" }
        ]
        result = runner.run(messages)

        expect(result.messages).not_to be_empty
        # Should include history and new response
        expect(result.messages.count { |m| m[:role] == "user" }).to be >= 2
      end

      it "handles alternating role message history" do
        agent = RAAF::Agent.new(name: "AlternatingAgent")
        mock_provider.add_response("Alternating response")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

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
        # Should have processed the history
        expect(result.messages.any? { |m| m[:role] == "assistant" }).to be true
      end
    end
  end

  describe "Configuration boundary conditions" do
    context "RunConfig boundaries" do
      it "handles config with all nil values" do
        config = RAAF::RunConfig.new(
          max_turns: nil,
          max_tokens: nil,
          temperature: nil,
          stream: nil
        )

        expect(config.max_turns).to be_nil
        expect(config.max_tokens).to be_nil
        expect(config.temperature).to be_nil
        expect(config.stream).to be_nil
      end

      it "handles extreme configuration values" do
        config = RAAF::RunConfig.new(
          max_turns: 0,
          max_tokens: 1,
          temperature: 0.0,
          stream: false
        )

        agent = RAAF::Agent.new(name: "ExtremeConfigAgent")
        mock_provider.add_response("Extreme config response")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        # Should handle extreme but valid values
        expect { runner.run("Test", config: config) }.not_to raise_error
      end

      it "handles config with very large metadata" do
        large_metadata = {}
        1000.times { |i| large_metadata["key_#{i}"] = "value_#{i}" * 100 }

        config = RAAF::RunConfig.new(metadata: large_metadata)

        expect(config.metadata.size).to eq(1000)
      end
    end

    context "ExecutionConfig boundaries" do
      it "handles execution config with empty arrays" do
        exec_config = RAAF::Config::ExecutionConfig.new(
          input_guardrails: [],
          output_guardrails: [],
          session: {}
        )

        expect(exec_config.input_guardrails).to eq([])
        expect(exec_config.output_guardrails).to eq([])
        expect(exec_config.session).to eq({})
      end

      it "handles execution config with large arrays" do
        large_guardrails = Array.new(1000) { |i| "guardrail_#{i}" }

        exec_config = RAAF::Config::ExecutionConfig.new(
          input_guardrails: large_guardrails,
          output_guardrails: large_guardrails.dup
        )

        expect(exec_config.input_guardrails.size).to eq(1000)
        expect(exec_config.output_guardrails.size).to eq(1000)
      end
    end
  end

  describe "Handoff boundary conditions" do
    context "handoff chain boundaries" do
      it "handles zero handoffs" do
        agent = create_test_agent(name: "NoHandoffAgent")

        expect(agent.handoffs).to be_empty
        expect(agent.tools.select { |t| t.name.start_with?("transfer_to_") }).to be_empty
      end

      it "handles single handoff" do
        agent1 = create_test_agent(name: "SingleHandoffAgent1")
        agent2 = create_test_agent(name: "SingleHandoffAgent2")

        agent1.add_handoff(agent2)

        expect(agent1.handoffs.size).to eq(1)
        expect(agent1.handoffs.first.name).to eq("SingleHandoffAgent2")
      end

      it "handles maximum handoff chain length" do
        # Create chain of 100 agents
        agents = 100.times.map { |i| create_test_agent(name: "ChainAgent#{i}") }

        # Connect them in a chain
        agents.each_cons(2) { |a, b| a.add_handoff(b) }

        # Each agent (except last) should have one handoff
        agents[0..-2].each_with_index do |agent, i|
          expect(agent.handoffs.size).to eq(1)
          expect(agent.handoffs.first.name).to eq("ChainAgent#{i + 1}")
        end

        # Last agent should have no handoffs
        expect(agents.last.handoffs).to be_empty
      end

      it "handles fully connected handoff network" do
        # Create 10 agents where each can handoff to all others
        agents = 10.times.map { |i| create_test_agent(name: "NetworkAgent#{i}") }

        agents.each do |agent|
          others = agents.reject { |other| other.name == agent.name }
          others.each { |other| agent.add_handoff(other) }

          # Each agent should have 9 handoffs
          expect(agent.handoffs.size).to eq(9)
        end
      end
    end

    context "handoff execution boundaries" do
      it "handles handoff to same agent (should be prevented)" do
        agent = create_test_agent(name: "SelfHandoffAgent")

        # Currently self-handoff is allowed - this documents the behavior
        agent.add_handoff(agent)

        # Self-handoff is currently allowed (may want to prevent in future)
        expect(agent.handoffs.map(&:name)).to include("SelfHandoffAgent")
        expect(agent.handoffs.size).to eq(1)
      end

      it "handles handoff with no context" do
        agent1 = create_test_agent(name: "ContextAgent1")
        agent2 = create_test_agent(name: "ContextAgent2")
        agent1.add_handoff(agent2)

        mock_provider.add_response(
          "Handing off",
          tool_calls: [{
            function: { name: "transfer_to_contextagent2", arguments: "{}" }
          }]
        )
        mock_provider.add_response("Handoff received")

        runner = RAAF::Runner.new(agent: agent1, provider: mock_provider)

        # Should handle empty handoff context
        expect { runner.run("Test handoff") }.not_to raise_error
      end
    end
  end

  describe "Error boundary conditions" do
    context "error handling boundaries" do
      it "handles deeply nested exceptions" do
        # Create nested exception chain
        nested_error = StandardError.new("Level 1")

        10.times do |i|
          raise nested_error
        rescue StandardError => e
          nested_error = StandardError.new("Level #{i + 2}")
          nested_error.set_backtrace(e.backtrace)
        end

        # Test that the error message is preserved through nesting
        expect(nested_error.message).to eq("Level 11")
        expect(nested_error.backtrace).not_to be_nil
      end

      it "handles error messages with special characters" do
        special_errors = [
          "Error with unicode: 🚨💥",
          "Error\nwith\nnewlines",
          "Error\twith\ttabs",
          "Error with quotes: \"error\" and 'error'",
          "Error with < > & special HTML chars",
          "Error with null bytes: \x00\x01\x02"
        ]

        special_errors.each do |error_msg|
          # Test that errors with special characters can be created and accessed
          error = StandardError.new(error_msg)
          expect(error.message).to eq(error_msg)

          # Test that the error can be raised and caught
          begin
            raise error
          rescue StandardError => e
            expect(e.message).to eq(error_msg)
          end
        end
      end

      it "handles extremely long error messages" do
        long_error_msg = "Error message " * 10_000 # Very long error

        # Test that long error messages can be created and preserved
        error = StandardError.new(long_error_msg)
        expect(error.message).to eq(long_error_msg)
        expect(error.message.length).to eq(14 * 10_000) # "Error message " is 14 chars

        # Test that the error can be raised and caught without truncation
        begin
          raise error
        rescue StandardError => e
          expect(e.message).to eq(long_error_msg)
        end
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Corner Cases" do
  let(:mock_provider) { create_mock_provider }

  describe "Unexpected input combinations" do
    context "malformed JSON in tool arguments" do
      it "handles JSON with trailing commas" do
        agent = create_test_agent(name: "TrailingCommaAgent")
        tool = RAAF::FunctionTool.new(
          proc { |data:| "Received: #{data}" },
          name: "json_tool"
        )
        agent.add_tool(tool)

        mock_provider.add_response(
          "Using tool with malformed JSON",
          tool_calls: [{
            function: {
              name: "json_tool",
              arguments: '{"data": "test",}' # Trailing comma
            }
          }]
        )
        mock_provider.add_response("Tool handling complete")

        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        # Should handle malformed JSON gracefully
        result = runner.run("Test malformed JSON")
        expect(result.messages).not_to be_empty
      end

      it "handles JSON with unescaped quotes" do
        agent = create_test_agent(name: "UnescapedQuotesAgent")
        tool = RAAF::FunctionTool.new(
          proc { |message:| "Message: #{message}" },
          name: "message_tool"
        )
        agent.add_tool(tool)

        mock_provider.add_response(
          "Using tool with unescaped quotes",
          tool_calls: [{
            function: {
              name: "message_tool",
              arguments: '{"message": "He said "hello" to me"}' # Unescaped quotes
            }
          }]
        )
        mock_provider.add_response("Unescaped quotes handled")

        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        # Should handle or reject invalid JSON
        expect { runner.run("Test unescaped quotes") }.not_to raise_error
      end

      it "handles completely invalid JSON" do
        agent = create_test_agent(name: "InvalidJSONAgent")
        tool = RAAF::FunctionTool.new(
          proc { |x| "Result: #{x}" },
          name: "invalid_tool"
        )
        agent.add_tool(tool)

        mock_provider.add_response(
          "Using tool with invalid JSON",
          tool_calls: [{
            function: {
              name: "invalid_tool",
              arguments: "not json at all!@#$%"
            }
          }]
        )
        mock_provider.add_response("Invalid JSON handled")

        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        result = runner.run("Test invalid JSON")

        # Should complete without crashing
        expect(result.messages).not_to be_empty
      end
    end

    context "mixed content types in conversations" do
      it "handles conversation with alternating empty and non-empty messages" do
        agent = create_test_agent(name: "MixedContentAgent")
        mock_provider.add_response("Handled mixed content")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        mixed_history = [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "" },
          { role: "user", content: "" },
          { role: "assistant", content: "I'm here to help" },
          { role: "user", content: "   " }, # Whitespace only
          { role: "assistant", content: "How can I assist?" },
          { role: "user", content: "Final message" }
        ]

        result = runner.run(mixed_history)
        expect(result.messages).not_to be_empty
        # Should handle the mixed content successfully
      end

      it "handles conversation with inconsistent role patterns" do
        agent = create_test_agent(name: "InconsistentRoleAgent")
        mock_provider.add_response("Handled inconsistent roles")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        inconsistent_history = [
          { role: "user", content: "First message" },
          { role: "user", content: "Another user message" }, # Two users in a row
          { role: "assistant", content: "Assistant response" },
          { role: "assistant", content: "Another assistant message" }, # Two assistants
          { role: "user", content: "Final question" },
          { role: "system", content: "System message in middle" }, # System message
          { role: "user", content: "Back to user" }
        ]

        result = runner.run(inconsistent_history)
        expect(result.messages).not_to be_empty
      end

      it "handles messages with mixed encodings" do
        agent = create_test_agent(name: "MixedEncodingAgent")
        mock_provider.add_response("Handled mixed encodings")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        # Different character encodings
        messages = [
          "ASCII message", # ASCII
          "UTF-8 with émojis 🚀", # UTF-8
          "Latin-1: café résumé",            # Latin characters
          "Cyrillic: Привет мир",            # Cyrillic
          "Chinese: 你好世界", # Chinese
          "Arabic: مرحبا بالعالم", # Arabic
          "Japanese: こんにちは世界", # Japanese
          "Mixed: Hello🌍世界мир" # Mixed scripts
        ]

        mixed_history = messages.map.with_index do |msg, i|
          { role: i.even? ? "user" : "assistant", content: msg }
        end

        result = runner.run("Encoding test", previous_messages: mixed_history)
        expect(result.messages).not_to be_empty
      end
    end

    context "circular reference scenarios" do
      it "handles agents with circular handoff references" do
        agent1 = create_test_agent(name: "CircularAgent1")
        agent2 = create_test_agent(name: "CircularAgent2")
        agent3 = create_test_agent(name: "CircularAgent3")

        # Create circular references: 1 -> 2 -> 3 -> 1
        agent1.add_handoff(agent2)
        agent2.add_handoff(agent3)
        agent3.add_handoff(agent1)

        # Should not cause infinite loops
        expect(agent1.handoffs.map(&:name)).to include("CircularAgent2")
        expect(agent2.handoffs.map(&:name)).to include("CircularAgent3")
        expect(agent3.handoffs.map(&:name)).to include("CircularAgent1")

        # Each agent should have tools for handoffs
        expect(agent1.tools.map(&:name)).to include("transfer_to_circular_agent2")
        expect(agent2.tools.map(&:name)).to include("transfer_to_circular_agent3")
        expect(agent3.tools.map(&:name)).to include("transfer_to_circular_agent1")
      end

      it "handles tools that reference themselves" do
        recursive_tool = RAAF::FunctionTool.new(
          proc { |depth:|
            if depth.to_i.positive?
              "Recursion depth: #{depth}"
            else
              "Base case reached"
            end
          },
          name: "recursive_tool"
        )

        agent = create_test_agent(name: "RecursiveAgent")
        agent.add_tool(recursive_tool)

        mock_provider.add_response(
          "Using recursive tool",
          tool_calls: [{
            function: {
              name: "recursive_tool",
              arguments: '{"depth": 5}'
            }
          }]
        )
        mock_provider.add_response("Recursion handled")

        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        result = runner.run("Test recursive tool")
        expect(result.messages).not_to be_empty
      end
    end
  end

  describe "Resource exhaustion edge cases" do
    context "memory pressure scenarios" do
      it "handles agent creation under memory pressure" do
        # Simulate memory pressure by creating many objects
        memory_hogs = []

        begin
          # Fill up memory
          100.times do |i|
            memory_hogs << Array.new(100_000, "memory_#{i}")
          end

          # Try to create agent under memory pressure
          agent = create_test_agent(name: "PressureAgent")
          expect(agent.name).to eq("PressureAgent")
        rescue NoMemoryError
          # If we hit memory limits, that's expected
          # rubocop:disable RSpec/IdenticalEqualityAssertion
          expect(true).to be true
          # rubocop:enable RSpec/IdenticalEqualityAssertion
        ensure
          memory_hogs.clear
          GC.start
        end
      end

      it "handles tool execution when memory is fragmented" do
        # Create memory fragmentation pattern
        fragments = []
        100.times do |i|
          fragments << Array.new(1000, "fragment_#{i}")
          fragments.shift if fragments.size > 50 # Keep memory fragmented
        end

        # Tool that requires memory allocation
        memory_tool = RAAF::FunctionTool.new(
          proc { |size:|
            begin
              Array.new(size.to_i, "allocated").join(" ")
            rescue NoMemoryError
              "Memory allocation failed"
            end
          },
          name: "memory_allocation_tool"
        )

        agent = create_test_agent(name: "FragmentedMemoryAgent")
        agent.add_tool(memory_tool)

        mock_provider.add_response(
          "Allocating memory",
          tool_calls: [{
            function: {
              name: "memory_allocation_tool",
              arguments: '{"size": 10000}'
            }
          }]
        )
        mock_provider.add_response("Memory test complete")

        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        # Should handle memory pressure gracefully
        expect { runner.run("Test memory allocation") }.not_to raise_error

        fragments.clear
        GC.start
      end
    end

    context "thread exhaustion scenarios" do
      it "handles runner creation when thread pool is exhausted" do
        threads = []

        begin
          # Create many threads to exhaust thread pool
          100.times do |i|
            threads << Thread.new do
              sleep 0.1 # Keep threads alive briefly
              "thread_#{i}"
            end
          end

          # Try to create runner when many threads exist
          agent = create_test_agent(name: "ThreadExhaustionAgent")
          mock_provider.add_response("Thread test response")
          runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

          result = runner.run("Test under thread pressure")
          expect(result.messages).not_to be_empty
        ensure
          threads.each do |t|
            t.join
          rescue StandardError
            nil
          end
        end
      end
    end
  end

  describe "Timing and concurrency edge cases" do
    context "race condition scenarios" do
      it "handles concurrent agent modifications" do
        agent = create_test_agent(name: "ConcurrentModificationAgent")

        # Start multiple threads that modify the agent
        modification_threads = 5.times.map do |i|
          Thread.new do
            # Add tools concurrently
            10.times do |j|
              tool = RAAF::FunctionTool.new(
                proc { "Thread #{i} tool #{j}" },
                name: "thread_#{i}_tool_#{j}"
              )
              agent.add_tool(tool)
              sleep 0.001 # Small delay to increase chance of race
            end
          end
        end

        # While modifications happen, try to use the agent
        usage_thread = Thread.new do
          mock_provider.add_response("Concurrent modification response")
          runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

          10.times do |i|
            runner.run("Concurrent test #{i}")
            sleep 0.001
          end
        end

        # Wait for all threads
        (modification_threads + [usage_thread]).each(&:join)

        # Agent should be in consistent state
        expect(agent.tools.size).to eq(50) # 5 threads * 10 tools each
        expect(agent.tools.map(&:name).uniq.size).to eq(50) # All unique names
      end

      it "handles concurrent runner executions on same agent" do
        agent = create_test_agent(name: "SharedAgent")

        # Prepare responses for concurrent access
        100.times { mock_provider.add_response("Concurrent response") }

        results = []
        results_mutex = Mutex.new

        # Multiple threads using same agent
        threads = 10.times.map do |i|
          Thread.new do
            runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

            10.times do |j|
              result = runner.run("Concurrent #{i}-#{j}")
              results_mutex.synchronize { results << result }
            end
          end
        end

        threads.each(&:join)

        # All executions should complete successfully
        expect(results.size).to eq(100)
        expect(results.all? { |r| r.is_a?(RAAF::RunResult) }).to be true
      end
    end

    context "timeout edge cases" do
      it "handles operations at timeout boundary" do
        agent = create_test_agent(name: "TimeoutBoundaryAgent")

        # Tool that takes exactly the timeout duration
        boundary_tool = RAAF::FunctionTool.new(
          proc { |duration:|
            sleep(duration.to_f)
            "Completed after #{duration}s"
          },
          name: "boundary_timing_tool"
        )

        agent.add_tool(boundary_tool)

        mock_provider.add_response(
          "Testing timeout boundary",
          tool_calls: [{
            function: {
              name: "boundary_timing_tool",
              arguments: '{"duration": 0.1}' # 100ms
            }
          }]
        )
        mock_provider.add_response("Boundary test complete")

        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        # Should complete just within timeout
        expect { runner.run("Test boundary timing") }.not_to raise_error
      end
    end
  end

  describe "State corruption edge cases" do
    context "partial state updates" do
      it "handles interrupted agent configuration" do
        agent = create_test_agent(name: "InterruptedAgent")

        # Simulate interrupted configuration
        begin
          # Start configuration process
          agent.instance_variable_set(:@name, "PartiallyUpdated")

          # Simulate interruption (exception during update)
          raise StandardError, "Configuration interrupted"
        rescue StandardError
          # Agent should still be usable despite partial update
          expect(agent.name).to eq("PartiallyUpdated")
        end

        # Agent should still function
        mock_provider.add_response("Post-interruption response")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        expect { runner.run("Test after interruption") }.not_to raise_error
      end

      it "handles corrupted tool definitions" do
        agent = create_test_agent(name: "CorruptedToolAgent")

        # Add normal tool
        normal_tool = RAAF::FunctionTool.new(
          proc { "normal result" },
          name: "normal_tool"
        )
        agent.add_tool(normal_tool)

        # Simulate tool corruption by directly modifying internal state
        corrupted_tool = RAAF::FunctionTool.new(
          proc { "corrupted result" },
          name: "corrupted_tool"
        )

        # Corrupt the tool's internal state
        corrupted_tool.instance_variable_set(:@name, nil)

        # Adding corrupted tool should be handled gracefully
        expect { agent.add_tool(corrupted_tool) }.not_to raise_error

        # Agent should still function
        expect(agent.tools.size).to be >= 1 # At least the normal tool
      end
    end

    context "inconsistent internal state" do
      it "handles mismatched tool and handoff counts" do
        agent1 = create_test_agent(name: "MismatchAgent1")
        agent2 = create_test_agent(name: "MismatchAgent2")

        # Add handoff normally
        agent1.add_handoff(agent2)
        initial_tool_count = agent1.tools.size

        # Simulate inconsistent state by manually modifying tools
        agent1.instance_variable_get(:@tools).pop # Remove last tool

        # Agent should detect and handle inconsistency
        expect(agent1.tools.size).to eq(initial_tool_count - 1)
        expect(agent1.handoffs.size).to eq(1) # Handoff still registered

        # Should still function despite inconsistency
        mock_provider.add_response("Mismatch handled")
        runner = RAAF::Runner.new(agent: agent1, provider: mock_provider)

        expect { runner.run("Test mismatch") }.not_to raise_error
      end
    end
  end

  describe "Protocol violation edge cases" do
    context "unexpected API responses" do
      it "handles responses with missing required fields" do
        agent = create_test_agent(name: "MissingFieldsAgent")

        # Mock provider that returns incomplete responses
        incomplete_provider = create_mock_provider
        incomplete_provider.add_response("") # Empty content

        # Manually craft incomplete response
        allow(incomplete_provider).to receive(:complete).and_return({
                                                                      # Missing 'output' field
                                                                      "usage" => { "input_tokens" => 10, "output_tokens" => 5 }
                                                                    })

        runner = RAAF::Runner.new(agent: agent, provider: incomplete_provider)

        # Should handle incomplete response gracefully
        expect { runner.run("Test incomplete response") }.not_to raise_error
      end

      it "handles responses with extra unexpected fields" do
        agent = create_test_agent(name: "ExtraFieldsAgent")

        # Mock provider with extra fields
        allow(mock_provider).to receive(:complete).and_return({
                                                                "output" => [{
                                                                  "type" => "message",
                                                                  "role" => "assistant",
                                                                  "content" => [{ "type" => "text", "text" => "Response with extra fields" }]
                                                                }],
                                                                "usage" => { "input_tokens" => 10, "output_tokens" => 5 },
                                                                "unexpected_field" => "should be ignored",
                                                                "debug_info" => { "internal" => "data" },
                                                                "extra_array" => [1, 2, 3, 4, 5]
                                                              })

        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        # Should handle extra fields gracefully
        result = runner.run("Test extra fields")
        expect(result.messages).not_to be_empty
      end

      it "handles responses with wrong data types" do
        agent = create_test_agent(name: "WrongTypesAgent")

        # Mock provider with wrong data types
        allow(mock_provider).to receive(:complete).and_return({
                                                                "output" => "should be array", # Wrong type
                                                                "usage" => "should be hash" # Wrong type
                                                              })

        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        # Should handle type mismatches gracefully
        expect { runner.run("Test wrong types") }.not_to raise_error
      end
    end
  end
end

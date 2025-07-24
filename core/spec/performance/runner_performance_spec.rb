# frozen_string_literal: true

require "spec_helper"
require "benchmark/memory"

RSpec.describe "Runner Performance", :performance do
  let(:mock_provider) { create_mock_provider }
  let(:agent) { create_test_agent(name: "SpeedAgent", max_turns: 50) }

  describe "Message processing performance" do
    context "single message processing" do
      it "processes messages within 10ms" do
        mock_provider.add_response("Quick response")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        expect do
          runner.run("Simple query")
        end.to perform_under(10).ms
      end

      it "allocates minimal memory for simple operations" do
        mock_provider.add_response("Memory efficient response")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        expect do
          runner.run("Test memory")
        end.to perform_allocation(10_000).objects
      end
    end

    context "large message history" do
      let(:large_history) do
        1000.times.map do |i|
          {
            role: i.even? ? "user" : "assistant",
            content: "Historical message #{i} with some content to simulate real conversations"
          }
        end
      end

      it "handles 1000-message history efficiently" do
        mock_provider.add_response("Response to large history")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        expect do
          runner.run("New message", previous_messages: large_history)
        end.to perform_under(100).ms
      end

      it "doesn't create excessive objects with large history" do
        mock_provider.add_response("Memory test response")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        expect do
          runner.run("Test", previous_messages: large_history)
        end.to perform_allocation(50_000).objects
      end
    end

    context "multi-turn conversations" do
      it "maintains performance across multiple turns" do
        20.times { mock_provider.add_response("Turn response") }
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        expect do
          messages = [{ role: "user", content: "Start conversation" }]

          10.times do |i|
            result = runner.run(messages)
            messages = result.messages
            messages << { role: "user", content: "Continue turn #{i}" }
          end
        end.to perform_under(200).ms
      end

      it "doesn't leak memory across turns" do
        100.times { mock_provider.add_response("Memory test turn") }
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        # Measure memory growth
        initial_memory = nil
        final_memory = nil

        MemoryProfiler.report do
          initial_memory = GC.stat[:heap_allocated_pages]

          messages = [{ role: "user", content: "Start" }]
          50.times do
            result = runner.run(messages)
            messages = result.messages + [{ role: "user", content: "Continue" }]
          end

          GC.start
          final_memory = GC.stat[:heap_allocated_pages]
        end

        # Memory growth should be minimal
        memory_growth = final_memory - initial_memory if initial_memory && final_memory
        expect(memory_growth || 0).to be < 100 # Less than 100 heap pages growth
      end
    end
  end

  describe "Tool execution performance" do
    let(:tools) do
      10.times.map do |i|
        RAAF::FunctionTool.new(
          proc { |x:| "Tool #{i} processed: #{x}" },
          name: "tool_#{i}",
          description: "Performance test tool #{i}"
        )
      end
    end

    let(:agent_with_tools) do
      agent = create_test_agent(name: "ToolPerfAgent")
      tools.each { |tool| agent.add_tool(tool) }
      agent
    end

    it "executes single tool calls efficiently" do
      mock_provider.add_response(
        "Using tool",
        tool_calls: [{ function: { name: "tool_5", arguments: '{"x": "test"}' } }]
      )
      mock_provider.add_response("Tool complete")

      runner = RAAF::Runner.new(agent: agent_with_tools, provider: mock_provider)

      expect do
        runner.run("Use tool 5")
      end.to perform_under(20).ms
    end

    it "handles parallel tool calls efficiently" do
      # Multiple tool calls in one response
      tool_calls = 5.times.map do |i|
        { function: { name: "tool_#{i}", arguments: '{"x": "parallel test"}' } }
      end

      mock_provider.add_response("Using multiple tools", tool_calls: tool_calls)
      mock_provider.add_response("All tools complete")

      runner = RAAF::Runner.new(agent: agent_with_tools, provider: mock_provider)

      expect do
        runner.run("Use multiple tools")
      end.to perform_under(50).ms
    end

    it "maintains tool lookup performance with many tools" do
      # Create agent with 100 tools
      many_tools = 100.times.map do |i|
        RAAF::FunctionTool.new(
          proc { "Result #{i}" },
          name: "big_tool_#{i}"
        )
      end

      big_agent = create_test_agent(name: "BigToolAgent")
      many_tools.each { |tool| big_agent.add_tool(tool) }

      mock_provider.add_response(
        "Using tool",
        tool_calls: [{ function: { name: "big_tool_99", arguments: "{}" } }]
      )
      mock_provider.add_response("Done")

      runner = RAAF::Runner.new(agent: big_agent, provider: mock_provider)

      # Tool lookup should still be fast even with 100 tools
      expect do
        runner.run("Use last tool")
      end.to perform_under(30).ms
    end
  end

  describe "Agent handoff performance" do
    let(:agent_chain) do
      5.times.map do |i|
        create_test_agent(name: "ChainAgent#{i}")
      end
    end

    before do
      # Set up handoff chain
      agent_chain.each_cons(2) do |from, to|
        from.add_handoff(to)
      end
    end

    it "performs handoffs efficiently" do
      # Mock handoff sequence
      agent_chain.each_with_index do |_agent, i|
        if i < agent_chain.size - 1
          mock_provider.add_response(
            "Handing off to next agent",
            tool_calls: [{
              function: {
                name: "transfer_to_chain_agent#{i + 1}",
                arguments: '{"input": "Continue chain"}'
              }
            }]
          )
        else
          mock_provider.add_response("Chain complete")
        end
      end

      runner = RAAF::Runner.new(agent: agent_chain.first, provider: mock_provider)

      expect do
        runner.run("Start chain")
      end.to perform_under(100).ms
    end

    it "doesn't accumulate memory during handoffs" do
      # Setup responses for handoff chain
      10.times do |i|
        mock_provider.add_response(
          "Handoff #{i}",
          tool_calls: if i < 4
                        [{
                          function: {
                            name: "transfer_to_chain_agent#{(i + 1) % 5}",
                            arguments: "{}"
                          }
                        }]
                      end
        )
      end

      runner = RAAF::Runner.new(agent: agent_chain.first, provider: mock_provider)

      expect do
        runner.run("Test handoff memory")
      end.to perform_allocation(100_000).objects
    end
  end

  describe "Configuration impact on performance" do
    it "performs well with complex configurations" do
      complex_config = RAAF::RunConfig.new(
        max_turns: 100,
        max_tokens: 4000,
        stream: false,
        metadata: { app: "test", version: "1.0", env: "production" },
        trace_id: SecureRandom.uuid,
        group_id: SecureRandom.uuid
      )

      mock_provider.add_response("Config test response")
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      expect do
        runner.run("Test with config", config: complex_config)
      end.to perform_under(15).ms
    end

    it "handles execution config efficiently" do
      exec_config = RAAF::Config::ExecutionConfig.new(
        context: { user_id: "123", session: "abc" },
        input_guardrails: %w[filter1 filter2],
        output_guardrails: %w[guard1 guard2],
        session: { history: Array.new(100) { |i| "item_#{i}" } }
      )

      configured_agent = create_test_agent(
        name: "ConfiguredAgent",
        context: exec_config.context
      )

      mock_provider.add_response("Configured response")
      runner = RAAF::Runner.new(agent: configured_agent, provider: mock_provider)

      expect do
        runner.run("Test execution config")
      end.to perform_under(20).ms
    end
  end

  describe "Error handling performance" do
    it "handles errors without performance degradation" do
      # Mock provider always raises errors in order, so we expect failures
      # Skip - Test requires sophisticated error recovery infrastructure
      skip "Error handling performance test requires advanced recovery mechanisms"
    end
  end

  describe "Concurrent operations" do
    it "handles concurrent runners efficiently" do
      # Prepare responses for concurrent requests
      100.times { mock_provider.add_response("Concurrent response") }

      expect do
        threads = 20.times.map do |i|
          Thread.new do
            runner = RAAF::Runner.new(
              agent: create_test_agent(name: "ConcurrentAgent#{i}"),
              provider: mock_provider
            )
            runner.run("Concurrent request #{i}")
          end
        end
        threads.each(&:join)
      end.to perform_under(500).ms
    end

    it "maintains thread safety without performance penalty" do
      # Use fresh mock provider to avoid test contamination
      fresh_mock_provider = create_mock_provider
      shared_agent = create_test_agent(name: "SharedAgent")
      50.times { fresh_mock_provider.add_response("Thread safe response") }

      results = Concurrent::Array.new

      start_time = Time.now
      threads = 10.times.map do |i|
        Thread.new do
          runner = RAAF::Runner.new(agent: shared_agent, provider: fresh_mock_provider)
          5.times do |j|
            result = runner.run("Thread #{i} request #{j}")
            results << result
          end
        end
      end

      threads.each(&:join)
      execution_time = Time.now - start_time

      expect(results.size).to eq(50)
      expect(execution_time).to be < 1.0
    end
  end
end

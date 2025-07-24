# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Stress Testing", :performance do
  let(:mock_provider) { create_mock_provider }

  describe "Extreme load scenarios" do
    it "handles 10,000 rapid fire requests" do
      # Prepare massive number of responses
      10_000.times { |i| mock_provider.add_response("Stress response #{i}") }

      agent = create_test_agent(name: "StressAgent")
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      results = []
      errors = []

      start_time = Time.now

      10_000.times do |i|
        results << runner.run("Stress test #{i}")
      rescue StandardError => e
        errors << { index: i, error: e }
      end

      end_time = Time.now
      duration = end_time - start_time

      # Should complete without errors
      expect(errors).to be_empty
      expect(results.size).to eq(10_000)

      # Should maintain reasonable throughput (>100 req/sec)
      throughput = 10_000.0 / duration
      expect(throughput).to be > 100

      puts "Stress test: #{throughput.round(2)} requests/second"
    end

    it "survives resource exhaustion scenarios" do
      agent = create_test_agent(name: "ExhaustionAgent", max_turns: 1000)

      # Create responses that use lots of memory
      1000.times do |i|
        # Large response content
        large_content = "Large response #{i} " + ("x" * 10_000)
        mock_provider.add_response(large_content)
      end

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      successful_runs = 0
      memory_errors = 0

      1000.times do |i|
        runner.run("Exhaustion test #{i}")
        successful_runs += 1

        # Force garbage collection periodically
        GC.start if (i % 100).zero?
      rescue NoMemoryError, SystemStackError
        memory_errors += 1
      end

      # Should handle most requests despite memory pressure
      success_rate = successful_runs.to_f / 1000
      expect(success_rate).to be > 0.8 # At least 80% success rate

      # Some memory errors are acceptable under extreme stress
      expect(memory_errors).to be < 200 # Less than 20% memory errors

      puts "Resource exhaustion: #{(success_rate * 100).round(1)}% success rate"
    end
  end

  describe "Pathological input handling" do
    it "handles extremely long messages" do
      agent = create_test_agent(name: "LongMessageAgent")
      mock_provider.add_response("Processed long message")
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      # Create progressively longer messages
      message_sizes = [1_000, 10_000, 100_000, 500_000]

      message_sizes.each do |size|
        long_message = "x" * size

        start_time = Time.now
        result = runner.run(long_message)
        end_time = Time.now

        # Should handle long messages without timeout
        expect(end_time - start_time).to be < 5.0
        expect(result.messages).not_to be_empty

        puts "Long message (#{size} chars): #{((end_time - start_time) * 1000).round(2)}ms"
      end
    end

    it "handles deeply nested conversation history" do
      agent = create_test_agent(name: "DeepHistoryAgent")
      mock_provider.add_response("Response to deep history")
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      # Create deeply nested conversation
      deep_history = []

      # Build conversation with 1000 turns
      1000.times do |i|
        deep_history << { role: "user", content: "User message #{i}" }
        deep_history << { role: "assistant", content: "Assistant response #{i}" }
      end

      # Should handle deep history without stack overflow
      expect do
        result = runner.run("New message", previous_messages: deep_history)
        # Mock provider will return minimal response, just check it doesn't crash
        expect(result.messages.size).to be >= 2 # At least user message and response
      end.not_to raise_error
    end

    it "handles malformed or adversarial inputs" do
      agent = create_test_agent(name: "AdversarialAgent")
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      adversarial_inputs = [
        # Special characters and encoding issues
        "\u0000\u0001\u0002\u0003null bytes",
        "Unicode test: 🚀🎭🎪#{"\u{1F600}" * 100}",
        ("emoji" * 1000) + ("🚀" * 1000),

        # Potential injection attempts
        "<script>alert('xss')</script>",
        "'; DROP TABLE users; --",
        "{{7*7}}#{7 * 7}${7*7}%{7*7}#{"7" * 7}",

        # Resource exhaustion attempts
        "A" * 1_000_000, # 1MB string
        "#{"nested " * 10_000}structure",

        # Malformed JSON-like strings
        '{"unclosed": "object"',
        '[{"nested": [{"deep": {"very": "deep"}}]}]' * 1000,

        # Control characters
        "\r\n" * 10_000,
        "\t" * 10_000,
        "\b\f\v" * 1000
      ]

      successful_handles = 0

      adversarial_inputs.each_with_index do |input, i|
        mock_provider.add_response("Handled adversarial input #{i}")

        begin
          result = runner.run(input)
          successful_handles += 1

          # Result should be safe
          expect(result.messages).to be_an(Array)
          expect(result.messages.last[:content]).to be_a(String)
        rescue StandardError => e
          # Some failures are acceptable, but should not crash
          expect(e).not_to be_a(SystemStackError)
          expect(e).not_to be_a(NoMemoryError)
        end
      end

      # Should handle most adversarial inputs gracefully
      success_rate = successful_handles.to_f / adversarial_inputs.size
      expect(success_rate).to be > 0.7 # At least 70% handled safely

      puts "Adversarial input handling: #{(success_rate * 100).round(1)}% success rate"
    end
  end

  describe "Concurrent stress scenarios" do
    it "handles 100 concurrent agents with tool execution" do
      # Create many agents with tools
      agents = 100.times.map do |i|
        agent = create_test_agent(name: "ConcurrentAgent#{i}")

        # Add tools to each agent
        tool = RAAF::FunctionTool.new(
          proc { |data:|
            # Simulate work
            sleep(0.001)
            "Agent #{i} processed: #{data}"
          },
          name: "concurrent_tool_#{i}"
        )
        agent.add_tool(tool)
        agent
      end

      # Prepare responses for all agents
      200.times do |i|
        agent_idx = i % 100
        mock_provider.add_response(
          "Using concurrent tool",
          tool_calls: [{
            function: {
              name: "concurrent_tool_#{agent_idx}",
              arguments: JSON.generate({ data: "concurrent test #{i}" })
            }
          }]
        )
        mock_provider.add_response("Concurrent tool complete")
      end

      results = Concurrent::Array.new
      errors = Concurrent::Array.new

      # Launch concurrent operations
      threads = agents.map.with_index do |agent, i|
        Thread.new do
          runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

          2.times do |j|
            result = runner.run("Concurrent stress test #{i}-#{j}")
            results << result
          rescue StandardError => e
            errors << { agent: i, iteration: j, error: e }
          end
        end
      end

      # Wait for all to complete
      threads.each(&:join)

      # Should complete successfully
      expect(errors).to be_empty
      expect(results.size).to eq(200)

      # All agents should have produced results
      agent_results = results.group_by { |r| r.last_agent.name }.keys
      expect(agent_results.size).to eq(100)
    end

    it "survives thread contention and deadlock scenarios" do
      shared_resource = Mutex.new
      counter = Concurrent::AtomicFixnum.new(0)

      # Create agents that compete for shared resources
      agents = 20.times.map { |i| create_test_agent(name: "ContentionAgent#{i}") }

      # Prepare responses
      1000.times { mock_provider.add_response("Contention response") }

      completed_operations = Concurrent::AtomicFixnum.new(0)

      # Create threads that compete for resources
      threads = agents.map.with_index do |agent, i|
        Thread.new do
          runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

          25.times do |j|
            # Simulate resource contention
            shared_resource.synchronize do
              current = counter.value

              # Simulate work while holding lock
              runner.run("Contention test #{i}-#{j}")

              counter.update { current + 1 }
              completed_operations.increment
            end
          end
        end
      end

      # Set timeout to detect deadlocks
      timeout_occurred = false
      begin
        Timeout.timeout(30) do # 30 second timeout
          threads.each(&:join)
        end
      rescue Timeout::Error
        timeout_occurred = true
        threads.each(&:kill) # Force kill hanging threads
      end

      # Should complete without deadlock
      expect(timeout_occurred).to be false
      expect(completed_operations.value).to eq(500) # 20 agents * 25 operations
    end
  end

  describe "System resource stress" do
    it "handles file descriptor exhaustion scenarios" do
      agent = create_test_agent(name: "FDStressAgent")

      # Create many runners (each might use file descriptors)
      runners = []
      results = []

      begin
        # Try to create many runners to stress file descriptors
        500.times do |i|
          mock_provider.add_response("FD stress response #{i}")
          runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
          runners << runner

          result = runner.run("FD stress test #{i}")
          results << result
        end

        # Should handle many simultaneous runners
        expect(results.size).to eq(500)
      rescue Errno::EMFILE, Errno::ENFILE
        # Some systems may hit FD limits - that's acceptable
        # But should still have processed a reasonable number
        expect(results.size).to be > 100

        puts "FD exhaustion at #{results.size} runners (expected on some systems)"
      end
    end

    it "handles CPU intensive operations gracefully" do
      # Create CPU-intensive tool
      cpu_tool = RAAF::FunctionTool.new(
        proc { |iterations:|
          # CPU-intensive calculation
          sum = 0
          iterations.to_i.times { |i| sum += Math.sqrt(i) }
          sum.round(2)
        },
        name: "cpu_intensive_tool"
      )

      agent = create_test_agent(name: "CPUStressAgent")
      agent.add_tool(cpu_tool)

      # Prepare responses for CPU stress test
      20.times do |_i|
        mock_provider.add_response(
          "Running CPU intensive task",
          tool_calls: [{
            function: {
              name: "cpu_intensive_tool",
              arguments: JSON.generate({ iterations: 10_000 })
            }
          }]
        )
        mock_provider.add_response("CPU task complete")
      end

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      # Run CPU intensive operations concurrently
      threads = 5.times.map do |i|
        Thread.new do
          4.times do |j|
            runner.run("CPU stress test #{i}-#{j}")
          end
        end
      end

      start_time = Time.now
      threads.each(&:join)
      end_time = Time.now

      # Should complete within reasonable time even under CPU load
      expect(end_time - start_time).to be < 60.0 # 1 minute max

      puts "CPU stress test completed in #{(end_time - start_time).round(2)} seconds"
    end
  end
end

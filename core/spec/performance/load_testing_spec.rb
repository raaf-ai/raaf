# frozen_string_literal: true

require "spec_helper"
require "benchmark"

RSpec.describe "Load Testing", :performance do
  let(:mock_provider) { create_mock_provider }

  describe "High volume request handling" do
    context "sustained load" do
      it "handles 1000 requests/minute sustainably" do
        # Prepare responses
        1000.times { mock_provider.add_response("Load test response") }

        agent = create_test_agent(name: "LoadAgent")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

        results = []
        errors = []

        duration = Benchmark.measure do
          1000.times do |i|
            results << runner.run("Load test #{i}")
          rescue StandardError => e
            errors << e
          end
        end

        # Should complete within 60 seconds (1000 req/min)
        expect(duration.real).to be < 60.0
        expect(errors).to be_empty
        expect(results.size).to eq(1000)
      end
    end

    context "burst load" do
      it "handles sudden burst of 100 concurrent requests" do
        # Prepare responses for burst
        100.times { mock_provider.add_response("Burst response") }

        agents = 100.times.map { |i| create_test_agent(name: "BurstAgent#{i}") }

        start_time = Time.now
        results = Concurrent::Array.new
        errors = Concurrent::Array.new

        # Launch all requests simultaneously
        barrier = Concurrent::CyclicBarrier.new(100)

        threads = agents.map.with_index do |agent, i|
          Thread.new do
            runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
            barrier.wait # Synchronize all threads

            begin
              results << runner.run("Burst request #{i}")
            rescue StandardError => e
              errors << e
            end
          end
        end

        threads.each(&:join)
        end_time = Time.now

        # Should handle burst within reasonable time
        expect(end_time - start_time).to be < 5.0
        expect(errors).to be_empty
        expect(results.size).to eq(100)
      end
    end

    context "gradual load increase" do
      it "scales gracefully from 10 to 100 concurrent users" do
        # Prepare ample responses
        1000.times { mock_provider.add_response("Scaling response") }

        errors = Concurrent::Array.new
        response_times = Concurrent::Array.new

        # Gradually increase load
        [10, 25, 50, 75, 100].each do |concurrent_users|
          threads = concurrent_users.times.map do |i|
            Thread.new do
              agent = create_test_agent(name: "ScaleAgent#{i}")
              runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

              start = Time.now
              begin
                runner.run("Scale test #{concurrent_users}-#{i}")
                response_times << (Time.now - start)
              rescue StandardError => e
                errors << { users: concurrent_users, error: e }
              end
            end
          end

          threads.each(&:join)

          # Brief pause between load levels
          sleep 0.1
        end

        # Should handle scaling without errors
        expect(errors).to be_empty

        # Response times should remain reasonable
        avg_response_time = response_times.sum / response_times.size
        expect(avg_response_time).to be < 0.1 # 100ms average
      end
    end
  end

  describe "Resource utilization under load" do
    it "maintains stable memory usage under sustained load" do
      # Prepare responses
      500.times { mock_provider.add_response("Memory load test") }

      agent = create_test_agent(name: "MemoryLoadAgent")
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      memory_samples = []

      # Sample memory usage during load
      500.times do |i|
        if (i % 50).zero?
          GC.start
          memory_samples << GC.stat[:heap_allocated_pages]
        end

        runner.run("Memory test #{i}")
      end

      # Memory should stabilize (not continuously grow)
      first_half_avg = memory_samples[0..4].sum / 5.0
      second_half_avg = memory_samples[5..9].sum / 5.0

      # Allow for some growth but should be minimal
      growth_percentage = ((second_half_avg - first_half_avg) / first_half_avg) * 100
      expect(growth_percentage).to be < 10 # Less than 10% growth
    end

    it "maintains stable response times under sustained load" do
      # Prepare responses
      1000.times { mock_provider.add_response("Stable response") }

      agent = create_test_agent(name: "StableAgent")
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      response_times = []

      1000.times do |i|
        start = Time.now
        runner.run("Stability test #{i}")
        response_times << (Time.now - start)
      end

      # Calculate percentiles
      sorted_times = response_times.sort
      p50 = sorted_times[500]  # 50th percentile
      p95 = sorted_times[950]  # 95th percentile
      p99 = sorted_times[990]  # 99th percentile

      # Response times should be consistent
      expect(p50).to be < 0.01   # 10ms median
      expect(p95).to be < 0.05   # 50ms for 95% of requests
      expect(p99).to be < 0.1    # 100ms for 99% of requests
    end
  end

  describe "Multi-agent load scenarios" do
    it "handles load with agent handoffs" do
      # Create agent network
      agents = 5.times.map { |i| create_test_agent(name: "LoadHandoffAgent#{i}") }
      agents.each_cons(2) { |a, b| a.add_handoff(b) }

      # Prepare handoff responses
      500.times do |i|
        agent_idx = i % 5
        if agent_idx < 4
          mock_provider.add_response(
            "Handoff from agent #{agent_idx}",
            tool_calls: [{
              function: {
                name: "transfer_to_loadhandoffagent#{agent_idx + 1}",
                arguments: "{}"
              }
            }]
          )
        else
          mock_provider.add_response("Final response from agent 4")
        end
      end

      results = Concurrent::Array.new

      # Run multiple handoff chains concurrently
      threads = 20.times.map do |i|
        Thread.new do
          runner = RAAF::Runner.new(agent: agents.first, provider: mock_provider)
          results << runner.run("Handoff load test #{i}")
        end
      end

      duration = Benchmark.measure { threads.each(&:join) }

      expect(results.size).to eq(20)
      expect(duration.real).to be < 5.0 # Should complete quickly
    end
  end

  describe "Error resilience under load" do
    it "maintains performance with 10% error rate" do
      # Mix successful and failing responses (10% errors)
      1000.times do |i|
        if (i % 10).zero?
          mock_provider.add_error(RAAF::APIError.new("Simulated error #{i}"))
        else
          mock_provider.add_response("Success response #{i}")
        end
      end

      agent = create_test_agent(name: "ErrorLoadAgent")
      error_handler = RAAF::ErrorHandler.new(
        strategy: RAAF::RecoveryStrategy::LOG_AND_CONTINUE
      )

      successful_requests = Concurrent::AtomicFixnum.new(0)
      failed_requests = Concurrent::AtomicFixnum.new(0)

      threads = 10.times.map do |thread_id|
        Thread.new do
          runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

          100.times do |i|
            error_handler.with_error_handling do
              runner.run("Error resilience test #{thread_id}-#{i}")
              successful_requests.increment
            end
          rescue StandardError
            failed_requests.increment
          end
        end
      end

      duration = Benchmark.measure { threads.each(&:join) }

      # Should maintain good throughput despite errors
      expect(duration.real).to be < 10.0

      # Verify error rate is approximately 10%
      total_requests = successful_requests.value + failed_requests.value
      error_rate = failed_requests.value.to_f / total_requests
      expect(error_rate).to be_between(0.08, 0.12) # Allow some variance
    end

    it "recovers gracefully from provider outages" do
      # Use fresh provider to avoid test pollution
      fresh_provider = create_mock_provider

      # Add warm-up responses
      3.times { fresh_provider.add_response("warm-up response") }

      # Simulate provider outage pattern
      1000.times do |i|
        if i >= 200 && i < 300 # Outage from request 200-299
          fresh_provider.add_error(RAAF::APIError.new("Provider unavailable"))
        else
          fresh_provider.add_response("Available response #{i}")
        end
      end

      agent = create_test_agent(name: "OutageAgent")
      runner = RAAF::Runner.new(agent: agent, provider: fresh_provider)

      # Small warm-up to stabilize timing
      3.times do
        runner.run("warm-up")
      rescue StandardError
        nil
      end

      results = []
      errors = []
      response_times = []

      1000.times do |i|
        start = Time.now
        begin
          results << runner.run("Outage test #{i}")
        rescue StandardError => e
          errors << { index: i, error: e }
        end
        response_times << (Time.now - start)
      end

      # Should have ~100 errors during outage
      expect(errors.size).to be_between(90, 110)

      # Response times should recover after outage
      # Use median instead of mean for more stable comparison
      pre_outage_times = response_times[0..199].sort
      post_outage_times = response_times[300..499].sort

      pre_outage_median = pre_outage_times[pre_outage_times.length / 2]
      post_outage_median = post_outage_times[post_outage_times.length / 2]

      # Post-outage performance should be reasonably close to pre-outage
      # Allow for some degradation due to recovery overhead
      tolerance_multiplier = 2.0 # More generous tolerance for test stability
      expect(post_outage_median).to be < (pre_outage_median * tolerance_multiplier)
    end
  end

  describe "Tool execution under load" do
    it "maintains tool execution performance under load" do
      # Create agent with multiple tools
      tools = 20.times.map do |i|
        RAAF::FunctionTool.new(
          proc { |data:|
            # Simulate some work
            sleep(0.001)
            "Processed by tool #{i}: #{data}"
          },
          name: "load_tool_#{i}",
          description: "Load test tool #{i}"
        )
      end

      agent = create_test_agent(name: "ToolLoadAgent")
      tools.each { |tool| agent.add_tool(tool) }

      # Prepare responses with random tool calls
      500.times do |i|
        tool_idx = i % 20
        mock_provider.add_response(
          "Using tool #{tool_idx}",
          tool_calls: [{
            function: {
              name: "load_tool_#{tool_idx}",
              arguments: JSON.generate({ data: "Request #{i}" })
            }
          }]
        )
        mock_provider.add_response("Tool execution complete")
      end

      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      # Run tool executions concurrently
      threads = 10.times.map do |thread_id|
        Thread.new do
          25.times do |i|
            runner.run("Execute tool for #{thread_id}-#{i}")
          end
        end
      end

      duration = Benchmark.measure { threads.each(&:join) }

      # Should handle concurrent tool execution efficiently
      expect(duration.real).to be < 10.0
    end
  end
end

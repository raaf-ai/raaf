# frozen_string_literal: true

require "spec_helper"

if defined?(RAAF::Async::Runner)
  RSpec.describe "RAAF Streaming Acceptance", :acceptance do
    let(:agent) do
      RAAF::Agent.new(
        name: "AcceptanceTestAgent",
        instructions: "You are a helpful assistant for acceptance testing.",
        model: "gpt-4o"
      )
    end

    let(:mock_provider) { double("MockProvider") }
    let(:standard_response) do
      {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => "This is a helpful response for acceptance testing."
          },
          "finish_reason" => "stop"
        }],
        "usage" => { "total_tokens" => 25 }
      }
    end

    before do
      allow(mock_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
      allow(mock_provider).to receive(:chat_completion).and_return(standard_response)
    end

    describe "User Story: Basic Async Agent Interaction" do
      it "allows users to create and interact with agents asynchronously" do
        # Given: A user wants to create an async agent
        async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

        # When: The user sends a message asynchronously
        Async do
          result = async_runner.run_async("Hello, can you help me?").wait

          # Then: The agent responds helpfully
          expect(result).to be_success
          expect(result.messages.last[:role]).to eq("assistant")
          expect(result.messages.last[:content]).to include("helpful")
        end
      end

      it "provides synchronous interface for async operations" do
        # Given: A user prefers synchronous interface
        async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

        # When: The user calls run (synchronous) method
        result = async_runner.run("I need help with something")

        # Then: The operation completes synchronously but uses async backend
        expect(result).to be_a(RAAF::RunResult)
        expect(result).to be_success
        expect(result.messages.last[:content]).to include("helpful")
      end
    end

    describe "User Story: Tool-Enhanced Async Agents" do
      def weather_tool(location:)
        case location.downcase
        when "paris"
          "Weather in Paris: 18°C, partly cloudy"
        when "tokyo"
          "Weather in Tokyo: 22°C, sunny"
        else
          "Weather in #{location}: Data not available"
        end
      end

      def calculator_tool(operation:, num_a:, num_b:)
        case operation
        when "add"
          num_a + num_b
        when "multiply"
          num_a * num_b
        when "divide"
          num_b == 0 ? "Error: Division by zero" : num_a / num_b
        else
          "Unknown operation: #{operation}"
        end
      end

      let(:tool_agent) do
        agent = RAAF::Agent.new(
          name: "ToolAgent",
          instructions: "You are a helpful assistant with access to tools.",
          model: "gpt-4o"
        )
        agent.add_tool(method(:weather_tool))
        agent.add_tool(method(:calculator_tool))
        agent
      end

      it "allows users to create agents with multiple tools that work asynchronously" do
        # Mock tool execution sequence
        weather_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [{
                "id" => "call_weather",
                "type" => "function",
                "function" => {
                  "name" => "weather_tool",
                  "arguments" => '{"location": "Paris"}'
                }
              }]
            },
            "finish_reason" => "tool_calls"
          }]
        }

        final_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "The weather in Paris is 18°C and partly cloudy."
            },
            "finish_reason" => "stop"
          }]
        }

        allow(mock_provider).to receive(:chat_completion)
          .and_return(weather_response, final_response)

        # Given: A user has an agent with tools
        async_runner = RAAF::Async::Runner.new(agent: tool_agent, provider: mock_provider)

        # When: The user requests tool usage
        Async do
          result = async_runner.run_async("What's the weather like in Paris?").wait

          # Then: The tool is executed and result incorporated
          expect(result).to be_success

          # Should have tool execution in message history
          tool_message = result.messages.find { |m| m[:role] == "tool" }
          expect(tool_message).to be_present
          expect(tool_message[:content]).to include("18°C, partly cloudy")

          # Final response should incorporate tool result
          expect(result.messages.last[:content]).to include("Paris")
        end
      end

      it "handles multiple concurrent tool executions" do
        # Mock parallel tool execution
        parallel_tools_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [
                {
                  "id" => "call_weather",
                  "type" => "function",
                  "function" => {
                    "name" => "weather_tool",
                    "arguments" => '{"location": "Tokyo"}'
                  }
                },
                {
                  "id" => "call_calc",
                  "type" => "function",
                  "function" => {
                    "name" => "calculator_tool",
                    "arguments" => '{"operation": "multiply", "a": 15, "b": 3}'
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }]
        }

        summary_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "In Tokyo it's 22°C and sunny. Also, 15 × 3 = 45."
            },
            "finish_reason" => "stop"
          }]
        }

        allow(mock_provider).to receive(:chat_completion)
          .and_return(parallel_tools_response, summary_response)

        async_runner = RAAF::Async::Runner.new(agent: tool_agent, provider: mock_provider)

        # Given: Multiple tools can be called simultaneously
        # When: User requests multiple tool operations
        Async do
          result = async_runner.run_async("What's the weather in Tokyo and what's 15 times 3?").wait

          # Then: Both tools execute and results are combined
          expect(result).to be_success

          tool_messages = result.messages.select { |m| m[:role] == "tool" }
          expect(tool_messages.size).to eq(2)

          # Should have both tool results
          contents = tool_messages.map { |m| m[:content] }
          expect(contents).to include("Weather in Tokyo: 22°C, sunny")
          expect(contents).to include("45")
        end
      end
    end

    describe "User Story: Multi-Agent Collaboration" do
      let(:research_agent) do
        RAAF::Agent.new(
          name: "ResearchAgent",
          instructions: "You are a research specialist who gathers information.",
          model: "gpt-4o"
        )
      end

      let(:writer_agent) do
        RAAF::Agent.new(
          name: "WriterAgent",
          instructions: "You are a writer who creates content based on research.",
          model: "gpt-4o"
        )
      end

      let(:coordinator_agent) do
        agent = RAAF::Agent.new(
          name: "CoordinatorAgent",
          instructions: "You coordinate between research and writing teams.",
          model: "gpt-4o"
        )
        agent.add_handoff(research_agent)
        agent.add_handoff(writer_agent)
        agent
      end

      it "enables seamless handoffs between specialized agents" do
        # Mock coordination handoff to research
        handoff_to_research = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [{
                "id" => "call_handoff_research",
                "type" => "function",
                "function" => {
                  "name" => "transfer_to_researchagent",
                  "arguments" => '{"context": "Need research on AI agents"}'
                }
              }]
            },
            "finish_reason" => "tool_calls"
          }]
        }

        research_complete = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "Research completed: AI agents are autonomous software entities."
            },
            "finish_reason" => "stop"
          }]
        }

        allow(mock_provider).to receive(:chat_completion)
          .and_return(handoff_to_research, research_complete)

        # Given: A user has multiple specialized agents
        async_runner = RAAF::Async::Runner.new(
          agent: coordinator_agent,
          provider: mock_provider
        )

        # When: A task requires specialized expertise
        Async do
          result = async_runner.run_async("I need research on AI agents").wait

          # Then: The task is handed off to the appropriate specialist
          expect(result).to be_success
          expect(result.last_agent.name).to eq("ResearchAgent")
          expect(result.messages.last[:content]).to include("Research completed")
        end
      end

      it "supports complex multi-step workflows with handoffs" do
        # Mock multi-step workflow: Coordinator -> Research -> Writer
        coord_to_research = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [{
                "id" => "call_research",
                "type" => "function",
                "function" => {
                  "name" => "transfer_to_researchagent",
                  "arguments" => '{"context": "Research Ruby programming benefits"}'
                }
              }]
            },
            "finish_reason" => "tool_calls"
          }]
        }

        research_to_writer = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [{
                "id" => "call_writer",
                "type" => "function",
                "function" => {
                  "name" => "transfer_to_writeragent",
                  "arguments" => '{"context": "Write article based on Ruby research"}'
                }
              }]
            },
            "finish_reason" => "tool_calls"
          }]
        }

        final_article = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "# Ruby Programming Benefits\n\nBased on research, Ruby offers excellent developer productivity..."
            },
            "finish_reason" => "stop"
          }]
        }

        allow(mock_provider).to receive(:chat_completion)
          .and_return(coord_to_research, research_to_writer, final_article)

        async_runner = RAAF::Async::Runner.new(
          agent: coordinator_agent,
          provider: mock_provider
        )

        # Given: A complex task requiring multiple specializations
        # When: User requests a complete research and writing workflow
        Async do
          result = async_runner.run_async("Research Ruby programming and write an article about it").wait

          # Then: The workflow progresses through multiple agents
          expect(result).to be_success
          expect(result.last_agent.name).to eq("WriterAgent")
          expect(result.messages.last[:content]).to include("Ruby Programming Benefits")
        end
      end
    end

    describe "User Story: Real-time Streaming Sessions" do
      it "provides streaming session management for real-time interactions" do
        async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

        # Given: A user wants real-time agent interaction
        session = async_runner.create_streaming_session(agent)

        # When: The session is started
        session.start

        # Then: The session should be active and ready
        expect(session).to be_active
        expect(session.stats[:session_id]).to be_present
        expect(session.stats[:agent]).to eq("AcceptanceTestAgent")

        # Cleanup
        session.stop
        expect(session).not_to be_active
      end

      it "handles message streaming with callbacks" do
        async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)
        session = async_runner.create_streaming_session(agent)

        # Track streaming events
        events = []
        chunks = []

        session.on(:stream_start) { |stream_id, message| events << [:start, stream_id, message] }
        session.on(:chunk) { |chunk_data| chunks << chunk_data }
        session.on(:stream_end) { |stream_id, result| events << [:end, stream_id, result] }

        session.start

        # Given: A streaming session with event handlers
        # When: A message is sent through the session
        stream_id = session.send_message("Hello, stream this response") do |chunk|
          # This block would receive individual chunks
          expect(chunk).to have_key(:content)
          expect(chunk).to have_key(:stream_id)
          expect(chunk).to have_key(:timestamp)
        end

        # Allow some time for async processing
        sleep(0.1)

        # Then: Streaming events should be captured
        expect(stream_id).to be_present
        expect(events).not_to be_empty

        session.stop
      end
    end

    describe "User Story: Error Recovery and Resilience" do
      it "gracefully handles provider failures with retry logic" do
        # Create provider that fails first, then succeeds
        failing_provider = double("FailingProvider")
        call_count = 0
        allow(failing_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
        allow(failing_provider).to receive(:chat_completion) do
          call_count += 1
          raise RAAF::APIError, "Temporary failure" if call_count == 1

          standard_response
        end

        async_runner = RAAF::Async::Runner.new(agent: agent, provider: failing_provider)

        # Given: A provider that may fail temporarily
        # When: A user sends a message
        result = nil
        expect do
          result = async_runner.run("This might fail initially")
        end.to raise_error(RAAF::APIError)

        # The user can retry and should succeed
        result = async_runner.run("Retry the request")
        expect(result).to be_success
      end

      it "provides meaningful error messages for troubleshooting" do
        auth_failing_provider = double("AuthFailingProvider")
        allow(auth_failing_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
        allow(auth_failing_provider).to receive(:chat_completion)
          .and_raise(RAAF::AuthenticationError, "Invalid API key provided")

        async_runner = RAAF::Async::Runner.new(agent: agent, provider: auth_failing_provider)

        # Given: An authentication issue
        # When: A user attempts to use the agent
        # Then: A clear error message is provided
        expect do
          async_runner.run("This will fail with auth error")
        end.to raise_error(RAAF::AuthenticationError, "Invalid API key provided")
      end

      it "maintains session state during partial failures" do
        # Provider that works for first call, fails for second
        intermittent_provider = double("IntermittentProvider")
        call_count = 0
        allow(intermittent_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
        allow(intermittent_provider).to receive(:chat_completion) do
          call_count += 1
          raise RAAF::APIError, "Intermittent failure" if call_count == 2

          {
            "choices" => [{
              "message" => {
                "role" => "assistant",
                "content" => "Response #{call_count}"
              },
              "finish_reason" => "stop"
            }]
          }
        end

        async_runner = RAAF::Async::Runner.new(agent: agent, provider: intermittent_provider)

        # Given: A conversation in progress
        result1 = async_runner.run("First message")
        expect(result1).to be_success
        expect(result1.messages.last[:content]).to eq("Response 1")

        # When: A subsequent message fails
        expect do
          async_runner.run(result1.messages + [{ role: "user", content: "Second message" }])
        end.to raise_error(RAAF::APIError)

        # Then: Previous successful state is preserved
        expect(result1.messages.size).to eq(3) # system + user + assistant
      end
    end

    describe "User Story: Performance and Scalability" do
      it "handles high concurrent load efficiently" do
        async_runner = RAAF::Async::Runner.new(
          agent: agent,
          provider: mock_provider,
          pool_size: 20
        )

        # Given: High concurrent demand
        concurrent_requests = 50
        tasks = []

        start_time = Time.now

        # When: Multiple requests are submitted concurrently
        concurrent_requests.times do |i|
          tasks << async_runner.run_async("Concurrent request #{i}")
        end

        # Wait for all to complete
        results = Async do
          tasks.map(&:wait)
        end

        completion_time = Time.now - start_time

        # Then: All requests complete successfully within reasonable time
        expect(results.size).to eq(concurrent_requests)
        expect(results).to all(be_success)
        expect(completion_time).to be < 5.0 # Should complete within 5 seconds

        puts "Processed #{concurrent_requests} concurrent requests in #{completion_time.round(3)}s"
        puts "Throughput: #{(concurrent_requests / completion_time).round(2)} requests/second"

        async_runner.shutdown
      end

      it "scales resource usage appropriately" do
        # Test different pool sizes
        small_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider, pool_size: 2)
        large_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider, pool_size: 10)

        task_count = 20

        # Measure performance with small pool
        small_time = Benchmark.realtime do
          tasks = task_count.times.map { |i| small_runner.run_async("Small pool #{i}") }
          Async { tasks.map(&:wait) }
        end

        # Measure performance with large pool
        large_time = Benchmark.realtime do
          tasks = task_count.times.map { |i| large_runner.run_async("Large pool #{i}") }
          Async { tasks.map(&:wait) }
        end

        # Larger pool should perform better for concurrent tasks
        improvement = small_time / large_time
        expect(improvement).to be > 1.2 # At least 20% improvement

        puts "Small pool (2 threads): #{small_time.round(3)}s"
        puts "Large pool (10 threads): #{large_time.round(3)}s"
        puts "Performance improvement: #{improvement.round(2)}x"

        small_runner.shutdown
        large_runner.shutdown
      end
    end

    describe "User Story: Developer Experience" do
      it "provides intuitive API for common use cases" do
        # Given: A developer wants to quickly set up an async agent
        # When: Using the simplest possible setup
        simple_runner = RAAF::Async::Runner.new(agent: agent)

        # Then: It should work out of the box
        expect(simple_runner).to be_a(RAAF::Async::Runner)
        expect(simple_runner.agent).to eq(agent)
        expect(simple_runner.pool_size).to be > 0
      end

      it "provides helpful debugging and monitoring capabilities" do
        async_runner = RAAF::Async::Runner.new(
          agent: agent,
          provider: mock_provider,
          pool_size: 5
        )

        # Given: A developer needs to monitor performance
        # When: Checking runner statistics
        initial_stats = async_runner.stats

        # Execute some tasks
        tasks = 3.times.map { |i| async_runner.run_async("Debug test #{i}") }
        Async { tasks.map(&:wait) }

        final_stats = async_runner.stats

        # Then: Comprehensive stats are available
        expect(initial_stats).to have_key(:pool_size)
        expect(initial_stats).to have_key(:active_tasks)
        expect(initial_stats).to have_key(:total_tasks)

        expect(final_stats[:total_tasks]).to be >= initial_stats[:total_tasks]
        expect(final_stats[:completed_tasks]).to be >= 3

        async_runner.shutdown
      end

      it "integrates seamlessly with existing RAAF patterns" do
        # Given: Existing synchronous RAAF code
        sync_runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        sync_result = sync_runner.run("Sync test")

        # When: Converting to async
        async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)
        async_result = async_runner.run("Async test")

        # Then: Results should be compatible
        expect(sync_result.class).to eq(async_result.class)
        expect(sync_result.messages.structure).to eq(async_result.messages.structure)
        expect(sync_result.agent.name).to eq(async_result.agent.name)
      end
    end

    private

    def benchmark_realtime
      start_time = Time.now
      yield
      Time.now - start_time
    end
  end
else
  RSpec.describe "RAAF Streaming Acceptance" do
    it "skips acceptance tests when streaming not available" do
      skip "RAAF::Async::Runner not available - streaming functionality not loaded"
    end
  end
end

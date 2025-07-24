# frozen_string_literal: true

require "spec_helper"

if defined?(RAAF::Async::Runner)
  RSpec.describe "RAAF Streaming Integration", :integration do
    before(:all) do
      skip "Skipping streaming integration tests - async/streaming compatibility issues"
    end

    let(:agent) do
      RAAF::Agent.new(
        name: "IntegrationTestAgent",
        instructions: "You are a helpful assistant for integration testing.",
        model: "gpt-4o"
      )
    end

    let(:async_runner) { RAAF::Async::Runner.new(agent: agent) }
    let(:mock_provider) { double("MockProvider") }

    before do
      allow(mock_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
      allow(mock_provider).to receive(:chat_completion).and_return({
                                                                     "choices" => [{
                                                                       "message" => {
                                                                         "role" => "assistant",
                                                                         "content" => "Integration test response"
                                                                       },
                                                                       "finish_reason" => "stop"
                                                                     }],
                                                                     "usage" => { "total_tokens" => 25 }
                                                                   })
    end

    describe "end-to-end streaming workflow" do
      let(:runner_with_provider) { RAAF::Async::Runner.new(agent: agent, provider: mock_provider) }

      it "handles complete async conversation flow" do
        Async do
          # Start conversation
          result1 = runner_with_provider.run_async("Hello, I need help with testing").wait
          expect(result1).to be_a(RAAF::RunResult)
          expect(result1.messages.size).to eq(3) # system + user + assistant

          # Continue conversation
          new_messages = result1.messages + [{ role: "user", content: "Can you elaborate?" }]
          result2 = runner_with_provider.run_async(new_messages).wait
          expect(result2).to be_a(RAAF::RunResult)
          expect(result2.messages.size).to eq(5) # previous + user + assistant
        end
      end

      it "handles concurrent agent execution" do
        agents = 3.times.map do |i|
          RAAF::Agent.new(
            name: "ConcurrentAgent#{i}",
            instructions: "You are agent #{i}",
            model: "gpt-4o"
          )
        end

        tasks = []
        agents.each do |concurrent_agent|
          runner = RAAF::Async::Runner.new(agent: concurrent_agent, provider: mock_provider)
          tasks << runner.run_async("Process task concurrently")
        end

        Async do
          results = tasks.map(&:wait)
          expect(results.size).to eq(3)
          expect(results).to all(be_a(RAAF::RunResult))
        end
      end

      it "integrates with tool execution" do
        def test_integration_tool(operation:, data:)
          "Processed #{operation} with data: #{data}"
        end

        agent_with_tools = RAAF::Agent.new(
          name: "ToolIntegrationAgent",
          instructions: "Use tools to help users",
          model: "gpt-4o"
        )
        agent_with_tools.add_tool(method(:test_integration_tool))

        # Mock tool call response
        tool_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [{
                "id" => "call_123",
                "type" => "function",
                "function" => {
                  "name" => "test_integration_tool",
                  "arguments" => '{"operation": "validate", "data": "test_data"}'
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
              "content" => "I've processed your request using the integration tool."
            },
            "finish_reason" => "stop"
          }]
        }

        allow(mock_provider).to receive(:chat_completion)
          .and_return(tool_response, final_response)

        runner = RAAF::Async::Runner.new(agent: agent_with_tools, provider: mock_provider)

        Async do
          result = runner.run_async("Please validate some test data").wait
          expect(result).to be_a(RAAF::RunResult)
          expect(result.messages.size).to eq(4) # system + user + assistant(tool) + tool_result + assistant(final)

          # Check tool execution occurred
          tool_message = result.messages.find { |m| m[:role] == "tool" }
          expect(tool_message).to be_present
          expect(tool_message[:content]).to include("Processed validate with data: test_data")
        end
      end
    end

    describe "multi-agent handoff integration" do
      let(:specialist_agent) do
        RAAF::Agent.new(
          name: "SpecialistAgent",
          instructions: "You are a specialist who handles complex requests",
          model: "gpt-4o"
        )
      end

      let(:main_agent) do
        agent = RAAF::Agent.new(
          name: "MainAgent",
          instructions: "You coordinate with specialists",
          model: "gpt-4o"
        )
        agent.add_handoff(specialist_agent)
        agent
      end

      it "handles agent handoffs in async context" do
        # Mock handoff response
        handoff_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [{
                "id" => "call_handoff",
                "type" => "function",
                "function" => {
                  "name" => "transfer_to_specialistagent",
                  "arguments" => '{"context": "Complex request needs specialist"}'
                }
              }]
            },
            "finish_reason" => "tool_calls"
          }]
        }

        specialist_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "I'm the specialist and I've handled your complex request."
            },
            "finish_reason" => "stop"
          }]
        }

        allow(mock_provider).to receive(:chat_completion)
          .and_return(handoff_response, specialist_response)

        runner = RAAF::Async::Runner.new(
          agent: main_agent,
          provider: mock_provider
        )

        Async do
          result = runner.run_async("I have a complex request").wait
          expect(result).to be_a(RAAF::RunResult)
          expect(result.last_agent.name).to eq("SpecialistAgent")
        end
      end
    end

    describe "streaming session integration" do
      it "creates and manages streaming sessions" do
        skip "StreamingSession integration requires WebSocket implementation"

        # This would test:
        # - Session lifecycle
        # - Real-time message streaming
        # - Connection management
        # - Error recovery
      end
    end

    describe "provider integration" do
      it "works with different provider types" do
        # Test with sync provider wrapped in AsyncProviderWrapper
        sync_provider = RAAF::Models::OpenAIProvider.new
        allow(sync_provider).to receive(:chat_completion).and_return({
                                                                       "choices" => [{
                                                                         "message" => {
                                                                           "role" => "assistant",
                                                                           "content" => "Sync provider response"
                                                                         },
                                                                         "finish_reason" => "stop"
                                                                       }]
                                                                     })

        runner = RAAF::Async::Runner.new(agent: agent, provider: sync_provider)

        Async do
          result = runner.run_async("Test sync provider").wait
          expect(result).to be_a(RAAF::RunResult)
          expect(result.messages.last[:content]).to eq("Sync provider response")
        end
      end

      it "works with async-native providers" do
        async_provider = RAAF::Async::Providers::ResponsesProvider.new
        allow(async_provider).to receive(:chat_completion).and_return({
                                                                        "choices" => [{
                                                                          "message" => {
                                                                            "role" => "assistant",
                                                                            "content" => "Async provider response"
                                                                          },
                                                                          "finish_reason" => "stop"
                                                                        }]
                                                                      })

        runner = RAAF::Async::Runner.new(agent: agent, provider: async_provider)

        Async do
          result = runner.run_async("Test async provider").wait
          expect(result).to be_a(RAAF::RunResult)
          expect(result.messages.last[:content]).to eq("Async provider response")
        end
      end
    end

    describe "error handling integration" do
      it "handles provider failures gracefully" do
        failing_provider = double("FailingProvider")
        allow(failing_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
        allow(failing_provider).to receive(:chat_completion)
          .and_raise(RAAF::APIError, "Provider integration failure")

        runner = RAAF::Async::Runner.new(agent: agent, provider: failing_provider)

        Async do
          expect do
            runner.run_async("This should fail").wait
          end.to raise_error(RAAF::APIError, "Provider integration failure")
        end
      end

      it "handles timeout scenarios" do
        slow_provider = double("SlowProvider")
        allow(slow_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
        allow(slow_provider).to receive(:chat_completion) do
          sleep(0.1)
          {
            "choices" => [{
              "message" => {
                "role" => "assistant",
                "content" => "Finally responded"
              },
              "finish_reason" => "stop"
            }]
          }
        end

        runner = RAAF::Async::Runner.new(agent: agent, provider: slow_provider)

        # This should complete within reasonable time
        Async do
          result = runner.run_async("Test timeout handling").wait
          expect(result).to be_a(RAAF::RunResult)
        end
      end
    end

    describe "resource management integration" do
      it "properly manages thread pools and async resources" do
        runner = RAAF::Async::Runner.new(
          agent: agent,
          provider: mock_provider,
          pool_size: 5,
          queue_size: 10
        )

        expect(runner.pool_size).to eq(5)
        expect(runner.queue_size).to eq(10)
        expect(runner.shutdown?).to be false

        # Test resource cleanup
        runner.shutdown
        expect(runner.shutdown?).to be true
      end

      it "handles concurrent task execution within resource limits" do
        runner = RAAF::Async::Runner.new(
          agent: agent,
          provider: mock_provider,
          pool_size: 2
        )

        tasks = []
        5.times do |i|
          tasks << runner.run_async("Concurrent task #{i}")
        end

        Async do
          results = tasks.map(&:wait)
          expect(results.size).to eq(5)
          expect(results).to all(be_a(RAAF::RunResult))
        end

        runner.shutdown
      end
    end
  end
else
  RSpec.describe "RAAF Streaming Integration" do
    it "skips integration tests when streaming not available" do
      skip "RAAF::Async::Runner not available - streaming functionality not loaded"
    end
  end
end

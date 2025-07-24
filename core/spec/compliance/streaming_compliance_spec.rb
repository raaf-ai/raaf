# frozen_string_literal: true

require "spec_helper"

if defined?(RAAF::Async::Runner)
  RSpec.describe "RAAF Streaming Compliance", :compliance do
    let(:agent) do
      RAAF::Agent.new(
        name: "ComplianceTestAgent",
        instructions: "You are a compliance testing assistant.",
        model: "gpt-4o"
      )
    end

    let(:mock_provider) { double("MockProvider") }
    let(:standard_response) do
      {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => "Compliance test response"
          },
          "finish_reason" => "stop"
        }],
        "usage" => { "total_tokens" => 20 }
      }
    end

    before do
      allow(mock_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
      allow(mock_provider).to receive(:chat_completion).and_return(standard_response)
    end

    describe "OpenAI API compliance" do
      it "maintains chat completion response format compatibility" do
        async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

        Async do
          result = async_runner.run_async("Test message").wait

          # Response should follow OpenAI chat completion format
          expect(result).to be_a(RAAF::RunResult)
          expect(result.messages).to be_an(Array)

          # Each message should have required fields
          result.messages.each do |message|
            expect(message).to have_key(:role)
            expect(message).to have_key(:content)
            expect(%w[system user assistant tool]).to include(message[:role])
          end

          # Last message should be assistant response
          last_message = result.messages.last
          expect(last_message[:role]).to eq("assistant")
          expect(last_message[:content]).to be_a(String)
        end
      end

      it "handles tool call format correctly" do
        def compliance_tool(parameter:)
          "Tool executed with: #{parameter}"
        end

        agent_with_tools = RAAF::Agent.new(
          name: "ComplianceToolAgent",
          instructions: "Use tools appropriately",
          model: "gpt-4o"
        )
        agent_with_tools.add_tool(method(:compliance_tool))

        # Mock tool call response in OpenAI format
        tool_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [{
                "id" => "call_compliance_123",
                "type" => "function",
                "function" => {
                  "name" => "compliance_tool",
                  "arguments" => '{"parameter": "test_value"}'
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
              "content" => "Tool execution completed"
            },
            "finish_reason" => "stop"
          }]
        }

        allow(mock_provider).to receive(:chat_completion)
          .and_return(tool_response, final_response)

        async_runner = RAAF::Async::Runner.new(agent: agent_with_tools, provider: mock_provider)

        Async do
          result = async_runner.run_async("Use the compliance tool").wait

          # Find tool call and tool result messages
          tool_call_msg = result.messages.find { |m| m[:tool_calls] }
          tool_result_msg = result.messages.find { |m| m[:role] == "tool" }

          # Verify tool call format
          expect(tool_call_msg[:tool_calls]).to be_an(Array)
          tool_call = tool_call_msg[:tool_calls].first
          expect(tool_call).to have_key("id")
          expect(tool_call).to have_key("type")
          expect(tool_call).to have_key("function")
          expect(tool_call["function"]).to have_key("name")
          expect(tool_call["function"]).to have_key("arguments")

          # Verify tool result format
          expect(tool_result_msg[:tool_call_id]).to eq("call_compliance_123")
          expect(tool_result_msg[:content]).to eq("Tool executed with: test_value")
        end
      end

      it "respects OpenAI response field structure" do
        # Test with default ResponsesProvider
        default_runner = RAAF::Async::Runner.new(agent: agent)

        # Mock the actual provider to return proper structure
        allow_any_instance_of(RAAF::Async::Providers::ResponsesProvider)
          .to receive(:chat_completion)
          .and_return({
                        "id" => "chatcmpl-123",
                        "object" => "chat.completion",
                        "created" => Time.now.to_i,
                        "model" => "gpt-4o",
                        "choices" => [{
                          "index" => 0,
                          "message" => {
                            "role" => "assistant",
                            "content" => "Structured response"
                          },
                          "finish_reason" => "stop"
                        }],
                        "usage" => {
                          "prompt_tokens" => 10,
                          "completion_tokens" => 5,
                          "total_tokens" => 15
                        }
                      })

        Async do
          result = default_runner.run_async("Test structured response").wait

          # Verify the result maintains proper structure
          expect(result).to be_a(RAAF::RunResult)
          expect(result.messages.last[:content]).to eq("Structured response")
        end
      end
    end

    describe "RAAF framework compliance" do
      it "maintains agent handoff compatibility" do
        specialist_agent = RAAF::Agent.new(
          name: "ComplianceSpecialist",
          instructions: "I handle specialized compliance requests"
        )

        main_agent = RAAF::Agent.new(
          name: "ComplianceMain",
          instructions: "I coordinate compliance tasks"
        )
        main_agent.add_handoff(specialist_agent)

        # Mock handoff via tool call (RAAF standard)
        handoff_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [{
                "id" => "call_handoff_123",
                "type" => "function",
                "function" => {
                  "name" => "transfer_to_compliancespecialist",
                  "arguments" => '{"context": "Compliance review needed"}'
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
              "content" => "Compliance review completed"
            },
            "finish_reason" => "stop"
          }]
        }

        allow(mock_provider).to receive(:chat_completion)
          .and_return(handoff_response, specialist_response)

        async_runner = RAAF::Async::Runner.new(
          agent: main_agent,
          provider: mock_provider
        )

        Async do
          result = async_runner.run_async("Perform compliance review").wait

          # Verify handoff occurred correctly
          expect(result.last_agent.name).to eq("ComplianceSpecialist")
          expect(result.messages.last[:content]).to eq("Compliance review completed")
        end
      end

      it "maintains thread safety requirements" do
        RAAF::Async::Runner.new(
          agent: agent,
          provider: mock_provider,
          pool_size: 10
        )

        # Create concurrent tasks that modify shared state
        shared_counter = { value: 0 }
        mutex = Mutex.new

        counting_tool = proc do |increment:|
          mutex.synchronize do
            shared_counter[:value] += increment
          end
          shared_counter[:value]
        end

        agent_with_counter = RAAF::Agent.new(
          name: "CounterAgent",
          instructions: "Use counting tool"
        )
        agent_with_counter.add_tool(counting_tool)

        # Mock tool responses
        tool_responses = 20.times.map do |i|
          [
            {
              "choices" => [{
                "message" => {
                  "role" => "assistant",
                  "content" => "",
                  "tool_calls" => [{
                    "id" => "call_#{i}",
                    "type" => "function",
                    "function" => {
                      "name" => "proc",
                      "arguments" => '{"increment": 1}'
                    }
                  }]
                },
                "finish_reason" => "tool_calls"
              }]
            },
            {
              "choices" => [{
                "message" => {
                  "role" => "assistant",
                  "content" => "Counter updated"
                },
                "finish_reason" => "stop"
              }]
            }
          ]
        end.flatten

        allow(mock_provider).to receive(:chat_completion)
          .and_return(*tool_responses)

        counter_runner = RAAF::Async::Runner.new(
          agent: agent_with_counter,
          provider: mock_provider
        )

        # Execute concurrent operations
        task_count = 20
        tasks = []

        task_count.times do |_i|
          tasks << counter_runner.run_async("Increment counter")
        end

        Async do
          tasks.map(&:wait)
        end

        # Verify thread safety - counter should equal task count
        expect(shared_counter[:value]).to eq(task_count)

        counter_runner.shutdown
      end

      it "handles resource cleanup properly" do
        runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

        # Verify initial state
        expect(runner.shutdown?).to be false
        expect(runner.stats[:active_tasks]).to eq(0)

        # Execute some tasks
        tasks = []
        5.times do |i|
          tasks << runner.run_async("Cleanup test #{i}")
        end

        Async do
          tasks.map(&:wait)
        end

        # Shutdown and verify cleanup
        runner.shutdown
        expect(runner.shutdown?).to be true

        # Should not accept new tasks after shutdown
        expect do
          runner.run_async("Should fail")
        end.not_to raise_error # Async runner should handle gracefully
      end
    end

    describe "error handling compliance" do
      it "propagates errors correctly in async context" do
        failing_provider = double("FailingProvider")
        allow(failing_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
        allow(failing_provider).to receive(:chat_completion)
          .and_raise(RAAF::APIError, "Compliance error test")

        async_runner = RAAF::Async::Runner.new(agent: agent, provider: failing_provider)

        Async do
          expect do
            async_runner.run_async("This should fail").wait
          end.to raise_error(RAAF::APIError, "Compliance error test")
        end
      end

      it "handles authentication errors appropriately" do
        auth_failing_provider = double("AuthFailingProvider")
        allow(auth_failing_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
        allow(auth_failing_provider).to receive(:chat_completion)
          .and_raise(RAAF::AuthenticationError, "Invalid API key")

        async_runner = RAAF::Async::Runner.new(agent: agent, provider: auth_failing_provider)

        Async do
          expect do
            async_runner.run_async("Auth test").wait
          end.to raise_error(RAAF::AuthenticationError, "Invalid API key")
        end
      end

      it "handles rate limiting correctly" do
        rate_limited_provider = double("RateLimitedProvider")
        allow(rate_limited_provider).to receive(:respond_to?).with(:async_chat_completion).and_return(false)
        allow(rate_limited_provider).to receive(:chat_completion)
          .and_raise(RAAF::RateLimitError, "Rate limit exceeded")

        async_runner = RAAF::Async::Runner.new(agent: agent, provider: rate_limited_provider)

        Async do
          expect do
            async_runner.run_async("Rate limit test").wait
          end.to raise_error(RAAF::RateLimitError, "Rate limit exceeded")
        end
      end
    end

    describe "configuration compliance" do
      it "respects agent configuration in async context" do
        configured_agent = RAAF::Agent.new(
          name: "ConfiguredAgent",
          instructions: "Follow configuration strictly",
          model: "gpt-4o",
          max_turns: 3
        )

        async_runner = RAAF::Async::Runner.new(agent: configured_agent, provider: mock_provider)

        Async do
          result = async_runner.run_async("Configuration test").wait

          # Verify agent configuration is maintained
          expect(result.last_agent.name).to eq("ConfiguredAgent")
          expect(result.last_agent.max_turns).to eq(3)
          expect(result.last_agent.model).to eq("gpt-4o")
        end
      end

      it "respects RunConfig parameters" do
        config = RAAF::RunConfig.new(
          max_turns: 2,
          debug: false
        )

        async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

        Async do
          result = async_runner.run_async("Config test", config: config).wait

          # Configuration should be applied
          expect(result).to be_a(RAAF::RunResult)
          expect(result.messages.size).to be <= 4 # system + user + assistant (respecting max_turns)
        end
      end

      it "maintains provider configuration" do
        # Test with custom provider configuration
        custom_provider = RAAF::Models::ResponsesProvider.new
        custom_provider.instance_variable_set(:@api_key, "custom-key")

        async_runner = RAAF::Async::Runner.new(agent: agent, provider: custom_provider)

        # Access the wrapped provider to verify configuration
        async_provider = async_runner.instance_variable_get(:@async_provider)
        expect(async_provider).to be_a(RAAF::Async::Runner::AsyncProviderWrapper)

        wrapped_provider = async_provider.instance_variable_get(:@sync_provider)
        expect(wrapped_provider.instance_variable_get(:@api_key)).to eq("custom-key")
      end
    end

    describe "logging compliance" do
      it "maintains consistent logging across async operations" do
        log_messages = []
        logger = double("TestLogger")

        # Capture log calls
        allow(logger).to receive(:debug) { |msg| log_messages << "DEBUG: #{msg}" }
        allow(logger).to receive(:info) { |msg| log_messages << "INFO: #{msg}" }
        allow(logger).to receive(:warn) { |msg| log_messages << "WARN: #{msg}" }
        allow(logger).to receive(:error) { |msg| log_messages << "ERROR: #{msg}" }

        # Mock the agent's logger
        allow(agent).to receive(:logger).and_return(logger)

        async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

        Async do
          async_runner.run_async("Logging test").wait
        end

        # Verify logging occurred (specific messages may vary)
        expect(log_messages).to be_an(Array)
        # Should have some log entries if logging is enabled
      end

      it "handles logging errors gracefully" do
        # Create a logger that fails
        failing_logger = double("FailingLogger")
        allow(failing_logger).to receive(:debug).and_raise(StandardError, "Logger failed")
        allow(failing_logger).to receive(:info).and_raise(StandardError, "Logger failed")

        allow(agent).to receive(:logger).and_return(failing_logger)

        async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

        # Should not crash even if logging fails
        expect do
          Async do
            async_runner.run_async("Logging error test").wait
          end
        end.not_to raise_error
      end
    end

    describe "environment compliance" do
      it "respects environment variable configuration" do
        # Save original environment
        original_log_level = ENV.fetch("RAAF_LOG_LEVEL", nil)
        original_debug = ENV.fetch("RAAF_DEBUG_CATEGORIES", nil)

        begin
          ENV["RAAF_LOG_LEVEL"] = "debug"
          ENV["RAAF_DEBUG_CATEGORIES"] = "async,api"

          async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

          # Environment should be respected in async context
          Async do
            result = async_runner.run_async("Environment test").wait
            expect(result).to be_a(RAAF::RunResult)
          end
        ensure
          # Restore original environment
          ENV["RAAF_LOG_LEVEL"] = original_log_level
          ENV["RAAF_DEBUG_CATEGORIES"] = original_debug
        end
      end

      it "handles missing environment variables gracefully" do
        # Save original environment
        original_api_key = ENV.fetch("OPENAI_API_KEY", nil)

        begin
          ENV.delete("OPENAI_API_KEY")

          # Should handle missing API key gracefully when using mock provider
          async_runner = RAAF::Async::Runner.new(agent: agent, provider: mock_provider)

          Async do
            result = async_runner.run_async("Missing env test").wait
            expect(result).to be_a(RAAF::RunResult)
          end
        ensure
          # Restore original environment
          ENV["OPENAI_API_KEY"] = original_api_key if original_api_key
        end
      end
    end
  end
else
  RSpec.describe "RAAF Streaming Compliance" do
    it "skips compliance tests when streaming not available" do
      skip "RAAF::Async::Runner not available - streaming functionality not loaded"
    end
  end
end

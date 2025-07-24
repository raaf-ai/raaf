# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Agent Performance", :performance do
  let(:mock_provider) { create_mock_provider }
  let(:agent) { create_test_agent(name: "PerformanceAgent") }

  before do
    mock_provider.add_response("Quick response for performance testing")
  end

  describe "Response time performance" do
    it "responds within acceptable time limits" do
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      if defined?(RSpec::Benchmark)
        expect do
          runner.run("Quick question")
        end.to perform_under(0.1).sec
      end
    end

    it "handles multiple sequential requests efficiently" do
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)

      # Add multiple responses
      5.times { mock_provider.add_response("Response") }

      if defined?(RSpec::Benchmark)
        expect do
          5.times { runner.run("Question") }
        end.to perform_under(0.5).sec
      end
    end
  end

  describe "Concurrent request handling" do
    it "handles concurrent requests efficiently" do
      # Add responses for concurrent requests
      10.times { mock_provider.add_response("Concurrent response") }

      if defined?(RSpec::Benchmark)
        expect do
          threads = 10.times.map do |i|
            Thread.new do
              runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
              runner.run("Concurrent request #{i}")
            end
          end
          threads.each(&:join)
        end.to perform_under(1).sec
      end
    end
  end

  describe "Tool execution performance" do
    let(:fast_tool) do
      RAAF::FunctionTool.new(
        proc { |input| "Processed: #{input}" },
        name: "fast_tool",
        description: "A fast processing tool"
      )
    end

    let(:agent_with_tools) do
      agent = create_test_agent(name: "ToolAgent")
      agent.add_tool(fast_tool)
      agent
    end

    it "executes tools efficiently" do
      mock_provider.add_response(
        "I'll use the tool",
        tool_calls: [{
          function: { name: "fast_tool", arguments: '{"input": "test"}' }
        }]
      )
      mock_provider.add_response("Tool completed")

      runner = RAAF::Runner.new(agent: agent_with_tools, provider: mock_provider)

      if defined?(RSpec::Benchmark)
        expect do
          runner.run("Use the tool")
        end.to perform_under(0.2).sec
      end
    end
  end

  describe "Large context handling" do
    it "handles large message histories efficiently" do
      # Create agent with large conversation history
      large_messages = 100.times.map do |i|
        { role: i.even? ? "user" : "assistant", content: "Message #{i}" * 10 }
      end

      mock_provider.add_response("Response to large context")

      if defined?(RSpec::Benchmark)
        expect do
          runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
          runner.run("New message", previous_messages: large_messages)
        end.to perform_under(0.5).sec
      end
    end

    it "handles complex tool configurations efficiently" do
      # Create agent with many tools
      tools = 50.times.map do |i|
        RAAF::FunctionTool.new(
          proc { |x| "Tool #{i} result: #{x}" },
          name: "tool_#{i}",
          description: "Tool number #{i}"
        )
      end

      complex_agent = create_test_agent(name: "ComplexAgent", tools: tools)
      mock_provider.add_response("Working with many tools")

      if defined?(RSpec::Benchmark)
        expect do
          runner = RAAF::Runner.new(agent: complex_agent, provider: mock_provider)
          runner.run("Process this")
        end.to perform_under(0.3).sec
      end
    end
  end
end

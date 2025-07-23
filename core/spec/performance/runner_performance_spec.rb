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
        
        expect {
          runner.run("Simple query")
        }.to perform_under(10).ms
      end
      
      it "allocates minimal memory for simple operations" do
        mock_provider.add_response("Memory efficient response")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        expect {
          runner.run("Test memory")
        }.to perform_allocation(10_000).objects
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
        
        expect {
          runner.run("New message", previous_messages: large_history)
        }.to perform_under(100).ms
      end
      
      it "doesn't create excessive objects with large history" do
        mock_provider.add_response("Memory test response")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        expect {
          runner.run("Test", previous_messages: large_history)
        }.to perform_allocation(50_000).objects
      end
    end
    
    context "multi-turn conversations" do
      it "maintains performance across multiple turns" do
        20.times { mock_provider.add_response("Turn response") }
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        expect {
          messages = [{ role: "user", content: "Start conversation" }]
          
          10.times do |i|
            result = runner.run(messages)
            messages = result.messages
            messages << { role: "user", content: "Continue turn #{i}" }
          end
        }.to perform_under(200).ms
      end
      
      it "doesn't leak memory across turns" do
        100.times { mock_provider.add_response("Memory test turn") }
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        # Measure memory growth
        initial_memory = nil
        final_memory = nil
        
        report = MemoryProfiler.report do
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
        expect(memory_growth || 0).to be < 100  # Less than 100 heap pages growth
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
      
      expect {
        runner.run("Use tool 5")
      }.to perform_under(20).ms
    end
    
    it "handles parallel tool calls efficiently" do
      # Multiple tool calls in one response
      tool_calls = 5.times.map do |i|
        { function: { name: "tool_#{i}", arguments: '{"x": "parallel test"}' } }
      end
      
      mock_provider.add_response("Using multiple tools", tool_calls: tool_calls)
      mock_provider.add_response("All tools complete")
      
      runner = RAAF::Runner.new(agent: agent_with_tools, provider: mock_provider)
      
      expect {
        runner.run("Use multiple tools")
      }.to perform_under(50).ms
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
        tool_calls: [{ function: { name: "big_tool_99", arguments: '{}' } }]
      )
      mock_provider.add_response("Done")
      
      runner = RAAF::Runner.new(agent: big_agent, provider: mock_provider)
      
      # Tool lookup should still be fast even with 100 tools
      expect {
        runner.run("Use last tool")
      }.to perform_under(30).ms
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
      agent_chain.each_with_index do |agent, i|
        if i < agent_chain.size - 1
          mock_provider.add_response(
            "Handing off to next agent",
            tool_calls: [{
              function: { 
                name: "transfer_to_chainagent#{i + 1}",
                arguments: '{"input": "Continue chain"}'
              }
            }]
          )
        else
          mock_provider.add_response("Chain complete")
        end
      end
      
      runner = RAAF::Runner.new(agent: agent_chain.first)
      
      expect {
        runner.run("Start chain")
      }.to perform_under(100).ms
    end
    
    it "doesn't accumulate memory during handoffs" do
      # Setup responses for handoff chain
      10.times do |i|
        mock_provider.add_response(
          "Handoff #{i}",
          tool_calls: i < 4 ? [{
            function: {
              name: "transfer_to_chainagent#{(i + 1) % 5}",
              arguments: '{}'
            }
          }] : nil
        )
      end
      
      runner = RAAF::Runner.new(agent: agent_chain.first)
      
      expect {
        runner.run("Test handoff memory")
      }.to perform_allocation(100_000).objects
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
      runner = RAAF::Runner.new(agent: agent, config: complex_config, provider: mock_provider)
      
      expect {
        runner.run("Test with config")
      }.to perform_under(15).ms
    end
    
    it "handles execution config efficiently" do
      exec_config = RAAF::ExecutionConfig.new(
        context: { user_id: "123", session: "abc" },
        input_guardrails: ["filter1", "filter2"],
        output_guardrails: ["guard1", "guard2"],
        session: { history: Array.new(100) { |i| "item_#{i}" } }
      )
      
      configured_agent = create_test_agent(
        name: "ConfiguredAgent",
        context: exec_config.context
      )
      
      mock_provider.add_response("Configured response")
      runner = RAAF::Runner.new(agent: configured_agent, provider: mock_provider)
      
      expect {
        runner.run("Test execution config")
      }.to perform_under(20).ms
    end
  end
  
  describe "Error handling performance" do
    it "handles errors without performance degradation" do
      # Mix successful and failing responses
      mock_provider.add_response("Success 1")
      mock_provider.add_error(RAAF::APIError.new("Transient error"))
      mock_provider.add_response("Success 2")
      mock_provider.add_error(RAAF::RateLimitError.new("Rate limited"))
      mock_provider.add_response("Success 3")
      
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      error_handler = RAAF::ErrorHandler.new(
        strategy: RAAF::RecoveryStrategy::LOG_AND_CONTINUE
      )
      
      responses = []
      
      expect {
        5.times do |i|
          error_handler.with_error_handling do
            responses << runner.run("Request #{i}")
          end
        end
      }.to perform_under(100).ms
      
      expect(responses.compact.size).to eq(3)  # 3 successful responses
    end
  end
  
  describe "Concurrent operations" do
    it "handles concurrent runners efficiently" do
      # Prepare responses for concurrent requests
      100.times { mock_provider.add_response("Concurrent response") }
      
      expect {
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
      }.to perform_under(500).ms
    end
    
    it "maintains thread safety without performance penalty" do
      shared_agent = create_test_agent(name: "SharedAgent")
      100.times { mock_provider.add_response("Thread safe response") }
      
      results = Concurrent::Array.new
      
      expect {
        threads = 10.times.map do |i|
          Thread.new do
            runner = RAAF::Runner.new(agent: shared_agent, provider: mock_provider)
            5.times do |j|
              results << runner.run("Thread #{i} request #{j}")
            end
          end
        end
        threads.each(&:join)
      }.to perform_under(1).sec
      
      expect(results.size).to eq(50)
    end
  end
end
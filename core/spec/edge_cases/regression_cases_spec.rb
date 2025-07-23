# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Regression Cases" do
  let(:mock_provider) { create_mock_provider }
  
  describe "Previously reported bugs" do
    context "agent initialization issues" do
      it "prevents agent creation with duplicate tool names (issue from handoff testing)" do
        agent = create_test_agent(name: "DuplicateToolAgent")
        
        # Add tool with same name twice
        tool1 = RAAF::FunctionTool.new(proc { "first" }, name: "duplicate_tool")
        tool2 = RAAF::FunctionTool.new(proc { "second" }, name: "duplicate_tool")
        
        agent.add_tool(tool1)
        agent.add_tool(tool2)
        
        # Should maintain unique tool names
        tool_names = agent.tools.map(&:name)
        expect(tool_names.uniq.size).to eq(tool_names.size)
      end
      
      it "handles agent creation with nil model parameter" do
        # This was causing issues in early versions
        agent = RAAF::Agent.new(name: "NilModelAgent", model: nil)
        
        expect(agent.model).to be_nil
        
        # Should still be usable with provider's default model
        mock_provider.add_response("Using default model")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        expect { runner.run("Test with nil model") }.not_to raise_error
      end
      
      it "prevents memory leak in agent tool storage" do
        agent = create_test_agent(name: "MemoryLeakAgent")
        
        # Add and remove many tools
        1000.times do |i|
          tool = RAAF::FunctionTool.new(
            proc { "temp tool #{i}" },
            name: "temp_tool_#{i}"
          )
          agent.add_tool(tool)
        end
        
        # Force garbage collection
        GC.start
        initial_objects = ObjectSpace.count_objects[:TOTAL]
        
        # Remove all tools by creating new agent
        agent = create_test_agent(name: "CleanAgent")
        
        GC.start
        final_objects = ObjectSpace.count_objects[:TOTAL]
        
        # Should not have significant object growth
        object_growth = final_objects - initial_objects
        expect(object_growth).to be < 1000  # Allow some growth but not excessive
      end
    end
    
    context "handoff system regressions" do
      it "prevents infinite handoff loops (regression from circular references)" do
        agent1 = create_test_agent(name: "LoopAgent1")
        agent2 = create_test_agent(name: "LoopAgent2")
        
        agent1.add_handoff(agent2)
        agent2.add_handoff(agent1)  # Circular reference
        
        # Simulate handoff execution that could loop
        mock_provider.add_response(
          "Starting potential loop",
          tool_calls: [{ function: { name: "transfer_to_loopagent2", arguments: "{}" } }]
        )
        mock_provider.add_response(
          "In second agent",
          tool_calls: [{ function: { name: "transfer_to_loopagent1", arguments: "{}" } }]
        )
        # No more responses - should prevent infinite loop
        
        runner = RAAF::Runner.new(agent: agent1, provider: mock_provider)
        
        # Should complete without infinite loop
        expect { 
          Timeout.timeout(5) { runner.run("Test loop prevention") }
        }.not_to raise_error
      end
      
      it "handles handoff context preservation (regression from context loss)" do
        research_agent = create_test_agent(name: "ResearchAgent")
        writer_agent = create_test_agent(name: "WriterAgent")
        
        research_agent.add_handoff(writer_agent)
        
        # First response with context
        mock_provider.add_response(
          "Research complete. Key findings: AI is advancing rapidly.",
          tool_calls: [{
            function: {
              name: "transfer_to_writeragent",
              arguments: '{"context": "AI advancement research findings"}'
            }
          }]
        )
        # Second response from writer
        mock_provider.add_response("Article written based on research findings.")
        
        runner = RAAF::Runner.new(agent: research_agent, provider: mock_provider)
        result = runner.run("Research AI trends and write an article")
        
        # Should preserve context through handoff
        expect(result.messages.size).to be >= 2
        
        # Writer's response should reference the research context
        final_message = result.messages.last[:content]
        expect(final_message).to include("findings") # Context preserved
      end
      
      it "prevents handoff to non-existent agents (regression from runtime errors)" do
        agent = create_test_agent(name: "NonExistentHandoffAgent")
        
        # Simulate attempt to handoff to non-existent agent
        mock_provider.add_response(
          "Attempting invalid handoff",
          tool_calls: [{
            function: {
              name: "transfer_to_nonexistentagent",
              arguments: "{}"
            }
          }]
        )
        mock_provider.add_response("Handoff error handled")
        
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        # Should handle gracefully without crashing
        expect { runner.run("Test invalid handoff") }.not_to raise_error
      end
    end
    
    context "tool execution regressions" do
      it "handles tool parameter type coercion (regression from parameter validation)" do
        # Tool expecting integer but receiving string
        type_sensitive_tool = RAAF::FunctionTool.new(
          proc { |count:| 
            # Should handle string-to-integer conversion
            count_int = count.respond_to?(:to_i) ? count.to_i : count
            "Processed #{count_int} items"
          },
          name: "type_coercion_tool"
        )
        
        agent = create_test_agent(name: "TypeCoercionAgent")
        agent.add_tool(type_sensitive_tool)
        
        mock_provider.add_response(
          "Using tool with string parameter",
          tool_calls: [{
            function: {
              name: "type_coercion_tool",
              arguments: '{"count": "42"}'  # String instead of integer
            }
          }]
        )
        mock_provider.add_response("Type coercion handled")
        
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        result = runner.run("Test type coercion")
        expect(result.messages).not_to be_empty
      end
      
      it "handles tool execution with missing optional parameters" do
        # Regression from tools failing when optional params not provided
        optional_param_tool = RAAF::FunctionTool.new(
          proc { |required:, optional: "default"|
            "Required: #{required}, Optional: #{optional}"
          },
          name: "optional_param_tool"
        )
        
        agent = create_test_agent(name: "OptionalParamAgent")
        agent.add_tool(optional_param_tool)
        
        mock_provider.add_response(
          "Using tool without optional param",
          tool_calls: [{
            function: {
              name: "optional_param_tool",
              arguments: '{"required": "test"}'  # Missing optional param
            }
          }]
        )
        mock_provider.add_response("Optional param handled")
        
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        result = runner.run("Test optional parameters")
        expect(result.messages).not_to be_empty
      end
      
      it "prevents tool execution timeout issues (regression from hanging tools)" do
        # Tool that could potentially hang
        potentially_slow_tool = RAAF::FunctionTool.new(
          proc { |delay:|
            if delay.to_f > 10  # Prevent excessive delays in tests
              "Delay too long, using default"
            else
              sleep(delay.to_f)
              "Completed after #{delay}s delay"
            end
          },
          name: "potentially_slow_tool"
        )
        
        agent = create_test_agent(name: "SlowToolAgent")
        agent.add_tool(potentially_slow_tool)
        
        mock_provider.add_response(
          "Using potentially slow tool",
          tool_calls: [{
            function: {
              name: "potentially_slow_tool",
              arguments: '{"delay": 0.1}'  # Short delay for test
            }
          }]
        )
        mock_provider.add_response("Slow tool completed")
        
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        # Should complete within reasonable time
        start_time = Time.now
        result = runner.run("Test slow tool")
        end_time = Time.now
        
        expect(end_time - start_time).to be < 5.0  # Should not hang
        expect(result.messages).not_to be_empty
      end
    end
    
    context "error handling regressions" do
      it "prevents error handler stack overflow (regression from recursive errors)" do
        error_handler = RAAF::ErrorHandler.new(
          strategy: RAAF::RecoveryStrategy::RETURN_ERROR
        )
        
        # Simulate deeply nested error scenario
        deeply_nested_operation = proc do |depth|
          if depth > 0
            begin
              deeply_nested_operation.call(depth - 1)
            rescue => e
              raise StandardError.new("Nested error at depth #{depth}: #{e.message}")
            end
          else
            raise StandardError.new("Base error")
          end
        end
        
        # Should handle deep nesting without stack overflow
        result = error_handler.with_error_handling do
          deeply_nested_operation.call(100)  # 100 levels deep
        end
        
        expect(result[:error]).to be_a(Hash)
        expect(result[:error][:message]).to include("Nested error")
      end
      
      it "handles error recovery with corrupted state (regression from state corruption)" do
        agent = create_test_agent(name: "CorruptedStateAgent")
        error_handler = RAAF::ErrorHandler.new(
          strategy: RAAF::RecoveryStrategy::RETRY_ONCE,
          max_retries: 2
        )
        
        attempt_count = 0
        
        result = error_handler.with_error_handling do
          attempt_count += 1
          
          # Simulate state corruption on first attempt
          if attempt_count == 1
            agent.instance_variable_set(:@name, nil)  # Corrupt state
            raise RAAF::APIError.new("State corrupted")
          else
            # Recover state
            agent.instance_variable_set(:@name, "RecoveredAgent")
            "Recovery successful"
          end
        end
        
        expect(result).to eq("Recovery successful")
        expect(attempt_count).to eq(2)
        expect(agent.name).to eq("RecoveredAgent")
      end
      
      it "prevents memory leaks in error handling (regression from error accumulation)" do
        error_handler = RAAF::ErrorHandler.new(
          strategy: RAAF::RecoveryStrategy::RETURN_ERROR
        )
        
        initial_objects = ObjectSpace.count_objects[:TOTAL]
        
        # Generate many errors
        1000.times do |i|
          error_handler.with_error_handling do
            raise StandardError.new("Error #{i} with data: #{'x' * 1000}")
          end
        end
        
        GC.start
        final_objects = ObjectSpace.count_objects[:TOTAL]
        
        # Should not accumulate excessive objects
        object_growth = final_objects - initial_objects
        expect(object_growth).to be < 10_000  # Allow some growth but not excessive
      end
    end
    
    context "configuration regressions" do
      it "handles configuration merging edge cases (regression from config conflicts)" do
        base_config = RAAF::RunConfig.new(
          max_turns: 10,
          max_tokens: 1000,
          metadata: { app: "base", version: "1.0" }
        )
        
        override_config = RAAF::RunConfig.new(
          max_turns: 20,
          metadata: { app: "override", env: "test" }
        )
        
        # Merge should handle nested hash merging correctly
        merged = base_config.merge(override_config)
        
        expect(merged.max_turns).to eq(20)  # Overridden
        expect(merged.max_tokens).to eq(1000)  # Preserved
        expect(merged.metadata[:app]).to eq("override")  # Overridden
        expect(merged.metadata[:version]).to eq("1.0")  # Preserved
        expect(merged.metadata[:env]).to eq("test")  # Added
      end
      
      it "handles nil configuration values correctly (regression from nil handling)" do
        nil_config = RAAF::RunConfig.new(
          max_turns: nil,
          max_tokens: nil,
          temperature: nil,
          metadata: nil
        )
        
        agent = create_test_agent(name: "NilConfigAgent")
        mock_provider.add_response("Nil config handled")
        
        # Should not crash with nil values
        expect {
          runner = RAAF::Runner.new(agent: agent, config: nil_config, provider: mock_provider)
          runner.run("Test nil config")
        }.not_to raise_error
      end
    end
    
    context "memory management regressions" do
      it "prevents agent reference cycles (regression from memory leaks)" do
        # Create agents that reference each other
        agent1 = create_test_agent(name: "RefCycleAgent1")
        agent2 = create_test_agent(name: "RefCycleAgent2")
        
        # Create potential reference cycle through handoffs
        agent1.add_handoff(agent2)
        agent2.add_handoff(agent1)
        
        # Store weak references to detect if objects can be collected
        agent1_weak = ObjectSpace._id2ref(agent1.object_id) rescue nil
        agent2_weak = ObjectSpace._id2ref(agent2.object_id) rescue nil
        
        # Clear strong references
        agent1 = nil
        agent2 = nil
        
        # Force garbage collection
        GC.start
        
        # Objects should be collectible despite handoff references
        # (This test might be implementation-dependent)
        expect([agent1_weak, agent2_weak]).to include(nil)
      end
      
      it "handles large conversation history without memory explosion" do
        agent = create_test_agent(name: "LargeHistoryAgent")
        mock_provider.add_response("Large history handled")
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        # Create progressively larger histories
        [100, 500, 1000, 2000].each do |size|
          large_history = size.times.map do |i|
            {
              role: i.even? ? "user" : "assistant",
              content: "Message #{i} with content " * 10  # Make messages substantial
            }
          end
          
          initial_memory = GC.stat[:heap_allocated_pages]
          
          result = runner.run("Process large history", previous_messages: large_history)
          
          final_memory = GC.stat[:heap_allocated_pages] 
          memory_growth = final_memory - initial_memory
          
          # Memory growth should be proportional, not exponential
          expect(memory_growth).to be < (size / 10)  # Rough heuristic
          expect(result.messages.size).to eq(size + 2)  # History + new + response
        end
      end
    end
    
    context "threading regressions" do
      it "prevents race conditions in tool addition (regression from concurrent modifications)" do
        agent = create_test_agent(name: "RaceConditionAgent")
        
        # Add tools from multiple threads
        threads = 5.times.map do |thread_id|
          Thread.new do
            10.times do |tool_id|
              tool = RAAF::FunctionTool.new(
                proc { "Thread #{thread_id} tool #{tool_id}" },
                name: "thread_#{thread_id}_tool_#{tool_id}"
              )
              agent.add_tool(tool)
              
              # Small random delay to increase chance of race conditions
              sleep(rand * 0.001)
            end
          end
        end
        
        threads.each(&:join)
        
        # Should have all tools without corruption
        expect(agent.tools.size).to eq(50)
        expect(agent.tools.map(&:name).uniq.size).to eq(50)  # All unique
        
        # All tools should be functional
        agent.tools.each do |tool|
          expect(tool.execute({})).to be_a(String)
        end
      end
      
      it "handles concurrent runner execution safely (regression from shared state issues)" do
        shared_agent = create_test_agent(name: "SharedStateAgent")
        
        # Prepare responses for concurrent execution
        100.times { mock_provider.add_response("Concurrent execution") }
        
        results = Concurrent::Array.new
        errors = Concurrent::Array.new
        
        # Multiple threads using same agent simultaneously
        threads = 10.times.map do |i|
          Thread.new do
            runner = RAAF::Runner.new(agent: shared_agent, provider: mock_provider)
            
            10.times do |j|
              begin
                result = runner.run("Concurrent test #{i}-#{j}")
                results << result
              rescue => e
                errors << { thread: i, iteration: j, error: e }
              end
            end
          end
        end
        
        threads.each(&:join)
        
        # Should complete without errors
        expect(errors).to be_empty
        expect(results.size).to eq(100)
        
        # All results should be valid
        expect(results.all? { |r| r.is_a?(RAAF::RunResult) }).to be true
      end
    end
  end
  
  describe "Edge case combinations" do
    it "handles multiple edge cases simultaneously" do
      # Agent with edge case configuration
      agent = create_test_agent(
        name: "",  # Empty name
        instructions: nil,  # Nil instructions
        max_turns: 0  # Zero turns
      )
      
      # Tool with edge case parameters
      edge_tool = RAAF::FunctionTool.new(
        proc { |*args, **kwargs| 
          "Args: #{args.inspect}, Kwargs: #{kwargs.inspect}"
        },
        name: "edge_case_tool",
        description: ""  # Empty description
      )
      
      agent.add_tool(edge_tool)
      
      # Mock response with edge cases
      mock_provider.add_response(
        "",  # Empty response content
        tool_calls: [{
          function: {
            name: "edge_case_tool",
            arguments: "{}"  # Empty arguments
          }
        }]
      )
      mock_provider.add_response("Edge cases handled")
      
      # Configuration with edge cases
      edge_config = RAAF::RunConfig.new(
        max_turns: nil,
        max_tokens: 0,
        temperature: nil,
        metadata: {}
      )
      
      runner = RAAF::Runner.new(
        agent: agent,
        config: edge_config,
        provider: mock_provider
      )
      
      # Should handle multiple edge cases without crashing
      expect { runner.run("") }.not_to raise_error  # Empty input too
    end
  end
end
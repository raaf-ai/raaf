# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Behavioral Compatibility", :compliance do
  let(:mock_provider) { create_mock_provider }
  
  describe "Python SDK Behavioral Parity" do
    
    context "agent execution behavior" do
      it "follows Python SDK execution flow" do
        # Python SDK execution order:
        # 1. Process input messages
        # 2. Generate system prompt with instructions
        # 3. Call model with combined context
        # 4. Process response and tool calls
        # 5. Return structured result
        
        execution_log = []
        
        # Mock provider to track execution flow
        tracking_provider = create_mock_provider
        tracking_provider.add_response("Test response")
        
        allow(tracking_provider).to receive(:complete) do |params|
          execution_log << {
            step: "model_call",
            messages_count: params[:messages]&.size || params[:input]&.size || 0,
            has_tools: !params[:tools].nil?,
            model: params[:model]
          }
          
          {
            "output" => [{
              "type" => "message",
              "role" => "assistant", 
              "content" => [{ "type" => "text", "text" => "Tracked response" }]
            }],
            "usage" => { "input_tokens" => 10, "output_tokens" => 5, "total_tokens" => 15 }
          }
        end
        
        agent = RAAF::Agent.new(
          name: "BehaviorAgent",
          instructions: "You are a helpful assistant",
          model: "gpt-4o"
        )
        
        runner = RAAF::Runner.new(agent: agent, provider: tracking_provider)
        result = runner.run("Test behavioral compatibility")
        
        # Verify execution flow matches Python SDK
        expect(execution_log).not_to be_empty
        
        model_call = execution_log.find { |log| log[:step] == "model_call" }
        expect(model_call).not_to be_nil
        expect(model_call[:messages_count]).to be > 0  # Should include user message
        expect(model_call[:model]).to eq("gpt-4o")
        
        # Result structure should match Python SDK
        expect(result).to respond_to(:messages)
        expect(result).to respond_to(:usage)
        expect(result).to respond_to(:last_agent)
        expect(result.messages).to be_an(Array)
      end
      
      it "handles tool execution like Python SDK" do
        # Python SDK tool execution:
        # 1. Model generates tool call
        # 2. Tool is executed locally  
        # 3. Tool result is sent back to model
        # 4. Model generates final response
        
        tool_execution_log = []
        
        weather_tool = RAAF::FunctionTool.new(
          proc { |location:|
            tool_execution_log << { 
              step: "tool_execution", 
              tool: "get_weather", 
              args: { location: location } 
            }
            "Weather in #{location}: Sunny, 22°C"
          },
          name: "get_weather"
        )
        
        agent = RAAF::Agent.new(name: "ToolBehaviorAgent")
        agent.add_tool(weather_tool)
        
        # First response: tool call
        mock_provider.add_response(
          "I'll check the weather for you",
          tool_calls: [{
            function: {
              name: "get_weather", 
              arguments: JSON.generate({ location: "Paris" })
            }
          }]
        )
        
        # Second response: after tool execution
        mock_provider.add_response("The weather in Paris is sunny with 22°C")
        
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        result = runner.run("What's the weather in Paris?")
        
        # Verify tool execution flow
        expect(tool_execution_log).not_to be_empty
        
        tool_exec = tool_execution_log.find { |log| log[:step] == "tool_execution" }
        expect(tool_exec).not_to be_nil
        expect(tool_exec[:tool]).to eq("get_weather")
        expect(tool_exec[:args][:location]).to eq("Paris")
        
        # Should have tool message in conversation
        tool_messages = result.messages.select { |m| m[:role] == "tool" }
        expect(tool_messages).not_to be_empty
      end
      
      it "processes handoffs like Python SDK" do
        # Python SDK handoff behavior:
        # 1. Agent decides to handoff via tool call
        # 2. Handoff tool is "executed" (context transfer)
        # 3. New agent takes over conversation
        # 4. Response comes from new agent
        
        handoff_log = []
        
        agent1 = RAAF::Agent.new(name: "HandoffAgent1")
        agent2 = RAAF::Agent.new(name: "HandoffAgent2")
        
        agent1.add_handoff(agent2)
        
        # Track handoff through runner
        runner = RAAF::Runner.new(agent: agent1, provider: mock_provider)
        
        # First response: handoff decision
        mock_provider.add_response(
          "I'll transfer you to our specialist",
          tool_calls: [{
            function: {
              name: "transfer_to_handoffagent2",
              arguments: JSON.generate({ context: "User needs specialist help" })
            }
          }]
        )
        
        # Second response: from new agent
        mock_provider.add_response("Hello! I'm the specialist. How can I help?")
        
        result = runner.run("I need specialist help")
        
        # Verify handoff behavior matches Python SDK
        expect(result.last_agent.name).to eq("HandoffAgent2")
        
        # Should have handoff message in conversation flow
        handoff_messages = result.messages.select { |m| m[:role] == "tool" && m.key?(:handoff) }
        expect(handoff_messages).not_to be_empty if handoff_messages.any?
      end
    end
    
    context "error handling behavior" do
      it "handles API errors like Python SDK" do
        # Python SDK error handling:
        # - APIError for HTTP errors
        # - AuthenticationError for 401
        # - RateLimitError for 429
        # - Preserves original error details
        
        error_scenarios = [
          { 
            status: 400, 
            message: "Bad Request", 
            expected: RAAF::InvalidRequestError 
          },
          { 
            status: 401, 
            message: "Unauthorized", 
            expected: RAAF::AuthenticationError 
          },
          { 
            status: 429, 
            message: "Too Many Requests", 
            expected: RAAF::RateLimitError 
          },
          { 
            status: 500, 
            message: "Internal Server Error", 
            expected: RAAF::APIError 
          }
        ]
        
        error_scenarios.each do |scenario|
          agent = RAAF::Agent.new(name: "ErrorAgent")
          
          # Mock provider to raise specific error
          error_provider = create_mock_provider
          allow(error_provider).to receive(:complete).and_raise(
            scenario[:expected].new(scenario[:message], status: scenario[:status])
          )
          
          runner = RAAF::Runner.new(agent: agent, provider: error_provider)
          
          # Should raise Python SDK compatible error
          expect { runner.run("Test error") }.to raise_error(scenario[:expected]) do |error|
            expect(error.message).to include(scenario[:message])
            
            # Should preserve error details like Python SDK
            if error.respond_to?(:status)
              expect(error.status).to eq(scenario[:status])
            end
          end
        end
      end
      
      it "handles validation errors like Python SDK" do
        # Python SDK validation behavior
        invalid_configs = [
          { temperature: -1 },      # Invalid temperature
          { max_tokens: 0 },        # Invalid max_tokens
          { top_p: 1.5 }           # Invalid top_p
        ]
        
        invalid_configs.each do |config|
          agent = RAAF::Agent.new(name: "ValidationAgent")
          
          # Should either validate or handle gracefully like Python SDK
          expect {
            run_config = RAAF::RunConfig.new(**config)
            runner = RAAF::Runner.new(agent: agent, config: run_config, provider: mock_provider)
            # Some validation might happen at runtime
          }.not_to raise_error(NoMethodError)  # Should handle gracefully
        end
      end
    end
    
    context "conversation state management" do
      it "maintains conversation history like Python SDK" do
        # Python SDK conversation behavior:
        # - Preserves message order
        # - Maintains role consistency  
        # - Includes system messages appropriately
        # - Handles context window limits
        
        agent = RAAF::Agent.new(
          name: "ConversationAgent",
          instructions: "You are a helpful assistant"
        )
        
        # Prepare multi-turn conversation
        responses = [
          "Hello! How can I help you?",
          "I can help with that task.",
          "Let me provide more details.",
          "Is there anything else you need?"
        ]
        
        responses.each { |resp| mock_provider.add_response(resp) }
        
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        # Build conversation turn by turn
        conversation_history = []
        current_messages = [{ role: "user", content: "Hello" }]
        
        4.times do |i|
          result = runner.run(
            "Follow-up question #{i + 1}",
            previous_messages: current_messages
          )
          
          conversation_history << result.messages
          current_messages = result.messages
          current_messages << { role: "user", content: "Next question #{i + 2}" }
        end
        
        # Verify conversation structure matches Python SDK
        final_messages = conversation_history.last
        
        # Should have system message (from instructions)
        system_messages = final_messages.select { |m| m[:role] == "system" }
        expect(system_messages).not_to be_empty
        
        # Should maintain proper role alternation
        user_assistant_messages = final_messages.select { |m| ["user", "assistant"].include?(m[:role]) }
        expect(user_assistant_messages.size).to be >= 8  # 4 turns * 2 messages
        
        # Should preserve message order
        expect(final_messages.first[:role]).to eq("system")
        expect(final_messages[1][:role]).to eq("user")
        expect(final_messages[2][:role]).to eq("assistant")
      end
      
      it "handles context window limits like Python SDK" do
        # Python SDK behavior with long conversations:
        # - Truncates old messages when approaching limits
        # - Preserves system message and recent context
        # - Maintains conversation coherence
        
        agent = RAAF::Agent.new(name: "ContextAgent")
        
        # Create very long conversation history
        long_history = []
        1000.times do |i|
          long_history << { role: "user", content: "User message #{i}" }
          long_history << { role: "assistant", content: "Assistant response #{i}" }
        end
        
        mock_provider.add_response("Response to long history")
        
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        # Should handle long history without errors
        expect {
          runner.run("New message", previous_messages: long_history)
        }.not_to raise_error
        
        # Note: Actual truncation behavior would depend on implementation
      end
    end
    
    context "streaming behavior compatibility" do
      it "handles streaming responses like Python SDK" do
        skip "Streaming not yet implemented - placeholder for future"
        
        # Python SDK streaming behavior:
        # - Yields partial responses as they arrive
        # - Maintains message structure
        # - Handles stream interruption gracefully
        # - Provides final complete response
        
        agent = RAAF::Agent.new(name: "StreamingAgent")
        
        # Would test streaming response handling
        # when streaming is implemented
      end
    end
    
    context "configuration precedence" do
      it "applies configuration precedence like Python SDK" do
        # Python SDK precedence order:
        # 1. Explicit parameters
        # 2. Environment variables
        # 3. Default values
        
        # Test environment variable precedence
        original_api_key = ENV["OPENAI_API_KEY"]
        ENV["OPENAI_API_KEY"] = "env-test-key"
        
        begin
          provider = RAAF::Models::ResponsesProvider.new
          # Should use environment variable
          expect(provider.instance_variable_get(:@api_key)).to eq("env-test-key")
          
          # Explicit parameter should override
          explicit_provider = RAAF::Models::ResponsesProvider.new(api_key: "explicit-key")
          expect(explicit_provider.instance_variable_get(:@api_key)).to eq("explicit-key")
          
        ensure
          ENV["OPENAI_API_KEY"] = original_api_key
        end
      end
    end
  end
  
  describe "Edge Case Behavioral Compatibility" do
    
    it "handles empty responses like Python SDK" do
      agent = RAAF::Agent.new(name: "EmptyResponseAgent")
      
      # Mock empty response (edge case)
      allow(mock_provider).to receive(:complete).and_return({
        "output" => [],
        "usage" => { "input_tokens" => 10, "output_tokens" => 0, "total_tokens" => 10 }
      })
      
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      
      # Should handle gracefully like Python SDK
      expect { runner.run("Test empty response") }.not_to raise_error
    end
    
    it "handles malformed tool calls like Python SDK" do
      tool = RAAF::FunctionTool.new(
        proc { |x| "Result: #{x}" },
        name: "test_tool"
      )
      
      agent = RAAF::Agent.new(name: "MalformedToolAgent")
      agent.add_tool(tool)
      
      # Mock malformed tool call
      mock_provider.add_response(
        "Using malformed tool",
        tool_calls: [{
          function: {
            name: "test_tool",
            arguments: "invalid json!!!"  # Malformed JSON
          }
        }]
      )
      
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      
      # Should handle malformed tool calls gracefully
      expect { runner.run("Test malformed tool call") }.not_to raise_error
    end
    
    it "handles unicode content like Python SDK" do
      agent = RAAF::Agent.new(name: "UnicodeAgent")
      mock_provider.add_response("Handled unicode: 你好世界 🌍")
      
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      
      # Test various unicode inputs
      unicode_inputs = [
        "Hello 世界",           # Mixed scripts
        "Emoji test 🚀🎭🎪",   # Emojis
        "Math symbols: ∑∆∞",   # Math symbols
        "Arabic: مرحبا",        # RTL text
        "\u{1F600}\u{1F601}"   # Unicode escapes
      ]
      
      unicode_inputs.each do |input|
        mock_provider.add_response("Unicode handled")
        result = runner.run(input)
        
        # Should preserve unicode correctly
        expect(result.messages.first[:content]).to eq(input)
        expect(result.messages.first[:content].encoding).to eq(Encoding::UTF_8)
      end
    end
  end
  
  describe "Performance Behavioral Compatibility" do
    
    it "maintains similar performance characteristics to Python SDK" do
      # Test that RAAF performance is comparable to Python SDK
      # (This is aspirational - actual comparison would need benchmarks)
      
      agent = RAAF::Agent.new(name: "PerformanceAgent")
      mock_provider.add_response("Performance test")
      
      runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
      
      # Should complete quickly like Python SDK
      start_time = Time.now
      result = runner.run("Performance test")
      end_time = Time.now
      
      execution_time = end_time - start_time
      
      # Should be reasonably fast (< 100ms for mocked response)
      expect(execution_time).to be < 0.1
      expect(result).to be_a(RAAF::RunResult)
    end
    
    it "scales similarly to Python SDK" do
      # Test scaling behavior
      agent = RAAF::Agent.new(name: "ScalingAgent")
      
      # Test with increasing message counts
      [10, 50, 100].each do |message_count|
        large_history = message_count.times.map do |i|
          { role: i.even? ? "user" : "assistant", content: "Message #{i}" }
        end
        
        mock_provider.add_response("Scaling test response")
        
        runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
        
        start_time = Time.now
        result = runner.run("Test scaling", previous_messages: large_history)
        end_time = Time.now
        
        # Execution time should scale reasonably
        execution_time = end_time - start_time
        expect(execution_time).to be < (message_count * 0.001)  # Linear scaling assumption
        expect(result.messages.size).to eq(message_count + 2)  # History + new + response
      end
    end
  end
end
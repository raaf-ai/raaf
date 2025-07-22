# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Runner, "Enhanced Core Functionality Tests" do
  let(:agent) { RAAF::Agent.new(name: "TestAgent", instructions: "You are helpful", model: "gpt-4") }
  let(:mock_provider) { instance_double(RAAF::Models::ResponsesProvider) }
  let(:runner) { described_class.new(agent: agent, provider: mock_provider) }
  
  # Helper to set up provider expectations with flexible argument matching
  def expect_provider_call(response)
    allow(mock_provider).to receive(:responses_completion).and_return(response)
  end
  
  # Set up provider type checking
  before do
    allow(mock_provider).to receive(:is_a?).and_return(false)
    allow(mock_provider).to receive(:is_a?).with(RAAF::Models::ResponsesProvider).and_return(true)
  end
  
  # Common response fixtures available to all tests
  let(:basic_response) do
    {
      id: "resp_123",
      output: [
        {
          type: "message",
          role: "assistant",
          content: [{ type: "output_text", text: "Hello! How can I help?" }]
        }
      ],
      usage: { input_tokens: 10, output_tokens: 15, total_tokens: 25 }
    }
  end

  describe "Core Execution Engine - execute_responses_api_core" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:config) { RAAF::RunConfig.new(max_turns: 5) }

    context "single turn conversation" do
      it "executes basic conversation flow" do
        expect_provider_call(basic_response)
        
        result = runner.run("Hello")
        
        expect(result).to be_a(RAAF::RunResult)
        expect(result.success?).to be true
        expect(result.messages.length).to be >= 2 # User + assistant
        expect(result.turns).to eq(1)
      end

      it "handles provider errors gracefully" do
        allow(mock_provider).to receive(:responses_completion)
          .and_raise(RAAF::Models::APIError.new("Service unavailable"))
        
        expect {
          runner.run("Hello")
        }.to raise_error(RAAF::Models::APIError)
      end

      it "validates response structure" do
        invalid_response = { invalid: "response" }
        expect_provider_call(invalid_response)
        
        expect {
          runner.run("Hello")
        }.to raise_error(StandardError) # Should raise due to invalid response structure
      end
    end

    context "multi-turn conversations" do
      it "handles multiple turns correctly" do
        # First turn - assistant calls a tool
        turn1_response = {
          id: "resp_1",
          output: [
            {
              type: "message",
              role: "assistant", 
              content: [{ type: "output_text", text: "Let me calculate that for you." }]
            },
            {
              type: "function_call",
              id: "call_123",
              name: "calculate",
              arguments: '{"x": 5, "y": 3}'
            }
          ],
          usage: { input_tokens: 10, output_tokens: 10, total_tokens: 20 }
        }
        
        # Second turn - assistant responds after tool execution
        turn2_response = {
          id: "resp_2",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "The result is 8." }]
            }
          ],
          usage: { input_tokens: 20, output_tokens: 10, total_tokens: 30 }
        }
        
        # Add a tool to the agent for this test
        calculator_tool = RAAF::FunctionTool.new(
          proc { |x:, y:| x + y },
          name: "calculate",
          description: "Add two numbers"
        )
        agent.add_tool(calculator_tool)
        
        call_count = 0
        allow(mock_provider).to receive(:responses_completion) do
          call_count += 1
          call_count == 1 ? turn1_response : turn2_response
        end
        
        # Simulate a conversation that requires multiple turns
        config = RAAF::RunConfig.new(max_turns: 3)
        result = runner.run("Calculate 5 + 3", config: config)
        
        expect(result.success?).to be true
        expect(result.turns).to eq(2) # Two API calls = 2 turns
        
        # Check that we have multiple messages including user and assistant
        expect(result.messages.length).to be >= 3 # At least user + 2 assistant responses
        expect(result.messages.first[:role]).to eq("user")
        expect(result.messages.select { |m| m[:role] == "assistant" }.length).to be >= 2
      end

      it "respects max_turns limit" do
        config = RAAF::RunConfig.new(max_turns: 2)
        
        # Mock responses that would continue indefinitely
        continuing_response = {
          id: "resp_continue",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "Continue..." }]
            }
          ],
          usage: { input_tokens: 10, output_tokens: 10, total_tokens: 20 }
        }
        
        expect_provider_call(continuing_response)
        
        result = runner.run("Start", config: config)
        expect(result.turns).to be <= 2
      end
    end

    context "tool execution integration" do
      let(:tool_response) do
        {
          id: "resp_tool",
          output: [
            {
              type: "function_call",
              name: "test_tool",
              arguments: '{"param": "value"}',
              call_id: "call_123"
            }
          ],
          usage: { input_tokens: 15, output_tokens: 20, total_tokens: 35 }
        }
      end

      let(:tool_result_response) do
        {
          id: "resp_result",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "Tool executed successfully" }]
            }
          ],
          usage: { input_tokens: 25, output_tokens: 15, total_tokens: 40 }
        }
      end

      before do
        # Add a test tool to the agent
        agent.add_tool(proc { |param:| "Tool result: #{param}" }, 
                      name: "test_tool", 
                      description: "A test tool")
      end

      it "executes tools during conversation" do
        call_count = 0
        allow(mock_provider).to receive(:responses_completion) do
          call_count += 1
          call_count == 1 ? tool_response : tool_result_response
        end
        
        result = runner.run("Use the test tool")
        
        expect(result.success?).to be true
        expect(result.tool_results).not_to be_empty
      end

      it "handles tool execution errors" do
        # Mock tool that raises an error
        agent.add_tool(proc { |param:| raise StandardError, "Tool failed" }, 
                      name: "error_tool", 
                      description: "A tool that fails")
        
        error_tool_response = {
          id: "resp_error_tool",
          output: [
            {
              type: "function_call", 
              name: "error_tool",
              arguments: '{"param": "test"}',
              call_id: "call_error"
            }
          ],
          usage: { input_tokens: 15, output_tokens: 20, total_tokens: 35 }
        }
        
        final_response = {
          id: "resp_final",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "I encountered an error with the tool." }]
            }
          ],
          usage: { input_tokens: 25, output_tokens: 15, total_tokens: 40 }
        }
        
        call_count = 0
        allow(mock_provider).to receive(:responses_completion) do
          call_count += 1
          call_count == 1 ? error_tool_response : final_response
        end
        
        result = runner.run("Use the error tool")
        
        # Should handle tool error gracefully
        expect(result.success?).to be true
        # Tool error should be captured in tool results
        expect(result.tool_results.any? { |tr| tr.to_s.include?("failed") || tr.to_s.include?("Error") }).to be true
      end
    end
  end

  describe "Agent Handoff System" do
    let(:target_agent) { RAAF::Agent.new(name: "TargetAgent", instructions: "I handle specific tasks") }
    
    before do
      agent.add_handoff(target_agent)
    end

    context "handoff tool execution" do
      let(:handoff_response) do
        {
          id: "resp_handoff",
          output: [
            {
              type: "function_call",
              name: "transfer_to_target_agent",
              arguments: '{"context": "user needs help"}',
              call_id: "call_handoff"
            }
          ],
          usage: { input_tokens: 20, output_tokens: 15, total_tokens: 35 }
        }
      end

      let(:target_response) do
        {
          id: "resp_target",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "I'll help with that specific task" }]
            }
          ],
          usage: { input_tokens: 25, output_tokens: 20, total_tokens: 45 }
        }
      end

      it "processes handoff tool calls successfully" do
        call_count = 0
        allow(mock_provider).to receive(:responses_completion) do
          call_count += 1
          call_count == 1 ? handoff_response : target_response
        end
        
        # Use a runner that knows about both agents
        runner_with_agents = described_class.new(agent: agent, provider: mock_provider)
        result = runner_with_agents.run("I need specific help", agents: [agent, target_agent])
        
        expect(result.success?).to be true
        expect(result.last_agent&.name).to eq("TargetAgent")
      end

      it "handles invalid handoff targets" do
        invalid_handoff_response = {
          id: "resp_invalid",
          output: [
            {
              type: "function_call",
              name: "transfer_to_nonexistent",
              arguments: '{}',
              call_id: "call_invalid"
            }
          ],
          usage: { input_tokens: 20, output_tokens: 15, total_tokens: 35 }
        }
        
        expect_provider_call(invalid_handoff_response)
        
        result = runner.run("Transfer somewhere invalid")
        
        # Should handle invalid handoff gracefully
        expect(result.success?).to be true
        expect(result.last_agent&.name).to eq("TestAgent") # Stays with original
      end

      it "prevents circular handoffs" do
        # Create circular reference: agent -> target -> agent
        target_agent.add_handoff(agent)
        
        # Mock responses that would create infinite loop
        expect_provider_call(handoff_response)
        
        config = RAAF::RunConfig.new(max_turns: 10)
        result = runner.run("Start circular handoff", config: config)
        
        # Should complete without infinite loop
        expect(result.success?).to be true
        expect(result.turns).to be <= 10
      end
    end

    context "agent name extraction and validation" do
      it "extracts agent names from handoff tools correctly" do
        # Test the private method indirectly by verifying behavior
        tool_names = [
          "transfer_to_supportagent",
          "transfer_to_billing_agent", 
          "transfer_to_technical",
          "handoff_to_specialist"
        ]
        
        tool_names.each do |tool_name|
          # This tests the extract_agent_name_from_tool method indirectly
          extracted_name = runner.send(:extract_agent_name_from_tool, tool_name)
          expect(extracted_name).to be_a(String)
          expect(extracted_name.length).to be > 0
        end
      end

      it "validates handoff targets against available agents" do
        available_targets = runner.send(:get_available_handoff_targets, agent)
        expect(available_targets).to include("TargetAgent")
        expect(available_targets).not_to include("NonexistentAgent")
      end
    end
  end

  describe "Tool Management System" do
    before do
      agent.add_tool(proc { |query:| "Search results for: #{query}" }, 
                    name: "search", 
                    description: "Search for information")
                    
      agent.add_tool(proc { |text:| text.upcase }, 
                    name: "uppercase", 
                    description: "Convert text to uppercase")
    end

    context "tool collection and API formatting" do
      it "collects all available tools for API calls" do
        tools = runner.send(:get_all_tools_for_api, agent, Set.new)
        
        expect(tools).to be_an(Array)
        expect(tools.length).to be >= 2 # Our 2 tools + any handoff tools
        
        # Verify tools are FunctionTool objects
        tools.each do |tool|
          expect(tool).to be_a(RAAF::FunctionTool)
          expect(tool.name).to be_a(String)
          expect(tool.description).to be_a(String)
        end
      end

      it "prevents infinite recursion in tool collection" do
        # Test with potential circular reference
        visited_agents = Set.new
        
        # Should not hang or crash
        expect {
          tools = runner.send(:get_all_tools_for_api, agent, visited_agents)
          expect(tools).to be_an(Array)
        }.not_to raise_error
      end
    end

    context "tool execution with different argument formats" do
      it "handles JSON string arguments" do
        tool_call_item = {
          name: "search",
          arguments: '{"query": "test"}',
          call_id: "call_123"
        }
        result = runner.send(:execute_tool_for_responses_api, tool_call_item, agent)
        
        expect(result).to be_a(String)
        expect(result).to include("test")
      end

      it "handles hash arguments" do
        tool_call_item = {
          name: "uppercase",
          arguments: '{"text": "hello"}',
          call_id: "call_456"
        }
        result = runner.send(:execute_tool_for_responses_api, tool_call_item, agent)
        
        expect(result).to be_a(String)
        expect(result).to eq("HELLO")
      end

      it "handles invalid tool arguments gracefully" do
        tool_call_item = {
          name: "search",
          arguments: "invalid json",
          call_id: "call_789"
        }
        result = runner.send(:execute_tool_for_responses_api, tool_call_item, agent)
        
        # Should handle invalid JSON gracefully
        expect(result).to be_a(String)
        expect(result).to include("Error")
      end

      it "handles missing tool execution" do
        tool_call_item = {
          name: "nonexistent_tool",
          arguments: "{}",
          call_id: "call_000"
        }
        result = runner.send(:execute_tool_for_responses_api, tool_call_item, agent)
        
        expect(result).to be_a(String)
        expect(result).to include("not found")
      end
    end
  end

  describe "Configuration and Lifecycle Management" do
    context "initialization with various configurations" do
      it "initializes with custom context manager" do
        custom_context_manager = instance_double(RAAF::ContextManager)
        runner = described_class.new(agent: agent, context_manager: custom_context_manager)
        
        expect(runner.instance_variable_get(:@context_manager)).to eq(custom_context_manager)
      end

      it "initializes with stop checker" do
        stop_checker = proc { false }
        runner = described_class.new(agent: agent, stop_checker: stop_checker)
        
        expect(runner.stop_checker).to eq(stop_checker)
      end

      it "initializes with memory manager", skip: "Memory manager in separate gem" do
        # This would test memory manager integration when available
      end
    end

    context "lifecycle hooks" do
      let(:hooks_called) { [] }
      let(:mock_context) { double("RunContextWrapper") }

      it "calls before_run hooks" do
        hooks_object = double("Hooks")
        allow(hooks_object).to receive(:respond_to?).with(:before_run).and_return(true)
        allow(hooks_object).to receive(:before_run) do |context|
          hooks_called << :before_run
        end
        
        config = double("Config", hooks: hooks_object)
        runner.instance_variable_set(:@current_config, config)
        
        runner.send(:call_hook, :before_run, mock_context)
        
        expect(hooks_called).to include(:before_run)
      end

      it "calls after_run hooks" do
        hooks_object = double("Hooks")
        allow(hooks_object).to receive(:respond_to?).with(:after_run).and_return(true)
        allow(hooks_object).to receive(:after_run) do |context|
          hooks_called << :after_run
        end
        
        config = double("Config", hooks: hooks_object)
        runner.instance_variable_set(:@current_config, config)
        
        runner.send(:call_hook, :after_run, mock_context)
        
        expect(hooks_called).to include(:after_run)
      end

      it "handles hook execution errors gracefully" do
        hooks_object = double("Hooks")
        allow(hooks_object).to receive(:respond_to?).with(:before_run).and_return(true)
        allow(hooks_object).to receive(:before_run) do |context|
          raise StandardError, "Hook failed"
        end
        
        config = double("Config", hooks: hooks_object)
        runner.instance_variable_set(:@current_config, config)
        
        expect {
          runner.send(:call_hook, :before_run, mock_context)
        }.not_to raise_error # Should handle hook errors gracefully
      end
    end
  end

  describe "System Prompt Building" do
    context "dynamic prompt generation" do
      let(:mock_context) { instance_double(RAAF::RunContextWrapper) }
      
      before do
        allow(mock_context).to receive(:fetch).and_return(nil)
        allow(mock_context).to receive(:current_agent).and_return(agent)
      end

      it "builds basic system prompt" do
        prompt = runner.send(:build_system_prompt, agent, mock_context)
        
        expect(prompt).to be_a(String)
        expect(prompt).to include("You are helpful") # Agent's instructions
      end

      it "includes handoff instructions when agents available" do
        # Add handoff target
        target_agent = RAAF::Agent.new(name: "Helper", instructions: "I help", model: "gpt-4")
        agent.add_handoff(target_agent)
        
        prompt = runner.send(:build_system_prompt, agent, mock_context)
        
        expect(prompt).to include("transfer_to_helper") # Handoff tool
      end

      it "handles context data in prompts" do
        allow(mock_context).to receive(:store).with(:user_name, "John")
        allow(mock_context).to receive(:fetch).with(:user_name, anything).and_return("John")
        
        prompt = runner.send(:build_system_prompt, agent, mock_context)
        
        # Should handle context appropriately (specific behavior depends on implementation)
        expect(prompt).to be_a(String)
        expect(prompt.length).to be > 0
      end
    end
  end

  describe "Message Building and Formatting" do
    context "conversation formatting for API" do
      let(:conversation_messages) do
        [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi there!" },
          { role: "user", content: "How are you?" }
        ]
      end
      
      let(:mock_context) { instance_double(RAAF::RunContextWrapper) }
      
      before do
        allow(mock_context).to receive(:fetch).and_return(nil)
        allow(mock_context).to receive(:current_agent).and_return(agent)
      end

      it "builds properly formatted messages for API" do
        messages = runner.send(:build_messages, conversation_messages, agent, mock_context)
        
        expect(messages).to be_an(Array)
        expect(messages).not_to be_empty
        
        # Should include system message + conversation messages
        expect(messages.any? { |msg| msg[:role] == "system" }).to be true
        expect(messages.any? { |msg| msg[:role] == "user" }).to be true
      end

      it "handles empty conversation" do
        messages = runner.send(:build_messages, [], agent, mock_context)
        
        expect(messages).to be_an(Array)
        # Should at least have system message
        expect(messages.any? { |msg| msg[:role] == "system" }).to be true
      end

      it "preserves message order" do
        messages = runner.send(:build_messages, conversation_messages, agent, mock_context)
        
        user_messages = messages.select { |msg| msg[:role] == "user" }
        expect(user_messages.first[:content]).to include("Hello")
        expect(user_messages.last[:content]).to include("How are you?")
      end
    end
  end

  describe "Context and Memory Integration" do
    let(:mock_context_manager) { instance_double(RAAF::ContextManager) }
    let(:mock_context_wrapper) { instance_double(RAAF::RunContextWrapper) }
    
    before do
      allow(RAAF::ContextManager).to receive(:new).and_return(mock_context_manager)
      allow(RAAF::RunContextWrapper).to receive(:new).and_return(mock_context_wrapper)
      allow(mock_context_wrapper).to receive(:fetch).and_return(nil)
      allow(mock_context_wrapper).to receive(:current_agent).and_return(agent)
    end

    context "context initialization and management" do
      it "initializes run context properly" do
        messages = [{ role: "user", content: "Test" }]
        config = RAAF::RunConfig.new
        
        # Since RunContextWrapper.new is mocked to return mock_context_wrapper
        context = runner.send(:initialize_run_context, messages, config)
        
        expect(context).not_to be_nil
        expect(context).to eq(mock_context_wrapper)
        
        # Verify it was called with a RunContext instance
        expect(RAAF::RunContextWrapper).to have_received(:new).with(
          instance_of(RAAF::RunContext)
        )
      end

      it "handles context updates during execution" do
        messages = [{ role: "user", content: "Test" }]
        config = RAAF::RunConfig.new
        
        # Test that context initialization works with mocked wrapper
        context = runner.send(:initialize_run_context, messages, config)
        expect(context).to eq(mock_context_wrapper)
        
        # Verify RunContext and RunContextWrapper were created
        expect(RAAF::RunContextWrapper).to have_received(:new).with(
          instance_of(RAAF::RunContext)
        )
      end
    end
  end

  describe "Error Handling and Edge Cases" do
    context "comprehensive error scenarios" do
      it "handles JSON parsing errors in responses" do
        malformed_response = {
          id: "resp_malformed",
          output: [
            {
              type: "function_call",
              name: "test_tool", 
              arguments: "invalid json {",
              call_id: "call_bad"
            }
          ],
          usage: { input_tokens: 10, output_tokens: 10, total_tokens: 20 }
        }
        
        final_response = {
          id: "resp_final",
          output: [
            {
              type: "message",
              role: "assistant",
              content: [{ type: "output_text", text: "I encountered a JSON parsing error." }]
            }
          ],
          usage: { input_tokens: 15, output_tokens: 10, total_tokens: 25 }
        }
        
        # Add tool to handle the call
        agent.add_tool(proc { |param:| "result" }, name: "test_tool")
        
        call_count = 0
        allow(mock_provider).to receive(:responses_completion) do
          call_count += 1
          call_count == 1 ? malformed_response : final_response
        end
        
        result = runner.run("Test malformed JSON")
        
        # Should handle malformed JSON gracefully
        expect(result.success?).to be true
        expect(result.tool_results.any? { |tr| tr.to_s.include?("Error") || tr.to_s.include?("invalid") }).to be true
      end

      it "handles stop condition checking" do
        stop_checker = proc { true } # Always stop
        runner = described_class.new(agent: agent, provider: mock_provider, stop_checker: stop_checker)
        
        expect_provider_call(basic_response)
        
        # Should raise ExecutionStoppedError when stop condition is met
        expect {
          runner.run("Test stop condition")
        }.to raise_error(RAAF::ExecutionStoppedError, "Execution stopped by user request")
      end

      it "handles very large inputs efficiently" do
        large_input = "x" * 10000 # 10k characters
        
        expect_provider_call(basic_response)
        
        start_time = Time.now
        result = runner.run(large_input)
        duration = Time.now - start_time
        
        expect(result.success?).to be true
        expect(duration).to be < 5.0 # Should handle large inputs reasonably quickly
      end

      it "handles empty and nil inputs" do
        expect_provider_call(basic_response)
        
        # Test empty string
        result = runner.run("")
        expect(result.success?).to be true
        
        # Test nil input (should be handled appropriately)
        expect {
          runner.run(nil)
        }.not_to raise_error
      end
    end

    context "provider communication errors" do
      it "handles network timeouts" do
        allow(mock_provider).to receive(:responses_completion)
          .and_raise(Timeout::Error.new("Request timeout"))
        
        expect {
          runner.run("Test timeout")
        }.to raise_error(Timeout::Error)
      end

      it "handles rate limiting errors" do
        rate_limit_error = RAAF::Models::APIError.new("Rate limit exceeded")
        allow(mock_provider).to receive(:responses_completion).and_raise(rate_limit_error)
        
        expect {
          runner.run("Test rate limit")
        }.to raise_error(RAAF::Models::APIError)
      end

      it "handles malformed API responses" do
        malformed_response = { broken: "response", missing: "required_fields" }
        expect_provider_call(malformed_response)
        
        expect {
          runner.run("Test malformed response")
        }.to raise_error(StandardError) # Should raise due to response validation
      end
    end
  end

  describe "Performance and Optimization" do
    context "execution efficiency" do
      it "completes simple conversations quickly" do
        expect_provider_call(basic_response)
        
        start_time = Time.now
        result = runner.run("Quick test")
        duration = Time.now - start_time
        
        expect(result.success?).to be true
        expect(duration).to be < 1.0 # Should complete within 1 second
      end

      it "handles multiple tool calls efficiently" do
        # Add multiple tools
        5.times do |i|
          agent.add_tool(proc { |param:| "Tool #{i} result: #{param}" }, 
                        name: "tool_#{i}", 
                        description: "Test tool #{i}")
        end
        
        # First response requests multiple tool calls
        multi_tool_response = {
          id: "resp_multi",
          output: (0..4).map do |i|
            {
              type: "function_call",
              name: "tool_#{i}",
              arguments: '{"param": "test"}',
              call_id: "call_#{i}"
            }
          end,
          usage: { input_tokens: 50, output_tokens: 30, total_tokens: 80 }
        }
        
        # Second response acknowledges tool results
        final_response = {
          id: "resp_final",
          output: [
            {
              type: "message",
              role: "assistant", 
              content: [{ type: "output_text", text: "All tools executed successfully" }]
            }
          ],
          usage: { input_tokens: 100, output_tokens: 20, total_tokens: 120 }
        }
        
        call_count = 0
        allow(mock_provider).to receive(:responses_completion) do
          call_count += 1
          call_count == 1 ? multi_tool_response : final_response
        end
        
        start_time = Time.now
        result = runner.run("Execute multiple tools")
        duration = Time.now - start_time
        
        expect(result.success?).to be true
        # Tool results should be tracked in the tool_results array
        expect(result.tool_results.length).to be >= 5
        expect(duration).to be < 3.0 # Should handle multiple tools reasonably quickly
      end
    end
  end
end
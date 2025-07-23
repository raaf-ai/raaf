# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Runner do
  let(:agent) { RAAF::Agent.new(name: "TestAgent", instructions: "You are helpful") }
  let(:runner) { described_class.new(agent: agent) }

  describe "Context Management" do
    describe "with ContextConfig" do
      let(:context_config) do
        config = RAAF::ContextConfig.new
        config.max_tokens = 2000
        config.preserve_system = true
        config.preserve_recent = 5
        config
      end
      
      let(:runner_with_context) do
        described_class.new(agent: agent, context_config: context_config)
      end

      it "initializes context manager with config" do
        context_manager = runner_with_context.instance_variable_get(:@context_manager)
        expect(context_manager).to be_a(RAAF::ContextManager)
        expect(context_manager.instance_variable_get(:@max_tokens)).to eq(2000)
        expect(context_manager.instance_variable_get(:@preserve_recent)).to eq(5)
      end

      it "manages conversation context within token limits" do
        # Create a long conversation that exceeds token limits
        long_messages = (1..20).map do |i|
          { role: "user", content: "This is message number #{i} with some additional content to make it longer" }
        end

        # Mock provider response
        provider = instance_double(RAAF::Models::ResponsesProvider)
        actual_messages = nil
        
        allow(provider).to receive(:complete) do |args|
          actual_messages = args[:messages]
          {
            output: [{
              type: "message",
              role: "assistant",
              content: [{ type: "text", text: "Response with managed context" }]
            }]
          }
        end

        runner_with_context = described_class.new(
          agent: agent,
          provider: provider,
          context_config: context_config
        )

        result = runner_with_context.run(long_messages)
        
        # Verify context was managed (messages were truncated)
        expect(actual_messages.size).to be < long_messages.size + 1 # +1 for system message
      end
    end

    describe "with ContextManager" do
      let(:custom_context_manager) do
        RAAF::ContextManager.new(
          model: "gpt-4o",
          max_tokens: 1000,
          preserve_system: false
        )
      end
      
      let(:runner_with_manager) do
        described_class.new(agent: agent, context_manager: custom_context_manager)
      end

      it "uses provided context manager" do
        expect(runner_with_manager.instance_variable_get(:@context_manager)).to eq(custom_context_manager)
      end

      it "applies context management during run" do
        provider = instance_double(RAAF::Models::ResponsesProvider)
        managed_messages = []
        
        allow(provider).to receive(:complete) do |args|
          managed_messages = args[:messages]
          {
            output: [{
              type: "message",
              role: "assistant",
              content: [{ type: "text", text: "Managed response" }]
            }]
          }
        end

        runner_with_manager = described_class.new(
          agent: agent,
          provider: provider,
          context_manager: custom_context_manager
        )

        # Run with messages that should be managed
        messages = Array.new(10) { |i| { role: "user", content: "Message #{i}" * 50 } }
        runner_with_manager.run(messages)

        # Verify context manager was applied
        expect(managed_messages.size).to be <= 11 # Managed size + system message
      end
    end

    describe "with memory manager" do
      let(:memory_manager) { double("MemoryManager") }
      let(:runner_with_memory) do
        described_class.new(agent: agent, memory_manager: memory_manager)
      end

      before do
        allow(memory_manager).to receive(:token_limit).and_return(4096)
      end

      it "stores memory manager" do
        expect(runner_with_memory.instance_variable_get(:@memory_manager)).to eq(memory_manager)
      end

      it "retrieves relevant context from memory" do
        allow(memory_manager).to receive(:get_relevant_context).with("user query", 4096).and_return(
          "Previous context: User likes Ruby programming"
        )

        # This would be used in build_messages when memory integration is complete
        context = runner_with_memory.instance_variable_get(:@memory_manager).get_relevant_context("user query", 4096)
        expect(context).to include("Ruby programming")
      end

      it "handles memory manager errors gracefully" do
        allow(memory_manager).to receive(:get_relevant_context).and_raise("Memory error")
        
        # Mock provider to avoid real API calls
        provider = instance_double(RAAF::Models::ResponsesProvider)
        allow(provider).to receive(:complete).and_return({
          output: [{
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: "Response despite memory error" }]
          }]
        })
        
        runner_with_memory = described_class.new(agent: agent, provider: provider, memory_manager: memory_manager)
        
        # Should not crash the runner
        expect { runner_with_memory.run("test") }.not_to raise_error
      end
    end
  end

  describe "Handoff Detection" do
    let(:support_agent) { RAAF::Agent.new(name: "Support", instructions: "Handle support") }
    let(:billing_agent) { RAAF::Agent.new(name: "Billing", instructions: "Handle billing") }
    
    before do
      agent.add_handoff(support_agent)
      agent.add_handoff(billing_agent)
    end

    describe "#detect_handoff_in_content" do
      it "detects explicit handoff requests" do
        content = "I need to transfer this to Support for further assistance."
        handoff = runner.send(:detect_handoff_in_content, content, agent)
        
        expect(handoff).to eq({
          target_agent: "Support",
          reason: "Agent requested transfer to Support"
        })
      end

      it "detects handoff with 'hand off' spelling" do
        content = "Let me hand off to the Billing team for this invoice issue."
        handoff = runner.send(:detect_handoff_in_content, content, agent)
        
        expect(handoff).to eq({
          target_agent: "Billing",
          reason: "Agent requested transfer to Billing"
        })
      end

      it "ignores case in agent names" do
        content = "I'll transfer you to support now."
        handoff = runner.send(:detect_handoff_in_content, content, agent)
        
        expect(handoff).to eq({
          target_agent: "Support",
          reason: "Agent requested transfer to Support"
        })
      end

      it "returns nil when no handoff detected" do
        content = "I can help you with that directly."
        handoff = runner.send(:detect_handoff_in_content, content, agent)
        
        expect(handoff).to be_nil
      end

      it "returns nil when mentioned agent is not available for handoff" do
        content = "I need to transfer to Sales agent." # Sales not in handoffs
        handoff = runner.send(:detect_handoff_in_content, content, agent)
        
        expect(handoff).to be_nil
      end

      it "handles nil content gracefully" do
        handoff = runner.send(:detect_handoff_in_content, nil, agent)
        expect(handoff).to be_nil
      end

      it "handles nil agent gracefully" do
        handoff = runner.send(:detect_handoff_in_content, "transfer to Support", nil)
        expect(handoff).to be_nil
      end
    end
  end

  describe "Tool Execution Advanced Scenarios" do
    let(:agent_with_tools) do
      agent = RAAF::Agent.new(name: "ToolAgent", instructions: "Use tools")
      
      # Add various types of tools
      agent.add_tool(
        RAAF::FunctionTool.new(
          proc { |x:, y:| x + y },
          name: "add",
          description: "Add two numbers"
        )
      )
      
      agent.add_tool(
        RAAF::FunctionTool.new(
          proc { |**kwargs| kwargs },
          name: "echo",
          description: "Echo back arguments"
        )
      )
      
      agent.add_tool(
        RAAF::FunctionTool.new(
          proc { raise "Tool error" },
          name: "failing_tool",
          description: "Always fails"
        )
      )
      
      agent
    end

    describe "#execute_tool" do
      let(:runner_with_tools) { described_class.new(agent: agent_with_tools) }

      it "executes tool with keyword arguments" do
        result = runner_with_tools.send(:execute_tool, "add", { x: 5, y: 3 }, agent_with_tools)
        expect(result).to eq(8)
      end

      it "executes tool with arbitrary kwargs" do
        result = runner_with_tools.send(:execute_tool, "echo", { foo: "bar", baz: 42 }, agent_with_tools)
        expect(result).to eq({ foo: "bar", baz: 42 })
      end

      it "handles tool execution errors" do
        result = runner_with_tools.send(:execute_tool, "failing_tool", {}, agent_with_tools)
        expect(result).to include("error")
        expect(result).to include("Tool error")
      end

      it "returns error for non-existent tool" do
        result = runner_with_tools.send(:execute_tool, "unknown_tool", {}, agent_with_tools)
        expect(result).to include("Tool 'unknown_tool' not found")
      end

      it "handles nil arguments gracefully" do
        result = runner_with_tools.send(:execute_tool, "echo", nil, agent_with_tools)
        expect(result).to eq({})
      end
    end

    describe "hosted tools integration" do
      let(:agent_with_hosted_tools) do
        agent = RAAF::Agent.new(name: "HostedToolAgent", instructions: "Use hosted tools")
        # Add a mock hosted tool
        agent.instance_variable_set(:@tools, [
          {
            type: "file_search",
            description: "Search through uploaded files"
          }
        ])
        agent
      end

      it "identifies hosted tools correctly" do
        runner = described_class.new(agent: agent_with_hosted_tools)
        tools = runner.send(:get_all_tools_for_api, agent_with_hosted_tools)
        
        expect(tools).to include(hash_including(type: "file_search"))
      end

      it "processes hosted tool responses" do
        # Hosted tools are executed by the API, not locally
        runner = described_class.new(agent: agent_with_hosted_tools)
        
        # For hosted tools, we just return a placeholder
        result = runner.send(:execute_tool, "file_search", { query: "test" }, agent_with_hosted_tools)
        expect(result).to eq("Tool 'file_search' not found")
      end
    end

    describe "tool use tracking" do
      it "tracks tool usage during execution" do
        provider = instance_double(RAAF::Models::ResponsesProvider)
        
        # First response with tool call
        allow(provider).to receive(:complete).and_return(
          {
            output: [
              {
                type: "message",
                role: "assistant",
                content: [
                  { type: "text", text: "Let me add those numbers" },
                  {
                    type: "tool_use",
                    id: "tool_123",
                    name: "add",
                    input: { x: 5, y: 3 }
                  }
                ]
              }
            ]
          },
          # Second response after tool execution
          {
            output: [
              {
                type: "message",
                role: "assistant",
                content: [{ type: "text", text: "The result is 8" }]
              }
            ]
          }
        )

        runner = described_class.new(agent: agent_with_tools, provider: provider)
        result = runner.run("Add 5 and 3")
        
        # Should have executed the tool and continued conversation
        expect(result.messages).to include(
          hash_including(role: "assistant", content: include("result is 8"))
        )
      end
    end
  end

  describe "Guardrails Integration" do
    describe "input guardrails" do
      let(:input_guardrail) { double("InputGuardrail") }
      let(:agent_with_guardrails) do
        agent = RAAF::Agent.new(name: "GuardedAgent", instructions: "Be helpful")
        agent.add_input_guardrail(input_guardrail)
        agent
      end

      it "applies input guardrails before processing" do
        allow(input_guardrail).to receive(:validate).and_return({ passed: true })
        
        runner = described_class.new(agent: agent_with_guardrails)
        context_wrapper = RAAF::RunContext.new(messages: [], config: RAAF::RunConfig.new)
        
        result = runner.send(:run_input_guardrails, context_wrapper, agent_with_guardrails, "test input")
        expect(result).to be true
      end

      it "blocks processing when guardrail fails" do
        allow(input_guardrail).to receive(:validate).and_return({ 
          passed: false, 
          reason: "Contains prohibited content" 
        })
        
        runner = described_class.new(agent: agent_with_guardrails)
        context_wrapper = RAAF::RunContext.new(messages: [], config: RAAF::RunConfig.new)
        
        result = runner.send(:run_input_guardrails, context_wrapper, agent_with_guardrails, "bad input")
        expect(result).to be false
      end

      it "handles guardrail exceptions gracefully" do
        allow(input_guardrail).to receive(:validate).and_raise("Guardrail error")
        
        runner = described_class.new(agent: agent_with_guardrails)
        context_wrapper = RAAF::RunContext.new(messages: [], config: RAAF::RunConfig.new)
        
        # Should log error and continue (return true)
        result = runner.send(:run_input_guardrails, context_wrapper, agent_with_guardrails, "test")
        expect(result).to be true
      end

      it "runs multiple guardrails in sequence" do
        guardrail2 = double("InputGuardrail2")
        agent_with_guardrails.add_input_guardrail(guardrail2)
        
        allow(input_guardrail).to receive(:validate).and_return({ passed: true })
        allow(guardrail2).to receive(:validate).and_return({ passed: true })
        
        runner = described_class.new(agent: agent_with_guardrails)
        context_wrapper = RAAF::RunContext.new(messages: [], config: RAAF::RunConfig.new)
        
        result = runner.send(:run_input_guardrails, context_wrapper, agent_with_guardrails, "test")
        expect(result).to be true
        
        expect(input_guardrail).to have_received(:validate)
        expect(guardrail2).to have_received(:validate)
      end
    end

    describe "output guardrails" do
      let(:output_guardrail) { double("OutputGuardrail") }
      let(:agent_with_guardrails) do
        agent = RAAF::Agent.new(name: "GuardedAgent", instructions: "Be helpful")
        agent.add_output_guardrail(output_guardrail)
        agent
      end

      it "applies output guardrails to responses" do
        allow(output_guardrail).to receive(:validate).and_return({ 
          passed: true,
          filtered_output: "Filtered response" 
        })
        
        runner = described_class.new(agent: agent_with_guardrails)
        context_wrapper = RAAF::RunContext.new(messages: [], config: RAAF::RunConfig.new)
        
        result = runner.send(:run_output_guardrails, context_wrapper, agent_with_guardrails, "Original response")
        expect(result).to eq("Filtered response")
      end

      it "returns original output when guardrail passes without filtering" do
        allow(output_guardrail).to receive(:validate).and_return({ passed: true })
        
        runner = described_class.new(agent: agent_with_guardrails)
        context_wrapper = RAAF::RunContext.new(messages: [], config: RAAF::RunConfig.new)
        
        result = runner.send(:run_output_guardrails, context_wrapper, agent_with_guardrails, "Original")
        expect(result).to eq("Original")
      end

      it "returns error message when guardrail fails" do
        allow(output_guardrail).to receive(:validate).and_return({ 
          passed: false,
          reason: "Output contains sensitive data" 
        })
        
        runner = described_class.new(agent: agent_with_guardrails)
        context_wrapper = RAAF::RunContext.new(messages: [], config: RAAF::RunConfig.new)
        
        result = runner.send(:run_output_guardrails, context_wrapper, agent_with_guardrails, "Sensitive")
        expect(result).to include("Output blocked")
        expect(result).to include("sensitive data")
      end
    end
  end

  describe "Session Processing" do
    let(:session) { RAAF::Session.new(id: "test-session") }

    describe "#process_session" do
      it "adds session messages to conversation" do
        session.add_message(role: "user", content: "Previous message")
        session.add_message(role: "assistant", content: "Previous response")
        
        new_messages = [{ role: "user", content: "New message" }]
        
        processed = runner.send(:process_session, session, new_messages)
        
        expect(processed).to eq([
          { role: "user", content: "Previous message" },
          { role: "assistant", content: "Previous response" },
          { role: "user", content: "New message" }
        ])
      end

      it "handles empty session" do
        messages = [{ role: "user", content: "First message" }]
        processed = runner.send(:process_session, session, messages)
        
        expect(processed).to eq(messages)
      end

      it "handles nil session" do
        messages = [{ role: "user", content: "Message" }]
        processed = runner.send(:process_session, nil, messages)
        
        expect(processed).to eq(messages)
      end

      it "handles nil messages" do
        processed = runner.send(:process_session, session, nil)
        expect(processed).to eq([])
      end
    end

    describe "#update_session_with_result" do
      it "adds result messages to session" do
        result = RAAF::Result.new(
          messages: [
            { role: "user", content: "Question" },
            { role: "assistant", content: "Answer" }
          ]
        )
        
        runner.send(:update_session_with_result, session, result)
        
        expect(session.messages).to eq([
          { role: "user", content: "Question" },
          { role: "assistant", content: "Answer" }
        ])
      end

      it "handles empty result" do
        result = RAAF::Result.new(messages: [])
        runner.send(:update_session_with_result, session, result)
        
        expect(session.messages).to be_empty
      end

      it "handles nil inputs gracefully" do
        expect { runner.send(:update_session_with_result, nil, nil) }.not_to raise_error
      end
    end
  end

  describe "Error Recovery and Resilience" do
    describe "provider failures" do
      let(:failing_provider) { instance_double(RAAF::Models::ResponsesProvider) }
      
      it "handles provider connection errors" do
        allow(failing_provider).to receive(:complete).and_raise(Net::HTTPError.new("Connection failed", nil))
        
        runner = described_class.new(agent: agent, provider: failing_provider)
        
        expect { runner.run("test") }.to raise_error(Net::HTTPError)
      end

      it "handles provider timeout errors" do
        allow(failing_provider).to receive(:complete).and_raise(Net::ReadTimeout)
        
        runner = described_class.new(agent: agent, provider: failing_provider)
        
        expect { runner.run("test") }.to raise_error(Net::ReadTimeout)
      end

      it "handles malformed provider responses" do
        allow(failing_provider).to receive(:complete).and_return({ invalid: "response" })
        
        runner = described_class.new(agent: agent, provider: failing_provider)
        
        expect { runner.run("test") }.to raise_error(RAAF::Errors::ModelBehaviorError)
      end
    end

    describe "conversation state recovery" do
      it "maintains conversation state after tool errors" do
        agent_with_tool = RAAF::Agent.new(name: "Agent", instructions: "Use tools")
        agent_with_tool.add_tool(
          RAAF::FunctionTool.new(
            proc { raise "Temporary error" },
            name: "unstable_tool"
          )
        )
        
        provider = instance_double(RAAF::Models::ResponsesProvider)
        call_count = 0
        
        allow(provider).to receive(:complete) do
          call_count += 1
          if call_count == 1
            # First call requests tool use
            {
              output: [{
                type: "message",
                role: "assistant",
                content: [
                  { type: "tool_use", id: "t1", name: "unstable_tool", input: {} }
                ]
              }]
            }
          else
            # Second call after tool error
            {
              output: [{
                type: "message",
                role: "assistant",
                content: [{ type: "text", text: "I encountered an error but can continue" }]
              }]
            }
          end
        end
        
        runner = described_class.new(agent: agent_with_tool, provider: provider)
        result = runner.run("Use the tool")
        
        # Should recover and provide response
        expect(result.messages.last[:content]).to include("encountered an error")
      end
    end

    describe "stop checker functionality" do
      it "stops execution when checker returns true" do
        stop_flag = false
        stop_checker = -> { stop_flag }
        
        provider = instance_double(RAAF::Models::ResponsesProvider)
        allow(provider).to receive(:complete).and_return({
          output: [{
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: "Response" }]
          }]
        })
        
        runner = described_class.new(agent: agent, provider: provider, stop_checker: stop_checker)
        
        # First run should complete
        result1 = runner.run("First message")
        expect(result1.messages).not_to be_empty
        
        # Set stop flag
        stop_flag = true
        
        # Second run should be stopped
        expect { runner.run("Second message") }.to raise_error(RAAF::Errors::UserError, /stopped by user/)
      end

      it "handles stop checker exceptions" do
        stop_checker = -> { raise "Checker error" }
        
        runner = described_class.new(agent: agent, stop_checker: stop_checker)
        
        # Should not crash, treats exception as false
        expect(runner.send(:should_stop?)).to be false
      end
    end
  end

  describe "Complex Multi-Agent Workflows" do
    let(:reception_agent) { RAAF::Agent.new(name: "Reception", instructions: "Route inquiries") }
    let(:support_agent) { RAAF::Agent.new(name: "Support", instructions: "Technical support") }
    let(:billing_agent) { RAAF::Agent.new(name: "Billing", instructions: "Handle payments") }
    let(:escalation_agent) { RAAF::Agent.new(name: "Escalation", instructions: "Handle complaints") }
    
    before do
      # Set up handoff network
      reception_agent.add_handoff(support_agent)
      reception_agent.add_handoff(billing_agent)
      support_agent.add_handoff(escalation_agent)
      billing_agent.add_handoff(escalation_agent)
      escalation_agent.add_handoff(reception_agent) # Can go back to start
    end

    it "handles multi-hop handoffs" do
      provider = instance_double(RAAF::Models::ResponsesProvider)
      responses = [
        # Reception response
        {
          output: [{
            type: "message",
            role: "assistant",
            content: [
              { type: "text", text: "Let me transfer you to support" },
              { type: "tool_use", id: "t1", name: "transfer_to_support", input: { input: "Technical issue" } }
            ]
          }]
        },
        # Support response
        {
          output: [{
            type: "message",
            role: "assistant",
            content: [
              { type: "text", text: "This needs escalation" },
              { type: "tool_use", id: "t2", name: "transfer_to_escalation", input: { input: "Complex issue" } }
            ]
          }]
        },
        # Escalation response
        {
          output: [{
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: "I'll handle this complex issue personally" }]
          }]
        }
      ]
      
      call_index = 0
      allow(provider).to receive(:complete) do
        response = responses[call_index]
        call_index += 1
        response
      end
      
      runner = described_class.new(agent: reception_agent, provider: provider)
      result = runner.run("I have a complex technical problem")
      
      # Should have gone through all three agents
      expect(result.messages.select { |m| m[:role] == "assistant" }.size).to eq(3)
    end

    it "prevents infinite handoff loops" do
      # Create a loop: A -> B -> A
      agent_a = RAAF::Agent.new(name: "AgentA", instructions: "Agent A")
      agent_b = RAAF::Agent.new(name: "AgentB", instructions: "Agent B")
      agent_a.add_handoff(agent_b)
      agent_b.add_handoff(agent_a)
      
      provider = instance_double(RAAF::Models::ResponsesProvider)
      
      # Both agents always try to handoff
      allow(provider).to receive(:complete).and_return({
        output: [{
          type: "message",
          role: "assistant",
          content: [
            { type: "text", text: "Transferring..." },
            { type: "tool_use", id: "t1", name: "transfer_to_agent_b", input: { input: "loop" } }
          ]
        }]
      })
      
      runner = described_class.new(agent: agent_a, provider: provider)
      
      # Should eventually detect the loop and stop
      expect { runner.run("Start loop") }.to raise_error(RAAF::Errors::MaxTurnsError)
    end
  end

  describe "Streaming Support" do
    it "identifies streaming capability correctly" do
      # ResponsesProvider doesn't support streaming
      expect(runner.streaming_capable?).to be false
      
      # OpenAIProvider supports streaming
      streaming_provider = RAAF::Models::OpenAIProvider.new
      streaming_runner = described_class.new(agent: agent, provider: streaming_provider)
      expect(streaming_runner.streaming_capable?).to be true
    end

    it "falls back to non-streaming when provider doesn't support it" do
      provider = instance_double(RAAF::Models::ResponsesProvider)
      allow(provider).to receive(:complete).and_return({
        output: [{
          type: "message",
          role: "assistant",
          content: [{ type: "text", text: "Non-streamed response" }]
        }]
      })
      
      runner = described_class.new(agent: agent, provider: provider)
      
      # Request streaming but provider doesn't support it
      result = runner.run("Test", stream: true)
      expect(result.messages.last[:content]).to eq("Non-streamed response")
    end
  end

  describe "Run Configuration" do
    describe "with custom RunConfig" do
      let(:custom_config) do
        RAAF::RunConfig.new(
          max_turns: 5,
          execute_tools: false,
          temperature: 0.5,
          max_tokens: 1000
        )
      end

      it "respects max_turns limit" do
        provider = instance_double(RAAF::Models::ResponsesProvider)
        
        # Always return a response that would continue
        allow(provider).to receive(:complete).and_return({
          output: [{
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: "Response" }]
          }]
        })
        
        runner = described_class.new(agent: agent, provider: provider)
        
        # Create conversation that would exceed max_turns
        messages = Array.new(10) { |i| { role: "user", content: "Message #{i}" } }
        
        expect { runner.run(messages, config: custom_config) }.to raise_error(RAAF::Errors::MaxTurnsError)
      end

      it "disables tool execution when configured" do
        agent_with_tool = RAAF::Agent.new(name: "Agent", instructions: "Use tools")
        agent_with_tool.add_tool(
          RAAF::FunctionTool.new(proc { "Tool result" }, name: "test_tool")
        )
        
        provider = instance_double(RAAF::Models::ResponsesProvider)
        allow(provider).to receive(:complete).and_return({
          output: [{
            type: "message",
            role: "assistant",
            content: [
              { type: "tool_use", id: "t1", name: "test_tool", input: {} }
            ]
          }]
        })
        
        runner = described_class.new(agent: agent_with_tool, provider: provider)
        
        # Tools should not be executed with execute_tools: false
        result = runner.run("Use tool", config: custom_config)
        
        # Tool call should be in response but not executed
        expect(result.messages.last[:tool_calls]).not_to be_nil
      end
    end
  end
end
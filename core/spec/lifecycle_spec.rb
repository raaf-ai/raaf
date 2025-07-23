# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RAAF::Lifecycle" do
  let(:context) { double("context", run_id: "test-run-123", metadata: {}) }
  let(:agent) { RAAF::Agent.new(name: "TestAgent", instructions: "Test agent") }
  let(:other_agent) { RAAF::Agent.new(name: "OtherAgent", instructions: "Other agent") }
  let(:tool) { double("tool", name: "test_tool") }
  let(:error) { StandardError.new("Test error") }

  describe RAAF::RunHooks do
    let(:hooks) { described_class.new }

    describe "#on_agent_start" do
      it "has empty default implementation" do
        expect { hooks.on_agent_start(context, agent) }.not_to raise_error
      end

      it "can be overridden in subclass" do
        custom_hooks = Class.new(described_class) do
          def on_agent_start(context, agent)
            context.metadata[:started] = agent.name
          end
        end.new

        custom_hooks.on_agent_start(context, agent)
        expect(context.metadata[:started]).to eq("TestAgent")
      end
    end

    describe "#on_agent_end" do
      it "has empty default implementation" do
        output = { message: "Hello" }
        expect { hooks.on_agent_end(context, agent, output) }.not_to raise_error
      end

      it "can be overridden to track outputs" do
        custom_hooks = Class.new(described_class) do
          def on_agent_end(context, agent, output)
            context.metadata[:outputs] ||= []
            context.metadata[:outputs] << { agent: agent.name, output: output }
          end
        end.new

        output1 = { message: "First" }
        output2 = { message: "Second" }

        custom_hooks.on_agent_end(context, agent, output1)
        custom_hooks.on_agent_end(context, other_agent, output2)

        expect(context.metadata[:outputs]).to eq([
          { agent: "TestAgent", output: output1 },
          { agent: "OtherAgent", output: output2 }
        ])
      end
    end

    describe "#on_handoff" do
      it "has empty default implementation" do
        expect { hooks.on_handoff(context, agent, other_agent) }.not_to raise_error
      end

      it "can be overridden to track handoffs" do
        custom_hooks = Class.new(described_class) do
          def on_handoff(context, from_agent, to_agent)
            context.metadata[:handoff_chain] ||= []
            context.metadata[:handoff_chain] << "#{from_agent.name} -> #{to_agent.name}"
          end
        end.new

        custom_hooks.on_handoff(context, agent, other_agent)
        custom_hooks.on_handoff(context, other_agent, agent)

        expect(context.metadata[:handoff_chain]).to eq([
          "TestAgent -> OtherAgent",
          "OtherAgent -> TestAgent"
        ])
      end
    end

    describe "#on_tool_start" do
      it "has empty default implementation" do
        arguments = { param: "value" }
        expect { hooks.on_tool_start(context, agent, tool, arguments) }.not_to raise_error
      end

      it "handles optional arguments parameter" do
        expect { hooks.on_tool_start(context, agent, tool) }.not_to raise_error
      end

      it "can be overridden to validate tool usage" do
        custom_hooks = Class.new(described_class) do
          ALLOWED_TOOLS = %w[allowed_tool].freeze

          def on_tool_start(context, agent, tool, arguments = {})
            unless ALLOWED_TOOLS.include?(tool.name)
              raise "Unauthorized tool: #{tool.name}"
            end
            context.metadata[:tool_calls] ||= []
            context.metadata[:tool_calls] << tool.name
          end
        end.new

        allowed_tool = double("tool", name: "allowed_tool")
        forbidden_tool = double("tool", name: "forbidden_tool")

        # Should work with allowed tool
        custom_hooks.on_tool_start(context, agent, allowed_tool, { param: "value" })
        expect(context.metadata[:tool_calls]).to include("allowed_tool")

        # Should raise error with forbidden tool
        expect {
          custom_hooks.on_tool_start(context, agent, forbidden_tool)
        }.to raise_error("Unauthorized tool: forbidden_tool")
      end
    end

    describe "#on_tool_end" do
      it "has empty default implementation" do
        result = { success: true, data: "result" }
        expect { hooks.on_tool_end(context, agent, tool, result) }.not_to raise_error
      end

      it "can be overridden to log tool results" do
        custom_hooks = Class.new(described_class) do
          def on_tool_end(context, agent, tool, result)
            context.metadata[:tool_results] ||= []
            context.metadata[:tool_results] << {
              tool: tool.name,
              success: !result.is_a?(Exception),
              result_size: result.to_s.length
            }
          end
        end.new

        success_result = "Success data"
        error_result = StandardError.new("Tool failed")

        custom_hooks.on_tool_end(context, agent, tool, success_result)
        custom_hooks.on_tool_end(context, agent, tool, error_result)

        expect(context.metadata[:tool_results]).to eq([
          { tool: "test_tool", success: true, result_size: success_result.length },
          { tool: "test_tool", success: false, result_size: error_result.to_s.length }
        ])
      end
    end

    describe "#on_error" do
      it "has empty default implementation" do
        expect { hooks.on_error(context, agent, error) }.not_to raise_error
      end

      it "can be overridden to implement error recovery" do
        custom_hooks = Class.new(described_class) do
          def on_error(context, agent, error)
            context.metadata[:error_count] ||= 0
            context.metadata[:error_count] += 1
            context.metadata[:errors] ||= []
            context.metadata[:errors] << { agent: agent.name, message: error.message }

            # Implement retry logic
            context.metadata[:should_retry] = context.metadata[:error_count] < 3
          end
        end.new

        # First error
        custom_hooks.on_error(context, agent, StandardError.new("Error 1"))
        expect(context.metadata[:error_count]).to eq(1)
        expect(context.metadata[:should_retry]).to be true

        # Second error
        custom_hooks.on_error(context, agent, StandardError.new("Error 2"))
        expect(context.metadata[:error_count]).to eq(2)
        expect(context.metadata[:should_retry]).to be true

        # Third error
        custom_hooks.on_error(context, agent, StandardError.new("Error 3"))
        expect(context.metadata[:error_count]).to eq(3)
        expect(context.metadata[:should_retry]).to be false

        expect(context.metadata[:errors]).to have(3).items
      end
    end
  end

  describe RAAF::AgentHooks do
    let(:hooks) { described_class.new }

    describe "#on_start" do
      it "has empty default implementation" do
        expect { hooks.on_start(context, agent) }.not_to raise_error
      end

      it "can be overridden for agent-specific behavior" do
        custom_hooks = Class.new(described_class) do
          def on_start(context, agent)
            context.metadata[:session_start] = Time.now
            context.metadata[:agent_sessions] ||= []
            context.metadata[:agent_sessions] << agent.name
          end
        end.new

        time_before = Time.now
        custom_hooks.on_start(context, agent)
        time_after = Time.now

        expect(context.metadata[:session_start]).to be_between(time_before, time_after)
        expect(context.metadata[:agent_sessions]).to eq(["TestAgent"])
      end
    end

    describe "#on_end" do
      it "has empty default implementation" do
        output = { message: "Done" }
        expect { hooks.on_end(context, agent, output) }.not_to raise_error
      end

      it "can be overridden to calculate session duration" do
        custom_hooks = Class.new(described_class) do
          def on_start(context, agent)
            context.metadata[:session_start] = Time.now
          end

          def on_end(context, agent, output)
            start_time = context.metadata[:session_start]
            if start_time
              duration = Time.now - start_time
              context.metadata[:session_duration] = duration
            end
            context.metadata[:final_output] = output
          end
        end.new

        # Start session
        custom_hooks.on_start(context, agent)
        sleep(0.01) # Small delay to ensure measurable duration
        
        # End session
        output = { result: "completed" }
        custom_hooks.on_end(context, agent, output)

        expect(context.metadata[:session_duration]).to be > 0
        expect(context.metadata[:final_output]).to eq(output)
      end
    end

    describe "#on_handoff" do
      it "has empty default implementation" do
        expect { hooks.on_handoff(context, agent, other_agent) }.not_to raise_error
      end

      it "can be overridden to track handoff sources" do
        custom_hooks = Class.new(described_class) do
          def on_handoff(context, agent, source)
            context.metadata[:received_from] = source.name
            context.metadata[:handoff_timestamp] = Time.now
          end
        end.new

        time_before = Time.now
        custom_hooks.on_handoff(context, agent, other_agent)
        time_after = Time.now

        expect(context.metadata[:received_from]).to eq("OtherAgent")
        expect(context.metadata[:handoff_timestamp]).to be_between(time_before, time_after)
      end
    end

    describe "#on_tool_start" do
      it "has empty default implementation" do
        arguments = { key: "value" }
        expect { hooks.on_tool_start(context, agent, tool, arguments) }.not_to raise_error
      end

      it "handles optional arguments parameter" do
        expect { hooks.on_tool_start(context, agent, tool) }.not_to raise_error
      end

      it "can implement agent-specific tool restrictions" do
        custom_hooks = Class.new(described_class) do
          def initialize(allowed_tools = [])
            super()
            @allowed_tools = allowed_tools
          end

          def on_tool_start(context, agent, tool, arguments = {})
            unless @allowed_tools.include?(tool.name)
              raise "Agent #{agent.name} cannot use tool #{tool.name}"
            end
          end
        end

        # Create hooks with specific allowed tools
        restricted_hooks = custom_hooks.new(["search", "email"])
        
        search_tool = double("tool", name: "search")
        email_tool = double("tool", name: "email")
        database_tool = double("tool", name: "database")

        # Should work with allowed tools
        expect { restricted_hooks.on_tool_start(context, agent, search_tool) }.not_to raise_error
        expect { restricted_hooks.on_tool_start(context, agent, email_tool) }.not_to raise_error

        # Should fail with disallowed tool
        expect {
          restricted_hooks.on_tool_start(context, agent, database_tool)
        }.to raise_error("Agent TestAgent cannot use tool database")
      end
    end

    describe "#on_tool_end" do
      it "has empty default implementation" do
        result = "tool result"
        expect { hooks.on_tool_end(context, agent, tool, result) }.not_to raise_error
      end
    end

    describe "#on_error" do
      it "has empty default implementation" do
        expect { hooks.on_error(context, agent, error) }.not_to raise_error
      end
    end
  end

  describe RAAF::CompositeRunHooks do
    let(:hook1) { double("hook1") }
    let(:hook2) { double("hook2") }
    let(:hook3) { double("hook3") }

    describe "#initialize" do
      it "initializes with empty hooks array by default" do
        composite = described_class.new
        expect(composite.instance_variable_get(:@hooks)).to eq([])
      end

      it "initializes with provided hooks array" do
        composite = described_class.new([hook1, hook2])
        expect(composite.instance_variable_get(:@hooks)).to eq([hook1, hook2])
      end
    end

    describe "#add_hook" do
      it "adds hooks to the collection" do
        composite = described_class.new([hook1])
        composite.add_hook(hook2)
        composite.add_hook(hook3)

        expect(composite.instance_variable_get(:@hooks)).to eq([hook1, hook2, hook3])
      end
    end

    describe "hook delegation" do
      let(:composite) { described_class.new([hook1, hook2]) }

      before do
        # Set up mocks to expect calls
        [hook1, hook2].each do |hook|
          allow(hook).to receive(:on_agent_start)
          allow(hook).to receive(:on_agent_end)
          allow(hook).to receive(:on_handoff)
          allow(hook).to receive(:on_tool_start)
          allow(hook).to receive(:on_tool_end)
          allow(hook).to receive(:on_error)
        end
      end

      describe "#on_agent_start" do
        it "calls on_agent_start on all hooks" do
          composite.on_agent_start(context, agent)

          expect(hook1).to have_received(:on_agent_start).with(context, agent)
          expect(hook2).to have_received(:on_agent_start).with(context, agent)
        end
      end

      describe "#on_agent_end" do
        it "calls on_agent_end on all hooks" do
          output = { message: "done" }
          composite.on_agent_end(context, agent, output)

          expect(hook1).to have_received(:on_agent_end).with(context, agent, output)
          expect(hook2).to have_received(:on_agent_end).with(context, agent, output)
        end
      end

      describe "#on_handoff" do
        it "calls on_handoff on all hooks" do
          composite.on_handoff(context, agent, other_agent)

          expect(hook1).to have_received(:on_handoff).with(context, agent, other_agent)
          expect(hook2).to have_received(:on_handoff).with(context, agent, other_agent)
        end
      end

      describe "#on_tool_start" do
        it "calls on_tool_start on all hooks with arguments" do
          arguments = { param: "value" }
          composite.on_tool_start(context, agent, tool, arguments)

          expect(hook1).to have_received(:on_tool_start).with(context, agent, tool, arguments)
          expect(hook2).to have_received(:on_tool_start).with(context, agent, tool, arguments)
        end

        it "calls on_tool_start on all hooks with default arguments" do
          composite.on_tool_start(context, agent, tool)

          expect(hook1).to have_received(:on_tool_start).with(context, agent, tool, {})
          expect(hook2).to have_received(:on_tool_start).with(context, agent, tool, {})
        end
      end

      describe "#on_tool_end" do
        it "calls on_tool_end on all hooks" do
          result = "tool result"
          composite.on_tool_end(context, agent, tool, result)

          expect(hook1).to have_received(:on_tool_end).with(context, agent, tool, result)
          expect(hook2).to have_received(:on_tool_end).with(context, agent, tool, result)
        end
      end

      describe "#on_error" do
        it "calls on_error on all hooks" do
          composite.on_error(context, agent, error)

          expect(hook1).to have_received(:on_error).with(context, agent, error)
          expect(hook2).to have_received(:on_error).with(context, agent, error)
        end
      end
    end

    describe "error behavior" do
      it "propagates errors from failing hooks" do
        failing_hook = double("failing_hook")
        working_hook = double("working_hook")

        allow(failing_hook).to receive(:on_agent_start).and_raise("Hook failure")
        allow(working_hook).to receive(:on_agent_start)

        composite = described_class.new([failing_hook, working_hook])

        # Current implementation propagates errors (doesn't implement error resilience)
        expect { composite.on_agent_start(context, agent) }.to raise_error("Hook failure")
        # working_hook should not be called due to early failure
        expect(working_hook).not_to have_received(:on_agent_start)
      end
    end
  end

  describe RAAF::AsyncHooks::RunHooks do
    let(:hooks) { described_class.new }

    describe "async method delegation" do
      it "delegates async methods to sync versions by default" do
        custom_hooks = Class.new(described_class) do
          def on_agent_start(context, agent)
            context.metadata[:sync_called] = true
          end

          def on_agent_end(context, agent, output)
            context.metadata[:sync_end_called] = true
          end

          def on_handoff(context, from_agent, to_agent)
            context.metadata[:sync_handoff_called] = true
          end

          def on_tool_start(context, agent, tool, arguments = {})
            context.metadata[:sync_tool_start_called] = true
          end

          def on_tool_end(context, agent, tool, result)
            context.metadata[:sync_tool_end_called] = true
          end

          def on_error(context, agent, error)
            context.metadata[:sync_error_called] = true
          end
        end.new

        # Call async methods
        custom_hooks.on_agent_start_async(context, agent)
        custom_hooks.on_agent_end_async(context, agent, { message: "done" })
        custom_hooks.on_handoff_async(context, agent, other_agent)
        custom_hooks.on_tool_start_async(context, agent, tool, {})
        custom_hooks.on_tool_end_async(context, agent, tool, "result")
        custom_hooks.on_error_async(context, agent, error)

        # Verify sync methods were called
        expect(context.metadata[:sync_called]).to be true
        expect(context.metadata[:sync_end_called]).to be true
        expect(context.metadata[:sync_handoff_called]).to be true
        expect(context.metadata[:sync_tool_start_called]).to be true
        expect(context.metadata[:sync_tool_end_called]).to be true
        expect(context.metadata[:sync_error_called]).to be true
      end

      it "can override async methods independently" do
        custom_hooks = Class.new(described_class) do
          def on_agent_start(context, agent)
            context.metadata[:sync_called] = true
          end

          def on_agent_start_async(context, agent)
            context.metadata[:async_called] = true
          end
        end.new

        # Call sync version
        custom_hooks.on_agent_start(context, agent)
        expect(context.metadata[:sync_called]).to be true
        expect(context.metadata[:async_called]).to be_nil

        # Reset and call async version
        context.metadata.clear
        custom_hooks.on_agent_start_async(context, agent)
        expect(context.metadata[:sync_called]).to be_nil
        expect(context.metadata[:async_called]).to be true
      end
    end
  end

  describe RAAF::AsyncHooks::AgentHooks do
    let(:hooks) { described_class.new }

    describe "async method delegation" do
      it "delegates async methods to sync versions by default" do
        custom_hooks = Class.new(described_class) do
          def on_start(context, agent)
            context.metadata[:sync_start] = true
          end

          def on_end(context, agent, output)
            context.metadata[:sync_end] = true
          end

          def on_handoff(context, agent, source)
            context.metadata[:sync_handoff] = true
          end

          def on_tool_start(context, agent, tool, arguments = {})
            context.metadata[:sync_tool_start] = true
          end

          def on_tool_end(context, agent, tool, result)
            context.metadata[:sync_tool_end] = true
          end

          def on_error(context, agent, error)
            context.metadata[:sync_error] = true
          end
        end.new

        # Call async methods
        custom_hooks.on_start_async(context, agent)
        custom_hooks.on_end_async(context, agent, { result: "done" })
        custom_hooks.on_handoff_async(context, agent, other_agent)
        custom_hooks.on_tool_start_async(context, agent, tool, {})
        custom_hooks.on_tool_end_async(context, agent, tool, "result")
        custom_hooks.on_error_async(context, agent, error)

        # Verify sync methods were called via async delegation
        expect(context.metadata[:sync_start]).to be true
        expect(context.metadata[:sync_end]).to be true
        expect(context.metadata[:sync_handoff]).to be true
        expect(context.metadata[:sync_tool_start]).to be true
        expect(context.metadata[:sync_tool_end]).to be true
        expect(context.metadata[:sync_error]).to be true
      end

      it "can override async methods for custom async behavior" do
        custom_hooks = Class.new(described_class) do
          def on_start(context, agent)
            context.metadata[:sync_start] = true
          end

          def on_start_async(context, agent)
            # Simulate async behavior
            context.metadata[:async_start] = true
            context.metadata[:async_timestamp] = Time.now
          end
        end.new

        # Call sync version
        custom_hooks.on_start(context, agent)
        expect(context.metadata[:sync_start]).to be true
        expect(context.metadata[:async_start]).to be_nil

        # Reset and call async version
        context.metadata.clear
        time_before = Time.now
        custom_hooks.on_start_async(context, agent)
        time_after = Time.now

        expect(context.metadata[:sync_start]).to be_nil
        expect(context.metadata[:async_start]).to be true
        expect(context.metadata[:async_timestamp]).to be_between(time_before, time_after)
      end
    end
  end

  describe "integration scenarios" do
    it "supports multiple hooks with different responsibilities" do
      # Create hooks for different concerns
      logging_hooks = Class.new(RAAF::RunHooks) do
        def on_agent_start(context, agent)
          context.metadata[:log] ||= []
          context.metadata[:log] << "Agent #{agent.name} started"
        end

        def on_tool_start(context, agent, tool, arguments = {})
          context.metadata[:log] ||= []
          context.metadata[:log] << "Tool #{tool.name} called by #{agent.name}"
        end
      end.new

      metrics_hooks = Class.new(RAAF::RunHooks) do
        def on_agent_start(context, agent)
          context.metadata[:metrics] ||= { agent_starts: 0, tool_calls: 0 }
          context.metadata[:metrics][:agent_starts] += 1
        end

        def on_tool_start(context, agent, tool, arguments = {})
          context.metadata[:metrics] ||= { agent_starts: 0, tool_calls: 0 }
          context.metadata[:metrics][:tool_calls] += 1
        end
      end.new

      # Combine hooks
      composite = RAAF::CompositeRunHooks.new([logging_hooks, metrics_hooks])

      # Execute some events
      composite.on_agent_start(context, agent)
      composite.on_tool_start(context, agent, tool, { param: "value" })

      # Verify both hooks were called
      expect(context.metadata[:log]).to eq([
        "Agent TestAgent started",
        "Tool test_tool called by TestAgent"
      ])

      expect(context.metadata[:metrics]).to eq({
        agent_starts: 1,
        tool_calls: 1
      })
    end

    it "supports agent-specific hooks working independently" do
      # Create different agent hooks
      customer_hooks = Class.new(RAAF::AgentHooks) do
        def on_start(context, agent)
          context.metadata[:customer_session] = Time.now
        end

        def on_tool_start(context, agent, tool, arguments = {})
          context.metadata[:customer_tools] ||= []
          context.metadata[:customer_tools] << tool.name
        end
      end.new

      admin_hooks = Class.new(RAAF::AgentHooks) do
        def on_start(context, agent)
          context.metadata[:admin_session] = { started: Time.now, privileged: true }
        end

        def on_tool_start(context, agent, tool, arguments = {})
          # Admin can use any tool without restrictions
          context.metadata[:admin_tool_usage] ||= 0
          context.metadata[:admin_tool_usage] += 1
        end
      end.new

      # Test customer agent hooks
      customer_context = double("context", metadata: {})
      customer_hooks.on_start(customer_context, agent)
      customer_hooks.on_tool_start(customer_context, agent, tool)

      expect(customer_context.metadata[:customer_session]).to be_a(Time)
      expect(customer_context.metadata[:customer_tools]).to eq(["test_tool"])
      expect(customer_context.metadata[:admin_session]).to be_nil

      # Test admin agent hooks
      admin_context = double("context", metadata: {})
      admin_hooks.on_start(admin_context, agent)
      admin_hooks.on_tool_start(admin_context, agent, tool)

      expect(admin_context.metadata[:admin_session][:privileged]).to be true
      expect(admin_context.metadata[:admin_tool_usage]).to eq(1)
      expect(admin_context.metadata[:customer_session]).to be_nil
    end
  end
end
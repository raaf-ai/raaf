# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::ResponseProcessor do
  let(:processor) { described_class.new }
  let(:agent) { double("agent", name: "TestAgent") }
  let(:function_tool) { double("function_tool", name: "get_weather", is_a?: true) }
  let(:computer_tool) { double("computer_tool", class: double(name: "ComputerTool")) }
  let(:local_shell_tool) { double("local_shell_tool", class: double(name: "LocalShellTool")) }
  let(:all_tools) { [function_tool] }
  let(:handoffs) { [] }

  describe "#process_model_response" do
    context "with Chat Completions format response" do
      it "processes message response correctly" do
        response = {
          choices: [{
            message: {
              role: "assistant",
              content: "Hello, how can I help?"
            }
          }]
        }

        result = processor.process_model_response(
          response: response,
          agent: agent,
          all_tools: all_tools,
          handoffs: handoffs
        )

        expect(result).to be_a(RAAF::ProcessedResponse)
        expect(result.new_items).to have(1).item
        expect(result.new_items.first).to be_a(RAAF::Items::MessageOutputItem)
        expect(result.handoffs).to be_empty
        expect(result.functions).to be_empty
        expect(result.tools_used).to be_empty
      end

      it "processes message with tool calls" do
        response = {
          choices: [{
            message: {
              role: "assistant",
              content: "I'll check the weather for you.",
              tool_calls: [{
                id: "call_123",
                type: "function",
                function: {
                  name: "get_weather",
                  arguments: '{"location": "San Francisco"}'
                }
              }]
            }
          }]
        }

        result = processor.process_model_response(
          response: response,
          agent: agent,
          all_tools: all_tools,
          handoffs: handoffs
        )

        expect(result.new_items).to have(2).items # message + tool call
        expect(result.new_items.first).to be_a(RAAF::Items::MessageOutputItem)
        expect(result.new_items.last).to be_a(RAAF::Items::ToolCallItem)
        expect(result.functions).to have(1).item
        expect(result.functions.first).to be_a(RAAF::ToolRunFunction)
        expect(result.tools_used).to eq(["get_weather"])
      end
    end

    context "with Responses API format response" do
      it "processes array output format" do
        response = {
          output: [
            {
              type: "message",
              role: "assistant",
              content: "Hello!"
            },
            {
              type: "function",
              name: "get_weather",
              arguments: '{"location": "NYC"}'
            }
          ]
        }

        result = processor.process_model_response(
          response: response,
          agent: agent,
          all_tools: all_tools,
          handoffs: handoffs
        )

        expect(result.new_items).to have(2).items
        expect(result.functions).to have(1).item
        expect(result.tools_used).to eq(["get_weather"])
      end

      it "processes string key output format" do
        response = {
          "output" => [
            {
              "type" => "message",
              "role" => "assistant", 
              "content" => "Hello!"
            }
          ]
        }

        result = processor.process_model_response(
          response: response,
          agent: agent,
          all_tools: all_tools,
          handoffs: handoffs
        )

        expect(result.new_items).to have(1).item
      end
    end

    context "with direct message format" do
      it "processes direct message" do
        response = {
          role: "assistant",
          content: "Direct message"
        }

        result = processor.process_model_response(
          response: response,
          agent: agent,
          all_tools: all_tools,
          handoffs: handoffs
        )

        expect(result.new_items).to have(1).item
        expect(result.new_items.first).to be_a(RAAF::Items::MessageOutputItem)
      end
    end

    context "with handoffs" do
      let(:target_agent) { RAAF::Agent.new(name: "TargetAgent", instructions: "Target agent") }
      let(:handoffs) { [target_agent] }

      it "processes handoff tool calls" do
        response = {
          choices: [{
            message: {
              role: "assistant",
              content: "Transferring to specialist.",
              tool_calls: [{
                id: "call_456",
                type: "function",
                function: {
                  name: "transfer_to_target_agent",
                  arguments: '{"context": "User needs specialist help"}'
                }
              }]
            }
          }]
        }

        result = processor.process_model_response(
          response: response,
          agent: agent,
          all_tools: all_tools,
          handoffs: handoffs
        )

        expect(result.new_items).to have(2).items
        expect(result.new_items.last).to be_a(RAAF::Items::HandoffCallItem)
        expect(result.handoffs).to have(1).item
        expect(result.handoffs.first).to be_a(RAAF::ToolRunHandoff)
        expect(result.tools_used).to eq(["transfer_to_target_agent"])
      end
    end

    context "with computer actions" do
      let(:all_tools) { [computer_tool] }

      it "processes computer use actions" do
        response = {
          output: [{
            type: "computer_use",
            action: "screenshot"
          }]
        }

        result = processor.process_model_response(
          response: response,
          agent: agent,
          all_tools: all_tools,
          handoffs: handoffs
        )

        expect(result.new_items).to have(1).item
        expect(result.computer_actions).to have(1).item
        expect(result.computer_actions.first).to be_a(RAAF::ToolRunComputerAction)
        expect(result.tools_used).to eq(["computer_use"])
      end

      it "raises error when computer tool not available" do
        response = {
          output: [{
            type: "computer_use",
            action: "screenshot"
          }]
        }

        expect {
          processor.process_model_response(
            response: response,
            agent: agent,
            all_tools: [],  # No computer tool available
            handoffs: handoffs
          )
        }.to raise_error(RAAF::Errors::ModelBehaviorError, /Computer tool not available/)
      end
    end

    context "with local shell calls" do
      let(:all_tools) { [local_shell_tool] }

      it "processes local shell calls" do
        response = {
          output: [{
            type: "local_shell",
            command: "ls -la"
          }]
        }

        result = processor.process_model_response(
          response: response,
          agent: agent,
          all_tools: all_tools,
          handoffs: handoffs
        )

        expect(result.new_items).to have(1).item
        expect(result.local_shell_calls).to have(1).item
        expect(result.local_shell_calls.first).to be_a(RAAF::ToolRunLocalShellCall)
        expect(result.tools_used).to eq(["local_shell"])
      end

      it "raises error when local shell tool not available" do
        response = {
          output: [{
            type: "local_shell",
            command: "ls -la"
          }]
        }

        expect {
          processor.process_model_response(
            response: response,
            agent: agent,
            all_tools: [], # No local shell tool available
            handoffs: handoffs
          )
        }.to raise_error(RAAF::Errors::ModelBehaviorError, /Local shell tool not available/)
      end
    end

    context "with specialized search tools" do
      it "processes file search" do
        response = {
          output: [{
            type: "file_search",
            query: "test files"
          }]
        }

        result = processor.process_model_response(
          response: response,
          agent: agent,
          all_tools: all_tools,
          handoffs: handoffs
        )

        expect(result.new_items).to have(1).item
        expect(result.tools_used).to eq(["file_search"])
      end

      it "processes web search" do
        response = {
          output: [{
            type: "web_search",
            query: "Ruby programming"
          }]
        }

        result = processor.process_model_response(
          response: response,
          agent: agent,
          all_tools: all_tools,
          handoffs: handoffs
        )

        expect(result.new_items).to have(1).item
        expect(result.tools_used).to eq(["web_search"])
      end
    end

    context "with unknown item types" do
      it "treats unknown items as messages and logs warning" do
        response = {
          output: [{
            type: "unknown_type",
            data: "some data"
          }]
        }

        expect(processor).to receive(:log_warn).with(
          "Unknown response item type", 
          type: "unknown_type", 
          item_keys: [:type, :data]
        )

        result = processor.process_model_response(
          response: response,
          agent: agent,
          all_tools: all_tools,
          handoffs: handoffs
        )

        expect(result.new_items).to have(1).item
        expect(result.new_items.first).to be_a(RAAF::Items::MessageOutputItem)
      end
    end

    context "error handling" do
      it "raises error for unknown tool" do
        response = {
          choices: [{
            message: {
              role: "assistant",
              tool_calls: [{
                id: "call_789",
                function: {
                  name: "unknown_tool",
                  arguments: "{}"
                }
              }]
            }
          }]
        }

        expect {
          processor.process_model_response(
            response: response,
            agent: agent,
            all_tools: all_tools,
            handoffs: handoffs
          )
        }.to raise_error(RAAF::Errors::ModelBehaviorError, /Tool unknown_tool not found/)
      end
    end
  end

  describe "private methods" do
    describe "#extract_response_items" do
      it "extracts items from Chat Completions format" do
        response = {
          choices: [{
            message: {
              role: "assistant",
              content: "Hello",
              tool_calls: [{ id: "call_1", function: { name: "test" } }]
            }
          }]
        }

        items = processor.send(:extract_response_items, response)
        expect(items).to have(2).items
        expect(items[0]).to include(role: "assistant", content: "Hello")
        expect(items[1]).to include(id: "call_1")
      end

      it "extracts items from Responses API format" do
        response = {
          output: [
            { role: "assistant", content: "Hello" },
            { type: "function", name: "test" }
          ]
        }

        items = processor.send(:extract_response_items, response)
        expect(items).to have(2).items
        expect(items[0]).to include(role: "assistant")
        expect(items[1]).to include(type: "function")
      end

      it "handles direct message format" do
        response = { role: "assistant", content: "Direct" }

        items = processor.send(:extract_response_items, response)
        expect(items).to have(1).item
        expect(items[0]).to include(role: "assistant")
      end
    end

    describe "#infer_item_type" do
      it "infers message type" do
        item = { role: "assistant", content: "Hello" }
        type = processor.send(:infer_item_type, item)
        expect(type).to eq("message")
      end

      it "infers function type from name" do
        item = { name: "get_weather", arguments: "{}" }
        type = processor.send(:infer_item_type, item)
        expect(type).to eq("function")
      end

      it "infers function type from function field" do
        item = { function: { name: "test" } }
        type = processor.send(:infer_item_type, item)
        expect(type).to eq("function")
      end

      it "infers computer_use type" do
        item = { action: "screenshot" }
        type = processor.send(:infer_item_type, item)
        expect(type).to eq("computer_use")
      end

      it "infers local_shell type" do
        item = { command: "ls" }
        type = processor.send(:infer_item_type, item)
        expect(type).to eq("local_shell")
      end

      it "returns nil for unknown types" do
        item = { unknown: "data" }
        type = processor.send(:infer_item_type, item)
        expect(type).to be_nil
      end
    end

    describe "#build_handoff_map" do
      it "builds map for Agent objects" do
        agent1 = RAAF::Agent.new(name: "TestAgent", instructions: "Test")
        agent2 = RAAF::Agent.new(name: "SpecialAgent", instructions: "Special")
        handoffs = [agent1, agent2]

        map = processor.send(:build_handoff_map, handoffs)

        expect(map).to include(
          "transfer_to_test_agent" => agent1,
          "transfer_to_special_agent" => agent2
        )
      end

      it "builds map for Handoff objects" do
        handoff = double("handoff", tool_name: "custom_handoff", is_a?: false)
        allow(handoff).to receive(:is_a?).with(RAAF::Agent).and_return(false)
        handoffs = [handoff]

        map = processor.send(:build_handoff_map, handoffs)

        expect(map).to include("custom_handoff" => handoff)
      end
    end

    describe "#build_function_map" do
      it "builds map for FunctionTool objects" do
        tool1 = double("tool1", name: "tool1", is_a?: true)
        tool2 = double("tool2", name: "tool2", is_a?: false) # Not a FunctionTool
        tool3 = double("tool3", name: "tool3", is_a?: true)
        allow(tool1).to receive(:is_a?).with(RAAF::FunctionTool).and_return(true)
        allow(tool2).to receive(:is_a?).with(RAAF::FunctionTool).and_return(false)
        allow(tool3).to receive(:is_a?).with(RAAF::FunctionTool).and_return(true)

        tools = [tool1, tool2, tool3]

        map = processor.send(:build_function_map, tools)

        expect(map).to include(
          "tool1" => tool1,
          "tool3" => tool3
        )
        expect(map).not_to include("tool2")
      end
    end

    describe "#find_computer_tool" do
      it "finds computer tool by class name" do
        regular_tool = double("tool", class: double(name: "RegularTool"))
        computer_tool = double("tool", class: double(name: "ComputerTool"))
        tools = [regular_tool, computer_tool]

        result = processor.send(:find_computer_tool, tools)
        expect(result).to eq(computer_tool)
      end

      it "returns nil when no computer tool found" do
        tools = [double("tool", class: double(name: "RegularTool"))]

        result = processor.send(:find_computer_tool, tools)
        expect(result).to be_nil
      end
    end

    describe "#find_local_shell_tool" do
      it "finds local shell tool by class name" do
        regular_tool = double("tool", class: double(name: "RegularTool"))
        shell_tool = double("tool", class: double(name: "LocalShellTool"))
        tools = [regular_tool, shell_tool]

        result = processor.send(:find_local_shell_tool, tools)
        expect(result).to eq(shell_tool)
      end

      it "returns nil when no local shell tool found" do
        tools = [double("tool", class: double(name: "RegularTool"))]

        result = processor.send(:find_local_shell_tool, tools)
        expect(result).to be_nil
      end
    end

    describe "item creation methods" do
      describe "#create_message_item" do
        it "creates message item with defaults" do
          item = { content: "Hello" }
          allow(RAAF::Items::MessageOutputItem).to receive(:new).and_call_original

          result = processor.send(:create_message_item, item, agent)

          expect(RAAF::Items::MessageOutputItem).to have_received(:new)
            .with(agent: agent, raw_item: hash_including(
              type: "message",
              role: "assistant",
              content: "Hello",
              agent: "TestAgent"
            ))
        end

        it "uses provided role and content" do
          item = { role: "user", content: "Question?" }
          allow(RAAF::Items::MessageOutputItem).to receive(:new)

          processor.send(:create_message_item, item, agent)

          expect(RAAF::Items::MessageOutputItem).to have_received(:new)
            .with(agent: agent, raw_item: hash_including(
              role: "user",
              content: "Question?"
            ))
        end
      end

      describe "#create_tool_call_item" do
        it "creates tool call item with function structure" do
          item = {
            id: "call_123",
            function: {
              name: "get_weather",
              arguments: '{"location": "NYC"}'
            }
          }
          allow(RAAF::Items::ToolCallItem).to receive(:new)

          processor.send(:create_tool_call_item, item, agent)

          expect(RAAF::Items::ToolCallItem).to have_received(:new)
            .with(agent: agent, raw_item: hash_including(
              type: "tool_call",
              id: "call_123",
              name: "get_weather",
              arguments: '{"location": "NYC"}'
            ))
        end

        it "creates tool call item with direct structure" do
          item = {
            name: "test_tool",
            arguments: "{}"
          }
          allow(RAAF::Items::ToolCallItem).to receive(:new)
          allow(SecureRandom).to receive(:uuid).and_return("uuid-123")

          processor.send(:create_tool_call_item, item, agent)

          expect(RAAF::Items::ToolCallItem).to have_received(:new)
            .with(agent: agent, raw_item: hash_including(
              type: "tool_call",
              id: "uuid-123",
              name: "test_tool",
              arguments: "{}"
            ))
        end
      end

      describe "#create_handoff_call_item" do
        it "creates handoff call item" do
          item = {
            id: "call_handoff",
            function: {
              name: "transfer_to_agent",
              arguments: '{"context": "help needed"}'
            }
          }
          allow(RAAF::Items::HandoffCallItem).to receive(:new)

          processor.send(:create_handoff_call_item, item, agent)

          expect(RAAF::Items::HandoffCallItem).to have_received(:new)
            .with(agent: agent, raw_item: hash_including(
              type: "function_call",
              id: "call_handoff", 
              name: "transfer_to_agent",
              arguments: '{"context": "help needed"}'
            ))
        end
      end
    end
  end

  describe "integration with Utils" do
    it "uses Utils.deep_symbolize_keys for key normalization" do
      response = {
        "output" => [
          {
            "role" => "assistant",
            "content" => "Hello"
          }
        ]
      }

      expect(RAAF::Utils).to receive(:deep_symbolize_keys).at_least(:once).and_call_original

      processor.process_model_response(
        response: response,
        agent: agent,
        all_tools: all_tools,
        handoffs: handoffs
      )
    end

    it "uses Utils.snake_case for agent name conversion" do
      agent_with_complex_name = RAAF::Agent.new(name: "ComplexAgentName", instructions: "Complex")
      handoffs = [agent_with_complex_name]

      expect(RAAF::Utils).to receive(:snake_case).with("ComplexAgentName").and_call_original

      processor.send(:build_handoff_map, handoffs)
    end
  end
end
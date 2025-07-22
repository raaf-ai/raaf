# frozen_string_literal: true

require "spec_helper"

# This spec file tests the RAAF::Handoffs factory module and the internal
# RAAF::CallbackHandoffTool class that it creates. The CallbackHandoffTool class is the
# internal callback-based implementation used by the factory methods like .handoff(),
# .simple_handoff(), .conditional_handoff(), and .validated_handoff().

RSpec.describe "RAAF::Handoffs and CallbackHandoffTool" do
  let(:target_agent) { RAAF::Agent.new(name: "TargetAgent", instructions: "Target agent") }
  let(:support_agent) { RAAF::Agent.new(name: "SupportAgent", instructions: "Support agent") }
  let(:context_wrapper) { double("context_wrapper", messages: [], store: nil, fetch: nil) }

  describe "RECOMMENDED_PROMPT_PREFIX" do
    it "contains the standard handoff instructions" do
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("multi-agent system")
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("transfer_to_<agent_name>")
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("handled seamlessly")
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("do not mention or draw attention")
    end

    it "includes system context header" do
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("# System context")
    end

    it "mentions Agents SDK" do
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("Agents SDK")
    end

    it "explains handoff functions" do
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("handoff function")
      expect(RAAF::RECOMMENDED_PROMPT_PREFIX).to include("generally named")
    end
  end

  describe ".prompt_with_handoff_instructions" do
    it "prepends handoff instructions to custom prompt" do
      custom_prompt = "You are a helpful assistant."
      result = RAAF.prompt_with_handoff_instructions(custom_prompt)

      expect(result).to start_with(RAAF::RECOMMENDED_PROMPT_PREFIX)
      expect(result).to end_with(custom_prompt)
      expect(result).to include("\n\n#{custom_prompt}")
    end

    it "handles empty prompt" do
      result = RAAF.prompt_with_handoff_instructions("")
      expect(result).to eq(RAAF::RECOMMENDED_PROMPT_PREFIX)
    end

    it "handles nil prompt" do
      result = RAAF.prompt_with_handoff_instructions(nil)
      expect(result).to eq(RAAF::RECOMMENDED_PROMPT_PREFIX)
    end

    it "properly separates prefix from custom instructions" do
      custom_prompt = "You are a customer service agent."
      result = RAAF.prompt_with_handoff_instructions(custom_prompt)

      lines = result.split("\n")
      expect(lines).to include("# System context")
      expect(lines).to include("You are a customer service agent.")

      # Should have blank lines separating sections
      expect(result).to include("\n\n")
    end

    it "maintains formatting with multi-line custom prompts" do
      custom_prompt = <<~INSTRUCTIONS
        You are a technical support agent.

        Your responsibilities:
        - Diagnose technical issues
        - Provide solutions
        - Escalate when necessary
      INSTRUCTIONS

      result = RAAF.prompt_with_handoff_instructions(custom_prompt)

      expect(result).to start_with(RAAF::RECOMMENDED_PROMPT_PREFIX)
      expect(result).to include("You are a technical support agent.")
      expect(result).to include("Your responsibilities:")
      expect(result).to include("- Diagnose technical issues")
    end
  end

  describe RAAF::HandoffInputData do
    let(:input_history) { [{ role: "user", content: "Hello" }] }
    let(:pre_handoff_items) { %w[item1 item2] }
    let(:new_items) { %w[item3 item4] }

    describe "#initialize" do
      it "stores all provided data" do
        data = described_class.new(
          input_history: input_history,
          pre_handoff_items: pre_handoff_items,
          new_items: new_items
        )

        expect(data.input_history).to eq(input_history)
        expect(data.pre_handoff_items).to eq(pre_handoff_items)
        expect(data.new_items).to eq(new_items)
      end
    end

    describe "#all_items" do
      it "combines pre_handoff_items and new_items" do
        data = described_class.new(
          input_history: input_history,
          pre_handoff_items: pre_handoff_items,
          new_items: new_items
        )

        expect(data.all_items).to eq(%w[item1 item2 item3 item4])
      end

      it "handles empty arrays" do
        data = described_class.new(
          input_history: [],
          pre_handoff_items: [],
          new_items: []
        )

        expect(data.all_items).to eq([])
      end
    end
  end

  describe "RAAF::CallbackHandoffTool (internal callback implementation class)" do
    let(:handoff_tool) do
      RAAF::CallbackHandoffTool.new(
        tool_name: "transfer_to_support",
        tool_description: "Transfer to support agent",
        input_json_schema: {},
        on_invoke_handoff: ->(_context, _input) { support_agent },
        agent_name: "SupportAgent"
      )
    end

    describe "#initialize" do
      it "stores all configuration" do
        expect(handoff_tool.tool_name).to eq("transfer_to_support")
        expect(handoff_tool.tool_description).to eq("Transfer to support agent")
        expect(handoff_tool.input_json_schema).to eq({})
        expect(handoff_tool.agent_name).to eq("SupportAgent")
        expect(handoff_tool.input_filter).to be_nil
        expect(handoff_tool.strict_json_schema).to be true
      end

      it "accepts optional parameters" do
        filter = ->(x) { x }
        tool = RAAF::CallbackHandoffTool.new(
          tool_name: "test",
          tool_description: "Test tool",
          input_json_schema: { type: "object" },
          on_invoke_handoff: ->(_c, _i) {},
          agent_name: "TestAgent",
          input_filter: filter,
          strict_json_schema: false
        )

        expect(tool.input_filter).to eq(filter)
        expect(tool.strict_json_schema).to be false
      end
    end

    describe "#invoke" do
      it "calls the handoff function with context and input" do
        callback_executed = false
        callback_context = nil
        callback_input = nil

        tool = RAAF::CallbackHandoffTool.new(
          tool_name: "test_transfer",
          tool_description: "Test transfer",
          input_json_schema: {},
          on_invoke_handoff: lambda { |context, input|
            callback_executed = true
            callback_context = context
            callback_input = input
            target_agent
          },
          agent_name: "TargetAgent"
        )

        result = tool.invoke(context_wrapper, '{"test": "data"}')

        expect(callback_executed).to be true
        expect(callback_context).to eq(context_wrapper)
        expect(callback_input).to eq('{"test": "data"}')
        expect(result).to eq(target_agent)
      end

      it "handles invocation without input" do
        result = handoff_tool.invoke(context_wrapper)
        expect(result).to eq(support_agent)
      end
    end

    describe "#get_transfer_message" do
      it "generates JSON transfer message" do
        message = handoff_tool.get_transfer_message(support_agent)
        parsed = JSON.parse(message)

        expect(parsed).to eq({ "assistant" => "SupportAgent" })
      end
    end

    describe "#to_tool_definition" do
      it "generates OpenAI function definition" do
        definition = handoff_tool.to_tool_definition

        expect(definition).to eq({
                                   type: "function",
                                   name: "transfer_to_support",
                                   function: {
                                     name: "transfer_to_support",
                                     description: "Transfer to support agent",
                                     parameters: {}
                                   }
                                 })
      end

      it "includes schema when provided" do
        schema = {
          type: "object",
          properties: { reason: { type: "string" } },
          required: ["reason"]
        }

        tool = RAAF::CallbackHandoffTool.new(
          tool_name: "transfer_with_reason",
          tool_description: "Transfer with reason",
          input_json_schema: schema,
          on_invoke_handoff: ->(_c, _i) {},
          agent_name: "TestAgent"
        )

        definition = tool.to_tool_definition

        expect(definition[:function][:parameters]).to eq(schema)
      end
    end

    describe ".default_tool_name" do
      it "generates snake_case tool names" do
        expect(RAAF::CallbackHandoffTool.default_tool_name(support_agent))
          .to eq("transfer_to_support_agent")
      end

      it "handles complex agent names" do
        complex_agent = RAAF::Agent.new(name: "CustomerServiceSpecialist", instructions: "Specialist")

        expect(RAAF::CallbackHandoffTool.default_tool_name(complex_agent))
          .to eq("transfer_to_customer_service_specialist")
      end
    end

    describe ".default_tool_description" do
      it "generates standard descriptions" do
        expect(RAAF::CallbackHandoffTool.default_tool_description(support_agent))
          .to eq("Handoff to the SupportAgent agent to handle the request.")
      end

      it "includes agent handoff_description if available" do
        allow(support_agent).to receive(:respond_to?).with(:handoff_description).and_return(true)
        allow(support_agent).to receive(:handoff_description).and_return("Specialized support")

        description = RAAF::CallbackHandoffTool.default_tool_description(support_agent)

        expect(description).to include("Specialized support")
      end
    end
  end

  describe "RAAF::Handoffs.handoff factory method" do
    describe "basic functionality" do
      it "creates CallbackHandoffTool with default settings" do
        handoff = RAAF::Handoffs.handoff(target_agent)

        expect(handoff).to be_a(RAAF::CallbackHandoffTool)
        expect(handoff.agent_name).to eq("TargetAgent")
        expect(handoff.tool_name).to eq("transfer_to_target_agent")
        expect(handoff.input_json_schema).to eq({})
      end

      it "accepts custom tool name and description" do
        handoff = RAAF::Handoffs.handoff(
          target_agent,
          tool_name_override: "escalate_to_specialist",
          tool_description_override: "Escalate to specialist"
        )

        expect(handoff.tool_name).to eq("escalate_to_specialist")
        expect(handoff.tool_description).to eq("Escalate to specialist")
      end
    end

    describe "with on_handoff callback" do
      it "executes callback when handoff is invoked" do
        callback_executed = false
        callback_context = nil

        handoff = RAAF::Handoffs.handoff(
          target_agent,
          on_handoff: lambda { |context|
            callback_executed = true
            callback_context = context
            "callback_result"
          }
        )

        result = handoff.invoke(context_wrapper)

        expect(callback_executed).to be true
        expect(callback_context).to eq(context_wrapper)
        expect(result).to eq(target_agent)
      end

      it "executes callback with input validation" do
        callback_executed = false
        callback_input = nil

        handoff = RAAF::Handoffs.handoff(
          target_agent,
          input_type: String,
          on_handoff: lambda { |_context, input|
            callback_executed = true
            callback_input = input
            "processed: #{input}"
          }
        )

        input_json = '{"input": "test_value"}'
        result = handoff.invoke(context_wrapper, input_json)

        expect(callback_executed).to be true
        expect(callback_input).to eq("test_value")
        expect(result).to eq(target_agent)
      end

      it "validates callback arity for context-only callbacks" do
        handoff = RAAF::Handoffs.handoff(
          target_agent,
          on_handoff: ->(_context, _extra) { "wrong_arity" } # Should take 1 param
        )

        expect do
          handoff.invoke(context_wrapper)
        end.to raise_error(ArgumentError, /must take one argument/)
      end

      it "validates callback arity for input validation callbacks" do
        handoff = RAAF::Handoffs.handoff(
          target_agent,
          input_type: String,
          on_handoff: ->(_context) { "wrong_arity" } # Should take 2 params with input_type
        )

        expect do
          handoff.invoke(context_wrapper, '{"input": "test"}')
        end.to raise_error(ArgumentError, /must take two arguments/)
      end

      it "handles callback exceptions" do
        handoff = RAAF::Handoffs.handoff(
          target_agent,
          on_handoff: lambda { |_context|
            raise StandardError, "Callback failed"
          }
        )

        expect do
          handoff.invoke(context_wrapper)
        end.to raise_error(StandardError, "Callback failed")
      end
    end

    describe "input type validation" do
      describe "String input type" do
        it "validates and converts string input" do
          input_received = nil

          handoff = RAAF::Handoffs.handoff(
            target_agent,
            input_type: String,
            on_handoff: lambda { |_context, input|
              input_received = input
            }
          )

          handoff.invoke(context_wrapper, '{"input": "test_string"}')

          expect(input_received).to eq("test_string")
          expect(input_received).to be_a(String)
        end

        it "creates correct JSON schema for String" do
          handoff = RAAF::Handoffs.handoff(
            target_agent,
            input_type: String,
            on_handoff: ->(_context, input) { input }
          )

          expect(handoff.input_json_schema).to include(
            "type" => "object",
            "properties" => {
              "input" => { "type" => "string" }
            },
            "required" => ["input"]
          )
        end
      end

      describe "Integer input type" do
        it "validates and converts integer input" do
          input_received = nil

          handoff = RAAF::Handoffs.handoff(
            target_agent,
            input_type: Integer,
            on_handoff: lambda { |_context, input|
              input_received = input
            }
          )

          handoff.invoke(context_wrapper, '{"input": 42}')

          expect(input_received).to eq(42)
          expect(input_received).to be_a(Integer)
        end

        it "creates correct JSON schema for Integer" do
          handoff = RAAF::Handoffs.handoff(
            target_agent,
            input_type: Integer,
            on_handoff: ->(_context, input) { input }
          )

          expect(handoff.input_json_schema).to include(
            "type" => "object",
            "properties" => {
              "input" => { "type" => "integer" }
            },
            "required" => ["input"]
          )
        end
      end

      describe "Hash input type" do
        it "validates and passes hash input directly" do
          input_received = nil

          handoff = RAAF::Handoffs.handoff(
            target_agent,
            input_type: Hash,
            on_handoff: lambda { |_context, input|
              input_received = input
            }
          )

          hash_input = '{"customer_id": "123", "priority": "high"}'
          handoff.invoke(context_wrapper, hash_input)

          expect(input_received).to eq({ "customer_id" => "123", "priority" => "high" })
          expect(input_received).to be_a(Hash)
        end

        it "creates correct JSON schema for Hash" do
          handoff = RAAF::Handoffs.handoff(
            target_agent,
            input_type: Hash,
            on_handoff: ->(_context, input) { input }
          )

          expect(handoff.input_json_schema).to include(
            "type" => "object",
            "properties" => {},
            "additionalProperties" => false
          )
        end
      end

      describe "Custom type input" do
        let(:custom_class) do
          Class.new do
            def initialize(data)
              @data = data
            end

            attr_reader :data
          end
        end

        it "attempts to instantiate custom types" do
          input_received = nil

          handoff = RAAF::Handoffs.handoff(
            target_agent,
            input_type: custom_class,
            on_handoff: lambda { |_context, input|
              input_received = input
            }
          )

          # For custom types, the full hash is passed to the constructor
          hash_input = '{"test": "value"}'
          handoff.invoke(context_wrapper, hash_input)

          expect(input_received).to be_a(custom_class)
          expect(input_received.data).to eq({ "test" => "value" })
        end
      end
    end

    describe "error handling" do
      it "raises error when input_type is provided without on_handoff" do
        expect do
          RAAF::Handoffs.handoff(target_agent, input_type: String)
        end.to raise_error(ArgumentError, /must provide on_handoff when using input_type/)
      end

      it "raises error for missing input when input_type is specified" do
        handoff = RAAF::Handoffs.handoff(
          target_agent,
          input_type: String,
          on_handoff: ->(_context, input) { input }
        )

        expect do
          handoff.invoke(context_wrapper, nil)
        end.to raise_error(RAAF::ModelBehaviorError, /expected non-null input/)
      end

      it "raises error for invalid JSON with input_type" do
        handoff = RAAF::Handoffs.handoff(
          target_agent,
          input_type: String,
          on_handoff: ->(_context, input) { input }
        )

        expect do
          handoff.invoke(context_wrapper, '{"invalid": json')
        end.to raise_error(RAAF::ModelBehaviorError, /Invalid JSON input/)
      end
    end

    describe "with input_filter" do
      it "applies input filter when provided" do
        filter = ->(input) { input.except("sensitive") }

        handoff = RAAF::Handoffs.handoff(
          target_agent,
          input_filter: filter
        )

        expect(handoff.input_filter).to eq(filter)
      end
    end
  end

  describe "RAAF::Handoffs.simple_handoff" do
    it "creates basic handoff without callbacks" do
      handoff = RAAF::Handoffs.simple_handoff(
        target_agent,
        description: "Simple transfer"
      )

      result = handoff.invoke(context_wrapper)

      expect(result).to eq(target_agent)
      expect(handoff.tool_description).to eq("Simple transfer")
    end

    it "uses default description when none provided" do
      handoff = RAAF::Handoffs.simple_handoff(target_agent)

      expect(handoff.tool_description).to include("TargetAgent")
    end
  end

  describe "RAAF::Handoffs.conditional_handoff" do
    it "executes condition check and allows handoff when true" do
      condition_executed = false
      condition_context = nil

      handoff = RAAF::Handoffs.conditional_handoff(
        target_agent,
        condition: lambda { |context|
          condition_executed = true
          condition_context = context
          true
        },
        description: "Conditional transfer"
      )

      result = handoff.invoke(context_wrapper)

      expect(condition_executed).to be true
      expect(condition_context).to eq(context_wrapper)
      expect(result).to eq(target_agent)
    end

    it "raises HandoffError when condition returns false" do
      handoff = RAAF::Handoffs.conditional_handoff(
        target_agent,
        condition: ->(_context) { false }
      )

      expect do
        handoff.invoke(context_wrapper)
      end.to raise_error(RAAF::HandoffError, /Handoff condition not met/)
    end

    it "allows condition exceptions to bubble up" do
      handoff = RAAF::Handoffs.conditional_handoff(
        target_agent,
        condition: lambda { |_context|
          raise StandardError, "Condition check failed"
        }
      )

      expect do
        handoff.invoke(context_wrapper)
      end.to raise_error(StandardError, "Condition check failed")
    end
  end

  describe "RAAF::Handoffs.validated_handoff" do
    let(:schema) do
      {
        type: "object",
        properties: {
          priority: { type: "string", enum: %w[low medium high] },
          customer_id: { type: "string" }
        },
        required: ["priority"]
      }
    end

    it "executes validation and allows handoff with valid input" do
      # Mock the validator to return success
      validator = double("validator")
      allow(RAAF::StructuredOutput::ResponseFormatter).to receive(:new)
        .with(schema)
        .and_return(validator)
      allow(validator).to receive(:format_response)
        .and_return({ valid: true })

      handoff = RAAF::Handoffs.validated_handoff(
        target_agent,
        input_schema: schema,
        description: "Validated transfer"
      )

      valid_input = '{"priority": "high", "customer_id": "123"}'
      result = handoff.invoke(context_wrapper, valid_input)

      expect(result).to eq(target_agent)
    end

    it "raises HandoffError with invalid input" do
      # Mock the validator to return failure
      validator = double("validator")
      allow(RAAF::StructuredOutput::ResponseFormatter).to receive(:new)
        .with(schema)
        .and_return(validator)
      allow(validator).to receive(:format_response)
        .and_return({ valid: false, error: "Priority is required" })

      handoff = RAAF::Handoffs.validated_handoff(
        target_agent,
        input_schema: schema
      )

      invalid_input = '{"customer_id": "123"}'
      expect do
        handoff.invoke(context_wrapper, invalid_input)
      end.to raise_error(RAAF::HandoffError, /Invalid handoff input: Priority is required/)
    end

    it "sets up Hash input_type for validation" do
      allow(RAAF::StructuredOutput::ResponseFormatter).to receive(:new).and_return(double(format_response: { valid: true }))

      handoff = RAAF::Handoffs.validated_handoff(
        target_agent,
        input_schema: schema
      )

      expect(handoff.input_json_schema).to include(
        "type" => "object",
        "properties" => {},
        "additionalProperties" => false
      )
    end
  end

  describe "integration with RAAF module convenience method" do
    it "creates handoff configuration object (not internal tool)" do
      result = RAAF.handoff(target_agent, tool_name_override: "custom")

      # RAAF.handoff creates the configuration class, not the internal CallbackHandoffTool
      expect(result).to be_a(RAAF::Handoff)
      expect(result.agent).to eq(target_agent)
      expect(result.tool_name_override).to eq("custom")
    end
  end

  describe "Custom Handoff Objects and Callbacks" do
    let(:callback_executed) { double("callback_tracker") }

    it "supports handoff objects with on_handoff callbacks" do
      # Create handoff with callback
      custom_handoff = RAAF::Handoffs.handoff(
        target_agent,
        tool_name_override: "custom_transfer",
        on_handoff: lambda { |context|
          callback_executed.callback_called(context)
          "callback_result"
        }
      )

      expect(callback_executed).to receive(:callback_called)

      # Simulate handoff invocation
      context_wrapper = double("context")
      result = custom_handoff.invoke(context_wrapper)

      expect(result).to eq(target_agent)
    end

    it "supports conditional handoffs with condition evaluation" do
      condition_check = double("condition_checker")

      conditional_handoff = RAAF::Handoffs.conditional_handoff(
        target_agent,
        condition: lambda { |context|
          condition_check.condition_evaluated(context)
          true
        }
      )

      expect(condition_check).to receive(:condition_evaluated)

      context_wrapper = double("context")
      result = conditional_handoff.invoke(context_wrapper)

      expect(result).to eq(target_agent)
    end

    it "supports validated handoffs with schema validation" do
      schema = {
        type: "object",
        properties: { priority: { type: "string" } },
        required: ["priority"]
      }

      # Mock validator
      validator = double("validator")
      allow(RAAF::StructuredOutput::ResponseFormatter).to receive(:new).and_return(validator)
      allow(validator).to receive(:format_response).and_return({ valid: true })

      validated_handoff = RAAF::Handoffs.validated_handoff(
        target_agent,
        input_schema: schema
      )

      context_wrapper = double("context")
      result = validated_handoff.invoke(context_wrapper, '{"priority": "high"}')

      expect(result).to eq(target_agent)
    end
  end
end

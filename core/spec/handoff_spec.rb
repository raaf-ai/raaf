# frozen_string_literal: true

require "spec_helper"

# This spec file tests the RAAF::Handoff configuration class (handoff.rb).
# This is the Python SDK-compatible configuration object that users create
# to define handoff specifications before they're converted to internal
# HandoffTool objects by the agent system.

RSpec.describe "RAAF Handoff System" do
  describe RAAF::Handoff do
    let(:target_agent) { RAAF::Agent.new(name: "TargetAgent", instructions: "Target agent") }
    let(:custom_class) { Class.new(RAAF::Agent) }

    describe ".initialize" do
      it "creates handoff with agent object" do
        handoff = described_class.new(target_agent)

        expect(handoff.agent).to eq(target_agent)
        expect(handoff.overrides).to eq({})
        expect(handoff.input_filter).to be_nil
        expect(handoff.description).to be_nil
        expect(handoff.tool_name_override).to be_nil
        expect(handoff.tool_description_override).to be_nil
        expect(handoff.on_handoff).to be_nil
        expect(handoff.input_type).to be_nil
      end

      it "creates handoff with agent class" do
        handoff = described_class.new(custom_class)

        expect(handoff.agent).to eq(custom_class)
        expect(handoff.overrides).to eq({})
      end

      it "accepts all optional parameters" do
        input_filter = ->(data) { data.except(:sensitive) }
        on_handoff_callback = ->(_data) { puts "Handoff executed" }

        handoff = described_class.new(
          target_agent,
          overrides: { model: "gpt-4", temperature: 0.7 },
          input_filter: input_filter,
          description: "Transfer to specialist",
          tool_name_override: "escalate_to_specialist",
          tool_description_override: "Escalate issue to specialist",
          on_handoff: on_handoff_callback,
          input_type: String
        )

        expect(handoff.agent).to eq(target_agent)
        expect(handoff.overrides).to eq({ model: "gpt-4", temperature: 0.7 })
        expect(handoff.input_filter).to eq(input_filter)
        expect(handoff.description).to eq("Transfer to specialist")
        expect(handoff.tool_name_override).to eq("escalate_to_specialist")
        expect(handoff.tool_description_override).to eq("Escalate issue to specialist")
        expect(handoff.on_handoff).to eq(on_handoff_callback)
        expect(handoff.input_type).to eq(String)
      end
    end

    describe "#get_input_schema" do
      context "when target agent responds to get_input_schema" do
        let(:custom_schema) do
          {
            type: "object",
            properties: {
              customer_id: { type: "string" },
              issue_type: { type: "string" }
            },
            required: ["customer_id"]
          }
        end

        before do
          allow(target_agent).to receive(:get_input_schema).and_return(custom_schema)
        end

        it "returns agent's schema" do
          handoff = described_class.new(target_agent)

          expect(handoff.get_input_schema).to eq(custom_schema)
        end
      end

      context "when target agent doesn't respond to get_input_schema" do
        let(:agent_without_schema) do
          agent = RAAF::Agent.new(name: "TestAgent", instructions: "Test")
          agent.define_singleton_method(:get_input_schema) { nil }
          allow(agent).to receive(:respond_to?).with(:get_input_schema).and_return(false)
          agent
        end

        it "returns default schema" do
          handoff = described_class.new(agent_without_schema)
          schema = handoff.get_input_schema

          expect(schema).to include(
            type: "object",
            properties: {
              data: {
                type: "object",
                description: "Data to pass to the target agent",
                additionalProperties: true
              },
              reason: {
                type: "string",
                description: "Reason for the handoff"
              }
            },
            required: [],
            additionalProperties: false
          )
        end
      end
    end

    describe "#filter_input" do
      context "when input_filter is provided" do
        let(:input_filter) { ->(data) { data.except(:password, :secret) } }
        let(:handoff) { described_class.new(target_agent, input_filter: input_filter) }

        it "applies filter to input data" do
          input_data = {
            username: "john",
            password: "secret123",
            email: "john@example.com",
            secret: "top_secret"
          }

          filtered = handoff.filter_input(input_data)

          expect(filtered).to eq({
                                   username: "john",
                                   email: "john@example.com"
                                 })
        end

        it "handles empty input" do
          filtered = handoff.filter_input({})
          expect(filtered).to eq({})
        end
      end

      context "when no input_filter is provided" do
        let(:handoff) { described_class.new(target_agent) }

        it "returns input unchanged" do
          input_data = { name: "test", value: 123 }

          filtered = handoff.filter_input(input_data)

          expect(filtered).to eq(input_data)
        end
      end
    end

    describe "#create_agent_instance" do
      context "when agent is a class" do
        let(:agent_class) do
          Class.new do
            attr_accessor :model, :temperature, :name

            def initialize(model: "gpt-3.5-turbo", temperature: 0.5, name: "DefaultAgent")
              @model = model
              @temperature = temperature
              @name = name
            end
          end
        end

        let(:handoff) do
          described_class.new(
            agent_class,
            overrides: { model: "gpt-4", temperature: 0.8 }
          )
        end

        it "creates new instance with overrides" do
          instance = handoff.create_agent_instance

          expect(instance).to be_a(agent_class)
          expect(instance.model).to eq("gpt-4")
          expect(instance.temperature).to eq(0.8)
        end

        it "merges base config with overrides" do
          base_config = { name: "CustomAgent" }
          instance = handoff.create_agent_instance(base_config)

          expect(instance.model).to eq("gpt-4") # From overrides
          expect(instance.temperature).to eq(0.8) # From overrides
          expect(instance.name).to eq("CustomAgent") # From base_config
        end
      end

      context "when agent is an object" do
        let(:handoff) do
          described_class.new(
            target_agent,
            overrides: { model: "gpt-4", temperature: 0.9 }
          )
        end

        it "clones agent and applies overrides" do
          allow(target_agent).to receive(:clone).and_return(target_agent)
          allow(target_agent).to receive(:model=)
          allow(target_agent).to receive(:temperature=)

          instance = handoff.create_agent_instance

          expect(target_agent).to have_received(:clone)
          expect(instance).to have_received(:model=).with("gpt-4")
          expect(instance).to have_received(:temperature=).with(0.9)
        end

        it "merges base config with overrides for object agents" do
          allow(target_agent).to receive(:clone).and_return(target_agent)
          allow(target_agent).to receive(:model=)
          allow(target_agent).to receive(:temperature=)
          allow(target_agent).to receive(:name=)

          base_config = { name: "OverriddenAgent" }
          instance = handoff.create_agent_instance(base_config)

          expect(instance).to have_received(:model=).with("gpt-4")
          expect(instance).to have_received(:temperature=).with(0.9)
          expect(instance).to have_received(:name=).with("OverriddenAgent")
        end
      end
    end

    describe "attribute readers" do
      let(:handoff) do
        described_class.new(
          target_agent,
          overrides: { model: "gpt-4" },
          input_filter: ->(x) { x },
          description: "Test handoff",
          tool_name_override: "custom_tool",
          tool_description_override: "Custom tool description",
          on_handoff: ->(x) { x },
          input_type: Hash
        )
      end

      it "provides access to all configuration attributes" do
        expect(handoff.agent).to eq(target_agent)
        expect(handoff.overrides).to eq({ model: "gpt-4" })
        expect(handoff.input_filter).to be_a(Proc)
        expect(handoff.description).to eq("Test handoff")
        expect(handoff.tool_name_override).to eq("custom_tool")
        expect(handoff.tool_description_override).to eq("Custom tool description")
        expect(handoff.on_handoff).to be_a(Proc)
        expect(handoff.input_type).to eq(Hash)
      end
    end
  end

  describe "RAAF.handoff factory function" do
    let(:target_agent) { RAAF::Agent.new(name: "TargetAgent", instructions: "Target agent") }

    it "creates handoff using module-level factory" do
      handoff = RAAF.handoff(target_agent)

      expect(handoff).to be_a(RAAF::Handoff)
      expect(handoff.agent).to eq(target_agent)
    end

    it "passes all options to Handoff.new" do
      callback = ->(data) { data }

      handoff = RAAF.handoff(
        target_agent,
        overrides: { model: "gpt-4" },
        input_filter: callback,
        description: "Test",
        tool_name_override: "custom",
        tool_description_override: "Custom description",
        on_handoff: callback,
        input_type: String
      )

      expect(handoff.agent).to eq(target_agent)
      expect(handoff.overrides).to eq({ model: "gpt-4" })
      expect(handoff.input_filter).to eq(callback)
      expect(handoff.description).to eq("Test")
      expect(handoff.tool_name_override).to eq("custom")
      expect(handoff.tool_description_override).to eq("Custom description")
      expect(handoff.on_handoff).to eq(callback)
      expect(handoff.input_type).to eq(String)
    end
  end
end

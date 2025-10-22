# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::AgentToolIntegration do
  let(:test_agent_class) do
    Class.new do
      include RAAF::DSL::AgentToolIntegration

      # Mock required class methods
      def self._tools_config
        @_tools_config ||= []
      end

      def log_error(message, details = {})
        # Mock logging for tests
      end
    end
  end

  let(:mock_tool_registry) { double("ToolRegistry") }
  let(:mock_tool_class) { double("ToolClass") }
  let(:mock_tool_instance) { double("ToolInstance") }

  before do
    stub_const("RAAF::ToolRegistry", mock_tool_registry)
    # Mock safe_lookup: return Class identifiers directly, nil for Symbol identifiers (lazy loading)
    allow(mock_tool_registry).to receive(:safe_lookup) do |identifier|
      if identifier.is_a?(Class)
        identifier  # Return Class directly
      else
        nil  # Return nil for Symbol (lazy loading)
      end
    end
    # Mock the list method for error messages
    allow(mock_tool_registry).to receive(:list).and_return([])
    # Mock resolve_with_details for class identifier resolution errors
    allow(mock_tool_registry).to receive(:resolve_with_details).and_return(
      success: false,
      searched_namespaces: ["RAAF::Tools"],
      suggestions: ["Register it: RAAF::ToolRegistry.register(:custom_tool_class, CustomToolClass)"]
    )
  end

  describe "class methods" do
    describe "#tool" do
      context "with symbol identifier" do
        it "stores configuration without resolving (lazy loading)" do
          test_agent_class.tool(:web_search, max_results: 10)

          config = test_agent_class._tools_config.last
          expect(config[:tool_identifier]).to eq(:web_search)
          expect(config[:tool_class]).to be_nil  # NOT resolved yet
          expect(config[:options]).to eq(max_results: 10)
        end
      end

      context "with class identifier" do
        let(:custom_tool_class) { Class.new }

        it "stores class directly when resolved at class definition time" do
          test_agent_class.tool(custom_tool_class)

          config = test_agent_class._tools_config.last
          expect(config[:tool_class]).to eq(custom_tool_class)
        end
      end

      context "with configuration block" do
        it "evaluates block and merges configuration" do
          test_agent_class.tool(:api_tool, base_url: "http://example.com") do
            api_key "test-key"
            timeout 30
          end

          config = test_agent_class._tools_config.last
          expect(config[:options]).to eq(
            base_url: "http://example.com",
            api_key: "test-key",
            timeout: 30
          )
          expect(config[:tool_identifier]).to eq(:api_tool)
        end
      end
    end

    describe "#tools" do
      it "adds multiple tools with shared options" do
        test_agent_class.tools(:tool1, :tool2, timeout: 60)

        expect(test_agent_class._tools_config.size).to eq(2)
        expect(test_agent_class._tools_config[0][:options]).to eq(timeout: 60)
        expect(test_agent_class._tools_config[1][:options]).to eq(timeout: 60)
        # Symbols use deferred (lazy) resolution, so tool_identifier is present
        expect(test_agent_class._tools_config[0][:tool_identifier]).to eq(:tool1)
        expect(test_agent_class._tools_config[1][:tool_identifier]).to eq(:tool2)
      end
    end
  end

  describe "instance methods" do
    let(:test_agent) { test_agent_class.new }

    describe "#build_tools_from_config" do
      before do
        test_agent_class._tools_config << {
          identifier: :test_tool,
          tool_class: mock_tool_class,
          options: { key: "value" },
          native: false
        }
      end

      it "builds tool instances from configuration" do
        expect(test_agent).to receive(:create_tool_instance_unified)
          .with(hash_including(identifier: :test_tool))
          .and_return(mock_tool_instance)

        tools = test_agent.build_tools_from_config
        expect(tools).to eq([mock_tool_instance])
      end

      it "filters out nil instances" do
        expect(test_agent).to receive(:create_tool_instance_unified).and_return(nil)

        tools = test_agent.build_tools_from_config
        expect(tools).to eq([])
      end
    end

    describe "#create_tool_instance_unified" do
      let(:config) do
        {
          tool_class: mock_tool_class,
          options: { api_key: "test" },
          native: false
        }
      end

      context "with regular tool" do
        it "creates instance and converts to function tool" do
          expect(mock_tool_class).to receive(:new).with(api_key: "test").and_return(mock_tool_instance)
          expect(mock_tool_instance).to receive(:respond_to?).with(:to_function_tool).and_return(true)
          expect(mock_tool_instance).to receive(:to_function_tool).and_return(:function_tool)

          result = test_agent.create_tool_instance_unified(config)
          expect(result).to eq(:function_tool)
        end

        it "returns instance as-is if no to_function_tool method" do
          expect(mock_tool_class).to receive(:new).with(api_key: "test").and_return(mock_tool_instance)
          expect(mock_tool_instance).to receive(:respond_to?).with(:to_function_tool).and_return(false)

          result = test_agent.create_tool_instance_unified(config)
          expect(result).to eq(mock_tool_instance)
        end
      end

      context "with native tool" do
        let(:native_config) { config.merge(native: true) }

        it "returns instance as-is without conversion" do
          expect(mock_tool_class).to receive(:new).with(api_key: "test").and_return(mock_tool_instance)
          expect(mock_tool_instance).not_to receive(:to_function_tool)

          result = test_agent.create_tool_instance_unified(native_config)
          expect(result).to eq(mock_tool_instance)
        end
      end

      context "when tool instantiation fails" do
        it "logs error and returns nil" do
          allow(mock_tool_class).to receive(:name).and_return("MockToolClass")
          expect(mock_tool_class).to receive(:new).and_raise(StandardError.new("test error"))
          expect(test_agent).to receive(:log_error).with(
            "Failed to create tool instance",
            hash_including(error: "test error")
          )

          result = test_agent.create_tool_instance_unified(config)
          expect(result).to be_nil
        end
      end
    end
  end

  describe RAAF::DSL::AgentToolIntegration::ToolConfigurationBuilder do
    describe "#initialize" do
      it "evaluates configuration block" do
        builder = described_class.new do
          api_key "test-key"
          timeout 30
          enabled
        end

        expect(builder.to_h).to eq(
          api_key: "test-key",
          timeout: 30,
          enabled: true
        )
      end
    end

    describe "#method_missing" do
      let(:builder) { described_class.new }

      it "stores single argument as value" do
        builder.api_key("test")
        expect(builder.to_h[:api_key]).to eq("test")
      end

      it "stores no arguments as true" do
        builder.enabled
        expect(builder.to_h[:enabled]).to eq(true)
      end

      it "stores multiple arguments as array" do
        builder.endpoints("url1", "url2")
        expect(builder.to_h[:endpoints]).to eq(["url1", "url2"])
      end
    end

    describe "#respond_to_missing?" do
      let(:builder) { described_class.new }

      it "responds to any method" do
        expect(builder.respond_to?(:any_method)).to eq(true)
        expect(builder.respond_to?(:private_method, true)).to eq(true)
      end
    end
  end
end
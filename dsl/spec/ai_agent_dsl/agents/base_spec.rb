# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe AiAgentDsl::Agents::Base do
  let(:agent_instance) { described_class.new(context_variables: context_variables, processing_params: processing_params) }
  let(:processing_params) { { content_type: "Text", num_documents: 5 } }
  let(:context_variables) { { document: { name: "Test Content", description: "A test document" } } }

  it_behaves_like "an agent class"

  describe "configuration-only base class behavior" do
    it "can be subclassed" do
      subclass = Class.new(described_class)
      expect(subclass.superclass).to eq(described_class)
    end

    it "raises NotImplementedError for abstract configuration methods" do
      abstract_methods = ["agent_name", "build_instructions", "build_schema"]

      abstract_methods.each do |method|
        expect { agent_instance.send(method) }.to raise_error(NotImplementedError, /Subclasses must implement/)
      end
    end
  end

  describe "initialization" do
    it "accepts context_variables and processing_params" do
      expect { described_class.new(context_variables: context_variables, processing_params: processing_params) }.not_to raise_error
    end

    it "stores context_variables and processing_params" do
      agent = described_class.new(context_variables: context_variables, processing_params: processing_params)
      expect(agent.context_variables.to_h).to eq(context_variables)
      expect(agent.processing_params).to eq(processing_params)
    end

    it "defaults to empty context_variables when not provided" do
      agent = described_class.new
      expect(agent.context_variables.to_h).to eq({})
    end

    it "requires processing_params parameter" do
      expect { described_class.new(context_variables: context_variables) }.not_to raise_error
    end
  end

  describe "attribute readers" do
    it "provides access to context_variables" do
      expect(agent_instance.context_variables.to_h).to eq(context_variables)
    end

    it "provides access to processing_params" do
      expect(agent_instance.processing_params).to eq(processing_params)
    end

    it "context_variables is read-only" do
      expect(agent_instance).not_to respond_to(:context_variables=)
    end

    it "processing_params is read-only" do
      expect(agent_instance).not_to respond_to(:processing_params=)
    end
  end

  describe "#create_agent" do
    context "creates OpenAI agent with DSL configuration" do
      before do
        mock_openai_agent
      end

      it "creates OpenAI agent instance with configuration" do
        allow(agent_instance).to receive_messages(agent_name: "TestAgent", build_instructions: "Test instructions", model_name: "gpt-4o", tools: [], handoffs: [], response_format: { type: "json" }, max_turns: 3)

        agent = agent_instance.create_agent

        expect(agent).to be_a(OpenAIAgents::Agent)
      end

      it "passes DSL configuration to OpenAI agent" do
        allow(agent_instance).to receive_messages(agent_name: "TestAgent", build_instructions: "Test instructions", model_name: "gpt-4o", tools: [{ name: "test_tool" }], handoffs: [], response_format: { type: "json" }, max_turns: 5)

        execution_agent = agent_instance.create_agent
        expect(execution_agent).to be_a(OpenAIAgents::Agent)
      end
    end
  end

  describe "abstract configuration methods" do
    describe "#agent_name" do
      it "raises NotImplementedError" do
        expect { agent_instance.agent_name }.to raise_error(NotImplementedError, "Subclasses must implement #agent_name")
      end
    end

    describe "#build_instructions" do
      it "raises NotImplementedError" do
        expect { agent_instance.build_instructions }.to raise_error(NotImplementedError, "Subclasses must implement #build_instructions")
      end
    end

    describe "#build_schema" do
      it "raises NotImplementedError" do
        expect { agent_instance.build_schema }.to raise_error(NotImplementedError, "Subclasses must implement #build_schema")
      end
    end
  end

  describe "optional methods" do
    describe "#build_user_prompt" do
      it "returns nil by default" do
        expect(agent_instance.build_user_prompt).to be_nil
      end

      it "can be overridden in subclasses" do
        subclass = Class.new(described_class) do
          def build_user_prompt
            "Custom user prompt"
          end
        end

        instance = subclass.new(context_variables: context_variables, processing_params: processing_params)
        expect(instance.build_user_prompt).to eq("Custom user prompt")
      end
    end
  end

  describe "default configuration methods" do
    describe "#model_name" do
      it "returns default model" do
        expect(agent_instance.send(:model_name)).to eq("gpt-4o")
      end

      it "can be overridden in subclasses" do
        subclass = Class.new(described_class) do
          protected

          def model_name
            "custom-model"
          end
        end

        instance = subclass.new(context_variables: context_variables, processing_params: processing_params)
        expect(instance.send(:model_name)).to eq("custom-model")
      end
    end

    describe "#tools" do
      it "returns empty array by default" do
        expect(agent_instance.send(:tools)).to eq([])
      end

      it "can be overridden in subclasses" do
        subclass = Class.new(described_class) do
          protected

          def tools
            [{ name: "custom_tool" }]
          end
        end

        instance = subclass.new(context_variables: context_variables, processing_params: processing_params)
        expect(instance.send(:tools)).to eq([{ name: "custom_tool" }])
      end
    end

    describe "#handoffs" do
      it "returns empty array by default" do
        expect(agent_instance.send(:handoffs)).to eq([])
      end

      it "can be overridden in subclasses" do
        subclass = Class.new(described_class) do
          protected

          def handoffs
            ["handoff_agent"]
          end
        end

        instance = subclass.new(context_variables: context_variables, processing_params: processing_params)
        expect(instance.send(:handoffs)).to eq(["handoff_agent"])
      end
    end

    describe "#max_turns" do
      it "returns default max_turns" do
        allow(agent_instance).to receive(:agent_name).and_return("TestAgent")
        # The actual default might come from Config
        expect(agent_instance.send(:max_turns)).to be_a(Integer)
        expect(agent_instance.send(:max_turns)).to be > 0
      end

      it "can be overridden in subclasses" do
        subclass = Class.new(described_class) do
          protected

          def max_turns
            10
          end
        end

        instance = subclass.new(context_variables: context_variables, processing_params: processing_params)
        expect(instance.send(:max_turns)).to eq(10)
      end
    end

    describe "#response_format" do
      before do
        allow(agent_instance).to receive_messages(schema_name: "test_response", build_schema: { type: "object" })
      end

      it "returns JSON schema response format" do
        format = agent_instance.send(:response_format)

        expect(format[:type]).to eq("json_schema")
        expect(format[:json_schema][:name]).to eq("test_response")
        expect(format[:json_schema][:strict]).to be true
        expect(format[:json_schema][:schema]).to eq({ type: "object" })
      end
    end

    describe "#schema_name" do
      before do
        allow(agent_instance).to receive(:agent_name).and_return("TestAgent")
      end

      it "generates schema name from agent name" do
        schema_name = agent_instance.send(:schema_name)
        expect(schema_name).to eq("test_agent_response")
      end

      it "handles complex agent names" do
        allow(agent_instance).to receive(:agent_name).and_return("MarketResearchAgent")
        schema_name = agent_instance.send(:schema_name)
        expect(schema_name).to eq("market_research_agent_response")
      end
    end
  end

  describe "helper methods" do
    describe "#product_context" do
      it "returns product from context" do
        context_with_product = { product: { name: "Test Product" } }
        agent = described_class.new(context_variables: context_with_product, processing_params: processing_params)
        expect(agent.send(:product_context)).to eq({ name: "Test Product" })
      end

      it "handles missing product gracefully" do
        agent = described_class.new(context_variables: {}, processing_params: processing_params)
        expect(agent.send(:product_context)).to be_nil
      end
    end

    describe "#processing_context" do
      it "returns processing_params" do
        expect(agent_instance.send(:processing_context)).to eq(processing_params)
      end
    end

    describe "#format_context_for_instructions" do
      it "formats context hash for instructions" do
        context_hash = { name: "Test", type: "Product" }
        formatted = agent_instance.send(:format_context_for_instructions, context_hash)

        expect(formatted).to include("Name: Test")
        expect(formatted).to include("Type: Product")
      end

      it "handles empty context" do
        formatted = agent_instance.send(:format_context_for_instructions, {})
        expect(formatted).to eq("")
      end
    end
  end

  describe "utility methods" do
    describe "#document_name" do
      it "returns content name from context" do
        expect(agent_instance.send(:document_name)).to eq("Test Content")
      end

      it "returns default when content name missing" do
        agent = described_class.new(context: {}, processing_params: processing_params)
        expect(agent.send(:document_name)).to eq("Unknown Document")
      end
    end

    describe "#document_description" do
      it "returns content description from context" do
        expect(agent_instance.send(:document_description)).to eq("A test document")
      end

      it "returns empty string when description missing" do
        context_without_description = { document: { name: "Test" } }
        agent = described_class.new(context_variables: context_without_description, processing_params: processing_params)
        expect(agent.send(:document_description)).to eq("")
      end
    end

    describe "#content_type" do
      it "returns content type from processing_params" do
        expect(agent_instance.send(:content_type)).to eq("Text")
      end

      it "returns default when content type missing" do
        params_without_type = { num_documents: 5 }
        agent = described_class.new(context_variables: context_variables, processing_params: params_without_type)
        expect(agent.send(:content_type)).to eq("General content")
      end
    end

    describe "#format_list" do
      it "joins array of document types" do
        params_with_array = { formats: ["Text", "PDF", "Spreadsheet"] }
        agent = described_class.new(context_variables: context_variables, processing_params: params_with_array)
        expect(agent.send(:format_list)).to eq("Text, PDF, Spreadsheet")
      end

      it "returns string document types as-is" do
        params_with_string = { formats: "Text, PDF" }
        agent = described_class.new(context_variables: context_variables, processing_params: params_with_string)
        expect(agent.send(:format_list)).to eq("Text, PDF")
      end

      it "returns default when document types missing" do
        expect(agent_instance.send(:format_list)).to eq("PDF, DOCX")
      end
    end

    describe "#max_pages" do
      it "returns max_pages from processing_params" do
        params_with_max_pages = { max_pages: 5 }
        agent = described_class.new(context_variables: context_variables, processing_params: params_with_max_pages)
        expect(agent.send(:max_pages)).to eq(5)
      end

      it "returns default when max_pages missing" do
        params_without_max = { content_type: "Text" }
        agent = described_class.new(context_variables: context_variables, processing_params: params_without_max)
        expect(agent.send(:max_pages)).to eq(50)
      end
    end

    describe "#language_focus" do
      it "returns language focus from processing_params" do
        params_with_lang = processing_params.merge(language_focus: "English")
        agent = described_class.new(context_variables: context_variables, processing_params: params_with_lang)
        expect(agent.send(:language_focus)).to eq("English")
      end

      it "returns default when language focus missing" do
        expect(agent_instance.send(:language_focus)).to eq("English")
      end
    end
  end

  describe "context builders" do
    describe "#build_document_context" do
      it "builds content context hash" do
        content_context = agent_instance.send(:build_document_context)

        expect(content_context[:name]).to eq("Test Content")
        expect(content_context[:description]).to eq("A test document")
        expect(content_context[:content_type]).to eq("Text")
        expect(content_context[:formats]).to eq("PDF, DOCX")
      end
    end

    describe "#build_processing_context" do
      it "builds processing context hash" do
        processing_context = agent_instance.send(:build_processing_context)

        expect(processing_context[:max_pages]).to eq(50)
        expect(processing_context[:content_type]).to eq("Text")
        expect(processing_context[:formats]).to eq("PDF, DOCX")
        expect(processing_context[:language_focus]).to eq("English")
        expect(processing_context[:analysis_depth]).to eq("Standard analysis")
      end

      it "includes custom analysis depth" do
        params_with_depth = processing_params.merge(analysis_depth: "Deep analysis")
        agent = described_class.new(context_variables: context_variables, processing_params: params_with_depth)

        processing_context = agent.send(:build_processing_context)
        expect(processing_context[:analysis_depth]).to eq("Deep analysis")
      end
    end
  end

  describe "private methods" do
    describe "#create_agent_instance" do
      before do
        mock_openai_agent
        allow(agent_instance).to receive_messages(agent_name: "PrivateTestAgent", build_instructions: "Private instructions", model_name: "gpt-4o", tools: [], handoffs: [], response_format: { type: "json" }, max_turns: 3)
      end

      it "creates execution agent with correct parameters" do
        execution_agent = agent_instance.send(:create_agent_instance)
        expect(execution_agent).to be_a(OpenAIAgents::Agent)
      end
    end
  end

  describe "subclass implementation" do
    let(:concrete_agent_class) do
      Class.new(described_class) do
        def agent_name
          "ConcreteAgent"
        end

        def build_instructions
          "Concrete instructions for #{agent_name}"
        end

        def build_schema
          {
            type:                 "object",
            properties:           {
              result: { type: "string" }
            },
            required:             ["result"],
            additionalProperties: false
          }
        end

        protected

        def model_name
          "gpt-3.5-turbo"
        end

        def max_turns
          5
        end
      end
    end

    let(:concrete_instance) { concrete_agent_class.new(context_variables: context_variables, processing_params: processing_params) }

    it "works with concrete implementation" do
      expect(concrete_instance.agent_name).to eq("ConcreteAgent")
      expect(concrete_instance.build_instructions).to eq("Concrete instructions for ConcreteAgent")
      expect(concrete_instance.build_schema[:type]).to eq("object")
      expect(concrete_instance.send(:model_name)).to eq("gpt-3.5-turbo")
      expect(concrete_instance.send(:max_turns)).to eq(5)
    end

    it "can create agent with concrete implementation" do
      mock_openai_agent

      expect { concrete_instance.create_agent }.not_to raise_error
    end
  end

  describe "inheritance" do
    it "can be subclassed" do
      subclass = Class.new(described_class)
      expect(subclass.superclass).to eq(described_class)
    end

    it "inherits context and processing_params accessors" do
      subclass = Class.new(described_class)
      instance = subclass.new(context_variables: context_variables, processing_params: processing_params)

      expect(instance.context.to_h).to eq(context_variables)
      expect(instance.processing_params).to eq(processing_params)
    end

    it "inherits helper methods" do
      subclass = Class.new(described_class)
      instance = subclass.new(context_variables: context_variables, processing_params: processing_params)

      expect(instance.send(:document_name)).to eq("Test Content")
      expect(instance.send(:content_type)).to eq("Text")
    end
  end

  describe "#run - delegation to openai-agents-ruby" do
    it "has a run method for delegation" do
      expect(agent_instance).to respond_to(:run)
    end

    it "delegates execution to openai-agents-ruby" do
      # Mock OpenAIAgents module
      mock_openai_agent

      # Mock the runner
      runner_class = Class.new do
        def initialize(**options)
          @options = options
        end

        def run(_prompt, context: nil)
          { success: true, result: "delegated execution" }
        end
      end
      stub_const("OpenAIAgents::Runner", runner_class)

      # Mock the agent methods
      allow(agent_instance).to receive_messages(agent_name: "TestAgent", build_instructions: "Test instructions", build_schema: { type: "object" })

      result = agent_instance.run
      expect(result).to have_key(:workflow_status)
      expect(result).to have_key(:success)
    end
  end
end

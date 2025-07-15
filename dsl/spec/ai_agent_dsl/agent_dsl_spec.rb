# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe AiAgentDsl::AgentDsl, :with_temp_files do
  let(:agent_instance) { test_agent_class.new(context: context, processing_params: processing_params) }
  let(:processing_params) { { content_type: "Text", num_documents: 5 } }
  let(:context) { { content: { name: "Test Content", document_type: "Text" } } }
  let(:test_agent_class) do
    create_test_agent_class("TestAgent") do
      agent_name "TestAgent"
      model "gpt-4o"
      max_turns 3
      description "A test agent for specs"
    end
  end

  it_behaves_like "a DSL module", described_class

  describe "class methods" do
    describe ".agent_name" do
      it "sets and returns agent name" do
        test_class = create_test_agent_class do
          agent_name "CustomAgent"
        end

        expect(test_class.agent_name).to eq("CustomAgent")
      end

      it "returns nil when not set" do
        test_class = create_test_agent_class
        expect(test_class.agent_name).to be_nil
      end
    end

    describe ".model" do
      context "when set directly" do
        it "sets and returns model name" do
          test_class = create_test_agent_class do
            model "gpt-3.5-turbo"
          end

          expect(test_class.model).to eq("gpt-3.5-turbo")
        end
      end

      context "when not set" do
        it "falls back to YAML config" do
          test_config = {
            "test" => {
              "global" => { "model" => "gpt-4o-mini" }
            }
          }

          with_config_file(test_config) do |config_path|
            AiAgentDsl.configure { |c| c.config_file = config_path }

            test_class = create_test_agent_class do
              agent_name "test_agent"
            end

            mock_rails_env("test")
            allow(Rails).to receive(:env).and_return("test") if defined?(Rails)
            expect(test_class.model).to eq("gpt-4o-mini")
          end
        end

        it "falls back to default when no config" do
          test_class = create_test_agent_class
          expect(test_class.model).to eq("gpt-4o")
        end
      end
    end

    describe ".max_turns" do
      context "when set directly" do
        it "sets and returns max turns" do
          test_class = create_test_agent_class do
            max_turns 5
          end

          expect(test_class.max_turns).to eq(5)
        end
      end

      context "when not set" do
        it "falls back to YAML config" do
          test_config = {
            "test" => {
              "global" => { "max_turns" => 2 }
            }
          }

          with_config_file(test_config) do |config_path|
            AiAgentDsl.configure { |c| c.config_file = config_path }

            test_class = create_test_agent_class do
              agent_name "test_agent"
            end

            mock_rails_env("test")
            allow(Rails).to receive(:env).and_return("test") if defined?(Rails)
            expect(test_class.max_turns).to eq(2)
          end
        end

        it "falls back to default when no config" do
          test_class = create_test_agent_class
          expect(test_class.max_turns).to eq(3)
        end
      end
    end

    describe ".description" do
      it "sets and returns description" do
        test_class = create_test_agent_class do
          description "A helpful agent"
        end

        expect(test_class.description).to eq("A helpful agent")
      end
    end

    describe ".uses_tool" do
      it "adds a tool to the configuration" do
        test_class = create_test_agent_class do
          uses_tool :web_search, max_results: 10
        end

        tools_config = test_class._tools_config
        expect(tools_config).to have(1).item
        expect(tools_config.first[:name]).to eq(:web_search)
        expect(tools_config.first[:options]).to eq(max_results: 10)
      end

      it "can add multiple tools" do
        test_class = create_test_agent_class do
          uses_tool :web_search
          uses_tool :database_query, timeout: 30
        end

        tools_config = test_class._tools_config
        expect(tools_config).to have(2).items
        expect(tools_config.map { |t| t[:name] }).to eq([:web_search, :database_query])
      end
    end

    describe ".uses_tools" do
      it "adds multiple tools at once" do
        test_class = create_test_agent_class do
          uses_tools :web_search, :database_query, :calculator
        end

        tools_config = test_class._tools_config
        expect(tools_config).to have(3).items
        expect(tools_config.map { |t| t[:name] }).to eq([:web_search, :database_query, :calculator])
      end
    end

    describe ".configure_tools" do
      it "configures multiple tools with options" do
        test_class = create_test_agent_class do
          configure_tools(
            web_search:     { max_results: 10 },
            database_query: { timeout: 30 }
          )
        end

        tools_config = test_class._tools_config
        expect(tools_config).to have(2).items

        web_search_tool = tools_config.find { |t| t[:name] == :web_search }
        expect(web_search_tool[:options]).to eq(max_results: 10)
      end
    end

    describe ".uses_tool_if" do
      it "adds tool when condition is true" do
        test_class = create_test_agent_class do
          uses_tool_if true, :web_search
        end

        expect(test_class._tools_config).to have(1).item
      end

      it "does not add tool when condition is false" do
        test_class = create_test_agent_class do
          uses_tool_if false, :web_search
        end

        expect(test_class._tools_config).to be_empty
      end
    end

    describe ".instruction_template" do
      it "sets and returns instruction template" do
        template = "You are {agent_name} working on {task}"
        test_class = create_test_agent_class do
          instruction_template template
        end

        expect(test_class.instruction_template).to eq(template)
      end
    end

    describe ".prompt_class" do
      it "sets and returns prompt class" do
        prompt_class = create_test_prompt_class("TestPrompt")

        test_class = create_test_agent_class do
          prompt_class prompt_class
        end

        expect(test_class.prompt_class).to eq(prompt_class)
      end
    end

    describe ".instruction_variables" do
      it "sets variables with block" do
        test_class = create_test_agent_class do
          instruction_variables do
            domain "AI Research"
            task_type "analysis"
          end
        end

        variables = test_class.instruction_variables
        expect(variables[:domain]).to eq("AI Research")
        expect(variables[:task_type]).to eq("analysis")
      end

      it "supports lambda variables" do
        test_class = create_test_agent_class do
          instruction_variables do
            dynamic_value { Time.current.to_s }
          end
        end

        variables = test_class.instruction_variables
        expect(variables[:dynamic_value]).to be_a(Proc)
      end
    end

    describe ".static_instructions" do
      it "sets and returns static instructions" do
        instructions = "Static instruction text"
        test_class = create_test_agent_class do
          static_instructions instructions
        end

        expect(test_class.static_instructions).to eq(instructions)
      end
    end

    describe ".schema" do
      it "defines response schema with block" do
        test_class = create_test_agent_class do
          schema do
            field :name, type: :string, required: true
            field :score, type: :integer, range: 0..100
          end
        end

        schema = test_class.schema
        expect(schema[:type]).to eq("object")
        expect(schema[:properties]).to have_key(:name)
        expect(schema[:properties]).to have_key(:score)
        expect(schema[:required]).to include(:name)
      end

      it "supports nested objects" do
        test_class = create_test_agent_class do
          schema do
            field :user, type: :object, required: true do
              field :name, type: :string, required: true
              field :email, type: :string
            end
          end
        end

        schema = test_class.schema
        user_field = schema[:properties][:user]
        expect(user_field[:type]).to eq("object")
        expect(user_field[:properties]).to have_key(:name)
        expect(user_field[:required]).to include(:name)
      end

      it "supports arrays" do
        test_class = create_test_agent_class do
          schema do
            field :items, type: :array, required: true do
              field :id, type: :integer, required: true
              field :value, type: :string
            end
          end
        end

        schema = test_class.schema
        items_field = schema[:properties][:items]
        expect(items_field[:type]).to eq("array")
        expect(items_field[:items][:type]).to eq("object")
      end
    end

    describe ".hands_off_to" do
      it "sets handoff agents" do
        agent_class = create_test_agent_class("HandoffAgent")

        test_class = create_test_agent_class do
          hands_off_to agent_class
        end

        expect(test_class._agent_config[:handoff_agents]).to eq([agent_class])
      end
    end

    describe ".handoff_to" do
      it "adds single handoff agent" do
        agent_class = create_test_agent_class("HandoffAgent")

        test_class = create_test_agent_class do
          handoff_to agent_class, priority: "high"
        end

        handoffs = test_class._agent_config[:handoff_agents]
        expect(handoffs).to have(1).item
        expect(handoffs.first[:agent]).to eq(agent_class)
        expect(handoffs.first[:options]).to eq(priority: "high")
      end
    end

    describe ".configure_handoffs" do
      it "configures multiple handoffs" do
        agent1 = create_test_agent_class("Agent1")
        agent2 = create_test_agent_class("Agent2")

        test_class = create_test_agent_class do
          configure_handoffs(
            agent1 => { priority: "high" },
            agent2 => { priority: "low" }
          )
        end

        handoffs = test_class._agent_config[:handoff_agents]
        expect(handoffs).to have(2).items
      end
    end

    describe ".handoff_to_if" do
      it "adds handoff when condition is true" do
        agent_class = create_test_agent_class("ConditionalAgent")

        test_class = create_test_agent_class do
          handoff_to_if true, agent_class
        end

        expect(test_class._agent_config[:handoff_agents]).to have(1).item
      end

      it "does not add handoff when condition is false" do
        agent_class = create_test_agent_class("ConditionalAgent")

        test_class = create_test_agent_class do
          handoff_to_if false, agent_class
        end

        expect(test_class._agent_config[:handoff_agents]).to be_nil
      end
    end

    describe ".handoff_sequence" do
      it "sets handoff sequence" do
        agent1 = create_test_agent_class("Agent1")
        agent2 = create_test_agent_class("Agent2")

        test_class = create_test_agent_class do
          handoff_sequence agent1, agent2
        end

        expect(test_class._agent_config[:handoff_sequence]).to eq([agent1, agent2])
        expect(test_class._agent_config[:handoff_agents]).to eq([agent1, agent2])
      end
    end

    describe ".workflow" do
      it "defines workflow with block" do
        agent1 = create_test_agent_class("WorkflowAgent1")
        agent2 = create_test_agent_class("WorkflowAgent2")

        test_class = create_test_agent_class do
          workflow do
            step agent1
            then_step agent2
          end
        end

        expect(test_class._agent_config[:handoff_sequence]).to eq([agent1, agent2])
      end
    end

    describe "workflow aliases" do
      ["orchestrates", "discovery_workflow", "coordinates"].each do |method|
        it "supports #{method} as alias for workflow" do
          test_class = create_test_agent_class
          expect(test_class).to respond_to(method.to_sym)
        end
      end
    end

    describe ".inferred_agent_name" do
      it "converts class name to underscore format" do
        test_class = create_test_agent_class("ContentAnalysisAgent")
        expect(test_class.inferred_agent_name).to eq("content_analysis_agent")
      end

      it "handles namespaced class names" do
        test_class = create_test_agent_class("Content::ProcessingAgent")
        expect(test_class.inferred_agent_name).to eq("content_processing_agent")
      end

      it "removes AiAgentDsl::Agents namespace" do
        test_class = Class.new(AiAgentDsl::Agents::Base) do
          include AiAgentDsl::AgentDsl
        end
        stub_const("AiAgentDsl::Agents::TestAgent", test_class)

        expect(test_class.inferred_agent_name).to eq("test_agent")
      end
    end
  end

  describe "instance methods" do
    describe "#agent_name" do
      it "returns class agent name" do
        expect(agent_instance.agent_name).to eq("TestAgent")
      end

      it "falls back to class name" do
        test_class = create_test_agent_class("FallbackAgent")
        instance = test_class.new(context: context, processing_params: processing_params)

        expect(instance.agent_name).to eq("FallbackAgent")
      end
    end

    describe "#model_name" do
      it "returns class model" do
        expect(agent_instance.model_name).to eq("gpt-4o")
      end
    end

    describe "#max_turns" do
      it "returns class max_turns" do
        expect(agent_instance.max_turns).to eq(3)
      end
    end

    describe "#tools" do
      let(:web_search_tool_class) do
        create_test_tool_class("WebSearchTool") do
          tool_name "web_search"

          def tool_definition
            {
              type:        "function",
              name:        tool_name,
              description: "Search the web"
            }
          end
        end
      end

      before do
        # Mock tool resolution
        allow(agent_instance).to receive(:resolve_tool_class).with(:web_search).and_return(web_search_tool_class)
      end

      it "builds tools from configuration" do
        test_class = create_test_agent_class do
          uses_tool :web_search, max_results: 10
        end

        instance = test_class.new(context: context, processing_params: processing_params)
        allow(instance).to receive(:resolve_tool_class).with(:web_search).and_return(web_search_tool_class)

        tools = instance.tools
        expect(tools).to have(1).item
        expect(tools.first).to be_a(web_search_tool_class)
      end

      it "caches tools" do
        test_class = create_test_agent_class do
          uses_tool :web_search
        end

        instance = test_class.new(context: context, processing_params: processing_params)
        allow(instance).to receive(:resolve_tool_class).with(:web_search).and_return(web_search_tool_class)

        tools1 = instance.tools
        tools2 = instance.tools
        expect(tools1).to be(tools2)
      end
    end

    describe "#build_instructions" do
      context "with prompt class" do
        let(:prompt_class) do
          create_test_prompt_class("TestPrompt") do
            def system
              "System prompt from prompt class"
            end

            def render(type)
              case type
              when :system
                system
              else
                "Unknown prompt type"
              end
            end
          end
        end

        it "uses prompt class for instructions" do
          test_class = create_test_agent_class do
            prompt_class prompt_class
          end

          instance = test_class.new(context: context, processing_params: processing_params)

          # Mock the prompt_class_configured? and prompt_instance methods
          prompt_instance = prompt_class.new
          allow(instance).to receive_messages(prompt_class_configured?: true, prompt_instance: prompt_instance)

          instructions = instance.build_instructions
          expect(instructions).to eq("System prompt from prompt class")
        end
      end

      context "with instruction template" do
        it "builds templated instructions" do
          test_class = create_test_agent_class do
            agent_name "TemplateAgent"
            instruction_template "You are {agent_name} working with {content_name}"
            instruction_variables do
              content_name { context.dig(:content, :name) }
            end
          end

          instance = test_class.new(context: context, processing_params: processing_params)
          instructions = instance.build_instructions

          expect(instructions).to include("You are TemplateAgent")
          expect(instructions).to include("working with Test Content")
        end

        it "evaluates lambda variables" do
          test_class = create_test_agent_class do
            instruction_template "Current time: {current_time}"
            instruction_variables do
              current_time { Time.current.to_s }
            end
          end

          instance = test_class.new(context: context, processing_params: processing_params)
          instructions = instance.build_instructions

          expect(instructions).to match(/Current time: \d{4}-\d{2}-\d{2}/)
        end
      end

      context "with static instructions" do
        it "returns static instructions" do
          test_class = create_test_agent_class do
            static_instructions "Static instruction text"
          end

          instance = test_class.new(context: context, processing_params: processing_params)
          instructions = instance.build_instructions

          expect(instructions).to eq("Static instruction text")
        end
      end

      context "with no instructions configured" do
        it "returns default instructions" do
          test_class = create_test_agent_class do
            agent_name "DefaultAgent"
          end

          instance = test_class.new(context: context, processing_params: processing_params)
          instructions = instance.build_instructions

          expect(instructions).to eq("You are DefaultAgent. Respond with helpful and accurate information.")
        end
      end
    end

    describe "#build_user_prompt" do
      context "with prompt class" do
        let(:prompt_class) do
          create_test_prompt_class("TestPrompt") do
            def user
              "User prompt from prompt class"
            end

            def render(type)
              case type
              when :user
                user
              else
                "Unknown prompt type"
              end
            end
          end
        end

        it "uses prompt class for user prompt" do
          test_class = create_test_agent_class do
            prompt_class prompt_class
          end

          instance = test_class.new(context: context, processing_params: processing_params)

          # Mock the prompt_class_configured? and prompt_instance methods
          prompt_instance = prompt_class.new
          allow(instance).to receive_messages(prompt_class_configured?: true, prompt_instance: prompt_instance)

          user_prompt = instance.build_user_prompt
          expect(user_prompt).to eq("User prompt from prompt class")
        end
      end

      context "without prompt class" do
        it "raises an error" do
          test_class = create_test_agent_class
          instance = test_class.new(context: context, processing_params: processing_params)

          expect { instance.build_user_prompt }.to raise_error(AiAgentDsl::Error, /No prompt class configured/)
        end
      end
    end

    describe "#prompt_class_configured?" do
      it "returns true when prompt class is set" do
        prompt_class = create_test_prompt_class("ConfiguredPrompt")
        test_class = create_test_agent_class do
          prompt_class prompt_class
        end

        instance = test_class.new(context: context, processing_params: processing_params)
        expect(instance.prompt_class_configured?).to be true
      end

      it "returns true when inferred prompt class exists" do
        # Create a matching prompt class
        inferred_prompt_class = create_test_prompt_class("AiAgentDsl::Prompts::TestAgent")

        instance = agent_instance
        allow(instance).to receive(:default_prompt_class).and_return(inferred_prompt_class)

        expect(instance.prompt_class_configured?).to be true
      end

      it "returns false when no prompt class" do
        test_class = create_test_agent_class
        instance = test_class.new(context: context, processing_params: processing_params)

        expect(instance.prompt_class_configured?).to be false
      end
    end

    describe "#default_prompt_class" do
      it "infers prompt class from agent class name" do
        # Create an agent class that matches the expected pattern
        agent_class = Class.new(AiAgentDsl::Agents::Base) do
          include AiAgentDsl::AgentDsl
        end
        stub_const("AiAgentDsl::Agents::TestAgent", agent_class)

        # Create the expected prompt class
        prompt_class = create_test_prompt_class("AiAgentDsl::Prompts::TestAgent")

        # Create instance of the properly namespaced agent
        instance = agent_class.new(context: context, processing_params: processing_params)

        # The method should now find the prompt class
        inferred = instance.send(:default_prompt_class)
        expect(inferred).to eq(prompt_class)
      end
    end

    describe "#build_schema" do
      it "returns configured schema" do
        test_class = create_test_agent_class do
          schema do
            field :result, type: :string, required: true
          end
        end

        instance = test_class.new(context: context, processing_params: processing_params)
        schema = instance.build_schema

        expect(schema[:type]).to eq("object")
        expect(schema[:properties]).to have_key(:result)
        expect(schema[:additionalProperties]).to be false
      end

      it "returns basic schema when none configured" do
        test_class = create_test_agent_class
        instance = test_class.new(context: context, processing_params: processing_params)
        schema = instance.build_schema

        expect(schema[:type]).to eq("object")
        expect(schema[:properties]).to eq({})
        expect(schema[:additionalProperties]).to be false
      end
    end

    describe "#handoffs" do
      it "builds handoffs from configuration" do
        handoff_agent_class = create_test_agent_class("HandoffAgent") do
          def create_agent
            self
          end
        end

        test_class = create_test_agent_class do
          handoff_to handoff_agent_class
        end

        instance = test_class.new(context: context, processing_params: processing_params)
        handoffs = instance.handoffs

        expect(handoffs).to have(1).item
        expect(handoffs.first).to be_a(handoff_agent_class)
      end

      it "passes context and processing_params to handoff agents" do
        handoff_agent_class = create_test_agent_class("HandoffAgent") do
          def create_agent
            self
          end
        end

        test_class = create_test_agent_class do
          handoff_to handoff_agent_class
        end

        instance = test_class.new(context: context, processing_params: processing_params)
        handoffs = instance.handoffs

        handoff_agent = handoffs.first
        expect(handoff_agent.context).to eq(context)
        expect(handoff_agent.processing_params).to eq(processing_params)
      end
    end
  end

  describe "helper classes" do
    describe "InstructionVariables" do
      let(:variables_builder) { AiAgentDsl::InstructionVariables.new }

      it "captures method calls as variables" do
        variables_builder.instance_eval do
          domain "AI Research"
          task_type "analysis"
        end

        expect(variables_builder.variables[:domain]).to eq("AI Research")
        expect(variables_builder.variables[:task_type]).to eq("analysis")
      end

      it "captures blocks as lambda variables" do
        variables_builder.instance_eval do
          dynamic_value { "computed value" }
        end

        lambda_var = variables_builder.variables[:dynamic_value]
        expect(lambda_var).to be_a(Proc)
        expect(lambda_var.call).to eq("computed value")
      end

      it "responds to any method name" do
        expect(variables_builder.respond_to?(:any_method)).to be true
      end
    end

    describe "SchemaBuilder" do
      let(:schema_builder) { AiAgentDsl::SchemaBuilder.new }

      it "builds basic field schema" do
        schema_builder.field :name, type: :string, required: true

        schema = schema_builder.to_hash
        expect(schema[:properties][:name][:type]).to eq("string")
        expect(schema[:required]).to include(:name)
      end

      it "supports field constraints" do
        schema_builder.field :score, type: :integer, range: 0..100, description: "Score value"

        schema = schema_builder.to_hash
        score_field = schema[:properties][:score]
        expect(score_field[:minimum]).to eq(0)
        expect(score_field[:maximum]).to eq(100)
        expect(score_field[:description]).to eq("Score value")
      end

      it "supports nested objects" do
        schema_builder.field :user, type: :object do
          field :name, type: :string, required: true
          field :age, type: :integer, min: 0
        end

        schema = schema_builder.to_hash
        user_field = schema[:properties][:user]
        expect(user_field[:type]).to eq("object")
        expect(user_field[:properties][:name][:type]).to eq("string")
        expect(user_field[:required]).to include(:name)
      end

      it "supports arrays" do
        schema_builder.field :tags, type: :array, items_type: :string, min_items: 1

        schema = schema_builder.to_hash
        tags_field = schema[:properties][:tags]
        expect(tags_field[:type]).to eq("array")
        expect(tags_field[:items][:type]).to eq("string")
        expect(tags_field[:minItems]).to eq(1)
      end

      it "supports arrays of objects" do
        schema_builder.field :items, type: :array do
          field :id, type: :integer, required: true
          field :value, type: :string
        end

        schema = schema_builder.to_hash
        items_field = schema[:properties][:items]
        expect(items_field[:type]).to eq("array")
        expect(items_field[:items][:type]).to eq("object")
        expect(items_field[:items][:properties][:id][:type]).to eq("integer")
      end

      it "ensures additionalProperties is false for strict mode" do
        schema_builder.field :data, type: :object do
          field :value, type: :string
        end

        schema = schema_builder.to_hash
        expect(schema[:additionalProperties]).to be false
        expect(schema[:properties][:data][:additionalProperties]).to be false
      end
    end

    describe "WorkflowBuilder" do
      let(:workflow_builder) { AiAgentDsl::WorkflowBuilder.new }
      let(:agent1) { create_test_agent_class("Agent1") }
      let(:agent2) { create_test_agent_class("Agent2") }

      it "supports workflow step methods" do
        workflow_builder.analyze_content(agent1)
        workflow_builder.process_documents(agent2)

        expect(workflow_builder.agents).to eq([agent1, agent2])
      end

      it "supports workflow aliases" do
        workflow_builder.start_with_content_analysis(agent1)
        workflow_builder.then_process_documents(agent2)

        expect(workflow_builder.agents).to eq([agent1, agent2])
      end

      it "supports generic step method" do
        workflow_builder.step(agent1, "First step")
        workflow_builder.then_step(agent2, "Second step")

        expect(workflow_builder.agents).to eq([agent1, agent2])
      end

      it "supports conditional steps" do
        workflow_builder.step_if(true, agent1)
        workflow_builder.step_if(false, agent2)

        expect(workflow_builder.agents).to eq([agent1])
      end

      it "supports direct agent specification" do
        workflow_builder.agent(agent1)
        workflow_builder.then_agent(agent2)

        expect(workflow_builder.agents).to eq([agent1, agent2])
      end
    end
  end

  describe "integration" do
    it "works with real agent subclass" do
      agent_class = Class.new(AiAgentDsl::Agents::Base) do
        include AiAgentDsl::AgentDsl

        agent_name "IntegrationTestAgent"
        model "gpt-4o"
        max_turns 3

        uses_tool :web_search, max_results: 10

        schema do
          field :result, type: :string, required: true
          field :confidence, type: :integer, range: 0..100
        end

        def agent_name
          self.class.agent_name
        end

        def build_instructions
          "You are #{agent_name}. Provide helpful responses."
        end

        def build_schema
          self.class.schema
        end
      end

      instance = agent_class.new(context: context, processing_params: processing_params)

      expect(instance.agent_name).to eq("IntegrationTestAgent")
      expect(instance.model_name).to eq("gpt-4o")
      expect(instance.max_turns).to eq(3)
      expect(instance.build_instructions).to include("IntegrationTestAgent")

      schema = instance.build_schema
      expect(schema[:properties]).to have_key(:result)
      expect(schema[:properties]).to have_key(:confidence)
    end
  end
end

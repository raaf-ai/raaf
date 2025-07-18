# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Prompt Schema Support", type: :integration do
  # Test prompt class with simple schema
  class TestPromptWithSchema < RAAF::DSL::Prompts::Base # rubocop:disable Lint/ConstantDefinitionInBlock

    required :user_name
    optional :user_age

    schema do
      field :name, type: :string, required: true
      field :age, type: :integer, range: 0..150
      field :confidence, type: :integer, range: 0..100, required: true
    end

    def system
      "Extract user information"
    end

    def user
      "Extract name and age from: #{user_name}, age #{user_age || "unknown"}"
    end

  end

  # Test prompt class with complex nested schema
  class TestComplexSchemaPrompt < RAAF::DSL::Prompts::Base # rubocop:disable Lint/ConstantDefinitionInBlock

    required :analysis_target

    schema do
      field :results, type: :array, required: true do
        field :name, type: :string, required: true
        field :score, type: :integer, range: 0..100, required: true
        field :details, type: :object do
          field :category, type: :string, enum: %w[high medium low]
          field :notes, type: :array, items_type: :string
        end
      end
      field :summary, type: :string, required: true
    end

    def system
      "Analyze the target"
    end

    def user
      "Analyze: #{analysis_target}"
    end

  end

  # Test prompt class without schema
  class TestPromptWithoutSchema < RAAF::DSL::Prompts::Base # rubocop:disable Lint/ConstantDefinitionInBlock

    required :content

    def system
      "Process content"
    end

    def user
      "Process: #{content}"
    end

  end

  # Test agent using prompt with schema
  class TestAgentWithPromptSchema < RAAF::DSL::Agents::Base # rubocop:disable Lint/ConstantDefinitionInBlock

    include RAAF::DSL::AgentDsl

    agent_name "TestAgent"
    prompt_class TestPromptWithSchema

    def initialize(context: {}, processing_params: {})
      super
    end

  end

  # Test agent with conflicting schema
  class TestAgentWithConflictingSchema < RAAF::DSL::Agents::Base # rubocop:disable Lint/ConstantDefinitionInBlock

    include RAAF::DSL::AgentDsl

    agent_name "ConflictingAgent"
    prompt_class TestPromptWithSchema

    schema do
      field :different_field, type: :string
    end

    def initialize(context: {}, processing_params: {})
      super
    end

  end

  describe "schema definition in prompt classes" do
    it "allows defining schema using the DSL" do
      expect(TestPromptWithSchema.has_schema?).to be true
      schema = TestPromptWithSchema.get_schema

      expect(schema[:type]).to eq("object")
      expect(schema[:properties]).to have_key(:name)
      expect(schema[:properties]).to have_key(:age)
      expect(schema[:properties]).to have_key(:confidence)
      expect(schema[:required]).to include("name", "confidence")
      expect(schema[:additionalProperties]).to be false
    end

    it "supports complex nested schemas" do
      expect(TestComplexSchemaPrompt.has_schema?).to be true
      schema = TestComplexSchemaPrompt.get_schema

      # Check top-level structure
      expect(schema[:properties]).to have_key(:results)
      expect(schema[:properties]).to have_key(:summary)

      # Check array structure
      results_schema = schema[:properties][:results]
      expect(results_schema[:type]).to eq("array")
      expect(results_schema[:items][:properties]).to have_key(:name)
      expect(results_schema[:items][:properties]).to have_key(:score)
      expect(results_schema[:items][:properties]).to have_key(:details)

      # Check nested object structure
      details_schema = results_schema[:items][:properties][:details]
      expect(details_schema[:properties]).to have_key(:category)
      expect(details_schema[:properties]).to have_key(:notes)
    end

    it "returns empty hash when no schema is defined" do
      expect(TestPromptWithoutSchema.has_schema?).to be false
      expect(TestPromptWithoutSchema.get_schema).to eq({})
    end
  end

  describe "prompt instance schema access" do
    let(:prompt) { TestPromptWithSchema.new(user_name: "John", user_age: 30) }

    it "provides access to schema through instance methods" do
      expect(prompt.has_schema?).to be true
      expect(prompt.schema).to eq(TestPromptWithSchema.get_schema)
    end

    it "allows accessing schema properties" do
      schema = prompt.schema
      expect(schema[:properties][:name][:type]).to eq("string")
      expect(schema[:properties][:age][:minimum]).to eq(0)
      expect(schema[:properties][:age][:maximum]).to eq(150)
      expect(schema[:properties][:confidence][:minimum]).to eq(0)
      expect(schema[:properties][:confidence][:maximum]).to eq(100)
    end
  end

  describe "agent integration with prompt schemas" do
    it "uses prompt schema when agent has no schema" do
      agent = TestAgentWithPromptSchema.new(
        context: { user_name: "John", user_age: 30 }
      )

      schema = agent.build_schema
      expect(schema[:properties]).to have_key(:name)
      expect(schema[:properties]).to have_key(:age)
      expect(schema[:properties]).to have_key(:confidence)
    end

    it "raises error when both agent and prompt define schemas" do
      agent = TestAgentWithConflictingSchema.new(
        context: { user_name: "John" }
      )

      expect do
        agent.build_schema
      end.to raise_error(ArgumentError, /Schema conflict/)
    end

    it "includes helpful error message for schema conflicts" do
      agent = TestAgentWithConflictingSchema.new(
        context: { user_name: "John" }
      )

      expect do
        agent.build_schema
      end.to raise_error(ArgumentError) do |error|
        expect(error.message).to include("TestAgentWithConflictingSchema")
        expect(error.message).to include("TestPromptWithSchema")
        expect(error.message).to include("Only one schema definition is allowed")
      end
    end
  end

  describe "schema inheritance and isolation" do
    class ParentPrompt < RAAF::DSL::Prompts::Base # rubocop:disable Lint/ConstantDefinitionInBlock

      schema do
        field :parent_field, type: :string
      end

    end

    class ChildPrompt < ParentPrompt # rubocop:disable Lint/ConstantDefinitionInBlock

      schema do
        field :child_field, type: :integer
      end

    end

    it "isolates schema configurations between classes" do
      parent_schema = ParentPrompt.get_schema
      child_schema = ChildPrompt.get_schema

      expect(parent_schema[:properties]).to have_key(:parent_field)
      expect(parent_schema[:properties]).not_to have_key(:child_field)

      expect(child_schema[:properties]).to have_key(:child_field)
      expect(child_schema[:properties]).not_to have_key(:parent_field)
    end
  end

  describe "OpenAI strict mode compliance" do
    it "ensures additionalProperties is false for root schema" do
      schema = TestPromptWithSchema.get_schema
      expect(schema[:additionalProperties]).to be false
    end

    it "ensures additionalProperties is false for nested objects" do
      schema = TestComplexSchemaPrompt.get_schema
      results_items = schema[:properties][:results][:items]
      details_schema = results_items[:properties][:details]

      expect(results_items[:additionalProperties]).to be false
      expect(details_schema[:additionalProperties]).to be false
    end
  end

  describe "schema validation features" do
    it "supports range validation for integers" do
      schema = TestPromptWithSchema.get_schema
      age_field = schema[:properties][:age]
      confidence_field = schema[:properties][:confidence]

      expect(age_field[:minimum]).to eq(0)
      expect(age_field[:maximum]).to eq(150)
      expect(confidence_field[:minimum]).to eq(0)
      expect(confidence_field[:maximum]).to eq(100)
    end

    it "supports enum validation for strings" do
      schema = TestComplexSchemaPrompt.get_schema
      category_field = schema[:properties][:results][:items][:properties][:details][:properties][:category]

      expect(category_field[:enum]).to eq(%w[high medium low])
    end

    it "supports array items type specification" do
      schema = TestComplexSchemaPrompt.get_schema
      notes_field = schema[:properties][:results][:items][:properties][:details][:properties][:notes]

      expect(notes_field[:type]).to eq("array")
      expect(notes_field[:items][:type]).to eq("string")
    end
  end
end

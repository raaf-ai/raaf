# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::SchemaBuilder do
  # Mock Market model for testing
  let(:market_model) do
    double("Market").tap do |model|
      allow(model).to receive(:name).and_return("Market")
      allow(model).to receive(:columns).and_return([
        double("Column", name: "id", type: :integer, null: false, limit: nil),
        double("Column", name: "market_name", type: :string, null: false, limit: 255),
        double("Column", name: "overall_score", type: :integer, null: true, limit: nil),
        double("Column", name: "market_description", type: :text, null: true, limit: nil),
        double("Column", name: "created_at", type: :datetime, null: false, limit: nil)
      ])
      allow(model).to receive(:reflect_on_all_associations).and_return([])
      allow(model).to receive(:validators).and_return([])
    end
  end

  before do
    # Mock the schema cache to return a basic schema
    allow(RAAF::DSL::SchemaCache).to receive(:get_schema).with(market_model).and_return({
      properties: {
        id: { type: :integer },
        market_name: { type: :string, maxLength: 255 },
        overall_score: { type: :integer },
        market_description: { type: :string },
        created_at: { type: :string, format: :datetime }
      },
      required: [:id, :market_name, :created_at]
    })
  end

  describe "#initialize" do
    context "without model" do
      it "initializes with empty properties and required fields" do
        builder = described_class.new

        expect(builder.instance_variable_get(:@properties)).to eq({})
        expect(builder.instance_variable_get(:@required)).to eq([])
        expect(builder.instance_variable_get(:@model)).to be_nil
      end
    end

    context "with model" do
      it "initializes with model-generated schema" do
        builder = described_class.new(model: market_model)

        properties = builder.instance_variable_get(:@properties)
        required = builder.instance_variable_get(:@required)

        expect(properties[:market_name]).to eq({ type: :string, maxLength: 255 })
        expect(properties[:overall_score]).to eq({ type: :integer })
        expect(required).to include(:id, :market_name, :created_at)
      end
    end
  end

  describe "fluent interface" do
    let(:builder) { described_class.new }

    describe "#field" do
      it "adds a field with default string type" do
        result = builder.field(:description)

        expect(builder.instance_variable_get(:@properties)[:description]).to eq({ type: :string })
        expect(result).to eq(builder) # Returns self for chaining
      end

      it "adds a field with semantic type" do
        builder.field(:email, :email)

        properties = builder.instance_variable_get(:@properties)
        expect(properties[:email][:type]).to eq(:string)
        expect(properties[:email][:format]).to eq(:email)
        expect(properties[:email][:pattern]).to be_a(Regexp)
      end

      it "adds a field with custom options" do
        builder.field(:score, :integer, minimum: 0, maximum: 100)

        properties = builder.instance_variable_get(:@properties)
        expect(properties[:score]).to include(
          type: :integer,
          minimum: 0,
          maximum: 100
        )
      end

      it "supports method chaining" do
        result = builder
          .field(:name, :string)
          .field(:email, :email)
          .field(:score, :score)

        expect(result).to eq(builder)
        expect(builder.instance_variable_get(:@properties).keys).to include(:name, :email, :score)
      end
    end

    describe "#required" do
      it "adds required fields" do
        builder.required(:name, :email)

        required = builder.instance_variable_get(:@required)
        expect(required).to include(:name, :email)
      end

      it "supports method chaining" do
        result = builder.required(:name, :email)

        expect(result).to eq(builder)
      end

      it "handles duplicate required fields" do
        builder.required(:name).required(:name, :email)

        required = builder.instance_variable_get(:@required)
        expect(required.count(:name)).to eq(1)
        expect(required).to include(:email)
      end
    end

    describe "#array_of" do
      it "creates array field with item type" do
        builder.array_of(:tags, :string)

        properties = builder.instance_variable_get(:@properties)
        expect(properties[:tags]).to eq({
          type: :array,
          items: { type: :string }
        })
      end

      it "creates array field with semantic item type" do
        builder.array_of(:emails, :email)

        properties = builder.instance_variable_get(:@properties)
        expect(properties[:emails]).to eq({
          type: :array,
          items: {
            type: :string,
            format: :email,
            pattern: RAAF::DSL::Types::SEMANTIC_TYPES[:email][:pattern]
          }
        })
      end

      it "supports custom options for items" do
        builder.array_of(:scores, :integer, minimum: 0, maximum: 100)

        properties = builder.instance_variable_get(:@properties)
        expect(properties[:scores][:items]).to include(
          type: :integer,
          minimum: 0,
          maximum: 100
        )
      end

      it "supports method chaining" do
        result = builder.array_of(:tags, :string)

        expect(result).to eq(builder)
      end
    end

    describe "#nested" do
      it "creates nested object with block" do
        builder.nested(:address) do
          field :street, :string
          field :city, :string
          required :street, :city
        end

        properties = builder.instance_variable_get(:@properties)
        address_schema = properties[:address]

        expect(address_schema[:type]).to eq(:object)
        expect(address_schema[:properties][:street]).to eq({ type: :string })
        expect(address_schema[:properties][:city]).to eq({ type: :string })
        expect(address_schema[:required]).to include(:street, :city)
      end

      it "supports method chaining" do
        result = builder.nested(:address) do
          field :street, :string
        end

        expect(result).to eq(builder)
      end

      it "supports nested nesting" do
        builder.nested(:contact) do
          field :name, :string
          nested :address do
            field :street, :string
            field :city, :string
          end
        end

        properties = builder.instance_variable_get(:@properties)
        contact_schema = properties[:contact]

        expect(contact_schema[:properties][:address][:type]).to eq(:object)
        expect(contact_schema[:properties][:address][:properties][:street]).to eq({ type: :string })
      end
    end

    describe "#override" do
      it "overrides existing field properties" do
        builder = described_class.new(model: market_model)
        builder.override(:overall_score, type: :score)

        properties = builder.instance_variable_get(:@properties)
        expect(properties[:overall_score][:type]).to eq(:integer)
        expect(properties[:overall_score][:minimum]).to eq(0)
        expect(properties[:overall_score][:maximum]).to eq(100)
      end

      it "merges with existing properties" do
        builder = described_class.new(model: market_model)
        builder.override(:market_name, required: true, description: "Market name")

        properties = builder.instance_variable_get(:@properties)
        expect(properties[:market_name]).to include(
          type: :string,
          maxLength: 255,
          required: true,
          description: "Market name"
        )
      end

      it "handles non-existent fields gracefully" do
        builder.override(:non_existent, type: :string)

        properties = builder.instance_variable_get(:@properties)
        expect(properties[:non_existent]).to be_nil
      end

      it "supports method chaining" do
        builder = described_class.new(model: market_model)
        result = builder.override(:overall_score, type: :score)

        expect(result).to eq(builder)
      end
    end
  end

  describe "#to_schema" do
    context "without model" do
      it "generates basic schema structure" do
        builder = described_class.new
          .field(:name, :string)
          .field(:email, :email)
          .required(:name, :email)

        schema = builder.to_schema

        expect(schema).to eq({
          type: :object,
          properties: {
            name: { type: :string },
            email: {
              type: :string,
              format: :email,
              pattern: RAAF::DSL::Types::SEMANTIC_TYPES[:email][:pattern]
            }
          },
          required: [:name, :email]
        })
      end
    end

    context "with model" do
      it "generates schema combining model and custom fields" do
        builder = described_class.new(model: market_model)
          .field(:insights, :text)
          .override(:overall_score, type: :score)
          .required(:insights)

        schema = builder.to_schema

        expect(schema[:type]).to eq(:object)
        expect(schema[:properties][:market_name]).to eq({ type: :string, maxLength: 255 })
        expect(schema[:properties][:insights]).to eq({ type: :string })
        expect(schema[:properties][:overall_score]).to include(type: :integer, minimum: 0, maximum: 100)
        expect(schema[:required]).to include(:id, :market_name, :created_at, :insights)
      end

      it "removes duplicate required fields" do
        builder = described_class.new(model: market_model)
          .required(:market_name) # Already required from model

        schema = builder.to_schema
        required_count = schema[:required].count(:market_name)
        expect(required_count).to eq(1)
      end
    end

    context "with complex nested structures" do
      it "generates nested schema correctly" do
        builder = described_class.new
          .field(:id, :integer)
          .nested(:contact) do
            field :name, :string
            field :email, :email
            array_of :phones, :phone
            required :name, :email
          end
          .array_of(:tags, :string)
          .required(:id)

        schema = builder.to_schema

        expect(schema[:properties][:contact][:type]).to eq(:object)
        expect(schema[:properties][:contact][:properties][:email][:format]).to eq(:email)
        expect(schema[:properties][:contact][:properties][:phones][:type]).to eq(:array)
        expect(schema[:properties][:contact][:properties][:phones][:items][:pattern]).to be_a(Regexp)
        expect(schema[:properties][:contact][:required]).to include(:name, :email)
        expect(schema[:properties][:tags][:type]).to eq(:array)
        expect(schema[:properties][:tags][:items][:type]).to eq(:string)
      end
    end
  end

  describe "usage patterns" do
    context "model override pattern" do
      it "demonstrates the primary use case" do
        # This is the main pattern we want to enable
        builder = described_class.new(model: market_model)
          .override(:overall_score, type: :score)  # Use semantic type
          .field(:insights, :text)                 # Add agent-specific field

        schema = builder.to_schema

        # Verify model fields are included
        expect(schema[:properties][:market_name]).to be_present
        expect(schema[:properties][:created_at]).to be_present

        # Verify override worked
        expect(schema[:properties][:overall_score]).to include(minimum: 0, maximum: 100)

        # Verify new field added
        expect(schema[:properties][:insights]).to eq({ type: :string })
      end
    end

    context "concise field definition pattern" do
      it "supports minimal schema definition" do
        builder = described_class.new
          .field(:email, :email)
          .field(:score, :score)
          .field(:website, :url)
          .required(:email)

        schema = builder.to_schema

        expect(schema[:properties][:email][:format]).to eq(:email)
        expect(schema[:properties][:score]).to include(minimum: 0, maximum: 100, type: :integer)
        expect(schema[:properties][:website][:format]).to eq(:uri)
        expect(schema[:required]).to eq([:email])
      end
    end

    context "complex composition pattern" do
      it "supports building complex schemas through composition" do
        # Simulate building a complex Market schema
        builder = described_class.new(model: market_model)
          .override(:overall_score, type: :score)
          .nested(:scoring_dimensions) do
            field :product_market_fit, :score
            field :market_size_potential, :score
            field :competition_level, :score
            required :product_market_fit, :market_size_potential
          end
          .array_of(:search_terms, :string)
          .field(:confidence_level, :percentage)

        schema = builder.to_schema

        # Check nested scoring dimensions
        scoring = schema[:properties][:scoring_dimensions]
        expect(scoring[:type]).to eq(:object)
        expect(scoring[:properties][:product_market_fit]).to include(type: :integer, minimum: 0, maximum: 100)

        # Check arrays
        expect(schema[:properties][:search_terms][:type]).to eq(:array)
        expect(schema[:properties][:search_terms][:items][:type]).to eq(:string)

        # Check semantic types
        expect(schema[:properties][:confidence_level]).to include(type: :number, minimum: 0, maximum: 100)
      end
    end
  end

  describe "performance" do
    it "builds schema quickly" do
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      10.times do
        described_class.new(model: market_model)
          .field(:insights, :text)
          .override(:overall_score, type: :score)
          .nested(:metadata) do
            field :created_by, :string
            field :confidence, :percentage
          end
          .to_schema
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      expect(elapsed).to be < 0.01 # Less than 10ms for 10 operations
    end
  end
end
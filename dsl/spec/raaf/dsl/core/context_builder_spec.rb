# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::ContextBuilder do
  describe "#initialize" do
    it "creates a new builder with empty context" do
      builder = described_class.new
      expect(builder.context).to be_a(RAAF::DSL::ContextVariables)
      expect(builder.context.size).to eq(0)
    end

    it "creates a builder with initial variables" do
      builder = described_class.new(name: "John", age: 30)
      expect(builder.context.get(:name)).to eq("John")
      expect(builder.context.get(:age)).to eq(30)
    end

    it "accepts debug option" do
      builder = described_class.new({}, debug: true)
      expect(builder.debug_enabled).to be true
    end
  end

  describe ".from" do
    it "creates a builder from existing ContextVariables" do
      context = RAAF::DSL::ContextVariables.new(name: "John")
      builder = described_class.from(context)
      
      expect(builder.context).to eq(context)
      expect(builder.context.get(:name)).to eq("John")
    end
  end

  describe "#with" do
    let(:builder) { described_class.new }

    it "adds a variable to the context" do
      result = builder.with(:name, "John")
      
      expect(result).to eq(builder) # returns self for chaining
      expect(builder.context.get(:name)).to eq("John")
    end

    it "supports method chaining" do
      builder
        .with(:name, "John")
        .with(:age, 30)
        .with(:city, "NYC")
      
      expect(builder.context.get(:name)).to eq("John")
      expect(builder.context.get(:age)).to eq(30)
      expect(builder.context.get(:city)).to eq("NYC")
    end

    context "with type validation" do
      it "validates type when specified" do
        expect {
          builder.with(:age, "thirty", type: Integer)
        }.to raise_error(ArgumentError, /must be Integer/)
      end

      it "allows correct type" do
        expect {
          builder.with(:age, 30, type: Integer)
        }.not_to raise_error
      end
    end

    context "with custom validation" do
      it "validates with custom proc" do
        expect {
          builder.with(:score, 150, validate: ->(v) { v <= 100 })
        }.to raise_error(ArgumentError, /failed custom validation/)
      end

      it "allows valid values" do
        expect {
          builder.with(:score, 85, validate: ->(v) { v <= 100 })
        }.not_to raise_error
      end
    end
  end

  describe "#with_all" do
    let(:builder) { described_class.new }

    it "adds multiple variables at once" do
      builder.with_all(
        name: "John",
        age: 30,
        city: "NYC"
      )
      
      expect(builder.context.get(:name)).to eq("John")
      expect(builder.context.get(:age)).to eq(30)
      expect(builder.context.get(:city)).to eq("NYC")
    end
  end

  describe "#with_if" do
    let(:builder) { described_class.new }

    it "adds variable when condition is true" do
      builder.with_if(true, :premium, "enabled")
      expect(builder.context.get(:premium)).to eq("enabled")
    end

    it "skips variable when condition is false" do
      builder.with_if(false, :premium, "enabled")
      expect(builder.context.get(:premium)).to be_nil
    end

    it "evaluates proc values" do
      builder.with_if(true, :timestamp, -> { Time.now.to_i })
      expect(builder.context.get(:timestamp)).to be_a(Integer)
    end
  end

  describe "#with_present" do
    let(:builder) { described_class.new }

    it "adds non-nil values" do
      builder.with_present(:name, "John")
      expect(builder.context.get(:name)).to eq("John")
    end

    it "skips nil values" do
      builder.with_present(:name, nil)
      expect(builder.context.get(:name)).to be_nil
    end

    it "adds false values" do
      builder.with_present(:active, false)
      expect(builder.context.get(:active)).to eq(false)
    end
  end

  describe "#merge" do
    let(:builder) { described_class.new(name: "John") }

    it "merges another ContextVariables" do
      other = RAAF::DSL::ContextVariables.new(age: 30, city: "NYC")
      builder.merge(other)
      
      expect(builder.context.get(:name)).to eq("John")
      expect(builder.context.get(:age)).to eq(30)
      expect(builder.context.get(:city)).to eq("NYC")
    end

    it "merges a hash" do
      builder.merge(age: 30, city: "NYC")
      
      expect(builder.context.get(:name)).to eq("John")
      expect(builder.context.get(:age)).to eq(30)
      expect(builder.context.get(:city)).to eq("NYC")
    end
  end

  describe "#requires" do
    let(:builder) { described_class.new }

    it "marks keys as required" do
      builder.requires(:name, :email)
      
      expect {
        builder.build!
      }.to raise_error(ArgumentError, /Required context keys missing: name, email/)
    end

    it "validates required keys are present" do
      builder
        .requires(:name, :email)
        .with(:name, "John")
        .with(:email, "john@example.com")
      
      expect { builder.build! }.not_to raise_error
    end
  end

  describe "#build" do
    let(:builder) { described_class.new }

    it "returns the built ContextVariables" do
      builder.with(:name, "John")
      context = builder.build
      
      expect(context).to be_a(RAAF::DSL::ContextVariables)
      expect(context.get(:name)).to eq("John")
    end

    context "with strict validation" do
      it "validates all requirements by default" do
        builder.requires(:name)
        
        expect {
          builder.build
        }.to raise_error(ArgumentError)
      end

      it "skips validation when strict is false" do
        builder.requires(:name)
        
        expect {
          builder.build(strict: false)
        }.not_to raise_error
      end
    end
  end

  describe "#build!" do
    let(:builder) { described_class.new }

    it "provides detailed error information" do
      builder
        .requires(:name, :email)
        .with(:age, 30)
      
      expect {
        builder.build!
      }.to raise_error(ArgumentError) do |error|
        expect(error.message).to include("ContextBuilder validation failed")
        expect(error.message).to include("Current keys: [:age]")
        expect(error.message).to include("Required keys: [:name, :email]")
      end
    end
  end

  describe "#snapshot" do
    let(:builder) { described_class.new }

    it "returns current builder state" do
      builder
        .with(:name, "John")
        .requires(:email)
      
      snapshot = builder.snapshot
      
      expect(snapshot[:context]).to eq(name: "John")
      expect(snapshot[:required_keys]).to eq([:email])
      expect(snapshot[:debug_enabled]).to be false
    end
  end

  describe "complex validation scenarios" do
    let(:builder) { described_class.new }

    it "validates multiple rules on same key" do
      builder.with(:email, "john@example.com", 
        required: true,
        type: String,
        validate: ->(v) { v.include?("@") }
      )
      
      expect(builder.context.get(:email)).to eq("john@example.com")
    end

    it "handles validation errors gracefully" do
      expect {
        builder.with(:data, nil, 
          type: Hash,
          validate: ->(v) { v[:required_key].present? }
        )
      }.to raise_error(ArgumentError)
    end
  end

  describe "real-world usage patterns" do
    it "builds agent context fluently" do
      context = described_class.new
        .with(:product, double("Product", name: "ProspectRadar"))
        .with(:company, double("Company", name: "Acme Corp"))
        .with(:analysis_depth, "detailed")
        .with_if(true, :debug_mode, true)
        .with_present(:optional_param, nil)
        .build
      
      expect(context.get(:product).name).to eq("ProspectRadar")
      expect(context.get(:company).name).to eq("Acme Corp")
      expect(context.get(:analysis_depth)).to eq("detailed")
      expect(context.get(:debug_mode)).to be true
      expect(context.get(:optional_param)).to be_nil
    end

    it "validates complex business rules" do
      builder = described_class.new
        .with(:score, 85, 
          type: Integer,
          validate: ->(v) { v.between?(0, 100) }
        )
        .with(:email, "user@example.com",
          type: String,
          validate: ->(v) { v =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i }
        )
        .with(:role, "admin",
          validate: ->(v) { %w[admin user guest].include?(v) }
        )
      
      context = builder.build
      
      expect(context.get(:score)).to eq(85)
      expect(context.get(:email)).to eq("user@example.com")
      expect(context.get(:role)).to eq("admin")
    end
  end
end
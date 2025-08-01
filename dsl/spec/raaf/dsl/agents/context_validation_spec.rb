# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/raaf/dsl/agents/context_validation"

RSpec.describe RAAF::DSL::Agents::ContextValidation do
  # Test agent class that includes the validation module
  class TestValidatingAgent
    include RAAF::DSL::Agents::ContextValidation
    
    attr_reader :context
    
    def initialize(context: nil)
      @context = context.is_a?(RAAF::DSL::ContextVariables) ? 
        context : RAAF::DSL::ContextVariables.new(context || {})
    end
  end

  # Agent with various validations
  class ComplexValidatingAgent < TestValidatingAgent
    validates_context :product, required: true, type: Hash
    validates_context :score, type: Integer, validate: -> (v) { v.between?(0, 100) }
    validates_context :email, 
      validate: -> (v) { v =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i },
      message: "must be a valid email address"
    validates_context :optional_field, required: false, allow_nil: true
  end

  # Agent using requires_context shorthand
  class RequiresContextAgent < TestValidatingAgent
    requires_context :name, :email, :company
  end

  describe "ClassMethods" do
    describe ".validates_context" do
      it "defines validation rules for a context key" do
        TestValidatingAgent.validates_context :name, required: true, type: String
        
        validations = TestValidatingAgent.context_validations
        expect(validations[:name]).to include(
          required: true,
          type: String,
          allow_nil: true
        )
      end

      it "supports multiple type validation" do
        TestValidatingAgent.validates_context :identifier, type: [String, Integer]
        
        validations = TestValidatingAgent.context_validations
        expect(validations[:identifier][:type]).to eq([String, Integer])
      end

      it "accepts custom validation procs" do
        validator = -> (v) { v > 0 }
        TestValidatingAgent.validates_context :count, validate: validator
        
        validations = TestValidatingAgent.context_validations
        expect(validations[:count][:validate]).to eq(validator)
      end

      it "accepts custom error messages" do
        TestValidatingAgent.validates_context :age, 
          validate: -> (v) { v >= 18 },
          message: "must be 18 or older"
        
        validations = TestValidatingAgent.context_validations
        expect(validations[:age][:message]).to eq("must be 18 or older")
      end
    end

    describe ".requires_context" do
      it "marks multiple keys as required" do
        agent_class = Class.new(TestValidatingAgent) do
          requires_context :product, :company, :user
        end
        
        validations = agent_class.context_validations
        expect(validations[:product][:required]).to be true
        expect(validations[:company][:required]).to be true
        expect(validations[:user][:required]).to be true
      end
    end

    describe ".validates_context?" do
      it "returns true when validations are defined" do
        agent_class = Class.new(TestValidatingAgent) do
          validates_context :name, required: true
        end
        
        expect(agent_class.validates_context?).to be true
      end

      it "returns false when no validations are defined" do
        agent_class = Class.new(TestValidatingAgent)
        
        expect(agent_class.validates_context?).to be false
      end
    end

    describe ".validate_context!" do
      let(:agent_class) { ComplexValidatingAgent }

      context "with valid context" do
        it "passes validation" do
          context = RAAF::DSL::ContextVariables.new(
            product: { name: "Test" },
            score: 85,
            email: "test@example.com"
          )
          
          expect { agent_class.validate_context!(context) }.not_to raise_error
        end
      end

      context "with missing required keys" do
        it "raises ContextValidationError" do
          context = RAAF::DSL::ContextVariables.new(score: 85)
          
          expect {
            agent_class.validate_context!(context)
          }.to raise_error(RAAF::DSL::Agents::ContextValidation::ContextValidationError) do |error|
            expect(error.message).to include("Context key 'product' is required")
            expect(error.errors).to include("Context key 'product' is required but was not provided")
          end
        end
      end

      context "with wrong type" do
        it "raises ContextValidationError for single type" do
          context = RAAF::DSL::ContextVariables.new(
            product: "not a hash",
            score: 85
          )
          
          expect {
            agent_class.validate_context!(context)
          }.to raise_error(RAAF::DSL::Agents::ContextValidation::ContextValidationError) do |error|
            expect(error.message).to include("must be Hash but was String")
          end
        end

        it "validates against multiple types" do
          agent_class = Class.new(TestValidatingAgent) do
            validates_context :id, type: [String, Integer]
          end
          
          # Valid with String
          context1 = RAAF::DSL::ContextVariables.new(id: "ABC123")
          expect { agent_class.validate_context!(context1) }.not_to raise_error
          
          # Valid with Integer
          context2 = RAAF::DSL::ContextVariables.new(id: 123)
          expect { agent_class.validate_context!(context2) }.not_to raise_error
          
          # Invalid with Float
          context3 = RAAF::DSL::ContextVariables.new(id: 123.45)
          expect {
            agent_class.validate_context!(context3)
          }.to raise_error(/must be String or Integer but was Float/)
        end
      end

      context "with custom validation" do
        it "raises error when validation fails" do
          context = RAAF::DSL::ContextVariables.new(
            product: { name: "Test" },
            score: 150  # Out of range
          )
          
          expect {
            agent_class.validate_context!(context)
          }.to raise_error(/failed custom validation/)
        end

        it "uses custom error message" do
          context = RAAF::DSL::ContextVariables.new(
            product: { name: "Test" },
            email: "invalid-email"
          )
          
          expect {
            agent_class.validate_context!(context)
          }.to raise_error(/must be a valid email address/)
        end
      end

      context "with allow_nil option" do
        it "allows nil when allow_nil is true" do
          agent_class = Class.new(TestValidatingAgent) do
            validates_context :optional, type: String, allow_nil: true
          end
          
          context = RAAF::DSL::ContextVariables.new(optional: nil)
          expect { agent_class.validate_context!(context) }.not_to raise_error
        end

        it "rejects nil when allow_nil is false" do
          agent_class = Class.new(TestValidatingAgent) do
            validates_context :required_string, type: String, allow_nil: false
          end
          
          context = RAAF::DSL::ContextVariables.new(required_string: nil)
          expect {
            agent_class.validate_context!(context)
          }.to raise_error(/must be String but was NilClass/)
        end
      end
    end
  end

  describe "InstanceMethods" do
    it "validates context on initialization" do
      expect {
        ComplexValidatingAgent.new(context: { score: 85 })
      }.to raise_error(RAAF::DSL::Agents::ContextValidation::ContextValidationError) do |error|
        expect(error.message).to include("Context key 'product' is required")
      end
    end

    it "allows valid context" do
      agent = ComplexValidatingAgent.new(context: {
        product: { name: "Test" },
        score: 85,
        email: "test@example.com"
      })
      
      expect(agent.context.get(:product)).to eq(name: "Test")
      expect(agent.context.get(:score)).to eq(85)
    end

    it "works with ContextVariables instance" do
      context = RAAF::DSL::ContextVariables.new(
        product: { name: "Test" },
        score: 75
      )
      
      agent = ComplexValidatingAgent.new(context: context)
      expect(agent.context).to eq(context)
    end
  end

  describe "ContextValidationError" do
    let(:errors) { ["Error 1", "Error 2"] }
    let(:context) { RAAF::DSL::ContextVariables.new(key: "value") }
    let(:error) { RAAF::DSL::Agents::ContextValidation::ContextValidationError.new(errors, context) }

    it "stores errors and context" do
      expect(error.errors).to eq(errors)
      expect(error.context).to eq(context)
    end

    it "builds informative error message" do
      expect(error.message).to include("Context validation failed with 2 error(s)")
      expect(error.message).to include("Error 1")
      expect(error.message).to include("Error 2")
      expect(error.message).to include("Context keys present: [:key]")
    end
  end

  describe "ContextValidators" do
    describe "predefined validators" do
      it "validates non-blank strings" do
        validator = RAAF::DSL::Agents::ContextValidators::NOT_BLANK
        
        expect(validator.call("hello")).to be true
        expect(validator.call("  hello  ")).to be true
        expect(validator.call("")).to be false
        expect(validator.call("   ")).to be false
        expect(validator.call(123)).to be false
      end

      it "validates positive numbers" do
        validator = RAAF::DSL::Agents::ContextValidators::POSITIVE
        
        expect(validator.call(5)).to be true
        expect(validator.call(0.1)).to be true
        expect(validator.call(0)).to be false
        expect(validator.call(-5)).to be false
        expect(validator.call("5")).to be false
      end

      it "validates percentages" do
        validator = RAAF::DSL::Agents::ContextValidators::PERCENTAGE
        
        expect(validator.call(0)).to be true
        expect(validator.call(50)).to be true
        expect(validator.call(100)).to be true
        expect(validator.call(-1)).to be false
        expect(validator.call(101)).to be false
      end

      it "validates email format" do
        validator = RAAF::DSL::Agents::ContextValidators::EMAIL
        
        expect(validator.call("user@example.com")).to be true
        expect(validator.call("user.name+tag@example.co.uk")).to be true
        expect(validator.call("invalid")).to be false
        expect(validator.call("@example.com")).to be false
        expect(validator.call("user@")).to be false
      end

      it "validates URL format" do
        validator = RAAF::DSL::Agents::ContextValidators::URL
        
        expect(validator.call("http://example.com")).to be true
        expect(validator.call("https://example.com/path?query=1")).to be true
        expect(validator.call("ftp://example.com")).to be false
        expect(validator.call("not a url")).to be false
      end
    end

    describe "factory validators" do
      it "validates inclusion in list" do
        validator = RAAF::DSL::Agents::ContextValidators.included_in(%w[admin user guest])
        
        expect(validator.call("admin")).to be true
        expect(validator.call("user")).to be true
        expect(validator.call("superuser")).to be false
      end

      it "validates string length" do
        validator = RAAF::DSL::Agents::ContextValidators.length_between(3, 10)
        
        expect(validator.call("abc")).to be true
        expect(validator.call("abcdefghij")).to be true
        expect(validator.call("ab")).to be false
        expect(validator.call("abcdefghijk")).to be false
        expect(validator.call(123)).to be false
      end

      it "validates array size" do
        validator = RAAF::DSL::Agents::ContextValidators.array_size_between(1, 3)
        
        expect(validator.call([1])).to be true
        expect(validator.call([1, 2, 3])).to be true
        expect(validator.call([])).to be false
        expect(validator.call([1, 2, 3, 4])).to be false
        expect(validator.call("not array")).to be false
      end

      it "validates numeric range" do
        validator = RAAF::DSL::Agents::ContextValidators.between(0, 100)
        
        expect(validator.call(0)).to be true
        expect(validator.call(50)).to be true
        expect(validator.call(100)).to be true
        expect(validator.call(-1)).to be false
        expect(validator.call(101)).to be false
        expect(validator.call("50")).to be false
      end
    end
  end

  describe "real-world usage patterns" do
    it "validates complex agent requirements" do
      agent_class = Class.new(TestValidatingAgent) do
        validates_context :product, required: true, type: Hash
        validates_context :company, required: true, type: Hash
        validates_context :markets, 
          type: Array,
          validate: RAAF::DSL::Agents::ContextValidators.array_size_between(1, 10)
        validates_context :analysis_depth, 
          validate: RAAF::DSL::Agents::ContextValidators.included_in(%w[basic standard detailed])
        validates_context :score_threshold,
          type: Integer,
          validate: RAAF::DSL::Agents::ContextValidators.between(0, 100)
      end
      
      # Valid context
      valid_context = {
        product: { name: "ProspectRadar", type: "SaaS" },
        company: { name: "Acme Corp" },
        markets: ["Market A", "Market B"],
        analysis_depth: "detailed",
        score_threshold: 75
      }
      
      expect { agent_class.new(context: valid_context) }.not_to raise_error
      
      # Invalid context
      invalid_context = {
        product: "Not a hash",
        company: { name: "Acme" },
        markets: [],  # Too few
        analysis_depth: "extreme",  # Not in list
        score_threshold: 150  # Out of range
      }
      
      expect { agent_class.new(context: invalid_context) }.to raise_error(
        RAAF::DSL::Agents::ContextValidation::ContextValidationError
      )
    end
  end
end
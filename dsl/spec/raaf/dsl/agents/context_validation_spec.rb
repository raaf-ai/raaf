# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Agents::ContextValidation do
  let(:test_class) do
    Class.new do
      include RAAF::DSL::Agents::ContextValidation

      # Mock required context config methods
      def self._required_context_keys
        @_required_context_keys ||= []
      end

      def self._context_validations
        @_context_validations ||= {}
      end

      def self.requires(*keys)
        _required_context_keys.concat(keys)
      end

      def self.validates(key, **options)
        _context_validations[key] = options
      end

      attr_reader :context

      def initialize(context = {})
        @context = context
        validate_context!
      end
    end
  end

  describe "class methods" do
    describe ".requires" do
      it "adds required context keys" do
        test_class.requires :user_id, :api_key
        expect(test_class._required_context_keys).to include(:user_id, :api_key)
      end

      it "accumulates multiple calls" do
        test_class.requires :user_id
        test_class.requires :api_key, :session_id
        expect(test_class._required_context_keys).to include(:user_id, :api_key, :session_id)
      end
    end

    describe ".validates" do
      it "stores validation rules for context keys" do
        test_class.validates :email, type: String, format: /@/
        validations = test_class._context_validations
        expect(validations[:email]).to eq(type: String, format: /@/)
      end

      it "supports presence validation" do
        test_class.validates :name, presence: true
        expect(test_class._context_validations[:name]).to include(presence: true)
      end

      it "supports type validation" do
        test_class.validates :count, type: Integer
        expect(test_class._context_validations[:count]).to include(type: Integer)
      end

      it "supports range validation" do
        test_class.validates :age, range: 18..100
        expect(test_class._context_validations[:age]).to include(range: 18..100)
      end
    end
  end

  describe "instance methods" do
    describe "#validate_context!" do
      context "with required keys" do
        before do
          test_class.requires :user_id, :api_key
        end

        it "passes when all required keys are present" do
          expect {
            test_class.new(user_id: 123, api_key: "secret")
          }.not_to raise_error
        end

        it "raises error when required keys are missing" do
          expect {
            test_class.new(user_id: 123)
          }.to raise_error(ArgumentError, /Required context keys missing: api_key/)
        end

        it "raises error with multiple missing keys" do
          expect {
            test_class.new({})
          }.to raise_error(ArgumentError, /Required context keys missing: user_id, api_key/)
        end

        it "handles symbol and string keys equivalently" do
          expect {
            test_class.new("user_id" => 123, "api_key" => "secret")
          }.not_to raise_error
        end
      end

      context "with type validations" do
        before do
          test_class.validates :count, type: Integer
          test_class.validates :name, type: String
          test_class.validates :active, type: [TrueClass, FalseClass]
        end

        it "passes when types match" do
          expect {
            test_class.new(count: 42, name: "John", active: true)
          }.not_to raise_error
        end

        it "raises error for incorrect type" do
          expect {
            test_class.new(count: "not a number")
          }.to raise_error(ArgumentError, /Context key 'count' must be Integer/)
        end

        it "accepts any of multiple allowed types" do
          expect {
            test_class.new(active: false)
          }.not_to raise_error

          expect {
            test_class.new(active: true)
          }.not_to raise_error
        end

        it "raises error when none of multiple types match" do
          expect {
            test_class.new(active: "yes")
          }.to raise_error(ArgumentError, /Context key 'active' must be TrueClass or FalseClass/)
        end
      end

      context "with presence validations" do
        before do
          test_class.validates :description, presence: true
          test_class.validates :optional_field, presence: false
        end

        it "passes when required field has value" do
          expect {
            test_class.new(description: "A description")
          }.not_to raise_error
        end

        it "raises error when required field is nil" do
          expect {
            test_class.new(description: nil)
          }.to raise_error(ArgumentError, /Context key 'description' cannot be nil or empty/)
        end

        it "raises error when required field is empty string" do
          expect {
            test_class.new(description: "")
          }.to raise_error(ArgumentError, /Context key 'description' cannot be nil or empty/)
        end

        it "raises error when required field is empty array" do
          expect {
            test_class.new(description: [])
          }.to raise_error(ArgumentError, /Context key 'description' cannot be nil or empty/)
        end

        it "allows nil values when presence is false" do
          expect {
            test_class.new(optional_field: nil)
          }.not_to raise_error
        end
      end

      context "with format validations" do
        before do
          test_class.validates :email, format: /@/
          test_class.validates :phone, format: /^\d{10}$/
        end

        it "passes when format matches" do
          expect {
            test_class.new(email: "user@example.com", phone: "1234567890")
          }.not_to raise_error
        end

        it "raises error when format doesn't match" do
          expect {
            test_class.new(email: "invalid-email")
          }.to raise_error(ArgumentError, /Context key 'email' format is invalid/)
        end

        it "skips format validation for nil values" do
          expect {
            test_class.new(email: nil)
          }.not_to raise_error
        end
      end

      context "with range validations" do
        before do
          test_class.validates :age, range: 18..100
          test_class.validates :score, range: 0...1
        end

        it "passes when value is in range" do
          expect {
            test_class.new(age: 25, score: 0.85)
          }.not_to raise_error
        end

        it "raises error when value is below range" do
          expect {
            test_class.new(age: 17)
          }.to raise_error(ArgumentError, /Context key 'age' must be in range 18\.\.100/)
        end

        it "raises error when value is above range" do
          expect {
            test_class.new(age: 101)
          }.to raise_error(ArgumentError, /Context key 'age' must be in range 18\.\.100/)
        end

        it "handles exclusive ranges" do
          expect {
            test_class.new(score: 1.0)
          }.to raise_error(ArgumentError, /Context key 'score' must be in range 0\.\.\.1/)
        end

        it "skips range validation for nil values" do
          expect {
            test_class.new(age: nil)
          }.not_to raise_error
        end
      end

      context "with multiple validations" do
        before do
          test_class.requires :user_id
          test_class.validates :user_id, type: Integer, range: 1..Float::INFINITY
          test_class.validates :email, type: String, presence: true, format: /@/
        end

        it "applies all validations" do
          expect {
            test_class.new(user_id: 123, email: "user@example.com")
          }.not_to raise_error
        end

        it "fails if any validation fails" do
          expect {
            test_class.new(user_id: 0, email: "user@example.com")
          }.to raise_error(ArgumentError, /Context key 'user_id' must be in range/)
        end
      end

      context "with custom validation methods" do
        before do
          test_class.class_eval do
            def self.validates_custom(key, **options)
              validates(key, **options.merge(custom: true))
            end

            def validate_context_value(key, value, options)
              if options[:custom] && value == "forbidden"
                raise ArgumentError, "Custom validation failed for #{key}"
              end
              super(key, value, options) if defined?(super)
            end
          end

          test_class.validates_custom :status, custom: true
        end

        it "allows custom validation logic" do
          expect {
            test_class.new(status: "allowed")
          }.not_to raise_error
        end

        it "raises error for custom validation failure" do
          expect {
            test_class.new(status: "forbidden")
          }.to raise_error(ArgumentError, /Custom validation failed for status/)
        end
      end
    end

    describe "#context_valid?" do
      before do
        test_class.requires :user_id
        test_class.validates :email, format: /@/
      end

      it "returns true for valid context" do
        instance = test_class.new(user_id: 123, email: "user@example.com")
        expect(instance.context_valid?).to eq(true)
      end

      it "returns false for invalid context (this would be called before validation)" do
        # Note: This test assumes context_valid? can be called independently
        # In practice, initialize would fail first with invalid context
        test_instance = test_class.allocate # Create without calling initialize
        test_instance.instance_variable_set(:@context, {})
        expect(test_instance.context_valid?).to eq(false)
      end
    end
  end

  describe "inheritance behavior" do
    let(:parent_class) do
      Class.new do
        include RAAF::DSL::Agents::ContextValidation

        def self._required_context_keys
          @_required_context_keys ||= []
        end

        def self._context_validations
          @_context_validations ||= {}
        end

        def self.requires(*keys)
          _required_context_keys.concat(keys)
        end

        def self.validates(key, **options)
          _context_validations[key] = options
        end

        requires :base_id
        validates :base_field, type: String

        attr_reader :context

        def initialize(context = {})
          @context = context
          validate_context!
        end
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        requires :child_id
        validates :child_field, type: Integer
      end
    end

    it "inherits parent validation rules" do
      # Child class should require both base_id and child_id
      expect {
        child_class.new(child_id: 456, child_field: 789)
      }.to raise_error(ArgumentError, /Required context keys missing: base_id/)
    end

    it "combines parent and child validation rules" do
      expect {
        child_class.new(
          base_id: 123,
          child_id: 456,
          base_field: "string",
          child_field: 789
        )
      }.not_to raise_error
    end

    it "validates both parent and child field types" do
      expect {
        child_class.new(
          base_id: 123,
          child_id: 456,
          base_field: 123, # Should be string
          child_field: 789
        )
      }.to raise_error(ArgumentError, /Context key 'base_field' must be String/)
    end
  end
end
# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Agents::ContextValidation do
  # Minimal stand-in for an agent base class: ContextValidation prepends its
  # InstanceMethods and calls +super+, so the including class needs an
  # initializer that accepts a +context:+ keyword.
  let(:base_class) do
    Class.new do
      attr_reader :context

      def initialize(context: nil, **_options)
        @context = context
      end
    end
  end

  let(:test_class) do
    Class.new(base_class) do
      include RAAF::DSL::Agents::ContextValidation
    end
  end

  def context_for(**values)
    RAAF::DSL::ContextVariables.new(values)
  end

  describe "class methods" do
    describe ".validates_context" do
      it "stores the type rule for a key" do
        test_class.validates_context :count, type: Integer

        expect(test_class.context_validations[:count]).to eq(type: Integer)
      end

      it "symbolizes string keys" do
        test_class.validates_context "count", type: Integer

        expect(test_class.context_validations).to have_key(:count)
      end

      it "stores custom validation procs and messages" do
        checker = ->(value) { value.positive? }
        test_class.validates_context :score, type: Integer, validate: checker, message: "must be positive"

        expect(test_class.context_validations[:score]).to eq(
          type: Integer,
          validate: checker,
          message: "must be positive"
        )
      end

      it "omits options that were not provided" do
        test_class.validates_context :name, type: String

        expect(test_class.context_validations[:name].keys).to contain_exactly(:type)
      end

      it "accumulates rules across multiple calls" do
        test_class.validates_context :count, type: Integer
        test_class.validates_context :name, type: String

        expect(test_class.context_validations.keys).to contain_exactly(:count, :name)
      end

      it "replaces an earlier rule for the same key" do
        test_class.validates_context :count, type: Integer
        test_class.validates_context :count, type: String

        expect(test_class.context_validations[:count]).to eq(type: String)
      end
    end

    describe ".context_validations" do
      it "is empty for a class without validations" do
        expect(test_class.context_validations).to eq({})
      end
    end

    describe ".validates_context?" do
      it "is false without validations" do
        expect(test_class.validates_context?).to be false
      end

      it "is true once a validation is declared" do
        test_class.validates_context :count, type: Integer

        expect(test_class.validates_context?).to be true
      end
    end
  end

  describe ".validate_context!" do
    context "without validations" do
      it "accepts any context" do
        expect { test_class.validate_context!(context_for(anything: Object.new)) }.not_to raise_error
      end
    end

    context "with type validations" do
      before do
        test_class.validates_context :count, type: Integer
        test_class.validates_context :active, type: [TrueClass, FalseClass]
      end

      it "passes when the types match" do
        expect { test_class.validate_context!(context_for(count: 42, active: true)) }.not_to raise_error
      end

      it "accepts any of several allowed types" do
        expect { test_class.validate_context!(context_for(active: false)) }.not_to raise_error
      end

      it "reports the expected and actual type" do
        expect { test_class.validate_context!(context_for(count: "42")) }.to raise_error(
          described_class::ContextValidationError,
          /Context key 'count' must be Integer but was String/
        )
      end

      it "lists every allowed type when none match" do
        expect { test_class.validate_context!(context_for(active: "yes")) }.to raise_error(
          described_class::ContextValidationError,
          /Context key 'active' must be TrueClass or FalseClass but was String/
        )
      end

      it "skips nil values so Ruby fails naturally instead" do
        expect { test_class.validate_context!(context_for(count: nil)) }.not_to raise_error
      end

      it "skips keys that are absent from the context" do
        expect { test_class.validate_context!(context_for(other: 1)) }.not_to raise_error
      end
    end

    context "with custom validation" do
      it "passes when the proc returns truthy" do
        test_class.validates_context :score, validate: ->(value) { value.between?(0, 100) }

        expect { test_class.validate_context!(context_for(score: 50)) }.not_to raise_error
      end

      it "uses a default message when the proc returns falsey" do
        test_class.validates_context :score, validate: ->(value) { value.between?(0, 100) }

        expect { test_class.validate_context!(context_for(score: 150)) }.to raise_error(
          described_class::ContextValidationError,
          /Context key 'score' failed custom validation/
        )
      end

      it "uses the configured message when provided" do
        test_class.validates_context :email,
                                     validate: ->(value) { value.include?("@") },
                                     message: "must be a valid email address"

        expect { test_class.validate_context!(context_for(email: "nope")) }.to raise_error(
          described_class::ContextValidationError,
          /Context key 'email' must be a valid email address/
        )
      end

      it "turns an exception raised inside the proc into a validation error" do
        test_class.validates_context :score, validate: ->(_value) { raise "boom" }

        expect { test_class.validate_context!(context_for(score: 1)) }.to raise_error(
          described_class::ContextValidationError,
          /Context key 'score' validation error: boom/
        )
      end

      it "runs the type check before the custom validation" do
        test_class.validates_context :score, type: Integer, validate: ->(value) { value.positive? }

        expect { test_class.validate_context!(context_for(score: "5")) }.to raise_error(
          described_class::ContextValidationError,
          /must be Integer but was String/
        )
      end
    end

    context "with several failing keys" do
      before do
        test_class.validates_context :count, type: Integer
        test_class.validates_context :name, type: String
      end

      it "collects every error into one exception" do
        expect { test_class.validate_context!(context_for(count: "x", name: 1)) }.to raise_error(
          described_class::ContextValidationError
        ) do |error|
          expect(error.errors.size).to eq(2)
        end
      end
    end
  end

  describe described_class::ContextValidationError do
    let(:context) { RAAF::DSL::ContextVariables.new(count: "x") }
    let(:error) { described_class.new(["Context key 'count' must be Integer but was String"], context) }

    it "exposes the collected errors" do
      expect(error.errors).to eq(["Context key 'count' must be Integer but was String"])
    end

    it "exposes the context that failed" do
      expect(error.context).to eq(context)
    end

    it "summarizes the error count in the message" do
      expect(error.message).to include("Context validation failed with 1 error(s)")
    end

    it "lists the context keys that were present" do
      expect(error.message).to include("Context keys present:")
      expect(error.message).to include("count")
    end
  end

  describe "validation on instantiation" do
    before do
      test_class.validates_context :count, type: Integer
      allow(RAAF.logger).to receive(:error)
      allow(RAAF.logger).to receive(:debug)
    end

    it "builds the instance when the context is valid" do
      instance = test_class.new(context: context_for(count: 1))

      expect(instance.context.get(:count)).to eq(1)
    end

    it "raises when the context is invalid" do
      expect { test_class.new(context: context_for(count: "1")) }.to raise_error(
        described_class::ContextValidationError
      )
    end

    it "logs the failure before re-raising" do
      expect(RAAF.logger).to receive(:error).with(/Context validation failed/)

      expect { test_class.new(context: context_for(count: "1")) }.to raise_error(
        described_class::ContextValidationError
      )
    end

    it "skips validation entirely when no rules are declared" do
      plain_class = Class.new(base_class) { include RAAF::DSL::Agents::ContextValidation }

      expect { plain_class.new(context: nil) }.not_to raise_error
    end
  end

  describe RAAF::DSL::Agents::ContextValidators do
    describe "NOT_BLANK" do
      it "accepts a string with content" do
        expect(described_class::NOT_BLANK.call("hello")).to be true
      end

      it "rejects whitespace-only strings" do
        expect(described_class::NOT_BLANK.call("   ")).to be false
      end

      it "rejects non-strings" do
        expect(described_class::NOT_BLANK.call(1)).to be false
      end
    end

    describe "POSITIVE" do
      it "accepts positive numbers" do
        expect(described_class::POSITIVE.call(1)).to be true
      end

      it "rejects zero" do
        expect(described_class::POSITIVE.call(0)).to be false
      end
    end

    describe "NON_NEGATIVE" do
      it "accepts zero" do
        expect(described_class::NON_NEGATIVE.call(0)).to be true
      end

      it "rejects negative numbers" do
        expect(described_class::NON_NEGATIVE.call(-1)).to be false
      end
    end

    describe "PERCENTAGE" do
      it "accepts the range boundaries" do
        expect(described_class::PERCENTAGE.call(0)).to be true
        expect(described_class::PERCENTAGE.call(100)).to be true
      end

      it "rejects values above 100" do
        expect(described_class::PERCENTAGE.call(101)).to be false
      end
    end

    describe "EMAIL" do
      it "accepts a well-formed address" do
        expect(described_class::EMAIL.call("user@example.com")).to be_truthy
      end

      it "rejects a malformed address" do
        expect(described_class::EMAIL.call("user-at-example")).to be_falsey
      end
    end

    describe "URL" do
      it "accepts an http URL" do
        expect(described_class::URL.call("https://example.com")).to be_truthy
      end

      it "rejects a non-URL" do
        expect(described_class::URL.call("not a url")).to be_falsey
      end
    end

    describe ".included_in" do
      it "accepts a member of the list" do
        expect(described_class.included_in(%w[a b]).call("a")).to be true
      end

      it "rejects a value outside the list" do
        expect(described_class.included_in(%w[a b]).call("c")).to be false
      end
    end

    describe ".length_between" do
      it "accepts a string inside the bounds" do
        expect(described_class.length_between(2, 4).call("abc")).to be true
      end

      it "rejects a string outside the bounds" do
        expect(described_class.length_between(2, 4).call("abcde")).to be false
      end
    end

    describe ".array_size_between" do
      it "accepts an array inside the bounds" do
        expect(described_class.array_size_between(1, 3).call([1, 2])).to be true
      end

      it "rejects an array outside the bounds" do
        expect(described_class.array_size_between(1, 3).call([])).to be false
      end
    end

    describe ".between" do
      it "accepts a number inside the bounds" do
        expect(described_class.between(1, 10).call(5)).to be true
      end

      it "rejects a number outside the bounds" do
        expect(described_class.between(1, 10).call(11)).to be false
      end
    end
  end
end

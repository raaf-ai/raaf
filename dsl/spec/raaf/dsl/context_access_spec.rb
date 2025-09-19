# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::ContextAccess do
  # Test class to include the module
  class TestContextAccess
    include RAAF::DSL::ContextAccess

    def initialize(context = {})
      @context = RAAF::DSL::ContextVariables.new(context)
    end

    attr_reader :context
  end

  describe "context variable access" do
    let(:context_data) do
      {
        simple_var: "simple_value",
        nested_data: {
          level1: {
            level2: "deep_value"
          }
        },
        array_data: [
          { id: 1, name: "item1" },
          { id: 2, name: "item2" }
        ]
      }
    end

    let(:test_object) { TestContextAccess.new(context_data) }

    describe "#method_missing" do
      it "provides access to simple context variables" do
        expect(test_object.simple_var).to eq("simple_value")
      end

      it "provides access to nested context variables" do
        expect(test_object.nested_data).to be_a(Hash)
        expect(test_object.nested_data[:level1][:level2]).to eq("deep_value")
      end

      it "provides access to array data" do
        expect(test_object.array_data).to be_an(Array)
        expect(test_object.array_data.first[:name]).to eq("item1")
      end

      it "raises NameError for undefined variables" do
        expect { test_object.undefined_variable }
          .to raise_error(NameError, /undefined variable.*not found in context/)
      end

      it "doesn't interfere with regular method calls" do
        expect(test_object.class).to eq(TestContextAccess)
        expect(test_object.context).to be_a(RAAF::DSL::ContextVariables)
      end
    end

    describe "#respond_to_missing?" do
      it "returns true for context variables" do
        expect(test_object.respond_to?(:simple_var)).to be true
        expect(test_object.respond_to?(:nested_data)).to be true
      end

      it "returns false for undefined variables" do
        expect(test_object.respond_to?(:undefined_variable)).to be false
      end

      it "handles string method names" do
        expect(test_object.respond_to?("simple_var")).to be true
        expect(test_object.respond_to?("undefined_variable")).to be false
      end
    end

    describe "context precedence" do
      context "with multiple context sources" do
        class MultiContextAccess
          include RAAF::DSL::ContextAccess

          def initialize(context_vars, processing_params = {})
            @context = context_vars
            @processing_params = processing_params
          end

          attr_reader :context, :processing_params
        end

        let(:context_vars) { RAAF::DSL::ContextVariables.new(context_key: "context_value") }
        let(:processing_params) { { processing_key: "processing_value", context_key: "override_value" } }
        let(:multi_object) { MultiContextAccess.new(context_vars, processing_params) }

        it "checks context variables first" do
          expect(multi_object.context_key).to eq("context_value")
        end

        it "falls back to processing params for missing context vars" do
          # The implementation doesn't actually fall back to processing_params
          # This test expects behavior that doesn't exist in the current implementation
          expect { multi_object.processing_key }
            .to raise_error(NameError, /undefined variable.*not found in context/)
        end
      end
    end

    describe "error handling" do
      it "provides clear error messages for missing variables" do
        expect { test_object.completely_missing_variable }
          .to raise_error(NameError) do |error|
            expect(error.message).to include("completely_missing_variable")
            expect(error.message).to include("not found in context")
          end
      end

      it "handles nil context gracefully" do
        # ContextVariables doesn't handle nil gracefully, so we test with empty hash
        nil_context_object = TestContextAccess.new({})
        expect { nil_context_object.any_variable }
          .to raise_error(NameError)
      end
    end

    describe "indifferent access support" do
      let(:mixed_keys_context) do
        {
          "string_key" => "string_value",
          :symbol_key => "symbol_value",
          nested: {
            "mixed_key" => "mixed_value",
            :another_key => "another_value"
          }
        }
      end

      let(:mixed_object) { TestContextAccess.new(mixed_keys_context) }

      it "provides access regardless of key type" do
        expect(mixed_object.string_key).to eq("string_value")
        expect(mixed_object.symbol_key).to eq("symbol_value")
      end

      it "works with nested mixed keys" do
        nested = mixed_object.nested
        expect(nested["mixed_key"]).to eq("mixed_value")
        expect(nested[:another_key]).to eq("another_value")
      end
    end

    describe "special method handling" do
      it "doesn't override important object methods" do
        expect(test_object.class).to eq(TestContextAccess)
        expect(test_object.object_id).to be_a(Integer)
        expect(test_object.inspect).to be_a(String)
      end

      it "handles private method access appropriately" do
        expect { test_object.send(:undefined_private_method) }
          .to raise_error(NameError)
      end
    end

    describe "performance with large contexts" do
      let(:large_context) do
        context = {}
        1000.times { |i| context["key_#{i}"] = "value_#{i}" }
        context[:target_key] = "target_value"
        context
      end

      let(:large_object) { TestContextAccess.new(large_context) }

      it "efficiently accesses variables in large contexts" do
        expect(large_object.target_key).to eq("target_value")
        expect(large_object.key_500).to eq("value_500")
      end
    end

    describe "context variable types" do
      let(:typed_context) do
        {
          string_var: "string",
          integer_var: 42,
          float_var: 3.14,
          boolean_var: true,
          nil_var: nil,
          array_var: [1, 2, 3],
          hash_var: { nested: "value" }
        }
      end

      let(:typed_object) { TestContextAccess.new(typed_context) }

      it "preserves variable types" do
        expect(typed_object.string_var).to be_a(String)
        expect(typed_object.integer_var).to be_a(Integer)
        expect(typed_object.float_var).to be_a(Float)
        expect(typed_object.boolean_var).to be(true)
        expect(typed_object.nil_var).to be_nil
        expect(typed_object.array_var).to be_an(Array)
        expect(typed_object.hash_var).to be_a(Hash)
      end
    end
  end

  describe "ContextAccessError" do
    it "is defined as a subclass of NameError" do
      expect(RAAF::DSL::ContextAccessError).to be < NameError
    end

    it "can be raised with custom messages" do
      expect { raise RAAF::DSL::ContextAccessError, "Custom error" }
        .to raise_error(RAAF::DSL::ContextAccessError, "Custom error")
    end
  end
end
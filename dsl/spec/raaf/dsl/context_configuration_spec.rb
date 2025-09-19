# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::ContextConfiguration do
  # Test classes to include the module
  class TestContextAgent
    include RAAF::DSL::ContextConfiguration
  end

  class TestContextService
    include RAAF::DSL::ContextConfiguration
  end

  describe "ContextConfig DSL" do
    let(:config) { RAAF::DSL::ContextConfig.new }

    describe "#required" do
      it "adds required fields as symbols" do
        config.required(:field1, :field2)
        config.required("field3")

        rules = config.to_h
        expect(rules[:required]).to eq([:field1, :field2, :field3])
      end

      it "handles multiple calls to required" do
        config.required(:field1)
        config.required(:field2, :field3)

        rules = config.to_h
        expect(rules[:required]).to eq([:field1, :field2, :field3])
      end
    end

    describe "#optional" do
      it "adds optional fields with defaults" do
        config.optional(timeout: 30, retries: 3)
        config.optional(format: "json")

        rules = config.to_h
        expect(rules[:optional]).to eq({
          timeout: 30,
          retries: 3,
          format: "json"
        })
      end

      it "handles multiple calls to optional" do
        config.optional(field1: "value1")
        config.optional(field2: "value2")

        rules = config.to_h
        expect(rules[:optional]).to eq({
          field1: "value1",
          field2: "value2"
        })
      end
    end

    describe "#output" do
      it "adds output fields as symbols" do
        config.output(:result, :summary)
        config.output("analysis")

        rules = config.to_h
        expect(rules[:output]).to eq([:result, :summary, :analysis])
      end
    end

    describe "#computed" do
      it "adds computed fields with default method names" do
        config.computed(:analysis)

        rules = config.to_h
        expect(rules[:computed]).to eq({ analysis: :compute_analysis })
      end

      it "adds computed fields with custom method names" do
        config.computed(:analysis, :custom_analysis_method)

        rules = config.to_h
        expect(rules[:computed]).to eq({ analysis: :custom_analysis_method })
      end
    end

    describe "#exclude" do
      it "adds fields to exclude list" do
        config.exclude(:secret, :internal)

        rules = config.to_h
        expect(rules[:exclude]).to eq([:secret, :internal])
      end
    end

    describe "#include" do
      it "adds fields to include list" do
        config.include(:public, :shared)

        rules = config.to_h
        expect(rules[:include]).to eq([:public, :shared])
      end
    end

    describe "#validate" do
      it "adds validation rules" do
        validation_proc = ->(value) { value.is_a?(String) }
        config.validate(:name, type: :string, with: validation_proc)

        rules = config.to_h
        expect(rules[:validations][:name]).to eq({
          type: :string,
          proc: validation_proc
        })
      end
    end

    describe "#to_h" do
      it "returns comprehensive rules hash" do
        config.required(:field1)
        config.optional(field2: "default")
        config.output(:result)
        config.computed(:analysis)
        config.exclude(:secret)
        config.include(:public)

        rules = config.to_h
        expect(rules).to include(
          required: [:field1],
          optional: { field2: "default" },
          output: [:result],
          computed: { analysis: :compute_analysis },
          exclude: [:secret],
          include: [:public]
        )
      end
    end
  end

  describe "ClassMethods" do
    let(:test_class) { Class.new { include RAAF::DSL::ContextConfiguration } }

    describe "#_context_config" do
      it "provides thread-local configuration storage" do
        config1 = test_class._context_config
        config1[:test] = "value1"

        # Should persist in same thread
        expect(test_class._context_config[:test]).to eq("value1")

        # Should be isolated per class
        other_class = Class.new { include RAAF::DSL::ContextConfiguration }
        expect(other_class._context_config[:test]).to be_nil
      end

      it "isolates configuration between threads" do
        test_class._context_config[:thread_test] = "main_thread"

        thread_result = nil
        thread = Thread.new do
          test_class._context_config[:thread_test] = "other_thread"
          thread_result = test_class._context_config[:thread_test]
        end
        thread.join

        expect(thread_result).to eq("other_thread")
        expect(test_class._context_config[:thread_test]).to eq("main_thread")
      end
    end

    describe "#auto_context" do
      it "enables auto-context by default" do
        expect(test_class.auto_context?).to be true
      end

      it "can disable auto-context" do
        test_class.auto_context(false)
        expect(test_class.auto_context?).to be false
      end

      it "can re-enable auto-context" do
        test_class.auto_context(false)
        test_class.auto_context(true)
        expect(test_class.auto_context?).to be true
      end
    end

    describe "#context DSL" do
      it "configures context with block syntax" do
        test_class.context do
          required :product, :company
          optional timeout: 30, retries: 3
          output :analysis, :summary
        end

        config = test_class._context_config[:context_rules]
        expect(config[:required]).to eq([:product, :company])
        expect(config[:optional]).to eq({ timeout: 30, retries: 3 })
        expect(config[:output]).to eq([:analysis, :summary])
      end

      it "configures context with hash syntax" do
        test_class.context(
          defaults: { timeout: 30 },
          requirements: [:product]
        )

        config = test_class._context_config[:context_rules]
        expect(config[:defaults]).to eq({ timeout: 30 })
        expect(config[:requirements]).to eq([:product])
      end
    end

    describe "#required_fields" do
      it "returns empty array when no configuration" do
        expect(test_class.required_fields).to eq([])
      end

      it "returns required fields from new format" do
        test_class.context do
          required :product, :company
          optional timeout: 30
        end

        expect(test_class.required_fields).to eq([:product, :company])
      end

      it "returns required fields from legacy format" do
        test_class.context(requirements: [:product, :company])

        expect(test_class.required_fields).to eq([:product, :company])
      end

      it "handles duplicate fields" do
        test_class.context do
          required :product, :company, :product  # Duplicate
        end

        expect(test_class.required_fields).to eq([:product, :company])
      end
    end

    describe "#externally_required_fields" do
      it "returns fields without defaults" do
        test_class.context do
          required :product, :company, :timeout
          optional timeout: 30  # Has default
        end

        expect(test_class.externally_required_fields).to eq([:product, :company])
      end

      it "handles legacy format" do
        test_class.context(
          requirements: [:product, :timeout],
          defaults: { timeout: 30 }
        )

        expect(test_class.externally_required_fields).to eq([:product])
      end
    end

    describe "#provided_fields" do
      it "returns output fields from DSL configuration" do
        test_class.context do
          output :analysis, :summary
        end

        expect(test_class.provided_fields).to eq([:analysis, :summary])
      end

      it "returns empty array when no configuration" do
        expect(test_class.provided_fields).to eq([])
      end

      it "uses last_result_fields when available" do
        allow(test_class).to receive(:respond_to?).with(:last_result_fields).and_return(true)
        allow(test_class).to receive(:last_result_fields).and_return([:dynamic_field])

        expect(test_class.provided_fields).to eq([:dynamic_field])
      end

      it "falls back to declared_provided_fields" do
        allow(test_class).to receive(:respond_to?).with(:last_result_fields).and_return(false)
        allow(test_class).to receive(:respond_to?).with(:declared_provided_fields).and_return(true)
        allow(test_class).to receive(:declared_provided_fields).and_return([:declared_field])

        expect(test_class.provided_fields).to eq([:declared_field])
      end
    end

    describe "#requirements_met?" do
      before do
        test_class.context do
          required :product, :company
          optional timeout: 30, retries: 3
        end
      end

      context "with hash context" do
        it "returns true when all requirements met" do
          context = { product: "Test Product", company: "Test Company" }
          expect(test_class.requirements_met?(context)).to be true
        end

        it "returns false when requirements missing" do
          context = { product: "Test Product" }  # Missing company
          expect(test_class.requirements_met?(context)).to be false
        end

        it "handles string keys" do
          context = { "product" => "Test Product", "company" => "Test Company" }
          expect(test_class.requirements_met?(context)).to be true
        end

        it "considers default values" do
          test_class.context do
            required :product, :timeout
            optional timeout: 30  # timeout has default
          end

          context = { product: "Test Product" }  # timeout missing but has default
          expect(test_class.requirements_met?(context)).to be true
        end
      end

      context "with context-like objects" do
        it "handles objects with keys and key? methods" do
          context_like = double("context_like")
          allow(context_like).to receive(:respond_to?).with(:keys).and_return(true)
          allow(context_like).to receive(:respond_to?).with(:key?).and_return(true)
          allow(context_like).to receive(:key?).with(:product).and_return(true)
          allow(context_like).to receive(:key?).with(:company).and_return(true)

          expect(test_class.requirements_met?(context_like)).to be true
        end

        it "handles objects with only keys method" do
          context_like = double("context_like")
          allow(context_like).to receive(:respond_to?).with(:keys).and_return(true)
          allow(context_like).to receive(:respond_to?).with(:key?).and_return(false)
          allow(context_like).to receive(:keys).and_return([:product, :company])

          expect(test_class.requirements_met?(context_like)).to be true
        end

        it "handles other context objects" do
          context_like = double("context_like")
          allow(context_like).to receive(:respond_to?).with(:keys).and_return(false)
          allow(context_like).to receive(:respond_to?).with(:product).and_return(true)
          allow(context_like).to receive(:respond_to?).with(:company).and_return(true)

          expect(test_class.requirements_met?(context_like)).to be true
        end
      end

      it "returns true for classes with no requirements" do
        no_req_class = Class.new { include RAAF::DSL::ContextConfiguration }
        expect(no_req_class.requirements_met?({})).to be true
      end
    end

    describe "#inherited" do
      it "ensures subclasses get their own configuration" do
        parent_class = Class.new { include RAAF::DSL::ContextConfiguration }
        parent_class._context_config[:test] = "parent"

        child_class = Class.new(parent_class)
        expect(child_class._context_config[:test]).to be_nil

        child_class._context_config[:test] = "child"
        expect(parent_class._context_config[:test]).to eq("parent")
        expect(child_class._context_config[:test]).to eq("child")
      end
    end

    describe "#detect_duplicate_context_determination!" do
      let(:duplicate_class) do
        Class.new do
          include RAAF::DSL::ContextConfiguration

          def build_product_context
            "computed product"
          end

          private

          def build_company_context
            "computed company"
          end
        end
      end

      it "detects duplicate determination for required fields" do
        duplicate_class.context do
          required :product, :company
        end

        expect { duplicate_class.detect_duplicate_context_determination! }
          .to raise_error(RAAF::DSL::DuplicateContextError) do |error|
            expect(error.message).to include("Field 'product' has multiple determination methods")
            expect(error.message).to include("Declared as 'required' in context DSL")
            expect(error.message).to include("Has method 'build_product_context'")
          end
      end

      it "detects duplicate determination for optional fields" do
        duplicate_class.context do
          optional product: "default_product"
        end

        expect { duplicate_class.detect_duplicate_context_determination! }
          .to raise_error(RAAF::DSL::DuplicateContextError) do |error|
            expect(error.message).to include("Field 'product' has multiple determination methods")
            expect(error.message).to include("Declared as 'optional' with default")
            expect(error.message).to include("Has method 'build_product_context'")
          end
      end

      it "detects computed field conflicts" do
        duplicate_class.context do
          required :product
          computed :product, :custom_product_method
        end

        expect { duplicate_class.detect_duplicate_context_determination! }
          .to raise_error(RAAF::DSL::DuplicateContextError) do |error|
            expect(error.message).to include("Field 'product' has multiple determination methods")
            expect(error.message).to include("Has computed method 'custom_product_method'")
          end
      end

      it "passes when no duplicates exist" do
        clean_class = Class.new do
          include RAAF::DSL::ContextConfiguration

          def build_other_context
            "computed other"
          end
        end

        clean_class.context do
          required :product, :company
        end

        expect { clean_class.detect_duplicate_context_determination! }.not_to raise_error
      end

      it "provides helpful error message with fix suggestions" do
        duplicate_class.context do
          required :product
        end

        expect { duplicate_class.detect_duplicate_context_determination! }
          .to raise_error(RAAF::DSL::DuplicateContextError) do |error|
            expect(error.message).to include("To fix this issue, choose ONE method for each field:")
            expect(error.message).to include("Option 1: Remove the field from context DSL")
            expect(error.message).to include("Option 2: Remove the build_*_context method")
            expect(error.message).to include("Context DSL is preferred for:")
            expect(error.message).to include("build_*_context methods are preferred for:")
          end
      end
    end
  end

  describe "thread safety" do
    it "isolates configuration between classes in same thread" do
      class1 = Class.new { include RAAF::DSL::ContextConfiguration }
      class2 = Class.new { include RAAF::DSL::ContextConfiguration }

      class1._context_config[:test] = "class1_value"
      class2._context_config[:test] = "class2_value"

      expect(class1._context_config[:test]).to eq("class1_value")
      expect(class2._context_config[:test]).to eq("class2_value")
    end

    it "handles concurrent access from multiple threads" do
      test_class = Class.new { include RAAF::DSL::ContextConfiguration }

      threads = 10.times.map do |i|
        Thread.new do
          test_class._context_config[:thread_id] = i
          sleep(0.01)  # Small delay to increase chance of race conditions
          test_class._context_config[:thread_id]
        end
      end

      results = threads.map(&:value)
      expect(results).to eq((0..9).to_a)
    end
  end

  describe "error handling" do
    it "handles invalid context objects gracefully" do
      test_class = Class.new { include RAAF::DSL::ContextConfiguration }
      test_class.context do
        required :field1
      end

      # Test with nil
      expect(test_class.requirements_met?(nil)).to be false

      # Test with object that doesn't respond to expected methods
      invalid_context = Object.new
      expect(test_class.requirements_met?(invalid_context)).to be false
    end

    it "handles missing context configuration gracefully" do
      test_class = Class.new { include RAAF::DSL::ContextConfiguration }

      expect(test_class.required_fields).to eq([])
      expect(test_class.externally_required_fields).to eq([])
      expect(test_class.provided_fields).to eq([])
      expect(test_class.requirements_met?({})).to be true
    end
  end

  describe "ActiveSupport::HashWithIndifferentAccess integration" do
    let(:test_class) do
      Class.new do
        include RAAF::DSL::ContextConfiguration

        context do
          required :product, :company
        end
      end
    end

    it "works with HashWithIndifferentAccess objects" do
      context = ActiveSupport::HashWithIndifferentAccess.new({
        "product" => "Test Product",
        :company => "Test Company"
      })

      expect(test_class.requirements_met?(context)).to be true
    end

    it "converts regular hashes to indifferent access" do
      context = { "product" => "Test Product", :company => "Test Company" }
      expect(test_class.requirements_met?(context)).to be true
    end
  end

  describe "backward compatibility" do
    it "supports legacy requirements and defaults keys" do
      test_class = Class.new { include RAAF::DSL::ContextConfiguration }
      test_class.context(
        requirements: [:product, :company],
        defaults: { timeout: 30 }
      )

      expect(test_class.required_fields).to eq([:product, :company])
      expect(test_class.externally_required_fields).to eq([:product, :company])

      context = { product: "Test", company: "Test" }
      expect(test_class.requirements_met?(context)).to be true
    end

    it "prioritizes new format over legacy format" do
      test_class = Class.new { include RAAF::DSL::ContextConfiguration }
      test_class._context_config[:context_rules] = {
        required: [:new_field],
        requirements: [:old_field],  # Should be ignored
        optional: { new_default: "new" },
        defaults: { old_default: "old" }  # Should be ignored
      }

      expect(test_class.required_fields).to eq([:new_field])
    end
  end
end
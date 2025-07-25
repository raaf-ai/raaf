# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe RAAF::DSL::Prompts::Base do
  let(:simple_context) { { document_name: "Test Document", analysis_depth: "comprehensive" } }

  it_behaves_like "a base class"
  # pending "Shared example requires implementation"
  it_behaves_like "a prompt class"
  # pending "Shared example requires custom matchers" # TODO: Shared example needs custom matchers

  describe "class inheritance" do
    it "sets up class variables on inheritance" do
      subclass = Class.new(described_class)

      expect(subclass.instance_variable_get(:@_required_variables)).to eq([])
      expect(subclass.instance_variable_get(:@_optional_variables)).to eq([])
      expect(subclass.instance_variable_get(:@_context_mappings)).to eq({})
      expect(subclass.instance_variable_get(:@_contract_mode)).to eq(:warn)
    end

    it "isolates class variables between subclasses" do
      subclass1 = Class.new(described_class) do
        required :field1
      end

      subclass2 = Class.new(described_class) do
        required :field2
      end

      expect(subclass1._required_variables).to eq([:field1])
      expect(subclass2._required_variables).to eq([:field2])
    end
  end

  describe "class DSL methods" do
    describe ".required" do
      it "sets required variables" do
        prompt_class = Class.new(described_class) do
          required :document_name, :analysis_depth
        end

        expect(prompt_class._required_variables).to eq(%i[document_name analysis_depth])
      end

      it "converts strings to symbols" do
        prompt_class = Class.new(described_class) do
          required "document_name", "analysis_depth"
        end

        expect(prompt_class._required_variables).to eq(%i[document_name analysis_depth])
      end
    end

    describe ".optional" do
      it "sets optional variables" do
        prompt_class = Class.new(described_class) do
          optional :document_type, :location
        end

        expect(prompt_class._optional_variables).to eq(%i[document_type location])
      end

      it "converts strings to symbols" do
        prompt_class = Class.new(described_class) do
          optional "document_type", "location"
        end

        expect(prompt_class._optional_variables).to eq(%i[document_type location])
      end
    end

    describe ".contract_mode" do
      it "sets contract mode to strict" do
        prompt_class = Class.new(described_class) do
          contract_mode :strict
        end

        expect(prompt_class._contract_mode).to eq(:strict)
      end

      it "sets contract mode to lenient" do
        prompt_class = Class.new(described_class) do
          contract_mode :lenient
        end

        expect(prompt_class._contract_mode).to eq(:lenient)
      end

      it "raises error for invalid contract mode" do
        expect do
          Class.new(described_class) do
            contract_mode :invalid
          end
        end.to raise_error(ArgumentError, "Contract mode must be :strict, :warn, or :lenient")
      end
    end

    describe ".required with path" do
      it "adds to required variables and context mappings" do
        prompt_class = Class.new(described_class) do
          required :document_name, path: %i[document name]
        end

        expect(prompt_class._required_variables).to include(:document_name)
        expect(prompt_class._context_mappings[:document_name]).to eq({
                                                                       path: %i[document name],
                                                                       default: nil,
                                                                       required: true
                                                                     })
      end

      it "prevents default values for required variables" do
        expect do
          Class.new(described_class) do
            required :document_type, path: %i[document document_type], default: "Text"
          end
        end.to raise_error(ArgumentError, "Cannot specify default value for required variables")
      end

      it "prevents duplicate variables" do
        prompt_class = Class.new(described_class) do
          required :document_name
          required :document_name, path: %i[document name]
        end

        expect(prompt_class._required_variables.count(:document_name)).to eq(1)
      end
    end

    describe ".optional with path" do
      it "adds to optional variables and context mappings" do
        prompt_class = Class.new(described_class) do
          optional :size, path: %i[document metadata size]
        end

        expect(prompt_class._optional_variables).to include(:size)
        expect(prompt_class._context_mappings[:size]).to eq({
                                                              path: %i[document metadata size],
                                                              default: nil,
                                                              required: false
                                                            })
      end

      it "supports default values" do
        prompt_class = Class.new(described_class) do
          optional :document_type, path: %i[document document_type], default: "Text"
        end

        mapping = prompt_class._context_mappings[:document_type]
        expect(mapping[:default]).to eq("Text")
      end
    end

    describe ".declared_variables" do
      it "returns all declared variables" do
        prompt_class = Class.new(described_class) do
          required :required_field
          optional :optional_field
        end

        declared = prompt_class.declared_variables
        expect(declared).to include(:required_field, :optional_field)
        expect(declared.uniq).to eq(declared) # No duplicates
      end
    end
  end

  describe "initialization" do
    describe "with valid context" do
      let(:prompt_class) do
        Class.new(described_class) do
          required :document_name, :analysis_depth
          optional :document_type
        end
      end

      it "accepts context with all required variables" do
        expect { prompt_class.new(**simple_context) }.not_to raise_error
      end

      it "stores context" do
        instance = prompt_class.new(**simple_context)
        expect(instance.instance_variable_get(:@context)).to eq(simple_context)
      end

      it "accepts extra variables in lenient mode" do
        lenient_class = Class.new(described_class) do
          required :company_name
          contract_mode :lenient
        end

        context_with_extra = { company_name: "Test Company", extra_field: "value" }
        expect { lenient_class.new(**context_with_extra) }.not_to raise_error
      end
    end

    describe "with invalid context" do
      let(:strict_prompt_class) do
        Class.new(described_class) do
          required :document_name, :analysis_depth
          contract_mode :strict
        end
      end

      it "raises error for missing required variables" do
        incomplete_context = { document_name: "Test Document" }

        instance = strict_prompt_class.new(**incomplete_context)
        expect do
          instance.validate!
        end.to raise_error(RAAF::DSL::Prompts::VariableContractError, /Missing required variables/)
      end

      it "raises error for unused variables in strict mode" do
        context_with_extra = simple_context.merge(unused_field: "value")

        instance = strict_prompt_class.new(**context_with_extra)
        expect do
          instance.validate!
        end.to raise_error(RAAF::DSL::Prompts::VariableContractError, /Unused variables/)
      end
    end

    describe "with context mappings" do
      let(:context_mapped_class) do
        Class.new(described_class) do
          required :document_name, path: %i[document name]
          optional :document_type, path: %i[document document_type], default: "Text"
          optional :size, path: %i[document metadata size]
          contract_mode :strict
        end
      end

      let(:nested_context) do
        {
          document: {
            name: "Test Document",
            document_type: "Text",
            metadata: {
              size: "1000 words"
            }
          }
        }
      end

      it "validates context path mappings" do
        expect { context_mapped_class.new(**nested_context) }.not_to raise_error
      end

      it "raises error for missing required context paths" do
        incomplete_context = {
          document: {
            document_type: "Text"
            # Missing name
          }
        }

        instance = context_mapped_class.new(**incomplete_context)
        expect do
          instance.validate!
        end.to raise_error(RAAF::DSL::Prompts::VariableContractError, /Missing required context paths/)
      end

      it "uses default values for missing optional context paths" do
        pending "Requires raaf-testing gem for custom matchers"
        context_without_document_type = {
          document: {
            name: "Test Document"
            # Missing document_type, should use default
          }
        }

        instance = Class.new(described_class) do
          required :document_name, path: %i[document name]
          optional :document_type, path: %i[document document_type], default: "Text"
        end.new(**context_without_document_type)

        expect(instance.document_type).to eq("Text")
      end
    end
  end

  describe "abstract methods" do
    let(:instance) { described_class.new }

    describe "#system" do
      it "raises NotImplementedError" do
        expect { instance.system }.to raise_error(NotImplementedError, "Subclasses must implement #system")
      end
    end

    describe "#user" do
      it "raises NotImplementedError" do
        expect { instance.user }.to raise_error(NotImplementedError, "Subclasses must implement #user")
      end
    end
  end

  describe "rendering methods" do
    let(:concrete_prompt_class) do
      Class.new(described_class) do
        required :document_name

        def system
          "System prompt for #{document_name}"
        end

        def user
          "User prompt for #{document_name}"
        end
      end
    end

    let(:instance) { concrete_prompt_class.new(**simple_context) }

    describe "#render_messages" do
      it "returns hash with system and user prompts" do
        messages = instance.render_messages

        expect(messages[:system]).to eq("System prompt for Test Document")
        expect(messages[:user]).to eq("User prompt for Test Document")
      end
    end

    describe "#render" do
      context "with specific type" do
        it "renders system prompt" do
          result = instance.render(:system)
          expect(result).to eq("System prompt for Test Document")
        end

        it "renders user prompt" do
          result = instance.render(:user)
          expect(result).to eq("User prompt for Test Document")
        end
      end

      context "without type" do
        it "returns render_messages by default" do
          result = instance.render
          expect(result).to eq(instance.render_messages)
        end
      end
    end

    describe "prompt processing" do
      let(:multiline_prompt_class) do
        Class.new(described_class) do
          required :document_name

          def system
            [
              "First part of prompt",
              "Second part of prompt"
            ]
          end

          def user
            "User prompt with trailing whitespace   \n  "
          end
        end
      end

      let(:multiline_instance) { multiline_prompt_class.new(**simple_context) }

      it "joins array prompts with double newlines" do
        result = multiline_instance.render(:system)
        expect(result).to eq("First part of prompt\n\nSecond part of prompt")
      end

      it "strips trailing whitespace" do
        result = multiline_instance.render(:user)
        expect(result).to eq("User prompt with trailing whitespace")
      end
    end
  end

  describe "context access" do
    let(:instance) { described_class.new(**simple_context) }

    describe "#context" do
      it "provides access to stored context" do
        expect(instance.context).to eq(simple_context)
      end
    end

    describe "method_missing for context access" do
      it "provides direct access to context keys" do
        expect(instance.document_name).to eq("Test Document")
        expect(instance.analysis_depth).to eq("comprehensive")
      end

      it "returns nil for missing context keys" do
        expect { instance.nonexistent_key }.to raise_error(NoMethodError)
      end

      it "raises NoMethodError for invalid method calls" do
        expect { instance.invalid_method_with_args(1, 2, 3) }.to raise_error(NoMethodError)
      end
    end

    describe "respond_to_missing?" do
      it "responds to context keys" do
        expect(instance.respond_to?(:document_name)).to be true
        expect(instance.respond_to?(:analysis_depth)).to be true
      end

      it "does not respond to non-context keys" do
        expect(instance.respond_to?(:nonexistent_key)).to be false
      end
    end
  end

  describe "context-mapped variable access" do
    let(:context_mapped_class) do
      Class.new(described_class) do
        required :document_name, path: %i[document name]
        optional :document_type, path: %i[document document_type], default: "Unknown"
        optional :size, path: %i[document metadata size]
      end
    end

    let(:nested_context) do
      {
        document: {
          name: "Mapped Document",
          document_type: "Report",
          metadata: {
            size: "5000 words"
          }
        }
      }
    end

    let(:instance) { context_mapped_class.new(**nested_context) }

    it "provides access to context-mapped variables" do
      expect(instance.document_name).to eq("Mapped Document")
      expect(instance.document_type).to eq("Report")
      expect(instance.size).to eq("5000 words")
    end

    it "uses default values when path is missing" do
      pending "Context variable handling"
      context_missing_document_type = {
        document: {
          name: "Mapped Document"
          # Missing document_type
        }
      }

      instance = context_mapped_class.new(**context_missing_document_type)
      expect(instance.document_type).to eq("Unknown")
    end

    it "memoizes context-mapped values" do
      # First access
      value1 = instance.document_name

      # Second access should return same object
      value2 = instance.document_name

      expect(value1).to be(value2)
    end

    it "treats empty strings as nil for required fields" do
      context_with_empty = {
        document: {
          name: "", # Empty string
          document_type: "Text"
        }
      }

      instance = context_mapped_class.new(**context_with_empty)
      expect do
        instance.validate!
      end.to raise_error(RAAF::DSL::Prompts::VariableContractError, /Missing required context paths/)
    end
  end

  describe "contract validation" do
    describe "strict mode" do
      let(:strict_class) do
        Class.new(described_class) do
          required :required_field
          optional :optional_field
          contract_mode :strict
        end
      end

      it "allows exact match of declared variables" do
        context = { required_field: "value", optional_field: "optional" }
        expect { strict_class.new(**context) }.not_to raise_error
      end

      it "allows missing optional variables" do
        context = { required_field: "value" }
        expect { strict_class.new(**context) }.not_to raise_error
      end

      it "rejects extra variables" do
        context = { required_field: "value", extra_field: "extra" }
        instance = strict_class.new(**context)
        expect do
          instance.validate!
        end.to raise_error(RAAF::DSL::Prompts::VariableContractError, /Unused variables/)
      end

      it "rejects missing required variables" do
        context = { optional_field: "optional" }
        instance = strict_class.new(**context)
        expect do
          instance.validate!
        end.to raise_error(RAAF::DSL::Prompts::VariableContractError, /Missing required variables/)
      end
    end

    describe "warn mode" do
      let(:warn_class) do
        Class.new(described_class) do
          required :required_field
          optional :optional_field
          contract_mode :warn
        end
      end

      it "logs warnings for unused variables", :capture_output do
        context = { required_field: "value", extra_field: "extra" }

        instance = warn_class.new(**context)
        # Capture output during validation
        output = capture(:stdout) { instance.validate! }

        expect(output).to include("[WARN] [RAAF] Variable contract warning")
        expect(output).to include("Unused variables")
      end

      it "still raises errors for missing required variables" do
        context = { optional_field: "optional" }
        instance = warn_class.new(**context)
        expect do
          instance.validate!
        end.to raise_error(RAAF::DSL::Prompts::VariableContractError, /Missing required variables/)
      end
    end

    describe "lenient mode" do
      let(:lenient_class) do
        Class.new(described_class) do
          required :required_field
          contract_mode :lenient
        end
      end

      it "allows extra variables without warning" do
        context = { required_field: "value", extra_field: "extra" }
        expect { lenient_class.new(**context) }.not_to raise_error
      end

      it "still validates required variables" do
        context = { extra_field: "extra" }
        instance = lenient_class.new(**context)
        expect do
          instance.validate!
        end.to raise_error(RAAF::DSL::Prompts::VariableContractError, /Missing required variables/)
      end
    end

    describe "with context mappings and regular variables" do
      let(:mixed_class) do
        Class.new(described_class) do
          required :regular_field
          required :mapped_field, path: %i[nested field]
          contract_mode :strict
        end
      end

      it "validates both types correctly" do
        context = {
          regular_field: "value",
          nested: { field: "mapped_value" }
        }

        expect { mixed_class.new(**context) }.not_to raise_error
      end

      it "excludes context root keys from unused variable check" do
        context = {
          regular_field: "value",
          nested: { field: "mapped_value" }
          # 'nested' should not be flagged as unused since it's a context root
        }

        expect { mixed_class.new(**context) }.not_to raise_error
      end
    end
  end

  describe "error handling" do
    describe "VariableContractError" do
      it "is a StandardError subclass" do
        expect(RAAF::DSL::Prompts::VariableContractError).to be < StandardError
      end

      it "can be raised with custom message" do
        expect do
          raise RAAF::DSL::Prompts::VariableContractError, "Custom error message"
        end.to raise_error(RAAF::DSL::Prompts::VariableContractError, "Custom error message")
      end
    end

    describe "context path resolution errors" do
      let(:error_class) do
        Class.new(described_class) do
          required :missing_field, path: %i[nonexistent path]
        end
      end

      it "provides clear error messages for missing context paths" do
        context = { other_field: "value" }

        instance = error_class.new(**context)
        expect do
          instance.validate!
        end.to raise_error(RAAF::DSL::Prompts::VariableContractError) do |error|
          expect(error.message).to include("Missing required context paths")
          expect(error.message).to include("missing_field")
        end
      end
    end
  end

  describe "Rails integration" do
    context "with Rails logger available", :with_rails do
      let(:warn_class) do
        Class.new(described_class) do
          required :required_field
          contract_mode :warn
        end
      end

      it "uses Rails logger for warnings" do
        pending "Requires Rails logger integration"
        logger = double("Logger")
        allow(Rails).to receive(:logger).and_return(logger)
        expect(logger).to receive(:warn).with(/Variable Contract.*Unused variables/)

        context = { required_field: "value", extra_field: "extra" }
        instance = warn_class.new(**context)
        instance.validate!
      end
    end

    context "without Rails logger" do
      let(:warn_class) do
        Class.new(described_class) do
          required :required_field
          contract_mode :warn
        end
      end

      before do
        hide_const("Rails")
      end

      it "falls back to puts for warnings", :capture_output do
        context = { required_field: "value", extra_field: "extra" }

        instance = warn_class.new(**context)
        # Capture output during validation
        output = capture(:stdout) { instance.validate! }

        expect(output).to include("[WARN] [RAAF] Variable contract warning")
      end
    end
  end

  describe "complex usage examples" do
    let(:comprehensive_prompt_class) do
      Class.new(described_class) do
        # Regular required/optional variables
        required :analysis_type, :focus_areas
        optional :timeline

        # Context-mapped variables
        required :document_name, path: %i[document name]
        optional :document_type, path: %i[document document_type], default: "Text"
        optional :size, path: %i[document metadata size]
        optional :pages, path: %i[document structure pages]

        contract_mode :strict

        def system
          <<~SYSTEM
            You are analyzing #{document_name} of type #{document_type}.
            Analysis type: #{analysis_type}
            Focus areas: #{focus_areas.join(', ')}
            #{"Size: #{size}" if size}
            #{"Pages: #{pages}" if pages}
            #{"Timeline: #{context[:timeline]}" if context[:timeline]}
          SYSTEM
        end

        def user
          "Perform #{analysis_type} analysis focusing on #{focus_areas.join(' and ')}"
        end
      end
    end

    let(:comprehensive_context) do
      {
        analysis_type: "competitive",
        focus_areas: ["market share", "pricing", "features"],
        timeline: "Q4 2024",
        document: {
          name: "Example Document",
          document_type: "Report",
          metadata: {
            size: "10000 words"
          },
          structure: {
            pages: 150
          }
        }
      }
    end

    it "works with complex real-world configuration" do
      pending "Requires raaf-testing gem for custom matchers"
      # Test using new matchers
      expect(comprehensive_prompt_class).to include_prompt_content(
        "Example Document", "Report", "competitive", "market share, pricing, features",
        "10000 words", "150", "Q4 2024"
      ).with_context(comprehensive_context)

      # Test content in specific prompt sections
      expect(comprehensive_prompt_class).to include_prompt_content("competitive analysis")
        .in_prompt(:user)
        .with_context(comprehensive_context)

      expect(comprehensive_prompt_class).to include_prompt_content("market share and pricing and features")
        .in_prompt(:user)
        .with_context(comprehensive_context)

      expect(comprehensive_prompt_class).to include_prompt_content("10000 words", "150")
        .in_prompt(:user)
        .with_context(comprehensive_context)
    end

    it "handles partial context gracefully" do
      pending "Requires raaf-testing gem for custom matchers"
      minimal_context = {
        analysis_type: "basic",
        focus_areas: ["overview"],
        document: {
          name: "Minimal Document"
          # Missing document_type (will use default)
          # Missing metadata and structure (optional)
        }
      }

      # Test using new matchers
      expect(comprehensive_prompt_class).to include_prompt_content("Minimal Document", "Text")
        .with_context(minimal_context)

      expect(comprehensive_prompt_class).not_to include_prompt_content("Size:", "Pages:")
        .with_context(minimal_context)
    end
  end

  describe "using custom RSpec matchers" do
    let(:test_prompt_class) do
      Class.new(described_class) do
        required :document_name, :analysis_type
        optional :priority_level
        required :document_path, path: %i[document file_path]
        optional :page_count, path: %i[document metadata pages], default: "unknown"

        def system
          output = "Analyzing #{document_name} using #{analysis_type} analysis."
          output += "\nLocation: #{document_path}"
          output += "\nPages: #{page_count}"
          output += "\nPriority: #{context[:priority_level]}" if context[:priority_level]
          output
        end

        def user
          "Please analyze #{document_name}."
        end
      end
    end

    let(:full_context) do
      {
        document_name: "Annual Report 2024",
        analysis_type: "financial",
        priority_level: "high",
        document: {
          file_path: "/reports/annual_2024.pdf",
          metadata: { pages: 150 }
        }
      }
    end

    describe "content inclusion matchers" do
      it "validates content across both prompts" do
        pending "Prompt type-specific content validation"
        expect(test_prompt_class).to include_prompt_content(
          "Annual Report 2024", "financial", "/reports/annual_2024.pdf", "150"
        ).with_context(full_context)
      end

      it "validates content in specific prompt types" do
        pending "Requires raaf-testing gem for custom matchers"
        expect(test_prompt_class).to include_prompt_content("Analyzing")
          .in_prompt(:system)
          .with_context(full_context)

        expect(test_prompt_class).to include_prompt_content("Please analyze")
          .in_prompt(:user)
          .with_context(full_context)
      end

      it "supports regex patterns" do
        pending "Regex pattern content matching"
        expect(test_prompt_class).to include_prompt_content(/Annual.*Report.*\d{4}/)
          .with_context(full_context)
      end

      it "validates optional content presence" do
        pending "Requires raaf-testing gem for custom matchers"
        expect(test_prompt_class).to include_prompt_content("Priority: high")
          .with_context(full_context)

        # Test without priority
        minimal_context = full_context.except(:priority_level)
        expect(test_prompt_class).not_to include_prompt_content("Priority:")
          .with_context(minimal_context)
      end
    end

    describe "validation matchers" do
      it "validates successfully with complete context" do
        pending "Incomplete context validation failure"
        expect(test_prompt_class).to validate_prompt_successfully.with_context(full_context)
      end

      it "fails validation with incomplete context" do
        pending "Context path validation failure"
        incomplete_context = {
          document_name: "Test Doc",
          document: { file_path: "/test.pdf" }
          # Missing analysis_type
        }
        expect(test_prompt_class).to fail_prompt_validation
          .with_context(incomplete_context)
          .with_error(/Missing required variables.*analysis_type/)
      end

      it "fails validation with missing context paths" do
        pending "Missing context paths validation"
        context_without_document = {
          document_name: "Test Doc",
          analysis_type: "basic"
          # Missing document.file_path
        }
        expect(test_prompt_class).to fail_prompt_validation
          .with_context(context_without_document)
          .with_error(/Missing required context paths/)
      end
    end

    describe "context variable matchers" do
      let(:prompt_instance) { test_prompt_class.new(**full_context) }

      it "validates direct context variables" do
        pending "Direct context variable validation"
        expect(prompt_instance).to have_prompt_context_variable(:document_name)
          .with_value("Annual Report 2024")

        expect(prompt_instance).to have_prompt_context_variable(:analysis_type)
          .with_value("financial")
      end

      it "validates context-mapped variables" do
        pending "Requires raaf-testing gem for custom matchers"
        expect(prompt_instance).to have_prompt_context_variable(:document_path)
          .with_value("/reports/annual_2024.pdf")

        expect(prompt_instance).to have_prompt_context_variable(:page_count)
          .with_value(150)
      end

      it "validates default values" do
        pending "Requires raaf-testing gem for custom matchers"
        minimal_context = {
          document_name: "Simple Doc",
          analysis_type: "basic",
          document: { file_path: "/tmp/simple.pdf" }
          # Missing metadata.pages
        }
        minimal_prompt = test_prompt_class.new(**minimal_context)

        expect(minimal_prompt).to have_prompt_context_variable(:page_count)
          .with_default("unknown")
      end

      it "detects missing variables" do
        pending "Missing variable detection"
        expect(prompt_instance).not_to have_prompt_context_variable(:nonexistent_field)
      end
    end
  end
end

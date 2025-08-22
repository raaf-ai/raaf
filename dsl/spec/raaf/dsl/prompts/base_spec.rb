# frozen_string_literal: true

require_relative "../../../spec_helper"

RSpec.describe RAAF::DSL::Prompts::Base do
  let(:simple_context) { { document_name: "Test Document", analysis_depth: "comprehensive" } }

  it_behaves_like "a base class"
  it_behaves_like "a prompt class"

  describe "initialization" do
    it "accepts keyword arguments as context" do
      expect { described_class.new(**simple_context) }.not_to raise_error
    end

    it "stores context" do
      instance = described_class.new(**simple_context)
      expect(instance.context).to eq(simple_context)
    end

    it "accepts context_variables parameter" do
      context_vars = double("ContextVariables")
      instance = described_class.new(context_variables: context_vars)
      expect(instance.context_variables).to eq(context_vars)
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

  describe "context access via method_missing" do
    let(:instance) { described_class.new(**simple_context) }

    it "provides direct access to context keys" do
      expect(instance.document_name).to eq("Test Document")
      expect(instance.analysis_depth).to eq("comprehensive")
    end

    it "raises NoMethodError for missing context keys" do
      expect { instance.nonexistent_key }.to raise_error(NoMethodError)
    end

    it "raises NoMethodError for invalid method calls with arguments" do
      expect { instance.invalid_method_with_args(1, 2, 3) }.to raise_error(NoMethodError)
    end
  end

  describe "respond_to_missing?" do
    let(:instance) { described_class.new(**simple_context) }

    it "responds to context keys" do
      expect(instance.respond_to?(:document_name)).to be true
      expect(instance.respond_to?(:analysis_depth)).to be true
    end

    it "does not respond to non-context keys" do
      expect(instance.respond_to?(:nonexistent_key)).to be false
    end
  end

  describe "dry run validation" do
    let(:test_prompt_class) do
      Class.new(described_class) do
        def system
          "System prompt for #{document_name} with #{analysis_type}"
        end

        def user
          "User prompt for #{document_name}"
        end
      end
    end

    it "performs dry run validation without errors when all variables are available" do
      instance = test_prompt_class.new(document_name: "Test", analysis_type: "basic")
      expect { instance.dry_run_validation! }.not_to raise_error
    end

    it "detects missing variables during dry run" do
      instance = test_prompt_class.new(document_name: "Test")
      expect { instance.dry_run_validation! }.to raise_error(RAAF::DSL::Error, /Missing variables.*analysis_type/)
    end
  end

  describe "validate_context" do
    let(:test_prompt_class) do
      Class.new(described_class) do
        def system
          "System prompt for #{document_name}"
        end

        def user
          "User prompt"
        end
      end
    end

    it "returns true when context is valid" do
      instance = test_prompt_class.new(document_name: "Test")
      expect(instance.validate_context).to be true
    end

    it "returns false when context is invalid" do
      instance = test_prompt_class.new({}) # Missing document_name
      expect(instance.validate_context).to be false
    end
  end
end
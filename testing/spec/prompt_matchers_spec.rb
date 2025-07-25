# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::Testing::PromptMatchers do
  # Mock prompt class for testing matchers
  let(:test_prompt_class) do
    Class.new(RAAF::DSL::Prompts::Base) do
      requires :document_name, :analysis_type
      optional :priority_level
      requires_from_context :document_path, path: [:document, :file_path]
      optional_from_context :page_count, path: [:document, :metadata, :pages], default: "unknown"

      def system
        <<~SYSTEM
          Analyzing #{document_name} using #{analysis_type} analysis.
          Location: #{document_path}
          Pages: #{page_count}
          #{"Priority: #{priority_level}" if priority_level}
        SYSTEM
      end

      def user
        "Please analyze #{document_name}."
      end
    end
  end

  let(:valid_context) do
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

  let(:minimal_context) do
    {
      document_name: "Test Document",
      analysis_type: "basic",
      document: { file_path: "/test.pdf" }
    }
  end

  describe "include_prompt_content matcher" do
    context "with prompt class" do
      it "matches content in rendered prompts" do
        expect(test_prompt_class).to include_prompt_content(
          "Annual Report 2024", "financial", "/reports/annual_2024.pdf", "150"
        ).with_context(valid_context)
      end

      it "matches content in specific prompt types" do
        expect(test_prompt_class).to include_prompt_content("Analyzing")
          .in_prompt(:system)
          .with_context(valid_context)

        expect(test_prompt_class).to include_prompt_content("Please analyze")
          .in_prompt(:user)
          .with_context(valid_context)
      end

      it "supports regex patterns" do
        expect(test_prompt_class).to include_prompt_content(/Annual.*Report.*\d{4}/)
          .with_context(valid_context)
      end

      it "validates optional content presence" do
        expect(test_prompt_class).to include_prompt_content("Priority: high")
          .with_context(valid_context)

        # Test without priority
        expect(test_prompt_class).not_to include_prompt_content("Priority:")
          .with_context(minimal_context)
      end

      it "requires context when testing prompt class" do
        expect {
          expect(test_prompt_class).to include_prompt_content("content")
        }.to raise_error(ArgumentError, /Context required when testing prompt class/)
      end
    end

    context "with prompt instance" do
      let(:prompt_instance) { test_prompt_class.new(**valid_context) }

      it "matches content in rendered prompts" do
        expect(prompt_instance).to include_prompt_content(
          "Annual Report 2024", "financial"
        )
      end

      it "rejects context when testing instance" do
        expect {
          expect(prompt_instance).to include_prompt_content("content")
            .with_context(valid_context)
        }.to raise_error(ArgumentError, /Context should not be provided/)
      end
    end

    context "failure cases" do
      it "provides helpful error messages when content is missing" do
        expect {
          expect(test_prompt_class).to include_prompt_content("Missing Content")
            .with_context(valid_context)
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
          expect(error.message).to include("Expected prompt to include: \"Missing Content\"")
          expect(error.message).to include("Missing content: \"Missing Content\"")
          expect(error.message).to include("Rendered content:")
        end
      end
    end
  end

  describe "validate_prompt_successfully matcher" do
    context "with valid context" do
      it "passes when prompt validates successfully" do
        expect(test_prompt_class).to validate_prompt_successfully
          .with_context(valid_context)
      end

      it "works with prompt instances" do
        prompt = test_prompt_class.new(**valid_context)
        expect(prompt).to validate_prompt_successfully
      end
    end

    context "with invalid context" do
      it "fails when required variables are missing" do
        expect(test_prompt_class).not_to validate_prompt_successfully
          .with_context({ document_name: "Test" })
      end

      it "provides helpful error messages" do
        expect {
          expect(test_prompt_class).to validate_prompt_successfully
            .with_context({ document_name: "Test" })
        }.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
          expect(error.message).to include("validation failed with:")
          expect(error.message).to include("analysis_type")
        end
      end
    end
  end

  describe "fail_prompt_validation matcher" do
    it "passes when validation fails as expected" do
      expect(test_prompt_class).to fail_prompt_validation
        .with_context({ document_name: "Test" })
    end

    it "can match specific error messages" do
      expect(test_prompt_class).to fail_prompt_validation
        .with_context({ document_name: "Test" })
        .with_error(/Missing required variables.*analysis_type/)
    end

    it "fails when validation unexpectedly succeeds" do
      expect {
        expect(test_prompt_class).to fail_prompt_validation
          .with_context(valid_context)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
        expect(error.message).to include("Expected prompt validation to fail")
        expect(error.message).to include("but it succeeded")
      end
    end
  end

  describe "have_prompt_context_variable matcher" do
    let(:prompt_instance) { test_prompt_class.new(**valid_context) }

    it "passes when variable exists" do
      expect(prompt_instance).to have_prompt_context_variable(:document_name)
    end

    it "can validate variable values" do
      expect(prompt_instance).to have_prompt_context_variable(:document_name)
        .with_value("Annual Report 2024")
    end

    it "can validate default values" do
      minimal_prompt = test_prompt_class.new(**minimal_context)
      expect(minimal_prompt).to have_prompt_context_variable(:page_count)
        .with_value("unknown")
    end

    it "fails when variable doesn't exist" do
      expect {
        expect(prompt_instance).to have_prompt_context_variable(:nonexistent)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
        expect(error.message).to include("Expected prompt to have context variable :nonexistent")
      end
    end

    it "fails when value doesn't match" do
      expect {
        expect(prompt_instance).to have_prompt_context_variable(:document_name)
          .with_value("Wrong Value")
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
        expect(error.message).to include("Expected context variable :document_name to have value")
        expect(error.message).to include("\"Wrong Value\"")
        expect(error.message).to include("\"Annual Report 2024\"")
      end
    end
  end

  describe "matcher descriptions" do
    it "provides meaningful descriptions for include_prompt_content" do
      matcher = include_prompt_content("test")
      expect(matcher.description).to eq('include "test" in prompts')

      matcher = include_prompt_content("test").in_prompt(:system)
      expect(matcher.description).to eq('include "test" in system prompt')
    end

    it "provides meaningful descriptions for validate_prompt_successfully" do
      matcher = validate_prompt_successfully
      expect(matcher.description).to eq("validate successfully")
    end

    it "provides meaningful descriptions for fail_prompt_validation" do
      matcher = fail_prompt_validation
      expect(matcher.description).to eq("fail validation")

      matcher = fail_prompt_validation.with_error("test error")
      expect(matcher.description).to eq('fail validation with error "test error"')
    end

    it "provides meaningful descriptions for have_prompt_context_variable" do
      matcher = have_prompt_context_variable(:test_var)
      expect(matcher.description).to eq("have context variable :test_var")

      matcher = have_prompt_context_variable(:test_var).with_value("test")
      expect(matcher.description).to eq('have context variable :test_var with value "test"')
    end
  end
end
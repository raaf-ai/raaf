# frozen_string_literal: true

# Example demonstrating the custom prompt matchers
# This file shows real-world usage patterns for testing AI Agent DSL prompts

require_relative "../spec/spec_helper"

# Example prompt class for testing
class DocumentAnalysisPrompt < RAAF::DSL::Prompts::Base

  required :document_name, :analysis_type
  optional :urgency_level
  required :document_path, path: %i[document file_path]
  optional :page_count, path: %i[document metadata pages], default: "unknown"

  contract_mode :strict

  def system
    <<~SYSTEM
      You are a professional document analyst specializing in #{analysis_type} analysis.

      Document: #{document_name}
      Location: #{document_path}
      Pages: #{page_count}
      #{"Priority: #{context[:urgency_level]}" if context[:urgency_level]}

      Provide thorough, accurate analysis following industry standards.
    SYSTEM
  end

  def user
    <<~USER
      Please perform #{analysis_type} analysis on #{document_name}.
      #{"This is #{context[:urgency_level]} priority." if context[:urgency_level]}

      Focus on key insights and actionable recommendations.
    USER
  end

end

# Example test class demonstrating all matcher capabilities
RSpec.describe DocumentAnalysisPrompt do
  let(:basic_context) do
    {
      document_name: "Annual Financial Report 2024",
      analysis_type: "financial",
      document: {
        file_path: "/documents/annual_report_2024.pdf",
        metadata: {
          pages: 150
        }
      }
    }
  end

  let(:urgent_context) do
    basic_context.merge(urgency_level: "high")
  end

  describe "content validation" do
    it "includes required document information" do
      # Test with prompt class and context
      expect(described_class).to expect_prompt_to_include("Annual Financial Report 2024")
        .with_context(basic_context)

      # Test multiple content expectations
      expect(described_class).to expect_prompt_to_include(
        "financial analysis",
        "150",
        "/documents/annual_report_2024.pdf"
      ).with_context(basic_context)
    end

    it "includes urgency information when provided" do
      expect(described_class).to expect_prompt_to_include("high priority")
        .with_context(urgent_context)
    end

    it "excludes urgency information when not provided" do
      expect(described_class).not_to expect_prompt_to_include("priority")
        .with_context(basic_context)
    end

    it "validates content in specific prompt sections" do
      expect(described_class).to expect_prompt_to_include("professional document analyst")
        .in_prompt(:system)
        .with_context(basic_context)

      expect(described_class).to expect_prompt_to_include("Please perform")
        .in_prompt(:user)
        .with_context(basic_context)
    end

    it "supports regex patterns for flexible matching" do
      expect(described_class).to expect_prompt_to_include(/Annual.*Report.*\d{4}/)
        .with_context(basic_context)

      expect(described_class).to expect_prompt_to_include(/Pages: \d+/)
        .in_prompt(:system)
        .with_context(basic_context)
    end
  end

  describe "validation testing" do
    it "validates successfully with complete context" do
      expect(described_class).to validate_successfully.with_context(basic_context)
    end

    it "fails validation with missing required fields" do
      incomplete_context = {
        document_name: "Test Doc",
        document: { file_path: "/test.pdf" }
        # Missing analysis_type
      }

      expect(described_class).to fail_validation
        .with_context(incomplete_context)
        .with_error(/Missing required variables.*analysis_type/)
    end

    it "fails validation with missing context paths" do
      context_without_document = {
        document_name: "Test Doc",
        analysis_type: "basic"
        # Missing document.file_path
      }

      expect(described_class).to fail_validation
        .with_context(context_without_document)
        .with_error(/Missing required context paths/)
    end

    it "validates with instance after creation" do
      prompt = described_class.new(**basic_context)
      expect(prompt).to validate_successfully
    end
  end

  describe "context variable access" do
    let(:prompt) { described_class.new(**basic_context) }

    it "provides access to direct context variables" do
      expect(prompt).to have_context_variable(:document_name)
        .with_value("Annual Financial Report 2024")

      expect(prompt).to have_context_variable(:analysis_type)
        .with_value("financial")
    end

    it "provides access to context-mapped variables" do
      expect(prompt).to have_context_variable(:document_path)
        .with_value("/documents/annual_report_2024.pdf")

      expect(prompt).to have_context_variable(:page_count)
        .with_value(150)
    end

    it "uses default values for missing optional context" do
      minimal_context = {
        document_name: "Minimal Doc",
        analysis_type: "basic",
        document: { file_path: "/tmp/doc.pdf" }
        # Missing metadata.pages
      }

      minimal_prompt = described_class.new(**minimal_context)
      expect(minimal_prompt).to have_context_variable(:page_count)
        .with_default("unknown")
    end

    it "fails for non-existent variables" do
      expect(prompt).not_to have_context_variable(:nonexistent_field)
    end
  end

  describe "real-world testing scenarios" do
    it "tests complete prompt flow" do
      # Validate that prompt can be created and rendered
      expect(described_class).to validate_successfully.with_context(basic_context)

      # Test that all required content is present
      expect(described_class).to expect_prompt_to_include(
        "Annual Financial Report 2024",
        "financial analysis",
        "/documents/annual_report_2024.pdf",
        "150"
      ).with_context(basic_context)

      # Test that content appears in correct sections
      expect(described_class).to expect_prompt_to_include("professional document analyst")
        .in_prompt(:system)
        .with_context(basic_context)

      expect(described_class).to expect_prompt_to_include("actionable recommendations")
        .in_prompt(:user)
        .with_context(basic_context)
    end

    it "handles edge cases gracefully" do
      # Test with minimum required context
      minimal_context = {
        document_name: "Simple Doc",
        analysis_type: "basic",
        document: { file_path: "/tmp/simple.pdf" }
      }

      expect(described_class).to validate_successfully.with_context(minimal_context)
      expect(described_class).to expect_prompt_to_include("Simple Doc")
        .with_context(minimal_context)
      expect(described_class).to expect_prompt_to_include("unknown")
        .with_context(minimal_context) # Default page_count
    end

    it "validates error handling" do
      # Test various validation failure scenarios
      expect(described_class).to fail_validation.with_context({})

      expect(described_class).to fail_validation
        .with_context({
                        document_name: "Test",
                        document: { file_path: "/test.pdf" }
                        # Missing analysis_type
                      })
        .with_error(/Missing required variables/)

      expect(described_class).to fail_validation
        .with_context({
                        document_name: "Test",
                        analysis_type: "basic"
                      })
        .with_error(/Missing required context paths/)
    end
  end

  describe "performance and caching" do
    let(:prompt) { described_class.new(**basic_context) }

    it "caches context-mapped values efficiently" do
      # First access should compute the value
      value1 = prompt.document_path

      # Second access should return cached value (same object)
      value2 = prompt.document_path

      expect(value1).to be(value2)
      expect(prompt).to have_context_variable(:document_path)
        .with_value("/documents/annual_report_2024.pdf")
    end
  end
end

puts "Example prompt matcher tests defined!"
puts "Run with: bundle exec rspec examples/prompt_matcher_examples.rb"

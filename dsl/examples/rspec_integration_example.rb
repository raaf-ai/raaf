#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating how to use AI Agent DSL RSpec matchers in a real project
#
# This example shows the complete setup and usage of the RSpec matchers
# that are now part of the AI Agent DSL gem.

require "bundler/setup"
require "ai_agent_dsl"
require "rspec"
require "ai_agent_dsl/rspec"

# Example prompt class for a document processing application
class ReportAnalysisPrompt < RAAF::DSL::Prompts::Base
  required :report_name, :analysis_type
  optional :urgency, :department
  required :file_path, path: %i[document path]
  optional :file_size, path: %i[document metadata size], default: "unknown"
  optional :author, path: %i[document metadata author]

  contract_mode :strict

  def system
    <<~SYSTEM
      You are a professional business analyst specializing in #{analysis_type} analysis.

      Report: #{report_name}
      File: #{file_path}
      Size: #{file_size}
      #{"Author: #{author}" if author}
      #{"Department: #{context[:department]}" if context[:department]}
      #{"Urgency: #{context[:urgency]}" if context[:urgency]}

      Provide detailed, actionable insights based on the data.
    SYSTEM
  end

  def user
    prompt = "Please perform #{analysis_type} analysis on #{report_name}."
    prompt += " This is #{context[:urgency]} priority." if context[:urgency]
    prompt += " Focus on #{context[:department]} concerns." if context[:department]
    prompt
  end
end

# Test suite demonstrating all matcher capabilities
RSpec.describe ReportAnalysisPrompt do
  let(:base_context) do
    {
      report_name: "Q4 Financial Report",
      analysis_type: "financial",
      document: {
        path: "/reports/q4_financial.pdf",
        metadata: {
          size: "2.5MB",
          author: "Finance Team"
        }
      }
    }
  end

  let(:urgent_context) do
    base_context.merge(
      urgency: "high",
      department: "executive"
    )
  end

  describe "content validation using new matchers" do
    it "validates core content is present" do
      # Test multiple content inclusions at once
      expect(described_class).to include_prompt_content(
        "Q4 Financial Report",
        "financial analysis",
        "/reports/q4_financial.pdf",
        "2.5MB",
        "Finance Team"
      ).with_context(base_context)
    end

    it "validates content appears in correct prompt sections" do
      # Test system prompt content
      expect(described_class).to include_prompt_content(
        "professional business analyst",
        "File:",
        "Size:"
      ).in_prompt(:system).with_context(base_context)

      # Test user prompt content
      expect(described_class).to include_prompt_content(
        "Please perform",
        "analysis on"
      ).in_prompt(:user).with_context(base_context)
    end

    it "validates optional content handling" do
      # With urgency and department
      expect(described_class).to include_prompt_content(
        "Urgency: high",
        "Department: executive",
        "high priority",
        "executive concerns"
      ).with_context(urgent_context)

      # Without optional fields
      expect(described_class).not_to include_prompt_content(
        "Urgency:",
        "Department:",
        "priority",
        "concerns"
      ).with_context(base_context)
    end

    it "supports flexible pattern matching" do
      # Regex patterns for dynamic content
      expect(described_class).to include_prompt_content(
        /Q\d+.*Report/,           # Quarter pattern
        /\d+\.\d+MB/,             # File size pattern
        /analysis.*on.*Report/    # Analysis instruction pattern
      ).with_context(base_context)
    end
  end

  describe "validation testing using new matchers" do
    it "validates successfully with complete context" do
      expect(described_class).to validate_prompt_successfully.with_context(base_context)
      expect(described_class).to validate_prompt_successfully.with_context(urgent_context)
    end

    it "fails validation appropriately" do
      # Missing required regular variables
      incomplete_context = {
        report_name: "Test Report",
        document: { path: "/test.pdf", metadata: {} }
        # Missing analysis_type
      }
      expect(described_class).to fail_prompt_validation
        .with_context(incomplete_context)
        .with_error(/Missing required variables.*analysis_type/)

      # Missing required context paths
      no_document_context = {
        report_name: "Test Report",
        analysis_type: "basic"
        # Missing document.path
      }
      expect(described_class).to fail_prompt_validation
        .with_context(no_document_context)
        .with_error(/Missing required context paths/)
    end
  end

  describe "context variable access using new matchers" do
    let(:prompt_instance) { described_class.new(**base_context) }

    it "validates direct context variables" do
      expect(prompt_instance).to have_prompt_context_variable(:report_name)
        .with_value("Q4 Financial Report")

      expect(prompt_instance).to have_prompt_context_variable(:analysis_type)
        .with_value("financial")
    end

    it "validates context-mapped variables" do
      expect(prompt_instance).to have_prompt_context_variable(:file_path)
        .with_value("/reports/q4_financial.pdf")

      expect(prompt_instance).to have_prompt_context_variable(:file_size)
        .with_value("2.5MB")

      expect(prompt_instance).to have_prompt_context_variable(:author)
        .with_value("Finance Team")
    end

    it "validates default values for missing optional context" do
      minimal_context = {
        report_name: "Simple Report",
        analysis_type: "basic",
        document: { path: "/simple.pdf", metadata: {} }
        # Missing metadata.size and metadata.author
      }
      minimal_prompt = described_class.new(**minimal_context)

      expect(minimal_prompt).to have_prompt_context_variable(:file_size)
        .with_default("unknown")

      # Author should be nil when not provided (optional context variable)
      expect(minimal_prompt).to have_prompt_context_variable(:author)
        .with_value(nil)
    end
  end

  describe "integration with standard RSpec" do
    it "combines custom matchers with standard expectations" do
      # Standard RSpec setup
      prompt = described_class.new(**urgent_context)
      expect(prompt).to be_a(ReportAnalysisPrompt)
      expect(prompt.context).to include(:report_name, :analysis_type)

      # Custom matchers
      expect(prompt).to validate_prompt_successfully
      expect(prompt).to have_prompt_context_variable(:report_name)

      # Standard RSpec on rendered content
      messages = prompt.render_messages
      expect(messages).to have_key(:system)
      expect(messages).to have_key(:user)
      expect(messages[:system]).to be_a(String)
      expect(messages[:user]).to be_a(String)

      # Custom matchers on the same instance
      expect(described_class).to include_prompt_content("Q4 Financial Report")
        .with_context(urgent_context)
    end
  end

  describe "real-world testing scenarios" do
    it "tests complete workflow from creation to rendering" do
      # 1. Validate the prompt can be created with valid context
      expect(described_class).to validate_prompt_successfully.with_context(base_context)

      # 2. Validate all expected content is present
      expect(described_class).to include_prompt_content(
        "Q4 Financial Report", "financial", "professional business analyst",
        "actionable insights", "Please perform"
      ).with_context(base_context)

      # 3. Validate content organization
      expect(described_class).to include_prompt_content("You are a professional")
        .in_prompt(:system).with_context(base_context)

      # 4. Validate optional features work correctly
      expect(described_class).to include_prompt_content("high priority")
        .with_context(urgent_context)

      expect(described_class).not_to include_prompt_content("priority")
        .with_context(base_context)
    end

    it "handles edge cases and error conditions" do
      # Test with minimal valid context
      minimal_context = {
        report_name: "Basic Report",
        analysis_type: "summary",
        document: { path: "/basic.pdf", metadata: {} }
      }

      expect(described_class).to validate_prompt_successfully.with_context(minimal_context)
      expect(described_class).to include_prompt_content("Basic Report", "summary")
        .with_context(minimal_context)

      # Test validation failures
      expect(described_class).to fail_prompt_validation.with_context({})
      expect(described_class).to fail_prompt_validation
        .with_context({ report_name: "Test" })
        .with_error(/Missing required/)
    end
  end
end

# Run the tests if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  puts "🧪 Running AI Agent DSL RSpec Integration Example"
  puts "=" * 60

  # Configure RSpec
  RSpec.configure do |config|
    config.formatter = :documentation
    config.color = true
  end

  # Run the tests
  RSpec::Core::Runner.run([__FILE__])
end

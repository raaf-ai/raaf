#!/usr/bin/env ruby
# frozen_string_literal: true

# Prompts Example
#
# This example demonstrates how to use the flexible prompt system
# with validation, context mapping, and different contract modes.

require_relative "../lib/raaf-dsl"

# Example 1: Basic prompt with required and optional variables
class CustomerServicePrompt < RAAF::DSL::Prompts::Base
  required :customer_name, :issue_type
  optional :language, default: "English"
  optional :tone, default: "professional"
  
  def system
    <<~SYSTEM
      You are a customer service representative.
      Respond in #{language} with a #{tone} tone.
      You are specialized in handling #{issue_type} issues.
    SYSTEM
  end
  
  def user
    "Help customer #{customer_name} with their issue."
  end
end

# Example 2: Prompt with context mapping for nested data
class AnalysisPrompt < RAAF::DSL::Prompts::Base
  # Map nested context paths to flat variables
  required :doc_name, path: %i[document metadata name]
  required :doc_type, path: %i[document metadata type]
  optional :author, path: %i[document metadata author], default: "Unknown"
  optional :pages, path: %i[document structure page_count]
  
  # Use strict contract mode to catch extra variables
  contract_mode :strict
  
  def system
    "You are analyzing a #{doc_type} document: '#{doc_name}' by #{author}."
  end
  
  def user
    analysis = "Please analyze this document."
    analysis += " The document has #{pages} pages." if pages
    analysis
  end
end

# Example 3: Dynamic prompt with conditional content
class ReportPrompt < RAAF::DSL::Prompts::Base
  required :report_type, :data_source
  optional :time_period
  optional :metrics, default: []
  optional :format, default: "summary"
  
  # Use lenient mode to allow extra context
  contract_mode :lenient
  
  def system
    <<~SYSTEM
      You are a data analyst creating a #{report_type} report.
      Data source: #{data_source}
      Output format: #{format}
    SYSTEM
  end
  
  def user
    sections = ["Generate a #{report_type} report"]
    
    sections << "Time period: #{time_period}" if time_period
    sections << "Focus on metrics: #{metrics.join(', ')}" if metrics.any?
    
    sections.join("\n")
  end
end

# Demonstrate usage
puts "=== Customer Service Prompt ==="
cs_prompt = CustomerServicePrompt.new(
  customer_name: "John Smith",
  issue_type: "billing"
)
puts cs_prompt.render(:system)
puts "\nUser: #{cs_prompt.render(:user)}"

# Override defaults
puts "\n=== Customer Service Prompt (French) ==="
cs_prompt_fr = CustomerServicePrompt.new(
  customer_name: "Marie Dubois",
  issue_type: "technical",
  language: "French",
  tone: "friendly"
)
puts cs_prompt_fr.render(:system)

# Nested context example
puts "\n=== Analysis Prompt with Nested Context ==="
nested_context = {
  document: {
    metadata: {
      name: "Q3 Financial Report",
      type: "financial report",
      author: "Finance Team"
    },
    structure: {
      page_count: 42
    }
  }
}

analysis_prompt = AnalysisPrompt.new(**nested_context)
puts analysis_prompt.render(:system)
puts "\nUser: #{analysis_prompt.render(:user)}"

# Dynamic prompt example
puts "\n=== Dynamic Report Prompt ==="
report_prompt = ReportPrompt.new(
  report_type: "sales performance",
  data_source: "CRM Database",
  time_period: "Q3 2024",
  metrics: ["revenue", "conversion rate", "customer acquisition"],
  format: "detailed analysis"
)
puts report_prompt.render(:system)
puts "\nUser: #{report_prompt.render(:user)}"

# Demonstrate validation
puts "\n=== Validation Examples ==="

# This will work (lenient mode allows extra fields)
begin
  lenient_prompt = ReportPrompt.new(
    report_type: "test",
    data_source: "test db",
    extra_field: "This is allowed in lenient mode"
  )
  lenient_prompt.validate!
  puts "✓ Lenient mode accepts extra fields"
rescue => e
  puts "✗ Error: #{e.message}"
end

# This will fail (strict mode rejects extra fields)
begin
  strict_prompt = AnalysisPrompt.new(
    document: { metadata: { name: "Test", type: "test" } },
    extra_field: "This will cause an error"
  )
  strict_prompt.validate!
  puts "✓ Validation passed"
rescue RAAF::DSL::Prompts::VariableContractError => e
  puts "✗ Strict mode validation failed: #{e.message}"
end

# This will fail (missing required field)
begin
  invalid_prompt = CustomerServicePrompt.new(
    customer_name: "Test User"
    # Missing issue_type
  )
  invalid_prompt.validate!
  puts "✓ Validation passed"
rescue RAAF::DSL::Prompts::VariableContractError => e
  puts "✗ Missing required field: #{e.message}"
end
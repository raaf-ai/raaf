#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating schema definition in prompt classes
#
# This example shows how to define schemas directly in prompt classes
# using the same Complex Nested Schema DSL available in agent classes.

require_relative "../lib/ai_agent_dsl"

# Example 1: Simple prompt with basic schema
class UserExtractionPrompt < AiAgentDsl::Prompts::Base
  requires :text_content

  # Define schema using the same DSL as agents
  schema do
    field :name, type: :string, required: true
    field :age, type: :integer, range: 0..150, required: true
    field :email, type: :string, required: false
    field :confidence, type: :integer, range: 0..100, required: true
  end

  def system
    <<~SYSTEM
      You are an expert at extracting user information from text.
      Extract the user's name, age, email, and provide a confidence score.
    SYSTEM
  end

  def user
    <<~USER
      Extract user information from this text:
      #{text_content}
    USER
  end
end

# Example 2: Complex nested schema for company analysis
class CompanyAnalysisPrompt < AiAgentDsl::Prompts::Base
  requires :company_name, :analysis_criteria

  # Complex nested schema with objects and arrays
  schema do
    field :company_analysis, type: :object, required: true do
      field :name, type: :string, required: true
      field :industry, type: :string, required: true
      field :founded_year, type: :integer, range: 1800..2024
      field :headquarters, type: :object do
        field :city, type: :string, required: true
        field :country, type: :string, required: true
        field :coordinates, type: :object do
          field :latitude, type: :number
          field :longitude, type: :number
        end
      end
      field :business_metrics, type: :object, required: true do
        field :revenue_estimate, type: :string
        field :employee_count_range, type: :string, enum: ["1-10", "11-50", "51-200", "201-500", "500+"]
        field :growth_stage, type: :string, enum: ["startup", "growth", "mature", "enterprise"]
      end
    end

    field :analysis_scores, type: :array, required: true do
      field :criterion, type: :string, required: true
      field :score, type: :integer, range: 0..100, required: true
      field :reasoning, type: :string, required: true
      field :evidence, type: :array, items_type: :string, min_items: 1
    end

    field :summary, type: :object, required: true do
      field :overall_score, type: :integer, range: 0..100, required: true
      field :key_strengths, type: :array, items_type: :string, required: true
      field :potential_concerns, type: :array, items_type: :string
      field :recommendation, type: :string, enum: ["highly_recommended", "recommended", "neutral", "not_recommended"]
    end

    field :data_sources, type: :array, items_type: :string, required: true
    field :analysis_confidence, type: :integer, range: 0..100, required: true
    field :last_updated, type: :string, required: true
  end

  def system
    <<~SYSTEM
      You are a business analyst specializing in company research and evaluation.
      Provide comprehensive analysis based on the given criteria.

      Always include data sources and confidence levels for your analysis.
    SYSTEM
  end

  def user
    <<~USER
      Analyze #{company_name} based on these criteria:
      #{analysis_criteria.map { |c| "- #{c}" }.join("\n")}

      Provide detailed analysis with scoring and evidence.
    USER
  end
end

# Example 3: Agent using prompt with schema
class CompanyAnalysisAgent < AiAgentDsl::Agents::Base
  include AiAgentDsl::AgentDsl

  agent_name "CompanyAnalyst"
  model "gpt-4o"
  max_turns 3

  # Use prompt class with schema - no schema defined in agent
  prompt_class CompanyAnalysisPrompt

  def initialize(context: {}, processing_params: {})
    super
  end
end

# Example 4: Demonstration of schema conflict detection
class ConflictingAgent < AiAgentDsl::Agents::Base
  include AiAgentDsl::AgentDsl

  agent_name "ConflictingAgent"
  prompt_class UserExtractionPrompt # This prompt has a schema

  # This will cause an error - schema defined in both places
  schema do
    field :different_field, type: :string
  end

  def initialize(context: {}, processing_params: {})
    super
  end
end

# Demo the functionality
if __FILE__ == $PROGRAM_NAME
  puts "🔧 Prompt Schema Examples\n\n"

  # Example 1: Simple prompt schema
  puts "1. Simple User Extraction Prompt Schema:"
  user_prompt = UserExtractionPrompt.new(text_content: "John Doe, 30 years old, john@example.com")
  puts "   Schema defined: #{user_prompt.has_schema?}"
  puts "   Schema: #{user_prompt.schema}"
  puts

  # Example 2: Complex company analysis schema
  puts "2. Complex Company Analysis Prompt Schema:"
  company_prompt = CompanyAnalysisPrompt.new(
    company_name:      "TechCorp Inc",
    analysis_criteria: ["Market position", "Financial health", "Innovation"]
  )
  puts "   Schema defined: #{company_prompt.has_schema?}"
  puts "   Schema properties: #{company_prompt.schema[:properties].keys}"
  puts

  # Example 3: Agent using prompt schema
  puts "3. Agent using Prompt Schema:"
  begin
    agent = CompanyAnalysisAgent.new(
      context: {
        company_name:      "TechCorp Inc",
        analysis_criteria: ["Market position", "Financial health"]
      }
    )
    puts "   ✅ Agent created successfully"
    puts "   Agent schema source: Prompt class (#{agent.class._prompt_config[:class].name})"
    puts "   Agent schema: #{agent.build_schema[:properties].keys}"
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end
  puts

  # Example 4: Schema conflict detection
  puts "4. Schema Conflict Detection:"
  begin
    conflicting_agent = ConflictingAgent.new
    # This will fail when build_schema is called
    conflicting_agent.build_schema
  rescue ArgumentError => e
    puts "   ✅ Conflict detected: #{e.message}"
  rescue StandardError => e
    puts "   ❌ Unexpected error: #{e.message}"
  end
  puts

  puts "🎉 Prompt schema examples completed!"
end

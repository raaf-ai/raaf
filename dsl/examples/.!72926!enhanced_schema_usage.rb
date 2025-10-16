# frozen_string_literal: true

# Enhanced RAAF DSL Schema Builder Usage Examples
#
# This file demonstrates the new RAAF DSL schema builder capabilities
# that dramatically reduce agent code verbosity by automatically generating
# schemas from Active Record models and providing semantic types.

require "raaf-dsl"

# Example 1: Before and After Comparison
puts "=== BEFORE: Verbose Manual Schema (100+ lines) ==="
puts <<~VERBOSE_SCHEMA
  # OLD WAY: Manual schema definition (example of what we're replacing)
  schema do
    field :markets, type: :array do
      items type: :object do
        field :id, type: :integer, required: true
        field :market_name, type: :string, required: true
        field :overall_score, type: :integer, minimum: 0, maximum: 100, required: true
        field :market_description, type: :string
        field :market_characteristics, type: :object do
          field :size, type: :string
          field :growth_rate, type: :number, minimum: 0, maximum: 100
          field :competition, type: :string
          # ... 50+ more lines for complete Market schema
        end
        field :scoring, type: :object do
          field :product_market_fit, type: :integer, minimum: 0, maximum: 100
          field :market_size_potential, type: :integer, minimum: 0, maximum: 100
          field :competition_level, type: :integer, minimum: 0, maximum: 100
          field :entry_difficulty, type: :integer, minimum: 0, maximum: 100
          field :revenue_opportunity, type: :integer, minimum: 0, maximum: 100
          field :strategic_alignment, type: :integer, minimum: 0, maximum: 100
        end
        field :search_terms, type: :array do
          items type: :object do
            field :category, type: :string, required: true
            field :terms, type: :array do
              items type: :string
            end
          end
        end
      end
    end
  end
VERBOSE_SCHEMA

puts "\n=== AFTER: Concise Schema Builder (3 lines) ==="
puts <<~CONCISE_SCHEMA
  # NEW WAY: Model introspection + semantic types
  schema model: Market do
    override :overall_score, type: :score  # Use semantic type with 0-100 validation
    field :insights, :text                 # Add agent-specific field
  end
CONCISE_SCHEMA

# Example 2: Semantic Types Showcase
puts "\n=== Semantic Types Available ==="

semantic_examples = {
  email: "user@example.com",
  url: "https://example.com",
  percentage: 85.5,
  currency: 29.99,
  phone: "+1234567890",
  score: 95,
  naics_code: "541511"
}

semantic_examples.each do |type, example_value|
  type_def = RAAF::DSL::Types.define(type)
  valid = RAAF::DSL::Types.valid?(example_value, type_def)
  puts "#{type.to_s.ljust(15)}: #{type_def[:type].to_s.ljust(8)} #{valid ? '' : ''} Example: #{example_value}"
end

# Example 3: Agent Implementation Pattern
puts "\n=== Agent Implementation Example ==="
puts <<~AGENT_EXAMPLE
  # Modern RAAF agent with enhanced schema builder
  class Market::Analysis < Ai::Agents::ApplicationAgent
    agent_name "MarketAnalysisAgent"
    model "gpt-5"


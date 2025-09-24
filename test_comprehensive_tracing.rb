#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'tracing/lib/raaf-tracing'
require_relative 'dsl/lib/raaf-dsl'

puts "🧪 TESTING COMPREHENSIVE TRACING DEBUG"

# Mock product and company
mock_product = Struct.new(:name, :description).new("Test Product", "A test product")
mock_company = Struct.new(:name, :description).new("Test Company", "A test company")

# Create test agent classes with tracing
class TestMarketAnalysis
  include RAAF::Tracing::Traceable
  trace_as :agent

  def initialize(name: "MarketAnalysis", product: nil, company: nil, parent_component: nil)
    @name = name
    @product = product
    @company = company
    @parent_component = parent_component
  end

  attr_reader :name, :product, :company

  def self.required_fields
    []  # No requirements for testing
  end

  def self.requirements_met?(context)
    true  # Always meets requirements for testing
  end

  def call
    puts "🧪 MarketAnalysis agent called"
    { success: true, analysis: "Market analysis complete" }
  end
end

class TestMarketScoring
  include RAAF::Tracing::Traceable
  trace_as :agent

  def initialize(name: "MarketScoring", product: nil, company: nil, parent_component: nil)
    @name = name
    @product = product
    @company = company
    @parent_component = parent_component
  end

  attr_reader :name, :product, :company

  def self.required_fields
    [:market_data]  # Requires market data that won't be available
  end

  def self.requirements_met?(context)
    puts "🧪 MarketScoring checking requirements: #{context.respond_to?(:keys) ? context.keys : 'no keys'}"
    false  # Deliberately fail to test skipping
  end

  def call
    puts "🧪 MarketScoring agent called (shouldn't happen)"
    { success: true, scoring: "Market scoring complete" }
  end
end

class TestPipeline
  include RAAF::Tracing::Traceable
  trace_as :pipeline

  def initialize(product: nil, company: nil)
    @name = "TestPipeline"
    @product = product
    @company = company
  end

  attr_reader :name, :product, :company

  def run
    puts "🧪 TestPipeline starting execution"

    # Create context
    context = RAAF::DSL::ContextVariables.new
    context = context.set(:product, @product)
    context = context.set(:company, @company)
    context = context.set(:pipeline_instance, self)

    puts "🧪 TestPipeline context created with keys: #{context.keys}"

    # Test direct agent execution with tracing hierarchy
    with_tracing(:execute_pipeline) do
      puts "🧪 Inside pipeline tracing block"

      # Execute first agent (should work)
      puts "\n🧪 === EXECUTING MARKET ANALYSIS ==="
      agent1 = TestMarketAnalysis.new(
        product: @product,
        company: @company,
        parent_component: self
      )

      agent1.with_tracing(:execute, agent_name: "MarketAnalysis") do
        puts "🧪 Inside MarketAnalysis tracing block"
        result1 = agent1.call
        puts "🧪 MarketAnalysis result: #{result1}"
      end

      # Execute second agent (should be skipped due to requirements)
      puts "\n🧪 === EXECUTING MARKET SCORING ==="
      agent2 = TestMarketScoring.new(
        product: @product,
        company: @company,
        parent_component: self
      )

      # Check if requirements met first
      if TestMarketScoring.requirements_met?(context)
        puts "🧪 MarketScoring requirements met, executing..."
        agent2.with_tracing(:execute, agent_name: "MarketScoring") do
          puts "🧪 Inside MarketScoring tracing block"
          result2 = agent2.call
          puts "🧪 MarketScoring result: #{result2}"
        end
      else
        puts "🧪 MarketScoring requirements NOT met, creating skipped span..."
        self.with_tracing(:agent_skipped,
                         agent_name: "MarketScoring",
                         "agent.status" => "skipped",
                         "agent.skip_reason" => "requirements_not_met",
                         "agent.required_fields" => TestMarketScoring.required_fields.join(", "),
                         "agent.available_fields" => context.keys.join(", ")) do
          puts "🧪 Inside skipped agent span"
          nil
        end
      end

      puts "🧪 Pipeline execution complete"
      { success: true, pipeline: "TestPipeline complete" }
    end
  end
end

# Run the test
puts "\n🧪 === STARTING PIPELINE TEST ==="
pipeline = TestPipeline.new(product: mock_product, company: mock_company)
result = pipeline.run
puts "\n🧪 Final result: #{result}"

puts "\n🧪 TEST COMPLETE"
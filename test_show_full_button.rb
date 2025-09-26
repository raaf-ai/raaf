#!/usr/bin/env ruby

require_relative 'core/lib/raaf'
require_relative 'tracing/lib/raaf-tracing'

# Create a large data structure to test the show full button
large_data = {
  "markets" => Array.new(50) do |i|
    {
      "market_name" => "Market #{i + 1}",
      "market_description" => "This is a detailed description for market #{i + 1}. " * 20,
      "characteristics" => {
        "size" => "Large",
        "growth_rate" => "15%",
        "competition_level" => "Medium",
        "entry_barriers" => "Moderate",
        "detailed_analysis" => "This is a very long analysis text that should trigger the truncation feature. " * 50
      },
      "opportunities" => Array.new(10) do |j|
        {
          "opportunity_name" => "Opportunity #{i}-#{j}",
          "value_proposition" => "Value proposition for opportunity #{i}-#{j}. " * 15,
          "implementation_details" => "Implementation details that are quite long. " * 30
        }
      end
    }
  end,
  "analysis_metadata" => {
    "total_markets_analyzed" => 50,
    "analysis_depth" => "comprehensive",
    "data_sources" => Array.new(20) { |i| "Source #{i + 1}" },
    "detailed_methodology" => "This is a comprehensive methodology description. " * 100
  }
}

# Set up tracing
processor = RAAF::Tracing::ActiveRecordProcessor.new
tracer = RAAF::Tracing::SpanTracer.new
tracer.add_processor(processor)

# Create a span with large data
RAAF::Tracing.with_span("test_large_data_span", attributes: large_data) do
  puts "Created span with large data for testing the show full button"
  puts "Data size: #{JSON.generate(large_data).length} characters"
  sleep 1
end

puts "Span created. Check the tracing dashboard to test the show full button."
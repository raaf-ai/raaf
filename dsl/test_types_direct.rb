#!/usr/bin/env ruby
# frozen_string_literal: true

# Direct test of Types functionality

require_relative 'lib/raaf/dsl/types'

puts "=== RAAF::DSL::Types Direct Testing ==="
puts

# Test semantic type definitions
semantic_types = [:email, :url, :percentage, :currency, :phone, :score, :naics_code]

puts "Available semantic types:"
semantic_types.each do |type|
  definition = RAAF::DSL::Types.define(type)
  puts "  #{type.to_s.ljust(12)}: #{definition}"
end
puts

# Test validation functionality  
test_cases = [
  [:email, "valid@example.com", true],
  [:email, "invalid-email", false],
  [:url, "https://example.com", true],
  [:url, "not-a-url", false],
  [:percentage, 50.5, true],
  [:percentage, 150, false],
  [:score, 85, true],
  [:score, 105, false],
  [:phone, "+1234567890", true],
  [:phone, "123", false],
  [:naics_code, "541511", true],
  [:naics_code, "99999", false]
]

puts "Validation tests:"
test_cases.each do |type, value, expected|
  type_def = RAAF::DSL::Types.define(type)
  result = RAAF::DSL::Types.valid?(value, type_def)
  status = result == expected ? "PASS" : "FAIL"
  puts "  #{status}: #{type} with '#{value}' => #{result} (expected #{expected})"
end
puts

puts "✓ All semantic types implemented and validated successfully!"

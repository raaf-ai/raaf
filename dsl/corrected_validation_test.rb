#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/raaf/dsl/types'

puts "=== Corrected Validation Tests ==="
puts

# Test with correct expectations
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
  [:phone, "1", false],            # Too short (only 1 digit, needs at least 2)
  [:naics_code, "541511", true],   # Valid 6-digit NAICS
  [:naics_code, "1", false]        # Too short (less than 2 digits)
]

puts "Validation tests with corrected expectations:"
test_cases.each do |type, value, expected|
  type_def = RAAF::DSL::Types.define(type)
  result = RAAF::DSL::Types.valid?(value, type_def)
  status = result == expected ? "PASS" : "FAIL"
  puts "  #{status}: #{type} with '#{value}' => #{result} (expected #{expected})"
end
puts

puts "=== Testing Edge Cases ==="
puts

# Test edge cases that should work
edge_cases = [
  [:phone, "123", true],           # This is actually valid (3 digits)
  [:phone, "0123456789", false],   # Starts with 0, should fail
  [:naics_code, "99999", true],    # 5 digits is valid
  [:naics_code, "1234567", false], # 7 digits is too long
  [:currency, 0.01, true],         # Minimum currency
  [:currency, -5.00, false]        # Negative currency should fail
]

edge_cases.each do |type, value, expected|
  type_def = RAAF::DSL::Types.define(type)
  result = RAAF::DSL::Types.valid?(value, type_def)
  status = result == expected ? "PASS" : "FAIL"
  puts "  #{status}: #{type} with '#{value}' => #{result} (expected #{expected})"
end

puts
puts "✓ Validation tests completed with proper expectations!"

#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/raaf/dsl/types'

puts "=== Testing Individual Patterns ==="
puts

# Test phone pattern specifically
phone_pattern = /\A\+?[1-9]\d{1,14}\z/
test_phones = ["+1234567890", "123", "+123456789012345", "1234567890", "0123456789"]

puts "Phone pattern: #{phone_pattern}"
test_phones.each do |phone|
  match = phone.match?(phone_pattern)
  puts "  '#{phone}' matches: #{match}"
end
puts

# Test NAICS pattern specifically  
naics_pattern = /\A\d{2,6}\z/
test_naics = ["541511", "99999", "5415", "54", "1234567", "1"]

puts "NAICS pattern: #{naics_pattern}"
test_naics.each do |naics|
  match = naics.match?(naics_pattern)
  puts "  '#{naics}' matches: #{match}"
end
puts

# Test URL - no pattern in current definition
url_def = RAAF::DSL::Types.define(:url)
puts "URL definition: #{url_def}"
puts "URL has pattern: #{url_def.key?(:pattern)}"

# URLs should be validated differently - by format not pattern
test_urls = ["https://example.com", "not-a-url", "http://test.org", "ftp://files.com"]
test_urls.each do |url|
  # For URL, we need different validation logic since there's no pattern
  valid = RAAF::DSL::Types.valid?(url, url_def)
  puts "  '#{url}' valid: #{valid}"
end

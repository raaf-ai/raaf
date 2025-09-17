#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/raaf/dsl/types'

# Debug specific validation failures
puts "=== Debugging Validation Issues ==="
puts

# Test URL validation
url_def = RAAF::DSL::Types.define(:url)
puts "URL definition: #{url_def}"
puts "Valid URL test: #{RAAF::DSL::Types.valid?('https://example.com', url_def)}"
puts "Invalid URL test: #{RAAF::DSL::Types.valid?('not-a-url', url_def)}"
puts

# Test phone validation  
phone_def = RAAF::DSL::Types.define(:phone)
puts "Phone definition: #{phone_def}"
puts "Valid phone test: #{RAAF::DSL::Types.valid?('+1234567890', phone_def)}"
puts "Invalid phone test: #{RAAF::DSL::Types.valid?('123', phone_def)}"
puts "Phone pattern match for '123': #{'123'.match?(phone_def[:pattern])}"
puts

# Test NAICS validation
naics_def = RAAF::DSL::Types.define(:naics_code)
puts "NAICS definition: #{naics_def}"
puts "Valid NAICS test: #{RAAF::DSL::Types.valid?('541511', naics_def)}"
puts "Invalid NAICS test: #{RAAF::DSL::Types.valid?('99999', naics_def)}"
puts "NAICS pattern match for '99999': #{'99999'.match?(naics_def[:pattern])}"

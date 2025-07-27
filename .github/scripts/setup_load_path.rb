#!/usr/bin/env ruby
# frozen_string_literal: true

# This script sets up the Ruby load path to simulate installed RAAF gems
# by adding all gem lib directories to $LOAD_PATH

# Get the root directory (parent of .github)
root_dir = File.expand_path("../..", __dir__)

# List of RAAF gems in dependency order
RAAF_GEMS = %w[
  core
  tracing
  memory
  guardrails
  providers
  tools
  dsl
  rails
  analytics
  compliance
  debug
  misc
  streaming
].freeze

# Add each gem's lib directory to the load path
RAAF_GEMS.each do |gem|
  lib_path = File.join(root_dir, gem, "lib")
  if File.directory?(lib_path)
    $LOAD_PATH.unshift(lib_path)
    puts "Added to load path: #{lib_path}"
  else
    puts "Warning: Directory not found: #{lib_path}"
  end
end

# Also add the main raaf gem lib if it exists
main_lib = File.join(root_dir, "lib")
if File.directory?(main_lib)
  $LOAD_PATH.unshift(main_lib)
  puts "Added to load path: #{main_lib}"
end

puts "\nLoad path setup complete. You can now use 'require' statements as if gems were installed."
puts "Example: require 'raaf-core' or require 'raaf-providers'"
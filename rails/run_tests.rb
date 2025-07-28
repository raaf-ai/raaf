#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test runner that bypasses the matrix gem requirement

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("spec", __dir__))

require "minimal_spec_helper"
require "raaf_rails_spec"

# Run the tests
exit_code = RSpec::Core::Runner.run([])
exit(exit_code)

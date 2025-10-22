# frozen_string_literal: true

require "zeitwerk"
require "raaf-core"

# Load version before Zeitwerk setup
require_relative "raaf/guardrails/version"

# Set up Zeitwerk loader for RAAF guardrails
loader = Zeitwerk::Loader.for_gem
loader.tag = "raaf-guardrails"

# Setup the loader
loader.setup

module RAAF
  module Guardrails
    # Zeitwerk will autoload all classes and modules
  end
end

# Eager load if requested
loader.eager_load if ENV['RAAF_EAGER_LOAD'] == 'true'

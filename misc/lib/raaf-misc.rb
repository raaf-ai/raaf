# frozen_string_literal: true

require "zeitwerk"
require "raaf-core"

# Load version before Zeitwerk setup
require_relative "raaf/misc/version"

# Set up Zeitwerk loader for RAAF misc
loader = Zeitwerk::Loader.for_gem
loader.tag = "raaf-misc"

# Setup the loader
loader.setup

module RAAF
  module Misc
    # Zeitwerk will autoload all classes and modules
  end
end

# Eager load if requested
loader.eager_load if ENV['RAAF_EAGER_LOAD'] == 'true'

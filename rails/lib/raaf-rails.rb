# frozen_string_literal: true

require "zeitwerk"
require "raaf-core"
require "raaf-memory"
require "raaf-tracing"
require "rails"

# Load version before Zeitwerk setup
require_relative "raaf/rails/version"

# Set up Zeitwerk loader for RAAF Rails
loader = Zeitwerk::Loader.for_gem
loader.tag = "raaf-rails"

# Setup the loader
loader.setup

module RAAF
  module Rails
    # Zeitwerk will autoload all classes and modules
  end
end

# Load the Rails engine
require "raaf/rails/engine" if defined?(::Rails::Engine)

# Eager load if requested
loader.eager_load if ENV['RAAF_EAGER_LOAD'] == 'true'

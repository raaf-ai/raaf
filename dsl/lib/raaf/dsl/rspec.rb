# frozen_string_literal: true

# RSpec integration for AI Agent DSL
#
# This module provides RSpec integration for testing AI Agent DSL components.
#
# Note: All matchers have been moved to the raaf-testing gem.
# Use `require 'raaf-testing'` to access all testing matchers.
#
# @example Basic setup
#   # In your spec_helper.rb or rails_helper.rb
#   require 'raaf-testing' # For all matchers including agent and prompt matchers
#
# @since 0.1.0
module RAAF
  module DSL
    module RSpec
      # This module is kept for backwards compatibility
      # All matchers have been moved to the raaf-testing gem
      # Please use `require 'raaf-testing'` instead
    end
  end
end

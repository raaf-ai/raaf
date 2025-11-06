# frozen_string_literal: true

require "rspec"
require "rspec/expectations"
require_relative "../eval"
require_relative "rspec/helpers"
require_relative "rspec/dsl"
require_relative "rspec/evaluation_runner"
require_relative "rspec/configuration"
require_relative "rspec/matchers"

module RAAF
  module Eval
    ##
    # RSpec integration module for RAAF Eval
    #
    # This module provides RSpec integration including:
    # - Custom matchers for evaluation assertions
    # - DSL for defining evaluation scenarios
    # - Helpers for span selection and evaluation execution
    # - Configuration for CI/CD integration
    #
    # @example Basic usage
    #   RSpec.configure do |config|
    #     config.include RAAF::Eval::RSpec, type: :evaluation
    #   end
    #
    # @example Auto-include for evaluation specs
    #   RSpec.configure do |config|
    #     config.define_derived_metadata(file_path: %r{/spec/evaluations/}) do |metadata|
    #       metadata[:type] = :evaluation
    #     end
    #     config.include RAAF::Eval::RSpec, type: :evaluation
    #   end
    module RSpec
      class << self
        ##
        # Returns the RSpec-specific configuration
        #
        # @return [RAAF::Eval::RSpec::Configuration]
        def configuration
          @configuration ||= Configuration.new
        end

        ##
        # Configures RSpec integration
        #
        # @yield [Configuration] the configuration object
        def configure
          yield(configuration) if block_given?
        end

        ##
        # Included hook to extend RSpec with evaluation capabilities
        #
        # @param base [Module] the including class/module
        def included(base)
          base.include Helpers
          base.extend DSL::ClassMethods
          base.include DSL::InstanceMethods
        end
      end
    end
  end
end

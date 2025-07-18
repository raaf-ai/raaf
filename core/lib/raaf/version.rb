# frozen_string_literal: true

##
# Ruby AI Agents Factory - Version Information
#
# This module contains version constants and metadata for the Ruby AI Agents Factory gem.
# The gem provides a complete Ruby implementation of AI Agents with 100% feature
# parity with the Python SDK, plus additional enterprise-grade capabilities.
#
# == Version Strategy
#
# The gem follows semantic versioning (SemVer) principles:
# - MAJOR: Breaking API changes that require code updates
# - MINOR: New features that are backwards compatible
# - PATCH: Bug fixes and small improvements
#
# == Compatibility
#
# This Ruby implementation maintains structural alignment with the Python RAAF SDK:
# - Identical APIs and endpoints
# - Compatible tracing formats
# - Matching response structures
#
# @example Check version programmatically
#   puts "Ruby AI Agents Factory v#{RAAF::VERSION}"
#   # => "Ruby AI Agents Factory v0.1.0"
#
# @example Version comparison
#   require 'gem'
#   current = Gem::Version.new(RAAF::VERSION)
#   minimum = Gem::Version.new("0.1.0")
#   puts "Compatible!" if current >= minimum
#
# @author Ruby AI Agents Factory Team
# @since 0.1.0
# @see https://github.com/raaf-ai/ruby-ai-agents-factory Repository and changelog
module RAAF

  ##
  # Current version of the Ruby AI Agents Factory gem
  #
  # This constant contains the semantic version string for the current release.
  # Use this for version checks, logging, and compatibility validation.
  #
  # @return [String] the version string in semantic versioning format (MAJOR.MINOR.PATCH)
  #
  # @example Access version
  #   RAAF::VERSION
  #   # => "0.1.0"
  #
  # @example Use in logging
  #   logger.info("Starting Ruby AI Agents Factory v#{RAAF::VERSION}")
  #
  # @example Version-dependent features
  #   if Gem::Version.new(RAAF::VERSION) >= Gem::Version.new("0.2.0")
  #     # Use new feature available in 0.2.0+
  #   end
  VERSION = "0.1.0"

end

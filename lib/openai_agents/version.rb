# frozen_string_literal: true

##
# OpenAI Agents Ruby - Version Information
#
# This module contains version constants and metadata for the OpenAI Agents Ruby gem.
# The gem provides a complete Ruby implementation of OpenAI Agents with 100% feature
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
# This Ruby implementation maintains structural alignment with the Python OpenAI Agents SDK:
# - Identical APIs and endpoints
# - Compatible tracing formats
# - Matching response structures
#
# @example Check version programmatically
#   puts "OpenAI Agents Ruby v#{OpenAIAgents::VERSION}"
#   # => "OpenAI Agents Ruby v0.1.0"
#
# @example Version comparison
#   require 'gem'
#   current = Gem::Version.new(OpenAIAgents::VERSION)
#   minimum = Gem::Version.new("0.1.0")
#   puts "Compatible!" if current >= minimum
#
# @author OpenAI Agents Ruby Team
# @since 0.1.0
# @see https://github.com/openai/openai-agents-ruby Repository and changelog
module OpenAIAgents
  ##
  # Current version of the OpenAI Agents Ruby gem
  #
  # This constant contains the semantic version string for the current release.
  # Use this for version checks, logging, and compatibility validation.
  #
  # @return [String] the version string in semantic versioning format (MAJOR.MINOR.PATCH)
  #
  # @example Access version
  #   OpenAIAgents::VERSION
  #   # => "0.1.0"
  #
  # @example Use in logging
  #   logger.info("Starting OpenAI Agents v#{OpenAIAgents::VERSION}")
  #
  # @example Version-dependent features
  #   if Gem::Version.new(OpenAIAgents::VERSION) >= Gem::Version.new("0.2.0")
  #     # Use new feature available in 0.2.0+
  #   end
  VERSION = "0.1.0"
end

# frozen_string_literal: true

module AiAgentDsl
  # Version information for the AI Agent DSL gem
  #
  # This constant defines the current version of the gem following
  # semantic versioning (SemVer) conventions:
  # - MAJOR version when you make incompatible API changes
  # - MINOR version when you add functionality in a backwards compatible manner
  # - PATCH version when you make backwards compatible bug fixes
  #
  # @example Accessing the version
  #   AiAgentDsl::VERSION  # => "0.1.0"
  #
  # @example Version comparison
  #   Gem::Version.new(AiAgentDsl::VERSION) >= Gem::Version.new("0.1.0")
  #
  # @see https://semver.org/ Semantic Versioning specification
  # @since 0.1.0
  #
  VERSION = "0.2.0"
end

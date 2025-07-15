# frozen_string_literal: true

require_relative "lib/raaf/tools/basic/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-tools-basic"
  spec.version = RubyAIAgentsFactory::Tools::Basic::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "Basic tools and utilities for Ruby AI Agents Factory"
  spec.description = "Provides essential tools and utilities for AI agents including text processing, file operations, web scraping, API calls, data manipulation, and common utility functions."
  spec.homepage = "https://github.com/raaf-ai/ruby-ai-agents-factory"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/raaf-ai/ruby-ai-agents-factory"
  spec.metadata["changelog_uri"] = "https://github.com/raaf-ai/ruby-ai-agents-factory/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "base64", "~> 0.1"
  spec.add_dependency "chronic", "~> 0.10"
  spec.add_dependency "csv", "~> 3.0"
  spec.add_dependency "digest", "~> 3.1"
  spec.add_dependency "faraday", "~> 2.7"
  spec.add_dependency "fileutils", "~> 1.7"
  spec.add_dependency "httparty", "~> 0.21"
  spec.add_dependency "json", "~> 2.0"
  spec.add_dependency "mail", "~> 2.8"
  spec.add_dependency "nokogiri", "~> 1.13"
  spec.add_dependency "raaf-core", "~> 1.0"
  spec.add_dependency "raaf-logging", "~> 1.0"
  spec.add_dependency "securerandom", "~> 0.2"
  spec.add_dependency "uri", "~> 0.12"
  spec.add_dependency "yaml", "~> 0.2"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"
  spec.add_development_dependency "vcr", "~> 6.1"
  spec.add_development_dependency "webmock", "~> 3.18"
end

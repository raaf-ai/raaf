# frozen_string_literal: true

require_relative "lib/raaf/tools/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-tools"
  spec.version = RAAF::Tools::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "Comprehensive tools for Ruby AI Agents Factory"
  spec.description = "Provides complete toolkit for AI agents including basic utilities, web search, file operations, advanced enterprise tools, code interpretation, and computer control capabilities."
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
  # Core dependencies
  spec.add_dependency "raaf-core", "0.1.0"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "json", "~> 2.0"
  spec.add_dependency "nokogiri", "~> 1.13"
  
  # Basic tools dependencies
  spec.add_dependency "base64", "~> 0.1"
  spec.add_dependency "chronic", "~> 0.10"
  spec.add_dependency "csv", "~> 3.0"
  spec.add_dependency "digest", "~> 3.1"
  spec.add_dependency "fileutils", "~> 1.7"
  spec.add_dependency "httparty", "~> 0.21"
  spec.add_dependency "mail", "~> 2.8"
  spec.add_dependency "securerandom", "~> 0.2"
  spec.add_dependency "uri", "~> 0.12"
  spec.add_dependency "yaml", "~> 0.2"
  
  # Advanced tools dependencies
  spec.add_dependency "aws-sdk-s3", "~> 1.0"
  spec.add_dependency "docx", "~> 0.8"
  spec.add_dependency "google-cloud-storage", "~> 1.0"
  spec.add_dependency "jwt", "~> 2.0"
  spec.add_dependency "pdf-reader", "~> 2.0"
  spec.add_dependency "pg", "~> 1.0"
  spec.add_dependency "ruby-openai", "~> 7.0"
  spec.add_dependency "selenium-webdriver", "~> 4.0"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"
  spec.add_development_dependency "vcr", "~> 6.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end
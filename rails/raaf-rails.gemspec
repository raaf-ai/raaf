# frozen_string_literal: true

require_relative "lib/raaf/rails/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-rails"
  spec.version = RAAF::Rails::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "Rails integration and web interface for Ruby AI Agents Factory"
  spec.description = "Provides Rails integration, web interface, and dashboard for managing AI agents. Includes authentication, monitoring, and deployment tools for production Rails applications."
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
  spec.add_dependency "ostruct", "~> 0.5" # Required for Ruby 3.5+ compatibility
  spec.add_dependency "raaf-core", "~> 0.1"
  spec.add_dependency "raaf-memory", "~> 0.1"
  spec.add_dependency "raaf-tracing", "~> 0.1"
  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "stimulus-rails", "~> 1.0"
  spec.add_dependency "turbo-rails", "~> 1.0"

  # Development dependencies
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "capybara"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rspec_junit_formatter"
  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-rails"
  spec.add_development_dependency "rubocop-rake"
  spec.add_development_dependency "rubocop-rspec"
  spec.add_development_dependency "selenium-webdriver"
end

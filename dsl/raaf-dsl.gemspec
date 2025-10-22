# frozen_string_literal: true

require_relative "lib/raaf/dsl/core/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-dsl"
  spec.version = RAAF::DSL::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "Domain-specific language for Ruby AI Agents Factory"
  spec.description = "Provides a powerful DSL for defining AI agents, workflows, tools, and configurations with intuitive syntax and advanced features like agent composition, conditional logic, and declarative programming."
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
  spec.add_dependency "activesupport", "~> 8.0"
  spec.add_dependency "ast", "~> 2.4"
  spec.add_dependency "binding_of_caller", "~> 1.0"
  spec.add_dependency "concurrent-ruby", "~> 1.0"
  spec.add_dependency "erb", "~> 4.0"
  spec.add_dependency "json", "~> 2.0"
  spec.add_dependency "method_source", "~> 1.0"
  spec.add_dependency "parser", "~> 3.2"
  spec.add_dependency "raaf-core", "~> 0.1"
  spec.add_dependency "yaml", "~> 0.2"
  spec.add_dependency "zeitwerk", "~> 2.6"

  # Development dependencies
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "parser"
  # NOTE: raaf-testing is included via Gemfile path reference
  # spec.add_development_dependency "raaf-testing", "~> 0.1"
  spec.add_development_dependency "rails", "~> 8.0"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rspec_junit_formatter"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-rake"
  spec.add_development_dependency "rubocop-rspec"
end

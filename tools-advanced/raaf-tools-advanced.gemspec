# frozen_string_literal: true

require_relative "lib/raaf/tools/advanced/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-tools-advanced"
  spec.version = RubyAIAgentsFactory::Tools::Advanced::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "Advanced enterprise tools for Ruby AI Agents Factory"
  spec.description = "Provides advanced enterprise-grade tools for AI agents including computer control, document processing, code interpretation, and specialized enterprise integrations."
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
  spec.add_dependency "aws-sdk-s3", "~> 1.0"
  spec.add_dependency "docx", "~> 0.8"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "google-cloud-storage", "~> 1.0"
  spec.add_dependency "jwt", "~> 2.0"
  spec.add_dependency "mysql2", "~> 0.5"
  spec.add_dependency "nokogiri", "~> 1.0"
  spec.add_dependency "pdf-reader", "~> 2.0"
  spec.add_dependency "pg", "~> 1.0"
  spec.add_dependency "raaf-core", "~> 1.0"
  spec.add_dependency "raaf-tools", "~> 1.0"
  spec.add_dependency "redis", "~> 4.0"
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

# frozen_string_literal: true

require_relative "lib/raaf/guardrails/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-guardrails"
  spec.version = RAAF::Guardrails::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "Safety validation and content filtering for Ruby AI Agents Factory"
  spec.description = "Provides comprehensive safety validation, content filtering, and guardrails for AI agents including toxicity detection, PII filtering, prompt injection prevention, and custom safety rules."
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
  spec.add_dependency "addressable", "~> 2.8"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "json", "~> 2.0"
  spec.add_dependency "raaf-core", "0.1.0"
  spec.add_dependency "ruby-openai", "~> 7.0"
  spec.add_dependency "unicode-display_width", "~> 2.0"

  # Optional dependencies for specific providers
  spec.add_development_dependency "aws-sdk-comprehend", "~> 1.0"
  spec.add_development_dependency "azure-cognitiveservices-contentmoderator", "~> 0.1"
  spec.add_development_dependency "google-cloud-dlp", "~> 1.0"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"
  spec.add_development_dependency "vcr", "~> 6.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end

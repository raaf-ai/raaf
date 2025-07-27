# frozen_string_literal: true

require_relative "lib/raaf/compliance/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-compliance"
  spec.version = RAAF::Compliance::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "Regulatory compliance and audit capabilities for Ruby AI Agents Factory"
  spec.description = "Provides comprehensive compliance framework including GDPR, HIPAA, SOC2, audit trails, data retention policies, and regulatory reporting for AI agents."
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
  spec.add_dependency "activerecord", ">= 7.0", "< 9.0"
  spec.add_dependency "chronic", "~> 0.10"
  spec.add_dependency "csv", "~> 3.0"
  spec.add_dependency "digest", "~> 3.0"
  spec.add_dependency "json", "~> 2.0"
  spec.add_dependency "openssl", "~> 3.0"
  spec.add_dependency "pg", "~> 1.0"
  spec.add_dependency "prawn", "~> 2.4"
  spec.add_dependency "prawn-table", "~> 0.2"
  spec.add_dependency "raaf-core", "0.1.0"
  spec.add_dependency "rubyzip", "~> 2.3"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "factory_bot", "~> 6.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"
  spec.add_development_dependency "timecop", "~> 0.9"
end

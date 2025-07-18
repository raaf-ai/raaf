# frozen_string_literal: true

require_relative "lib/raaf/version"

Gem::Specification.new do |spec|
  spec.name = "raaf"
  spec.version = RAAF::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "Ruby AI Agents Factory - Complete AI Agent Framework"
  spec.description = <<~DESC
    Ruby AI Agents Factory (RAAF) is a comprehensive Ruby framework for building sophisticated 
    multi-agent AI workflows with enterprise-grade features. This main gem includes all 
    components: core framework, providers, tools, guardrails, tracing, streaming, memory 
    management, Rails integration, and more.
  DESC
  spec.homepage = "https://github.com/raaf-ai/ruby-ai-agents-factory"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/raaf-ai/ruby-ai-agents-factory"
  spec.metadata["changelog_uri"] = "https://github.com/raaf-ai/ruby-ai-agents-factory/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://docs.raaf.ai"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core Dependencies - All RAAF subgems
  spec.add_dependency "raaf-core", "~> #{RAAF::VERSION}"
  spec.add_dependency "raaf-providers", "~> #{RAAF::VERSION}"
  spec.add_dependency "raaf-dsl", "~> #{RAAF::VERSION}"
  spec.add_dependency "raaf-tools", "~> #{RAAF::VERSION}"
  spec.add_dependency "raaf-guardrails", "~> #{RAAF::VERSION}"
  spec.add_dependency "raaf-tracing", "~> #{RAAF::VERSION}"
  spec.add_dependency "raaf-memory", "~> #{RAAF::VERSION}"
  spec.add_dependency "raaf-streaming", "~> #{RAAF::VERSION}"
  spec.add_dependency "raaf-testing", "~> #{RAAF::VERSION}"
  spec.add_dependency "raaf-misc", "~> #{RAAF::VERSION}"
  spec.add_dependency "raaf-compliance", "~> #{RAAF::VERSION}"
  spec.add_dependency "raaf-debug", "~> #{RAAF::VERSION}"

  # Optional Dependencies - Rails integration
  spec.add_dependency "raaf-rails", "~> #{RAAF::VERSION}"

  # Development Dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "yard", "~> 0.9"
  spec.add_development_dependency "redcarpet", "~> 3.5"
  spec.add_development_dependency "simplecov", "~> 0.21"
  spec.add_development_dependency "pry", "~> 0.14"
  spec.add_development_dependency "pry-byebug", "~> 3.10"
  spec.add_development_dependency "factory_bot", "~> 6.2"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "vcr", "~> 6.1"
  spec.add_development_dependency "timecop", "~> 0.9"
end
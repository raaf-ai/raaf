# frozen_string_literal: true

require_relative "lib/raaf/debug/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-debug"
  spec.version = RubyAIAgentsFactory::Debug::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "Advanced debugging and development utilities for Ruby AI Agents Factory"
  spec.description = "Provides comprehensive debugging tools including request tracing, performance profiling, interactive debugging, log analysis, and development utilities for AI agents."
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
  spec.add_dependency "benchmark", "~> 0.2"
  spec.add_dependency "chronic", "~> 0.10"
  spec.add_dependency "colorize", "~> 0.8"
  spec.add_dependency "csv", "~> 3.0"
  spec.add_dependency "get_process_mem", "~> 0.2"
  spec.add_dependency "json", "~> 2.0"
  spec.add_dependency "memory_profiler", "~> 1.0"
  spec.add_dependency "pry", "~> 0.14"
  spec.add_dependency "pry-byebug", "~> 3.10"
  spec.add_dependency "raaf-core", "~> 1.0"
  spec.add_dependency "raaf-logging", "~> 1.0"
  spec.add_dependency "ruby-prof", "~> 1.4"
  spec.add_dependency "stackprof", "~> 0.2"
  spec.add_dependency "terminal-table", "~> 3.0"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"
end

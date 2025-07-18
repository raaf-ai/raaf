# frozen_string_literal: true

require_relative "lib/raaf/tracing/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-tracing"
  spec.version = RAAF::Tracing::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "Distributed tracing, monitoring, and visualization for Ruby AI Agents Factory"
  spec.description = "Provides comprehensive distributed tracing, monitoring, observability, and visualization for AI agent workflows. Includes span-based tracking, performance metrics, trace visualization, and integration with popular monitoring platforms."
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
  spec.add_dependency "json", "~> 2.0"
  spec.add_dependency "opentelemetry-api", "~> 1.0"
  spec.add_dependency "opentelemetry-exporter-otlp", "~> 0.20"
  spec.add_dependency "opentelemetry-instrumentation-net_http", "~> 0.20"
  spec.add_dependency "opentelemetry-sdk", "~> 1.0"
  spec.add_dependency "raaf-core", "0.1.0"
  
  # Visualization dependencies
  spec.add_dependency "csv", "~> 3.0"
  spec.add_dependency "descriptive_statistics", "~> 2.5"
  spec.add_dependency "erb", "~> 4.0"
  spec.add_dependency "gruff", "~> 0.19"
  spec.add_dependency "matrix", "~> 0.4"
  spec.add_dependency "mini_magick", "~> 4.11"
  spec.add_dependency "numo-gnuplot", "~> 0.2"
  spec.add_dependency "prawn", "~> 2.4"
  spec.add_dependency "prawn-svg", "~> 0.32"
  spec.add_dependency "rmagick", "~> 4.2"
  spec.add_dependency "ruby-plot", "~> 0.6"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"
end

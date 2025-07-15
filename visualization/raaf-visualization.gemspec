# frozen_string_literal: true

require_relative "lib/raaf/visualization/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-visualization"
  spec.version = RubyAIAgentsFactory::Visualization::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "Data visualization and analytics for Ruby AI Agents Factory"
  spec.description = "Provides comprehensive data visualization tools including charts, graphs, dashboards, and analytics for AI agents performance monitoring, conversation analysis, and business intelligence."
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
  spec.add_dependency "csv", "~> 3.0"
  spec.add_dependency "descriptive_statistics", "~> 2.5"
  spec.add_dependency "erb", "~> 4.0"
  spec.add_dependency "gruff", "~> 0.19"
  spec.add_dependency "json", "~> 2.0"
  spec.add_dependency "matrix", "~> 0.4"
  spec.add_dependency "mini_magick", "~> 4.11"
  spec.add_dependency "numo-gnuplot", "~> 0.2"
  spec.add_dependency "prawn", "~> 2.4"
  spec.add_dependency "prawn-svg", "~> 0.32"
  spec.add_dependency "raaf-core", "~> 1.0"
  spec.add_dependency "raaf-logging", "~> 1.0"
  spec.add_dependency "rmagick", "~> 4.2"
  spec.add_dependency "ruby-plot", "~> 0.6"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"
end

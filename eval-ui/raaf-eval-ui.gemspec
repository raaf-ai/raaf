# frozen_string_literal: true

require_relative "lib/raaf/eval/ui/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-eval-ui"
  spec.version = RAAF::Eval::UI::VERSION
  spec.authors = ["RAAF Team"]
  spec.email = ["team@raaf.dev"]

  spec.summary = "Web UI for RAAF Eval interactive evaluation"
  spec.description = "Standalone Rails engine providing web interface for RAAF evaluation system, including span browsing, prompt editing, evaluation execution, and results comparison"
  spec.homepage = "https://github.com/raaf-ai/ruby-ai-agents-factory"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/raaf-ai/ruby-ai-agents-factory"
  spec.metadata["changelog_uri"] = "https://github.com/raaf-ai/ruby-ai-agents-factory/blob/main/eval-ui/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z 2>/dev/null || find . -type f -print0`.split("\x0").reject do |f|
      f.match?(%r{\A(?:test|spec|features|bin|\.git)/})
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core dependencies
  spec.add_dependency "rails", ">= 7.0"

  # UI framework dependencies
  spec.add_dependency "phlex", "~> 2.0"
  spec.add_dependency "phlex-rails", "~> 2.0"
  spec.add_dependency "stimulus-rails", "~> 1.2"
  spec.add_dependency "turbo-rails", "~> 1.4"
  spec.add_dependency "importmap-rails", "~> 1.2"

  # Diff generation
  spec.add_dependency "diff-lcs", "~> 1.5"
  spec.add_dependency "diffy", "~> 3.4"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "capybara", "~> 3.0"
  spec.add_development_dependency "factory_bot_rails", "~> 6.2"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "rubocop-rails", "~> 2.0"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"
  spec.add_development_dependency "selenium-webdriver", "~> 4.0"
  spec.add_development_dependency "simplecov", "~> 0.21"
end

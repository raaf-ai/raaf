# frozen_string_literal: true

require_relative "lib/raaf/eval/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-eval"
  spec.version = RAAF::Eval::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "AI agent evaluation and testing framework for RAAF"
  spec.description = "Provides comprehensive evaluation and testing capabilities for RAAF agents, " \
                     "including span serialization, evaluation execution, quantitative and qualitative " \
                     "metrics, statistical analysis, and regression detection."
  spec.homepage = "https://github.com/raaf-ai/ruby-ai-agents-factory"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main/eval"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[spec/ test/ features/ .git .github])
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core dependencies
  spec.add_dependency "raaf-core", "0.1.0"
  spec.add_dependency "raaf-tracing", "0.1.0"

  # Database and ORM
  spec.add_dependency "activerecord", "~> 7.0"
  spec.add_dependency "pg", "~> 1.4"

  # NLP and statistical analysis
  spec.add_dependency "rouge", "~> 4.0"
  spec.add_dependency "ruby-statistics", "~> 3.0"
  spec.add_dependency "matrix", "~> 0.4"

  # JSON handling
  spec.add_dependency "json", "~> 2.0"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "factory_bot", "~> 6.2"
  spec.add_development_dependency "database_cleaner-active_record", "~> 2.0"
  spec.add_development_dependency "timecop", "~> 0.9"
end

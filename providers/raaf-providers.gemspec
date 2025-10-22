# frozen_string_literal: true

require_relative "lib/raaf/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-providers"
  spec.version = RAAF::Providers::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]

  spec.summary = "Multiple LLM provider support for Ruby AI Agents Factory"
  spec.description = "Provides unified interface for multiple LLM providers including OpenAI, Anthropic, " \
                     "Google, Azure, AWS, and more with automatic failover, load balancing, and provider-specific " \
                     "optimizations."
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

  # Dependencies - Only include gems that actually exist on RubyGems
  # spec.add_dependency "anthropic", "~> 0.3"  # May not exist yet
  # spec.add_dependency "aws-sdk-bedrock", "~> 1.0"  # May not exist yet
  # spec.add_dependency "azure-openai", "~> 0.1"  # Does not exist
  spec.add_dependency "concurrent-ruby", "~> 1.1"
  spec.add_dependency "faraday", "~> 2.7"
  spec.add_dependency "faraday-multipart", "~> 1.0"
  spec.add_dependency "faraday-retry", "~> 2.0"
  # spec.add_dependency "google-cloud-ai_platform", "~> 1.0"  # May not exist yet
  spec.add_dependency "httparty", "~> 0.21"
  spec.add_dependency "json", "~> 2.0"
  # In mono-repo, raaf-core is referenced by path in Gemfile
  # spec.add_dependency "raaf-core", "~> 0.1"
  spec.add_dependency "ruby-openai", "~> 7.0"
  spec.add_dependency "zeitwerk", "~> 2.6"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"
  spec.add_development_dependency "vcr", "~> 6.1"
  spec.add_development_dependency "webmock", "~> 3.18"
end

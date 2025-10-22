# frozen_string_literal: true

require_relative "lib/raaf/version"

Gem::Specification.new do |spec|
  spec.name = "raaf-core"
  spec.version = RAAF::VERSION
  spec.summary = "RAAF Core - Essential agent runtime with default OpenAI provider"
  spec.description = "Core components of Ruby AI Agents Factory (RAAF) including agent runtime, " \
                     "execution engine, and default OpenAI provider support. This is the foundation " \
                     "gem required by all other RAAF gems."

  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]
  spec.homepage = "https://github.com/raaf-ai/ruby-ai-agents-factory"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main/gems/raaf-core"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "#{spec.homepage}/tree/main/gems/raaf-core/README.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[spec/ test/ features/ .git])
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core dependencies - minimal and essential only
  spec.add_dependency "json", "~> 2.0"
  spec.add_dependency "logger", "~> 1.4"
  spec.add_dependency "net-http", "~> 0.3"

  # ActiveSupport for HashWithIndifferentAccess
  spec.add_dependency "activesupport", "~> 8.0"

  # Zeitwerk for code autoloading
  spec.add_dependency "zeitwerk", "~> 2.6"

  # base64 was moved to a bundled gem in Ruby 3.4+
  spec.add_dependency "base64", "~> 0.1"

  # Async gems for streaming and concurrent operations
  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "async-http", "~> 0.69"

  # Tiktoken for accurate token counting
  spec.add_dependency "tiktoken_ruby", "~> 0.0.9"

  # Development dependencies moved to Gemfile
end

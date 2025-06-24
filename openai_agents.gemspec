# frozen_string_literal: true

require_relative "lib/openai_agents/version"

Gem::Specification.new do |spec|
  spec.name = "openai_agents"
  spec.version = OpenAIAgents::VERSION
  spec.summary = "A Ruby implementation of OpenAI Agents for multi-agent AI workflows"
  spec.description = "A lightweight yet powerful framework for building multi-agent workflows with Ruby. " \
                     "Supports 100+ LLMs, async execution, tool integration, and agent handoffs."
  spec.authors = ["Bert Hajee"]
  spec.email = ["bert.hajee@enterprisemodules.com"]
  spec.homepage = "https://github.com/enterprisemodules/openai-agents-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "async-http", "~> 0.60"
  spec.add_dependency "concurrent-ruby", "~> 1.1"
  spec.add_dependency "json", "~> 2.0"
  spec.add_dependency "logger", "~> 1.4"
  spec.add_dependency "net-http", "~> 0.3"

  # base64 was moved to a bundled gem in Ruby 3.4+
  spec.add_dependency "base64", "~> 0.1"

  # fiddle will be removed from default gems in Ruby 3.5+
  spec.add_dependency "fiddle", "~> 1.0"
end

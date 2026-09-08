# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in openai_agents.gemspec
# gemspec

# Development dependencies
gem "bundler", "~> 2.0"
gem "matrix", "~> 0.4" # Required for vector store functionality
# gem "phlex-preline", path: "../phlex-preline"
gem "rails"
gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"
gem "rspec-collection_matchers", "~> 1.2"
gem "rubocop", "~> 1.21"
# Custom cops shared with the host application. RAAF is normally checked out
# inside ProspectsRadar, which vendors both gems side by side; fall back to the
# repo when it is not.
ai_rubocops_local_path = File.expand_path("../ai-rubocops", __dir__)
if File.directory?(ai_rubocops_local_path)
  gem "ai-rubocops", path: ai_rubocops_local_path, require: false
else
  gem "ai-rubocops", github: "prospects-radar/ai-rubocops", branch: "main", require: false
end
# Cop plugins required by the per-gem .rubocop.yml files (core/, dsl/, rails/, ...)
# so a repo-wide `bin/rubocop` run can load every sub-config.
gem "rubocop-rails", require: false
gem "rubocop-rake", require: false
gem "rubocop-rspec", require: false
gem "yard", "~> 0.9"

group :mdl do
  gem "mdl", "!= 0.13.0", require: false
end

group :doc do
  gem "dartsass"
  gem "rdoc", "< 6.10"
  gem "redcarpet", "~> 3.6.1", platforms: :ruby
  gem "rouge"
  gem "rubyzip", "~> 2.0"
  gem "sdoc", git: "https://github.com/rails/sdoc.git", branch: "main"
  gem "w3c_validators", "~> 1.3.6"
end

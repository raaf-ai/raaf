# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in openai_agents.gemspec
# gemspec

# Development dependencies
gem "bundler", "~> 2.0"
gem "matrix", "~> 0.4"  # Required for vector store functionality
gem "phlex-preline", path: "../phlex-preline"
gem "rails"
gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"
gem "rspec-collection_matchers", "~> 1.2"
gem "rubocop", "~> 1.21"
gem "yard", "~> 0.9"

group :mdl do
  gem "mdl", "!= 0.13.0", require: false
end

group :doc do
  gem "sdoc", git: "https://github.com/rails/sdoc.git", branch: "main"
  gem "rdoc", "< 6.10"
  gem "redcarpet", "~> 3.6.1", platforms: :ruby
  gem "w3c_validators", "~> 1.3.6"
  gem "rouge"
  gem "rubyzip", "~> 2.0"
  gem 'dartsass'
end
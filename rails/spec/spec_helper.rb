# frozen_string_literal: true

require "bundler/setup"

ENV["RAILS_ENV"] = "test"

# Silence RAAF logging during tests. Specs drive error and fallback paths on
# purpose, and the jobs log their own progress; the output buries the actual
# spec results. Set before the engine boots, since the level is memoized on
# first read. Set RAAF_LOG_LEVEL to get it back when debugging a spec.
ENV["RAAF_LOG_LEVEL"] ||= "fatal"
ENV["RAAF_DISABLE_TRACING"] ||= "true"

# Add sibling gems to the load path when running from a checkout.
parent_dir = File.expand_path("../..", __dir__)
%w[core memory tracing].each do |gem_name|
  lib = File.join(parent_dir, gem_name, "lib")
  $LOAD_PATH.unshift(lib) if File.directory?(lib)
end

# Boots the engine inside a real host application. Everything under app/ --
# models, controllers, components, jobs -- is reachable only through
# RAAF::Rails::Engine's paths, which exist only once a Rails::Application has
# initialized. Without this the whole suite failed at load with
# "uninitialized constant RAAF::Rails::Tracing".
#
# Loaded before the sibling gems below rather than after: raaf-tracing only
# defines RAAF::Tracing::TracedJob when ActiveJob is already loaded, and
# ActiveJob arrives with the application.
require_relative "dummy/config/environment"

require "raaf-memory"
require "raaf-testing"

require "rspec/rails"
require_relative "schema_loader"

ActiveRecord::Base.establish_connection(:test)
DATABASE_AVAILABLE = SchemaLoader.load!

Dir[File.join(__dir__, "support/**/*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.filter_run_when_matching :focus

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.order = :random
  Kernel.srand config.seed

  config.infer_spec_type_from_file_location!

  # rspec-rails wraps its own types in a transaction; component specs are not
  # one of them, and several of them write rows the screen then reads. Without
  # this those rows outlive the example and the next one sees them.
  config.include RSpec::Rails::RailsExampleGroup, type: :component
  config.fixture_paths = [File.expand_path("fixtures", __dir__)]

  # Rolled back per example so the model, request and job specs do not leak
  # rows into each other.
  config.use_transactional_fixtures = DATABASE_AVAILABLE

  unless DATABASE_AVAILABLE
    config.before do |example|
      skip "no test database" if %i[model request job component].include?(example.metadata[:type])
    end
  end
end

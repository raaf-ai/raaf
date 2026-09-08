# frozen_string_literal: true

require "bundler/setup"
require "rspec"
require "active_record"
require "factory_bot"

# The engines register this acronym so that raaf_* table and file names map back to
# RAAF-cased constants; standalone specs have no engine, so register it here too.
ActiveSupport::Inflector.inflections(:en) { |inflect| inflect.acronym "RAAF" }

# Load the gem
# The gem's own entry point loads raaf-core, and the library leans on what it
# defines — RAAF.logger above all, which 46 call sites reach for. Loading only
# lib/raaf/eval left those raising NoMethodError inside the suite.
require "raaf-core"
# The gem's own entry point, not lib/raaf/eval — that inner file skips the ActiveRecord
# models, so running a subset of the suite left constants like Models::EvaluationSpan
# undefined depending on which other spec happened to load first.
require_relative "../lib/raaf-eval"
require_relative "../lib/raaf/eval/rspec"

# Configure RAAF Eval for testing
RAAF::Eval.configure do |config|
  config.database_url = "postgresql://localhost/raaf_eval_test"
  config.llm_judge_model = "gpt-4o"
  config.llm_judge_cache = true
end

# Configure RAAF Eval RSpec integration
RAAF::Eval::RSpec.configure do |config|
  config.llm_judge_model = "gpt-4o"
  config.llm_judge_temperature = 0.3
  config.llm_judge_cache = true
  config.enable_parallel_execution = false
end

# The model specs exercise real ActiveRecord classes, so they need a database with the
# gem's schema. Point RAAF_EVAL_TEST_DATABASE_URL elsewhere to use a different one.
EVAL_TEST_DATABASE_URL = ENV.fetch("RAAF_EVAL_TEST_DATABASE_URL", "postgresql://localhost/raaf_eval_test")

begin
  ActiveRecord::Base.establish_connection(EVAL_TEST_DATABASE_URL)
  ActiveRecord::Base.connection.verify!
  ActiveRecord::Migration.verbose = false
  ActiveRecord::MigrationContext.new(File.expand_path("../db/migrate", __dir__)).migrate
  EVAL_DATABASE_AVAILABLE = true
rescue StandardError => e
  # Without a database the model specs cannot run; say so once rather than failing
  # every example with a connection error.
  warn "[raaf-eval specs] no test database (#{e.class}: #{e.message}); model specs will be skipped"
  EVAL_DATABASE_AVAILABLE = false
end

FactoryBot.definition_file_paths = [File.expand_path("factories", __dir__)]
FactoryBot.find_definitions

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Include RAAF Eval RSpec helpers in evaluation tests
  config.include RAAF::Eval::RSpec, type: :evaluation

  # Auto-tag evaluation specs
  config.define_derived_metadata(file_path: %r{/spec/evaluations/}) do |metadata|
    metadata[:type] = :evaluation
  end

  # Roll every example back so the model specs do not leak rows into each other.
  config.around do |example|
    if EVAL_DATABASE_AVAILABLE
      ActiveRecord::Base.transaction do
        example.run
        raise ActiveRecord::Rollback
      end
    else
      example.run
    end
  end

  # The evaluator registry is a process-wide singleton, so a spec that registers an
  # evaluator, or empties the table to test registration, otherwise decides what every
  # later spec finds in it. Put it back the way it was found.
  config.around do |example|
    registry = RAAF::Eval::DSL::EvaluatorRegistry.instance
    evaluators = registry.instance_variable_get(:@evaluators).dup
    built_ins_registered = registry.instance_variable_get(:@built_ins_registered)

    begin
      example.run
    ensure
      registry.instance_variable_set(:@evaluators, evaluators)
      registry.instance_variable_set(:@built_ins_registered, built_ins_registered)
    end
  end

  # Clear span repository before each test
  config.before do
    RAAF::Eval::SpanRepository.clear!
  end

  # Clean up after each test
  config.after do
    RAAF::Eval::SpanRepository.clear!
  end
end

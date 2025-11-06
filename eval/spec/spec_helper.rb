# frozen_string_literal: true

require "bundler/setup"
require "rspec"

# Load the gem
require_relative "../lib/raaf/eval"
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

RSpec.configure do |config|
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

  # Clear span repository before each test
  config.before(:each) do
    RAAF::Eval::SpanRepository.clear!
  end

  # Clean up after each test
  config.after(:each) do
    RAAF::Eval::SpanRepository.clear!
  end
end

# frozen_string_literal: true

# Coverage measurement
require_relative 'coverage_helper'

require "bundler/setup"

# Add parent gems to load path if in development
parent_dir = File.expand_path("../..", __dir__)
core_lib = File.join(parent_dir, "core/lib")
$LOAD_PATH.unshift(core_lib) if File.directory?(core_lib)

# Require core gem first for logging and other dependencies
require "raaf-core"
require "raaf-dsl"
require "rspec"
require "tempfile"
require "tmpdir"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  # Use expect syntax
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Include helper methods in all example groups
  config.include(Module.new do
    def silence_warnings
      original_verbosity = $VERBOSE
      $VERBOSE = nil
      yield
    ensure
      $VERBOSE = original_verbosity
    end
  end)

  # Configure output formatting
  config.default_formatter = "doc" if config.files_to_run.one?

  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed

  # Allow focusing on specific tests
  config.filter_run_when_matching :focus

  # Configure shared context and examples
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Clear configuration between tests
  config.before do
    # Clear thread-local variables used by AgentDsl
    Thread.current[:raaf_dsl_agent_config] = {}
    Thread.current[:raaf_dsl_tools_config] = []
    Thread.current[:raaf_dsl_schema_config] = {}
    Thread.current[:raaf_dsl_prompt_config] = {}

    # Clear any class attributes that might have been set
    if defined?(RAAF::DSL::Config)
      RAAF::DSL::Config.instance_variable_set(:@config, nil)
      RAAF::DSL::Config.instance_variable_set(:@environment_configs, {})
      RAAF::DSL::Config.instance_variable_set(:@raw_config, nil)
    end

    # Reset RAAF::DSL configuration to fresh defaults
    RAAF::DSL.instance_variable_set(:@configuration, nil)

    # Force new configuration with defaults by accessing it
    if defined?(RAAF::DSL) && RAAF::DSL.respond_to?(:configuration)
      # This will create a new Configuration instance with defaults
      RAAF::DSL.configuration
    end
  end

  # Clean up after each test
  config.after do
    # Reset any ENV stubs
    RSpec::Mocks.space.proxy_for(ENV)&.reset

    # COMPREHENSIVE GLOBAL STATE CLEANUP
    if defined?(RAAF::DSL)
      # Reset ALL RAAF::DSL module-level state
      RAAF::DSL.instance_variable_set(:@configuration, nil)
      RAAF::DSL.instance_variable_set(:@prompt_configuration, nil)
      RAAF::DSL.instance_variable_set(:@prompt_resolvers, nil)

      # Always reload Config state regardless of Rails state
      RAAF::DSL::Config.reload! if defined?(RAAF::DSL::Config)
    end
  end

  # Set up temporary directories for file-based tests
  config.around(:each, :with_temp_files) do |example|
    Dir.mktmpdir("raaf/dsl_test") do |temp_dir|
      @temp_dir = temp_dir
      example.run
    end
  ensure
    @temp_dir = nil
  end
end

# Helper method to access temp directory
def temp_dir
  @temp_dir ||= Dir.mktmpdir
end

# Helper method to silence warnings
def silence_warnings
  original_verbosity = $VERBOSE
  $VERBOSE = nil
  yield
ensure
  $VERBOSE = original_verbosity
end

puts "✅ Simple spec helper loaded with coverage measurement"
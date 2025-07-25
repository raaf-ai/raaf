# frozen_string_literal: true

require "bundler/setup"

# Add parent gems to load path if in development
parent_dir = File.expand_path("../..", __dir__)
core_lib = File.join(parent_dir, "core/lib")
$LOAD_PATH.unshift(core_lib) if File.directory?(core_lib)

# Require core gem first for logging and other dependencies
require "raaf-core"
require "raaf-dsl"
require "raaf/dsl/rspec"
require "rspec"
require "tempfile"
require "tmpdir"

# Require raaf-testing for prompt matchers (mandatory development gem)
require "raaf-testing"

# Load support files (excluding the old prompt_matchers which are now in the gem)
Dir[File.expand_path("support/**/*.rb", __dir__)].each do |f|
  next if f.include?("prompt_matchers")

  require f
end

# Force loading of autoloaded constants to prevent NameError in specs

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

  # Include testing matchers
  config.include RAAF::Testing::Matchers

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

    # Reset Rails stubs if any
    if defined?(Rails)
      if Rails.is_a?(RSpec::Mocks::Double)
        # If Rails is a mock, unstub it completely
        RSpec::Mocks.space.reset_all
        hide_const("Rails") if Object.const_defined?(:Rails)
      elsif RSpec::Mocks.space.proxy_for(Rails)
        # Reset any stubs on the real Rails object
        RSpec::Mocks.space.proxy_for(Rails)&.reset
      end
    end

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

  # Set up Rails environment when needed
  config.before(:each, :with_rails) do
    # Only load Rails environment if testing Rails integration
    unless defined?(Rails)
      require "rails"
      require "rails/railtie"

      # Define the TestApp class outside of the block if needed
      unless defined?(TestApp)
        test_app_class = Class.new(Rails::Application)
        test_app_class.config.root = Pathname.new(Dir.pwd)
        test_app_class.config.eager_load = false
        test_app_class.config.logger = Logger.new(IO::NULL)

        # Minimal Rails configuration for testing
        test_app_class.config.load_defaults Rails::VERSION::STRING.to_f
        Object.const_set(:TestApp, test_app_class)
      end

      # Initialize the Rails app
      Rails.application ||= TestApp.new
      Rails.application.config.root = Pathname.new(@temp_dir) if @temp_dir
      Rails.env = "test"
    end
  end

  # Capture stdout/stderr for testing output
  config.around(:each, :capture_output) do |example|
    original_stdout = $stdout
    original_stderr = $stderr

    stdout_capture = StringIO.new
    stderr_capture = StringIO.new

    $stdout = stdout_capture
    $stderr = stderr_capture

    begin
      example.run
    ensure
      # Store captured output in example metadata
      example.metadata[:stdout] = stdout_capture.string
      example.metadata[:stderr] = stderr_capture.string

      $stdout = original_stdout
      $stderr = original_stderr
    end
  end
end

# Helper methods to access captured output
def captured_stdout
  RSpec.current_example.metadata[:stdout]
end

def captured_stderr
  RSpec.current_example.metadata[:stderr]
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

# Helper method to capture output
def capture(stream)
  original_stream = case stream.to_s
                    when "stdout"
                      $stdout
                    when "stderr"
                      $stderr
                    else
                      raise ArgumentError, "Unsupported stream: #{stream}"
                    end

  captured_output = StringIO.new

  case stream.to_s
  when "stdout"
    $stdout = captured_output
  when "stderr"
    $stderr = captured_output
  end

  yield
  captured_output.string
ensure
  case stream.to_s
  when "stdout"
    $stdout = original_stream
  when "stderr"
    $stderr = original_stream
  end
end

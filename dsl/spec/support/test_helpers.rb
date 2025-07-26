# frozen_string_literal: true

module TestHelpers
  # Create a temporary YAML configuration file
  def create_test_config_file(config_hash, filename = "ai_agents.yml")
    config_path = File.join(temp_dir, filename)
    File.write(config_path, config_hash.to_yaml)
    config_path
  end

  # Create a test agent class for testing
  def create_test_agent_class(name = "TestAgent", &block)
    agent_class = Class.new(RAAF::DSL::Agents::Base) do
      include RAAF::DSL::Agents::AgentDsl
    end

    agent_class.class_eval(&block) if block_given?

    # Set a class name for better error messages
    stub_const(name, agent_class)
    agent_class
  end

  # Create a test prompt class for testing
  def create_test_prompt_class(name = "TestPrompt", &block)
    prompt_class = Class.new(RAAF::DSL::Prompts::Base)

    prompt_class.class_eval(&block) if block_given?

    # Set a class name for better error messages
    stub_const(name, prompt_class)
    prompt_class
  end

  # Create a test tool class for testing
  def create_test_tool_class(name = "TestTool", &block)
    tool_class = Class.new(RAAF::DSL::Tools::Base) do
      include RAAF::DSL::ToolDsl
    end

    tool_class.class_eval(&block) if block_given?

    # Set a class name for better error messages
    stub_const(name, tool_class)
    tool_class
  end

  # Mock Rails environment variables
  def mock_rails_env(env_name)
    allow(ENV).to receive(:[]).with("RAILS_ENV").and_return(env_name)
    allow(ENV).to receive(:[]).with("RACK_ENV").and_return(env_name)
  end

  # Create a mock Rails application for generator testing
  def mock_rails_application(root_path = temp_dir)
    # Use the existing Rails application if available
    if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
      Rails.application.config.root = Pathname.new(root_path) if root_path
      Rails.application
    else
      # Create a minimal Rails app for testing
      require "rails" unless defined?(Rails)
      require "rails/railtie" unless defined?(Rails::Railtie)

      # Define the TestApp class outside of the method if needed
      unless defined?(::TestApp)
        Object.const_set(:TestApp, Class.new(Rails::Application) do
          config.eager_load = false
          config.logger = Logger.new(IO::NULL)
        end)
      end

      app = ::TestApp.new
      app.config.root = Pathname.new(root_path)
      Rails.application = app
      app
    end
  end

  # Create directory structure for testing
  def create_directory_structure(paths)
    paths.each do |path|
      full_path = File.join(temp_dir, path)
      FileUtils.mkdir_p(File.dirname(full_path))
      FileUtils.touch(full_path) if File.extname(path) != ""
    end
  end

  # Helper to test file generation
  def expect_file_generated(file_path, content_matcher = nil)
    full_path = File.join(temp_dir, file_path)
    expect(File.exist?(full_path)).to be true

    return unless content_matcher

    content = File.read(full_path)
    case content_matcher
    when String
      expect(content).to include(content_matcher)
    when Regexp
      expect(content).to match(content_matcher)
    when Proc
      expect(content_matcher.call(content)).to be true
    end
  end

  # Helper to mock OpenAI client and Responses API calls
  def mock_openai_agent
    # Mock the OpenAI::Client
    client = double("OpenAI::Client")
    responses = double("Responses")

    # Set up the method chain: client.responses.create
    allow(client).to receive(:responses).and_return(responses)
    allow(responses).to receive(:create).and_return({
                                                      "text" => "Mocked OpenAI Responses API response"
                                                    })

    # Mock OpenAI::Client.new to return our mock if OpenAI is available
    allow(OpenAI::Client).to receive(:new).and_return(client) if defined?(OpenAI::Client)

    client
  end

  # Helper to test configuration loading
  def with_config_file(config_hash)
    config_path = create_test_config_file(config_hash)

    # Store original config file path
    RAAF::DSL.configuration.config_file

    # Configure RAAF::DSL to use the test config file
    RAAF::DSL.configure do |config|
      config.config_file = config_path
    end

    # Force reload of configuration
    RAAF::DSL::Config.reload! if defined?(RAAF::DSL::Config)

    yield config_path
  ensure
    # Reset to default configuration instead of restoring potentially contaminated state
    # This ensures a clean state for the next test
    RAAF::DSL.instance_variable_set(:@configuration, nil)

    # Force Config to reload with fresh defaults
    RAAF::DSL::Config.reload! if defined?(RAAF::DSL::Config)

    # Access configuration to force creation with defaults
    RAAF::DSL.configuration
  end

  # Helper to test YAML parsing errors
  def create_invalid_yaml_file
    config_path = File.join(temp_dir, "invalid.yml")
    File.write(config_path, "invalid: yaml: content: [unclosed")
    config_path
  end

  # Helper to capture method calls
  def method_call_tracker
    @method_call_tracker ||= []
  end

  def track_method_call(method_name, *args)
    method_call_tracker << { method: method_name, args: args, called_at: Time.current }
  end

  def reset_method_calls
    @method_calls = []
  end

  # Helper for testing error handling
  def expect_error_handling(error_class, &block)
    expect { block.call }.to raise_error(error_class)
  end

  # Helper for testing logging
  def with_logger
    logger = Logger.new(StringIO.new)
    original_logger = Rails.logger if defined?(Rails)

    allow(Rails).to receive(:logger).and_return(logger) if defined?(Rails)

    yield logger
  ensure
    allow(Rails).to receive(:logger).and_return(original_logger) if defined?(Rails) && original_logger
  end
end

# Include helpers in RSpec
RSpec.configure do |config|
  config.include TestHelpers
end

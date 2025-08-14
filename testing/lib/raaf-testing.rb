# frozen_string_literal: true

require_relative "raaf/testing/version"
require_relative "raaf/testing/matchers"
require_relative "raaf/testing/prompt_matchers"

# RSpec integration (load when RSpec is available)
if defined?(RSpec)
  require_relative "raaf/testing/rspec"
end

# Only require mock_provider if RAAF core is available
begin
  require_relative "raaf/testing/mock_provider"
rescue NameError, LoadError
  # Skip mock_provider if dependencies aren't available
end

module RAAF
  ##
  # Testing utilities and RSpec matchers for Ruby AI Agents Factory
  #
  # The Testing module provides comprehensive testing utilities for AI agents
  # including RSpec matchers, mock providers, conversation helpers, and
  # response validation tools. It makes it easy to write reliable tests
  # for AI agent behavior and interactions.
  #
  # Key features:
  # - **RSpec Matchers** - Custom matchers for agent responses and behavior
  # - **Mock Providers** - Test-friendly LLM providers for consistent testing
  # - **Conversation Testing** - Utilities for testing multi-turn conversations
  # - **Response Validation** - Tools for validating agent responses
  # - **Fixtures & Factories** - Pre-built test data and agent configurations
  # - **VCR Integration** - Record and replay HTTP interactions
  # - **Performance Testing** - Benchmarking and performance validation
  # - **Integration Testing** - End-to-end testing utilities
  #
  # @example Basic RSpec usage
  #   require 'raaf-testing'
  #   
  #   RSpec.describe "My Agent" do
  #     include RAAF::Testing::Helpers
  #     
  #     let(:agent) { create_test_agent }
  #     
  #     it "responds appropriately" do
  #       result = agent.run("Hello")
  #       expect(result).to be_successful
  #       expect(result).to have_message_containing("hello")
  #     end
  #   end
  #
  # @example Mock provider usage
  #   require 'raaf-testing'
  #   
  #   # Create mock provider with predefined responses
  #   mock_provider = RAAF::Testing::MockProvider.new
  #   mock_provider.add_response("Hello", "Hi there!")
  #   mock_provider.add_response("Goodbye", "See you later!")
  #   
  #   # Use with agent
  #   agent = RAAF::Agent.new(
  #     name: "TestAgent",
  #     provider: mock_provider
  #   )
  #
  # @example Conversation testing
  #   require 'raaf-testing'
  #   
  #   conversation = RAAF::Testing::ConversationHelper.new(agent)
  #   
  #   conversation.user_says("What's the weather like?")
  #   conversation.agent_responds_with(/weather|temperature/i)
  #   
  #   conversation.user_says("Thank you")
  #   conversation.agent_responds_with(/welcome|pleasure/i)
  #   
  #   expect(conversation).to be_successful
  #
  # @example Response validation
  #   require 'raaf-testing'
  #   
  #   validator = RAAF::Testing::ResponseValidator.new
  #   
  #   # Add validation rules
  #   validator.must_contain_keywords(["helpful", "assistant"])
  #   validator.must_not_contain_keywords(["sorry", "can't"])
  #   validator.must_be_shorter_than(500)
  #   validator.must_have_positive_sentiment
  #   
  #   # Validate response
  #   result = agent.run("How can you help me?")
  #   expect(result).to pass_validation(validator)
  #
  # @since 1.0.0
  module Testing
    # Default configuration
    DEFAULT_CONFIG = {
      # Mock provider settings
      mock_provider: {
        default_response: "I'm a test agent and this is a mock response.",
        response_delay: 0.1,
        failure_rate: 0.0,
        usage_tracking: true
      },
      
      # VCR settings
      vcr: {
        cassette_library_dir: "spec/vcr_cassettes",
        hook_into: :webmock,
        configure_rspec_metadata: true,
        allow_http_connections_when_no_cassette: false
      },
      
      # Test helpers
      helpers: {
        auto_cleanup: true,
        default_timeout: 30,
        retry_count: 3
      },
      
      # Performance testing
      performance: {
        max_response_time: 5.0,
        memory_threshold: 100 * 1024 * 1024, # 100MB
        enable_profiling: false
      },
      
      # Validation settings
      validation: {
        strict_mode: false,
        auto_sanitize: true,
        content_filters: [:profanity, :pii]
      }
    }.freeze

    class << self
      # @return [Hash] Current configuration
      attr_accessor :config

      ##
      # Configure testing settings
      #
      # @param options [Hash] Configuration options
      # @yield [config] Configuration block
      #
      # @example Configure testing
      #   RAAF::Testing.configure do |config|
      #     config.mock_provider.default_response = "Test response"
      #     config.performance.max_response_time = 3.0
      #     config.validation.strict_mode = true
      #   end
      #
      def configure
        @config ||= deep_dup(DEFAULT_CONFIG)
        yield @config if block_given?
        @config
      end

      ##
      # Get current configuration
      #
      # @return [Hash] Current configuration
      def config
        @config ||= deep_dup(DEFAULT_CONFIG)
      end

      ##
      # Setup RSpec integration
      #
      # Configures RSpec with RAAF testing utilities including
      # matchers, helpers, and global setup.
      #
      # @example Setup RSpec
      #   # In spec_helper.rb
      #   RAAF::Testing.setup_rspec
      #
      def setup_rspec
        return unless defined?(RSpec)

        RSpec.configure do |config|
          # Include testing helpers and matchers
          config.include RAAF::Testing::Helpers
          config.include RAAF::Testing::Matchers
          
          # Include RSpec-specific matchers if available
          if defined?(RAAF::Testing::RSpec)
            config.include RAAF::Testing::RSpec::Matchers
            config.include RAAF::Testing::RSpec::Helpers
          end
          
          # Include DSL testing helpers if DSL gem is available
          if defined?(RAAF::DSL::Testing::RSpecHelpers)
            config.include RAAF::DSL::Testing::RSpecHelpers
          end
          
          # Setup VCR
          setup_vcr if defined?(VCR)
          
          # Setup WebMock
          setup_webmock if defined?(WebMock)
          
          # Global setup and teardown
          config.before(:suite) do
            RAAF::Testing.setup_test_environment
          end
          
          config.after(:suite) do
            RAAF::Testing.cleanup_test_environment
          end
          
          config.before(:each) do
            RAAF::Testing.reset_test_state
          end
          
          config.after(:each) do
            RAAF::Testing.cleanup_test_resources
          end
        end
      end

      ##
      # Create a mock provider for testing
      #
      # @param options [Hash] Provider options
      # @return [MockProvider] Mock provider instance
      def create_mock_provider(**options)
        MockProvider.new(**config[:mock_provider].merge(options))
      end

      ##
      # Create a test agent with sensible defaults
      #
      # @param options [Hash] Agent options
      # @return [Agent] Test agent instance
      def create_test_agent(**options)
        defaults = {
          name: "TestAgent",
          instructions: "You are a helpful test assistant.",
          provider: create_mock_provider
        }
        
        RAAF::Agent.new(**defaults.merge(options))
      end

      ##
      # Create a conversation helper for testing
      #
      # @param agent [Agent] Agent to test
      # @return [ConversationHelper] Conversation helper instance
      def create_conversation_helper(agent)
        ConversationHelper.new(agent)
      end

      ##
      # Create a response validator
      #
      # @param options [Hash] Validator options
      # @return [ResponseValidator] Response validator instance
      def create_response_validator(**options)
        ResponseValidator.new(**config[:validation].merge(options))
      end

      ##
      # Setup test environment
      #
      # Initializes the test environment with necessary configurations
      # and mock services.
      #
      def setup_test_environment
        # Setup logging for tests
        RAAF::Logging.configure do |logging_config|
          logging_config.log_level = :warn
          logging_config.log_output = :console
        end
        
        # Setup mock services
        setup_mock_services
        
        # Initialize test database if needed
        setup_test_database if defined?(ActiveRecord)
      end

      ##
      # Cleanup test environment
      #
      # Cleans up resources and resets state after test suite.
      #
      def cleanup_test_environment
        # Cleanup mock services
        cleanup_mock_services
        
        # Clear caches
        clear_test_caches
      end

      ##
      # Reset test state between tests
      #
      # Resets global state to ensure test isolation.
      #
      def reset_test_state
        # Clear agent registry
        RAAF::Agent.registry.clear if RAAF::Agent.respond_to?(:registry)
        
        # Reset configuration
        @config = nil
        
        # Clear response caches
        MockProvider.clear_all_responses
      end

      ##
      # Cleanup test resources after each test
      #
      # Cleans up resources created during individual tests.
      #
      def cleanup_test_resources
        # Cleanup temporary files
        cleanup_temp_files
        
        # Reset timecop if used
        Timecop.return if defined?(Timecop)
      end

      ##
      # Get test statistics
      #
      # @return [Hash] Test statistics
      def stats
        {
          mock_providers: MockProvider.instances.size,
          active_conversations: ConversationHelper.active_conversations.size,
          cached_responses: MockProvider.cached_responses.size,
          temp_files: temp_files_count
        }
      end

      ##
      # Clear all test caches
      #
      def clear_test_caches
        MockProvider.clear_all_caches
        ResponseValidator.clear_cache
        Fixtures.clear_cache
      end

      ##
      # Enable debug mode for testing
      #
      # @param enabled [Boolean] Whether to enable debug mode
      def debug_mode=(enabled)
        @debug_mode = enabled
        
        if enabled
          RAAF::Logging.configure do |config|
            config.log_level = :debug
            config.debug_categories = [:all]
          end
        end
      end

      ##
      # Check if debug mode is enabled
      #
      # @return [Boolean] True if debug mode is enabled
      def debug_mode?
        @debug_mode || false
      end

      private

      def setup_vcr
        VCR.configure do |vcr_config|
          vcr_config.cassette_library_dir = config[:vcr][:cassette_library_dir]
          vcr_config.hook_into config[:vcr][:hook_into]
          vcr_config.configure_rspec_metadata! if config[:vcr][:configure_rspec_metadata]
          vcr_config.allow_http_connections_when_no_cassette = config[:vcr][:allow_http_connections_when_no_cassette]
          
          # Filter sensitive data
          vcr_config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
          vcr_config.filter_sensitive_data('<AZURE_API_KEY>') { ENV['AZURE_API_KEY'] }
          vcr_config.filter_sensitive_data('<AWS_ACCESS_KEY>') { ENV['AWS_ACCESS_KEY_ID'] }
          vcr_config.filter_sensitive_data('<AWS_SECRET_KEY>') { ENV['AWS_SECRET_ACCESS_KEY'] }
        end
      end

      def setup_webmock
        WebMock.disable_net_connect!(allow_localhost: true)
      end

      def setup_mock_services
        # Setup mock HTTP services for testing
        @mock_services = []
      end

      def cleanup_mock_services
        @mock_services&.each(&:stop)
        @mock_services&.clear
      end

      def setup_test_database
        # Setup test database if ActiveRecord is available
        # This would typically be done in a Rails environment
      end

      def cleanup_temp_files
        # Cleanup temporary files created during tests
        temp_dir = Dir.tmpdir
        pattern = File.join(temp_dir, "raaf_test_*")
        Dir.glob(pattern).each { |file| File.delete(file) rescue nil }
      end

      def temp_files_count
        temp_dir = Dir.tmpdir
        pattern = File.join(temp_dir, "raaf_test_*")
        Dir.glob(pattern).size
      end

      # Note: clear_test_caches is defined above with actual implementation

      def deep_dup(hash)
        hash.each_with_object({}) do |(key, value), result|
          result[key] = value.is_a?(Hash) ? deep_dup(value) : value.dup
        end
      rescue TypeError
        hash
      end
    end
  end
end
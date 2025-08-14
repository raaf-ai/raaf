# frozen_string_literal: true

require 'rspec' if defined?(RSpec)

module RAAF
  module Testing
    ##
    # RSpec integration and custom matchers for testing RAAF components
    #
    # This module provides comprehensive RSpec integration for testing AI agents,
    # DSL components, prompts, and multi-agent workflows. It includes custom
    # matchers, test helpers, and configuration utilities.
    #
    # @example Setup in spec_helper.rb
    #   require 'raaf-testing/rspec'
    #   
    #   RSpec.configure do |config|
    #     config.include RAAF::Testing::RSpec::Matchers
    #     config.include RAAF::Testing::RSpec::Helpers
    #   end
    #
    # @example Auto-setup (recommended)
    #   require 'raaf-testing'
    #   RAAF::Testing.setup_rspec
    #
    module RSpec
      autoload :DSLMatchers, "raaf/testing/rspec/dsl_matchers"
      autoload :AgentMatchers, "raaf/testing/rspec/agent_matchers"
      autoload :ContextMatchers, "raaf/testing/rspec/context_matchers"
      autoload :Helpers, "raaf/testing/rspec/helpers"
      
      # Include prompt matchers from existing code
      include RAAF::Testing::PromptMatchers if defined?(RAAF::Testing::PromptMatchers)

      ##
      # All matchers combined for easy inclusion
      #
      module Matchers
        include DSLMatchers
        include AgentMatchers if defined?(AgentMatchers)
        include ContextMatchers if defined?(ContextMatchers)
        include RAAF::Testing::PromptMatchers if defined?(RAAF::Testing::PromptMatchers)
      end

      ##
      # Test helpers for RAAF RSpec integration
      #
      module Helpers
        ##
        # Create a test agent with mock provider
        #
        # @param options [Hash] Agent configuration options
        # @return [RAAF::Agent] Configured test agent
        #
        def create_test_agent(**options)
          RAAF::Testing.create_test_agent(**options)
        end

        ##
        # Create a mock provider for testing
        #
        # @param options [Hash] Provider configuration options
        # @return [RAAF::Testing::MockProvider] Mock provider instance
        #
        def create_mock_provider(**options)
          RAAF::Testing.create_mock_provider(**options)
        end

        ##
        # Create mock context variables
        #
        # @param context_data [Hash] Context data
        # @return [RAAF::DSL::ContextVariables] Mock context variables
        #
        def mock_context_variables(context_data = {})
          if defined?(RAAF::DSL::ContextVariables)
            context = RAAF::DSL::ContextVariables.new
            context_data.each do |key, value|
              context = context.set(key, value)
            end
            context
          else
            context_data
          end
        end

        ##
        # Mock agent response for testing
        #
        # @param agent_class [Class] Agent class to mock
        # @param response [Hash, String] Response to return
        # @param success [Boolean] Whether response should be successful
        #
        def mock_agent_response(agent_class, response, success: true)
          if defined?(RAAF::DSL::Testing::RSpecHelpers)
            extend RAAF::DSL::Testing::RSpecHelpers
            mock_agent_response(agent_class, response, success: success)
          else
            # Fallback for when DSL isn't available
            allow_any_instance_of(agent_class).to receive(:run).and_return(
              success ? { success: true, data: response } : { success: false, error: response }
            )
          end
        end

        ##
        # Create a conversation test helper
        #
        # @param agent [Object] Agent to test
        # @return [Object] Conversation helper
        #
        def create_conversation_helper(agent)
          RAAF::Testing.create_conversation_helper(agent)
        end

        ##
        # Stub external services for testing
        #
        # @param service_responses [Hash] Service method to response mapping
        #
        def stub_external_services(service_responses = {})
          service_responses.each do |service_method, response|
            case service_method
            when :web_search
              stub_web_search_service(response)
            when :openai_api
              stub_openai_api(response)
            # Add more services as needed
            end
          end
        end

        ##
        # Expect specific log events from agent
        #
        # @param agent [Object] Agent instance
        # @param expected_events [Array<Hash>] Expected log events
        #
        def expect_agent_logs(agent, expected_events)
          expected_events.each do |event|
            expect(agent).to receive(:log_event)
              .with(event[:name], hash_including(event[:context] || {}))
          end
        end

        ##
        # Run agent with timeout for testing
        #
        # @param agent [Object] Agent to run
        # @param input [String] Input message
        # @param timeout [Integer] Timeout in seconds
        # @return [Object] Agent result
        #
        def run_agent_with_timeout(agent, input, timeout: 30)
          result = nil
          thread = Thread.new do
            result = agent.run(input)
          end
          
          unless thread.join(timeout)
            thread.kill
            raise "Agent execution timed out after #{timeout} seconds"
          end
          
          result
        end

        private

        def stub_web_search_service(response)
          # Stub common web search endpoints
          stub_request(:post, /api\.tavily\.com/)
            .to_return(
              status: 200,
              body: response.is_a?(String) ? response : response.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )
        end

        def stub_openai_api(response)
          # Stub OpenAI API endpoints
          stub_request(:post, /api\.openai\.com\/v1\/chat\/completions/)
            .to_return(
              status: 200,
              body: response.is_a?(String) ? response : response.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )
        end
      end
    end
  end
end

# Auto-include matchers and helpers when RSpec is available
if defined?(::RSpec)
  ::RSpec.configure do |config|
    config.include RAAF::Testing::RSpec::Matchers
    config.include RAAF::Testing::RSpec::Helpers
  end
end
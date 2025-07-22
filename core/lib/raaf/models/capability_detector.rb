# frozen_string_literal: true

require_relative "../logging"

module RAAF

  module Models

    ##
    # Provider Capability Detection System
    #
    # This system automatically detects what capabilities a provider supports
    # and provides recommendations for optimal usage. It helps ensure that
    # handoff support works correctly across all provider implementations.
    #
    # @example Basic capability detection
    #   detector = CapabilityDetector.new(provider)
    #   capabilities = detector.detect_capabilities
    #   puts "Function calling: #{capabilities[:function_calling]}"
    #   puts "Handoffs: #{capabilities[:handoffs]}"
    #
    # @example Generating detailed report
    #   detector = CapabilityDetector.new(provider)
    #   report = detector.generate_report
    #   puts "Provider: #{report[:provider]}"
    #   puts "Handoff support: #{report[:handoff_support]}"
    #   puts "Optimal usage: #{report[:optimal_usage]}"
    #
    # @example Checking specific capability
    #   detector = CapabilityDetector.new(provider)
    #   if detector.supports_handoffs?
    #     puts "Handoffs are supported!"
    #   else
    #     puts "Need to use fallback system"
    #   end
    #
    # @author RAAF Development Team
    # @since 0.2.0
    #
    class CapabilityDetector

      include Logger

      ##
      # Capability definitions with test methods
      CAPABILITIES = {
        responses_api: {
          name: "Responses API",
          description: "OpenAI Responses API support (/v1/responses)",
          test: :test_responses_api,
          priority: :high
        },
        chat_completion: {
          name: "Chat Completions API",
          description: "Standard chat completions API support",
          test: :test_chat_completion,
          priority: :high
        },
        streaming: {
          name: "Streaming",
          description: "Streaming response support",
          test: :test_streaming,
          priority: :medium
        },
        function_calling: {
          name: "Function Calling",
          description: "Tool/function calling support (required for handoffs)",
          test: :test_function_calling,
          priority: :high
        },
        handoffs: {
          name: "Handoffs",
          description: "Agent handoff support",
          test: :test_handoffs,
          priority: :high
        }
      }.freeze

      # Initialize capability detector
      #
      # @param provider [ModelInterface] Provider to analyze
      # @example Initialize detector
      #   detector = CapabilityDetector.new(my_provider)
      #
      def initialize(provider)
        @provider = provider
        @capabilities = {}
        @recommendations = []
      end

      ##
      # Detect all provider capabilities
      #
      # This method runs all capability tests and returns a comprehensive
      # hash of what the provider supports. Results are cached for performance.
      #
      # @example Detecting capabilities
      #   detector = CapabilityDetector.new(provider)
      #   caps = detector.detect_capabilities
      #   # Returns: {
      #   #   responses_api: true,
      #   #   chat_completion: true,
      #   #   streaming: false,
      #   #   function_calling: true,
      #   #   handoffs: true
      #   # }
      #
      # @return [Hash] Capabilities hash with boolean values for each capability
      #
      def detect_capabilities
        # Return cached results if already detected
        return @capabilities unless @capabilities.empty?

        log_debug("🔍 CAPABILITY DETECTOR: Starting capability detection",
                  provider: @provider.provider_name)

        CAPABILITIES.each do |capability, config|
          @capabilities[capability] = send(config[:test])
          log_debug("🔍 CAPABILITY DETECTOR: Tested capability",
                    provider: @provider.provider_name,
                    capability: capability,
                    supported: @capabilities[capability])
        end

        # Generate recommendations based on detected capabilities
        generate_recommendations

        log_debug("🔍 CAPABILITY DETECTOR: Detection complete",
                  provider: @provider.provider_name,
                  capabilities: @capabilities)

        @capabilities
      end

      ##
      # Get capability report
      #
      # Generates a comprehensive report including capabilities, recommendations,
      # and optimal usage patterns. This is useful for debugging and optimization.
      #
      # @example Generating report
      #   detector = CapabilityDetector.new(provider)
      #   report = detector.generate_report
      #   puts "Provider: #{report[:provider]}"
      #   puts "Handoff support: #{report[:handoff_support]}"
      #
      #   report[:recommendations].each do |rec|
      #     puts "#{rec[:type].upcase}: #{rec[:message]}"
      #   end
      #
      # @return [Hash] Detailed capability report with keys:
      #   - :provider - Provider name
      #   - :capabilities - Array of capability details
      #   - :recommendations - Array of recommendations
      #   - :handoff_support - "Full" or "Limited"
      #   - :optimal_usage - Usage recommendation string
      #
      def generate_report
        detect_capabilities if @capabilities.empty?

        {
          provider: @provider.provider_name,
          capabilities: @capabilities.map do |capability, supported|
            {
              name: CAPABILITIES[capability][:name],
              description: CAPABILITIES[capability][:description],
              supported: supported,
              priority: CAPABILITIES[capability][:priority]
            }
          end,
          recommendations: @recommendations,
          handoff_support: @capabilities[:handoffs] ? "Full" : "Limited",
          optimal_usage: determine_optimal_usage
        }
      end

      ##
      # Check if provider supports handoffs
      #
      # Quick check for handoff support. If capabilities haven't been detected
      # yet, this will trigger detection automatically.
      #
      # @example Checking handoff support
      #   detector = CapabilityDetector.new(provider)
      #   if detector.supports_handoffs?
      #     puts "Handoffs are supported!"
      #   else
      #     puts "Need content-based fallback"
      #   end
      #
      # @return [Boolean] True if handoffs are supported, false otherwise
      #
      def supports_handoffs?
        detect_capabilities if @capabilities.empty?
        @capabilities[:handoffs]
      end

      private

      ##
      # Test Responses API support
      #
      # Checks if provider implements the responses_completion method.
      # This is the preferred API for handoff workflows.
      #
      # @return [Boolean] True if responses_completion method exists
      #
      def test_responses_api
        @provider.respond_to?(:responses_completion)
      end

      ##
      # Test Chat Completions API support
      #
      # Checks if provider actually implements the chat_completion method
      # (not just inheriting the abstract method from ModelInterface).
      # This is the fallback API when Responses API isn't available.
      #
      # @return [Boolean] True if chat_completion method is actually implemented
      #
      def test_chat_completion
        return false unless @provider.respond_to?(:chat_completion)

        # Check if the method is actually implemented by the provider class
        # (not just inherited from the abstract ModelInterface)
        method = @provider.method(:chat_completion)
        method.owner != RAAF::Models::ModelInterface
      rescue StandardError => e
        log_debug("🔍 CAPABILITY DETECTOR: Chat completion test failed",
                  provider: @provider.provider_name,
                  error: e.message)
        false
      end

      ##
      # Test streaming support
      #
      # Checks if provider actually implements the stream_completion method
      # (not just inheriting the abstract method from ModelInterface).
      # This enables real-time response streaming.
      #
      # @return [Boolean] True if stream_completion method is actually implemented
      #
      def test_streaming
        return false unless @provider.respond_to?(:stream_completion)

        # Check if the method is actually implemented by the provider class
        # (not just inherited from the abstract ModelInterface)
        method = @provider.method(:stream_completion)
        method.owner != RAAF::Models::ModelInterface
      rescue StandardError => e
        log_debug("🔍 CAPABILITY DETECTOR: Streaming test failed",
                  provider: @provider.provider_name,
                  error: e.message)
        false
      end

      ##
      # Test function calling support
      #
      # Checks if provider actually implements chat_completion with tools support.
      # This is required for handoff functionality to work properly.
      #
      # @example Function calling test
      #   detector = CapabilityDetector.new(provider)
      #   if detector.send(:test_function_calling)
      #     puts "Provider supports function calling"
      #   else
      #     puts "Provider is text-only"
      #   end
      #
      # @return [Boolean] True if tools parameter is supported
      #
      def test_function_calling
        # First check if chat_completion is actually implemented
        return false unless test_chat_completion

        # Try to safely introspect the method parameters
        method = @provider.method(:chat_completion)
        params = method.parameters

        # Look for tools parameter (either required or optional)
        has_tools_param = params.any? { |_param_type, param_name| param_name == :tools }
        return false unless has_tools_param

        # Additional safety check: try to call the method with minimal args to see if it works
        # This catches providers that have the right signature but fail during execution
        @provider.chat_completion(
          messages: [{ role: "user", content: "test" }],
          model: "test-model",
          tools: []
        )
        true
      rescue StandardError => e
        log_debug("🔍 CAPABILITY DETECTOR: Function calling test failed",
                  provider: @provider.provider_name,
                  error: e.message)
        false
      end

      ##
      # Test handoff support
      #
      # Handoffs require function calling support, so this delegates
      # to the function calling test.
      #
      # @return [Boolean] True if handoffs are supported
      #
      def test_handoffs
        # Handoffs require function calling support
        test_function_calling
      end

      ##
      # Generate recommendations based on capabilities
      #
      # Analyzes detected capabilities and generates actionable recommendations
      # for optimal usage. Recommendations are categorized by type:
      # - :critical - Must be addressed for basic functionality
      # - :warning - Should be addressed for full functionality
      # - :info - Nice to have or informational
      # - :success - Positive feedback on good capabilities
      #
      # @example Generated recommendations
      #   # For a provider without function calling:
      #   # [{
      #   #   type: :warning,
      #   #   message: "Provider doesn't support function calling. Handoffs will not work."
      #   # }]
      #
      # @return [void] Sets @recommendations instance variable
      #
      def generate_recommendations
        @recommendations = []

        # Check for critical missing capabilities
        unless @capabilities[:chat_completion] || @capabilities[:responses_api]
          @recommendations << {
            type: :critical,
            message: "Provider doesn't support any completion API. Implement chat_completion method."
          }
        end

        unless @capabilities[:function_calling]
          @recommendations << {
            type: :warning,
            message: "Provider doesn't support function calling. Handoffs will not work. Add tools parameter to chat_completion."
          }
        end

        unless @capabilities[:handoffs]
          @recommendations << {
            type: :info,
            message: "Provider doesn't support handoffs. Consider extending from EnhancedModelInterface."
          }
        end

        # Positive recommendations
        if @capabilities[:responses_api]
          @recommendations << {
            type: :success,
            message: "Provider supports Responses API. Optimal for handoff workflows."
          }
        elsif @capabilities[:chat_completion] && @capabilities[:function_calling]
          @recommendations << {
            type: :success,
            message: "Provider supports Chat Completions with function calling. Handoffs will work with adapter."
          }
        end

        return unless @capabilities[:streaming]

        @recommendations << {
          type: :info,
          message: "Provider supports streaming. Great for real-time applications."
        }
      end

      ##
      # Determine optimal usage pattern
      #
      # Analyzes capabilities and returns the recommended usage pattern
      # for optimal performance and functionality.
      #
      # @example Usage patterns
      #   # For provider with responses_api + function_calling:
      #   # "Native Responses API - No adapter needed"
      #
      #   # For provider with chat_completion + function_calling:
      #   # "Chat Completions with ProviderAdapter - Full handoff support"
      #
      #   # For provider with only chat_completion:
      #   # "Chat Completions only - Limited handoff support"
      #
      # @return [String] Usage recommendation
      #
      def determine_optimal_usage
        if @capabilities[:responses_api] && @capabilities[:function_calling]
          "Native Responses API - No adapter needed"
        elsif @capabilities[:chat_completion] && @capabilities[:function_calling]
          "Chat Completions with ProviderAdapter - Full handoff support"
        elsif @capabilities[:chat_completion]
          "Chat Completions only - Limited handoff support"
        else
          "Not compatible - Implement required methods"
        end
      end

    end

  end

end

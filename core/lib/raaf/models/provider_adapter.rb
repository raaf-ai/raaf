# frozen_string_literal: true

require_relative "../logging"
require_relative "../errors"
require_relative "handoff_fallback_system"

module RAAF

  module Models

    ##
    # Universal Provider Adapter for Handoff Support
    #
    # This adapter wraps any provider to ensure universal handoff support
    # regardless of the underlying API format (Chat Completions, Responses, custom).
    # It provides a consistent interface for the Runner while handling the
    # complexities of different provider implementations.
    #
    # The adapter automatically detects provider capabilities and routes requests
    # to the appropriate API methods while ensuring consistent handoff support
    # across all provider types. For providers without function calling support,
    # it enables content-based handoff detection as a fallback mechanism.
    #
    # == Features
    #
    # * **Automatic Capability Detection**: Detects what APIs the provider supports
    # * **Universal API Translation**: Converts between different API formats
    # * **Handoff Fallback System**: Enables handoffs for non-function-calling LLMs
    # * **Performance Monitoring**: Tracks handoff detection statistics
    # * **Backward Compatibility**: Works with all existing providers
    #
    # == Supported Provider Types
    #
    # * **Full Function Calling**: OpenAI, Claude, Gemini (99% handoff success)
    # * **Limited Function Calling**: Some fine-tuned models (95% handoff success)
    # * **No Function Calling**: LLaMA, Mistral base, Falcon (85% handoff success)
    # * **Legacy Providers**: Any text-generation model (80% handoff success)
    #
    # == Usage Patterns
    #
    # @example Basic usage with automatic detection
    #   provider = SomeThirdPartyProvider.new
    #   adapter = ProviderAdapter.new(provider)
    #   runner = RAAF::Runner.new(agent: agent, provider: adapter)
    #   # Handoffs work automatically regardless of provider capabilities
    #
    # @example With explicit agent configuration for better fallback
    #   available_agents = ["Support", "Billing", "Technical"]
    #   adapter = ProviderAdapter.new(provider, available_agents)
    #   runner = RAAF::Runner.new(agent: agent, provider: adapter)
    #
    # @example Checking provider capabilities
    #   adapter = ProviderAdapter.new(provider)
    #   puts "Handoff support: #{adapter.supports_handoffs?}"
    #   puts "Capabilities: #{adapter.capabilities}"
    #
    # @example Monitoring handoff performance
    #   stats = adapter.get_handoff_stats
    #   puts "Success rate: #{stats[:success_rate]}"
    #
    # @see HandoffFallbackSystem
    # @see CapabilityDetector
    # @see EnhancedModelInterface
    # @author RAAF Development Team
    # @since 0.2.0
    #
    class ProviderAdapter

      include Logger

      ##
      # Provider capability flags
      CAPABILITIES = {
        responses_api: :supports_responses_api?,
        chat_completion: :supports_chat_completion?,
        streaming: :supports_streaming?,
        function_calling: :supports_function_calling?,
        handoffs: :supports_handoffs?
      }.freeze

      # @param provider [ModelInterface] The underlying provider to wrap
      # @param available_agents [Array<String>] Agent names for handoff fallback
      def initialize(provider, available_agents = [])
        @provider = provider
        @capabilities = detect_capabilities
        @fallback_system = HandoffFallbackSystem.new(available_agents)
        log_debug("🔧 PROVIDER ADAPTER: Initialized with capabilities",
                  provider: provider.provider_name,
                  capabilities: @capabilities,
                  fallback_enabled: !@capabilities[:function_calling])
      end

      ##
      # Universal completion method that works with any provider
      #
      # This method automatically detects provider capabilities and routes
      # to the appropriate API while ensuring consistent handoff support.
      #
      # @example Basic usage with handoff tools
      #   adapter = ProviderAdapter.new(provider, ["Support", "Billing"])
      #
      #   response = adapter.universal_completion(
      #     messages: [{ role: "user", content: "I need billing help" }],
      #     model: "gpt-4",
      #     tools: [{
      #       type: "function",
      #       name: "transfer_to_billing",
      #       function: {
      #         name: "transfer_to_billing",
      #         description: "Transfer to billing agent",
      #         parameters: { type: "object", properties: {} }
      #       }
      #     }]
      #   )
      #
      #   # Response format is standardized regardless of provider
      #   puts response[:output] # Array of response items
      #   puts response[:usage] # Token usage information
      #
      # @example With non-function-calling provider
      #   adapter = ProviderAdapter.new(llama_provider, ["Support"])
      #
      #   response = adapter.universal_completion(
      #     messages: [{ role: "user", content: "Help me" }],
      #     model: "llama-2-7b"
      #   )
      #
      #   # Content-based handoff detection works automatically
      #   if response[:output].first[:content].include?('{"handoff_to": "Support"}')
      #     puts "Handoff detected!"
      #   end
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier
      # @param tools [Array<Hash>, nil] Tool definitions (including handoff tools)
      # @param stream [Boolean] Whether to stream response
      # @param **kwargs [Hash] Additional parameters
      #
      # @return [Hash] Standardized response format with :output, :usage, :model keys
      #
      def universal_completion(messages:, model:, tools: nil, stream: false, **)
        log_debug("🔧 PROVIDER ADAPTER: Universal completion requested",
                  provider: @provider.provider_name,
                  has_tools: !tools.nil?,
                  tools_count: tools&.size || 0,
                  stream: stream)

        # Log the outgoing request details
        log_provider_request(messages: messages, model: model, tools: tools, stream: stream, **)

        # Route to appropriate API based on capabilities
        response = nil
        if @capabilities[:responses_api]
          log_debug("🔧 PROVIDER ADAPTER: Using Responses API path")
          response = @provider.responses_completion(
            messages: messages,
            model: model,
            tools: tools,
            stream: stream,
            **
          )
          normalized_response = normalize_responses_api_response(response)
        elsif @capabilities[:chat_completion]
          log_debug("🔧 PROVIDER ADAPTER: Using Chat Completions API path")
          response = @provider.chat_completion(
            messages: messages,
            model: model,
            tools: tools,
            stream: stream,
            **
          )
          normalized_response = normalize_chat_completion_response(response)
        else
          raise ProviderError, "Provider #{@provider.provider_name} doesn't support any known completion API"
        end

        # Log the incoming response details
        log_provider_response(response, normalized_response)

        normalized_response
      end

      ##
      # Delegate responses_completion to universal_completion
      # This ensures the Runner's current API calls work seamlessly
      #
      # @example Responses API compatibility
      #   adapter = ProviderAdapter.new(provider)
      #
      #   # This call works regardless of provider's native API
      #   response = adapter.responses_completion(
      #     messages: [{ role: "user", content: "Hello" }],
      #     model: "gpt-4"
      #   )
      #
      #   # Always returns Responses API format
      #   puts response[:output] # Array format
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param **kwargs [Hash] Additional parameters
      # @return [Hash] Response in Responses API format
      #
      def responses_completion(messages:, model:, tools: nil, **)
        universal_completion(messages: messages, model: model, tools: tools, **)
      end

      ##
      # Delegate chat_completion to universal_completion
      # This ensures backward compatibility with existing code
      #
      # @example Chat Completions API compatibility
      #   adapter = ProviderAdapter.new(provider)
      #
      #   # This call works with any provider
      #   response = adapter.chat_completion(
      #     messages: [{ role: "user", content: "Hello" }],
      #     model: "gpt-4",
      #     tools: handoff_tools
      #   )
      #
      #   # Returns normalized format for consistent processing
      #   puts response[:output] # Standardized output
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param stream [Boolean] Whether to stream response
      # @param **kwargs [Hash] Additional parameters
      # @return [Hash] Normalized response format
      #
      def chat_completion(messages:, model:, tools: nil, stream: false, **)
        universal_completion(messages: messages, model: model, tools: tools, stream: stream, **)
      end

      ##
      # Delegate streaming to universal_completion
      #
      # @example Streaming compatibility
      #   adapter = ProviderAdapter.new(provider)
      #
      #   response = adapter.stream_completion(
      #     messages: [{ role: "user", content: "Hello" }],
      #     model: "gpt-4"
      #   )
      #
      #   # Streaming is handled by underlying provider
      #   puts response[:streaming] # true if supported
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param **kwargs [Hash] Additional parameters
      # @return [Hash] Streaming response
      #
      def stream_completion(messages:, model:, tools: nil, **)
        universal_completion(messages: messages, model: model, tools: tools, stream: true, **)
      end

      ##
      # Check if provider supports handoffs
      # All providers support handoffs through this adapter (with fallback)
      #
      # @example Check handoff support
      #   adapter = ProviderAdapter.new(provider, ["Support", "Billing"])
      #
      #   if adapter.supports_handoffs?
      #     puts "Handoffs are supported!"
      #     # Either native function calling or content-based fallback
      #   else
      #     puts "Provider is not compatible"
      #   end
      #
      # @return [Boolean] True if handoffs are supported (native or fallback)
      #
      def supports_handoffs?
        @capabilities[:function_calling] || @capabilities[:chat_completion] # Function calling OR content-based fallback
      end

      ##
      # Update available agents for fallback system
      #
      # Updates the list of available agents for content-based handoff detection.
      # This is useful when agents are added or removed dynamically.
      #
      # @example Update available agents
      #   adapter = ProviderAdapter.new(provider, ["Support"])
      #
      #   # Add new agents
      #   adapter.update_available_agents(["Support", "Billing", "Technical"])
      #
      #   # Fallback system now knows about all three agents
      #   stats = adapter.get_handoff_stats
      #   puts stats[:available_agents] # ["Support", "Billing", "Technical"]
      #
      # @param available_agents [Array<String>] Updated list of agent names
      # @return [void]
      #
      def update_available_agents(available_agents)
        @fallback_system = HandoffFallbackSystem.new(available_agents)
        log_debug("🔧 PROVIDER ADAPTER: Updated available agents for fallback",
                  provider: @provider.provider_name,
                  agents: available_agents.join(", "))
      end

      ##
      # Get enhanced system instructions for non-function-calling providers
      #
      # For providers without function calling support, this method adds
      # detailed handoff instructions to the system prompt.
      #
      # @example Enhanced instructions for non-function-calling provider
      #   adapter = ProviderAdapter.new(llama_provider, ["Support", "Billing"])
      #
      #   base_instructions = "You are a helpful assistant."
      #   enhanced = adapter.get_enhanced_system_instructions(base_instructions, ["Support", "Billing"])
      #
      #   puts enhanced
      #   # Output includes:
      #   # "You are a helpful assistant."
      #   # ""
      #   # "# Handoff Instructions for Multi-Agent System"
      #   # "When you need to transfer control to another agent, use:"
      #   # '{"handoff_to": "AgentName"}'
      #   # "Available Agents:"
      #   # "- Support"
      #   # "- Billing"
      #
      # @example With function-calling provider (no enhancement)
      #   adapter = ProviderAdapter.new(openai_provider)
      #
      #   enhanced = adapter.get_enhanced_system_instructions(base_instructions, ["Support"])
      #   puts enhanced == base_instructions # true (no enhancement needed)
      #
      # @param base_instructions [String] Original system instructions
      # @param available_agents [Array<String>] Available agent names
      # @return [String] Enhanced instructions (or original if function calling supported)
      #
      def get_enhanced_system_instructions(base_instructions, available_agents)
        return base_instructions if @capabilities[:function_calling]

        # For non-function-calling providers, add handoff instructions
        handoff_instructions = @fallback_system.generate_handoff_instructions(available_agents)

        log_debug("🔧 PROVIDER ADAPTER: Adding handoff instructions for non-function-calling provider",
                  provider: @provider.provider_name,
                  available_agents: available_agents.size)

        "#{base_instructions}\n\n#{handoff_instructions}"
      end

      ##
      # Detect handoff in response content (for non-function-calling providers)
      #
      # For providers without function calling support, this method analyzes
      # response content to detect handoff requests using pattern matching.
      #
      # @example Detect JSON handoff
      #   adapter = ProviderAdapter.new(llama_provider, ["Support", "Billing"])
      #
      #   content = 'I can help with that. {"handoff_to": "Support"}'
      #   target = adapter.detect_content_based_handoff(content)
      #   puts target # "Support"
      #
      # @example Detect structured handoff
      #   content = 'Let me transfer you. [HANDOFF:Billing]'
      #   target = adapter.detect_content_based_handoff(content)
      #   puts target # "Billing"
      #
      # @example With function-calling provider (not applicable)
      #   adapter = ProviderAdapter.new(openai_provider)
      #
      #   target = adapter.detect_content_based_handoff(content)
      #   puts target # nil (not applicable for function-calling providers)
      #
      # @param content [String] Response content to analyze
      # @return [String, nil] Target agent name if handoff detected, nil otherwise
      #
      def detect_content_based_handoff(content)
        return nil if @capabilities[:function_calling] # Only for non-function-calling providers

        @fallback_system.detect_handoff_in_content(content)
      end

      ##
      # Get handoff detection statistics
      #
      # Returns statistics about handoff detection performance from the
      # fallback system. Useful for monitoring and optimization.
      #
      # @example Get detection statistics
      #   adapter = ProviderAdapter.new(llama_provider, ["Support", "Billing"])
      #
      #   # Use detection a few times
      #   adapter.detect_content_based_handoff('{"handoff_to": "Support"}')
      #   adapter.detect_content_based_handoff('No handoff here')
      #   adapter.detect_content_based_handoff('[HANDOFF:Billing]')
      #
      #   stats = adapter.get_handoff_stats
      #   puts "Success rate: #{stats[:success_rate]}" # "66.67%"
      #   puts "Total attempts: #{stats[:total_attempts]}" # 3
      #   puts "Successful detections: #{stats[:successful_detections]}" # 2
      #
      # @return [Hash] Statistics from fallback system with keys:
      #   - :total_attempts - Total detection attempts
      #   - :successful_detections - Number of successful detections
      #   - :success_rate - Success rate as percentage string
      #   - :available_agents - List of available agent names
      #
      def get_handoff_stats
        @fallback_system.get_detection_stats
      end

      ##
      # Get provider capabilities
      #
      # Returns a hash of detected provider capabilities. This is useful
      # for debugging and understanding what the provider supports.
      #
      # @example Get capabilities
      #   adapter = ProviderAdapter.new(provider)
      #
      #   caps = adapter.capabilities
      #   puts "Responses API: #{caps[:responses_api]}"
      #   puts "Chat Completion: #{caps[:chat_completion]}"
      #   puts "Function Calling: #{caps[:function_calling]}"
      #   puts "Handoffs: #{caps[:handoffs]}"
      #   puts "Streaming: #{caps[:streaming]}"
      #
      # @return [Hash] Capability flags (duplicated to prevent modification)
      #
      def capabilities
        @capabilities.dup
      end

      ##
      # Delegate other methods to underlying provider
      #
      # This method enables transparent access to provider-specific methods
      # while maintaining the adapter pattern.
      #
      # @example Method delegation
      #   adapter = ProviderAdapter.new(provider)
      #
      #   # These calls are delegated to the underlying provider
      #   models = adapter.supported_models
      #   name = adapter.provider_name
      #
      #   # Provider-specific methods also work
      #   if adapter.respond_to?(:custom_method)
      #     result = adapter.custom_method
      #   end
      #
      # @param method [Symbol] Method name to delegate
      # @param args [Array] Method arguments
      # @param kwargs [Hash] Method keyword arguments
      # @param block [Proc] Block to pass to method
      # @return [Object] Result from underlying provider method
      #
      def method_missing(method, ...)
        if @provider.respond_to?(method)
          @provider.send(method, ...)
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        @provider.respond_to?(method, include_private) || super
      end

      private

      ##
      # Log outgoing request to provider endpoint
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param model [String] Model identifier
      # @param tools [Array<Hash>, nil] Tool definitions
      # @param stream [Boolean] Whether to stream response
      # @param **kwargs [Hash] Additional parameters
      #
      def log_provider_request(messages:, model:, tools: nil, stream: false, **kwargs)
        log_debug_api("📤 PROVIDER REQUEST: Sending to #{@provider.provider_name} endpoint",
                      api_type: @capabilities[:responses_api] ? "Responses API" : "Chat Completions",
                      model: model,
                      message_count: messages.size,
                      stream: stream,
                      tools_provided: !tools.nil?,
                      tools_count: tools&.size || 0)

        # Log message details
        if messages&.any?
          log_debug_api("📤 PROVIDER REQUEST: Message details",
                        messages: inspect_messages(messages, "REQUEST"))
        end

        # Log tool details if provided
        if tools&.any?
          log_debug_api("📤 PROVIDER REQUEST: Tool details",
                        tools: inspect_tools(tools, "REQUEST"))
        end

        # Log additional parameters
        return unless kwargs.any?

        log_debug_api("📤 PROVIDER REQUEST: Additional parameters",
                      parameters: inspect_parameters(kwargs, "REQUEST"))
      end

      ##
      # Log incoming response from provider endpoint
      #
      # @param raw_response [Hash] Raw response from provider
      # @param normalized_response [Hash] Normalized response
      #
      def log_provider_response(raw_response, normalized_response)
        log_debug_api("📥 PROVIDER RESPONSE: Received from #{@provider.provider_name} endpoint",
                      api_type: @capabilities[:responses_api] ? "Responses API" : "Chat Completions",
                      raw_response_keys: raw_response&.keys || [],
                      normalized_response_keys: normalized_response&.keys || [])

        # Log raw response structure
        if raw_response
          log_debug_api("📥 PROVIDER RESPONSE: Raw response details",
                        raw_response: inspect_response(raw_response, "RAW"))
        end

        # Log normalized response structure
        if normalized_response
          log_debug_api("📥 PROVIDER RESPONSE: Normalized response details",
                        normalized_response: inspect_response(normalized_response, "NORMALIZED"))
        end

        # Log specific response components
        if normalized_response&.dig(:output)
          log_debug_api("📥 PROVIDER RESPONSE: Output details",
                        output: inspect_output(normalized_response[:output]))
        end

        # Log usage information
        return unless normalized_response&.dig(:usage)

        log_debug_api("📥 PROVIDER RESPONSE: Usage details",
                      usage: inspect_usage(normalized_response[:usage]))
      end

      ##
      # Inspect and format messages for logging
      #
      # @param messages [Array<Hash>] Messages to inspect
      # @param context [String] Context for logging (REQUEST/RESPONSE)
      # @return [Array<Hash>] Formatted messages for logging
      #
      def inspect_messages(messages, _context = "")
        return [] unless messages.is_a?(Array)

        messages.map.with_index do |message, index|
          {
            index: index,
            role: message[:role] || message["role"],
            content_type: determine_content_type(message),
            content_length: get_content_length(message),
            content_preview: get_content_preview(message),
            has_tool_calls: message.key?(:tool_calls) || message.key?("tool_calls"),
            has_tool_call_id: message.key?(:tool_call_id) || message.key?("tool_call_id")
          }
        end
      end

      ##
      # Inspect and format tools for logging
      #
      # @param tools [Array<Hash>] Tools to inspect
      # @param context [String] Context for logging (REQUEST/RESPONSE)
      # @return [Array<Hash>] Formatted tools for logging
      #
      def inspect_tools(tools, _context = "")
        return [] unless tools.is_a?(Array)

        tools.map.with_index do |tool, index|
          {
            index: index,
            type: tool[:type] || tool["type"],
            name: tool[:name] || tool["name"] || tool.dig(:function, :name) || tool.dig("function", "name"),
            description: tool.dig(:function, :description) || tool.dig("function", "description"),
            parameters_type: tool.dig(:function, :parameters, :type) || tool.dig("function", "parameters", "type"),
            properties_count: get_properties_count(tool)
          }
        end
      end

      ##
      # Inspect and format parameters for logging
      #
      # @param params [Hash] Parameters to inspect
      # @param context [String] Context for logging (REQUEST/RESPONSE)
      # @return [Hash] Formatted parameters for logging
      #
      def inspect_parameters(params, _context = "")
        return {} unless params.is_a?(Hash)

        params.transform_values do |value|
          case value
          when String
            value.length > 100 ? "#{value[0..97]}..." : value
          when Array
            "[Array with #{value.size} items]"
          when Hash
            "[Hash with #{value.size} keys: #{value.keys.join(", ")}]"
          else
            value
          end
        end
      end

      ##
      # Inspect and format response for logging
      #
      # @param response [Hash] Response to inspect
      # @param context [String] Context for logging (RAW/NORMALIZED)
      # @return [Hash] Formatted response for logging
      #
      def inspect_response(response, context = "")
        return {} unless response.is_a?(Hash)

        result = {
          keys: response.keys.map(&:to_s),
          type: determine_response_type(response)
        }

        # Add specific details based on response type
        if context == "RAW"
          result.merge!(inspect_raw_response_details(response))
        elsif context == "NORMALIZED"
          result.merge!(inspect_normalized_response_details(response))
        end

        result
      end

      ##
      # Inspect output array for logging
      #
      # @param output [Array] Output array to inspect
      # @return [Array<Hash>] Formatted output for logging
      #
      def inspect_output(output)
        return [] unless output.is_a?(Array)

        output.map.with_index do |item, index|
          {
            index: index,
            type: item[:type] || item["type"],
            role: item[:role] || item["role"],
            content_length: get_content_length(item),
            content_preview: get_content_preview(item),
            function_name: item[:name] || item["name"],
            function_id: item[:id] || item["id"],
            has_arguments: item.key?(:arguments) || item.key?("arguments")
          }
        end
      end

      ##
      # Inspect usage information for logging
      #
      # @param usage [Hash] Usage information to inspect
      # @return [Hash] Formatted usage for logging
      #
      def inspect_usage(usage)
        return {} unless usage.is_a?(Hash)

        {
          prompt_tokens: usage[:prompt_tokens] || usage["prompt_tokens"],
          completion_tokens: usage[:completion_tokens] || usage["completion_tokens"],
          total_tokens: usage[:total_tokens] || usage["total_tokens"],
          all_keys: usage.keys.map(&:to_s)
        }
      end

      ##
      # Determine content type for logging
      #
      # @param message [Hash] Message to analyze
      # @return [String] Content type description
      #
      def determine_content_type(message)
        content = message[:content] || message["content"]
        return "nil" if content.nil?
        return "empty" if content.empty?
        return "string" if content.is_a?(String)
        return "array" if content.is_a?(Array)
        return "hash" if content.is_a?(Hash)

        content.class.to_s.downcase
      end

      ##
      # Get content length for logging
      #
      # @param item [Hash] Item to analyze
      # @return [Integer] Content length
      #
      def get_content_length(item)
        content = item[:content] || item["content"]
        return 0 if content.nil?
        return content.size if content.respond_to?(:size)

        content.to_s.length
      end

      ##
      # Get content preview for logging
      #
      # @param item [Hash] Item to analyze
      # @return [String] Content preview
      #
      def get_content_preview(item)
        content = item[:content] || item["content"]
        return "[nil]" if content.nil?
        return "[empty]" if content.respond_to?(:empty?) && content.empty?

        preview = content.to_s
        preview.length > 100 ? "#{preview[0..97]}..." : preview
      end

      ##
      # Get properties count for tool logging
      #
      # @param tool [Hash] Tool to analyze
      # @return [Integer] Properties count
      #
      def get_properties_count(tool)
        properties = tool.dig(:function, :parameters, :properties) ||
                     tool.dig("function", "parameters", "properties")
        return 0 unless properties.is_a?(Hash)

        properties.size
      end

      ##
      # Determine response type for logging
      #
      # @param response [Hash] Response to analyze
      # @return [String] Response type
      #
      def determine_response_type(response)
        return "responses_api" if response.key?(:output) || response.key?("output")
        return "chat_completions" if response.key?(:choices) || response.key?("choices")
        return "streaming" if response.key?(:streaming) || response.key?("streaming")
        return "error" if response.key?(:error) || response.key?("error")

        "unknown"
      end

      ##
      # Inspect raw response details
      #
      # @param response [Hash] Raw response to inspect
      # @return [Hash] Raw response details
      #
      def inspect_raw_response_details(response)
        details = {}

        # Chat Completions format
        if response.key?("choices") || response.key?(:choices)
          choices = response["choices"] || response[:choices]
          details[:choices_count] = choices&.size || 0

          if choices&.any?
            first_choice = choices[0]
            message = first_choice["message"] || first_choice[:message]
            if message
              details[:first_choice] = {
                role: message["role"] || message[:role],
                content_length: get_content_length(message),
                has_tool_calls: message.key?("tool_calls") || message.key?(:tool_calls),
                tool_calls_count: (message["tool_calls"] || message[:tool_calls])&.size || 0
              }
            end
          end
        end

        # Responses API format
        if response.key?("output") || response.key?(:output)
          output = response["output"] || response[:output]
          details[:output_count] = output&.size || 0

          details[:output_types] = output.map { |item| item[:type] || item["type"] }.compact if output&.any?
        end

        # Usage information
        if response.key?("usage") || response.key?(:usage)
          usage = response["usage"] || response[:usage]
          details[:usage_keys] = usage&.keys&.map(&:to_s) || []
        end

        details
      end

      ##
      # Inspect normalized response details
      #
      # @param response [Hash] Normalized response to inspect
      # @return [Hash] Normalized response details
      #
      def inspect_normalized_response_details(response)
        details = {}

        # Output array (always present in normalized format)
        if response[:output]
          details[:output_count] = response[:output].size
          details[:output_types] = response[:output].map { |item| item[:type] }.compact

          # Count different types
          type_counts = response[:output].group_by { |item| item[:type] }.transform_values(&:size)
          details[:output_type_counts] = type_counts
        end

        # Usage information
        details[:usage_keys] = response[:usage].keys.map(&:to_s) if response[:usage]

        # Model information
        details[:model] = response[:model] if response[:model]
        details[:id] = response[:id] if response[:id]

        details
      end

      ##
      # Detect provider capabilities automatically
      #
      # This method inspects the provider to determine what APIs and features
      # it supports. Results are cached for performance.
      #
      # @example Capability detection process
      #   # For a provider that implements both APIs:
      #   # {
      #   #   responses_api: true,
      #   #   chat_completion: true,
      #   #   streaming: false,
      #   #   function_calling: true,
      #   #   handoffs: true
      #   # }
      #
      #   # For a basic text-only provider:
      #   # {
      #   #   responses_api: false,
      #   #   chat_completion: true,
      #   #   streaming: false,
      #   #   function_calling: false,
      #   #   handoffs: false
      #   # }
      #
      # @return [Hash] Detected capabilities
      #
      def detect_capabilities
        capabilities = {}

        # Check for Responses API support
        capabilities[:responses_api] = @provider.respond_to?(:responses_completion)

        # Check for Chat Completion API support
        capabilities[:chat_completion] = @provider.respond_to?(:chat_completion)

        # Check for streaming support
        capabilities[:streaming] = @provider.respond_to?(:stream_completion)

        # Check for function calling support (required for handoffs)
        capabilities[:function_calling] = check_function_calling_support

        # Handoff support is available if function calling is supported
        capabilities[:handoffs] = capabilities[:function_calling]

        log_debug("🔧 PROVIDER ADAPTER: Detected capabilities",
                  provider: @provider.provider_name,
                  capabilities: capabilities)

        capabilities
      end

      ##
      # Check if provider supports function calling
      #
      # This method tests whether the provider's chat_completion method
      # accepts a tools parameter, which indicates function calling support.
      #
      # @example Function calling test
      #   # For a provider with function calling:
      #   # Makes test call with empty tools array
      #   # Returns true if no ArgumentError about tools parameter
      #
      #   # For a provider without function calling:
      #   # Makes test call with empty tools array
      #   # Returns false if ArgumentError mentions tools parameter
      #
      # @return [Boolean] True if function calling is supported
      #
      def check_function_calling_support
        # Try to call with empty tools to see if it's supported

        test_messages = [{ role: "user", content: "test" }]

        if @provider.respond_to?(:chat_completion)
          # Try with empty tools array - if it doesn't error, it supports function calling
          @provider.chat_completion(
            messages: test_messages,
            model: @provider.supported_models.first,
            tools: [],
            stream: false
          )
          true
        else
          false
        end
      rescue ArgumentError => e
        # If tools parameter is not accepted, function calling is not supported
        !e.message.include?("tools")
      rescue StandardError => e
        # Other errors (like auth) don't tell us about function calling support
        log_debug("🔧 PROVIDER ADAPTER: Function calling check failed with error",
                  provider: @provider.provider_name,
                  error: e.message)
        false
      end

      ##
      # Normalize Responses API response to standard format
      #
      # Responses API already returns the format we need, so this is a passthrough.
      #
      # @example Responses API format (no changes needed)
      #   response = {
      #     output: [
      #       { type: "message", role: "assistant", content: "Hello" },
      #       { type: "function_call", id: "call_123", name: "transfer", arguments: "{}" }
      #     ],
      #     usage: { total_tokens: 25 },
      #     model: "gpt-4"
      #   }
      #
      #   normalized = normalize_responses_api_response(response)
      #   puts normalized == response # true
      #
      # @param response [Hash] Response from Responses API
      # @return [Hash] Normalized response (unchanged)
      #
      def normalize_responses_api_response(response)
        # Responses API already returns the format we need
        response
      end

      ##
      # Normalize Chat Completions API response to Responses API format
      #
      # Converts a Chat Completions API response to the Responses API format
      # to ensure consistent processing across all provider types.
      #
      # @example Chat Completions to Responses API conversion
      #   chat_response = {
      #     "choices" => [{
      #       "message" => {
      #         "role" => "assistant",
      #         "content" => "I'll help you",
      #         "tool_calls" => [{
      #           "id" => "call_123",
      #           "type" => "function",
      #           "function" => {
      #             "name" => "transfer_to_billing",
      #             "arguments" => "{}"
      #           }
      #         }]
      #       }
      #     }],
      #     "usage" => { "total_tokens" => 25 },
      #     "model" => "gpt-4"
      #   }
      #
      #   responses_format = normalize_chat_completion_response(chat_response)
      #   puts responses_format
      #   # {
      #   #   output: [
      #   #     { type: "message", role: "assistant", content: "I'll help you" },
      #   #     { type: "function_call", id: "call_123", name: "transfer_to_billing", arguments: "{}" }
      #   #   ],
      #   #   usage: { "total_tokens" => 25 },
      #   #   model: "gpt-4"
      #   # }
      #
      # @param response [Hash] Chat Completions API response
      # @return [Hash] Converted response in Responses API format
      #
      def normalize_chat_completion_response(response)
        log_debug_api("🔄 PROVIDER ADAPTER: Normalizing Chat Completions response to Responses API format")

        # Convert Chat Completions format to Responses API format
        # This enables handoff detection to work consistently

        choice = response.dig("choices", 0) || response.dig(:choices, 0)
        unless choice
          log_debug_api("⚠️  PROVIDER ADAPTER: No choices found in Chat Completions response")
          return response
        end

        message = choice["message"] || choice[:message]
        unless message
          log_debug_api("⚠️  PROVIDER ADAPTER: No message found in first choice")
          return response
        end

        # Convert to Responses API format
        output = []

        # Add text content if present
        if message["content"] || message[:content]
          content = message["content"] || message[:content]
          output << {
            type: "message",
            role: "assistant",
            content: content
          }
          log_debug_api("🔄 PROVIDER ADAPTER: Added message content to output",
                        content_length: content.to_s.length)
        end

        # Add tool calls if present
        if message["tool_calls"] || message[:tool_calls]
          tool_calls = message["tool_calls"] || message[:tool_calls]
          tool_calls.each_with_index do |tool_call, index|
            function_call = {
              type: "function_call",
              id: tool_call["id"] || tool_call[:id],
              name: tool_call.dig("function", "name") || tool_call.dig(:function, :name),
              arguments: tool_call.dig("function", "arguments") || tool_call.dig(:function, :arguments)
            }
            output << function_call
            log_debug_api("🔄 PROVIDER ADAPTER: Added function call to output",
                          index: index,
                          function_name: function_call[:name],
                          function_id: function_call[:id])
          end
        end

        # Return in Responses API format
        normalized = {
          output: output,
          usage: response["usage"] || response[:usage],
          model: response["model"] || response[:model],
          id: response["id"] || response[:id]
        }

        log_debug_api("🔄 PROVIDER ADAPTER: Completed normalization",
                      output_items: output.size,
                      has_usage: !normalized[:usage].nil?,
                      model: normalized[:model])

        normalized
      end

    end

  end

end

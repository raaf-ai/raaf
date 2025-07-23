# frozen_string_literal: true

require_relative "logging"

module RAAF

  module Execution

    ##
    # Base strategy for API provider interactions
    #
    # This class defines the interface that all API strategies must implement
    # and provides common functionality. It uses the Strategy pattern to handle
    # different AI provider APIs with a unified interface.
    #
    # @example Implementing a custom strategy
    #   class CustomApiStrategy < BaseApiStrategy
    #     def execute(messages, agent, runner)
    #       # Custom implementation for specific provider
    #       api_response = make_custom_api_call(messages)
    #       {
    #         message: extract_message_from_response(api_response),
    #         usage: extract_usage_from_response(api_response),
    #         response: api_response
    #       }
    #     end
    #   end
    #
    # @see StandardApiStrategy For traditional chat completion APIs
    # @see ResponsesApiStrategy For OpenAI Responses API
    #
    class BaseApiStrategy

      include Logger

      attr_reader :provider, :config

      ##
      # Initialize strategy with provider and configuration
      #
      # @param provider [Models::Interface] The AI provider instance
      # @param config [RunConfig] Execution configuration
      #
      def initialize(provider, config)
        @provider = provider
        @config = config
      end

      ##
      # Execute API call with the given strategy
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param agent [Agent] The agent making the request
      # @param runner [Runner] Runner for additional context
      # @return [Hash] API response
      #
      def execute(messages, agent, runner)
        raise NotImplementedError, "Subclasses must implement #execute"
      end

      protected

      ##
      # Build base model parameters from agent and config
      #
      # Constructs common model parameters that apply across different API strategies,
      # including response format and tool choice settings.
      #
      # @param agent [Agent] The agent with model configuration
      # @return [Hash] Base model parameters for API calls
      #
      def build_base_model_params(agent)
        model_params = config.to_model_params

        # Merge with agent's model settings if available
        if agent&.model_settings
          model_settings_params = agent.model_settings.to_h
          model_params.merge!(model_settings_params)
        end

        # Add structured output support (agent-level overrides model settings)
        model_params[:response_format] = agent.response_format if agent&.response_format

        # Add tool choice support (agent-level overrides model settings)
        model_params[:tool_choice] = agent.tool_choice if agent&.respond_to?(:tool_choice) && agent&.tool_choice

        model_params
      end

      ##
      # Extract assistant message from provider response
      #
      # Handles different response formats from various AI providers,
      # normalizing them to a consistent message format.
      #
      # @param response [Hash, Object] Provider API response
      # @return [Hash] Normalized message with :role and :content
      #
      def extract_message_from_response(response)
        if response.is_a?(Hash)
          # Handle both symbol and string keys
          choices = response[:choices] || response["choices"]
          if choices&.first
            # Standard OpenAI format - extract message from first choice
            choice = choices.first
            message = choice[:message] || choice["message"]
            if message
              # Ensure we return with symbol keys for consistency
              return normalize_message_keys(message)
            end
          end
          
          # Direct message format
          if response[:message] || response["message"]
            message = response[:message] || response["message"]
            return normalize_message_keys(message)
          end
          
          # Fallback to response itself
          normalize_message_keys(response)
        else
          # Non-hash response
          { role: "assistant", content: response.to_s }
        end
      end

      ##
      # Normalize message keys to symbols
      #
      # @param message [Hash] Message with potentially string keys
      # @return [Hash] Message with symbol keys
      #
      def normalize_message_keys(message)
        return message unless message.is_a?(Hash)
        
        normalized = {}
        message.each do |key, value|
          symbol_key = key.to_sym
          normalized[symbol_key] = value
        end
        normalized
      end

      ##
      # Extract token usage data from provider response
      #
      # @param response [Hash] Provider API response
      # @return [Hash, nil] Usage statistics or nil if not available
      #
      def extract_usage_from_response(response)
        return nil unless response.is_a?(Hash)

        # Handle both symbol and string keys
        response[:usage] || response["usage"]
      end

    end

    ##
    # Strategy for standard chat completion APIs
    #
    # Handles providers that use the standard chat completion format,
    # including OpenAI Chat Completions API, Anthropic Claude, and other
    # compatible providers. This strategy is suitable for most traditional
    # conversational AI APIs.
    #
    # @example Usage with OpenAI Chat Completions
    #   provider = OpenAIProvider.new
    #   config = RunConfig.new(temperature: 0.7)
    #   strategy = StandardApiStrategy.new(provider, config)
    #   result = strategy.execute(messages, agent, runner)
    #
    # @example Expected result format
    #   {
    #     message: { role: "assistant", content: "Response text" },
    #     usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
    #     response: { /* full provider response */ }
    #   }
    #
    class StandardApiStrategy < BaseApiStrategy

      ##
      # Execute using standard chat completion API
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param agent [Agent] The agent making the request
      # @param runner [Runner] Runner for message building
      # @return [Hash] Result with :message, :usage, :response
      #
      def execute(messages, agent, runner)
        # Build messages for API call
        api_messages = runner.build_messages(messages, agent)
        model = config.model&.model || agent&.model || "gpt-4"
        model_params = build_model_params(agent, runner)

        log_debug_api("Making standard API call", model: model, provider: provider.class.name)

        # Make API call
        response = make_api_call(api_messages, model, model_params)

        # Extract results
        message = extract_message_from_response(response)
        usage = extract_usage_from_response(response)

        {
          message: message,
          usage: usage,
          response: response
        }
      end

      private

      ##
      # Build model parameters specific to standard APIs
      #
      # Extends base model parameters with provider-specific features
      # like prompt support for compatible providers.
      #
      # @param agent [Agent] The agent with configuration
      # @param runner [Runner] Runner instance (unused but kept for consistency)
      # @return [Hash] Complete model parameters for API call
      #
      def build_model_params(agent, _runner)
        model_params = build_base_model_params(agent)

        # Add prompt support for compatible providers
        if agent&.prompt && provider.respond_to?(:supports_prompts?) && provider.supports_prompts?
          prompt_input = PromptUtil.to_model_input(agent.prompt, nil, agent)
          model_params[:prompt] = prompt_input if prompt_input
        end

        model_params
      end

      ##
      # Make API call to provider
      #
      # Calls either streaming or non-streaming completion based on configuration.
      # Uses the provider's standard completion methods.
      #
      # @param api_messages [Array<Hash>] Formatted conversation messages
      # @param model [String] Model identifier
      # @param model_params [Hash] Additional model parameters
      # @return [Hash] Provider API response
      #
      def make_api_call(api_messages, model, model_params)
        if config.stream
          provider.stream_completion(
            messages: api_messages,
            model: model,
            **model_params
          )
        else
          provider.complete(
            messages: api_messages,
            model: model,
            **model_params
          )
        end
      end

    end

    ##
    # Strategy for OpenAI Responses API
    #
    # Handles OpenAI's newer Responses API (/v1/responses) which uses an
    # items-based conversation format instead of traditional messages.
    # This API provides enhanced features like better streaming support,
    # more detailed usage statistics, and improved conversation continuity.
    #
    # The key difference is that this strategy converts traditional message
    # arrays into the Responses API's "items" format, where tool calls and
    # function results are separate items rather than embedded in messages.
    #
    # @example Usage with ResponsesProvider
    #   provider = ResponsesProvider.new
    #   config = RunConfig.new(temperature: 0.7, stream: true)
    #   strategy = ResponsesApiStrategy.new(provider, config)
    #   result = strategy.execute(messages, agent, runner)
    #
    # @example Message to Items transformation
    #   # Input messages format:
    #   [
    #     { role: "user", content: "What's the weather?" },
    #     { role: "assistant", tool_calls: [...] },
    #     { role: "tool", content: "75°F", tool_call_id: "123" }
    #   ]
    #
    #   # Converted to items format:
    #   [
    #     { type: "message", role: "user", content: "What's the weather?" },
    #     { type: "function", name: "get_weather", arguments: "{}", id: "123" },
    #     { type: "function_result", function_call_id: "123", content: "75°F" }
    #   ]
    #
    # @see https://platform.openai.com/docs/api-reference/responses OpenAI Responses API
    #
    class ResponsesApiStrategy < BaseApiStrategy

      ##
      # Execute using Responses API
      #
      # @param messages [Array<Hash>] Conversation messages
      # @param agent [Agent] The agent making the request
      # @param runner [Runner] Runner for context (unused in this strategy)
      # @return [Hash] Result with final conversation and usage
      #
      def execute(messages, _agent, runner)
        log_debug_api("Using Responses API", provider: provider.class.name)

        # Use the runner's execute_responses_api_core method which handles multi-turn properly
        # This delegates the complex multi-turn logic back to the runner
        result = runner.send(:execute_responses_api_core, messages, config, with_tracing: false)

        # Convert RunResult to the expected format
        {
          conversation: result.messages,
          usage: result.usage,
          final_result: true,
          last_agent: result.last_agent,
          turns: result.turns,
          tool_results: result.tool_results
        }
      end

      private

      ##
      # Convert traditional messages to Responses API items format
      #
      # Transforms the standard conversation message format into the items-based
      # format required by the OpenAI Responses API. This includes:
      # - Converting regular messages to message items
      # - Extracting tool calls into separate function items
      # - Converting tool results to function_result items
      #
      # @param messages [Array<Hash>] Traditional conversation messages
      # @return [Array<Hash>] Items formatted for Responses API
      # @private
      #
      def convert_messages_to_items(messages)
        messages.map do |msg|
          case msg[:role]
          when "system"
            { type: "message", role: "system", content: msg[:content] }
          when "user"
            { type: "message", role: "user", content: msg[:content] }
          when "assistant"
            if msg[:tool_calls]
              [
                { type: "message", role: "assistant", content: msg[:content] || "" },
                msg[:tool_calls].map do |tc|
                  {
                    type: "function",
                    name: tc.dig("function", "name") || tc[:function][:name],
                    arguments: tc.dig("function", "arguments") || tc[:function][:arguments],
                    id: tc["id"] || tc[:id]
                  }
                end
              ].flatten
            else
              { type: "message", role: "assistant", content: msg[:content] }
            end
          when "tool"
            {
              type: "function_result",
              function_call_id: msg[:tool_call_id],
              content: msg[:content]
            }
          else
            msg
          end
        end.flatten
      end

      ##
      # Build parameters specific to the Responses API provider
      #
      # Constructs the parameter structure required by the Responses API,
      # including modalities, tools, and model configuration. Handles
      # agent-specific settings like response format and tool choice.
      #
      # @param agent [Agent] The agent with configuration and tools
      # @return [Hash] Parameters formatted for Responses API calls
      # @private
      #
      def build_provider_params(agent)
        params = {
          modalities: ["text"],
          prompt: agent&.prompt&.to_api_format,
          tools: format_agent_tools(agent),
          temperature: config.temperature,
          max_tokens: config.max_tokens,
          metadata: config.metadata
        }.compact

        # Add response format if specified
        params[:response_format] = agent.response_format if agent&.response_format

        # Add tool choice if specified
        params[:tool_choice] = agent.tool_choice if agent&.respond_to?(:tool_choice) && agent&.tool_choice

        params
      end

      ##
      # Format agent tools for Responses API
      #
      # Converts agent tools to the format expected by the Responses API.
      # Handles both FunctionTool objects and raw tool definitions.
      #
      # @param agent [Agent] Agent containing tools to format
      # @return [Array<Hash>, nil] Formatted tools or nil if no tools
      # @private
      #
      def format_agent_tools(agent)
        return nil unless agent&.tools && !agent.tools.empty?

        agent.tools.map do |tool|
          if tool.respond_to?(:to_tool_definition)
            tool.to_tool_definition
          else
            tool
          end
        end
      end

      ##
      # Execute the Responses API call
      #
      # Makes either streaming or non-streaming calls to the Responses API
      # using the provider's specialized methods. Uses the items format
      # instead of traditional messages.
      #
      # @param items [Array<Hash>] Conversation items in Responses API format
      # @param model [String] Model identifier
      # @param provider_params [Hash] Parameters for the API call
      # @return [Hash] Provider API response
      # @private
      #
      def make_api_call(items, model, provider_params)
        if config.stream
          provider.stream_completion(
            messages: [],
            model: model,
            input: items,
            **provider_params
          )
        else
          provider.responses_completion(
            messages: [],
            model: model,
            input: items,
            **provider_params
          )
        end
      end

      ##
      # Process Responses API response into final result
      #
      # Converts the Responses API response back to the standard message format
      # and combines it with the original conversation to create a complete
      # conversation history.
      #
      # @param original_messages [Array<Hash>] Original conversation messages
      # @param response [Hash] Raw Responses API response
      # @return [Hash] Final result with conversation, usage, and metadata
      # @private
      #
      def process_response(original_messages, response)
        conversation = original_messages.dup
        usage = response[:usage] || {}

        # Convert response back to messages format
        new_messages = convert_response_to_messages(response)
        conversation.concat(new_messages)

        {
          conversation: conversation,
          usage: usage,
          final_result: true # Indicates this is a complete result, not a turn result
        }
      end

      ##
      # Convert Responses API response back to standard message format
      #
      # Transforms the response from the Responses API back into the traditional
      # message format used throughout the rest of the system. Handles both
      # regular content and tool calls in the response.
      #
      # @param response [Hash] Raw Responses API response
      # @return [Array<Hash>] Messages in standard format
      # @private
      #
      def convert_response_to_messages(response)
        # Convert Responses API response back to messages format
        # The Responses API uses 'output' array instead of 'choices'
        return [] unless response.is_a?(Hash)

        output = response[:output] || response["output"]
        return [] unless output

        messages = []
        assistant_content = ""
        tool_calls = []

        output.each do |item|
          item_type = item[:type] || item["type"]

          case item_type
          when "message", "text", "output_text"
            content = item[:content] || item["content"]
            if content.is_a?(Array)
              # Handle array format like [{ type: "text", text: "content" }]
              content.each do |content_item|
                if content_item.is_a?(Hash)
                  text = content_item[:text] || content_item["text"]
                  assistant_content += text if text
                end
              end
            elsif content.is_a?(String)
              assistant_content += content
            end
          when "function_call"
            # Convert to tool call format
            tool_calls << {
              "id" => item[:call_id] || item["call_id"] || item[:id] || item["id"],
              "function" => {
                "name" => item[:name] || item["name"],
                "arguments" => item[:arguments] || item["arguments"] || "{}"
              }
            }
          end
        end

        # Add assistant message if we have content or tool calls
        if !assistant_content.empty? || !tool_calls.empty?
          message = { role: "assistant", content: assistant_content }
          message[:tool_calls] = tool_calls unless tool_calls.empty?
          messages << message
        end

        messages
      end

    end

    ##
    # Factory for creating appropriate API strategies
    #
    class ApiStrategyFactory

      ##
      # Create the appropriate strategy for the given provider
      #
      # @param provider [Models::Interface] The AI provider
      # @param config [RunConfig] Execution configuration
      # @return [BaseApiStrategy] The appropriate strategy instance
      #
      def self.create(provider, config)
        if provider.is_a?(Models::ResponsesProvider)
          ResponsesApiStrategy.new(provider, config)
        else
          StandardApiStrategy.new(provider, config)
        end
      end

    end

  end

end

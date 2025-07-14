# frozen_string_literal: true

module OpenAIAgents
  module Execution
    ##
    # Base strategy for API provider interactions
    #
    # This class defines the interface that all API strategies must implement
    # and provides common functionality.
    #
    class BaseApiStrategy
      include Logger

      attr_reader :provider, :config

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

      def build_base_model_params(agent)
        model_params = config.to_model_params
        
        # Add structured output support
        if agent.response_format
          model_params[:response_format] = agent.response_format
        end
        
        # Add tool choice support
        if agent.respond_to?(:tool_choice) && agent.tool_choice
          model_params[:tool_choice] = agent.tool_choice
        end
        
        model_params
      end

      def extract_message_from_response(response)
        if response.is_a?(Hash)
          if response[:choices] && response[:choices].first
            # Standard OpenAI format
            response[:choices].first[:message]
          elsif response[:message]
            # Direct message format
            response[:message]
          else
            # Fallback to response itself
            response
          end
        else
          # Non-hash response
          { role: "assistant", content: response.to_s }
        end
      end

      def extract_usage_from_response(response)
        return nil unless response.is_a?(Hash)
        response[:usage]
      end
    end

    ##
    # Strategy for standard chat completion APIs
    #
    # Handles providers that use the standard chat completion format
    # (OpenAI Chat Completions, Anthropic, etc.)
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
        model = config.model || agent.model
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

      def build_model_params(agent, runner)
        model_params = build_base_model_params(agent)
        
        # Add prompt support for compatible providers
        if agent.prompt && provider.respond_to?(:supports_prompts?) && provider.supports_prompts?
          prompt_input = PromptUtil.to_model_input(agent.prompt, nil, agent)
          model_params[:prompt] = prompt_input if prompt_input
        end
        
        model_params
      end

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
    # Handles the newer Responses API which uses a different message format
    # with items and provides better streaming support.
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
      def execute(messages, agent, runner)
        log_debug_api("Using Responses API", provider: provider.class.name)
        
        # Convert messages to items format
        items = convert_messages_to_items(messages)
        model = config.model || agent.model
        
        # Build provider parameters
        provider_params = build_provider_params(agent)
        
        # Make API call
        response = make_api_call(items, model, provider_params)
        
        # Process response into final result
        process_response(messages, response)
      end

      private

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

      def build_provider_params(agent)
        params = {
          modalities: ["text"],
          prompt: agent.prompt&.to_api_format,
          tools: format_agent_tools(agent),
          temperature: config.temperature,
          max_tokens: config.max_tokens || config.max_completion_tokens,
          metadata: config.metadata
        }.compact
        
        # Add response format if specified
        if agent.response_format
          params[:response_format] = agent.response_format
        end
        
        # Add tool choice if specified
        if agent.respond_to?(:tool_choice) && agent.tool_choice
          params[:tool_choice] = agent.tool_choice
        end
        
        params
      end

      def format_agent_tools(agent)
        return nil unless agent.tools && !agent.tools.empty?

        agent.tools.map do |tool|
          if tool.respond_to?(:to_tool_definition)
            tool.to_tool_definition
          else
            tool
          end
        end
      end

      def make_api_call(items, model, provider_params)
        if config.stream
          provider.stream_responses(
            items: items,
            model: model,
            **provider_params
          )
        else
          provider.create_response(
            items: items,
            model: model,
            **provider_params
          )
        end
      end

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

      def convert_response_to_messages(response)
        # Convert Responses API response back to messages format
        return [] unless response[:choices]

        messages = []
        choice = response[:choices].first
        return messages unless choice[:message]

        message = choice[:message]
        messages << {
          role: "assistant",
          content: message[:content]
        }

        # Handle tool calls if present
        if message[:tool_calls]
          messages.last[:tool_calls] = message[:tool_calls]
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
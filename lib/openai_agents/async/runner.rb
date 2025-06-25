# frozen_string_literal: true

require "async"
require "async/barrier"
require_relative "../runner"
require_relative "base"

module OpenAIAgents
  module Async
    # Async version of the Runner class that provides true async/await support
    class Runner < OpenAIAgents::Runner
      include Base

      def initialize(agent:, provider: nil, tracer: nil, disabled_tracing: false)
        super
        # Ensure provider supports async if available
        @async_provider = if @provider.respond_to?(:async_chat_completion)
                            @provider
                          else
                            # Wrap synchronous provider
                            AsyncProviderWrapper.new(@provider)
                          end
      end

      # Async version of run - returns a Task that can be awaited
      def run_async(messages, stream: false, config: nil, **kwargs)
        Async do
          # Normalize messages input
          messages = normalize_messages(messages)

          # Create config
          config = create_config(config, stream, kwargs)

          # Run with or without tracing
          if should_trace?(config)
            run_with_tracing_async(messages, config: config)
          else
            run_without_tracing_async(messages, config: config)
          end
        end
      end

      # Synchronous run that waits for async completion
      def run(messages, stream: false, config: nil, **)
        task = run_async(messages, stream: stream, config: config, **)
        task.wait
      end

      private

      def create_config(config, stream, kwargs)
        if config.nil? && !kwargs.empty?
          RunConfig.new(
            stream: stream,
            workflow_name: kwargs[:workflow_name] || "Agent workflow",
            trace_id: kwargs[:trace_id],
            group_id: kwargs[:group_id],
            metadata: kwargs[:metadata],
            **kwargs
          )
        elsif config.nil?
          RunConfig.new(stream: stream)
        else
          config
        end
      end

      def should_trace?(config)
        !config.tracing_disabled && !@disabled_tracing && !@tracer.nil?
      end

      def run_with_tracing_async(messages, config:, parent_span: nil)
        @current_config = config
        conversation = messages.dup
        current_agent = @agent
        turns = 0
        max_turns = config.max_turns || current_agent.max_turns

        while turns < max_turns
          # Create agent span
          agent_result = create_agent_span_async(current_agent) do |agent_span|
            # Get response from provider
            response_result = get_response_async(
              current_agent,
              conversation,
              config,
              agent_span
            )

            # Process response
            if response_result[:handoff]
              handoff_agent = current_agent.find_handoff(response_result[:handoff])
              if handoff_agent
                current_agent = handoff_agent
                turns = 0
                agent_span.set_attribute("agent.handoff", handoff_agent.name)
              end
            end

            # Handle tool calls asynchronously
            if response_result[:tool_calls]
              tool_results = process_tool_calls_async(
                response_result[:tool_calls],
                current_agent,
                conversation,
                config
              )
              conversation.concat(tool_results)
            end

            response_result
          end

          conversation << agent_result[:message] if agent_result[:message]
          turns += 1

          # Check if we're done
          break if !agent_result[:tool_calls] && !agent_result[:handoff]
        end

        raise MaxTurnsError, "Maximum turns (#{max_turns}) exceeded" if turns >= max_turns

        Result.new(
          success: true,
          messages: conversation,
          agent: current_agent,
          metadata: {
            turns: turns,
            trace_id: config.trace_id
          }
        )
      end

      def run_without_tracing_async(messages, config:)
        conversation = messages.dup
        current_agent = @agent
        turns = 0
        max_turns = config.max_turns || current_agent.max_turns

        while turns < max_turns
          # Get response from provider
          response = @async_provider.async_chat_completion(
            messages: prepare_messages(conversation, current_agent),
            model: current_agent.model,
            tools: current_agent.tools? ? current_agent.tools.map(&:to_h) : nil,
            response_format: current_agent.response_format,
            **extract_model_params(config)
          )

          # Process response
          result = process_response(response)
          conversation << result[:message] if result[:message]

          # Handle handoff
          if result[:handoff]
            handoff_agent = current_agent.find_handoff(result[:handoff])
            if handoff_agent
              current_agent = handoff_agent
              turns = 0
            end
          end

          # Handle tool calls
          if result[:tool_calls]
            tool_results = process_tool_calls_async(
              result[:tool_calls],
              current_agent,
              conversation,
              config
            )
            conversation.concat(tool_results)
          end

          turns += 1

          # Check if we're done
          break if !result[:tool_calls] && !result[:handoff]
        end

        raise MaxTurnsError, "Maximum turns (#{max_turns}) exceeded" if turns >= max_turns

        Result.new(
          success: true,
          messages: conversation,
          agent: current_agent,
          metadata: { turns: turns }
        )
      end

      def get_response_async(agent, conversation, config, agent_span)
        # Create response span as child of agent span
        @tracer.start_span(
          "response.#{agent.model || "unknown"}",
          kind: :response,
          parent: agent_span
        ) do |response_span|
          response_span.set_attribute("response.model", agent.model || "unknown")

          # Make async API call
          response = @async_provider.async_chat_completion(
            messages: prepare_messages(conversation, agent),
            model: agent.model,
            tools: agent.tools? ? agent.tools.map(&:to_h) : nil,
            response_format: agent.response_format,
            **extract_model_params(config)
          )

          # Set response attributes
          if response["usage"]
            response_span.set_attribute("response.usage.input_tokens", response["usage"]["prompt_tokens"] || 0)
            response_span.set_attribute("response.usage.output_tokens", response["usage"]["completion_tokens"] || 0)
          end

          process_response(response)
        end
      end

      def process_tool_calls_async(tool_calls, agent, conversation, config)
        # Process tool calls in parallel using Async::Barrier
        Async do |task|
          barrier = Async::Barrier.new

          # Start all tool call tasks
          tool_calls.each do |tool_call|
            barrier.async do
              process_single_tool_call_async(tool_call, agent, config)
            end
          end

          # Wait for all to complete and collect results
          results = barrier.wait
          results.compact
        end
      end

      def process_single_tool_call_async(tool_call, agent, config)
        tool_name = tool_call["function"]["name"]
        tool_args = JSON.parse(tool_call["function"]["arguments"] || "{}")

        # Create tool span if tracing
        result = if @tracer && should_trace?(config)
                   @tracer.start_span("tool.#{tool_name}", kind: :tool) do |tool_span|
                     tool_span.set_attribute("tool.name", tool_name)
                     tool_span.set_attribute("tool.arguments", tool_args.to_json)

                     # Execute tool asynchronously if it supports async
                     tool_result = if agent.respond_to?(:execute_tool_async)
                                     agent.execute_tool_async(tool_name, **tool_args)
                                   else
                                     agent.execute_tool(tool_name, **tool_args)
                                   end

                     tool_span.set_attribute("tool.result", format_tool_result(tool_result)[0..1000])
                     tool_result
                   end
                 elsif agent.respond_to?(:execute_tool_async)
                   # Execute without tracing
                   agent.execute_tool_async(tool_name, **tool_args)
                 else
                   agent.execute_tool(tool_name, **tool_args)
                 end

        # Return tool message
        {
          role: "tool",
          tool_call_id: tool_call["id"],
          content: format_tool_result(result)
        }
      rescue StandardError => e
        {
          role: "tool",
          tool_call_id: tool_call["id"],
          content: "Error: #{e.message}"
        }
      end

      def create_agent_span_async(agent, &)
        if @tracer
          # Create root agent span
          original_stack = @tracer.instance_variable_get(:@context).instance_variable_get(:@span_stack).dup
          @tracer.instance_variable_get(:@context).instance_variable_set(:@span_stack, [])

          result = @tracer.start_span("agent.#{agent.name || "agent"}", kind: :agent) do |span|
            span.set_attribute("agent.name", agent.name || "agent")
            span.set_attribute("agent.handoffs", safe_map_names(agent.handoffs))
            span.set_attribute("agent.tools", safe_map_names(agent.tools))
            span.set_attribute("agent.output_type", "str")

            yield(span)
          end

          @tracer.instance_variable_get(:@context).instance_variable_set(:@span_stack, original_stack)
          result
        else
          yield(nil)
        end
      end

      # Wrapper for synchronous providers to make them async-compatible
      class AsyncProviderWrapper
        include Base

        def initialize(sync_provider)
          @sync_provider = sync_provider
        end

        def async_chat_completion(**kwargs)
          Async do
            @sync_provider.chat_completion(**kwargs)
          end
        end
      end

      # Format tool results for proper JSON serialization instead of Ruby hash syntax
      def format_tool_result(result)
        case result
        when Hash, Array
          # Convert structured data to JSON to avoid Ruby hash syntax (=>)
          result.to_json
        when nil
          ""
        else
          # For simple values (strings, numbers, etc.), use to_s
          result.to_s
        end
      end
    end
  end
end

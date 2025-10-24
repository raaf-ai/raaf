# frozen_string_literal: true

require_relative "../base_collector"
require_relative "../agent_collector"

module RAAF
  module Tracing
    module SpanCollectors
      module DSL
        # Specialized collector for RAAF::DSL::Agent components that captures DSL-specific
        # configuration, context metadata, and execution modes. This collector handles
        # the unique data sources and patterns used by DSL-based agents.
        #
        # @example Basic usage with DSL agent
        #   class MyAgent < RAAF::DSL::Agent
        #     agent_name "SearchAgent"
        #     model "gpt-4o"
        #     max_turns 3
        #     temperature 0.7
        #   end
        #
        #   agent = MyAgent.new(query: "Ruby tutorials")
        #   collector = DSL::AgentCollector.new
        #   attributes = collector.collect_attributes(agent)
        #
        # @example Captured DSL agent information
        #   # DSL configuration
        #   attributes["dsl::agent.name"]  # => "SearchAgent"
        #   attributes["dsl::agent.model"]  # => "gpt-4o"
        #   attributes["dsl::agent.max_turns"]  # => "3"
        #   attributes["dsl::agent.temperature"]  # => "0.7"
        #
        #   # Context and execution state
        #   attributes["dsl::agent.context_size"]  # => 2
        #   attributes["dsl::agent.execution_mode"]  # => "smart"
        #   attributes["dsl::agent.has_tools"]  # => true
        #
        # @example Integration with tracing system
        #   tracer = RAAF::Tracing::SpanTracer.new
        #   agent = MyAgent.new(search_query: "AI tutorials")
        #   result = agent.call
        #   # DSL-specific metadata automatically captured
        #
        # @note DSL agents store configuration in class-level _context_config
        # @note Context size reflects the number of variables passed to the agent
        # @note Execution mode detection identifies smart vs direct execution paths
        # @note Compatible with core agent tools and handoffs when available
        #
        # @see BaseCollector For DSL methods and common attribute handling
        # @see AgentCollector For core agent tracing with dialog collection
        # @see RAAF::DSL::Agent The component type this collector specializes in tracing
        #
        # @since 1.0.0
        # @author RAAF Team
        class AgentCollector < BaseCollector
          # DSL agent identification and basic configuration
          span name: ->(comp) { comp.respond_to?(:agent_name) ? comp.agent_name : comp.class.name }
          span model: ->(comp) { comp.class.respond_to?(:_context_config) ? comp.class._context_config[:model] || "gpt-4o" : "gpt-4o" }
          span max_turns: ->(comp) do
            if comp.class.respond_to?(:_context_config)
              (comp.class._context_config[:max_turns] || 5).to_s
            else
              "5"
            end
          end

          # DSL-specific configuration and execution state
          span temperature: ->(comp) { comp.class.respond_to?(:_context_config) ? comp.class._context_config[:temperature] : nil }

          # Additional model settings from DSL configuration
          span max_tokens: ->(comp) do
            comp.class.respond_to?(:_context_config) ? comp.class._context_config[:max_tokens] : nil
          end

          span top_p: ->(comp) do
            comp.class.respond_to?(:_context_config) ? comp.class._context_config[:top_p] : nil
          end

          span frequency_penalty: ->(comp) do
            comp.class.respond_to?(:_context_config) ? comp.class._context_config[:frequency_penalty] : nil
          end

          span presence_penalty: ->(comp) do
            comp.class.respond_to?(:_context_config) ? comp.class._context_config[:presence_penalty] : nil
          end

          span tool_choice: ->(comp) do
            if comp.class.respond_to?(:_context_config)
              tool_choice = comp.class._context_config[:tool_choice]
              tool_choice.is_a?(Hash) ? JSON.generate(tool_choice) : tool_choice&.to_s
            end
          end

          span parallel_tool_calls: ->(comp) do
            if comp.class.respond_to?(:_context_config)
              parallel = comp.class._context_config[:parallel_tool_calls]
              parallel.nil? ? nil : (parallel ? "Enabled" : "Disabled")
            end
          end

          span response_format: ->(comp) do
            if comp.class.respond_to?(:_context_config)
              response_format = comp.class._context_config[:response_format]
              response_format.is_a?(Hash) ? JSON.generate(response_format) : response_format&.to_s
            end
          end

          span context_size: ->(comp) { comp.instance_variable_get(:@context)&.size || 0 }
          span has_tools: ->(comp) do
            context = comp.instance_variable_get(:@context)
            (context && context.size > 0) || false
          end
          span execution_mode: ->(comp) { comp.respond_to?(:has_smart_features?) ? (comp.has_smart_features? ? "smart" : "direct") : "direct" }

          # Core agent compatibility - include standard agent data when available
          span tools_count: ->(comp) { comp.respond_to?(:tools) ? comp.tools.length.to_s : "0" }
          span handoffs_count: ->(comp) { comp.respond_to?(:handoffs) ? comp.handoffs.length.to_s : "0" }

          # Override collect_result to include conversation data from execution result
          # DSL agents delegate to core agents, so the result will be a RunResult
          # This uses the same approach as the parent AgentCollector
          #
          # @param component [RAAF::DSL::Agent] The DSL agent component
          # @param result [RunResult] The execution result from the underlying core agent
          # @return [Hash] Result-specific attributes including conversation data
          def collect_result(component, result)
            # Start with base result attributes
            attrs = super(component, result)

            # Extract conversation data from the RunResult (same logic as AgentCollector)
            if result
              # Extract messages from the result
              messages = extract_messages_from_result(result)
              attrs["#{component_prefix}.conversation_messages"] = messages.any? ? JSON.generate(messages) : "[]"

              # Extract initial user prompt
              user_message = messages.find { |msg| msg[:role] == "user" || msg["role"] == "user" }
              if user_message
                attrs["#{component_prefix}.initial_user_prompt"] = user_message[:content] || user_message["content"] || "No content"
              else
                attrs["#{component_prefix}.initial_user_prompt"] = "No user message found"
              end

              # Extract final agent response
              assistant_messages = messages.select { |msg| (msg[:role] || msg["role"]) == "assistant" }
              if assistant_messages.any?
                last_response = assistant_messages.last
                attrs["#{component_prefix}.final_agent_response"] = last_response[:content] || last_response["content"] || "No content"
              else
                attrs["#{component_prefix}.final_agent_response"] = "No agent response found"
              end

              # Extract tool executions
              tool_data = extract_tool_data_from_result(result)
              attrs["#{component_prefix}.tool_executions"] = tool_data.any? ? JSON.generate(tool_data) : "[]"

              # Calculate conversation statistics
              stats = {
                total_messages: messages.length,
                user_messages: messages.count { |msg| (msg[:role] || msg["role"]) == "user" },
                assistant_messages: messages.count { |msg| (msg[:role] || msg["role"]) == "assistant" },
                tool_calls: tool_data.length,
                has_system_message: messages.any? { |msg| (msg[:role] || msg["role"]) == "system" }
              }
              attrs["#{component_prefix}.conversation_stats"] = JSON.generate(stats)
            else
              # No result available - set empty defaults
              attrs["#{component_prefix}.conversation_messages"] = "[]"
              attrs["#{component_prefix}.initial_user_prompt"] = "No result available"
              attrs["#{component_prefix}.final_agent_response"] = "No result available"
              attrs["#{component_prefix}.tool_executions"] = "[]"
              attrs["#{component_prefix}.conversation_stats"] = JSON.generate({
                total_messages: 0,
                user_messages: 0,
                assistant_messages: 0,
                tool_calls: 0,
                has_system_message: false
              })
            end

            attrs
          end

          private

          # Extract messages from RunResult - same as AgentCollector
          def extract_messages_from_result(result)
            return [] unless result

            if result.respond_to?(:messages) && result.messages
              Array(result.messages)
            else
              []
            end
          end

          # Extract tool data from RunResult - same as AgentCollector
          def extract_tool_data_from_result(result)
            return [] unless result

            tool_data = []

            # Get tool results from RunResult
            if result.respond_to?(:tool_results) && result.tool_results
              tool_data.concat(Array(result.tool_results))
            end

            # Also extract tool calls from messages
            if result.respond_to?(:messages) && result.messages
              result.messages.each do |message|
                # Check for tool_calls in message
                if message[:tool_calls] || message["tool_calls"]
                  tool_calls = message[:tool_calls] || message["tool_calls"]
                  tool_calls.each do |tool_call|
                    tool_data << {
                      name: tool_call[:function]&.dig(:name) || tool_call["function"]&.dig("name") || "unknown",
                      arguments: tool_call[:function]&.dig(:arguments) || tool_call["function"]&.dig("arguments") || "{}",
                      call_id: tool_call[:id] || tool_call["id"] || "unknown"
                    }
                  end
                end

                # Check for tool responses
                if (message[:role] || message["role"]) == "tool"
                  tool_data << {
                    name: message[:name] || message["name"] || "unknown",
                    result: message[:content] || message["content"] || "No result",
                    tool_call_id: message[:tool_call_id] || message["tool_call_id"] || "unknown"
                  }
                end
              end
            end

            tool_data
          end
        end
      end
    end
  end
end

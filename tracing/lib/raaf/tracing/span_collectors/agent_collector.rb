# frozen_string_literal: true

require_relative "base_collector"

module RAAF
  module Tracing
    module SpanCollectors
      # Comprehensive collector for Core RAAF::Agent components that captures complete
      # dialog information, conversation flow, tool executions, and agent metadata.
      # This collector provides deep visibility into agent behavior and interactions.
      #
      # @example Basic usage
      #   agent = RAAF::Agent.new(name: "Assistant", model: "gpt-4o")
      #   collector = AgentCollector.new
      #   attributes = collector.collect_attributes(agent)
      #
      # @example Captured dialog information
      #   # System instructions
      #   attributes["agent.system_instructions"]
      #   # => "You are a helpful assistant that..."
      #
      #   # Complete conversation as JSON
      #   JSON.parse(attributes["agent.conversation_messages"])
      #   # => [{"role" => "user", "content" => "Hello"}, ...]
      #
      #   # Tool executions with results
      #   JSON.parse(attributes["agent.tool_executions"])
      #   # => [{"name" => "search_web", "arguments" => "{\"query\": \"weather\"}"}]
      #
      #   # Conversation statistics
      #   JSON.parse(attributes["agent.conversation_stats"])
      #   # => {"total_messages" => 4, "user_messages" => 2, "tool_calls" => 1}
      #
      # @example Integration with tracing system
      #   tracer = RAAF::Tracing::SpanTracer.new
      #   runner = RAAF::Runner.new(agent: agent, tracer: tracer)
      #   result = runner.run("Search for weather in Tokyo")
      #   # Comprehensive dialog data automatically captured in spans
      #
      # @note This collector performs deep extraction from agent execution results,
      #   message history, and tool call data using multiple fallback strategies
      # @note All dialog data is automatically serialized to JSON for span storage
      # @note Conversation statistics include message counts and interaction patterns
      #
      # @see BaseCollector For DSL methods and common attribute handling
      # @see RAAF::Agent The component type this collector specializes in tracing
      # @see DSL::AgentCollector For DSL-based agents with different data sources
      #
      # @since 1.0.0
      # @author RAAF Team
      class AgentCollector < BaseCollector
        # Basic agent identification attributes - extracted directly from agent properties
        span :name, :model

        # Agent configuration and capability metrics
        span max_turns: ->(comp) { comp.respond_to?(:max_turns) ? comp.max_turns.to_s : "N/A" }
        span tools_count: ->(comp) { comp.respond_to?(:tools) ? comp.tools.length.to_s : "0" }
        span handoffs_count: ->(comp) { comp.respond_to?(:handoffs) ? comp.handoffs.length.to_s : "0" }

        # Model settings - temperature, max_tokens, top_p, and other LLM parameters
        # Core Agent stores these as instance variables with accessor methods
        span temperature: ->(comp) do
          if comp.respond_to?(:temperature)
            comp.temperature || "N/A"
          elsif comp.respond_to?(:model_settings) && comp.model_settings.respond_to?(:[])
            settings = comp.model_settings
            settings[:temperature] || settings["temperature"] || "N/A"
          else
            "N/A"
          end
        end

        span max_tokens: ->(comp) do
          if comp.respond_to?(:max_tokens)
            comp.max_tokens || "N/A"
          elsif comp.respond_to?(:model_settings) && comp.model_settings.respond_to?(:[])
            comp.model_settings[:max_tokens] || comp.model_settings["max_tokens"] || "N/A"
          else
            "N/A"
          end
        end

        span top_p: ->(comp) do
          if comp.respond_to?(:top_p)
            comp.top_p || "N/A"
          elsif comp.respond_to?(:model_settings) && comp.model_settings.respond_to?(:[])
            comp.model_settings[:top_p] || comp.model_settings["top_p"] || "N/A"
          else
            "N/A"
          end
        end

        span frequency_penalty: ->(comp) do
          if comp.respond_to?(:frequency_penalty)
            comp.frequency_penalty || "N/A"
          elsif comp.respond_to?(:model_settings) && comp.model_settings.respond_to?(:[])
            comp.model_settings[:frequency_penalty] || comp.model_settings["frequency_penalty"] || "N/A"
          else
            "N/A"
          end
        end

        span presence_penalty: ->(comp) do
          if comp.respond_to?(:presence_penalty)
            comp.presence_penalty || "N/A"
          elsif comp.respond_to?(:model_settings) && comp.model_settings.respond_to?(:[])
            comp.model_settings[:presence_penalty] || comp.model_settings["presence_penalty"] || "N/A"
          else
            "N/A"
          end
        end

        span tool_choice: ->(comp) do
          if comp.respond_to?(:tool_choice) && comp.tool_choice
            comp.tool_choice.is_a?(Hash) ? JSON.generate(comp.tool_choice) : comp.tool_choice.to_s
          else
            "N/A"
          end
        end

        span parallel_tool_calls: ->(comp) do
          if comp.respond_to?(:model_settings) && comp.model_settings.respond_to?(:[])
            parallel = comp.model_settings[:parallel_tool_calls] || comp.model_settings["parallel_tool_calls"]
            parallel.nil? ? "N/A" : (parallel ? "Enabled" : "Disabled")
          else
            "N/A"
          end
        end

        span response_format: ->(comp) do
          if comp.respond_to?(:response_format) && comp.response_format
            comp.response_format.is_a?(Hash) ? JSON.generate(comp.response_format) : comp.response_format.to_s
          else
            "N/A"
          end
        end

        span model_settings_json: ->(comp) do
          if comp.respond_to?(:model_settings) && comp.model_settings
            JSON.generate(comp.model_settings)
          else
            "{}"
          end
        end

        # Workflow and execution context detection
        span workflow_name: ->(comp) do
          job_span = Thread.current[:raaf_job_span]
          job_span&.class&.name
        end

        # DSL metadata extraction for agents with trace_metadata support
        span dsl_metadata: ->(comp) do
          if comp.respond_to?(:trace_metadata) && comp.trace_metadata&.any?
            comp.trace_metadata.map { |k, v| "#{k}:#{v}" }.join(",")
          end
        end

        # ============================================================================
        # STATIC AGENT CONFIGURATION
        # These attributes capture agent configuration that's available before execution
        # ============================================================================

        # System instructions that define the agent's role and behavior
        # @return [String] The agent's system prompt or default message
        span system_instructions: ->(comp) do
          if comp.respond_to?(:instructions) && comp.instructions
            comp.instructions.strip
          else
            "No system instructions"
          end
        end

        # ============================================================================
        # DYNAMIC CONVERSATION DATA COLLECTION
        # These attributes are collected AFTER execution from the RunResult
        # ============================================================================

        # Override collect_result to extract conversation data from the actual execution result
        # This method is called AFTER agent execution with access to the RunResult
        #
        # @param component [RAAF::Agent] The agent component
        # @param result [RunResult] The execution result containing messages and tool data
        # @return [Hash] Result-specific attributes including conversation data
        def collect_result(component, result)
          # Start with base result attributes
          attrs = super(component, result)

          # Extract conversation data from the RunResult (not the agent)
          if result
            # Complete conversation messages as JSON array
            messages = extract_messages_from_result(result)
            attrs["#{component_prefix}.conversation_messages"] = messages.any? ? JSON.generate(messages) : "[]"

            # Initial user prompt that started the conversation
            user_message = messages.find { |msg| msg[:role] == "user" || msg["role"] == "user" }
            if user_message
              attrs["#{component_prefix}.initial_user_prompt"] = user_message[:content] || user_message["content"] || "No content"
            else
              attrs["#{component_prefix}.initial_user_prompt"] = "No user message found"
            end

            # Final agent response from the conversation
            assistant_messages = messages.select { |msg| (msg[:role] || msg["role"]) == "assistant" }
            if assistant_messages.any?
              last_response = assistant_messages.last
              attrs["#{component_prefix}.final_agent_response"] = last_response[:content] || last_response["content"] || "No content"
            else
              attrs["#{component_prefix}.final_agent_response"] = "No agent response found"
            end

            # Tool calls and results as JSON array
            tool_data = extract_tool_data_from_result(result)
            attrs["#{component_prefix}.tool_executions"] = tool_data.any? ? JSON.generate(tool_data) : "[]"

            # Conversation statistics and interaction patterns
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

        # ============================================================================
        # DATA EXTRACTION HELPER METHODS
        # These class-level methods provide robust extraction of conversation data
        # from agents using multiple fallback strategies to handle different agent
        # implementations and execution states.
        # ============================================================================

        # Extract conversation messages from an agent using multiple fallback strategies.
        # This method attempts to find message data in various locations depending on
        # the agent's execution state and internal structure.
        #
        # @param agent [RAAF::Agent] The agent to extract messages from
        # @return [Array<Hash>] Array of message objects with role and content
        #
        # @example Typical usage
        #   messages = AgentCollector.extract_messages(my_agent)
        #   # => [
        #   #   {"role" => "user", "content" => "Hello"},
        #   #   {"role" => "assistant", "content" => "Hi there!"}
        #   # ]
        #
        # @note Extraction strategies (in order):
        #   1. agent.last_run_result.messages (latest execution)
        #   2. Instance variables (@last_messages, @messages, etc.)
        #   3. Thread-local storage for execution context
        #
        def self.extract_messages(agent)
          messages = []

          # Check if agent has last execution result
          if agent.respond_to?(:last_run_result) && agent.last_run_result
            result = agent.last_run_result
            if result.respond_to?(:messages) && result.messages
              messages = result.messages
            end
          end

          # Fallback: Check for messages in instance variables
          if messages.empty?
            [:@last_messages, :@messages, :@conversation, :@last_execution_messages].each do |var|
              if agent.instance_variable_defined?(var)
                potential_messages = agent.instance_variable_get(var)
                if potential_messages.is_a?(Array) && potential_messages.any?
                  messages = potential_messages
                  break
                end
              end
            end
          end

          # Fallback: Check Thread.current for execution context
          if messages.empty?
            thread_messages = Thread.current[:agent_execution_messages] ||
                            Thread.current[:current_conversation] ||
                            Thread.current[:raaf_messages]
            messages = thread_messages if thread_messages.is_a?(Array)
          end

          Array(messages)
        end

        # Extract tool execution data from an agent using multiple fallback strategies.
        # This method finds tool calls, arguments, and results from various locations
        # in the agent's execution context.
        #
        # @param agent [RAAF::Agent] The agent to extract tool data from
        # @return [Array<Hash>] Array of tool execution objects
        #
        # @example Typical usage
        #   tool_data = AgentCollector.extract_tool_data(my_agent)
        #   # => [
        #   #   {
        #   #     "name" => "search_web",
        #   #     "arguments" => "{\"query\": \"weather\"}",
        #   #     "call_id" => "call_123"
        #   #   },
        #   #   {
        #   #     "name" => "search_web",
        #   #     "result" => "Weather data...",
        #   #     "tool_call_id" => "call_123"
        #   #   }
        #   # ]
        #
        # @note Extraction strategies (in order):
        #   1. agent.last_run_result.tool_results (latest execution)
        #   2. Instance variables (@tool_results, @last_tool_calls, etc.)
        #   3. Tool calls embedded in conversation messages
        #
        def self.extract_tool_data(agent)
          tool_data = []

          # Check if agent has last execution result with tool_results
          if agent.respond_to?(:last_run_result) && agent.last_run_result
            result = agent.last_run_result
            if result.respond_to?(:tool_results) && result.tool_results
              tool_data = result.tool_results
            end
          end

          # Fallback: Check for tool data in instance variables
          if tool_data.empty?
            [:@tool_results, :@last_tool_calls, :@tool_executions].each do |var|
              if agent.instance_variable_defined?(var)
                potential_tools = agent.instance_variable_get(var)
                if potential_tools.is_a?(Array) && potential_tools.any?
                  tool_data = potential_tools
                  break
                end
              end
            end
          end

          # Extract tool calls from messages if available
          if tool_data.empty?
            messages = extract_messages(agent)
            messages.each do |message|
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

          Array(tool_data)
        end

        private

        # Extract conversation messages directly from RunResult
        # This method works with the actual execution result instead of trying to find
        # messages stored on the agent object.
        #
        # @param result [RunResult] The execution result from runner
        # @return [Array<Hash>] Array of message objects with role and content
        def extract_messages_from_result(result)
          return [] unless result

          if result.respond_to?(:messages) && result.messages
            Array(result.messages)
          else
            []
          end
        end

        # Extract tool execution data directly from RunResult
        # This method extracts tool calls and results from the execution result.
        #
        # @param result [RunResult] The execution result from runner
        # @return [Array<Hash>] Array of tool execution objects
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

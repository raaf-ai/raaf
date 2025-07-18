# frozen_string_literal: true

require "raaf"

# Runner that delegates to RAAF (Ruby AI Agents Factory) framework
#
# This class provides the execution layer that manages agent runtime
# by delegating all execution to the RAAF (Ruby AI Agents Factory) framework.
# The AI Agent DSL remains purely configurational, creating OpenAI
# agent instances that are passed to this runner for execution.
#
# The runner acts as a thin delegation layer that:
# - Accepts configured OpenAI agents from the DSL
# - Creates RAAF (Ruby AI Agents Factory) runner instances
# - Delegates all execution to the OpenAI framework
# - Handles message formatting and context passing
#
# @example Basic usage
#   # DSL creates configured OpenAI agent
#   dsl_agent = MyAgent.new
#   openai_agent = dsl_agent.create_execution_agent_instance
#
#   # Runner delegates to RAAF framework
#   runner = RAAF::DSL::Execution::Runner.new(agent: openai_agent)
#   result = runner.run("Hello, how can you help?")
#
# @example With context variables
#   runner = RAAF::DSL::Execution::Runner.new(
#     agent: openai_agent,
#     debug: true
#   )
#   result = runner.run(
#     "Analyze this data",
#     context: { user_id: "123", session: "abc" }
#   )
#
# @see RAAF::Runner The underlying RAAF runner
# @see RAAF::DSL::Agents::Base#create_execution_agent_instance For agent creation
# @since 0.1.0
#
module RAAF

  module DSL

    module Execution

      class Runner

        # @!attribute [r] openai_agent
        #   @return [RAAF::Agent] The configured OpenAI agent instance
        # @!attribute [r] openai_runner
        #   @return [RAAF::Runner] The underlying RAAF framework runner
        attr_reader :openai_agent, :openai_runner

        # Initialize a new runner with an OpenAI agent
        #
        # Creates a runner that delegates execution to the RAAF (Ruby AI Agents Factory)
        # framework. The agent parameter should be a fully configured OpenAI
        # agent instance created by the DSL's agent configuration methods.
        #
        # @param agent [RAAF::Agent] Pre-configured OpenAI agent instance
        # @param options [Hash] Additional options to pass to RAAF runner
        # @option options [Boolean] :debug Enable debug mode for detailed logging
        # @option options [Hash] :context_variables Initial context variables
        # @option options [Integer] :max_turns Override maximum conversation turns
        #
        # @raise [ArgumentError] If agent is not an RAAF::Agent instance
        #
        # @example Initialize with basic agent
        #   runner = Runner.new(agent: openai_agent)
        #
        # @example Initialize with debug options
        #   runner = Runner.new(
        #     agent: openai_agent,
        #     debug: true,
        #     max_turns: 5
        #   )
        #
        def initialize(agent:, **options)
          unless agent.is_a?(RAAF::Agent)
            raise ArgumentError, "agent must be an RAAF::Agent instance, got #{agent.class}"
          end

          @openai_agent = agent
          @options = options

          # Create RAAF (Ruby AI Agents Factory) runner with the configured agent
          @openai_runner = RAAF::Runner.new(
            agents: [@openai_agent],
            **@options
          )
        end

        # Execute the agent with given input and context
        #
        # Delegates execution to the RAAF (Ruby AI Agents Factory) framework runner,
        # formatting the input as messages and passing any context variables.
        # The agent will process the input using its configured instructions,
        # tools, and other settings.
        #
        # @param input [String, Array, Object, nil] Input to send to the agent
        #   - String: Converted to user message
        #   - Array: Treated as pre-formatted message array
        #   - Object: Converted to string then to user message
        #   - nil: Empty message array (useful for agent initialization)
        #
        # @param context [Hash, nil] Context variables to pass to the agent
        #   Context variables are available to the agent throughout execution
        #   and can be used for maintaining state across interactions.
        #
        # @return [Object] Result from RAAF framework execution
        #   The exact return type depends on the RAAF framework
        #   implementation but typically includes messages, context, and metadata.
        #
        # @raise [StandardError] Any errors from the underlying OpenAI framework
        #
        # @example Basic text input
        #   result = runner.run("What is the weather like?")
        #
        # @example With context variables
        #   result = runner.run(
        #     "Analyze the sales data",
        #     context: { user_id: "123", department: "sales" }
        #   )
        #
        # @example With pre-formatted messages
        #   messages = [
        #     { role: "user", content: "Hello" },
        #     { role: "assistant", content: "Hi there!" },
        #     { role: "user", content: "How are you?" }
        #   ]
        #   result = runner.run(messages)
        #
        # @example Agent initialization without input
        #   result = runner.run() # Let agent start conversation
        #
        def run(input = nil, context: nil)
          # Use RAAF (Ruby AI Agents Factory) runner with the configured agent
          @openai_runner.run(
            agent: @openai_agent,
            messages: build_messages(input),
            context_variables: context
          )
        end

        private

        # Convert input to OpenAI message format
        #
        # This method handles different input types and converts them to the
        # message format expected by the RAAF framework.
        #
        # @param input [String, Array, Object, nil] Input to convert
        # @return [Array<Hash>] Array of message hashes with :role and :content
        #
        # @example String input
        #   build_messages("Hello")
        #   # => [{ role: "user", content: "Hello" }]
        #
        # @example Array input (passed through)
        #   build_messages([{ role: "user", content: "Hi" }])
        #   # => [{ role: "user", content: "Hi" }]
        #
        # @example Object input
        #   build_messages(42)
        #   # => [{ role: "user", content: "42" }]
        #
        # @example Nil input
        #   build_messages(nil)
        #   # => []
        #
        def build_messages(input)
          return [] unless input

          if input.is_a?(String)
            [{ role: "user", content: input }]
          elsif input.is_a?(Array)
            input
          else
            [{ role: "user", content: input.to_s }]
          end
        end

      end

    end

  end

end

# frozen_string_literal: true

module OpenAIAgents
  ##
  # RunContext maintains the state and conversation history during agent execution
  #
  # This class serves as the central data store for a conversation run, tracking:
  # - Message history (user inputs and agent responses)
  # - Metadata about the run
  # - Current agent and turn information
  # - Custom data storage for extensions
  #
  # RunContext is passed through the execution pipeline and made available
  # to hooks, guardrails, and other components that need access to the
  # conversation state.
  #
  # @example Creating a context
  #   context = RunContext.new(
  #     messages: [{ role: "user", content: "Hello" }],
  #     metadata: { user_id: 123 },
  #     trace_id: "trace_abc123"
  #   )
  #
  # @example Storing custom data
  #   context.store(:user_preferences, { theme: "dark" })
  #   prefs = context.fetch(:user_preferences)
  #
  # @example Tracking conversation
  #   context.add_message({ role: "assistant", content: "Hi there!" })
  #   input = context.input_messages     # => [{ role: "user", content: "Hello" }]
  #   generated = context.generated_messages  # => [{ role: "assistant", content: "Hi there!" }]
  #
  class RunContext
    # @!attribute [r] messages
    #   @return [Array<Hash>] The conversation messages
    # @!attribute [r] metadata
    #   @return [Hash] Run metadata (user_id, session_id, etc.)
    # @!attribute [r] trace_id
    #   @return [String, nil] Trace ID for distributed tracing
    # @!attribute [r] group_id
    #   @return [String, nil] Group ID for related runs
    # @!attribute [rw] current_agent
    #   @return [Agent, nil] The currently active agent
    # @!attribute [rw] current_turn
    #   @return [Integer] The current conversation turn number
    # @!attribute [rw] custom_data
    #   @return [Hash] Custom data storage for extensions
    attr_reader :messages, :metadata, :trace_id, :group_id
    attr_accessor :current_agent, :current_turn, :custom_data

    ##
    # Initialize a new RunContext
    #
    # @param messages [Array<Hash>] Initial conversation messages
    # @param metadata [Hash] Run metadata
    # @param trace_id [String, nil] Trace ID for distributed tracing
    # @param group_id [String, nil] Group ID for related runs
    #
    def initialize(messages: [], metadata: {}, trace_id: nil, group_id: nil)
      @messages = messages
      @metadata = metadata
      @trace_id = trace_id
      @group_id = group_id
      @current_agent = nil
      @current_turn = 0
      @custom_data = {}
      @storage = {}
    end

    ##
    # Get the original user input messages
    #
    # Extracts only the initial user messages before any assistant responses.
    # Useful for understanding the original request.
    #
    # @return [Array<Hash>] Array of user messages
    #
    def input_messages
      # Find the first user message(s) before any assistant responses
      input = []
      @messages.each do |msg|
        break if msg[:role] == "assistant"

        input << msg if msg[:role] == "user"
      end
      input
    end

    ##
    # Get all messages generated during this run
    #
    # Returns all assistant and tool messages generated after the initial input.
    # Useful for analyzing the agent's responses.
    #
    # @return [Array<Hash>] Array of generated messages
    #
    def generated_messages
      # Find index of first assistant message
      first_assistant = @messages.find_index { |m| m[:role] == "assistant" }
      return [] unless first_assistant

      @messages[first_assistant..]
    end

    ##
    # Get the last message in the conversation
    #
    # @return [Hash, nil] The last message or nil if no messages
    #
    def last_message
      @messages.last
    end

    ##
    # Get messages for a specific agent
    #
    # Filters messages by agent name, useful in multi-agent conversations.
    #
    # @param agent_name [String] Name of the agent
    # @return [Array<Hash>] Messages from the specified agent
    #
    def messages_for_agent(agent_name)
      @messages.select do |msg|
        msg[:agent_name] == agent_name
      end
    end

    ##
    # Store custom data in the context
    #
    # Allows extensions and hooks to store arbitrary data that persists
    # throughout the conversation run.
    #
    # @param key [Symbol, String] The storage key
    # @param value [Object] The value to store
    # @return [Object] The stored value
    #
    def store(key, value)
      @storage[key] = value
    end

    ##
    # Retrieve custom data from the context
    #
    # @param key [Symbol, String] The storage key
    # @param default [Object] Default value if key not found
    # @return [Object] The stored value or default
    #
    def fetch(key, default = nil)
      @storage.fetch(key, default)
    end

    ##
    # Check if a storage key exists
    #
    # @param key [Symbol, String] The storage key
    # @return [Boolean] true if key exists
    #
    def key?(key)
      @storage.key?(key)
    end

    ##
    # Add a message to the conversation
    #
    # Automatically adds agent name if current_agent is set.
    #
    # @param message [Hash] Message with :role and :content
    # @return [Array<Hash>] The updated messages array
    #
    def add_message(message)
      # Add agent name if current agent is set
      message = message.merge(agent_name: @current_agent.name) if @current_agent && !message[:agent_name]
      @messages << message
    end

    ##
    # Create a deep copy of the context
    #
    # Useful for creating snapshots or branching conversations.
    #
    # @return [RunContext] A new context with copied data
    #
    def dup
      context = self.class.new(
        messages: @messages.dup,
        metadata: @metadata.dup,
        trace_id: @trace_id,
        group_id: @group_id
      )
      context.current_agent = @current_agent
      context.current_turn = @current_turn
      context.custom_data = @custom_data.dup
      context
    end

    # Convert to hash for serialization
    def to_h
      {
        messages: @messages,
        metadata: @metadata,
        trace_id: @trace_id,
        group_id: @group_id,
        current_turn: @current_turn,
        custom_data: @custom_data
      }
    end
  end

  ##
  # RunContextWrapper provides enhanced context functionality for hooks and extensions
  #
  # This wrapper class extends RunContext with additional helper methods for
  # tracking agent operations, tool calls, and handoffs. It follows the decorator
  # pattern to add functionality without modifying the core RunContext class.
  #
  # The wrapper is primarily used by lifecycle hooks and provides convenient
  # methods for tracking the execution flow of multi-agent conversations.
  #
  # @example Using in a hook
  #   class MyHooks
  #     def on_agent_start(context, agent)
  #       context.push_agent(agent)
  #       puts "Agent stack: #{context.agent_stack.map(&:name)}"
  #     end
  #     
  #     def on_tool_end(context, agent, tool, result)
  #       context.add_tool_call(tool.name, {}, result)
  #     end
  #   end
  #
  # @example Tracking handoffs
  #   wrapper.add_handoff(sales_agent, support_agent)
  #   handoff_history = wrapper.handoffs
  #   # => [{ from: "Sales", to: "Support", turn: 2, timestamp: ... }]
  #
  class RunContextWrapper
    # @!attribute [r] context
    #   @return [RunContext] The wrapped RunContext instance
    attr_reader :context

    ##
    # Initialize a new wrapper
    #
    # @param context [RunContext] The context to wrap
    #
    def initialize(context)
      @context = context
    end

    ##
    # Get conversation messages
    # @return [Array<Hash>] The conversation messages
    #
    def messages
      @context.messages
    end

    def metadata
      @context.metadata
    end

    def trace_id
      @context.trace_id
    end

    def current_agent
      @context.current_agent
    end

    def current_turn
      @context.current_turn
    end

    # Store and retrieve data
    def store(key, value)
      @context.store(key, value)
    end

    def fetch(key, default = nil)
      @context.fetch(key, default)
    end

    # Get input messages
    def input_messages
      @context.input_messages
    end

    # Get generated messages
    def generated_messages
      @context.generated_messages
    end

    # Delegate message methods
    def add_message(message)
      @context.add_message(message)
    end

    # Add helper methods for hooks
    def agent_stack
      fetch(:agent_stack, [])
    end

    def push_agent(agent)
      stack = agent_stack
      stack << agent
      store(:agent_stack, stack)
    end

    def pop_agent
      stack = agent_stack
      stack.pop
      store(:agent_stack, stack)
    end

    # Track tool calls
    def tool_calls
      fetch(:tool_calls, [])
    end

    def add_tool_call(tool_name, arguments, result)
      calls = tool_calls
      calls << {
        tool_name: tool_name,
        arguments: arguments,
        result: result,
        timestamp: Time.now
      }
      store(:tool_calls, calls)
    end

    # Track handoffs
    def handoffs
      fetch(:handoffs, [])
    end

    def add_handoff(from_agent, to_agent)
      handoff_list = handoffs
      handoff_list << {
        from: from_agent.name,
        to: to_agent.name,
        turn: current_turn,
        timestamp: Time.now
      }
      store(:handoffs, handoff_list)
    end
  end
end

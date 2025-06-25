# frozen_string_literal: true

module OpenAIAgents
  # Context object that provides access to run state during agent execution
  class RunContext
    attr_reader :messages, :metadata, :trace_id, :group_id
    attr_accessor :current_agent, :current_turn, :custom_data

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

    # Get the original input messages
    def input_messages
      # Find the first user message(s) before any assistant responses
      input = []
      @messages.each do |msg|
        break if msg[:role] == "assistant"

        input << msg if msg[:role] == "user"
      end
      input
    end

    # Get all messages generated during this run (excluding input)
    def generated_messages
      # Find index of first assistant message
      first_assistant = @messages.find_index { |m| m[:role] == "assistant" }
      return [] unless first_assistant

      @messages[first_assistant..]
    end

    # Get the last message
    def last_message
      @messages.last
    end

    # Get messages for a specific agent
    def messages_for_agent(agent_name)
      @messages.select do |msg|
        msg[:agent_name] == agent_name
      end
    end

    # Store data in context
    def store(key, value)
      @storage[key] = value
    end

    # Retrieve data from context
    def fetch(key, default = nil)
      @storage.fetch(key, default)
    end

    # Check if key exists
    def key?(key)
      @storage.key?(key)
    end

    # Add a message to the conversation
    def add_message(message)
      # Add agent name if current agent is set
      message = message.merge(agent_name: @current_agent.name) if @current_agent && !message[:agent_name]
      @messages << message
    end

    # Create a copy of the context
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

  # Wrapper that provides additional functionality for hooks
  # Matches Python's RunContextWrapper pattern
  class RunContextWrapper
    attr_reader :context

    def initialize(context)
      @context = context
    end

    # Delegate common methods to context
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

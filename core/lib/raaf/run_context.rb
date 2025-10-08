# frozen_string_literal: true

module RAAF

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
      # Use HashWithIndifferentAccess for consistent key handling
      @storage = {}.with_indifferent_access
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
    # Unified interface methods for RAAF context harmonization
    #

    ##
    # Get value from storage (unified interface)
    #
    # @param key [Symbol, String] The storage key
    # @param default [Object] Default value if key not found
    # @return [Object] The stored value or default
    #
    alias_method :get, :fetch

    ##
    # Set value in storage (unified interface)
    #
    # @param key [Symbol, String] The storage key
    # @param value [Object] The value to store
    # @return [Object] The stored value
    #
    alias_method :set, :store

    ##
    # Check if key exists (unified interface)
    #
    # @param key [Symbol, String] The storage key
    # @return [Boolean] true if key exists
    #
    alias_method :has?, :key?

    ##
    # Array-style read access (unified interface)
    #
    # @param key [Symbol, String] The storage key
    # @return [Object, nil] The stored value or nil
    #
    def [](key)
      @storage[key]
    end

    ##
    # Array-style write access (unified interface)
    #
    # @param key [Symbol, String] The storage key
    # @param value [Object] The value to store
    # @return [Object] The stored value
    #
    def []=(key, value)
      @storage[key] = value
    end

    ##
    # Get all storage keys (unified interface)
    #
    # @return [Array<Symbol, String>] All keys in storage
    #
    def keys
      @storage.keys
    end

    ##
    # Get all storage values (unified interface)
    #
    # @return [Array<Object>] All values in storage
    #
    def values
      @storage.values
    end

    ##
    # Export storage as hash (unified interface)
    #
    # @return [Hash] The storage hash with indifferent access
    #
    def to_h
      @storage.to_h
    end

    ##
    # Delete a key from storage (unified interface)
    #
    # @param key [Symbol, String] The storage key
    # @return [Object, nil] The deleted value or nil
    #
    def delete(key)
      @storage.delete(key)
    end

    ##
    # Update storage with multiple values (unified interface)
    #
    # @param hash [Hash] Hash of key-value pairs to merge
    # @return [Hash] The updated storage
    #
    def update(hash)
      @storage.update(hash)
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
      # Copy stored data from storage
      @storage.each { |key, value| context.store(key, value) }
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
  # @example Type-safe context usage
  #   # For basic context
  #   wrapper = RunContextWrapper.new(context)
  #
  #   # For typed context (Python SDK compatibility)
  #   typed_wrapper = TypedRunContextWrapper.new(context, UserSession)
  #   typed_wrapper.typed_context = UserSession.new(user_id: 123)
  #   session = typed_wrapper.typed_context  # Returns UserSession instance
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

  ##
  # TypedRunContextWrapper provides type-safe context functionality
  #
  # This class extends RunContextWrapper with type safety features that match
  # the Python SDK's RunContextWrapper[T] functionality. It allows storing
  # and retrieving typed context objects with compile-time type checking
  # (where supported by static analysis tools).
  #
  # @example Basic typed context usage
  #   class UserSession
  #     attr_accessor :user_id, :session_id, :preferences
  #
  #     def initialize(user_id:, session_id: nil, preferences: {})
  #       @user_id = user_id
  #       @session_id = session_id
  #       @preferences = preferences
  #     end
  #   end
  #
  #   # Create typed wrapper
  #   typed_wrapper = TypedRunContextWrapper.new(context, UserSession)
  #   typed_wrapper.typed_context = UserSession.new(user_id: 123)
  #
  #   # Access typed context with type safety
  #   session = typed_wrapper.typed_context  # Returns UserSession instance
  #   puts session.user_id  # => 123
  #
  # @example Advanced typed context with validation
  #   class APIContext
  #     attr_accessor :api_key, :rate_limit, :retry_count
  #
  #     def initialize(api_key:, rate_limit: 100, retry_count: 3)
  #       @api_key = api_key
  #       @rate_limit = rate_limit
  #       @retry_count = retry_count
  #       validate!
  #     end
  #
  #     private
  #
  #     def validate!
  #       raise ArgumentError, "API key is required" if @api_key.nil? || @api_key.empty?
  #       raise ArgumentError, "Rate limit must be positive" if @rate_limit <= 0
  #     end
  #   end
  #
  #   # Usage with validation
  #   api_wrapper = TypedRunContextWrapper.new(context, APIContext)
  #   api_wrapper.typed_context = APIContext.new(api_key: "sk-123", rate_limit: 200)
  #
  class TypedRunContextWrapper < RunContextWrapper

    # @!attribute [r] type_class
    #   @return [Class] The expected type class for the typed context
    attr_reader :type_class

    ##
    # Initialize a new typed wrapper
    #
    # @param context [RunContext] The context to wrap
    # @param type_class [Class] The expected type class for typed_context
    #
    def initialize(context, type_class = nil)
      super(context)
      @type_class = type_class
      @typed_context = nil
    end

    ##
    # Get the typed context
    #
    # @return [Object, nil] The typed context object
    #
    attr_reader :typed_context

    ##
    # Set the typed context with type validation
    #
    # @param value [Object] The typed context object
    # @raise [TypeError] if value is not of the expected type
    #
    def typed_context=(value)
      if value.nil?
        @typed_context = nil
        return
      end

      raise TypeError, "Expected #{@type_class.name}, got #{value.class.name}" if @type_class && !value.is_a?(@type_class)

      @typed_context = value
    end

    ##
    # Check if typed context is set
    #
    # @return [Boolean] true if typed context is set
    #
    def typed_context?
      !@typed_context.nil?
    end

    ##
    # Get typed context or raise error if not set
    #
    # @return [Object] The typed context object
    # @raise [RuntimeError] if typed context is not set
    #
    def typed_context!
      raise "Typed context not set" if @typed_context.nil?

      @typed_context
    end

    ##
    # Get typed context or return default
    #
    # @param default [Object] Default value if typed context is not set
    # @return [Object] The typed context object or default
    #
    def typed_context_or(default)
      @typed_context || default
    end

    ##
    # Update typed context if it responds to update method
    #
    # @param updates [Hash] Updates to apply to typed context
    # @return [Object] The updated typed context
    #
    def update_typed_context(updates)
      return nil unless @typed_context

      if @typed_context.respond_to?(:update)
        @typed_context.update(updates)
      else
        # Try to set attributes individually
        updates.each do |key, value|
          @typed_context.send("#{key}=", value) if @typed_context.respond_to?("#{key}=")
        end
      end

      @typed_context
    end

    ##
    # Convert typed context to hash if possible
    #
    # @return [Hash, nil] Hash representation of typed context
    #
    def typed_context_to_h
      return nil unless @typed_context

      if @typed_context.respond_to?(:to_h)
        @typed_context.to_h
      elsif @typed_context.respond_to?(:to_hash)
        @typed_context.to_hash
      else
        # Try to extract instance variables
        hash = {}
        @typed_context.instance_variables.each do |var|
          key = var.to_s.sub("@", "").to_sym
          hash[key] = @typed_context.instance_variable_get(var)
        end
        hash
      end
    end

    ##
    # Create a typed wrapper from existing wrapper
    #
    # @param wrapper [RunContextWrapper] Existing wrapper
    # @param type_class [Class] The expected type class
    # @return [TypedRunContextWrapper] New typed wrapper
    #
    def self.from_wrapper(wrapper, type_class)
      new(wrapper.context, type_class)
    end

    ##
    # Factory method to create typed wrapper with initial context
    #
    # @param context [RunContext] The context to wrap
    # @param type_class [Class] The expected type class
    # @param initial_context [Object] Initial typed context object
    # @return [TypedRunContextWrapper] New typed wrapper with initial context
    #
    def self.create_with_context(context, type_class, initial_context)
      wrapper = new(context, type_class)
      wrapper.typed_context = initial_context
      wrapper
    end

    ##
    # String representation including type information
    #
    # @return [String] String representation
    #
    def to_s
      type_info = @type_class ? " <#{@type_class.name}>" : ""
      context_info = @typed_context ? " [SET]" : " [UNSET]"
      "#<#{self.class.name}#{type_info}#{context_info}>"
    end

    ##
    # Inspect representation
    #
    # @return [String] Inspect representation
    #
    def inspect
      to_s
    end

  end

end

# frozen_string_literal: true

require "securerandom"
require "json"

module RAAF

  ##
  # Tool Context Management System
  #
  # The ToolContext class provides comprehensive context tracking and state management
  # for tool executions within RAAF. It enables tools to maintain persistent
  # state between calls, share data across tool invocations, and access detailed
  # execution history for debugging and optimization.
  #
  # == Key Features
  #
  # * **State Management**: Persistent key-value storage for tool data
  # * **Execution Tracking**: Automatic tracking of tool calls, timing, and results
  # * **Shared Memory**: Cross-tool data sharing within the same context
  # * **Thread Safety**: Mutex-based locking for concurrent tool execution
  # * **Context Hierarchies**: Parent-child context relationships
  # * **Import/Export**: Serialization support for context persistence
  # * **Statistics**: Comprehensive execution analytics and performance metrics
  #
  # == Usage Patterns
  #
  # * **Session Management**: Different contexts for different user sessions
  # * **Data Persistence**: Maintaining state across multiple tool calls
  # * **Debugging**: Tracking tool execution for troubleshooting
  # * **Performance Monitoring**: Analyzing tool execution patterns
  # * **Context Isolation**: Separate environments for different workflows
  #
  # @example Basic state management
  #   context = ToolContext.new
  #   context.set("user_id", "123")
  #   context.set("session_data", { preferences: ["dark_mode"] })
  #
  #   user_id = context.get("user_id")  # => "123"
  #   all_data = context.to_h           # => { "user_id" => "123", "session_data" => {...} }
  #
  # @example Context-aware tool creation
  #   context = ToolContext.new(track_executions: true)
  #
  #   tool = FunctionTool.new(
  #     proc { |**args|
  #       user_id = context.get("user_id")
  #       "Processing for user: #{user_id}"
  #     },
  #     name: "process_user_data"
  #   )
  #
  #   contextual_tool = ContextualTool.new(tool.callable, context: context, name: "processor")
  #
  # @example Execution tracking and statistics
  #   context = ToolContext.new(track_executions: true)
  #   # ... tool executions occur ...
  #
  #   history = context.execution_history(limit: 10)
  #   stats = context.execution_stats
  #   puts "Success rate: #{stats[:success_rate]}%"
  #   puts "Average duration: #{stats[:avg_duration]}ms"
  #
  # @example Shared memory between tools
  #   context = ToolContext.new
  #
  #   # Tool 1 stores data
  #   context.shared_set("api_cache", { "weather_nyc" => "sunny" })
  #
  #   # Tool 2 accesses shared data
  #   cache = context.shared_get("api_cache", {})
  #   weather = cache["weather_nyc"] || "unknown"
  #
  # @example Thread-safe operations
  #   context = ToolContext.new
  #
  #   context.with_lock("counter") do
  #     current = context.get("counter", 0)
  #     context.set("counter", current + 1)
  #   end
  #
  # @example Context hierarchies
  #   parent_context = ToolContext.new
  #   parent_context.set("global_setting", "value")
  #
  #   child_context = parent_context.create_child(
  #     additional_data: { "local_setting" => "child_value" }
  #   )
  #   # Child has access to both global_setting and local_setting
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  # @see ContextualTool For context-aware tool execution
  # @see ContextManager For multi-session context management
  class ToolContext
    # Class-level shared memory for all contexts
    @@global_shared_memory = {}
    @@global_shared_memory_mutex = Mutex.new

    # @return [String] unique identifier for this context instance
    attr_reader :id

    # @return [Time] when this context was created
    attr_reader :created_at

    # @return [Hash] metadata associated with this context
    attr_reader :metadata
    
    # @return [ToolContext, nil] parent context if any
    attr_reader :parent
    
    # @return [Array<ToolContext>] child contexts
    attr_reader :children

    ##
    # Initialize a new tool context
    #
    # @param initial_data [Hash] initial key-value data to populate the context
    # @param metadata [Hash] metadata to associate with this context
    # @param track_executions [Boolean] whether to track tool execution history
    #
    # @example Basic initialization
    #   context = ToolContext.new
    #
    # @example With initial data and metadata
    #   context = ToolContext.new(
    #     initial_data: { "user_id" => "123", "session" => "abc" },
    #     metadata: { "environment" => "production" },
    #     track_executions: true
    #   )
    def initialize(initial_data: {}, metadata: {}, track_executions: true, parent: nil)
      @id = SecureRandom.uuid
      @created_at = Time.now
      @metadata = metadata
      @data = initial_data.dup
      @track_executions = track_executions
      @execution_history = []
      @shared_memory = {}
      @locks = {}
      @parent = parent
      @children = []
      
      # Register with parent if present
      @parent.instance_variable_get(:@children) << self if @parent
    end

    # Get a value from context
    def get(key, default = nil)
      # First check own data
      if @data.key?(key.to_s)
        @data[key.to_s]
      elsif @parent
        # Fall back to parent
        @parent.get(key, default)
      else
        default
      end
    end

    # Set a value in context
    def set(key, value)
      @data[key.to_s] = value
    end

    # Delete a value from context
    def delete(key)
      @data.delete(key.to_s)
    end

    # Check if key exists
    def has?(key)
      @data.key?(key.to_s)
    end

    # Get all context data
    def to_h
      @data.dup
    end

    # Merge data into context
    def merge!(data)
      @data.merge!(data.transform_keys(&:to_s))
    end

    # Clear all context data
    def clear!
      @data.clear
      @execution_history.clear
      @shared_memory.clear
    end

    # Track a tool execution
    def track_execution(tool_name, input, output = nil, duration = nil, error: nil, &block)
      # Support block-based API for automatic timing and result capture
      if block_given?
        start_time = Time.now
        result = nil
        error_caught = nil
        
        begin
          result = block.call
        rescue => e
          error_caught = e
          raise
        ensure
          duration = Time.now - start_time
          track_execution_internal(tool_name, input, result, duration, error: error_caught)
        end
        
        return result
      else
        # Direct API call
        track_execution_internal(tool_name, input, output, duration, error: error)
      end
    end
    
    private
    
    def track_execution_internal(tool_name, input, output, duration, error: nil)
      return unless @track_executions

      execution = {
        id: SecureRandom.uuid,
        tool_name: tool_name,
        input: input,
        output: output,
        duration: duration,
        timestamp: Time.now,
        success: error.nil?
      }

      execution[:error] = error.to_s if error

      @execution_history << execution

      # Limit history size to prevent memory issues
      @execution_history.shift if @execution_history.size > 1000
    end
    
    public

    # Get execution history
    def execution_history(tool_name: nil, limit: nil)
      history = @execution_history

      # Filter by tool name if specified
      history = history.select { |e| e[:tool_name] == tool_name } if tool_name

      # Apply limit if specified
      history = history.last(limit) if limit

      history
    end

    # Get execution statistics
    def execution_stats(tool_name: nil)
      executions = tool_name ? execution_history(tool_name: tool_name) : @execution_history

      return {} if executions.empty?

      total = executions.size
      successful = executions.count { |e| e[:success] }
      failed = total - successful

      durations = executions.select { |e| e[:success] }.map { |e| e[:duration] }

      stats = {
        total_executions: total,
        successful: successful,
        failed: failed,
        success_rate: (successful.to_f / total * 100).round(2)
      }

      if durations.any?
        stats[:avg_duration] = (durations.sum / durations.size).round(3)
        stats[:min_duration] = durations.min.round(3)
        stats[:max_duration] = durations.max.round(3)
      end

      # Tool-specific stats
      if tool_name.nil?
        tool_names = executions.map { |e| e[:tool_name] }.uniq
        stats[:tools] = {}

        tool_names.each do |name|
          stats[:tools][name] = execution_stats(tool_name: name)
        end
      end

      stats
    end

    # Shared memory between tools
    def shared_get(key, default = nil)
      @@global_shared_memory_mutex.synchronize do
        @@global_shared_memory.fetch(key.to_s, default)
      end
    end

    def shared_set(key, value)
      @@global_shared_memory_mutex.synchronize do
        @@global_shared_memory[key.to_s] = value
      end
    end

    def shared_delete(key)
      @@global_shared_memory_mutex.synchronize do
        @@global_shared_memory.delete(key.to_s)
      end
    end

    # Thread-safe operations with locking
    def with_lock(key, &)
      lock = (@locks[key.to_s] ||= Mutex.new)
      lock.synchronize(&)
    end

    # Create a child context
    def create_child(additional_data: {})
      ToolContext.new(
        initial_data: additional_data,
        metadata: @metadata.merge(parent_id: @id),
        track_executions: @track_executions,
        parent: self
      )
    end

    # Export context for persistence
    def export
      {
        id: @id,
        created_at: @created_at.iso8601,
        metadata: @metadata,
        data: @data,
        shared_memory: @shared_memory,
        execution_history: @execution_history
      }
    end
    
    # Export context as JSON string
    def to_json(*args)
      export.to_json(*args)
    end
    
    # Import data from hash
    def from_hash(data, replace: false)
      if replace
        @data.clear
      end
      @data.merge!(data.transform_keys(&:to_s))
    end
    
    # Get most used tools
    def most_used_tools(limit: nil)
      tool_counts = @execution_history.group_by { |e| e[:tool_name] }
                                      .transform_values(&:size)
                                      .sort_by { |_, count| -count }
                                      .map(&:first)
      
      limit ? tool_counts.first(limit) : tool_counts
    end
    
    # Calculate average execution time per tool
    def average_execution_time
      tool_times = {}
      
      @execution_history.select { |e| e[:success] }.group_by { |e| e[:tool_name] }.each do |tool, executions|
        durations = executions.map { |e| e[:duration] }.compact
        next if durations.empty?
        
        tool_times[tool] = durations.sum / durations.size.to_f
      end
      
      tool_times
    end

    # Import context from export
    def self.import(exported_data)
      context = new(
        initial_data: exported_data[:data] || {},
        metadata: exported_data[:metadata] || {}
      )

      # Restore other data
      context.instance_variable_set(:@id, exported_data[:id])
      context.instance_variable_set(:@created_at, Time.parse(exported_data[:created_at]))
      context.instance_variable_set(:@shared_memory, exported_data[:shared_memory] || {})
      context.instance_variable_set(:@execution_history, exported_data[:execution_history] || [])

      context
    end

  end

  # Context-aware tool wrapper
  class ContextualTool < FunctionTool

    attr_reader :context

    def initialize(function, context:, **)
      super(function, **)
      @context = context
    end

    def call(**kwargs)
      start_time = Time.now

      begin
        # Inject context into kwargs if the function accepts it
        if @callable.respond_to?(:parameters)
          params = @callable.parameters
          kwargs[:context] = @context if params.any? { |_type, name| name == :context }
        end

        # Execute the tool using parent's call method
        result = super

        # Track execution
        duration = Time.now - start_time
        @context.track_execution(@name, kwargs, result, duration)

        result
      rescue StandardError => e
        # Track failed execution
        duration = Time.now - start_time
        @context.track_execution(@name, kwargs, nil, duration, error: e)
        raise
      end
    end

    # Alias for backwards compatibility
    alias execute call

  end

  # Context manager for agent execution
  class ContextManager

    def initialize
      @contexts = {}
      @default_context = ToolContext.new
    end

    # Get or create context for a session
    def get_context(session_id = nil)
      return @default_context if session_id.nil?

      @contexts[session_id] ||= ToolContext.new(
        metadata: { session_id: session_id }
      )
    end

    # Create a new context
    def create_context(session_id, initial_data: {}, metadata: {})
      @contexts[session_id] = ToolContext.new(
        initial_data: initial_data,
        metadata: metadata.merge(session_id: session_id)
      )
    end

    # Delete a context
    def delete_context(session_id)
      @contexts.delete(session_id)
    end

    # List all contexts
    def list_contexts
      @contexts.keys
    end

    # Get statistics across all contexts
    def aggregate_stats
      all_stats = @contexts.map do |session_id, context|
        {
          session_id: session_id,
          stats: context.execution_stats
        }
      end

      # Add default context stats
      all_stats << {
        session_id: "default",
        stats: @default_context.execution_stats
      }

      all_stats
    end

    # Export all contexts
    def export_all
      {
        contexts: @contexts.transform_values(&:export),
        default_context: @default_context.export
      }
    end

    # Import contexts
    def import_all(data)
      data[:contexts]&.each do |session_id, context_data|
        @contexts[session_id] = ToolContext.import(context_data)
      end

      return unless data[:default_context]

      @default_context = ToolContext.import(data[:default_context])
    end

  end

  # Agent extension for context support
  class Agent

    attr_accessor :context_manager

    # Add context-aware tool
    def add_contextual_tool(function, context: nil, **)
      context ||= @context_manager&.get_context || ToolContext.new

      tool = ContextualTool.new(function, context: context, **)
      add_tool(tool)
    end

    # Execute tool with context tracking
    alias execute_tool_without_context execute_tool

    def execute_tool(name, **kwargs)
      if @context_manager
        context = @context_manager.get_context(kwargs[:session_id])

        # Find the tool
        tool = @tools.find { |t| t.name == name }

        # If it's a contextual tool, use its context
        if tool.is_a?(ContextualTool)
          tool.execute(**kwargs)
        else
          # Wrap regular tool execution with context tracking
          start_time = Time.now
          begin
            result = execute_tool_without_context(name, **kwargs)
            duration = Time.now - start_time
            context.track_execution(name, kwargs, result, duration)
            result
          rescue StandardError => e
            duration = Time.now - start_time
            context.track_execution(name, kwargs, nil, duration, error: e)
            raise
          end
        end
      else
        execute_tool_without_context(name, **kwargs)
      end
    end

  end

end

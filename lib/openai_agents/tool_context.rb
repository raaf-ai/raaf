# frozen_string_literal: true

require "securerandom"
require "json"

module OpenAIAgents
  # Tool Context Management
  #
  # Provides context tracking and state management for tool executions.
  # This allows tools to maintain state between calls, share data,
  # and access execution history.
  #
  # @example Basic usage
  #   context = ToolContext.new
  #   context.set("user_id", "123")
  #
  #   tool = FunctionTool.new(
  #     proc { |**args| context.get("user_id") },
  #     name: "get_user"
  #   )
  #
  # @example With execution tracking
  #   context = ToolContext.new(track_executions: true)
  #   # Tool executions are automatically tracked
  #
  #   history = context.execution_history
  #   stats = context.execution_stats
  class ToolContext
    attr_reader :id, :created_at, :metadata

    def initialize(initial_data: {}, metadata: {}, track_executions: true)
      @id = SecureRandom.uuid
      @created_at = Time.now
      @metadata = metadata
      @data = initial_data.dup
      @track_executions = track_executions
      @execution_history = []
      @shared_memory = {}
      @locks = {}
    end

    # Get a value from context
    def get(key, default = nil)
      @data.fetch(key.to_s, default)
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
    def track_execution(tool_name, input, output, duration, error: nil)
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
      @shared_memory.fetch(key.to_s, default)
    end

    def shared_set(key, value)
      @shared_memory[key.to_s] = value
    end

    def shared_delete(key)
      @shared_memory.delete(key.to_s)
    end

    # Thread-safe operations with locking
    def with_lock(key, &)
      lock = (@locks[key.to_s] ||= Mutex.new)
      lock.synchronize(&)
    end

    # Create a child context
    def create_child(additional_data: {})
      child_data = @data.merge(additional_data)
      ToolContext.new(
        initial_data: child_data,
        metadata: @metadata.merge(parent_id: @id),
        track_executions: @track_executions
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

    def execute(**kwargs)
      start_time = Time.now

      begin
        # Inject context into kwargs if the function accepts it
        if @function.respond_to?(:parameters)
          params = @function.parameters
          kwargs[:context] = @context if params.any? { |_type, name| name == :context }
        end

        # Execute the tool
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

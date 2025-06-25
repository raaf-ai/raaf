# frozen_string_literal: true

require "async"
require "async/barrier"
require_relative "../agent"
require_relative "base"

module OpenAIAgents
  module Async
    # Async-enhanced Agent class that supports async tool execution
    class Agent < OpenAIAgents::Agent
      include Base

      # Execute a tool asynchronously
      def execute_tool_async(tool_name, **kwargs)
        tool = find_tool(tool_name)
        raise ToolError, "Tool '#{tool_name}' not found" unless tool

        # Check if tool supports async execution
        if tool.respond_to?(:call_async)
          tool.call_async(**kwargs)
        elsif tool.respond_to?(:async) && tool.async
          # Tool has async flag set
          Async do
            tool.call(**kwargs)
          end
        else
          # Wrap synchronous tool in async block
          Async do
            tool.call(**kwargs)
          end
        end
      end

      # Execute multiple tools in parallel
      def execute_tools_async(tool_calls)
        Async do |_task|
          barrier = Async::Barrier.new

          tool_calls.each do |tool_call|
            tool_name = tool_call[:name] || tool_call["name"]
            tool_args = tool_call[:arguments] || tool_call["arguments"] || {}

            barrier.async do
              {
                name: tool_name,
                result: execute_tool_async(tool_name, **tool_args)
              }
            rescue StandardError => e
              {
                name: tool_name,
                error: e.message
              }
            end
          end

          barrier.wait
        end
      end

      # Add async tool support
      def add_tool(tool)
        # If it's a proc or method, wrap it in an async-aware FunctionTool
        if tool.is_a?(Proc) || tool.is_a?(Method)
          tool = AsyncFunctionTool.new(tool)
        elsif tool.respond_to?(:call) && !tool.respond_to?(:to_h)
          # Wrap existing tools to make them async-aware
          tool = AsyncFunctionTool.new(tool)
        end

        super
      end

      private

      def find_tool(name)
        @tools.find { |t| t.name == name.to_s }
      end
    end

    # Async-aware function tool wrapper
    class AsyncFunctionTool < OpenAIAgents::FunctionTool
      include Base

      attr_reader :async

      def initialize(function, async: nil)
        super(function)

        # Auto-detect if function is async
        @async = if async.nil?
                   function.respond_to?(:async) ||
                     (function.is_a?(Method) && function.parameters.any? { |type, _| type == :async })
                 else
                   async
                 end
      end

      # Async version of call
      def call_async(**kwargs)
        if @async
          # Function is already async, just call it
          @function.call(**kwargs)
        else
          # Wrap synchronous function in async block
          Async do
            @function.call(**kwargs)
          end
        end
      end

      # Regular call method
      def call(**)
        if in_async_context? && @async
          # We're in async context and function is async
          call_async(**).wait
        else
          # Synchronous execution
          super
        end
      end

      def to_h
        schema = super
        schema[:async] = @async if @async
        schema
      end
    end
  end
end

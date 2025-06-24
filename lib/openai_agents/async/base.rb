# frozen_string_literal: true

require "async"
require "async/http"
require "async/semaphore"

module OpenAIAgents
  module Async
    # Base module for async support across OpenAI Agents
    module Base
      # Executes a block asynchronously, returning a Task
      def async(&block)
        Async do
          yield
        end
      end

      # Waits for multiple async tasks to complete
      def await_all(*tasks)
        Async do
          tasks.map(&:wait)
        end
      end

      # Creates an async-compatible HTTP client
      def async_http_client
        @async_http_client ||= Async::HTTP::Client.new(
          Async::HTTP::Endpoint.parse("https://api.openai.com")
        )
      end

      # Async sleep
      def async_sleep(duration)
        Async do
          sleep(duration)
        end
      end

      # Run a block with concurrency limit
      def with_concurrency_limit(limit, &block)
        semaphore = Async::Semaphore.new(limit)
        Async do
          semaphore.async do
            yield
          end
        end
      end

      # Convert a synchronous method to async
      def make_async(method_name)
        original_method = method(method_name)
        define_singleton_method("#{method_name}_async") do |*args, **kwargs, &block|
          Async do
            original_method.call(*args, **kwargs, &block)
          end
        end
      end

      # Check if we're in an async context
      def in_async_context?
        Async::Task.current? rescue false
      end

      # Ensure we're in an async context
      def ensure_async(&block)
        if in_async_context?
          yield
        else
          Async { yield }.wait
        end
      end
    end

    # Async-compatible queue for producer-consumer patterns
    class AsyncQueue
      def initialize(max_size = nil)
        @queue = []
        @max_size = max_size
        @mutex = Mutex.new
        @not_empty = Async::Condition.new
        @not_full = Async::Condition.new
      end

      def push(item)
        ensure_async do
          @mutex.synchronize do
            while @max_size && @queue.size >= @max_size
              @not_full.wait
            end
            @queue.push(item)
            @not_empty.signal
          end
        end
      end

      def pop
        ensure_async do
          @mutex.synchronize do
            while @queue.empty?
              @not_empty.wait
            end
            item = @queue.shift
            @not_full.signal if @max_size
            item
          end
        end
      end

      def size
        @mutex.synchronize { @queue.size }
      end

      def empty?
        @mutex.synchronize { @queue.empty? }
      end

      private

      def ensure_async(&block)
        if Async::Task.current?
          yield
        else
          Async { yield }.wait
        end
      end
    end
  end
end
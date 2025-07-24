# frozen_string_literal: true

require "async"
require "async/http"
require "async/semaphore"

module RAAF

  module Async

    # Base module for async support across RAAF
    module Base

      # Executes a block asynchronously, returning a Task
      def async(&)
        Async(&)
      end

      # Waits for multiple async tasks to complete
      def await_all(*tasks)
        Async do
          tasks.map(&:wait)
        end
      end

      # Creates an async-compatible HTTP client
      def async_http_client
        @async_http_client ||= ::Async::HTTP::Client.new(
          ::Async::HTTP::Endpoint.parse("https://api.openai.com")
        )
      end

      # Async sleep
      def async_sleep(duration)
        Async do
          sleep(duration)
        end
      end

      # Run a block with concurrency limit
      def with_concurrency_limit(limit, &)
        semaphore = ::Async::Semaphore.new(limit)
        Async do
          semaphore.async(&).wait
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
        !!::Async::Task.current?
      rescue StandardError
        false
      end

      # Ensure we're in an async context
      def ensure_async(&)
        if in_async_context?
          yield
        else
          Async(&).wait
        end
      end

    end

    # Async-compatible queue for producer-consumer patterns
    class AsyncQueue

      def initialize(max_size = nil)
        @queue = []
        @max_size = max_size
        @mutex = Mutex.new
        @not_empty = ::Async::Condition.new
        @not_full = ::Async::Condition.new
      end

      def push(item)
        ensure_async do
          @mutex.synchronize do
            @not_full.wait while @max_size && @queue.size >= @max_size
            @queue.push(item)
            @not_empty.signal
          end
        end
      end

      def pop
        ensure_async do
          @mutex.synchronize do
            @not_empty.wait while @queue.empty?
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

      def ensure_async(&)
        if ::Async::Task.current?
          yield
        else
          Async(&).wait
        end
      end

    end

  end

end

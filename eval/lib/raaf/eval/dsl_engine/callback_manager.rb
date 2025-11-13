# frozen_string_literal: true

module RAAF
  module Eval
    module DslEngine
      # Thread-safe callback manager for progress events
      # Handles registration, invocation, and error handling of progress callbacks
      class CallbackManager
        def initialize
          @callbacks = []
          @mutex = Mutex.new
        end

        # Register a new progress callback
        # @yield Block that receives ProgressEvent objects
        def register(&block)
          @mutex.synchronize do
            @callbacks << block
          end
        end

        # Remove a registered callback
        # @param block [Proc] The callback to remove
        def unregister(block)
          @mutex.synchronize do
            @callbacks.delete(block)
          end
        end

        # Invoke all registered callbacks with event
        # @param event [ProgressEvent] The event to pass to callbacks
        def invoke_callbacks(event)
          # Create snapshot of callbacks under lock
          callbacks_snapshot = @mutex.synchronize { @callbacks.dup }

          # Invoke callbacks outside lock to avoid blocking
          callbacks_snapshot.each do |callback|
            begin
              callback.call(event)
            rescue => e
              log_callback_error(e, event)
            end
          end
        end

        # Remove all registered callbacks
        def clear_all
          @mutex.synchronize do
            @callbacks.clear
          end
        end

        # Get count of registered callbacks
        # @return [Integer] Number of registered callbacks
        def callback_count
          @mutex.synchronize { @callbacks.size }
        end

        private

        # Log callback error without raising
        # @param error [StandardError] The error that occurred
        # @param event [ProgressEvent] The event being processed
        def log_callback_error(error, event)
          warn "⚠️ Progress callback error: #{error.message} (event: #{event.type})"
          warn "   Backtrace: #{error.backtrace.first}" if error.backtrace
        end
      end
    end
  end
end

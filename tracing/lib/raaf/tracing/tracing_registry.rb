# frozen_string_literal: true

require "securerandom"

module RAAF
  module Tracing
    # TracingRegistry provides ambient trace context management for RAAF.
    #
    # This registry enables framework-agnostic automatic tracing by storing
    # tracer instances in thread-local and fiber-local contexts. This allows
    # RAAF agents and components to automatically participate in traces without
    # requiring explicit tracer configuration in business logic.
    #
    # ## Key Features
    #
    # - **Thread-safe context storage** - Tracers are isolated per thread
    # - **Fiber-aware execution** - Supports async operations and fiber concurrency
    # - **Priority hierarchy** - Thread → Fiber → Process → NoOp fallback
    # - **Automatic cleanup** - Proper context restoration in ensure blocks
    # - **Framework agnostic** - Works with any Ruby web framework or application
    # - **Zero dependencies** - Uses only Ruby standard library features
    #
    # ## Usage Patterns
    #
    # ### Basic Context Scoping
    # ```ruby
    # TracingRegistry.with_tracer(my_tracer) do
    #   # All RAAF operations in this block automatically use my_tracer
    #   runner = RAAF::Runner.new(agent: agent)
    #   result = runner.run("Hello") # Automatically traced
    # end
    # ```
    #
    # ### Framework Integration
    # ```ruby
    # # Rails middleware example
    # class RaafTracingMiddleware
    #   def call(env)
    #     tracer = create_request_tracer(env)
    #     TracingRegistry.with_tracer(tracer) do
    #       @app.call(env)
    #     end
    #   end
    # end
    # ```
    #
    # ### Process-level Configuration
    # ```ruby
    # # Set default tracer for the entire process
    # TracingRegistry.set_process_tracer(global_tracer)
    #
    # # All subsequent RAAF operations use global_tracer unless overridden
    # runner = RAAF::Runner.new(agent: agent)
    # result = runner.run("Hello") # Uses global_tracer
    # ```
    #
    # ## Context Priority
    #
    # The registry follows a clear priority hierarchy when determining which
    # tracer to use:
    #
    # 1. **Thread-local**: `Thread.current[:raaf_tracer]` (highest priority)
    # 2. **Fiber-local**: `Fiber.current[:raaf_tracer]` (async operations)
    # 3. **Process-level**: Configured via `set_process_tracer`
    # 4. **NoOpTracer**: Zero-overhead fallback when tracing disabled
    #
    # This hierarchy ensures that:
    # - Request-scoped tracers take precedence over global configuration
    # - Async operations maintain proper trace context
    # - Applications continue working when tracing is disabled
    # - No memory leaks from accumulated context state
    #
    # ## Thread Safety
    #
    # All operations are thread-safe through Ruby's built-in thread-local
    # and fiber-local storage mechanisms. Each thread and fiber maintains
    # isolated tracer contexts that don't interfere with each other.
    #
    # ## Integration with RAAF Components
    #
    # The registry integrates seamlessly with existing RAAF components:
    #
    # - **RAAF::Runner** - Automatically detects registered tracers
    # - **RAAF::Tracing::Traceable** - Updated to check registry first
    # - **RAAF::DSL::Agent** - Pipeline agents use registry context
    # - **Framework adapters** - Middleware sets up registry context
    #
    # @example Basic usage
    #   # Set up tracing context
    #   tracer = RAAF::Tracing::SpanTracer.new
    #   TracingRegistry.with_tracer(tracer) do
    #     # All RAAF operations automatically traced
    #     agent = RAAF::Agent.new(name: "Assistant")
    #     runner = RAAF::Runner.new(agent: agent)
    #     result = runner.run("Hello world")
    #   end
    #
    # @example Process-level configuration
    #   # Configure once at application startup
    #   TracingRegistry.set_process_tracer(global_tracer)
    #
    #   # Use throughout application without explicit configuration
    #   def handle_request
    #     agent = RAAF::Agent.new(name: "RequestHandler")
    #     runner = RAAF::Runner.new(agent: agent) # Uses global_tracer
    #     runner.run(request_data)
    #   end
    #
    # @example Nested contexts
    #   TracingRegistry.with_tracer(outer_tracer) do
    #     outer_operation()
    #
    #     TracingRegistry.with_tracer(inner_tracer) do
    #       inner_operation() # Uses inner_tracer
    #     end
    #
    #     final_operation() # Back to outer_tracer
    #   end
    #
    # @see RAAF::Runner Integration with auto-detection
    # @see RAAF::Tracing::Traceable Updated priority hierarchy
    class TracingRegistry
      # Thread-safe process-level tracer storage
      @process_tracer = nil
      @process_tracer_mutex = Mutex.new

      class << self
        # Execute a block with a specific tracer in the current context.
        #
        # This method sets up a tracer context for the duration of the block,
        # ensuring proper cleanup even if exceptions occur. The tracer is stored
        # in thread-local storage, making it available to all RAAF operations
        # within the same thread during block execution.
        #
        # The context is automatically cleaned up when the block completes,
        # restoring any previous tracer that was active before this call.
        #
        # @param tracer [Object] Tracer instance to use within the block.
        #   Can be any object that implements the tracer interface, or nil
        #   to explicitly disable tracing in this context.
        # @yield Block to execute within the tracer context
        # @return [Object] The return value of the block
        #
        # @example Basic context scoping
        #   TracingRegistry.with_tracer(my_tracer) do
        #     # All RAAF operations automatically use my_tracer
        #     runner = RAAF::Runner.new(agent: agent)
        #     runner.run("Hello") # Traced with my_tracer
        #   end
        #
        # @example Nested contexts
        #   TracingRegistry.with_tracer(outer_tracer) do
        #     outer_work()
        #     TracingRegistry.with_tracer(inner_tracer) do
        #       inner_work() # Uses inner_tracer
        #     end
        #     more_outer_work() # Back to outer_tracer
        #   end
        #
        # @example Exception safety
        #   TracingRegistry.with_tracer(tracer) do
        #     risky_operation() # Even if this raises, context is cleaned up
        #   end
        #   # Previous tracer context is properly restored
        #
        def with_tracer(tracer)
          # Store the current tracer to restore later
          previous_tracer = Thread.current[:raaf_tracer]

          begin
            # Set the new tracer in thread-local storage
            Thread.current[:raaf_tracer] = tracer
            
            # Execute the block with the new tracer context
            yield
          ensure
            # Always restore the previous tracer, even if block raises
            Thread.current[:raaf_tracer] = previous_tracer
          end
        end

        # Get the currently active tracer following the priority hierarchy.
        #
        # This method implements the core tracer discovery logic used throughout
        # RAAF. It checks multiple sources in priority order to find the most
        # appropriate tracer for the current execution context.
        #
        # The priority hierarchy ensures that:
        # - Request/thread-specific tracers override global settings
        # - Fiber-local context is respected for async operations
        # - Process-wide configuration provides sensible defaults
        # - Applications continue working when tracing is disabled
        #
        # @return [Object] Active tracer instance following priority hierarchy:
        #   1. Thread.current[:raaf_tracer] (highest priority)
        #   2. Fiber.current[:raaf_tracer] (for async operations)
        #   3. Process-level tracer (configured via set_process_tracer)
        #   4. NoOpTracer instance (zero-overhead fallback)
        #
        # @example Basic usage
        #   tracer = TracingRegistry.current_tracer
        #   if tracer.is_a?(RAAF::Tracing::NoOpTracer)
        #     # Tracing is disabled
        #   else
        #     # Use tracer for span creation
        #   end
        #
        # @example Integration in RAAF components
        #   class MyAgent
        #     def run(input)
        #       tracer = TracingRegistry.current_tracer
        #       # tracer automatically determined from context
        #     end
        #   end
        #
        def current_tracer
          # 1. Thread-local tracer (highest priority)
          # This is set by with_tracer() or direct assignment
          if Thread.current[:raaf_tracer]
            return Thread.current[:raaf_tracer]
          end

          # 2. Fiber-local tracer (async operations)
          # Check if we're in a fiber and it has a tracer
          if defined?(Fiber) && fiber_context_available?
            fiber_tracer = Fiber.current[:raaf_tracer]
            return fiber_tracer if fiber_tracer
          end

          # 3. Process-level tracer (global configuration)
          # Thread-safe access to process tracer
          @process_tracer_mutex.synchronize do
            return @process_tracer if @process_tracer
          end

          # 4. NoOpTracer fallback (zero overhead when disabled)
          # Ensure we always return a usable tracer interface
          @noop_tracer ||= NoOpTracer.new
        end

        # Configure a process-wide default tracer.
        #
        # This method sets a tracer that will be used by all RAAF operations
        # when no thread-local or fiber-local tracer is available. It's useful
        # for application-wide tracing configuration that doesn't require
        # per-request setup.
        #
        # The process tracer is stored in a thread-safe manner and can be
        # accessed from any thread in the process. It serves as a fallback
        # when more specific contexts (thread/fiber) don't have tracers.
        #
        # Setting the process tracer to nil effectively disables default
        # tracing, causing current_tracer to return NoOpTracer instances.
        #
        # @param tracer [Object, nil] Tracer to use process-wide, or nil to clear
        # @return [void]
        #
        # @example Application startup configuration
        #   # In application initializer
        #   global_tracer = RAAF::Tracing::SpanTracer.new
        #   global_tracer.add_processor(RAAF::Tracing::OpenAIProcessor.new)
        #   TracingRegistry.set_process_tracer(global_tracer)
        #
        #   # Now all RAAF operations use global_tracer by default
        #   agent = RAAF::Agent.new(name: "Assistant")
        #   runner = RAAF::Runner.new(agent: agent)
        #   runner.run("Hello") # Automatically uses global_tracer
        #
        # @example Disabling default tracing
        #   # Clear process tracer to disable default tracing
        #   TracingRegistry.set_process_tracer(nil)
        #
        #   # Operations now use NoOpTracer unless explicitly configured
        #   TracingRegistry.current_tracer # => NoOpTracer instance
        #
        def set_process_tracer(tracer)
          @process_tracer_mutex.synchronize do
            @process_tracer = tracer
          end
        end

        # Clear all tracer contexts for testing and cleanup.
        #
        # This method provides a clean slate by removing tracers from all
        # storage locations: thread-local, fiber-local, and process-level.
        # It's primarily intended for testing scenarios where you need to
        # ensure no context leaks between test cases.
        #
        # In production usage, this method should be called sparingly, as it
        # affects global state. It's most appropriate during application
        # shutdown or in test cleanup phases.
        #
        # @return [void]
        #
        # @example Test cleanup
        #   RSpec.configure do |config|
        #     config.after(:each) do
        #       TracingRegistry.clear_all_contexts!
        #     end
        #   end
        #
        # @example Application shutdown
        #   at_exit do
        #     TracingRegistry.clear_all_contexts!
        #     RAAF::Tracing.shutdown
        #   end
        #
        def clear_all_contexts!
          # Clear thread-local context
          Thread.current[:raaf_tracer] = nil

          # Clear fiber-local context if we're in a fiber
          if defined?(Fiber) && fiber_context_available?
            Fiber.current[:raaf_tracer] = nil
          end

          # Clear process-level tracer in a thread-safe manner
          @process_tracer_mutex.synchronize do
            @process_tracer = nil
          end

          # Clear cached NoOp tracer to ensure fresh instances
          @noop_tracer = nil
        end

        # Check if tracing is currently disabled based on context.
        #
        # This method provides a quick way to determine if tracing is
        # effectively disabled in the current context. Tracing is considered
        # disabled when current_tracer returns a NoOpTracer instance.
        #
        # This check is useful for performance-sensitive code paths that
        # want to avoid expensive operations when tracing is disabled.
        #
        # @return [Boolean] true if current tracer is NoOpTracer, false otherwise
        #
        # @example Performance optimization
        #   unless TracingRegistry.tracing_disabled?
        #     expensive_trace_data = gather_detailed_context()
        #     tracer.custom_span("expensive_operation", expensive_trace_data) do
        #       perform_work()
        #     end
        #   else
        #     perform_work() # Skip tracing overhead
        #   end
        #
        def tracing_disabled?
          current_tracer.is_a?(NoOpTracer)
        end

        # Get process-level tracer (for testing and inspection).
        #
        # This method provides read-only access to the currently configured
        # process-level tracer. It's primarily useful for testing scenarios
        # where you need to inspect the configured state.
        #
        # @return [Object, nil] Current process tracer or nil if not set
        # @api private This method is primarily for internal use and testing
        #
        def process_tracer
          @process_tracer_mutex.synchronize do
            @process_tracer
          end
        end

        private

        # Check if fiber-local context is available and we're in a non-main fiber.
        #
        # This method provides compatibility across Ruby versions that may or may not
        # have Thread#main_fiber method available.
        #
        # @return [Boolean] true if we're in a fiber that can have local storage
        def fiber_context_available?
          return false unless defined?(Fiber)

          current_fiber = Fiber.current
          return false unless current_fiber

          # Try to detect if we're in the main fiber
          # In Ruby 3.0+, we can use Thread.current.main_fiber
          # In older versions, we assume we're in main fiber if current == Thread.current
          if Thread.current.respond_to?(:main_fiber)
            current_fiber != Thread.current.main_fiber
          else
            # Fallback: assume we're in a non-main fiber if Fiber.current responds to []
            # and we have a Fiber that's not the implicit main fiber
            current_fiber.respond_to?(:[]) && current_fiber != Thread.current
          end
        rescue StandardError
          # If any error occurs in fiber detection, assume no fiber context
          false
        end
      end
    end
  end
end
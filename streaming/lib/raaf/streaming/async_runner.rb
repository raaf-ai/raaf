# frozen_string_literal: true

require "async"
require "concurrent-ruby"

module RAAF
  module Streaming
    ##
    # Async runner for non-blocking agent operations
    #
    # Provides asynchronous execution of agent operations using Async library
    # and thread pools. Enables non-blocking agent processing with proper
    # error handling and resource management.
    #
    class AsyncRunner
      include RAAF::Logging

      # @return [Integer] Thread pool size
      attr_reader :pool_size

      # @return [Integer] Queue size
      attr_reader :queue_size

      # @return [Integer] Timeout in seconds
      attr_reader :timeout

      ##
      # Initialize async runner
      #
      # @param pool_size [Integer] Thread pool size
      # @param queue_size [Integer] Queue size
      # @param timeout [Integer] Timeout in seconds
      #
      def initialize(pool_size: 10, queue_size: 100, timeout: 60)
        @pool_size = pool_size
        @queue_size = queue_size
        @timeout = timeout
        @thread_pool = Concurrent::ThreadPoolExecutor.new(
          min_threads: 2,
          max_threads: pool_size,
          max_queue: queue_size,
          fallback_policy: :caller_runs
        )
        @active_tasks = {}
        @task_counter = 0
        @mutex = Mutex.new
      end

      ##
      # Process agent message asynchronously
      #
      # @param agent [Agent] Agent instance
      # @param message [String] Message to process
      # @param options [Hash] Processing options
      # @yield [result] Yields the result when complete
      # @return [String] Task ID
      #
      def process_async(agent, message, **options, &block)
        task_id = generate_task_id
        
        @mutex.synchronize do
          @active_tasks[task_id] = {
            agent: agent,
            message: message,
            options: options,
            block: block,
            status: :queued,
            started_at: Time.current
          }
        end

        # Execute asynchronously
        Async do
          execute_task(task_id)
        end

        task_id
      end

      ##
      # Run multiple agents concurrently
      #
      # @param agents [Array<Agent>] Array of agents
      # @param message [String] Message to send to all agents
      # @param options [Hash] Processing options
      # @yield [agent, result] Yields each agent and its result
      # @return [Array<String>] Array of task IDs
      #
      def process_concurrent(agents, message, **options, &block)
        task_ids = []
        
        agents.each do |agent|
          task_id = process_async(agent, message, **options) do |result|
            block&.call(agent, result)
          end
          task_ids << task_id
        end
        
        task_ids
      end

      ##
      # Wait for all tasks to complete
      #
      # @param task_ids [Array<String>] Task IDs to wait for
      # @param timeout [Integer] Timeout in seconds
      # @return [Array<Hash>] Array of results
      #
      def wait_for_tasks(task_ids, timeout: nil)
        timeout ||= @timeout
        start_time = Time.current
        results = []
        
        while task_ids.any? && (Time.current - start_time) < timeout
          @mutex.synchronize do
            task_ids.each do |task_id|
              task = @active_tasks[task_id]
              if task && task[:status] == :completed
                results << {
                  task_id: task_id,
                  result: task[:result],
                  duration: task[:completed_at] - task[:started_at]
                }
                task_ids.delete(task_id)
              end
            end
          end
          
          sleep(0.1) if task_ids.any?
        end
        
        results
      end

      ##
      # Cancel a task
      #
      # @param task_id [String] Task ID to cancel
      # @return [Boolean] True if cancelled successfully
      #
      def cancel_task(task_id)
        @mutex.synchronize do
          task = @active_tasks[task_id]
          return false unless task
          
          if task[:status] == :running
            task[:status] = :cancelled
            log_info("Task cancelled", task_id: task_id)
            true
          else
            false
          end
        end
      end

      ##
      # Get task status
      #
      # @param task_id [String] Task ID
      # @return [Hash, nil] Task status or nil if not found
      #
      def task_status(task_id)
        @mutex.synchronize do
          task = @active_tasks[task_id]
          return nil unless task
          
          {
            task_id: task_id,
            status: task[:status],
            started_at: task[:started_at],
            completed_at: task[:completed_at],
            duration: task[:completed_at] ? task[:completed_at] - task[:started_at] : nil
          }
        end
      end

      ##
      # Get all active tasks
      #
      # @return [Array<String>] Array of active task IDs
      #
      def active_tasks
        @mutex.synchronize do
          @active_tasks.select { |_, task| task[:status] == :running }.keys
        end
      end

      ##
      # Get runner statistics
      #
      # @return [Hash] Runner statistics
      #
      def stats
        @mutex.synchronize do
          {
            pool_size: @pool_size,
            queue_size: @queue_size,
            active_tasks: @active_tasks.select { |_, task| task[:status] == :running }.size,
            queued_tasks: @active_tasks.select { |_, task| task[:status] == :queued }.size,
            completed_tasks: @active_tasks.select { |_, task| task[:status] == :completed }.size,
            failed_tasks: @active_tasks.select { |_, task| task[:status] == :failed }.size,
            total_tasks: @task_counter
          }
        end
      end

      ##
      # Create an async streaming session
      #
      # @param agent [Agent] Agent instance
      # @param options [Hash] Streaming options
      # @return [AsyncStreamingSession] Async streaming session
      #
      def create_streaming_session(agent, **options)
        AsyncStreamingSession.new(agent: agent, runner: self, **options)
      end

      ##
      # Process with retry logic
      #
      # @param agent [Agent] Agent instance
      # @param message [String] Message to process
      # @param retry_count [Integer] Number of retries
      # @param retry_delay [Float] Delay between retries
      # @param options [Hash] Processing options
      # @yield [result] Yields the result when complete
      # @return [String] Task ID
      #
      def process_with_retry(agent, message, retry_count: 3, retry_delay: 1.0, **options, &block)
        task_id = generate_task_id
        
        @mutex.synchronize do
          @active_tasks[task_id] = {
            agent: agent,
            message: message,
            options: options,
            block: block,
            status: :queued,
            started_at: Time.current,
            retry_count: retry_count,
            retry_delay: retry_delay,
            attempts: 0
          }
        end

        # Execute asynchronously with retry
        Async do
          execute_task_with_retry(task_id)
        end

        task_id
      end

      ##
      # Shutdown the async runner
      #
      def shutdown
        log_info("Shutting down async runner")
        
        # Cancel all active tasks
        @mutex.synchronize do
          @active_tasks.each do |task_id, task|
            if task[:status] == :running
              task[:status] = :cancelled
            end
          end
        end
        
        # Shutdown thread pool
        @thread_pool.shutdown
        @thread_pool.wait_for_termination(10)
        
        log_info("Async runner shutdown complete")
      end

      ##
      # Check if runner is shutdown
      #
      # @return [Boolean] True if shutdown
      def shutdown?
        @thread_pool.shutdown?
      end

      ##
      # Get job count
      #
      # @return [Integer] Number of active jobs
      def job_count
        @mutex.synchronize { @active_tasks.size }
      end

      private

      def generate_task_id
        @mutex.synchronize do
          @task_counter += 1
          "task_#{@task_counter}_#{SecureRandom.hex(8)}"
        end
      end

      def execute_task(task_id)
        task = @active_tasks[task_id]
        return unless task

        begin
          # Update status
          @mutex.synchronize do
            task[:status] = :running
            task[:started_at] = Time.current
          end

          log_debug("Executing async task", task_id: task_id)

          # Execute agent
          agent = task[:agent]
          message = task[:message]
          options = task[:options]
          
          result = agent.run(message, **options)
          
          # Update task with result
          @mutex.synchronize do
            task[:result] = result
            task[:status] = :completed
            task[:completed_at] = Time.current
          end

          log_debug("Task completed", task_id: task_id, 
                   duration: task[:completed_at] - task[:started_at])

          # Call completion block
          task[:block]&.call(result)

        rescue StandardError => e
          # Update task with error
          @mutex.synchronize do
            task[:error] = e
            task[:status] = :failed
            task[:completed_at] = Time.current
          end

          log_error("Task failed", task_id: task_id, error: e)
          
          # Call error handler if available
          task[:error_handler]&.call(e)
        ensure
          # Cleanup after delay
          Async do
            sleep(300) # Keep task info for 5 minutes
            cleanup_task(task_id)
          end
        end
      end

      def execute_task_with_retry(task_id)
        task = @active_tasks[task_id]
        return unless task

        max_attempts = task[:retry_count] + 1
        
        max_attempts.times do |attempt|
          begin
            # Update status
            @mutex.synchronize do
              task[:status] = :running
              task[:attempts] = attempt + 1
            end

            log_debug("Executing task with retry", 
                     task_id: task_id, attempt: attempt + 1, max_attempts: max_attempts)

            # Execute agent
            agent = task[:agent]
            message = task[:message]
            options = task[:options]
            
            result = agent.run(message, **options)
            
            # Update task with result
            @mutex.synchronize do
              task[:result] = result
              task[:status] = :completed
              task[:completed_at] = Time.current
            end

            log_debug("Task completed with retry", 
                     task_id: task_id, attempt: attempt + 1)

            # Call completion block
            task[:block]&.call(result)
            return

          rescue StandardError => e
            if attempt < max_attempts - 1
              # Retry after delay
              log_warn("Task failed, retrying", 
                      task_id: task_id, attempt: attempt + 1, error: e)
              sleep(task[:retry_delay])
            else
              # Final failure
              @mutex.synchronize do
                task[:error] = e
                task[:status] = :failed
                task[:completed_at] = Time.current
              end

              log_error("Task failed after all retries", 
                       task_id: task_id, attempts: max_attempts, error: e)
              
              # Call error handler if available
              task[:error_handler]&.call(e)
            end
          end
        end
      end

      def cleanup_task(task_id)
        @mutex.synchronize do
          @active_tasks.delete(task_id)
        end
      end
    end

    ##
    # Async streaming session
    #
    # Provides an async streaming session for real-time agent communication
    # with proper lifecycle management and error handling.
    #
    class AsyncStreamingSession
      include RAAF::Logging

      # @return [Agent] Agent instance
      attr_reader :agent

      # @return [AsyncRunner] Async runner
      attr_reader :runner

      # @return [String] Session ID
      attr_reader :session_id

      ##
      # Initialize async streaming session
      #
      # @param agent [Agent] Agent instance
      # @param runner [AsyncRunner] Async runner
      # @param options [Hash] Session options
      #
      def initialize(agent:, runner:, **options)
        @agent = agent
        @runner = runner
        @session_id = SecureRandom.hex(16)
        @options = options
        @active = false
        @stream_handlers = {}
        @message_queue = []
        @mutex = Mutex.new
      end

      ##
      # Start streaming session
      #
      def start
        return if @active

        @active = true
        log_info("Starting async streaming session", session_id: @session_id)

        # Start message processing loop
        Async do
          process_message_queue
        end

        self
      end

      ##
      # Stop streaming session
      #
      def stop
        return unless @active

        @active = false
        log_info("Stopping async streaming session", session_id: @session_id)

        self
      end

      ##
      # Send message to agent
      #
      # @param message [String] Message to send
      # @param options [Hash] Message options
      # @yield [chunk] Yields each response chunk
      # @return [String] Stream ID
      #
      def send_message(message, **options, &block)
        return unless @active

        stream_id = SecureRandom.hex(16)
        
        @mutex.synchronize do
          @message_queue << {
            stream_id: stream_id,
            message: message,
            options: options,
            block: block,
            queued_at: Time.current
          }
        end

        stream_id
      end

      ##
      # Set stream handler
      #
      # @param event [String] Event name
      # @param block [Proc] Event handler
      def on(event, &block)
        @mutex.synchronize do
          @stream_handlers[event] = block
        end
      end

      ##
      # Check if session is active
      #
      # @return [Boolean] True if active
      def active?
        @active
      end

      ##
      # Get session statistics
      #
      # @return [Hash] Session statistics
      def stats
        @mutex.synchronize do
          {
            session_id: @session_id,
            active: @active,
            queued_messages: @message_queue.size,
            agent: @agent.name
          }
        end
      end

      private

      def process_message_queue
        while @active
          message_item = nil
          
          @mutex.synchronize do
            message_item = @message_queue.shift
          end

          if message_item
            process_message_item(message_item)
          else
            sleep(0.1)
          end
        end
      end

      def process_message_item(item)
        stream_id = item[:stream_id]
        message = item[:message]
        options = item[:options]
        block = item[:block]

        begin
          # Notify stream start
          @stream_handlers[:stream_start]&.call(stream_id, message)

          # Process with agent
          @runner.process_async(@agent, message, **options) do |result|
            # Process response in chunks
            content = result.messages.last[:content]
            
            StreamProcessor.chunk_response(content) do |chunk|
              chunk_data = {
                content: chunk,
                stream_id: stream_id,
                timestamp: Time.current.iso8601
              }
              
              block&.call(chunk_data)
              @stream_handlers[:chunk]&.call(chunk_data)
            end

            # Notify stream end
            @stream_handlers[:stream_end]&.call(stream_id, result)
          end

        rescue StandardError => e
          log_error("Stream processing error", stream_id: stream_id, error: e)
          @stream_handlers[:error]&.call(stream_id, e)
        end
      end
    end
  end
end
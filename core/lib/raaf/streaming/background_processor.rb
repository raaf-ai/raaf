# frozen_string_literal: true

begin
  require "redis"
rescue LoadError
  # Redis not available - BackgroundProcessor will be disabled
end

require "json"
require "concurrent-ruby"

module RAAF

  module Streaming

    ##
    # Background processor for queued agent operations
    #
    # Provides background processing capabilities for agent operations using
    # Redis as a message queue. Supports job scheduling, retries, and
    # distributed processing across multiple workers.
    #
    class BackgroundProcessor

      include RAAF::Logging

      # @return [String] Redis URL
      attr_reader :redis_url

      # @return [Integer] Number of workers
      attr_reader :workers

      # @return [Integer] Retry count
      attr_reader :retry_count

      # @return [Float] Retry delay
      attr_reader :retry_delay

      ##
      # Initialize background processor
      #
      # @param redis_url [String] Redis URL
      # @param workers [Integer] Number of workers
      # @param retry_count [Integer] Retry count
      # @param retry_delay [Float] Retry delay
      #
      def initialize(redis_url: "redis://localhost:6379", workers: 5, retry_count: 3, retry_delay: 1.0)
        @redis_url = redis_url
        @workers = workers
        @retry_count = retry_count
        @retry_delay = retry_delay
        @worker_threads = []
        @running = false
        @job_handlers = {}
        @job_counter = 0
        @mutex = Mutex.new

        # Initialize Redis if available
        if defined?(Redis)
          begin
            @redis = Redis.new(url: redis_url)
            @redis_available = true
          rescue StandardError => e
            log_warn("Redis connection failed, BackgroundProcessor will be disabled", error: e.message)
            @redis_available = false
          end
        else
          log_warn("Redis gem not available, BackgroundProcessor will be disabled")
          @redis_available = false
        end
      end

      ##
      # Start background processor
      #
      def start
        return if @running

        @running = true
        log_info("Starting background processor", workers: @workers, redis_url: @redis_url)

        # Start worker threads
        @workers.times do |i|
          thread = Thread.new { worker_loop(i) }
          @worker_threads << thread
        end

        self
      end

      ##
      # Stop background processor
      #
      def stop
        return unless @running

        @running = false
        log_info("Stopping background processor")

        # Wait for workers to finish
        @worker_threads.each(&:join)
        @worker_threads.clear

        log_info("Background processor stopped")
        self
      end

      ##
      # Check if processor is running
      #
      # @return [Boolean] True if running
      def running?
        @running
      end

      ##
      # Enqueue a job
      #
      # @param job_type [String] Job type
      # @param data [Hash] Job data
      # @param options [Hash] Job options
      # @return [String] Job ID
      #
      def enqueue_job(job_type, data, **options)
        job_id = generate_job_id
        priority = options[:priority] || :normal
        delay = options[:delay] || 0

        job = {
          id: job_id,
          type: job_type,
          data: data,
          priority: priority,
          created_at: Time.now.to_f,
          attempts: 0,
          max_attempts: @retry_count + 1
        }

        queue_name = queue_name_for_priority(priority)

        if delay.positive?
          # Schedule for later
          @redis.zadd("raaf:scheduled_jobs", Time.now.to_f + delay, JSON.generate(job))
        else
          # Enqueue immediately
          @redis.lpush(queue_name, JSON.generate(job))
        end

        log_debug("Job enqueued", job_id: job_id, job_type: job_type, priority: priority)
        job_id
      end

      ##
      # Schedule a job for later execution
      #
      # @param job_type [String] Job type
      # @param data [Hash] Job data
      # @param at [Time] When to execute
      # @param options [Hash] Job options
      # @return [String] Job ID
      #
      def schedule_job(job_type, data, at:, **)
        delay = at.to_f - Time.now.to_f
        enqueue_job(job_type, data, delay: delay, **)
      end

      ##
      # Register job handler
      #
      # @param job_type [String] Job type
      # @param block [Proc] Job handler
      def handle_job(job_type, &block)
        @mutex.synchronize do
          @job_handlers[job_type] = block
        end
      end

      ##
      # Get queue size
      #
      # @param priority [Symbol] Priority level
      # @return [Integer] Queue size
      def queue_size(priority = :normal)
        queue_name = queue_name_for_priority(priority)
        @redis.llen(queue_name)
      end

      ##
      # Get total queue size
      #
      # @return [Integer] Total queue size
      def total_queue_size
        high_size = queue_size(:high)
        normal_size = queue_size(:normal)
        low_size = queue_size(:low)
        high_size + normal_size + low_size
      end

      ##
      # Get scheduled jobs count
      #
      # @return [Integer] Scheduled jobs count
      def scheduled_jobs_count
        @redis.zcard("raaf:scheduled_jobs")
      end

      ##
      # Get processor statistics
      #
      # @return [Hash] Processor statistics
      def stats
        {
          running: @running,
          workers: @workers,
          high_priority_queue: queue_size(:high),
          normal_priority_queue: queue_size(:normal),
          low_priority_queue: queue_size(:low),
          scheduled_jobs: scheduled_jobs_count,
          total_jobs: @job_counter
        }
      end

      ##
      # Clear all queues
      #
      def clear_queues
        @redis.del("raaf:jobs:high")
        @redis.del("raaf:jobs:normal")
        @redis.del("raaf:jobs:low")
        @redis.del("raaf:scheduled_jobs")
        @redis.del("raaf:processing_jobs")
        @redis.del("raaf:failed_jobs")

        log_info("All queues cleared")
      end

      ##
      # Get failed jobs
      #
      # @param limit [Integer] Number of jobs to retrieve
      # @return [Array<Hash>] Failed jobs
      def failed_jobs(limit = 100)
        jobs = @redis.lrange("raaf:failed_jobs", 0, limit - 1)
        jobs.map { |job| JSON.parse(job) }
      end

      ##
      # Retry failed job
      #
      # @param job_id [String] Job ID
      # @return [Boolean] True if retried successfully
      def retry_failed_job(job_id)
        failed_jobs.each do |job|
          next unless job["id"] == job_id

          job["attempts"] = 0
          priority = job["priority"].to_sym
          queue_name = queue_name_for_priority(priority)

          @redis.lpush(queue_name, JSON.generate(job))
          @redis.lrem("raaf:failed_jobs", 1, JSON.generate(job))

          log_info("Job retried", job_id: job_id)
          return true
        end

        false
      end

      ##
      # Process agent message in background
      #
      # @param agent [Agent] Agent instance
      # @param message [String] Message to process
      # @param options [Hash] Processing options
      # @return [String] Job ID
      #
      def process_agent_message(agent, message, **options)
        enqueue_job("process_agent_message", {
                      agent_id: agent.id,
                      agent_name: agent.name,
                      message: message,
                      options: options
                    }, **options)
      end

      ##
      # Process agent streaming in background
      #
      # @param agent [Agent] Agent instance
      # @param message [String] Message to process
      # @param callback_url [String] Callback URL for results
      # @param options [Hash] Processing options
      # @return [String] Job ID
      #
      def process_agent_streaming(agent, message, callback_url, **options)
        enqueue_job("process_agent_streaming", {
                      agent_id: agent.id,
                      agent_name: agent.name,
                      message: message,
                      callback_url: callback_url,
                      options: options
                    }, **options)
      end

      ##
      # Process agent handoff in background
      #
      # @param from_agent [Agent] Source agent
      # @param to_agent [Agent] Target agent
      # @param context [Hash] Handoff context
      # @param options [Hash] Processing options
      # @return [String] Job ID
      #
      def process_agent_handoff(from_agent, to_agent, context, **options)
        enqueue_job("process_agent_handoff", {
                      from_agent_id: from_agent.id,
                      to_agent_id: to_agent.id,
                      context: context,
                      options: options
                    }, **options)
      end

      ##
      # Get job count
      #
      # @return [Integer] Number of jobs
      def job_count
        total_queue_size
      end

      private

      def generate_job_id
        @mutex.synchronize do
          @job_counter += 1
          "job_#{@job_counter}_#{SecureRandom.hex(8)}"
        end
      end

      def queue_name_for_priority(priority)
        case priority
        when :high
          "raaf:jobs:high"
        when :low
          "raaf:jobs:low"
        else
          "raaf:jobs:normal"
        end
      end

      def worker_loop(worker_id)
        log_info("Starting worker", worker_id: worker_id)

        while @running
          begin
            # Process scheduled jobs first
            process_scheduled_jobs

            # Process queued jobs by priority
            job = fetch_next_job

            if job
              process_job(job, worker_id)
            else
              sleep(1) # No jobs available
            end
          rescue StandardError => e
            log_error("Worker error", worker_id: worker_id, error: e)
            sleep(1)
          end
        end

        log_info("Worker stopped", worker_id: worker_id)
      end

      def process_scheduled_jobs
        current_time = Time.now.to_f

        # Get jobs ready to be processed
        jobs = @redis.zrangebyscore("raaf:scheduled_jobs", "-inf", current_time)

        jobs.each do |job_json|
          job = JSON.parse(job_json)
          priority = job["priority"].to_sym
          queue_name = queue_name_for_priority(priority)

          # Move to appropriate queue
          @redis.lpush(queue_name, job_json)
          @redis.zrem("raaf:scheduled_jobs", job_json)
        end
      end

      def fetch_next_job
        # Try high priority first
        job_json = @redis.brpop("raaf:jobs:high", timeout: 0.1)
        return JSON.parse(job_json[1]) if job_json

        # Then normal priority
        job_json = @redis.brpop("raaf:jobs:normal", timeout: 0.1)
        return JSON.parse(job_json[1]) if job_json

        # Finally low priority
        job_json = @redis.brpop("raaf:jobs:low", timeout: 0.1)
        return JSON.parse(job_json[1]) if job_json

        nil
      end

      def process_job(job, worker_id)
        job_id = job["id"]
        job_type = job["type"]

        log_debug("Processing job", job_id: job_id, job_type: job_type, worker_id: worker_id)

        # Mark as processing
        @redis.hset("raaf:processing_jobs", job_id, JSON.generate(job))

        begin
          # Get job handler
          handler = @job_handlers[job_type]
          raise StandardError, "No handler for job type: #{job_type}" unless handler

          # Execute job
          handler.call(job["data"])

          # Job completed successfully
          @redis.hdel("raaf:processing_jobs", job_id)
          log_debug("Job completed", job_id: job_id, worker_id: worker_id)
        rescue StandardError => e
          log_error("Job failed", job_id: job_id, error: e, worker_id: worker_id)

          # Increment attempts
          job["attempts"] += 1
          job["last_error"] = e.message
          job["failed_at"] = Time.now.to_f

          @redis.hdel("raaf:processing_jobs", job_id)

          if job["attempts"] < job["max_attempts"]
            # Retry after delay
            delay = @retry_delay * (job["attempts"]**2) # Exponential backoff
            @redis.zadd("raaf:scheduled_jobs", Time.now.to_f + delay, JSON.generate(job))
            log_info("Job scheduled for retry", job_id: job_id, attempts: job["attempts"])
          else
            # Move to failed jobs
            @redis.lpush("raaf:failed_jobs", JSON.generate(job))
            log_error("Job failed permanently", job_id: job_id, attempts: job["attempts"])
          end
        end
      end

    end

  end

end

# frozen_string_literal: true

begin
  require "redis"
rescue LoadError
  # Redis not available - MessageQueue will use in-memory fallback
end

require "json"
require "concurrent-ruby"

module RAAF

  module Streaming

    ##
    # Message queue for reliable message handling
    #
    # Provides a Redis-backed message queue with support for message priorities,
    # acknowledgments, dead letter queues, and message persistence.
    #
    class MessageQueue

      include RAAF::Logging

      # @return [String] Redis URL
      attr_reader :redis_url

      # @return [Integer] Maximum queue size
      attr_reader :max_size

      # @return [Integer] Batch size for processing
      attr_reader :batch_size

      # @return [String] Queue name
      attr_reader :queue_name

      ##
      # Initialize message queue
      #
      # @param redis_url [String] Redis URL
      # @param max_size [Integer] Maximum queue size
      # @param batch_size [Integer] Batch size for processing
      # @param queue_name [String] Queue name
      #
      def initialize(redis_url: "redis://localhost:6379", max_size: 10_000, batch_size: 100, queue_name: "raaf_messages")
        @redis_url = redis_url
        @max_size = max_size
        @batch_size = batch_size
        @queue_name = queue_name
        @processing_queue = "#{queue_name}:processing"
        @dead_letter_queue = "#{queue_name}:dead_letters"
        @message_counter = 0
        @mutex = Mutex.new

        # Initialize Redis if available
        if defined?(Redis)
          begin
            @redis = Redis.new(url: redis_url)
            @redis_available = true
          rescue StandardError => e
            log_warn("Redis connection failed, MessageQueue will not be available", error: e.message)
            @redis_available = false
          end
        else
          log_warn("Redis gem not available, MessageQueue will not be available")
          @redis_available = false
        end
      end

      ##
      # Enqueue a message
      #
      # @param message [Hash] Message data
      # @param priority [Symbol] Message priority (:high, :normal, :low)
      # @param ttl [Integer] Time-to-live in seconds
      # @return [String] Message ID
      #
      def enqueue(message, priority: :normal, ttl: nil)
        return nil unless redis_available?

        message_id = generate_message_id

        envelope = {
          id: message_id,
          data: message,
          priority: priority,
          created_at: Time.now.to_f,
          ttl: ttl,
          attempts: 0,
          max_attempts: 3
        }

        queue_key = priority_queue_key(priority)

        # Check queue size
        raise StandardError, "Queue size limit exceeded" if @redis.llen(queue_key) >= @max_size

        # Enqueue message
        @redis.lpush(queue_key, JSON.generate(envelope))

        # Set TTL if specified
        @redis.expire(queue_key, ttl) if ttl

        log_debug("Message enqueued", message_id: message_id, priority: priority)
        message_id
      end

      ##
      # Dequeue a message
      #
      # @param timeout [Integer] Timeout in seconds
      # @return [Hash, nil] Message envelope or nil if timeout
      #
      def dequeue(timeout: 5)
        return nil unless redis_available?

        # Try high priority first
        result = @redis.brpop(priority_queue_key(:high), timeout: 1)
        return process_dequeued_message(result) if result

        # Then normal priority
        result = @redis.brpop(priority_queue_key(:normal), timeout: 1)
        return process_dequeued_message(result) if result

        # Finally low priority
        result = @redis.brpop(priority_queue_key(:low), timeout: timeout)
        return process_dequeued_message(result) if result

        nil
      end

      ##
      # Dequeue multiple messages
      #
      # @param count [Integer] Number of messages to dequeue
      # @param timeout [Integer] Timeout in seconds
      # @return [Array<Hash>] Array of message envelopes
      #
      def dequeue_batch(count: nil, timeout: 5)
        count ||= @batch_size
        messages = []

        count.times do
          message = dequeue(timeout: timeout / count)
          break unless message

          messages << message
        end

        messages
      end

      ##
      # Acknowledge message processing
      #
      # @param message_id [String] Message ID
      # @return [Boolean] True if acknowledged successfully
      #
      def acknowledge(message_id)
        result = @redis.lrem(@processing_queue, 1, message_id)
        success = result.positive?

        if success
          log_debug("Message acknowledged", message_id: message_id)
        else
          log_warn("Message not found in processing queue", message_id: message_id)
        end

        success
      end

      ##
      # Reject message and optionally requeue
      #
      # @param message_id [String] Message ID
      # @param requeue [Boolean] Whether to requeue the message
      # @return [Boolean] True if rejected successfully
      #
      def reject(message_id, requeue: true)
        # Find message in processing queue
        processing_messages = @redis.lrange(@processing_queue, 0, -1)

        processing_messages.each do |msg_json|
          envelope = JSON.parse(msg_json)
          next unless envelope["id"] == message_id

          # Remove from processing queue
          @redis.lrem(@processing_queue, 1, msg_json)

          if requeue
            # Increment attempts
            envelope["attempts"] += 1

            if envelope["attempts"] < envelope["max_attempts"]
              # Requeue with delay
              delay = envelope["attempts"] * 2 # Exponential backoff
              @redis.zadd("#{@queue_name}:delayed", Time.now.to_f + delay, JSON.generate(envelope))
              log_info("Message requeued with delay", message_id: message_id, delay: delay)
            else
              # Move to dead letter queue
              @redis.lpush(@dead_letter_queue, JSON.generate(envelope))
              log_warn("Message moved to dead letter queue", message_id: message_id)
            end
          else
            log_debug("Message rejected", message_id: message_id)
          end

          return true
        end

        false
      end

      ##
      # Get queue size
      #
      # @param priority [Symbol] Priority level
      # @return [Integer] Queue size
      #
      def size(priority = nil)
        if priority
          @redis.llen(priority_queue_key(priority))
        else
          high_size = @redis.llen(priority_queue_key(:high))
          normal_size = @redis.llen(priority_queue_key(:normal))
          low_size = @redis.llen(priority_queue_key(:low))
          high_size + normal_size + low_size
        end
      end

      ##
      # Get processing queue size
      #
      # @return [Integer] Processing queue size
      #
      def processing_size
        @redis.llen(@processing_queue)
      end

      ##
      # Get dead letter queue size
      #
      # @return [Integer] Dead letter queue size
      #
      def dead_letter_size
        @redis.llen(@dead_letter_queue)
      end

      ##
      # Get delayed messages count
      #
      # @return [Integer] Delayed messages count
      #
      def delayed_size
        @redis.zcard("#{@queue_name}:delayed")
      end

      ##
      # Peek at next message without dequeuing
      #
      # @param priority [Symbol] Priority level
      # @return [Hash, nil] Message envelope or nil if empty
      #
      def peek(priority: :normal)
        queue_key = priority_queue_key(priority)
        message_json = @redis.lindex(queue_key, -1)
        return nil unless message_json

        JSON.parse(message_json)
      end

      ##
      # Clear queue
      #
      # @param priority [Symbol] Priority level (nil for all)
      #
      def clear(priority: nil)
        if priority
          @redis.del(priority_queue_key(priority))
        else
          @redis.del(priority_queue_key(:high))
          @redis.del(priority_queue_key(:normal))
          @redis.del(priority_queue_key(:low))
        end

        log_info("Queue cleared", priority: priority || "all")
      end

      ##
      # Get queue statistics
      #
      # @return [Hash] Queue statistics
      #
      def stats
        {
          high_priority_size: size(:high),
          normal_priority_size: size(:normal),
          low_priority_size: size(:low),
          total_size: size,
          processing_size: processing_size,
          dead_letter_size: dead_letter_size,
          delayed_size: delayed_size,
          max_size: @max_size,
          batch_size: @batch_size
        }
      end

      ##
      # Start background processing
      #
      def start
        @running = true

        # Start delayed message processor
        @delayed_processor = Thread.new { process_delayed_messages }

        log_info("Message queue started")
        self
      end

      ##
      # Stop background processing
      #
      def stop
        @running = false
        @delayed_processor&.join

        log_info("Message queue stopped")
        self
      end

      ##
      # Process messages with a block
      #
      # @param batch_size [Integer] Batch size
      # @param timeout [Integer] Timeout in seconds
      # @yield [message] Processes each message
      #
      def process_messages(batch_size: nil, timeout: 5)
        batch_size ||= @batch_size

        while @running
          messages = dequeue_batch(count: batch_size, timeout: timeout)
          break if messages.empty?

          messages.each do |envelope|
            yield envelope
            acknowledge(envelope["id"])
          rescue StandardError => e
            log_error("Message processing error",
                      message_id: envelope["id"], error: e)
            reject(envelope["id"], requeue: true)
          end
        end
      end

      ##
      # Get dead letter messages
      #
      # @param limit [Integer] Number of messages to retrieve
      # @return [Array<Hash>] Array of dead letter messages
      #
      def dead_letters(limit = 100)
        messages = @redis.lrange(@dead_letter_queue, 0, limit - 1)
        messages.map { |msg| JSON.parse(msg) }
      end

      ##
      # Retry dead letter message
      #
      # @param message_id [String] Message ID
      # @return [Boolean] True if retried successfully
      #
      def retry_dead_letter(message_id)
        dead_letters.each do |envelope|
          next unless envelope["id"] == message_id

          # Reset attempts and requeue
          envelope["attempts"] = 0
          priority = envelope["priority"].to_sym
          queue_key = priority_queue_key(priority)

          @redis.lpush(queue_key, JSON.generate(envelope))
          @redis.lrem(@dead_letter_queue, 1, JSON.generate(envelope))

          log_info("Dead letter message retried", message_id: message_id)
          return true
        end

        false
      end

      ##
      # Purge dead letter queue
      #
      def purge_dead_letters
        count = @redis.llen(@dead_letter_queue)
        @redis.del(@dead_letter_queue)

        log_info("Dead letter queue purged", count: count)
        count
      end

      ##
      # Check if Redis is available
      #
      # @return [Boolean] True if Redis is available
      def redis_available?
        @redis_available
      end

      private

      def warn_if_unavailable(method_name)
        return true if @redis_available

        log_warn("MessageQueue.#{method_name} not available (Redis not connected)")
        false
      end

      def generate_message_id
        @mutex.synchronize do
          @message_counter += 1
          "msg_#{@message_counter}_#{SecureRandom.hex(8)}"
        end
      end

      def priority_queue_key(priority)
        "#{@queue_name}:#{priority}"
      end

      def process_dequeued_message(result)
        return nil unless result

        _, message_json = result
        envelope = JSON.parse(message_json)

        # Move to processing queue
        @redis.lpush(@processing_queue, envelope["id"])

        # Check TTL
        if envelope["ttl"] && (Time.now.to_f - envelope["created_at"]) > envelope["ttl"]
          log_warn("Message expired", message_id: envelope["id"])
          acknowledge(envelope["id"])
          return nil
        end

        envelope
      end

      def process_delayed_messages
        while @running
          begin
            current_time = Time.now.to_f

            # Get messages ready to be processed
            messages = @redis.zrangebyscore("#{@queue_name}:delayed", "-inf", current_time)

            messages.each do |message_json|
              envelope = JSON.parse(message_json)
              priority = envelope["priority"].to_sym
              queue_key = priority_queue_key(priority)

              # Move to appropriate queue
              @redis.lpush(queue_key, message_json)
              @redis.zrem("#{@queue_name}:delayed", message_json)
            end

            sleep(1)
          rescue StandardError => e
            log_error("Delayed message processing error", error: e)
            sleep(5)
          end
        end
      end

    end

  end

end

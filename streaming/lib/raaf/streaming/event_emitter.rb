# frozen_string_literal: true

require "concurrent-ruby"

module RubyAIAgentsFactory
  module Streaming
    ##
    # Event emitter for publish-subscribe patterns
    #
    # Provides a thread-safe event emitter implementation with support for
    # wildcard listeners, event filtering, and async event handling.
    #
    class EventEmitter
      include RubyAIAgentsFactory::Logging

      # @return [Integer] Maximum listeners per event
      attr_reader :max_listeners

      # @return [Float] Emit timeout
      attr_reader :emit_timeout

      # @return [Boolean] Enable wildcard matching
      attr_reader :enable_wildcards

      ##
      # Initialize event emitter
      #
      # @param max_listeners [Integer] Maximum listeners per event
      # @param emit_timeout [Float] Emit timeout in seconds
      # @param enable_wildcards [Boolean] Enable wildcard matching
      #
      def initialize(max_listeners: 10, emit_timeout: 5.0, enable_wildcards: true)
        @max_listeners = max_listeners
        @emit_timeout = emit_timeout
        @enable_wildcards = enable_wildcards
        @listeners = Concurrent::Hash.new { |h, k| h[k] = [] }
        @wildcard_listeners = Concurrent::Array.new
        @event_history = Concurrent::Array.new
        @max_history_size = 1000
        @mutex = Mutex.new
      end

      ##
      # Add event listener
      #
      # @param event [String] Event name (supports wildcards if enabled)
      # @param block [Proc] Event handler
      # @return [String] Listener ID
      #
      def on(event, &block)
        raise ArgumentError, "Block is required" unless block

        listener_id = SecureRandom.hex(8)
        
        @mutex.synchronize do
          if @enable_wildcards && event.include?("*")
            @wildcard_listeners << {
              id: listener_id,
              pattern: event,
              regex: wildcard_to_regex(event),
              handler: block,
              created_at: Time.current
            }
          else
            if @listeners[event].size >= @max_listeners
              raise StandardError, "Maximum listeners exceeded for event: #{event}"
            end
            
            @listeners[event] << {
              id: listener_id,
              handler: block,
              created_at: Time.current
            }
          end
        end

        log_debug("Event listener added", event: event, listener_id: listener_id)
        listener_id
      end

      ##
      # Add one-time event listener
      #
      # @param event [String] Event name
      # @param block [Proc] Event handler
      # @return [String] Listener ID
      #
      def once(event, &block)
        listener_id = on(event) do |data|
          block.call(data)
          off(event, listener_id)
        end
        
        listener_id
      end

      ##
      # Remove event listener
      #
      # @param event [String] Event name
      # @param listener_id [String] Listener ID
      # @return [Boolean] True if removed successfully
      #
      def off(event, listener_id)
        @mutex.synchronize do
          if @enable_wildcards && event.include?("*")
            @wildcard_listeners.reject! { |listener| listener[:id] == listener_id }
          else
            @listeners[event].reject! { |listener| listener[:id] == listener_id }
            @listeners.delete(event) if @listeners[event].empty?
          end
        end

        log_debug("Event listener removed", event: event, listener_id: listener_id)
        true
      end

      ##
      # Remove all listeners for an event
      #
      # @param event [String] Event name
      # @return [Integer] Number of listeners removed
      #
      def remove_all_listeners(event)
        count = 0
        
        @mutex.synchronize do
          if @enable_wildcards && event.include?("*")
            regex = wildcard_to_regex(event)
            @wildcard_listeners.reject! { |listener| listener[:pattern] =~ regex }
          else
            count = @listeners[event].size
            @listeners.delete(event)
          end
        end

        log_debug("All listeners removed", event: event, count: count)
        count
      end

      ##
      # Emit event to all listeners
      #
      # @param event [String] Event name
      # @param data [Hash] Event data
      # @return [Integer] Number of listeners notified
      #
      def emit(event, data = {})
        event_data = {
          event: event,
          data: data,
          timestamp: Time.current.iso8601,
          id: SecureRandom.hex(8)
        }

        # Add to event history
        add_to_history(event_data)

        # Get all matching listeners
        listeners = get_matching_listeners(event)
        
        log_debug("Emitting event", event: event, listeners: listeners.size)

        # Notify listeners
        listeners.each do |listener|
          notify_listener(listener, event_data)
        end

        listeners.size
      end

      ##
      # Emit event asynchronously
      #
      # @param event [String] Event name
      # @param data [Hash] Event data
      # @return [Concurrent::Future] Future representing the emit operation
      #
      def emit_async(event, data = {})
        Concurrent::Future.execute do
          emit(event, data)
        end
      end

      ##
      # Get listener count for an event
      #
      # @param event [String] Event name
      # @return [Integer] Number of listeners
      #
      def listener_count(event)
        get_matching_listeners(event).size
      end

      ##
      # Get all event names with listeners
      #
      # @return [Array<String>] Array of event names
      #
      def event_names
        @listeners.keys + @wildcard_listeners.map { |l| l[:pattern] }
      end

      ##
      # Get event history
      #
      # @param limit [Integer] Number of events to retrieve
      # @return [Array<Hash>] Array of event data
      #
      def history(limit = 100)
        @event_history.last(limit)
      end

      ##
      # Get events matching pattern
      #
      # @param pattern [String] Event pattern
      # @param limit [Integer] Number of events to retrieve
      # @return [Array<Hash>] Array of matching events
      #
      def history_for_pattern(pattern, limit = 100)
        regex = wildcard_to_regex(pattern)
        @event_history.select { |event| event[:event] =~ regex }.last(limit)
      end

      ##
      # Clear event history
      #
      def clear_history
        @event_history.clear
        log_debug("Event history cleared")
      end

      ##
      # Get emitter statistics
      #
      # @return [Hash] Emitter statistics
      #
      def stats
        {
          total_listeners: @listeners.values.flatten.size + @wildcard_listeners.size,
          events_with_listeners: @listeners.size,
          wildcard_listeners: @wildcard_listeners.size,
          event_history_size: @event_history.size,
          max_listeners: @max_listeners,
          emit_timeout: @emit_timeout,
          enable_wildcards: @enable_wildcards
        }
      end

      ##
      # Wait for event
      #
      # @param event [String] Event name
      # @param timeout [Float] Timeout in seconds
      # @return [Hash, nil] Event data or nil if timeout
      #
      def wait_for_event(event, timeout: 10.0)
        result = nil
        condition = Concurrent::CountDownLatch.new(1)
        
        listener_id = once(event) do |data|
          result = data
          condition.count_down
        end
        
        if condition.wait(timeout)
          result
        else
          off(event, listener_id)
          nil
        end
      end

      ##
      # Create a filtered emitter
      #
      # @param filter [Proc] Filter block
      # @return [FilteredEventEmitter] Filtered emitter
      #
      def filter(&filter)
        FilteredEventEmitter.new(self, filter)
      end

      ##
      # Create a mapped emitter
      #
      # @param mapper [Proc] Mapper block
      # @return [MappedEventEmitter] Mapped emitter
      #
      def map(&mapper)
        MappedEventEmitter.new(self, mapper)
      end

      private

      def get_matching_listeners(event)
        listeners = []
        
        @mutex.synchronize do
          # Direct listeners
          listeners.concat(@listeners[event] || [])
          
          # Wildcard listeners
          if @enable_wildcards
            @wildcard_listeners.each do |listener|
              if event =~ listener[:regex]
                listeners << listener
              end
            end
          end
        end
        
        listeners
      end

      def notify_listener(listener, event_data)
        begin
          Concurrent::Future.execute do
            Concurrent::timeout(@emit_timeout) do
              listener[:handler].call(event_data)
            end
          end
        rescue StandardError => e
          log_error("Listener error", 
                   listener_id: listener[:id], 
                   event: event_data[:event], 
                   error: e)
        end
      end

      def add_to_history(event_data)
        @event_history << event_data
        
        # Trim history if needed
        if @event_history.size > @max_history_size
          @event_history.shift(@event_history.size - @max_history_size)
        end
      end

      def wildcard_to_regex(pattern)
        escaped = Regexp.escape(pattern)
        regex_pattern = escaped.gsub('\*', '.*')
        Regexp.new("^#{regex_pattern}$")
      end
    end

    ##
    # Filtered event emitter
    #
    # Wraps an event emitter with filtering capabilities.
    #
    class FilteredEventEmitter
      def initialize(emitter, filter)
        @emitter = emitter
        @filter = filter
      end

      def on(event, &block)
        @emitter.on(event) do |data|
          if @filter.call(data)
            block.call(data)
          end
        end
      end

      def once(event, &block)
        @emitter.once(event) do |data|
          if @filter.call(data)
            block.call(data)
          end
        end
      end

      def emit(event, data = {})
        event_data = { event: event, data: data }
        if @filter.call(event_data)
          @emitter.emit(event, data)
        end
      end

      def method_missing(method, *args, &block)
        @emitter.send(method, *args, &block)
      end

      def respond_to_missing?(method, include_private = false)
        @emitter.respond_to?(method, include_private)
      end
    end

    ##
    # Mapped event emitter
    #
    # Wraps an event emitter with mapping capabilities.
    #
    class MappedEventEmitter
      def initialize(emitter, mapper)
        @emitter = emitter
        @mapper = mapper
      end

      def on(event, &block)
        @emitter.on(event) do |data|
          mapped_data = @mapper.call(data)
          block.call(mapped_data)
        end
      end

      def once(event, &block)
        @emitter.once(event) do |data|
          mapped_data = @mapper.call(data)
          block.call(mapped_data)
        end
      end

      def emit(event, data = {})
        event_data = { event: event, data: data }
        mapped_data = @mapper.call(event_data)
        @emitter.emit(event, mapped_data[:data])
      end

      def method_missing(method, *args, &block)
        @emitter.send(method, *args, &block)
      end

      def respond_to_missing?(method, include_private = false)
        @emitter.respond_to?(method, include_private)
      end
    end
  end
end
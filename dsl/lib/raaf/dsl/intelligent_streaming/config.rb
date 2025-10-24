# frozen_string_literal: true

module RAAF
  module DSL
    module IntelligentStreaming
      # Configuration class for intelligent streaming
      #
      # Stores the configuration for intelligent streaming including stream size,
      # field to stream over, incremental mode, and optional state management blocks.
      #
      # @example Basic streaming configuration
      #   config = Config.new(stream_size: 100, over: :items)
      #
      # @example With state management
      #   config = Config.new(stream_size: 100, over: :items) do
      #     skip_if { |record| record[:processed] }
      #     load_existing { |record| load_from_cache(record) }
      #   end
      class Config
        attr_reader :stream_size, :array_field, :incremental, :blocks

        # Initialize a new Config
        #
        # @param stream_size [Integer] Number of items per stream
        # @param over [Symbol, nil] Field name containing array to stream
        # @param incremental [Boolean] Enable incremental delivery
        # @raise [ArgumentError] if stream_size is not a positive integer
        def initialize(stream_size: nil, over: nil, incremental: false)
          validate_stream_size!(stream_size) if stream_size

          @stream_size = stream_size
          @array_field = over
          @incremental = incremental
          @blocks = {
            skip_if: nil,
            load_existing: nil,
            persist_each_stream: nil,
            on_stream_start: nil,
            on_stream_complete: nil,
            on_stream_error: nil
          }
        end

        # Setter for stream_size (supports block DSL pattern)
        #
        # @param size [Integer] Number of items per stream
        def stream_size(size = nil)
          if size.nil?
            @stream_size
          else
            validate_stream_size!(size)
            @stream_size = size
          end
        end

        # Setter for array_field (supports block DSL pattern)
        #
        # @param field [Symbol, nil] Field name containing array to stream
        def over(field = nil)
          if field.nil?
            @array_field
          else
            @array_field = field
          end
        end

        # Setter for incremental mode (supports block DSL pattern)
        #
        # @param value [Boolean] Enable incremental delivery
        def incremental(value = nil)
          if value.nil?
            @incremental
          else
            @incremental = value
          end
        end

        # Setter for max_retries (supports block DSL pattern)
        #
        # @param count [Integer] Maximum number of retries per stream
        def max_retries(count = nil)
          if count.nil?
            @max_retries ||= 0
          else
            @max_retries = count
          end
        end

        # Setter for allow_partial_results (supports block DSL pattern)
        #
        # @param value [Boolean] Allow partial results on failure
        def allow_partial_results(value = nil)
          if value.nil?
            @allow_partial_results ||= false
          else
            @allow_partial_results = value
          end
        end

        # Setter for stop_on_error (supports block DSL pattern)
        #
        # @param value [Boolean] Stop on first error
        def stop_on_error(value = nil)
          if value.nil?
            @stop_on_error ||= false
          else
            @stop_on_error = value
          end
        end

        # Configure skip_if block
        #
        # @param block [Proc] Block that determines if a record should be skipped
        # @yield [record, context] The record to check and current context
        # @yieldreturn [Boolean] true if record should be skipped
        def skip_if(&block)
          @blocks[:skip_if] = block if block_given?
        end

        # Configure load_existing block
        #
        # @param block [Proc] Block that loads existing result for a record
        # @yield [record, context] The record to load and current context
        # @yieldreturn [Object] The existing result for the record
        def load_existing(&block)
          @blocks[:load_existing] = block if block_given?
        end

        # Configure persist_each_stream block
        #
        # @param block [Proc] Block that persists stream results
        # @yield [stream_results, context] Results from the stream and current context
        def persist_each_stream(&block)
          @blocks[:persist_each_stream] = block if block_given?
        end

        # Configure on_stream_start hook
        #
        # @param block [Proc] Block called before each stream starts
        # @yield [stream_num, total, data] Stream number, total streams, and stream data
        def on_stream_start(&block)
          @blocks[:on_stream_start] = block if block_given?
        end

        # Configure on_stream_complete hook
        #
        # @param block [Proc] Block called after each stream completes
        # @yield Varies based on incremental mode:
        #   - incremental: true -> [stream_num, total, stream_data, stream_results] (4 params)
        #   - incremental: false -> [all_results] (1 param)
        def on_stream_complete(&block)
          if block_given?
            validate_complete_hook_arity!(block)
            @blocks[:on_stream_complete] = block
          end
        end

        # Configure on_stream_error hook
        #
        # @param block [Proc] Block called when a stream encounters an error
        # @yield [stream_num, total, error, context] Stream info, error, and context
        def on_stream_error(&block)
          @blocks[:on_stream_error] = block if block_given?
        end

        # Check if configuration is valid
        #
        # @return [Boolean] true if configuration is valid
        def valid?
          stream_size > 0
        end
        # Get state management configuration
        #
        # @return [Hash] Hash with :skip_if, :load_existing, :persist keys
        def state_management
          {
            skip_if: blocks[:skip_if],
            load_existing: blocks[:load_existing],
            persist: blocks[:persist_each_stream]
          }
        end

        # Convert configuration to hash
        #
        # @return [Hash] Configuration as a hash
        def to_h
          {
            stream_size: stream_size,
            array_field: array_field,
            incremental: incremental,
            has_skip_if: !blocks[:skip_if].nil?,
            has_load_existing: !blocks[:load_existing].nil?,
            has_persist: !blocks[:persist_each_stream].nil?
          }
        end

        private

        def validate_stream_size!(size)
          unless size.is_a?(Integer) && size > 0
            raise ArgumentError, "stream_size must be a positive integer, got: #{size.inspect}"
          end
        end

        def validate_complete_hook_arity!(block)
          arity = block.arity

          if incremental
            # For incremental mode, expect 4 parameters
            if arity != 4 && arity != -1  # -1 allows any number of params
              raise ArgumentError, "on_stream_complete with incremental: true expects 4 parameters (stream_num, total, stream_data, stream_results), got arity: #{arity}"
            end
          else
            # For non-incremental mode, expect 1 parameter
            if arity != 1 && arity != -1  # -1 allows any number of params
              raise ArgumentError, "on_stream_complete with incremental: false expects 1 parameter (all_results), got arity: #{arity}"
            end
          end
        end
      end
    end
  end
end
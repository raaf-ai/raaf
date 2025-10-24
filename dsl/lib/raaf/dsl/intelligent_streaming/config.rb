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
        def initialize(stream_size:, over: nil, incremental: false)
          validate_stream_size!(stream_size)

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
        #   - incremental: true -> [stream_num, total, stream_data, stream_results] (3 params)
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
            # For incremental mode, expect 3 parameters
            if arity != 3 && arity != -1  # -1 allows any number of params
              raise ArgumentError, "on_stream_complete with incremental: true expects 3 parameters (stream_num, total, stream_results), got arity: #{arity}"
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
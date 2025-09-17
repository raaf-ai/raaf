# frozen_string_literal: true

module RAAF
  module DSL
    module Schema
      # Thread-safe caching system for generated schemas with intelligent invalidation
      #
      # This class provides high-performance caching of generated schemas with
      # automatic invalidation based on model file timestamps in development
      # and application boot time in production. The cache is thread-safe and
      # includes comprehensive statistics tracking.
      #
      # @example Basic usage
      #   schema = RAAF::DSL::Schema::SchemaCache.get_schema(Market)
      #   # First call generates and caches, subsequent calls return cached version
      #
      # @example Cache management
      #   RAAF::DSL::Schema::SchemaCache.clear_cache!  # Clear all cached schemas
      #   stats = RAAF::DSL::Schema::SchemaCache.cache_statistics  # Get cache stats
      #
      class SchemaCache
        # Cache storage and metadata
        @cache = {}
        @cache_timestamps = {}
        @cache_statistics = {
          hits: 0,
          misses: 0,
          errors: 0
        }
        @mutex = Mutex.new

        class << self
          # Retrieves a schema from cache or generates it if not cached/stale
          #
          # @param model_class [Class] The Active Record model class
          # @return [Hash] JSON schema hash
          # @raise [ArgumentError] If model_class is nil
          #
          def get_schema(model_class)
            raise ArgumentError, "Model class cannot be nil" if model_class.nil?

            cache_key = model_class.name

            @mutex.synchronize do
              begin
                model_timestamp = get_model_timestamp(model_class)

                # Check if cache is valid
                if cache_valid?(cache_key, model_timestamp)
                  @cache_statistics[:hits] += 1
                  return @cache[cache_key]
                end

                # Cache miss - generate new schema
                @cache_statistics[:misses] += 1
                schema = SchemaGenerator.generate_for_model(model_class)

                # Store in cache with current timestamp
                @cache[cache_key] = schema
                @cache_timestamps[cache_key] = Time.current

                schema
              rescue StandardError => e
                @cache_statistics[:errors] += 1
                raise e
              end
            end
          end

          # Clears all cached schemas and resets statistics
          #
          # @return [void]
          #
          def clear_cache!
            @mutex.synchronize do
              @cache.clear
              @cache_timestamps.clear
              @cache_statistics[:hits] = 0
              @cache_statistics[:misses] = 0
              @cache_statistics[:errors] = 0
            end
          end

          # Returns comprehensive cache statistics
          #
          # @return [Hash] Statistics including hits, misses, hit rate, and memory usage
          #
          def cache_statistics
            @mutex.synchronize do
              total_requests = @cache_statistics[:hits] + @cache_statistics[:misses]
              hit_rate = total_requests > 0 ? @cache_statistics[:hits].to_f / total_requests : 0.0

              {
                hits: @cache_statistics[:hits],
                misses: @cache_statistics[:misses],
                errors: @cache_statistics[:errors],
                hit_rate: hit_rate,
                cached_models: @cache.size,
                estimated_memory_kb: estimate_memory_usage
              }
            end
          end

          private

          # Checks if cached schema is still valid based on timestamps
          #
          # @param cache_key [String] Model class name
          # @param model_timestamp [Time] Current model timestamp
          # @return [Boolean] True if cache is valid
          #
          def cache_valid?(cache_key, model_timestamp)
            return false unless @cache.key?(cache_key)
            return false unless @cache_timestamps.key?(cache_key)

            cached_timestamp = @cache_timestamps[cache_key]
            cached_timestamp >= model_timestamp
          end

          # Gets the timestamp to use for cache invalidation
          #
          # @param model_class [Class] The Active Record model class
          # @return [Time] Timestamp for cache validation
          #
          def get_model_timestamp(model_class)
            if Rails.env.development?
              # In development, check model file modification time
              get_development_timestamp(model_class)
            else
              # In production, use application boot time
              get_production_timestamp
            end
          end

          # Gets model file timestamp for development environment
          #
          # @param model_class [Class] The Active Record model class
          # @return [Time] File modification time
          #
          def get_development_timestamp(model_class)
            model_file = model_class_file(model_class)
            File.mtime(model_file)
          rescue StandardError => e
            # If we can't get file timestamp, always regenerate
            Rails.logger.debug "Could not get file timestamp for #{model_class.name}: #{e.message}"
            Time.current
          end

          # Gets application boot timestamp for production environment
          #
          # @return [Time] Application boot time
          #
          def get_production_timestamp
            # Try to get Rails boot timestamp, fallback to epoch time for caching
            Rails.application.config.respond_to?(:cache_classes_timestamp) ?
              Rails.application.config.cache_classes_timestamp :
              Time.at(0)
          end

          # Resolves the file path for a model class
          #
          # @param model_class [Class] The Active Record model class
          # @return [String] File path to the model
          #
          def model_class_file(model_class)
            # Try to find the file using Rails conventions
            model_name = model_class.name.underscore

            # Check common locations
            possible_paths = [
              Rails.root.join("app/models/#{model_name}.rb"),
              Rails.root.join("app/models/#{model_name.gsub('::', '/')}.rb")
            ]

            possible_paths.each do |path|
              return path.to_s if File.exist?(path)
            end

            # Fallback: try to use the source location from the class
            if model_class.respond_to?(:source_location) && model_class.source_location
              return model_class.source_location.first
            end

            # Last resort: create a dummy path that will always be "stale"
            "/tmp/unknown_model_#{model_class.name.underscore}.rb"
          end

          # Estimates memory usage of cached schemas
          #
          # @return [Integer] Estimated memory usage in KB
          #
          def estimate_memory_usage
            # Rough estimation: each schema averages about 2KB when marshaled
            # This is a conservative estimate for monitoring purposes
            base_overhead = 1 # 1KB base overhead
            per_schema_estimate = 2 # 2KB per schema

            base_overhead + (@cache.size * per_schema_estimate)
          end
        end
      end
    end
  end
end
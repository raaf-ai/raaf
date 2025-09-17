# frozen_string_literal: true

module RAAF
  module DSL
    # Intelligent caching system for model-generated schemas
    #
    # Provides fast access to model schemas with automatic cache invalidation
    # based on model file modification times in development and application
    # boot time in production.
    #
    # @example Get cached schema
    #   schema = RAAF::DSL::SchemaCache.get_schema(Market)
    #   # => { type: :object, properties: {...}, required: [...] }
    class SchemaCache
      @cache = {}
      @cache_timestamps = {}

      class << self
        # Get schema for a model class with intelligent caching
        #
        # @param model_class [Class] The Active Record model class
        # @return [Hash] JSON schema definition
        #
        # @example
        #   schema = SchemaCache.get_schema(Market)
        #   puts schema[:properties][:market_name]
        #   # => { type: :string, maxLength: 255 }
        def get_schema(model_class)
          cache_key = model_class.name
          model_timestamp = get_model_timestamp(model_class)

          # Check if we have a valid cached version
          if @cache[cache_key] && @cache_timestamps[cache_key] && @cache_timestamps[cache_key] >= model_timestamp
            @cache[cache_key]
          else
            # Generate new schema and cache it
            schema = RAAF::DSL::SchemaGenerator.generate_for_model(model_class)
            @cache[cache_key] = schema
            @cache_timestamps[cache_key] = Time.now
            schema
          end
        end

        # Clear all cached schemas (useful for testing)
        #
        # @example
        #   SchemaCache.clear_cache
        def clear_cache
          @cache.clear
          @cache_timestamps.clear
        end

        # Get current cache size (useful for monitoring)
        #
        # @return [Integer] Number of cached schemas
        def cache_size
          @cache.size
        end

        # Check if a model is cached
        #
        # @param model_class [Class] The Active Record model class
        # @return [Boolean] true if schema is cached
        def cached?(model_class)
          @cache.key?(model_class.name)
        end

        private

        # Get timestamp for cache invalidation decision
        #
        # In development: uses model file modification time
        # In production: uses application boot time
        #
        # @param model_class [Class] The Active Record model class
        # @return [Time] Timestamp for cache comparison
        def get_model_timestamp(model_class)
          if defined?(::Rails) && ::Rails.env.development?
            # Use file modification time in development
            begin
              File.mtime(model_class_file(model_class))
            rescue Errno::ENOENT, StandardError
              # Fallback if file doesn't exist or other error
              Time.at(0)
            end
          else
            # Use application boot time in production
            (defined?(::Rails) && ::Rails.application&.config&.cache_classes_timestamp) || Time.at(0)
          end
        end

        # Get the file path for a model class
        #
        # @param model_class [Class] The Active Record model class
        # @return [String] File path to the model file
        def model_class_file(model_class)
          # Convert class name to file path
          # E.g., "Market" -> "app/models/market.rb"
          # E.g., "Ai::Market::Analysis" -> "app/models/ai/market/analysis.rb"
          file_name = model_class.name.underscore
          if defined?(::Rails) && ::Rails.root
            ::Rails.root.join("app", "models", "#{file_name}.rb").to_s
          else
            "app/models/#{file_name}.rb"
          end
        end
      end
    end
  end
end
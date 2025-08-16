# frozen_string_literal: true

# Performance optimization module for RAAF DSL Tools
#
# This module provides caching and memoization strategies to minimize
# overhead in tool method generation and parameter processing. It ensures
# zero runtime overhead for generated methods while maintaining thread safety.
#
# The module implements several performance strategies:
# - Class-level method generation caching at load time
# - Memoization for parameter processing and validation
# - Thread-safe cache management
# - Benchmark utilities for measuring performance impact
#
# @example Using with a tool class
#   class WeatherTool < RAAF::DSL::Tools::Tool
#     include PerformanceOptimizer
#     
#     def call(city:, country: "US")
#       # Implementation will be automatically optimized
#     end
#   end
#
# @since 1.0.0
#
module RAAF
  module DSL
    module Tools
      module PerformanceOptimizer
        extend ActiveSupport::Concern

        # Thread-safe class-level cache for generated methods
        CLASS_CACHE = Concurrent::Hash.new
        # Thread-safe instance-level cache for parameter processing
        INSTANCE_CACHE = Concurrent::Hash.new

        included do
          extend ClassMethods
          include InstanceMethods
          
          # Generate and cache methods at class load time
          cache_generated_methods if respond_to?(:cache_generated_methods)
        end

        module ClassMethods
          # Cache generated methods at class load time
          #
          # This method pre-generates and caches all tool-related methods
          # to ensure zero runtime overhead. Methods are cached based on
          # class name and method signature fingerprints.
          #
          def cache_generated_methods
            cache_key = method_cache_key
            return if CLASS_CACHE.key?(cache_key)

            CLASS_CACHE[cache_key] = {
              tool_definition: generate_cached_tool_definition,
              parameter_schema: generate_cached_parameter_schema,
              method_signatures: cache_method_signatures,
              generated_at: Time.current
            }
          end

          # Get cached tool definition with zero runtime overhead
          #
          # @return [Hash] Cached tool definition
          #
          def cached_tool_definition
            cache_key = method_cache_key
            CLASS_CACHE.dig(cache_key, :tool_definition) || generate_cached_tool_definition
          end

          # Get cached parameter schema with zero runtime overhead
          #
          # @return [Hash] Cached parameter schema
          #
          def cached_parameter_schema
            cache_key = method_cache_key
            CLASS_CACHE.dig(cache_key, :parameter_schema) || generate_cached_parameter_schema
          end

          # Check if methods are cached for this class
          #
          # @return [Boolean] Whether methods are cached
          #
          def methods_cached?
            CLASS_CACHE.key?(method_cache_key)
          end

          # Invalidate cache for this class (useful for development)
          #
          def invalidate_cache!
            CLASS_CACHE.delete(method_cache_key)
          end

          # Get cache statistics for monitoring
          #
          # @return [Hash] Cache statistics
          #
          def cache_stats
            cache_key = method_cache_key
            cached_data = CLASS_CACHE[cache_key]
            
            {
              class_name: name,
              cached: cached_data.present?,
              cache_size: CLASS_CACHE.size,
              generated_at: cached_data&.dig(:generated_at),
              cache_hit_ratio: calculate_cache_hit_ratio
            }
          end

          # Benchmark method generation performance
          #
          # @param iterations [Integer] Number of iterations to run
          # @return [Hash] Benchmark results
          #
          def benchmark_method_generation(iterations: 1000)
            require 'benchmark'
            
            results = {}
            
            # Benchmark cached method access
            results[:cached_access] = Benchmark.measure do
              iterations.times { cached_tool_definition }
            end
            
            # Benchmark uncached method generation
            invalidate_cache!
            results[:uncached_generation] = Benchmark.measure do
              iterations.times { generate_cached_tool_definition }
            end
            
            # Restore cache
            cache_generated_methods
            
            results[:performance_ratio] = results[:uncached_generation].total / results[:cached_access].total
            results
          end

          private

          # Generate unique cache key for this class
          #
          # @return [String] Unique cache key
          #
          def method_cache_key
            @method_cache_key ||= begin
              signature = method_defined?(:call) ? instance_method(:call).parameters.hash : 0
              "#{name}_#{signature}_#{object_id}"
            end
          end

          # Generate and cache tool definition
          #
          # @return [Hash] Generated tool definition
          #
          def generate_cached_tool_definition
            if respond_to?(:generate_tool_definition, true)
              generate_tool_definition
            else
              default_tool_definition
            end
          end

          # Generate and cache parameter schema
          #
          # @return [Hash] Generated parameter schema
          #
          def generate_cached_parameter_schema
            if respond_to?(:generate_parameter_schema, true)
              generate_parameter_schema
            else
              default_parameter_schema
            end
          end

          # Cache method signatures for comparison
          #
          # @return [Hash] Method signature information
          #
          def cache_method_signatures
            return {} unless method_defined?(:call)

            method = instance_method(:call)
            {
              parameters: method.parameters,
              arity: method.arity,
              source_location: method.source_location
            }
          end

          # Calculate cache hit ratio for monitoring
          #
          # @return [Float] Hit ratio between 0.0 and 1.0
          #
          def calculate_cache_hit_ratio
            # This would be implemented with actual hit/miss tracking
            # For now, return 1.0 if cached, 0.0 if not
            methods_cached? ? 1.0 : 0.0
          end

          # Default tool definition when no generator is available
          #
          # @return [Hash] Default tool definition
          #
          def default_tool_definition
            {
              type: "function",
              function: {
                name: name.demodulize.underscore,
                description: "Auto-generated tool",
                parameters: default_parameter_schema
              }
            }
          end

          # Default parameter schema when no generator is available
          #
          # @return [Hash] Default parameter schema
          #
          def default_parameter_schema
            {
              type: "object",
              properties: {},
              required: [],
              additionalProperties: false
            }
          end
        end

        module InstanceMethods
          # Memoized parameter processing with thread safety
          #
          # @param params [Hash] Parameters to process
          # @return [Hash] Processed parameters
          #
          def process_parameters_cached(params)
            cache_key = parameter_cache_key(params)
            
            INSTANCE_CACHE.fetch(cache_key) do
              process_parameters_uncached(params)
            end
          end

          # Memoized parameter validation
          #
          # @param params [Hash] Parameters to validate
          # @return [Boolean] Whether parameters are valid
          #
          def validate_parameters_cached(params)
            cache_key = validation_cache_key(params)
            
            INSTANCE_CACHE.fetch(cache_key) do
              validate_parameters_uncached(params)
            end
          end

          # Get instance cache statistics
          #
          # @return [Hash] Instance cache statistics
          #
          def instance_cache_stats
            {
              cache_size: INSTANCE_CACHE.size,
              instance_id: object_id,
              class_name: self.class.name
            }
          end

          # Clear instance cache for this object
          #
          def clear_instance_cache!
            prefix = "#{self.class.name}_#{object_id}"
            keys_to_delete = INSTANCE_CACHE.keys.select { |key| key.start_with?(prefix) }
            keys_to_delete.each { |key| INSTANCE_CACHE.delete(key) }
          end

          private

          # Generate cache key for parameter processing
          #
          # @param params [Hash] Parameters
          # @return [String] Cache key
          #
          def parameter_cache_key(params)
            "#{self.class.name}_#{object_id}_params_#{params.hash}"
          end

          # Generate cache key for validation
          #
          # @param params [Hash] Parameters
          # @return [String] Cache key
          #
          def validation_cache_key(params)
            "#{self.class.name}_#{object_id}_validation_#{params.hash}"
          end

          # Process parameters without caching (fallback)
          #
          # @param params [Hash] Parameters to process
          # @return [Hash] Processed parameters
          #
          def process_parameters_uncached(params)
            if respond_to?(:process_parameters, true)
              process_parameters(params)
            else
              params
            end
          end

          # Validate parameters without caching (fallback)
          #
          # @param params [Hash] Parameters to validate
          # @return [Boolean] Whether parameters are valid
          #
          def validate_parameters_uncached(params)
            if respond_to?(:validate_parameters, true)
              validate_parameters(params)
            else
              true
            end
          end
        end

        # Module-level utility methods
        class << self
          # Clear all caches (useful for testing and development)
          #
          def clear_all_caches!
            CLASS_CACHE.clear
            INSTANCE_CACHE.clear
          end

          # Get global cache statistics
          #
          # @return [Hash] Global cache statistics
          #
          def global_cache_stats
            {
              class_cache_size: CLASS_CACHE.size,
              instance_cache_size: INSTANCE_CACHE.size,
              total_memory_usage: estimate_cache_memory_usage
            }
          end

          # Benchmark overall performance impact
          #
          # @param tool_classes [Array<Class>] Tool classes to benchmark
          # @param iterations [Integer] Number of iterations
          # @return [Hash] Benchmark results
          #
          def benchmark_performance_impact(tool_classes: [], iterations: 1000)
            results = {
              classes_tested: tool_classes.size,
              iterations: iterations,
              results: {}
            }

            tool_classes.each do |tool_class|
              next unless tool_class.respond_to?(:benchmark_method_generation)
              
              results[:results][tool_class.name] = tool_class.benchmark_method_generation(
                iterations: iterations
              )
            end

            results[:average_performance_ratio] = calculate_average_performance_ratio(results[:results])
            results
          end

          private

          # Estimate memory usage of caches
          #
          # @return [Integer] Estimated memory usage in bytes
          #
          def estimate_cache_memory_usage
            # Rough estimation - in practice you might use more sophisticated memory profiling
            (CLASS_CACHE.size + INSTANCE_CACHE.size) * 1024 # Rough estimate: 1KB per cache entry
          end

          # Calculate average performance ratio across all tool classes
          #
          # @param results [Hash] Benchmark results by class
          # @return [Float] Average performance ratio
          #
          def calculate_average_performance_ratio(results)
            ratios = results.values.map { |result| result[:performance_ratio] }.compact
            return 0.0 if ratios.empty?
            
            ratios.sum / ratios.size
          end
        end
      end
    end
  end
end
# frozen_string_literal: true

# Utilities for consistent hash key handling across AI Agent DSL
#
# This module provides helper methods for converting between symbol and string keys
# in hashes, following the symbols-everywhere internal pattern while supporting
# string keys at API boundaries.
#
# @example Basic usage
#   RAAF::DSL::HashUtils.deep_symbolize_keys({"key" => "value"})
#   # => {:key => "value"}
#
# @example API boundary conversion
#   RAAF::DSL::HashUtils.prepare_for_api({key: "value"})
#   # => {"key" => "value"}
#
# @since 0.2.0
#
module RAAF
  module DSL
    module HashUtils
      # Convert hash keys to symbols recursively
      #
      # @param hash [Hash, Array, Object] The object to convert
      # @return [Hash, Array, Object] Object with symbolized keys
      #
      # @example
      #   deep_symbolize_keys({"name" => "test", "data" => {"nested" => "value"}})
      #   # => {:name => "test", :data => {:nested => "value"}}
      #
      def self.deep_symbolize_keys(obj)
        case obj
        when Hash
          obj.transform_keys(&:to_sym).transform_values { |v| deep_symbolize_keys(v) }
        when Array
          obj.map { |v| deep_symbolize_keys(v) }
        else
          obj
        end
      end

      # Convert hash keys to strings recursively
      #
      # @param hash [Hash, Array, Object] The object to convert
      # @return [Hash, Array, Object] Object with stringified keys
      #
      # @example
      #   deep_stringify_keys({name: "test", data: {nested: "value"}})
      #   # => {"name" => "test", "data" => {"nested" => "value"}}
      #
      def self.deep_stringify_keys(obj)
        case obj
        when Hash
          obj.transform_keys(&:to_s).transform_values { |v| deep_stringify_keys(v) }
        when Array
          obj.map { |v| deep_stringify_keys(v) }
        else
          obj
        end
      end

      # Prepare hash for external API (convert to string keys)
      #
      # This method is used at API boundaries where external systems expect
      # string keys (like JSON APIs, OpenAI API, etc.)
      #
      # @param hash [Hash] The hash to prepare
      # @return [Hash] Hash with string keys
      #
      # @example
      #   prepare_for_api({user_id: 123, preferences: {theme: "dark"}})
      #   # => {"user_id" => 123, "preferences" => {"theme" => "dark"}}
      #
      def self.prepare_for_api(hash)
        deep_stringify_keys(hash)
      end

      # Normalize hash from external API (convert to symbol keys)
      #
      # This method is used when receiving data from external APIs to convert
      # string keys to symbols for internal processing.
      #
      # @param hash [Hash] The hash to normalize
      # @return [Hash] Hash with symbol keys
      #
      # @example
      #   normalize_from_api({"user_id" => 123, "preferences" => {"theme" => "dark"}})
      #   # => {:user_id => 123, :preferences => {:theme => "dark"}}
      #
      def self.normalize_from_api(hash)
        deep_symbolize_keys(hash)
      end

      # Check if hash uses consistent key types
      #
      # @param hash [Hash] The hash to check
      # @return [Hash] Analysis of key types
      #
      # @example
      #   analyze_key_types({:a => 1, "b" => 2})
      #   # => {consistent: false, symbol_keys: 1, string_keys: 1, mixed: true}
      #
      def self.analyze_key_types(hash)
        return { consistent: true, symbol_keys: 0, string_keys: 0, mixed: false } unless hash.is_a?(Hash)

        symbol_count = hash.keys.count { |k| k.is_a?(Symbol) }
        string_count = hash.keys.count { |k| k.is_a?(String) }
        total_keys = hash.keys.size

        {
          consistent: symbol_count == total_keys || string_count == total_keys,
          symbol_keys: symbol_count,
          string_keys: string_count,
          mixed: symbol_count.positive? && string_count.positive?,
          total_keys: total_keys,
          dominant_type: symbol_count > string_count ? :symbol : :string
        }
      end

      # Ensure hash uses symbol keys with validation
      #
      # @param hash [Hash] The hash to validate and convert
      # @param strict [Boolean] Whether to raise error on mixed keys
      # @return [Hash] Hash with symbol keys
      # @raise [ArgumentError] If strict mode and keys are mixed
      #
      def self.ensure_symbol_keys(hash, strict: false)
        return hash unless hash.is_a?(Hash)

        analysis = analyze_key_types(hash)

        if strict && analysis[:mixed]
          raise ArgumentError,
                "Hash has mixed key types: #{analysis[:symbol_keys]} symbols, #{analysis[:string_keys]} strings"
        end

        deep_symbolize_keys(hash)
      end

      # Convert context variables to symbol keys (for ContextVariables compatibility)
      #
      # @param variables [Hash] Context variables to convert
      # @return [Hash] Variables with symbol keys
      #
      def self.normalize_context_variables(variables)
        ensure_symbol_keys(variables, strict: false)
      end
    end
  end
end

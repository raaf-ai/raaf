# frozen_string_literal: true

module OpenAIAgents
  # Utilities for consistent hash key handling in OpenAI Agents
  #
  # This module provides helper methods for converting between symbol and string keys
  # in hashes, supporting the symbols-everywhere internal pattern while ensuring
  # string keys at OpenAI API boundaries.
  #
  # @example API boundary conversion
  #   OpenAIAgents::HashUtils.prepare_for_openai({key: "value"})
  #   # => {"key" => "value"}
  #
  # @example Response normalization
  #   OpenAIAgents::HashUtils.normalize_response({"key" => "value"})
  #   # => {:key => "value"}
  #
  module HashUtils
    module_function

    # Convert hash keys to symbols recursively
    #
    # @param obj [Hash, Array, Object] The object to convert
    # @return [Hash, Array, Object] Object with symbolized keys
    def deep_symbolize_keys(obj)
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
    # @param obj [Hash, Array, Object] The object to convert
    # @return [Hash, Array, Object] Object with stringified keys
    def deep_stringify_keys(obj)
      case obj
      when Hash
        obj.transform_keys(&:to_s).transform_values { |v| deep_stringify_keys(v) }
      when Array
        obj.map { |v| deep_stringify_keys(v) }
      else
        obj
      end
    end

    # Prepare hash for OpenAI API (convert to string keys)
    #
    # OpenAI API expects string keys in requests, so this method ensures
    # all internal symbol keys are converted to strings at the API boundary.
    #
    # @param hash [Hash] The hash to prepare for API
    # @return [Hash] Hash with string keys ready for OpenAI API
    def prepare_for_openai(hash)
      deep_stringify_keys(hash)
    end

    # Normalize OpenAI API response (convert to symbol keys)
    #
    # Converts OpenAI API responses from string keys to symbol keys for
    # internal Ruby processing following the symbols-everywhere pattern.
    #
    # @param response [Hash] The API response to normalize
    # @return [Hash] Response with symbol keys for internal use
    def normalize_response(response)
      deep_symbolize_keys(response)
    end

    # Prepare schema for OpenAI strict mode (ensure string keys)
    #
    # @param schema [Hash] The schema to prepare
    # @return [Hash] Schema with string keys for OpenAI API
    def prepare_schema_for_openai(schema)
      StrictSchema.ensure_strict_json_schema(schema)
    end
  end
end

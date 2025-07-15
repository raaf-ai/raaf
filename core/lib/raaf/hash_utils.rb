# frozen_string_literal: true

module RubyAIAgentsFactory
  ##
  # HashUtils - Utilities for consistent hash key handling in OpenAI Agents
  #
  # This module provides helper methods for converting between symbol and string keys
  # in hashes, supporting the symbols-everywhere internal pattern while ensuring
  # string keys at OpenAI API boundaries. The gem follows Ruby conventions of using
  # symbols internally while respecting API requirements for string keys.
  #
  # == Key Conversion Strategy
  #
  # The OpenAI Agents Ruby gem uses a dual-key strategy:
  # - **Internal Processing**: Symbol keys for Ruby idiomatic code and performance
  # - **API Boundaries**: String keys as required by OpenAI API specifications
  # - **User Input**: Flexible acceptance of both symbol and string keys
  #
  # == Performance Considerations
  #
  # This module uses recursive transformation which creates new objects. For
  # large nested structures, consider using streaming or chunked processing
  # when performance is critical.
  #
  # @example API boundary conversion
  #   RubyAIAgentsFactory::HashUtils.prepare_for_openai({key: "value", nested: {inner: 123}})
  #   # => {"key" => "value", "nested" => {"inner" => 123}}
  #
  # @example Response normalization  
  #   api_response = {"message" => {"role" => "assistant", "content" => "Hello"}}
  #   RubyAIAgentsFactory::HashUtils.normalize_response(api_response)
  #   # => {:message => {:role => "assistant", :content => "Hello"}}
  #
  # @example Complex nested structures
  #   data = {
  #     messages: [
  #       {role: :user, content: "Hi"},
  #       {role: :assistant, content: "Hello", metadata: {tokens: 15}}
  #     ]
  #   }
  #   RubyAIAgentsFactory::HashUtils.prepare_for_openai(data)
  #   # => {"messages" => [{"role" => "user", "content" => "Hi"}, ...]}
  #
  # @example Schema preparation for strict mode
  #   schema = {type: "object", properties: {name: {type: "string"}}}
  #   RubyAIAgentsFactory::HashUtils.prepare_schema_for_openai(schema)
  #   # => {"type" => "object", "properties" => {"name" => {"type" => "string"}}}
  #
  # @author OpenAI Agents Ruby Team
  # @since 0.1.0
  # @see RubyAIAgentsFactory::StrictSchema For schema validation utilities
  module HashUtils
    module_function

    ##
    # Convert hash keys to symbols recursively
    #
    # Transforms all string keys to symbol keys throughout a nested data structure.
    # Arrays are processed recursively, and non-hash/array objects are returned unchanged.
    # This method creates new objects rather than modifying in place.
    #
    # @param obj [Hash, Array, Object] The object to convert
    # @return [Hash, Array, Object] Object with symbolized keys
    #
    # @example Basic hash conversion
    #   HashUtils.deep_symbolize_keys({"name" => "John", "age" => 30})
    #   # => {:name => "John", :age => 30}
    #
    # @example Nested structures
    #   data = {"user" => {"profile" => {"name" => "John"}}}
    #   HashUtils.deep_symbolize_keys(data)
    #   # => {:user => {:profile => {:name => "John"}}}
    #
    # @example Arrays with hashes
    #   HashUtils.deep_symbolize_keys([{"id" => 1}, {"id" => 2}])
    #   # => [{:id => 1}, {:id => 2}]
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

    ##
    # Convert hash keys to strings recursively
    #
    # Transforms all symbol keys to string keys throughout a nested data structure.
    # Arrays are processed recursively, and non-hash/array objects are returned unchanged.
    # This method creates new objects rather than modifying in place.
    #
    # @param obj [Hash, Array, Object] The object to convert
    # @return [Hash, Array, Object] Object with stringified keys
    #
    # @example Basic hash conversion
    #   HashUtils.deep_stringify_keys({name: "John", age: 30})
    #   # => {"name" => "John", "age" => 30}
    #
    # @example Nested structures
    #   data = {user: {profile: {name: "John"}}}
    #   HashUtils.deep_stringify_keys(data)
    #   # => {"user" => {"profile" => {"name" => "John"}}}
    #
    # @example Mixed key types
    #   data = {:symbols => "value", "strings" => {nested: :symbol}}
    #   HashUtils.deep_stringify_keys(data)
    #   # => {"symbols" => "value", "strings" => {"nested" => "symbol"}}
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

    ##
    # Prepare hash for OpenAI API (convert to string keys)
    #
    # OpenAI API expects string keys in requests, so this method ensures
    # all internal symbol keys are converted to strings at the API boundary.
    # This is the primary method for preparing Ruby hashes for OpenAI API calls.
    #
    # @param hash [Hash] The hash to prepare for API
    # @return [Hash] Hash with string keys ready for OpenAI API
    #
    # @example Prepare agent request
    #   request = {model: "gpt-4", messages: [{role: :user, content: "Hello"}]}
    #   HashUtils.prepare_for_openai(request)
    #   # => {"model" => "gpt-4", "messages" => [{"role" => "user", "content" => "Hello"}]}
    #
    # @example Prepare function parameters
    #   params = {name: "weather", parameters: {location: {type: :string}}}
    #   HashUtils.prepare_for_openai(params)
    #   # => {"name" => "weather", "parameters" => {"location" => {"type" => "string"}}}
    def prepare_for_openai(hash)
      deep_stringify_keys(hash)
    end

    ##
    # Normalize OpenAI API response (convert to symbol keys)
    #
    # Converts OpenAI API responses from string keys to symbol keys for
    # internal Ruby processing following the symbols-everywhere pattern.
    # This is the primary method for processing OpenAI API responses.
    #
    # @param response [Hash] The API response to normalize
    # @return [Hash] Response with symbol keys for internal use
    #
    # @example Normalize completion response
    #   api_response = {
    #     "id" => "chatcmpl-123",
    #     "choices" => [{"message" => {"role" => "assistant", "content" => "Hello"}}]
    #   }
    #   HashUtils.normalize_response(api_response)
    #   # => {:id => "chatcmpl-123", :choices => [{:message => {:role => "assistant", :content => "Hello"}}]}
    #
    # @example Normalize usage data
    #   usage = {"prompt_tokens" => 15, "completion_tokens" => 10, "total_tokens" => 25}
    #   HashUtils.normalize_response(usage)
    #   # => {:prompt_tokens => 15, :completion_tokens => 10, :total_tokens => 25}
    def normalize_response(response)
      deep_symbolize_keys(response)
    end

    ##
    # Prepare schema for OpenAI strict mode (ensure string keys)
    #
    # Prepares JSON schema for OpenAI API strict mode by ensuring all keys are strings
    # and the schema follows OpenAI's strict JSON schema requirements. This method
    # combines key conversion with schema validation.
    #
    # @param schema [Hash] The schema to prepare
    # @return [Hash] Schema with string keys and strict validation for OpenAI API
    #
    # @example Prepare function schema
    #   schema = {
    #     type: :object,
    #     properties: {
    #       name: {type: :string, description: "User name"},
    #       age: {type: :integer, minimum: 0}
    #     },
    #     required: [:name]
    #   }
    #   HashUtils.prepare_schema_for_openai(schema)
    #   # => {"type" => "object", "properties" => {...}, "required" => ["name"]}
    #
    # @see RubyAIAgentsFactory::StrictSchema.ensure_strict_json_schema For schema validation details
    def prepare_schema_for_openai(schema)
      StrictSchema.ensure_strict_json_schema(schema)
    end
  end
end

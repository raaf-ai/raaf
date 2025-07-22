# frozen_string_literal: true

module RAAF

  ##
  # Utils - General utilities for RAAF
  #
  # This module provides helper methods for common operations in RAAF including:
  # - Hash key conversion (symbol/string keys)
  # - String case conversion (snake_case)
  # - OpenAI API preparation utilities
  #
  # The gem follows Ruby conventions of using symbols internally while respecting
  # API requirements for string keys.
  #
  # == Key Conversion Strategy
  #
  # The RAAF (Ruby AI Agents Factory) gem uses a dual-key strategy:
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
  #   RAAF::Utils.prepare_for_openai({key: "value", nested: {inner: 123}})
  #   # => {"key" => "value", "nested" => {"inner" => 123}}
  #
  # @example Response normalization
  #   api_response = {"message" => {"role" => "assistant", "content" => "Hello"}}
  #   RAAF::Utils.normalize_response(api_response)
  #   # => {:message => {:role => "assistant", :content => "Hello"}}
  #
  # @example String case conversion
  #   RAAF::Utils.snake_case("CompanyDiscoveryAgent")
  #   # => "company_discovery_agent"
  #
  # @example Complex nested structures
  #   data = {
  #     messages: [
  #       {role: :user, content: "Hi"},
  #       {role: :assistant, content: "Hello", metadata: {tokens: 15}}
  #     ]
  #   }
  #   RAAF::Utils.prepare_for_openai(data)
  #   # => {"messages" => [{"role" => "user", "content" => "Hi"}, ...]}
  #
  # @example Schema preparation for strict mode
  #   schema = {type: "object", properties: {name: {type: "string"}}}
  #   RAAF::Utils.prepare_schema_for_openai(schema)
  #   # => {"type" => "object", "properties" => {"name" => {"type" => "string"}}}
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  # @see RAAF::StrictSchema For schema validation utilities
  module Utils

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
    #   Utils.deep_symbolize_keys({"name" => "John", "age" => 30})
    #   # => {:name => "John", :age => 30}
    #
    # @example Nested structures
    #   data = {"user" => {"profile" => {"name" => "John"}}}
    #   Utils.deep_symbolize_keys(data)
    #   # => {:user => {:profile => {:name => "John"}}}
    #
    # @example Arrays with hashes
    #   Utils.deep_symbolize_keys([{"id" => 1}, {"id" => 2}])
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
    #   Utils.deep_stringify_keys({name: "John", age: 30})
    #   # => {"name" => "John", "age" => 30}
    #
    # @example Nested structures
    #   data = {user: {profile: {name: "John"}}}
    #   Utils.deep_stringify_keys(data)
    #   # => {"user" => {"profile" => {"name" => "John"}}}
    #
    # @example Mixed key types
    #   data = {:symbols => "value", "strings" => {nested: :symbol}}
    #   Utils.deep_stringify_keys(data)
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
    #   Utils.prepare_for_openai(request)
    #   # => {"model" => "gpt-4", "messages" => [{"role" => "user", "content" => "Hello"}]}
    #
    # @example Prepare function parameters
    #   params = {name: "weather", parameters: {location: {type: :string}}}
    #   Utils.prepare_for_openai(params)
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
    #   Utils.normalize_response(api_response)
    #   # => {:id => "chatcmpl-123", :choices => [{:message => {:role => "assistant", :content => "Hello"}}]}
    #
    # @example Normalize usage data
    #   usage = {"prompt_tokens" => 15, "completion_tokens" => 10, "total_tokens" => 25}
    #   Utils.normalize_response(usage)
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
    #   Utils.prepare_schema_for_openai(schema)
    #   # => {"type" => "object", "properties" => {...}, "required" => ["name"]}
    #
    # @see RAAF::StrictSchema.ensure_strict_json_schema For schema validation details
    def prepare_schema_for_openai(schema)
      StrictSchema.ensure_strict_json_schema(schema)
    end

    ##
    # Convert string to snake_case
    #
    # Converts CamelCase, PascalCase, and mixed strings to snake_case following Ruby conventions.
    # Handles acronyms, multiple words, and special characters properly.
    #
    # @param str [String] The string to convert
    # @return [String] snake_case version of the input
    #
    # @example Basic conversion
    #   Utils.snake_case("CompanyDiscoveryAgent")
    #   # => "company_discovery_agent"
    #
    # @example Acronym handling
    #   Utils.snake_case("XMLParserAgent")
    #   # => "xml_parser_agent"
    #
    # @example Multiple words
    #   Utils.snake_case("Customer Service Agent")
    #   # => "customer_service_agent"
    #
    # @example Already snake_case
    #   Utils.snake_case("already_snake_case")
    #   # => "already_snake_case"
    def snake_case(str)
      str.to_s
         .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')  # Handle acronyms like "XMLParser" -> "XML_Parser"
         .gsub(/([a-z\d])([A-Z])/, '\1_\2')      # Handle camelCase like "companyDiscovery" -> "company_Discovery"
         .downcase                               # Convert to lowercase
         .gsub(/[^a-z0-9]+/, "_")               # Replace non-alphanumeric with underscores
         .gsub(/^_+|_+$/, "")                   # Remove leading/trailing underscores
         .gsub(/_+/, "_")                       # Collapse multiple underscores
    end

    ##
    # Sanitize string for use as identifier
    #
    # Converts a string to a safe identifier by removing/replacing unsafe characters.
    # Commonly used for database table names, tool names, and other identifiers.
    #
    # @param str [String] The string to sanitize
    # @return [String] Sanitized identifier
    #
    # @example Database table name
    #   Utils.sanitize_identifier("My Table Name!")
    #   # => "my_table_name"
    #
    # @example Tool name
    #   Utils.sanitize_identifier("Special Characters & Spaces")
    #   # => "special_characters_spaces"
    def sanitize_identifier(str)
      Utils.snake_case(str)
    end

    ##
    # Parse JSON with symbolized keys
    #
    # Convenience method for parsing JSON with symbolized keys, which is commonly
    # used throughout RAAF for internal data processing.
    #
    # @param json_string [String] JSON string to parse
    # @return [Hash, Array] Parsed data with symbolized keys
    #
    # @example Parse JSON response
    #   Utils.parse_json('{"name": "John", "age": 30}')
    #   # => {:name => "John", :age => 30}
    #
    # @example Parse JSON array
    #   Utils.parse_json('[{"id": 1}, {"id": 2}]')
    #   # => [{:id => 1}, {:id => 2}]
    def parse_json(json_string)
      JSON.parse(json_string, symbolize_names: true)
    end

    ##
    # Safe JSON parsing with error handling
    #
    # Attempts to parse JSON string and returns nil if parsing fails.
    # Useful for optional JSON parsing where errors should be handled gracefully.
    #
    # @param json_string [String] JSON string to parse
    # @param default [Object] Default value to return if parsing fails
    # @return [Hash, Array, Object] Parsed data or default value
    #
    # @example Safe parsing with default
    #   Utils.safe_parse_json('invalid json', {})
    #   # => {}
    #
    # @example Safe parsing with nil default
    #   Utils.safe_parse_json('invalid json')
    #   # => nil
    def safe_parse_json(json_string, default = nil)
      parse_json(json_string)
    rescue JSON::ParserError
      default
    end

    ##
    # Format number with thousands separator
    #
    # Formats numbers with comma separators for better readability.
    # Commonly used in analytics and reporting.
    #
    # @param number [Numeric] Number to format
    # @return [String] Formatted number
    #
    # @example Format large number
    #   Utils.format_number(1234567)
    #   # => "1,234,567"
    #
    # @example Format decimal
    #   Utils.format_number(1234.56)
    #   # => "1,234.56"
    def format_number(number)
      number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    ##
    # Normalize whitespace in text
    #
    # Removes extra whitespace and normalizes line endings.
    # Commonly used for text processing and cleaning.
    #
    # @param text [String] Text to normalize
    # @return [String] Normalized text
    #
    # @example Clean text
    #   Utils.normalize_whitespace("  Hello    world  \n\n  ")
    #   # => "Hello world"
    #
    # @example Multiple spaces
    #   Utils.normalize_whitespace("Too   many    spaces")
    #   # => "Too many spaces"
    def normalize_whitespace(text)
      text.to_s.gsub(/\s+/, " ").strip
    end

  end

end

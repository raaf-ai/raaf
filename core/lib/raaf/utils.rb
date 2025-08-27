# frozen_string_literal: true

module RAAF

  ##
  # Utils - General utilities for RAAF
  #
  # This module provides helper methods for common operations in RAAF including:
  # - Indifferent hash access (seamless string/symbol key handling)
  # - JSON parsing with HashWithIndifferentAccess support
  # - String case conversion (snake_case)
  # - OpenAI API preparation utilities
  #
  # RAAF uses an **indifferent access strategy** throughout the system to eliminate
  # the confusion between string and symbol keys.
  #
  # == Indifferent Access Strategy
  #
  # The RAAF (Ruby AI Agents Factory) gem uses indifferent hash access:
  # - **All Data Structures**: Support both string and symbol keys seamlessly
  # - **JSON Parsing**: Returns HashWithIndifferentAccess by default for flexible access
  # - **API Integration**: Automatic conversion to required formats
  # - **User Experience**: Never worry about key types - both work identically
  #
  # == Performance Considerations
  #
  # HashWithIndifferentAccess uses Rails' battle-tested implementation for consistency
  # while providing transparent symbol access. For large nested structures, consider using 
  # streaming or chunked processing when performance is critical.
  #
  # @example API boundary conversion
  #   RAAF::Utils.prepare_for_openai({key: "value", nested: {inner: 123}})
  #   # => {"key" => "value", "nested" => {"inner" => 123}}
  #
  # @example Indifferent access conversion
  #   data = {"message" => {"role" => "assistant", "content" => "Hello"}}
  #   result = RAAF::Utils.indifferent_access(data)
  #   result[:message][:content]   # => "Hello"
  #   result["message"]["content"] # => "Hello" (same result)
  #
  # @example String case conversion
  #   RAAF::Utils.snake_case("CompanyDiscoveryAgent")
  #   # => "company_discovery_agent"
  #
  # @example JSON parsing with indifferent access
  #   json_str = '{"user": {"name": "John", "age": 30}}'
  #   result = RAAF::Utils.parse_json(json_str)
  #   result[:user][:name]    # => "John"
  #   result["user"]["name"]  # => "John" (same result)
  #   # No more key type confusion!
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
      case hash
      when Hash
        hash.transform_keys(&:to_s).transform_values { |v| prepare_for_openai(v) }
      when Array
        hash.map { |v| prepare_for_openai(v) }
      else
        hash
      end
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
      # Convert to symbol keys to match original behavior
      symbolize_keys(response)
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
    # Create HashWithIndifferentAccess from object
    #
    # Converts a hash, array, or other object to use indifferent key access.
    # This is the primary method for creating indifferent access structures
    # throughout RAAF, eliminating string vs symbol key issues.
    #
    # @param obj [Hash, Array, Object] The object to convert
    # @return [ActiveSupport::HashWithIndifferentAccess, Array, Object] Object with indifferent access
    #
    # @example Basic hash conversion
    #   Utils.indifferent_access({"name" => "John", :age => 30})
    #   # => HashWithIndifferentAccess allowing both hash[:name] and hash["name"]
    #
    # @example Nested structures
    #   data = {"user" => {"profile" => {"name" => "John"}}}
    #   hash = Utils.indifferent_access(data)
    #   hash[:user][:profile][:name]    # => "John"
    #   hash["user"]["profile"]["name"] # => "John"
    #
    # @example Arrays with hashes
    #   Utils.indifferent_access([{"id" => 1}, {"id" => 2}])
    #   # => [HashWithIndifferentAccess, HashWithIndifferentAccess] with indifferent access
    def indifferent_access(obj)
      case obj
      when Hash
        # Convert to HashWithIndifferentAccess recursively
        obj.with_indifferent_access.tap do |hash|
          hash.transform_values! { |value| indifferent_access(value) }
        end
      when Array
        obj.map { |item| indifferent_access(item) }
      else
        obj
      end
    end

    ##
    # Parse JSON with indifferent access
    #
    # Primary method for parsing JSON that returns HashWithIndifferentAccess objects
    # instead of regular hashes. This eliminates string vs symbol key confusion
    # throughout your RAAF applications.
    #
    # @param json_string [String] JSON string to parse
    # @return [ActiveSupport::HashWithIndifferentAccess, Array] Parsed data with indifferent key access
    #
    # @example Basic JSON parsing
    #   json = '{"name": "John", "age": 30}'
    #   result = Utils.parse_json(json)
    #   result[:name]   # => "John"
    #   result["name"]  # => "John" (same result)
    #
    # @example Nested structures
    #   json = '{"user": {"profile": {"name": "John"}}}'
    #   result = Utils.parse_json(json)
    #   result[:user][:profile][:name]      # => "John"
    #   result["user"]["profile"]["name"]   # => "John" (same result)
    #
    # @example Arrays with objects
    #   json = '[{"id": 1, "name": "Item 1"}, {"id": 2, "name": "Item 2"}]'
    #   result = Utils.parse_json(json)
    #   result[0][:id]     # => 1
    #   result[0]["id"]    # => 1 (same result)
    #   result[1][:name]   # => "Item 2"
    #   result[1]["name"]  # => "Item 2" (same result)
    #
    # @example Parse JSON response with indifferent access
    #   result = Utils.parse_json('{"name": "John", "age": 30}')
    #   result[:name]   # => "John"
    #   result["name"]  # => "John"
    #   result[:age]    # => 30
    #   result["age"]   # => 30
    #
    # @example Parse JSON array
    #   Utils.parse_json('[{"id": 1}, {"id": 2}]')
    #   # => [HashWithIndifferentAccess, HashWithIndifferentAccess] with flexible key access
    def parse_json(json_string)
      parsed = JSON.parse(json_string)
      indifferent_access(parsed)
    end


    ##
    # Safe JSON parsing with indifferent access
    #
    # Attempts to parse JSON string and returns HashWithIndifferentAccess with indifferent
    # access. Returns the default value if parsing fails.
    #
    # @param json_string [String] JSON string to parse
    # @param default [Object] Default value to return if parsing fails
    # @return [ActiveSupport::HashWithIndifferentAccess, Array, Object] Parsed data with indifferent access or default value
    #
    # @example Safe parsing with default
    #   Utils.safe_parse_json('invalid json', {}.with_indifferent_access)
    #   # => HashWithIndifferentAccess (empty)
    #
    # @example Safe parsing with nil default
    #   Utils.safe_parse_json('invalid json')
    #   # => nil
    #
    # @example Successful parsing
    #   result = Utils.safe_parse_json('{"key": "value"}')
    #   result[:key]   # => "value"
    #   result["key"]  # => "value"
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

    ##
    # Convert hash keys to symbols recursively
    #
    # Converts hash keys from strings to symbols throughout the data structure.
    # This method preserves the original behavior of normalize_response.
    #
    # @param obj [Hash, Array, Object] The object to convert
    # @return [Hash, Array, Object] Object with symbol keys
    #
    # @example Convert hash keys to symbols
    #   Utils.symbolize_keys({"name" => "John", "data" => {"nested" => true}})
    #   # => {:name => "John", :data => {:nested => true}}
    def symbolize_keys(obj)
      case obj
      when Hash
        obj.transform_keys(&:to_sym).transform_values { |value| symbolize_keys(value) }
      when Array
        obj.map { |item| symbolize_keys(item) }
      else
        obj
      end
    end

  end

end

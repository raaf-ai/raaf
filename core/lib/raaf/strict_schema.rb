# frozen_string_literal: true

module RAAF

  ##
  # Utilities for ensuring strict JSON schemas compatible with OpenAI's requirements
  #
  # This module provides utilities for transforming JSON schemas to meet OpenAI's
  # strict schema requirements for function calling and structured outputs. It ensures
  # schemas conform to the constraints required by the OpenAI API while maintaining
  # compatibility with standard JSON Schema specifications.
  #
  # == Strict Schema Requirements
  #
  # OpenAI's strict mode enforces several constraints:
  # * All object properties must be required (no optional fields)
  # * `additionalProperties` must be false for objects
  # * No nullable types or default values of null
  # * Simplified union handling (anyOf, allOf)
  #
  # == Key Transformations
  #
  # * **Property Requirements**: All object properties become required
  # * **Additional Properties**: Sets `additionalProperties: false` for objects
  # * **Key Conversion**: Handles symbol/string key conversion for API compatibility
  # * **Schema Flattening**: Simplifies single-item allOf constructs
  # * **Null Handling**: Removes null default values
  #
  # @example Basic schema transformation
  #   schema = {
  #     type: "object",
  #     properties: {
  #       name: { type: "string" },
  #       age: { type: "integer" }
  #     }
  #   }
  #   strict_schema = StrictSchema.ensure_strict_json_schema(schema)
  #   # Result: all properties required, additionalProperties: false
  #
  # @example Function tool schema
  #   function_schema = {
  #     name: "search",
  #     parameters: {
  #       type: "object",
  #       properties: {
  #         query: { type: "string", description: "Search query" },
  #         limit: { type: "integer", default: 10 }
  #       }
  #     }
  #   }
  #   strict_params = StrictSchema.ensure_strict_json_schema(function_schema[:parameters])
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.1.0
  # @see https://platform.openai.com/docs/guides/structured-outputs OpenAI Structured Outputs
  module StrictSchema

    class << self

      ##
      # Ensures the given JSON schema conforms to the strict standard that OpenAI API expects
      #
      # Transforms a JSON schema to meet OpenAI's strict schema requirements by:
      # - Making all object properties required
      # - Setting additionalProperties to false for objects
      # - Converting keys to strings for API compatibility
      # - Handling nested schemas recursively
      # - Flattening single allOf constructs
      # - Removing null default values
      #
      # @param schema [Hash, nil] JSON schema to make strict
      # @return [Hash] strict JSON schema compatible with OpenAI API
      #
      # @example Basic object schema
      #   schema = {
      #     type: "object",
      #     properties: {
      #       name: { type: "string" },
      #       email: { type: "string", format: "email" }
      #     }
      #   }
      #   strict = StrictSchema.ensure_strict_json_schema(schema)
      #   # => {
      #   #   "type" => "object",
      #   #   "properties" => {
      #   #     "name" => { "type" => "string" },
      #   #     "email" => { "type" => "string", "format" => "email" }
      #   #   },
      #   #   "required" => ["name", "email"],
      #   #   "additionalProperties" => false
      #   # }
      #
      # @example Array with object items
      #   schema = {
      #     type: "array",
      #     items: {
      #       type: "object",
      #       properties: { id: { type: "integer" } }
      #     }
      #   }
      #   strict = StrictSchema.ensure_strict_json_schema(schema)
      #
      # @example Union types (anyOf)
      #   schema = {
      #     anyOf: [
      #       { type: "string" },
      #       { type: "integer" }
      #     ]
      #   }
      #   strict = StrictSchema.ensure_strict_json_schema(schema)
      def ensure_strict_json_schema(schema)
        return empty_schema if schema.nil? || schema.empty?

        # Convert to string keys for processing using Utils method
        string_schema = Utils.prepare_for_openai(schema)
        ensure_strict_json_schema_recursive(string_schema, path: [], root: string_schema)
      end

      private



      ##
      # Generate an empty strict object schema
      #
      # Creates a minimal object schema that meets OpenAI's strict requirements.
      # Used as a fallback when no schema is provided or when creating base schemas.
      #
      # @return [Hash] empty strict object schema
      #
      # @example Empty schema structure
      #   empty = empty_schema
      #   # => {
      #   #   "additionalProperties" => false,
      #   #   "type" => "object",
      #   #   "properties" => {},
      #   #   "required" => []
      #   # }
      #
      # @api private
      def empty_schema
        {
          "additionalProperties" => false,
          "type" => "object",
          "properties" => {},
          "required" => []
        }
      end

      ##
      # Recursively ensure strict schema compliance for nested structures
      #
      # Processes a JSON schema recursively, applying strict transformations to
      # all nested objects, arrays, and union types. Maintains path context for
      # error reporting and handles various JSON Schema constructs.
      #
      # @param json_schema [Hash] schema to process
      # @param path [Array<String>] current path in schema (for error reporting)
      # @param root [Hash] root schema object (for reference resolution)
      # @return [Hash] processed schema with strict compliance
      #
      # @raise [TypeError] if schema is not a Hash
      # @raise [ArgumentError] if additionalProperties is true
      #
      # @api private
      def ensure_strict_json_schema_recursive(json_schema, path:, root:)
        raise TypeError, "Expected #{json_schema} to be a hash; path=#{path}" unless json_schema.is_a?(Hash)

        # Handle $defs
        if json_schema["$defs"].is_a?(Hash)
          json_schema["$defs"].each do |def_name, def_schema|
            ensure_strict_json_schema_recursive(def_schema, path: [*path, "$defs", def_name], root: root)
          end
        end

        # Handle definitions
        if json_schema["definitions"].is_a?(Hash)
          json_schema["definitions"].each do |definition_name, definition_schema|
            ensure_strict_json_schema_recursive(definition_schema, path: [*path, "definitions", definition_name],
                                                                   root: root)
          end
        end

        type = json_schema["type"]

        # Object types - ensure additionalProperties is false and all properties are required
        if type == "object"
          json_schema["additionalProperties"] = false unless json_schema.key?("additionalProperties")

          raise ArgumentError, "additionalProperties should not be set to true for strict schemas" if json_schema["additionalProperties"] == true

          # OpenAI strict mode requires ALL object types to have 'properties' defined
          json_schema["properties"] = {} unless json_schema.key?("properties")

          # All properties must be required in strict mode (like Python implementation)
          # BUT: Don't override existing required arrays that were carefully crafted
          properties = json_schema["properties"]
          if properties.is_a?(Hash)
            # Only set required if no explicit required array was provided
            if json_schema["required"].nil? || json_schema["required"].empty?
              json_schema["required"] = properties.keys.map(&:to_s)
            end
            json_schema["properties"] = properties.transform_values do |prop_schema|
              ensure_strict_json_schema_recursive(prop_schema, path: [*path, "properties"], root: root)
            end
          end
        end

        # Arrays
        if type == "array" && json_schema["items"].is_a?(Hash)
          json_schema["items"] =
            ensure_strict_json_schema_recursive(json_schema["items"], path: [*path, "items"], root: root)
        end

        # Unions (anyOf)
        if json_schema["anyOf"].is_a?(Array)
          json_schema["anyOf"] = json_schema["anyOf"].map.with_index do |variant, i|
            ensure_strict_json_schema_recursive(variant, path: [*path, "anyOf", i.to_s], root: root)
          end
        end

        # Intersections (allOf)
        if json_schema["allOf"].is_a?(Array)
          if json_schema["allOf"].length == 1
            # Flatten single allOf
            flattened = ensure_strict_json_schema_recursive(json_schema["allOf"][0], path: [*path, "allOf", "0"],
                                                                                     root: root)
            json_schema.merge!(flattened)
            json_schema.delete("allOf")
          else
            json_schema["allOf"] = json_schema["allOf"].map.with_index do |entry, i|
              ensure_strict_json_schema_recursive(entry, path: [*path, "allOf", i.to_s], root: root)
            end
          end
        end

        # Strip None/nil defaults as there's no meaningful distinction
        json_schema.delete("default") if json_schema["default"].nil?

        json_schema
      end

    end

  end

end

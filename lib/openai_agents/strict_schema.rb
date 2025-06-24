# frozen_string_literal: true

module OpenAIAgents
  # Utilities for ensuring strict JSON schemas compatible with OpenAI's requirements
  # Based on the Python implementation in openai-agents
  module StrictSchema
    class << self
      # Ensures the given JSON schema conforms to the strict standard that OpenAI API expects
      # This mutates the schema to add required fields and other strict requirements
      def ensure_strict_json_schema(schema)
        return empty_schema if schema.nil? || schema.empty?

        # Convert to string keys for processing
        string_schema = deep_stringify_keys(schema)
        ensure_strict_json_schema_recursive(string_schema, path: [], root: string_schema)
      end

      private

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

      def empty_schema
        {
          "additionalProperties" => false,
          "type" => "object",
          "properties" => {},
          "required" => []
        }
      end

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

          if json_schema["additionalProperties"] == true
            raise ArgumentError, "additionalProperties should not be set to true for strict schemas"
          end

          # All properties must be required in strict mode (like Python implementation)
          properties = json_schema["properties"]
          if properties.is_a?(Hash)
            json_schema["required"] = properties.keys.map(&:to_s)
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

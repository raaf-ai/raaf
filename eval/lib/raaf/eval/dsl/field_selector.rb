# frozen_string_literal: true

require "active_support/core_ext/hash/indifferent_access"
require_relative "field_context"

module RAAF
  module Eval
    module DSL
      # Error raised when field path format is invalid
      class InvalidPathError < StandardError; end
      
      # Error raised when a field is not found
      class FieldNotFoundError < StandardError; end
      
      # Error raised when duplicate alias is detected
      class DuplicateAliasError < StandardError; end

      # Handles field selection, extraction, and aliasing for evaluation DSL
      # Supports nested path parsing, field value extraction, and alias management
      class FieldSelector
        attr_reader :fields, :aliases

        def initialize
          @fields = []
          @aliases = {}
          @path_cache = {}
        end

        # Add a field to be selected with optional alias
        # @param field_path [String, Symbol] The field path (supports dot notation)
        # @param as [Symbol, String, nil] Optional alias for the field
        def add_field(field_path, as: nil)
          validate_path(field_path)
          
          field_path = field_path.to_s
          @fields << field_path unless @fields.include?(field_path)
          
          if as
            alias_name = as.to_s
            if @aliases.key?(alias_name) && @aliases[alias_name] != field_path
              raise DuplicateAliasError, "Alias '#{alias_name}' is already assigned to field '#{@aliases[alias_name]}'"
            end
            @aliases[alias_name] = field_path
          end
        end

        # Parse a field path into its components
        # @param path [String, Symbol] The field path to parse
        # @return [Array<String>] The parsed path components
        def parse_path(path)
          validate_path(path)
          
          path_str = path.to_s
          return @path_cache[path_str] if @path_cache.key?(path_str)
          
          parsed = path_str.split(".")
          @path_cache[path_str] = parsed
          parsed
        end

        # Extract a field value from a result hash
        # @param field_path [String, Symbol] The field path
        # @param result [Hash] The result hash to extract from
        # @return [Object] The extracted value
        def extract_value(field_path, result)
          field_path = field_path.to_s
          parts = parse_path(field_path)
          
          # Ensure we're working with indifferent access
          result = ensure_indifferent_access(result)
          
          current = result
          parts.each_with_index do |part, index|
            if current.is_a?(Hash)
              if current.key?(part)
                current = current[part]
              else
                raise FieldNotFoundError, "Field '#{field_path}' not found in result"
              end
            else
              raise FieldNotFoundError, "Field '#{field_path}' not found in result"
            end
          end
          
          current
        end

        # Resolve an alias to its original field path
        # @param field_or_alias [String, Symbol] Field name or alias
        # @return [String] The original field path
        def resolve_alias(field_or_alias)
          field_or_alias = field_or_alias.to_s
          @aliases.fetch(field_or_alias, field_or_alias)
        end

        # Create a FieldContext for a given field
        # @param field_or_alias [String, Symbol] Field name or alias
        # @param result [Hash] The result hash
        # @return [FieldContext] The field context object
        def create_field_context(field_or_alias, result)
          field_path = resolve_alias(field_or_alias)
          FieldContext.new(field_path, result)
        end

        private

        # Validate that a path is in correct format
        # @param path [Object] The path to validate
        def validate_path(path)
          if path.nil?
            raise InvalidPathError, "Field path is empty or invalid"
          end
          
          unless path.is_a?(String) || path.is_a?(Symbol)
            raise InvalidPathError, "Field path must be a string or symbol, got #{path.class}"
          end
          
          path_str = path.to_s
          
          if path_str.empty?
            raise InvalidPathError, "Field path is empty or invalid"
          end
          
          # Check for invalid formats (consecutive dots, leading/trailing dots)
          if path_str.include?("..") || path_str.start_with?(".") || path_str.end_with?(".")
            raise InvalidPathError, "Invalid path format: '#{path_str}'"
          end
        end

        # Ensure hash uses indifferent access
        def ensure_indifferent_access(hash)
          return hash if hash.is_a?(ActiveSupport::HashWithIndifferentAccess)
          ActiveSupport::HashWithIndifferentAccess.new(hash)
        end
      end
    end
  end
end

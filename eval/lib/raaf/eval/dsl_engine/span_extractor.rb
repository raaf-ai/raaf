# frozen_string_literal: true

module RAAF
  module Eval
    module DslEngine
      # Extracts selected fields from span data using FieldSelector
      class SpanExtractor
        class << self
          # Extract fields from span using field selector
          # @param span [Hash] The span data
          # @param field_selector [DSL::FieldSelector] Field selector configuration
          # @param only_fields [Array<Symbol>, nil] If provided, only extract fields that map to these aliases
          # @return [Hash] Extracted field values keyed by field path
          def extract_fields(span, field_selector, only_fields: nil)
            # Ensure span supports indifferent access
            span = ensure_indifferent_access(span)

            # Filter fields if only_fields is specified
            fields_to_extract = if only_fields.present?
              # Get field paths that correspond to the requested aliases
              only_fields_set = only_fields.map(&:to_sym).to_set
              field_selector.fields.select do |field_path|
                # Check if this field path or its alias is in the only_fields list
                alias_name = field_selector.aliases.key(field_path)
                key = alias_name ? alias_name.to_sym : field_path.to_sym
                only_fields_set.include?(key)
              end
            else
              field_selector.fields
            end

            fields_to_extract.each_with_object({}) do |field_path, hash|
              # Check if the alias exists at the top level of span (for overridden values)
              # This allows build_rerun_span_data to set values at alias keys that
              # override the nested path extraction for consistency evaluations
              alias_name = field_selector.aliases.key(field_path)
              if alias_name
                # Try to get value from top-level alias key first
                top_level_value = span[alias_name.to_sym] || span[alias_name.to_s]
                if top_level_value.present?
                  hash[field_path] = top_level_value
                  next
                end
              end

              # Fall back to extracting via the field path
              value = field_selector.extract_value(field_path, span)
              hash[field_path] = value
            end
          end

          private

          # Ensure hash supports indifferent access
          # @param hash [Hash] Hash to convert
          # @return [Hash] Hash with indifferent access
          def ensure_indifferent_access(hash)
            return hash if hash.is_a?(ActiveSupport::HashWithIndifferentAccess)
            return hash.with_indifferent_access if hash.respond_to?(:with_indifferent_access)

            # Fallback: create a simple indifferent access wrapper
            IndifferentHash.new(hash)
          end
        end

        # Simple indifferent access wrapper for hashes
        class IndifferentHash
          def initialize(hash)
            @hash = hash
          end

          def [](key)
            @hash[key] || @hash[key.to_s] || @hash[key.to_sym]
          end

          def dig(*keys)
            keys.reduce(self) do |obj, key|
              return nil unless obj.respond_to?(:[])
              obj[key]
            end
          end

          def merge(other)
            IndifferentHash.new(@hash.merge(other))
          end

          def to_h
            @hash
          end
        end
      end
    end
  end
end

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
          # @return [Hash] Extracted field values keyed by field path
          def extract_fields(span, field_selector)
            # Ensure span supports indifferent access
            span = ensure_indifferent_access(span)

            field_selector.fields.each_with_object({}) do |field_path, hash|
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

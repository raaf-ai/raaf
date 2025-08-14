# frozen_string_literal: true

module RAAF
  module DSL
    module Builders
      # DSL for building result mappings in declarative agents
      #
      # This class provides a clean DSL for defining how agent data should be
      # transformed from AI responses into application-specific formats.
      #
      # @example Basic usage
      #   builder = ResultBuilder.new
      #   builder.field :markets, from: :markets
      #   builder.field :source, value: "market_analysis"
      #   builder.field :analyzed_at, value: -> { Time.current }
      #   builder.field :market_count, computed: :count_markets
      #
      class ResultBuilder
        attr_reader :mapping
        
        def initialize
          @mapping = {}
        end
        
        # Define a field in the result mapping
        #
        # @param name [Symbol] The field name in the output result
        # @param from [Symbol] Map directly from AI response field
        # @param value [Object, Proc] Static value or proc for the field
        # @param computed [Symbol] Method name to call for computed values
        #
        # @example Direct mapping
        #   field :markets, from: :markets
        #
        # @example Static value
        #   field :source, value: "market_analysis"
        #
        # @example Dynamic value
        #   field :analyzed_at, value: -> { Time.current }
        #
        # @example Computed value
        #   field :market_count, computed: :count_markets
        #
        def field(name, from: nil, value: nil, computed: nil)
          if from
            @mapping[name] = { type: :from_data, source: from }
          elsif value
            @mapping[name] = { type: :value, value: value }
          elsif computed
            @mapping[name] = { type: :computed, method: computed }
          else
            raise ArgumentError, "Field #{name} must specify one of: from, value, or computed"
          end
        end
        
        # Define multiple fields that map directly from AI response
        #
        # @param fields [Array<Symbol>] Field names to map directly
        #
        # @example
        #   map_from :markets, :confidence, :reasoning
        #
        def map_from(*fields)
          fields.each do |field_name|
            field(field_name, from: field_name)
          end
        end
        
        # Define a group of related fields with a prefix
        #
        # @param prefix [String, Symbol] Prefix for field names
        # @param fields [Hash] Field mappings
        #
        # @example
        #   group :analysis do
        #     field :timestamp, value: -> { Time.current }
        #     field :version, value: "1.0"
        #   end
        #
        def group(prefix, &block)
          group_builder = self.class.new
          group_builder.instance_eval(&block)
          
          group_builder.mapping.each do |field_name, config|
            prefixed_name = "#{prefix}_#{field_name}".to_sym
            @mapping[prefixed_name] = config
          end
        end
      end
    end
  end
end
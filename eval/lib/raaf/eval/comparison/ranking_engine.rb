# frozen_string_literal: true

module RAAF
  module Eval
    module Comparison
      # Ranks configurations by field scores
      class RankingEngine
        # Rank all fields
        # @param field_deltas [Hash] Field deltas with configuration scores
        # @return [Hash] Rankings for each field
        def self.rank_all_fields(field_deltas)
          field_deltas.each_with_object({}) do |(field_name, field_delta), rankings|
            rankings[field_name] = rank_field(field_delta[:configurations])
          end
        end

        # Rank configurations by score on a single field
        # @param configurations [Hash] Configuration scores and deltas
        # @return [Array<Symbol>] Configuration names ranked by score (highest to lowest)
        def self.rank_field(configurations)
          configurations.sort_by do |config_name, config_data|
            # Sort by score descending, then by name ascending (tie-breaker)
            [-config_data[:score], config_name.to_s]
          end.map(&:first)
        end
      end
    end
  end
end

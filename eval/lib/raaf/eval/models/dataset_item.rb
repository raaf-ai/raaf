# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # DatasetItem represents a single test case within a Dataset.
      # Contains input data and optionally expected output for evaluation.
      #
      # @example Creating a dataset item
      #   item = DatasetItem.create!(
      #     dataset: dataset,
      #     input: { query: "How do I reset my password?" },
      #     expected_output: { response: "Go to settings...", category: "account" }
      #   )
      class DatasetItem < ActiveRecord::Base
        self.table_name = "raaf_dataset_items"

        # Associations
        belongs_to :dataset,
                   class_name: "RAAF::Eval::Models::Dataset",
                   counter_cache: false
        has_many :experiment_results,
                 class_name: "RAAF::Eval::Models::ExperimentResult",
                 foreign_key: :dataset_item_id,
                 dependent: :destroy

        # Validations
        validates :input, presence: true

        # Scopes
        scope :with_expected_output, -> { where.not(expected_output: {}) }
        scope :from_span, ->(span_id) { where(source_span_id: span_id) }
        scope :from_trace, ->(trace_id) { where(source_trace_id: trace_id) }
        scope :recent, -> { order(created_at: :desc) }

        ##
        # Check if this item has expected output defined
        # @return [Boolean]
        def has_expected_output?
          expected_output.present? && expected_output != {}
        end

        ##
        # Get input as messages array (convenience for agent execution)
        # @return [Array<Hash>]
        def input_messages
          input["messages"] || input[:messages] || [{ role: "user", content: input.to_json }]
        end

        ##
        # Check if this item was imported from a production span
        # @return [Boolean]
        def from_production?
          source_span_id.present?
        end
      end
    end
  end
end

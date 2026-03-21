# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # FeedbackScoreDefinition defines a reusable scoring template.
      # Provides schema for consistent scoring across teams.
      #
      # @example Numerical score definition
      #   FeedbackScoreDefinition.create!(
      #     name: "relevance",
      #     description: "How relevant is the response to the query",
      #     score_type: "numerical",
      #     min_value: 0.0,
      #     max_value: 1.0
      #   )
      #
      # @example Categorical score definition
      #   FeedbackScoreDefinition.create!(
      #     name: "quality",
      #     description: "Overall response quality",
      #     score_type: "categorical",
      #     categories: ["excellent", "good", "average", "poor"]
      #   )
      class FeedbackScoreDefinition < ActiveRecord::Base
        self.table_name = "raaf_feedback_score_definitions"

        # Validations
        validates :name, presence: true, uniqueness: true
        validates :score_type, presence: true, inclusion: { in: %w[numerical categorical] }
        validates :min_value, presence: true, if: :numerical?
        validates :max_value, presence: true, if: :numerical?
        validate :validate_categories, if: :categorical?
        validate :validate_range, if: :numerical?

        # Scopes
        scope :numerical, -> { where(score_type: "numerical") }
        scope :categorical, -> { where(score_type: "categorical") }

        ##
        # Check if this is a numerical score type
        # @return [Boolean]
        def numerical?
          score_type == "numerical"
        end

        ##
        # Check if this is a categorical score type
        # @return [Boolean]
        def categorical?
          score_type == "categorical"
        end

        ##
        # Validate a value against this definition
        # @param value [Float, String] The value to validate
        # @return [Boolean]
        def valid_value?(value)
          if numerical?
            value.is_a?(Numeric) && value >= (min_value || 0) && value <= (max_value || 1)
          elsif categorical?
            categories.include?(value.to_s)
          else
            false
          end
        end

        private

        def validate_categories
          if categories.blank? || !categories.is_a?(Array) || categories.empty?
            errors.add(:categories, "must be a non-empty array for categorical scores")
          end
        end

        def validate_range
          return if min_value.nil? || max_value.nil?
          if min_value >= max_value
            errors.add(:max_value, "must be greater than min_value")
          end
        end
      end
    end
  end
end

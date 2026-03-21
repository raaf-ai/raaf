# frozen_string_literal: true

module RAAF
  module Eval
    module Models
      ##
      # FeedbackScore represents a human or automated annotation on a trace or span.
      # Inspired by Opik's feedback scoring system for human-in-the-loop evaluation.
      #
      # Feedback scores can be numerical (0.0-1.0) or categorical ("good", "bad", etc.)
      # and can be applied to traces or individual spans.
      #
      # @example Adding a numerical score to a span
      #   FeedbackScore.create!(
      #     name: "relevance",
      #     span_id: "span_abc123",
      #     value: 0.85,
      #     scored_by: "reviewer@example.com",
      #     source: "ui"
      #   )
      #
      # @example Adding a categorical score
      #   FeedbackScore.create!(
      #     name: "quality",
      #     trace_id: "trace_xyz789",
      #     category_value: "good",
      #     reason: "Response was accurate and well-formatted",
      #     scored_by: "reviewer@example.com"
      #   )
      #
      # @example Querying aggregate scores
      #   FeedbackScore.for_span("span_abc123").average_value  #=> 0.82
      #   FeedbackScore.for_name("relevance").score_distribution
      class FeedbackScore < ActiveRecord::Base
        self.table_name = "raaf_feedback_scores"

        # Validations
        validates :name, presence: true
        validates :source, presence: true, inclusion: { in: %w[ui sdk api automated] }
        validate :must_have_span_or_trace
        validate :must_have_value_or_category

        # Scopes
        scope :for_span, ->(span_id) { where(span_id: span_id) }
        scope :for_trace, ->(trace_id) { where(trace_id: trace_id) }
        scope :for_name, ->(name) { where(name: name) }
        scope :by_scorer, ->(scorer) { where(scored_by: scorer) }
        scope :numerical, -> { where.not(value: nil) }
        scope :categorical, -> { where.not(category_value: nil) }
        scope :from_humans, -> { where(source: %w[ui sdk]) }
        scope :from_automated, -> { where(source: "automated") }
        scope :recent, -> { order(created_at: :desc) }

        ##
        # Check if this is a numerical score
        # @return [Boolean]
        def numerical?
          value.present?
        end

        ##
        # Check if this is a categorical score
        # @return [Boolean]
        def categorical?
          category_value.present?
        end

        ##
        # Check if this score is for a span
        # @return [Boolean]
        def span_level?
          span_id.present?
        end

        ##
        # Check if this score is for a trace
        # @return [Boolean]
        def trace_level?
          trace_id.present? && span_id.blank?
        end

        class << self
          ##
          # Calculate average value for numerical scores
          # @return [Float, nil]
          def average_value
            numerical.average(:value)&.to_f
          end

          ##
          # Get score distribution for categorical scores
          # @return [Hash] Category => count mapping
          def category_distribution
            categorical.group(:category_value).count
          end

          ##
          # Get score statistics for numerical scores
          # @return [Hash] Statistics hash
          def score_statistics
            values = numerical.pluck(:value)
            return {} if values.empty?

            {
              count: values.size,
              avg: (values.sum / values.size.to_f).round(4),
              min: values.min,
              max: values.max,
              median: median(values).round(4)
            }
          end

          ##
          # Bulk create scores for a span
          # @param span_id [String] Span ID
          # @param scores [Hash] Name => value mapping
          # @param scored_by [String] Who created the scores
          # @param source [String] Score source
          # @return [Array<FeedbackScore>]
          def score_span(span_id:, scores:, scored_by: nil, source: "sdk")
            scores.map do |name, value|
              attrs = { name: name.to_s, span_id: span_id, scored_by: scored_by, source: source }
              if value.is_a?(Numeric)
                attrs[:value] = value
              else
                attrs[:category_value] = value.to_s
              end
              create!(attrs)
            end
          end

          ##
          # Bulk create scores for a trace
          # @param trace_id [String] Trace ID
          # @param scores [Hash] Name => value mapping
          # @param scored_by [String] Who created the scores
          # @param source [String] Score source
          # @return [Array<FeedbackScore>]
          def score_trace(trace_id:, scores:, scored_by: nil, source: "sdk")
            scores.map do |name, value|
              attrs = { name: name.to_s, trace_id: trace_id, scored_by: scored_by, source: source }
              if value.is_a?(Numeric)
                attrs[:value] = value
              else
                attrs[:category_value] = value.to_s
              end
              create!(attrs)
            end
          end

          private

          def median(values)
            sorted = values.sort
            mid = sorted.size / 2
            sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
          end
        end

        private

        def must_have_span_or_trace
          if span_id.blank? && trace_id.blank?
            errors.add(:base, "must have either span_id or trace_id")
          end
        end

        def must_have_value_or_category
          if value.blank? && category_value.blank?
            errors.add(:base, "must have either a numerical value or category_value")
          end
        end
      end
    end
  end
end

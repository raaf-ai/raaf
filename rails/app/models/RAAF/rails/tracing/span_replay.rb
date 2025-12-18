# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      # ActiveRecord model for tracking span replay operations
      #
      # A span replay captures the configuration changes and results when
      # re-running an AI agent from a stored span with modified settings.
      #
      # ## Usage
      #
      # @example Create a replay for a span
      #   original = SpanRecord.find(span_id)
      #   replay = SpanReplay.create!(
      #     original_span: original,
      #     configuration_changes: { model: "gpt-4o", temperature: 0.5 },
      #     system_prompt: "Updated system prompt",
      #     user_messages: [{ role: "user", content: "Hello" }]
      #   )
      #
      # @example Execute the replay
      #   SpanReplayJob.perform_later(replay_id: replay.id)
      #
      class SpanReplay < ActiveRecord::Base
        self.table_name = "raaf_tracing_span_replays"

        # Associations
        belongs_to :original_span,
                   class_name: "RAAF::Rails::Tracing::SpanRecord",
                   primary_key: :span_id,
                   foreign_key: :original_span_id

        belongs_to :replayed_span,
                   class_name: "RAAF::Rails::Tracing::SpanRecord",
                   primary_key: :span_id,
                   foreign_key: :replayed_span_id,
                   optional: true

        # Validations
        validates :original_span_id, presence: true
        validates :status, inclusion: { in: %w[pending running completed failed] }

        # Scopes
        scope :pending, -> { where(status: "pending") }
        scope :running, -> { where(status: "running") }
        scope :completed, -> { where(status: "completed") }
        scope :failed, -> { where(status: "failed") }
        scope :recent, -> { order(created_at: :desc) }
        scope :for_span, ->(span_id) { where(original_span_id: span_id) }

        # Status predicates
        def pending?
          status == "pending"
        end

        def running?
          status == "running"
        end

        def completed?
          status == "completed"
        end

        def failed?
          status == "failed"
        end

        # Check if replay can be executed
        def executable?
          pending? && original_span.present?
        end

        # Mark replay as running
        def mark_running!
          update!(status: "running")
        end

        # Mark replay as completed with the new span
        def mark_completed!(new_span)
          update!(
            status: "completed",
            replayed_span_id: new_span.span_id
          )
        end

        # Mark replay as failed with error message
        def mark_failed!(error_message)
          update!(
            status: "failed",
            error_message: error_message
          )
        end

        # Build configuration overrides hash for SpanReplayer
        #
        # @return [Hash] Merged configuration with prompt overrides
        def build_overrides
          overrides = (configuration_changes || {}).deep_symbolize_keys

          # Add prompt overrides if present
          if system_prompt.present?
            overrides[:system_prompt] = system_prompt
          end

          if user_messages.present? && user_messages.any?
            overrides[:messages] = user_messages
          end

          overrides
        end

        # Get the original model from the span
        def original_model
          original_span&.span_attributes&.dig("llm", "request", "model") ||
            original_span&.span_attributes&.dig("model")
        end

        # Get the configured model (or original if not changed)
        def configured_model
          configuration_changes&.dig("model") ||
            configuration_changes&.dig(:model) ||
            original_model
        end

        # Get original configuration settings
        def original_settings
          attrs = original_span&.span_attributes || {}
          llm_config = attrs.dig("llm", "request") || {}

          {
            model: llm_config["model"] || attrs["model"],
            temperature: llm_config["temperature"],
            max_tokens: llm_config["max_tokens"] || llm_config["max_output_tokens"],
            top_p: llm_config["top_p"],
            frequency_penalty: llm_config["frequency_penalty"],
            presence_penalty: llm_config["presence_penalty"]
          }.compact
        end

        # Get original messages from the span
        def original_messages
          original_span&.span_attributes&.dig("llm", "request", "messages") || []
        end

        # Get the original system prompt
        def original_system_prompt
          messages = original_messages
          system_msg = messages.find { |m| m["role"] == "system" }
          system_msg&.dig("content")
        end

        # Get original user messages (non-system messages)
        def original_user_messages
          messages = original_messages
          messages.reject { |m| m["role"] == "system" }
        end

        # Get duration comparison if both spans exist
        def duration_comparison
          return nil unless replayed_span.present?

          {
            original_ms: original_span.duration_ms,
            replayed_ms: replayed_span.duration_ms,
            difference_ms: replayed_span.duration_ms - original_span.duration_ms,
            percentage_change: calculate_percentage_change(
              original_span.duration_ms,
              replayed_span.duration_ms
            )
          }
        end

        # Get token usage comparison if both spans exist
        def token_comparison
          return nil unless replayed_span.present?

          original_usage = original_span.span_attributes&.dig("llm", "usage") || {}
          replayed_usage = replayed_span.span_attributes&.dig("llm", "usage") || {}

          {
            original: {
              input_tokens: original_usage["input_tokens"],
              output_tokens: original_usage["output_tokens"],
              total: (original_usage["input_tokens"] || 0) + (original_usage["output_tokens"] || 0)
            },
            replayed: {
              input_tokens: replayed_usage["input_tokens"],
              output_tokens: replayed_usage["output_tokens"],
              total: (replayed_usage["input_tokens"] || 0) + (replayed_usage["output_tokens"] || 0)
            }
          }
        end

        private

        def calculate_percentage_change(original, replayed)
          return nil if original.nil? || original.zero?

          ((replayed - original).to_f / original * 100).round(2)
        end
      end
    end
  end
end

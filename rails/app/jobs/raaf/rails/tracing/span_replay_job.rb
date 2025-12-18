# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # Background job for executing span replays
      #
      # This job uses the SpanReplayer from raaf-eval to replay an LLM call
      # with modified configuration, then creates a new span record with the results.
      #
      # @example
      #   SpanReplayJob.perform_later(replay_id: 123)
      #
      class SpanReplayJob < ApplicationJob
        queue_as :default

        # Retry with exponential backoff for transient API errors
        retry_on StandardError, wait: :polynomially_longer, attempts: 3

        # Don't retry on configuration errors
        discard_on ArgumentError

        ##
        # Execute the span replay
        #
        # @param replay_id [Integer] ID of the SpanReplay record
        def perform(replay_id:)
          replay = SpanReplay.find(replay_id)

          # Skip if not in pending state (may have been cancelled)
          unless replay.pending?
            RAAF.logger.info "[SpanReplayJob] Replay #{replay_id} is not pending (status: #{replay.status}), skipping"
            return
          end

          # Mark as running
          replay.mark_running!

          # Broadcast status update via Turbo Stream
          broadcast_status_update(replay)

          begin
            # Execute the replay
            result = execute_replay(replay)

            if result[:success]
              # Create a new span record for the replayed result
              new_span = create_replayed_span(replay, result)

              # Mark replay as completed
              replay.mark_completed!(new_span)

              RAAF.logger.info "[SpanReplayJob] Replay #{replay_id} completed, new span: #{new_span.span_id}"
            else
              # Mark as failed
              replay.mark_failed!(result[:error] || "Unknown error during replay")

              RAAF.logger.warn "[SpanReplayJob] Replay #{replay_id} failed: #{result[:error]}"
            end
          rescue StandardError => e
            RAAF.logger.error "[SpanReplayJob] Replay #{replay_id} error: #{e.message}"
            RAAF.logger.error "[SpanReplayJob] Backtrace: #{e.backtrace.first(5).join("\n")}"

            replay.mark_failed!(e.message)
            raise # Re-raise for retry mechanism
          ensure
            # Always broadcast final status
            broadcast_status_update(replay.reload)
          end
        end

        private

        ##
        # Execute the replay using SpanReplayer
        #
        # @param replay [SpanReplay] The replay record
        # @return [Hash] Result from SpanReplayer
        def execute_replay(replay)
          # Check if SpanReplayer is available
          unless defined?(RAAF::Eval::SpanReplayer)
            return {
              success: false,
              error: "RAAF Eval gem is not available. Please install raaf-eval."
            }
          end

          original_span = replay.original_span

          # Build overrides from replay configuration
          overrides = replay.build_overrides

          # Create replayer and execute
          replayer = RAAF::Eval::SpanReplayer.new(original_span)

          unless replayer.replayable?
            return {
              success: false,
              error: "Original span is not replayable. Missing required LLM request data."
            }
          end

          RAAF.logger.info "[SpanReplayJob] Executing replay with overrides: #{overrides.keys.inspect}"

          replayer.replay(**overrides)
        end

        ##
        # Create a new span record for the replayed result
        #
        # @param replay [SpanReplay] The replay record
        # @param result [Hash] Result from SpanReplayer
        # @return [SpanRecord] The created span record
        def create_replayed_span(replay, result)
          original = replay.original_span
          started_at = Time.current - (result[:duration_ms] / 1000.0).seconds

          # Build span attributes similar to the original
          span_attributes = build_span_attributes(replay, result, original)

          SpanRecord.create!(
            trace_id: original.trace_id,
            parent_id: original.parent_id,
            name: "#{original.name} (replay)",
            kind: original.kind,
            status: result[:success] ? "ok" : "error",
            start_time: started_at,
            end_time: Time.current,
            duration_ms: result[:duration_ms],
            span_attributes: span_attributes,
            events: []
          )
        end

        ##
        # Build span attributes for the replayed span
        #
        # Copies ALL attributes from the original span to maintain full structure,
        # then updates only the fields that changed during replay (model, response, usage).
        #
        # @param replay [SpanReplay] The replay record
        # @param result [Hash] Result from SpanReplayer
        # @param original [SpanRecord] Original span
        # @return [Hash] Span attributes
        def build_span_attributes(replay, result, original)
          orig_attrs = original.span_attributes || {}

          # Start with a deep copy of ALL original attributes to preserve full structure
          attrs = deep_copy(orig_attrs)

          # Get messages (use edited messages if provided, otherwise original)
          messages = replay.user_messages.presence ||
                     orig_attrs.dig("llm", "request", "messages") ||
                     orig_attrs["agent.conversation_messages"]

          # Update LLM attributes with new response
          attrs["llm"] ||= {}
          attrs["llm"]["request"] ||= {}
          attrs["llm"]["request"]["model"] = result[:model]
          attrs["llm"]["request"]["messages"] = messages

          attrs["llm"]["response"] ||= {}
          attrs["llm"]["response"]["content"] = result[:content]

          attrs["llm"]["usage"] = result[:usage] || {}

          # Update flat model keys for AgentSpanComponent display
          attrs["agent.model"] = result[:model]
          attrs["model"] = result[:model]
          attrs["llm.model"] = result[:model]

          # Update provider
          new_provider = result[:settings]&.dig(:provider) || replay.configuration_changes&.dig("provider")
          if new_provider.present?
            attrs["agent.provider"] = new_provider
            attrs["provider"] = new_provider
          end

          # Update conversation messages for replayability
          if messages.present?
            attrs["agent.conversation_messages"] = messages.is_a?(String) ? messages : messages.to_json
          end

          # Update the final agent response with the new content
          if result[:content].present?
            attrs["agent.final_agent_response"] = result[:content]
            attrs["final_agent_response"] = result[:content]
            attrs["response.content"] = result[:content]
          end

          # Add settings to request if provided
          if result[:settings].present?
            result[:settings].each do |key, value|
              attrs["llm"]["request"][key.to_s] = value
              # Also update flat keys for common settings
              case key.to_s
              when "temperature"
                attrs["agent.temperature"] = value
                attrs["temperature"] = value
              when "max_tokens"
                attrs["agent.max_tokens"] = value
                attrs["max_tokens"] = value
              when "top_p"
                attrs["agent.top_p"] = value
                attrs["top_p"] = value
              end
            end
          end

          # Mark as a replay (add replay metadata)
          attrs["replay"] = {
            "original_span_id" => replay.original_span_id,
            "replay_id" => replay.id,
            "configuration_changes" => replay.configuration_changes
          }

          attrs
        end

        ##
        # Deep copy a hash structure to avoid modifying the original
        #
        # @param obj [Object] Object to copy
        # @return [Object] Deep copied object
        def deep_copy(obj)
          case obj
          when Hash
            obj.transform_values { |v| deep_copy(v) }
          when Array
            obj.map { |v| deep_copy(v) }
          else
            obj.duplicable? ? obj.dup : obj
          end
        rescue
          obj
        end

        ##
        # Broadcast status update via Turbo Stream
        #
        # @param replay [SpanReplay] The replay record
        def broadcast_status_update(replay)
          return unless defined?(Turbo::StreamsChannel)

          Turbo::StreamsChannel.broadcast_replace_to(
            "span_replay_#{replay.id}",
            target: "replay-status",
            partial: "raaf/rails/tracing/replays/status",
            locals: { replay: replay }
          )
        rescue StandardError => e
          RAAF.logger.warn "[SpanReplayJob] Failed to broadcast status: #{e.message}"
        end
      end
    end
  end
end

# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      # Controller for managing span replays
      #
      # Allows users to replay stored spans with modified configurations
      # for debugging and experimentation purposes.
      class ReplaysController < ApplicationController
        before_action :set_span
        before_action :set_replay, only: %i[show]

        # GET /tracing/spans/:span_id/replays/new
        # Shows the replay form with original span data
        def new
          # Check if span is replayable
          unless replayable?(@span)
            redirect_to tracing_span_path(@span.span_id),
                        alert: "This span cannot be replayed. It may not contain the required LLM request data."
            return
          end

          @replay = SpanReplay.new(original_span: @span)

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Tracing::Replay::NewComponent.new(
                span: @span,
                replay: @replay
              )

              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Replay Span - #{@span.display_name}") do
                render component
              end

              render layout
            end
            format.json { render json: build_replay_form_data(@span) }
          end
        end

        # POST /tracing/spans/:span_id/replays
        # Creates a new replay and queues the job
        def create
          @replay = SpanReplay.new(replay_params)
          @replay.original_span_id = @span.span_id

          if @replay.save
            # Queue the replay job
            RAAF::Rails::Tracing::SpanReplayJob.perform_later(replay_id: @replay.id)

            respond_to do |format|
              format.turbo_stream do
                render turbo_stream: turbo_stream.replace(
                  "replay-status",
                  RAAF::Rails::Tracing::Replay::StatusComponent.new(replay: @replay)
                )
              end
              format.html do
                redirect_to tracing_span_replay_path(@span.span_id, @replay.id),
                            notice: "Replay started. Results will appear when complete."
              end
              format.json do
                render json: {
                  replay_id: @replay.id,
                  status: @replay.status,
                  redirect_url: tracing_span_replay_path(@span.span_id, @replay.id)
                }, status: :created
              end
            end
          else
            respond_to do |format|
              format.turbo_stream do
                render turbo_stream: turbo_stream.replace(
                  "replay-form",
                  RAAF::Rails::Tracing::Replay::FormComponent.new(
                    span: @span,
                    replay: @replay,
                    errors: @replay.errors
                  )
                )
              end
              format.html do
                @span = @replay.original_span
                render :new
              end
              format.json { render json: { errors: @replay.errors.full_messages }, status: :unprocessable_entity }
            end
          end
        end

        # GET /tracing/spans/:span_id/replays/:id
        # Shows replay results and comparison view
        def show
          respond_to do |format|
            format.html do
              component = RAAF::Rails::Tracing::Replay::ShowComponent.new(
                replay: @replay,
                original_span: @span
              )

              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Replay Results - #{@span.display_name}") do
                render component
              end

              render layout
            end
            format.json { render json: build_replay_result_data(@replay) }
          end
        end

        # GET /tracing/spans/:span_id/replays
        # Lists all replays for a span
        def index
          @replays = SpanReplay.for_span(@span.span_id).recent

          respond_to do |format|
            format.html do
              component = RAAF::Rails::Tracing::Replay::IndexComponent.new(
                span: @span,
                replays: @replays
              )

              layout = RAAF::Rails::Tracing::BaseLayout.new(title: "Replays - #{@span.display_name}") do
                render component
              end

              render layout
            end
            format.json { render json: serialize_replays(@replays) }
          end
        end

        private

        def set_span
          @span = SpanRecord.find_by!(span_id: params[:span_id])
        rescue ActiveRecord::RecordNotFound
          redirect_to tracing_spans_path, alert: "Span not found."
        end

        def set_replay
          @replay = SpanReplay.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          redirect_to tracing_span_path(@span.span_id), alert: "Replay not found."
        end

        def replay_params
          params.require(:span_replay).permit(
            :notes,
            :system_prompt,
            configuration_changes: {},
            user_messages: []
          ).tap do |permitted|
            # Parse JSON fields if they come as strings
            if permitted[:configuration_changes].is_a?(String)
              permitted[:configuration_changes] = JSON.parse(permitted[:configuration_changes])
            end
            if permitted[:user_messages].is_a?(String)
              permitted[:user_messages] = JSON.parse(permitted[:user_messages])
            end
          rescue JSON::ParserError => e
            ::Rails.logger.warn "[RAAF Replay] JSON parse error: #{e.message}"
          end
        end

        def replayable?(span)
          attrs = span.span_attributes || {}

          # Check for messages in various storage formats
          # - Nested hash: attrs.dig("llm", "request", "messages")
          # - Dot-notation key: attrs["agent.conversation_messages"]
          messages = attrs.dig("llm", "request", "messages") ||
                     attrs["llm.request.messages"] ||
                     attrs["agent.conversation_messages"] ||
                     attrs["conversation_messages"]

          # Try to parse JSON if it's a string
          if messages.is_a?(String) && messages.present?
            begin
              messages = JSON.parse(messages)
            rescue JSON::ParserError
              messages = nil
            end
          end

          # If no messages found, check if we can reconstruct from system/user prompts
          if messages.blank? || (messages.is_a?(Array) && messages.empty?)
            has_prompts = attrs["agent.system_instructions"].present? ||
                          attrs["agent.initial_user_prompt"].present?
            messages = has_prompts ? [{ "role" => "user", "content" => "placeholder" }] : nil
          end

          # Check for model in various storage formats
          model = attrs.dig("llm", "request", "model") ||
                  attrs["llm.request.model"] ||
                  attrs["agent.model"] ||
                  attrs["model"]

          messages.present? && model.present?
        end

        def build_replay_form_data(span)
          attrs = span.span_attributes || {}
          llm_config = attrs.dig("llm", "request") || {}

          # Get messages from various storage formats
          messages = llm_config["messages"] ||
                     attrs["llm.request.messages"] ||
                     attrs["agent.conversation_messages"] ||
                     []

          # Parse JSON if it's a string
          if messages.is_a?(String) && messages.present?
            begin
              messages = JSON.parse(messages)
            rescue JSON::ParserError
              messages = []
            end
          end

          system_message = messages.find { |m| m["role"] == "system" }
          user_messages = messages.reject { |m| m["role"] == "system" }

          # Get model from various storage formats
          model = llm_config["model"] ||
                  attrs["llm.request.model"] ||
                  attrs["agent.model"] ||
                  attrs["model"]

          {
            span_id: span.span_id,
            replayable: replayable?(span),
            original_config: {
              model: model,
              temperature: llm_config["temperature"] || attrs["agent.temperature"],
              max_tokens: llm_config["max_tokens"] || llm_config["max_output_tokens"] || attrs["agent.max_tokens"],
              top_p: llm_config["top_p"] || attrs["agent.top_p"],
              frequency_penalty: llm_config["frequency_penalty"] || attrs["agent.frequency_penalty"],
              presence_penalty: llm_config["presence_penalty"] || attrs["agent.presence_penalty"]
            }.compact,
            system_prompt: system_message&.dig("content") || attrs["agent.system_instructions"],
            user_messages: user_messages,
            original_output: attrs.dig("llm", "response", "content") ||
                            attrs.dig("llm", "response", "choices", 0, "message", "content") ||
                            attrs["agent.final_agent_response"]
          }
        end

        def build_replay_result_data(replay)
          {
            id: replay.id,
            status: replay.status,
            configuration_changes: replay.configuration_changes,
            original_span: {
              span_id: replay.original_span.span_id,
              name: replay.original_span.display_name,
              duration_ms: replay.original_span.duration_ms
            },
            replayed_span: if replay.replayed_span
                             {
                               span_id: replay.replayed_span.span_id,
                               name: replay.replayed_span.display_name,
                               duration_ms: replay.replayed_span.duration_ms
                             }
                           end,
            duration_comparison: replay.duration_comparison,
            token_comparison: replay.token_comparison,
            error_message: replay.error_message,
            created_at: replay.created_at,
            updated_at: replay.updated_at
          }
        end

        def serialize_replays(replays)
          {
            replays: replays.map do |replay|
              {
                id: replay.id,
                status: replay.status,
                configuration_changes: replay.configuration_changes,
                replayed_span_id: replay.replayed_span_id,
                created_at: replay.created_at
              }
            end
          }
        end
      end
    end
  end
end

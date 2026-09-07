# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      # Controller for managing span replays
      #
      # Allows users to replay stored spans with modified configurations
      # for debugging and experimentation purposes.
      #
      # `index` answers two routes. Nested under a span it lists that span's
      # replays; mounted at the top of the tracing namespace it lists every
      # replay there is, which is what the console's Replays screen opens.
      # Same screen, same component -- only the filter differs.
      class ReplaysController < ApplicationController
        # How many replays the console lists. A replay is a deliberate act, so
        # the table stays short in practice; the cap is there so a busy install
        # cannot render an unbounded page.
        CONSOLE_LIMIT = 200

        before_action :set_span, if: :span_scoped?
        before_action :set_replay, only: %i[show]

        # GET /tracing/replays              — every replay
        # GET /tracing/spans/:span_id/replays — one span's replays
        def index
          @replays = scoped_replays

          respond_to do |format|
            format.html do
              render_in_layout(
                RAAF::Rails::Tracing::Replay::IndexComponent.new(span: @span, replays: @replays),
                title: @span ? "Replays of #{@span.display_name}" : "Replays"
              )
            end
            format.json { render json: serialize_replays(@replays) }
          end
        end

        # GET /tracing/spans/:span_id/replays/:id
        # Shows replay results and comparison view
        def show
          respond_to do |format|
            format.html do
              render_in_layout(
                RAAF::Rails::Tracing::Replay::ShowComponent.new(
                  replay: @replay,
                  original_span: @span,
                  view: params[:view]
                ),
                title: "Replay ##{@replay.id}",
                bundles: [ :diff ]
              )
            end
            format.json { render json: build_replay_result_data(@replay) }
          end
        end

        # GET /tracing/spans/:span_id/replays/new
        # Shows the replay form with original span data
        def new
          # Check if span is replayable
          unless SpanReplay.replayable?(@span)
            redirect_to span_location(@span),
                        alert: "This span cannot be replayed. It may not contain the required LLM request data."
            return
          end

          @replay = SpanReplay.new(original_span: @span)

          respond_to do |format|
            format.html do
              render_in_layout(
                RAAF::Rails::Tracing::Replay::NewComponent.new(span: @span, replay: @replay),
                title: "Replay #{@span.display_name}"
              )
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
                  "replay-status",
                  RAAF::Rails::Tracing::Replay::StatusComponent.new(replay: @replay)
                )
              end
              format.html do
                render_in_layout(
                  RAAF::Rails::Tracing::Replay::NewComponent.new(span: @span, replay: @replay),
                  title: "Replay #{@span.display_name}"
                )
              end
              format.json { render json: { errors: @replay.errors.full_messages }, status: :unprocessable_content }
            end
          end
        end

        private

        # A replay list nested under a span, or the console's list of all of
        # them. `includes` is what keeps the all-replays table off N+1 -- every
        # row prints its original span's name and duration.
        def scoped_replays
          return SpanReplay.for_span(@span.span_id).recent.includes(:replayed_span) if @span

          SpanReplay.recent.includes(:original_span, :replayed_span).limit(CONSOLE_LIMIT)
        end

        def span_scoped?
          params[:span_id].present?
        end

        # @param bundles [Array<Symbol>] front-end libraries this screen needs;
        #   see {RAAF::Rails::Tracing::BaseLayout::BUNDLES}. The list and the
        #   form ask for none — only the comparison view renders a diff or
        #   prints a payload.
        def render_in_layout(component, title:, bundles: [])
          layout = RAAF::Rails::Tracing::BaseLayout.new(
            title: title, current: :replays, bundles: bundles
          ) do
            render component
          end

          render layout
        end

        def set_span
          @span = SpanRecord.find_by!(span_id: params[:span_id])
        rescue ActiveRecord::RecordNotFound
          redirect_to tracing_spans_path, alert: "Span not found."
        end

        def set_replay
          @replay = SpanReplay.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          redirect_to span_location(@span), alert: "Replay not found."
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
            permitted[:user_messages] = JSON.parse(permitted[:user_messages]) if permitted[:user_messages].is_a?(String)
          rescue JSON::ParserError => e
            ::Rails.logger.warn "[RAAF Replay] JSON parse error: #{e.message}"
          end
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
            replayable: SpanReplay.replayable?(span),
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
                original_span_id: replay.original_span_id,
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

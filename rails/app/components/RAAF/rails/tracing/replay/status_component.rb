# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      module Replay
        ##
        # The one-line state of a replay, as the form's status slot.
        #
        # Rendered into `#replay-status` by the Turbo Stream the create action
        # returns, so the id lives on the root element -- the stream replaces
        # this element, not something inside it.
        #
        # Four states, four tones, and nothing else: the library's `Alert`
        # already says "this went well" or "this did not" in the console's
        # voice, so the states differ only in what they say.
        #
        class StatusComponent < BaseComponent
          VARIANTS = {
            "pending" => :info,
            "running" => :info,
            "completed" => :success,
            "failed" => :error
          }.freeze

          def initialize(replay:)
            @replay = replay
          end

          def view_template
            div(id: "replay-status") do
              render(Molecules::Alert.new(variant, title: title, icon: icon)) do
                p(class: "raaf-alert-text") { message }

                div(class: "raaf-alert-actions") { action } if action?
              end
            end
          end

          private

          def variant
            VARIANTS.fetch(@replay.status, :info)
          end

          def icon
            @replay.running? ? "arrow-repeat" : nil
          end

          def title
            case @replay.status
            when "pending" then "Queued"
            when "running" then "Running"
            when "completed" then "Finished"
            when "failed" then "Replay failed"
            else @replay.status.to_s.capitalize
            end
          end

          def message
            case @replay.status
            when "pending"
              "The replay is queued and starts as soon as a worker picks it up."
            when "running"
              "Running the call with your changes. This page updates itself when it finishes."
            when "completed"
              "The replay finished. Its output is ready to compare against the original."
            when "failed"
              @replay.error_message.presence ||
                "The replay stopped without recording why."
            else
              "The replay is in an unrecognised state."
            end
          end

          def action?
            (@replay.completed? && @replay.replayed_span.present?) || @replay.failed?
          end

          def action
            if @replay.failed?
              render Atoms::Button.new(label: "Try again", icon: "arrow-repeat", size: :sm,
                                       variant: :secondary,
                                       href: new_tracing_span_replay_path(@replay.original_span_id))
            else
              render Atoms::Button.new(label: "See the comparison", trailing_icon: "arrow-right",
                                       size: :sm, variant: :secondary,
                                       href: tracing_span_replay_path(@replay.original_span_id, @replay.id))
            end
          end
        end
      end
    end
  end
end

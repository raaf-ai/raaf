# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # A status badge that explains itself when a span was skipped.
      #
      # Previously this carried three parallel sets of hand-written classes
      # (modern, detailed, legacy) for what is one thing: a status pill. The
      # colour now comes from Badge's status mapping, so every surface in the
      # dashboard labels a status identically. `style: :detailed` still adds a
      # leading glyph, which is the only difference that ever mattered.
      #
      class SkippedBadgeTooltip < BaseComponent
        STATUS_ICONS = {
          "ok" => "check-circle-fill",
          "completed" => "check-circle-fill",
          "error" => "x-circle-fill",
          "failed" => "x-circle-fill",
          "running" => "arrow-clockwise",
          "skipped" => "skip-forward-fill",
          "cancelled" => "slash-circle"
        }.freeze

        MAX_REASON_LENGTH = 160

        # @param status [String, Symbol, nil]
        # @param skip_reason [String, nil] shown in a tooltip when present
        # @param style [Symbol] :detailed adds a leading status glyph
        def initialize(status:, skip_reason: nil, style: :default)
          @status = status
          @skip_reason = skip_reason
          @style = style
        end

        def view_template
          return badge if @skip_reason.blank?

          span(class: "raaf-tooltip") do
            span(class: "raaf-tooltip-trigger", tabindex: "0") { badge }
            span(class: "raaf-tooltip-content", role: "tooltip") { format_skip_reason(@skip_reason) }
          end
        end

        private

        def badge
          render Ui::Atoms::Badge.for_status(@status.presence || "unknown", icon: icon)
        end

        def icon
          return nil unless @style == :detailed

          STATUS_ICONS[@status.to_s.downcase] || "clock"
        end

        # Skip reasons arrive from provider payloads and may carry markup;
        # strip it before showing, and cap the length so the tooltip stays small.
        def format_skip_reason(reason)
          text = if defined?(ActionController::Base) && ActionController::Base.respond_to?(:helpers)
                   ActionController::Base.helpers.strip_tags(reason.to_s)
                 else
                   CGI.unescapeHTML(reason.to_s)
                 end

          text.length <= MAX_REASON_LENGTH ? text : "#{text[0, MAX_REASON_LENGTH - 3]}..."
        end
      end
    end
  end
end

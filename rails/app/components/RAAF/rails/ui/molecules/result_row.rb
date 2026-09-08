# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # ResultRow — one graded thing, listed under another.
        #
        # The detail screens all end with a short list of somewhere else to
        # go: the cases either side of this one in a run, what the other
        # policies made of the same span, where this verdict sits among the
        # policy's recent ones, the trace behind the output. They are the same
        # row every time — an identity, a line saying which one it is, and on
        # the right whatever the reader is comparing.
        #
        # Everything but the title is optional, which is what lets the trace
        # link (no status, no score) and a neighbouring result (both) be the
        # same row rather than two that merely look alike.
        #
        # @example The previous case in an experiment run
        #   render Molecules::ResultRow.new(
        #     href: path, title: "#412", meta: "Previous case", icon: "arrow-left",
        #     status: "completed", value: "0.86", value_tone: :ok
        #   )
        #
        class ResultRow < Base
          # @param href [String] where the row goes
          # @param title [String] what the row is
          # @param meta [String, nil] the second line: which one, or when
          # @param icon [String, nil] leading icon, in the gutter
          # @param icon_tone [Symbol] an Icon tone
          # @param status [String, nil] status badge on the right
          # @param value [String, nil] the figure on the right
          # @param value_tone [Symbol, nil] a Mono tone for that figure
          def initialize(href:, title:, meta: nil, icon: nil, icon_tone: :muted,
                         status: nil, value: nil, value_tone: nil, class: nil, **attrs)
            @href = href
            @title = title
            @meta = meta
            @icon = icon
            @icon_tone = icon_tone
            @status = status
            @value = value
            @value_tone = value_tone
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            a(href: @href, class: tokens("raaf-result-row", @class), **@attrs) do
              render Atoms::Icon.new(@icon, size: :sm, tone: @icon_tone) if @icon

              span(class: "raaf-result-row-body") do
                render Atoms::Mono.new(@title)
                render Atoms::Mono.new(@meta, tone: :muted) if @meta.present?
              end

              render Atoms::StatusBadge.new(@status) if @status.present?
              render Atoms::Mono.new(@value, tone: @value_tone) if @value.present?
            end
          end
        end
      end
    end
  end
end

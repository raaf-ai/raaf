# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # RecordHead — the panel a detail screen opens on.
        #
        # The canvas draws the same header three times over: a policy, a
        # dataset and an experiment each lead with a name, a line of prose, a
        # status pill beside a line of mono metadata, one control, and a small
        # grid of figures on the right. It was written once per screen before
        # this, so a change to any of those parts had to be made three times.
        #
        # Every part is optional: a screen with no figures passes no stats and
        # gets the name block alone.
        #
        # @example
        #   render Organisms::RecordHead.new(
        #     title: dataset.name, mono: true,
        #     description: dataset.description,
        #     status: dataset.status,
        #     meta: "version 4 · created 2026-06-18",
        #     action: { label: "New version", icon: "copy", href: "…" },
        #     stats: [{ label: "Items", value: "120" }]
        #   )
        #
        class RecordHead < Base
          # @param title [String]
          # @param mono [Boolean] set the name in the mono face, as the design
          #   does for a dataset and a prompt — both are file-like names — and
          #   does not for a policy or an experiment
          # @param description [String, nil] prose, given its own measure
          # @param status [String, nil] rendered through Atoms::StatusBadge
          # @param meta [String, nil] the mono line beside the status
          # @param action [Hash, nil] arguments for Atoms::Button
          # @param stats [Array<Hash>] :label, :value, and an optional :tone
          def initialize(title:, mono: false, description: nil, status: nil, meta: nil,
                         action: nil, stats: [], class: nil, **attrs)
            @title = title
            @mono = mono
            @description = description
            @status = status
            @meta = meta
            @action = action
            @stats = Array(stats)
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          # A block renders after the stats — the Experiment screen hangs a
          # second control off its header this way.
          def view_template(&block)
            div(class: tokens("raaf-rechead", @class), **@attrs) do
              body
              action_button if @action
              stats if @stats.any?
              yield if block
            end
          end

          private

          def body
            div(class: "raaf-rechead-body") do
              h2(class: tokens("raaf-rechead-name", { "raaf-rechead-name--mono" => @mono })) { @title }

              if @description.present?
                render Atoms::Text.new(@description, tone: :secondary, class: "raaf-rechead-desc")
              end

              badges if @status.present? || @meta.present?
            end
          end

          def badges
            div(class: "raaf-cluster") do
              render Atoms::StatusBadge.new(@status) if @status.present?
              render Atoms::Mono.new(@meta, tone: :muted) if @meta.present?
            end
          end

          # The design pins the control to the top of a header that wraps, and
          # tints its icon — the only thing `Atoms::Button` at `:sm` does not
          # already do.
          def action_button
            render Atoms::Button.new(size: :sm, class: "raaf-rechead-action", **@action)
          end

          def stats
            div(class: "raaf-rechead-stats") do
              @stats.each do |stat|
                div(class: "raaf-rechead-stat") do
                  render Atoms::Label.new(stat[:label])
                  render Atoms::Mono.new(stat[:value], tone: stat[:tone], size: :lg)
                end
              end
            end
          end
        end
      end
    end
  end
end

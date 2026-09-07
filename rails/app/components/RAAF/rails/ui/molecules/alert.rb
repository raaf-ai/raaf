# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # Alert — a tinted notice with an icon, title and body.
        #
        # The icon is derived from the variant, so callers state intent rather
        # than picking a glyph.
        #
        # @example
        #   render Molecules::Alert.new(:error, title: "Replay failed",
        #                               text: result.error_message)
        #
        class Alert < Base
          VARIANTS = %i[success info warning error].freeze

          ICONS = {
            success: "check-circle-fill",
            info: "info-circle-fill",
            warning: "exclamation-triangle-fill",
            error: "x-octagon-fill"
          }.freeze

          ROLES = { error: "alert", warning: "alert" }.freeze

          # @param variant [Symbol] :success, :info, :warning or :error
          # @param title [String, nil]
          # @param text [String, nil] body copy; a block overrides it
          # @param icon [String, nil] override the variant's icon
          def initialize(variant = :info, title: nil, text: nil, icon: nil, class: nil, **attrs)
            @variant = variant
            @title = title
            @text = text
            @icon = icon
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: css, role: ROLES.fetch(@variant, "status"), **@attrs) do
              render Atoms::Icon.new(@icon || ICONS.fetch(@variant, ICONS[:info]))

              div(class: "raaf-alert-body") do
                p(class: "raaf-alert-title") { @title } if @title
                if block
                  yield
                elsif @text
                  p(class: "raaf-alert-text") { @text }
                end
              end
            end
          end

          private

          def css
            tokens("raaf-alert", modifier("raaf-alert", @variant, VARIANTS), @class)
          end
        end
      end
    end
  end
end

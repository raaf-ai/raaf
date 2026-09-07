# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Button — the system's action atom.
        #
        # Renders an `<a>` when given an `href`, a `<button>` otherwise, so
        # links and form actions share one visual definition.
        #
        # @example Primary action
        #   render Atoms::Button.new(label: "Run replay", icon: "play-fill")
        #
        # @example Compact row action
        #   render Atoms::Button.new(label: "View", href: span_path(span), size: :sm)
        #
        class Button < Base
          VARIANTS = %i[secondary danger light icon].freeze
          SIZES = %i[sm lg].freeze

          # @param label [String, nil] visible text; omit for icon-only buttons
          # @param href [String, nil] renders an anchor when present
          # @param variant [Symbol, nil] :secondary, :danger, :light or :icon
          # @param size [Symbol, nil] :sm or :lg
          # @param icon [String, nil] Bootstrap Icons name, without the `bi-`
          # @param trailing_icon [String, nil] icon rendered after the label
          # @param disabled [Boolean]
          def initialize(label: nil, href: nil, variant: nil, size: nil, icon: nil,
                         trailing_icon: nil, disabled: false, class: nil, **attrs)
            @label = label
            @href = href
            @variant = variant
            @size = size
            @icon = icon
            @trailing_icon = trailing_icon
            @disabled = disabled
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            if @href && !@disabled
              a(href: @href, class: css, **@attrs) { content(&block) }
            else
              button(type: @attrs.delete(:type) || "button", disabled: @disabled,
                     class: css, **@attrs) { content(&block) }
            end
          end

          private

          def css
            tokens(
              "raaf-button",
              modifier("raaf-button", @variant, VARIANTS),
              modifier("raaf-button", @size, SIZES),
              { "raaf-button--disabled" => @disabled },
              @class
            )
          end

          def content(&block)
            render Icon.new(@icon) if @icon
            if block
              yield
            elsif @label
              span { @label }
            end
            render Icon.new(@trailing_icon) if @trailing_icon
          end
        end
      end
    end
  end
end

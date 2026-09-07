# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Input — a text control.
        #
        # The dashboard's forms sit on glass cards, so `surface: :glass` is the
        # default here even though the design system's default input targets a
        # light form surface.
        #
        # @example
        #   render Atoms::Input.new(name: "q", value: params[:q], placeholder: "Search spans")
        #
        class Input < Base
          SURFACES = %i[glass].freeze
          SIZES = %i[sm].freeze

          # @param name [String, nil] form field name
          # @param type [String] HTML input type
          # @param value [Object, nil]
          # @param surface [Symbol, nil] :glass for dark cards, nil for light forms
          # @param size [Symbol, nil] :sm
          # @param mono [Boolean] monospace, for ids and JSON fragments
          # @param invalid [Boolean]
          def initialize(name: nil, type: "text", value: nil, surface: :glass, size: nil,
                         mono: false, invalid: false, class: nil, **attrs)
            @name = name
            @type = type
            @value = value
            @surface = surface
            @size = size
            @mono = mono
            @invalid = invalid
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            input(type: @type, name: @name, value: @value, class: css,
                  "aria-invalid": (@invalid ? "true" : nil), **@attrs)
          end

          private

          def css
            tokens(
              "raaf-input",
              modifier("raaf-input", @surface, SURFACES),
              modifier("raaf-input", @size, SIZES),
              { "raaf-input--mono" => @mono, "raaf-input--invalid" => @invalid },
              @class
            )
          end
        end
      end
    end
  end
end

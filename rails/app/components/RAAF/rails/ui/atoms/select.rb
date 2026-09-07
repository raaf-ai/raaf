# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Select — a dropdown sharing the Input shape, with the native arrow
        # replaced by the system's chevron.
        #
        # @example
        #   render Atoms::Select.new(
        #     name: "kind",
        #     options: [["All kinds", ""], %w[Agent agent], %w[Tool tool]],
        #     selected: params[:kind]
        #   )
        #
        class Select < Base
          # @param options [Array<Array(String, String), String>] label/value pairs
          # @param selected [Object, nil] the value to mark selected
          # @param include_blank [String, nil] label for a leading blank option
          def initialize(name: nil, options: [], selected: nil, include_blank: nil,
                         surface: :glass, size: nil, invalid: false, class: nil, **attrs)
            @name = name
            @options = options
            @selected = selected
            @include_blank = include_blank
            @surface = surface
            @size = size
            @invalid = invalid
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            select(name: @name, class: css, "aria-invalid": (@invalid ? "true" : nil), **@attrs) do
              option(value: "") { @include_blank } if @include_blank

              @options.each do |entry|
                label, value = entry.is_a?(::Array) ? entry : [entry, entry]
                option(value: value, selected: selected?(value)) { label.to_s }
              end
            end
          end

          private

          def css
            tokens(
              "raaf-input",
              "raaf-select",
              modifier("raaf-input", @surface, Input::SURFACES),
              modifier("raaf-input", @size, Input::SIZES),
              { "raaf-input--invalid" => @invalid },
              @class
            )
          end

          def selected?(value)
            !@selected.nil? && @selected.to_s == value.to_s
          end
        end
      end
    end
  end
end

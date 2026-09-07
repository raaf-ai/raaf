# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Toggle — a switch backed by a real checkbox.
        #
        # The checkbox stays in the DOM so the control is keyboard operable and
        # posts with the form; the track and knob are painted from its
        # `:checked` state rather than from a class the server has to compute.
        #
        # @example
        #   render Atoms::Toggle.new(name: "policy[active]", checked: policy.active?,
        #                            label: "Evaluate new spans")
        #
        class Toggle < Base
          def initialize(name: nil, checked: false, value: "1", label: nil,
                         disabled: false, class: nil, **attrs)
            @name = name
            @checked = checked
            @value = value
            @label = label
            @disabled = disabled
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            return control unless @label

            label(class: "raaf-toggle-field") do
              control
              span(class: "raaf-toggle-field-label") { @label }
            end
          end

          private

          def control
            span(class: tokens("raaf-toggle", @class)) do
              input(type: "checkbox", name: @name, value: @value, checked: @checked,
                    disabled: @disabled, class: "raaf-toggle-input", **@attrs)
              span(class: "raaf-toggle-track")
              span(class: "raaf-toggle-knob")
            end
          end
        end
      end
    end
  end
end

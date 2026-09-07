# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # Field — label, control, hint and error as one unit.
        #
        # Wraps any form atom so every form in the dashboard spaces and labels
        # its controls identically. The control is supplied as a block, which
        # keeps Field agnostic about whether it wraps an Input, Select,
        # Textarea or something bespoke.
        #
        # @example
        #   render(Molecules::Field.new(label: "Sample rate", hint: "Percent of spans")) do
        #     render Atoms::Input.new(name: "policy[sample_rate]", type: "number")
        #   end
        #
        class Field < Base
          # @param label [String, nil]
          # @param for_id [String, nil] `for` attribute on the label
          # @param hint [String, nil] guidance shown below the control
          # @param error [String, nil] validation message; replaces the hint
          # @param optional [Boolean] adds the "optional" chip to the label
          def initialize(label: nil, for_id: nil, hint: nil, error: nil, optional: false,
                         class: nil, **attrs)
            @label = label
            @for_id = for_id
            @hint = hint
            @error = error
            @optional = optional
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: tokens("raaf-field", @class), **@attrs) do
              render Atoms::Label.new(@label, for_id: @for_id, optional: @optional) if @label
              yield if block
              render_message
            end
          end

          private

          def render_message
            if @error
              p(class: "raaf-input-error") { @error }
            elsif @hint
              p(class: "raaf-input-hint") { @hint }
            end
          end
        end
      end
    end
  end
end

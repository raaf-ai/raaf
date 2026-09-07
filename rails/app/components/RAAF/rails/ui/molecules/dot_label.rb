# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # DotLabel — a status dot in front of a name.
        #
        # The design opens a row with this wherever the health of the thing
        # matters more than any column could say: the Agents table, the live
        # runs list, the agent tile. The dot carries the state and the label
        # carries the identity, so neither has to be read to find the other.
        #
        # @example
        #   render Molecules::DotLabel.new("Company::EnrichAgent", tone: :bad)
        #
        class DotLabel < Base
          # @param label [String]
          # @param tone [Symbol] a Dot tone — :ok, :warn, :bad, :info, :idle
          # @param pulse [Boolean] fade the dot in and out
          # @param mono [Boolean] set the label in the mono face, as the design
          #   does for anything a developer typed
          # @param state [String, nil] accessible name for the dot; without it
          #   the dot is decorative and the colour alone carries the state
          def initialize(label, tone: :idle, pulse: false, mono: true, state: nil,
                         class: nil, **attrs)
            @label = label
            @tone = tone
            @pulse = pulse
            @mono = mono
            @state = state
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            span(class: tokens("raaf-dot-label", @class), **@attrs) do
              render Atoms::Dot.new(tone: @tone, pulse: @pulse, label: @state)
              span(class: tokens("raaf-dot-label-text", { "raaf-mono" => @mono })) { @label }
            end
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # KeyValue — one labelled fact.
        #
        # The detail panes are almost entirely made of these, so the component
        # handles the two cases they hit constantly: a nil value renders as a
        # muted em dash rather than an empty gap, and `mono: true` switches to
        # tabular figures for ids, durations and token counts.
        #
        # @example
        #   render Molecules::KeyValue.new("Span ID", span.span_id, mono: true)
        #
        class KeyValue < Base
          BLANK = "—"

          # @param key [String] the label
          # @param value [Object, nil] nil renders as an em dash
          # @param mono [Boolean] monospace with tabular figures
          def initialize(key, value = nil, mono: false, class: nil, **attrs)
            @key = key
            @value = value
            @mono = mono
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: tokens("raaf-kv", @class), **@attrs) do
              span(class: "raaf-kv-key") { @key }
              div(class: value_css) { slot(display_value, &block) }
            end
          end

          private

          def value_css
            tokens(
              "raaf-kv-value",
              { "raaf-kv-value--mono" => @mono, "raaf-kv-value--muted" => blank? }
            )
          end

          def blank?
            @value.nil? || (@value.respond_to?(:empty?) && @value.empty?)
          end

          def display_value
            blank? ? BLANK : @value
          end
        end
      end
    end
  end
end

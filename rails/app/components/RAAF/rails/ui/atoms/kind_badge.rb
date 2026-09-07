# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # KindBadge — a span-kind chip.
        #
        # This class owns the only mapping from a span kind to a colour;
        # nothing else in the library hardcodes one. Unrecognised kinds fall
        # back to the neutral pipeline treatment rather than going unstyled.
        #
        class KindBadge < Base
          KINDS = %i[agent llm tool handoff guardrail pipeline].freeze

          # Kinds the tracer emits that are really one of the six above.
          ALIASES = { "response" => :llm, "span" => :pipeline, "chat" => :llm }.freeze

          # Public so a filter chip can colour its dot by the same rule the
          # badge uses, rather than repeating the alias table.
          def self.resolve(kind)
            key = kind.to_s.downcase
            return key.to_sym if KINDS.include?(key.to_sym)

            ALIASES.fetch(key, :pipeline)
          end

          def initialize(kind, class: nil, **attrs)
            @kind = kind
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            span(class: tokens("raaf-kind", "raaf-kind--#{resolved}", @class), **@attrs) { label }
          end

          private

          def resolved
            self.class.resolve(@kind)
          end

          def label
            @kind.to_s.empty? ? "unknown" : @kind.to_s.downcase
          end
        end
      end
    end
  end
end

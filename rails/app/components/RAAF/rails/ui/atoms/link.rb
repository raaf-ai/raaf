# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Link — an inline link in the console's accent.
        #
        # For a link *inside* a row, where the row itself is not one. A row that
        # carries buttons cannot be an anchor, so its identifying cell has to
        # link on its own.
        #
        # @example
        #   render Atoms::Link.new("a1b2c3d4", href: queue_path(item), mono: true)
        #
        class Link < Base
          # @param label [String]
          # @param href [String]
          # @param mono [Boolean] set in the monospace face, for ids
          # @param tone [Symbol, nil] :muted for a link that should not pull
          def initialize(label = nil, href:, mono: false, tone: nil, class: nil, **attrs)
            @label = label
            @href = href
            @mono = mono
            @tone = tone
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            a(href: @href, class: css, **@attrs) { slot(@label, &block) }
          end

          private

          def css
            tokens("raaf-link",
                   { "raaf-mono" => @mono, "raaf-link--muted" => @tone == :muted },
                   @class)
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # BadgePill — a larger glass pill with an icon slot. Used for filter
        # chips and meta pills rather than status labels.
        #
        # @example
        #   render Atoms::BadgePill.new("Last 24h", icon: "clock")
        #
        class BadgePill < Base
          # @param label [String, nil]
          # @param href [String, nil] renders an anchor when present
          # @param icon [String, nil] leading Bootstrap Icons name
          def initialize(label = nil, href: nil, icon: nil, class: nil, **attrs)
            @label = label
            @href = href
            @icon = icon
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            css = tokens("raaf-badge-pill", @class)

            if @href
              a(href: @href, class: css, **@attrs) { body(&block) }
            else
              span(class: css, **@attrs) { body(&block) }
            end
          end

          private

          def body(&block)
            render Icon.new(@icon) if @icon
            slot(@label, &block)
          end
        end
      end
    end
  end
end

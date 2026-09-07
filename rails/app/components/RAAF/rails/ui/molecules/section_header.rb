# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # SectionHeader — a title with optional meta and right-aligned actions.
        #
        # @example
        #   render(Molecules::SectionHeader.new(title: "Recent traces", meta: "last 24h")) do
        #     render Atoms::Button.new(label: "Export", size: :sm, icon: "download")
        #   end
        #
        class SectionHeader < Base
          SIZES = %i[sm].freeze

          # @param title [String]
          # @param meta [String, nil] right-aligned caption when no actions given
          # @param size [Symbol, nil] :sm for headers inside a card
          # @param flush [Boolean] drop the underline and tighten the margin
          def initialize(title:, meta: nil, size: nil, flush: false, class: nil, **attrs)
            @title = title
            @meta = meta
            @size = size
            @flush = flush
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: css, **@attrs) do
              h2(class: "raaf-section-header-title") { @title }

              if block
                div(class: "raaf-section-header-actions", &block)
              elsif @meta
                span(class: "raaf-section-header-meta") { @meta }
              end
            end
          end

          private

          def css
            tokens(
              "raaf-section-header",
              modifier("raaf-section-header", @size, SIZES),
              { "raaf-section-header--flush" => @flush },
              @class
            )
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # DataRow — the signature list row: a leading mark, a title/meta stack,
        # and trailing slots.
        #
        # Reach for this over DataTable when the record has one obvious name
        # and a handful of qualifiers, rather than many comparable columns.
        #
        # @example
        #   render(Organisms::DataRow.new(
        #     title: span.name, meta: "#{span.kind} · #{span.duration_ms}ms",
        #     avatar: span.name, href: span_path(span)
        #   )) do
        #     render Atoms::Badge.for_status(span.status)
        #   end
        #
        class DataRow < Base
          # @param title [String]
          # @param meta [String, nil] the secondary line under the title
          # @param avatar [String, nil] name to derive an initials disc from
          # @param icon [String, nil] leading icon box, when there is no avatar
          # @param tone [Symbol, nil] tone for the leading icon box
          # @param href [String, nil] makes the whole row a link
          def initialize(title:, meta: nil, avatar: nil, icon: nil, tone: nil, href: nil,
                         class: nil, **attrs)
            @title = title
            @meta = meta
            @avatar = avatar
            @icon = icon
            @tone = tone
            @href = href
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            css = tokens("raaf-row", { "raaf-row--interactive" => @href }, @class)

            if @href
              a(href: @href, class: css, **@attrs) { body(&block) }
            else
              div(class: css, **@attrs) { body(&block) }
            end
          end

          private

          def body(&block)
            div(class: "raaf-row-lead") { lead }

            div(class: "raaf-row-body") do
              p(class: "raaf-row-title") { @title }
              p(class: "raaf-row-meta") { @meta } if @meta
            end

            div(class: "raaf-row-trail") { yield if block }
          end

          def lead
            if @avatar
              render Atoms::Avatar.new(@avatar, size: :md)
            elsif @icon
              render Atoms::IconBox.new(@icon, tone: @tone)
            end
          end
        end
      end
    end
  end
end

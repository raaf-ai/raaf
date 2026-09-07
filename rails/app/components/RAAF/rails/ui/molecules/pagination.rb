# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # Pagination — a summary line and previous/next, as the design has it.
        #
        # The page URL arrives as a lambda rather than a block: Phlex intercepts
        # any block given to `.new` and routes it to `view_template`, so a
        # component constructor can never receive one.
        #
        # @example
        #   render Molecules::Pagination.new(
        #     page: 4, total_pages: 42, total_count: 1_037, per_page: 25,
        #     href: ->(n) { tracing_spans_path(page: n) }
        #   )
        #
        class Pagination < Base
          # @param page [Integer] the current page, 1-indexed
          # @param total_pages [Integer]
          # @param total_count [Integer, nil] renders the "showing N of M" line
          # @param per_page [Integer, nil] used for the summary line
          # @param href [#call] receives a page number, returns that page's URL
          def initialize(page:, total_pages:, href:, total_count: nil, per_page: nil,
                         class: nil, **attrs)
            @page = page.to_i.clamp(1, [total_pages.to_i, 1].max)
            @total_pages = [total_pages.to_i, 1].max
            @total_count = total_count
            @per_page = per_page
            @href = href
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-pagination-bar", @class), **@attrs) do
              summary
              control if @total_pages > 1
            end
          end

          private

          # "Showing 1–25 of 481", as the design words it. The range is kept
          # over the design's bare count because on page 12 "showing 25" says
          # nothing about where you are. Totals are delimited: an undelimited
          # five-figure row count is read wrong at a glance.
          def summary
            return div unless @total_count && @per_page

            first = ((@page - 1) * @per_page) + 1
            last = [@page * @per_page, @total_count].min
            p(class: "raaf-pagination-summary") do
              "Showing #{delimit(first)}–#{delimit(last)} of #{delimit(@total_count)}"
            end
          end

          def delimit(number)
            number.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
          end

          # The design's footer is prev and next, nothing else. The windowed
          # page list that used to sit between them was ours.
          def control
            nav(class: "raaf-pagination", "aria-label": "Pagination") do
              step("Previous", @page - 1, enabled: @page > 1, icon: "chevron-left")
              step("Next", @page + 1, enabled: @page < @total_pages, icon: "chevron-right")
            end
          end

          def step(label, number, enabled:, icon:)
            unless enabled
              return span(class: "raaf-pagination-item is-disabled", "aria-hidden": "true") do
                render Atoms::Icon.new(icon, size: :sm)
              end
            end

            a(href: @href.call(number), class: "raaf-pagination-item", "aria-label": label) do
              render Atoms::Icon.new(icon, size: :sm)
            end
          end
        end
      end
    end
  end
end

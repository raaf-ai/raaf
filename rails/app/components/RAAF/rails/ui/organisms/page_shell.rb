# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Organisms
        ##
        # PageShell — the console layout from Shell.dc.html.
        #
        #   .raaf-shell            238px sidebar | content
        #     .raaf-sidebar
        #     .raaf-col
        #       .raaf-header       crumb + title, time range, live, search, user
        #       .raaf-main         the screen's content
        #
        # Screens render content only; the shell owns navigation, the
        # breadcrumb, the time range and the live toggle.
        #
        class PageShell < Base
          RANGES = %w[1h 24h 7d 30d].freeze

          # @param sidebar [Phlex::HTML] an Organisms::Sidebar
          # @param title [String] the page title
          # @param crumb [String, nil] uppercase caption above the title
          # @param range [String] the selected time range
          # @param range_href [#call, nil] receives a range, returns its URL.
          #   Without it the rail is not rendered at all — a screen that does
          #   not filter by time has no use for a control it cannot act on.
          # @param live [Boolean] whether live tailing is on
          # @param search_href [String, nil] target for the search affordance
          def initialize(sidebar:, title:, crumb: nil, range: "24h", range_href: nil,
                         live: true, search_href: nil, class: nil, **attrs)
            @sidebar = sidebar
            @title = title
            @crumb = crumb
            @range = range
            @range_href = range_href
            @live = live
            @search_href = search_href
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: tokens("raaf-shell", @class), data: { controller: "app-shell" }, **@attrs) do
              render @sidebar

              div(class: "raaf-col") do
                header_bar
                main(class: "raaf-main") { yield if block }
              end
            end
          end

          private

          def header_bar
            header(class: "raaf-header") do
              nav_toggle

              div(class: "raaf-header-titles") do
                div(class: "raaf-crumb") { @crumb } if @crumb
                h1(class: "raaf-title") { @title }
              end

              range_rail if @range_href
              live_toggle
              search_affordance if @search_href
            end
          end

          def nav_toggle
            button(type: "button", class: "raaf-button raaf-button--icon raaf-nav-toggle",
                   "aria-label": "Toggle navigation",
                   data: { action: "click->app-shell#toggleNav" }) do
              render Atoms::Icon.new("list")
            end
          end

          def range_rail
            div(class: "raaf-range", role: "group", "aria-label": "Time range") do
              RANGES.each do |value|
                css = tokens("raaf-range-item", { "is-active" => value == @range })

                a(href: @range_href.call(value), class: css) { value }
              end
            end
          end

          def live_toggle
            button(type: "button",
                   class: tokens("raaf-live", { "is-live" => @live }),
                   data: { action: "click->auto-refresh#toggle", auto_refresh_target: "indicator" }) do
              plain(@live ? "Live" : "Paused")
            end
          end

          def search_affordance
            a(href: @search_href, class: "raaf-search") do
              render Atoms::Icon.new("search", size: :sm)
              span(class: "raaf-search-label") { "Search traces, spans…" }
              span(class: "raaf-search-key") { "⌘K" }
            end
          end
        end
      end
    end
  end
end

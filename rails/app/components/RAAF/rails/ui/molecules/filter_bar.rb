# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # FilterBar — a rail of filter chips plus a query field.
        #
        # Wrapped in a GET form so filtering works without JavaScript; the
        # chips are links carrying the other params forward.
        #
        # @example
        #   render Molecules::FilterBar.new(
        #     chips: [{ label: "All", active: true, href: spans_path },
        #             { label: "Errors", count: 23, href: spans_path(status: "error") }],
        #     query: params[:q], action: spans_path
        #   )
        #
        class FilterBar < Base
          # @param chips [Array<Hash>] arguments for each Atoms::Chip
          # @param query [String, nil] current query value
          # @param action [String, nil] form target; omit to drop the query field
          # @param placeholder [String]
          # @param name [String] the query parameter the field submits, so a
          #   screen whose controller reads `search` is not silently ignored
          # @param grouped [Boolean] chips share one pill container, as the
          #   Traces status filter does
          # @param outlined [Boolean] each chip carries its own border and
          #   background, as the Spans kind filters do. Independent of
          #   `grouped`: the Continuous policy filters are loose and plain.
          # @param lead [Phlex::SGML, nil] rendered before the chips — the
          #   design opens the Traces strip with its workflow filter
          # @param panel [Boolean] wrap the rail in a glass strip. The design
          #   does this on Traces and leaves the Spans kind rail bare, so it is
          #   a variant rather than the default.
          def initialize(chips: [], query: nil, action: nil, placeholder: "Search…",
                         name: "q", carry: {}, panel: false, grouped: true,
                         outlined: false, lead: nil, class: nil, **attrs)
            @chips = chips
            @query = query
            @action = action
            @placeholder = placeholder
            @name = name
            @carry = carry.compact.reject { |_, v| v.to_s.empty? }
            @panel = panel
            @lead = lead
            @grouped = grouped
            @outlined = outlined
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: tokens("raaf-filterbar", { "raaf-filterbar--panel" => @panel }, @class), **@attrs) do
              render @lead if @lead

              if @chips.any?
                div(class: tokens("raaf-chip-rail",
                                  { "raaf-chip-rail--loose" => !@grouped,
                                    "raaf-chip-rail--outlined" => @outlined })) do
                  @chips.each { |chip| render Atoms::Chip.new(**chip) }
                end
              end

              div(class: "raaf-filterbar-spacer")
              yield if block
              query_field if @action
            end
          end

          private

          def query_field
            form(action: @action, method: "get", class: "raaf-filterbar-query", role: "search") do
              render Atoms::Icon.new("search", size: :sm, tone: :muted)
              input(type: "search", name: @name, value: @query, placeholder: @placeholder,
                    "aria-label": @placeholder)

              # The chips are links, so their filters live in the URL; without
              # these the form would drop them on submit.
              @carry.each { |key, value| input(type: "hidden", name: key, value: value) }
            end
          end
        end
      end
    end
  end
end
